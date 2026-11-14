extends SceneTree
## Headless smoke test: the CPU plays both teams for a whole game at high speed.
## Fails if a state gets stuck or the basic football events never happen.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd
## Optional user args after "--":
##   games=<n>   play n games (default 1)
##   set=<name>:<value>[,<name>:<value>...]   override Tuning values for this run
##   monkey      random button presses play the human team (exercises input code)
##   home=<short name>, away=<short name>   the league teams that play (e.g.
##               home=grapes away=berries); the scene's own two otherwise

const SPEED: float = 8.0
## Frames a single state may last (at SPEED x 60 fps, 600 frames = 80 game seconds).
const STUCK_FRAMES: int = 600
const MONKEY_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"turbo", &"jump", &"confirm", &"action", &"switch_player", &"pass_1", &"pass_2", &"pass_3",
	&"jump_alt", &"spin", &"stiff_arm_left", &"stiff_arm_right",
	&"pass_lead", &"pass_under", &"flip_play", &"qb_call", &"throw_away",
]

var _game: Game
var _state: StringName = &""
var _state_frames: int = 0
var _games_left: int = 1
## The person's team is driven by random button presses instead of the CPU.
var _monkey: bool = false
## "home" or "away": only that team gets the CPU edge (see Tuning.cpu_skill).
var _edge: String = ""
## Short names of the league teams to play as home and away, "" for the scene's.
var _teams: PackedStringArray = PackedStringArray(["", ""])
var _home_points: int = 0
var _away_points: int = 0
var _overrides: Dictionary[String, float] = {}
## Kickoffs looked at in this game, and how many in the run were wrong.
var _kick_seen: int = 0
var _bad_kicks: int = 0
## A fumbled ball has to travel: how often it jumped further in one frame than
## it could have rolled, and where it was (and whether it was loose) last frame.
var _loose_jumps: int = 0
var _was_loose: bool = false
var _last_ball: Vector3 = Vector3.ZERO
## Incomplete passes whistled dead with the ball still in the air.
var _early_whistles: int = 0
var _incomplete_seen: bool = false
## More than this many yards in a frame (SPEED ticks) counts as a jump.
const MAX_LOOSE_STEP: float = 5.0
var _failures: PackedStringArray = PackedStringArray()
var _totals: Dictionary[StringName, int] = {}
## Deepest any two bodies were found inside each other, in yards, and how many
## of the pairs looked at were still overlapping after contacts were resolved.
var _worst_overlap: float = 0.0
var _pairs_checked: int = 0
var _pairs_touching: int = 0
## More overlap than this between two bodies fails the run.
const MAX_OVERLAP: float = 0.25


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("games="):
			_games_left = maxi(int(arg.trim_prefix("games=")), 1)
		elif arg == "monkey":
			_monkey = true
		elif arg.begins_with("edge="):
			_edge = arg.trim_prefix("edge=")
		elif arg.begins_with("home="):
			_teams[0] = arg.trim_prefix("home=")
		elif arg.begins_with("away="):
			_teams[1] = arg.trim_prefix("away=")
		elif arg.begins_with("set="):
			for pair: String in arg.trim_prefix("set=").split(","):
				var parts: PackedStringArray = pair.split(":")
				if parts.size() == 2:
					_overrides[parts[0]] = float(parts[1])
	# Raising the time scale alone stretches every physics step to SPEED / 60 s,
	# which changes the simulation (blocks stop holding). Raising the tick rate
	# with it keeps each step at 1/60 s of game time.
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	_start_game()


func _start_game() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = not _monkey
	for key: String in _overrides:
		_game.tuning.set(key, _overrides[key])
	for i: int in 2:
		if _teams[i] != "":
			Game.team_picks[i] = _game.league.find(_teams[i])
			if Game.team_picks[i] < 0:
				_failures.append("no team called '%s' in the league" % _teams[i])
	root.add_child(_game)
	_state = &""
	_state_frames = 0
	_kick_seen = 0


func _process(_delta: float) -> bool:
	if _game == null:
		return true
	# The first game is not in the tree yet when it is made, so this waits.
	if _edge != "" and _game.play_controller != null and _game.play_controller.edge_team == null:
		_game.play_controller.edge_team = _game.home if _edge == "home" else _game.away
	var now: StringName = _game.play_controller.state_machine.current_name()
	if now != _state:
		_state = now
		_state_frames = 0
	_state_frames += 1
	if _monkey:
		_mash_buttons()
	if _state == &"Live":
		_check_overlap()
		_check_kick()
	_check_loose_ball()

	if _state == &"GameOver":
		return _finish_game()
	if _state_frames > STUCK_FRAMES:
		_failures.append("stuck in state '%s' (down %d, los %.1f, clock %.1f)" % [_state, _game.down, _game.los_x, _game.clock])
		return _report()
	return false


## A kickoff has to come down between the middle of the receiving team's end
## zone and its 20, and go to one of its two receivers.
func _check_kick() -> void:
	var pc: PlayController = _game.play_controller
	if not pc.kickoff or pc.phase != PlayController.Phase.AIR or _kick_seen == _game.get_stat(&"kickoffs"):
		return
	_kick_seen = _game.get_stat(&"kickoffs")
	var tuning: Tuning = _game.tuning
	var yard: float = (pc.ball.target_point.x - tuning.own_goal_x(pc.offense.attack_dir)) * pc.off_dir
	if yard < tuning.kickoff_land_min - 0.01 or yard > tuning.kickoff_land_max + 0.01 or pc.ball.intended != pc.returner:
		_bad_kicks += 1
	if pc.returner != pc.offense.players[4] and pc.returner != pc.offense.players[5]:
		_bad_kicks += 1


## A fumble must not put the ball straight into somebody's hands: from the frame
## it comes out to the frame after it is recovered it only moves a little at a
## time.
func _check_loose_ball() -> void:
	var pc: PlayController = _game.play_controller
	var loose: bool = _state == &"Live" and (pc.phase == PlayController.Phase.LOOSE or pc.phase == PlayController.Phase.TIPPED)
	# A pass is not incomplete before it has touched the turf.
	if pc.ball_dead and pc.result == PlayController.Result.INCOMPLETE and not _incomplete_seen:
		_incomplete_seen = true
		if not pc.ball.grounded:
			_early_whistles += 1
	elif not pc.ball_dead:
		_incomplete_seen = false
	if _was_loose and _state == &"Live" and pc.ball.position.distance_to(_last_ball) > MAX_LOOSE_STEP:
		_loose_jumps += 1
	_was_loose = loose
	_last_ball = pc.ball.position


## Two players who should be keeping each other out must never share a spot.
func _check_overlap() -> void:
	var pc: PlayController = _game.play_controller
	for i: int in pc.players.size():
		var a: Player = pc.players[i]
		for j: int in range(i + 1, pc.players.size()):
			var b: Player = pc.players[j]
			var min_dist: float = pc._body_distance(a, b)
			if min_dist <= 0.0:
				continue
			_pairs_checked += 1
			var overlap: float = min_dist - Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length()
			_worst_overlap = maxf(_worst_overlap, overlap)
			if overlap > 0.02:
				_pairs_touching += 1


## Random presses and releases on every gameplay action, as the human player.
func _mash_buttons() -> void:
	for action: StringName in MONKEY_ACTIONS:
		if randf() < 0.12:
			if Input.is_action_pressed(action):
				Input.action_release(action)
			else:
				Input.action_press(action)


func _finish_game() -> bool:
	print("game over: %s %d - %d %s   stats: %s" % [_game.home.short_name, _game.home.score, _game.away.score, _game.away.short_name, _game.stats])
	for key: StringName in _game.stats:
		var so_far: int = _totals.get(key, 0)
		_totals[key] = so_far + _game.stats[key]
	_home_points += _game.home.score
	_away_points += _game.away.score
	_games_left -= 1
	if _games_left > 0:
		_game.free()
		_start_game()
		return false
	return _report()


func _report() -> bool:
	for key: StringName in [&"snaps", &"passes", &"completions", &"tackles", &"handoffs", &"turnovers", &"drags", &"fumbles", &"kickoffs", &"kick_returns", &"halftimes", &"scramble_recoveries"]:
		var count: int = _totals.get(key, 0)
		if count <= 0 and _failures.is_empty():
			_failures.append("no '%s' happened in the whole run" % key)
	var drives: int = _totals.get(&"drives", 0)
	if drives < 2 and _failures.is_empty():
		_failures.append("possession never changed")

	# Every touchdown is followed by a try, and both halves start with a scramble.
	var tries: int = _totals.get(&"conversion_tries", 0)
	var touchdowns: int = _totals.get(&"touchdowns", 0)
	if tries != touchdowns and _failures.is_empty():
		_failures.append("%d touchdowns but %d conversion tries" % [touchdowns, tries])
	var halftimes: int = _totals.get(&"halftimes", 0)
	var scrambles: int = _totals.get(&"scrambles_started", 0)
	var do_overs: int = _totals.get(&"scramble_do_overs", 0)
	if scrambles - do_overs != 2 * halftimes and _failures.is_empty():
		_failures.append("%d scrambles (%d of them do-overs) in %d games" % [scrambles, do_overs, halftimes])
	print("scrambles: %d started, %d do-overs, %d recovered" % [scrambles, do_overs, _totals.get(&"scramble_recoveries", 0)])
	# A warning at most once a half; a play would have to run out the last
	# thirty seconds on its own for a half to go without one.
	var warnings: int = _totals.get(&"warnings", 0)
	if (warnings < halftimes or warnings > 2 * halftimes) and _failures.is_empty():
		_failures.append("%d warnings in %d games" % [warnings, halftimes])
	if _bad_kicks > 0 and _failures.is_empty():
		_failures.append("%d kickoffs came down in the wrong place or went to the wrong man" % _bad_kicks)

	if _loose_jumps > 0 and _failures.is_empty():
		_failures.append("a fumbled ball jumped instead of travelling, %d times" % _loose_jumps)
	if _early_whistles > 0 and _failures.is_empty():
		_failures.append("%d passes were called incomplete before the ball was down" % _early_whistles)
	if _totals.get(&"fumbles_whistled_dead", 0) > 0 and _failures.is_empty():
		_failures.append("%d fumbles were never recovered" % _totals.get(&"fumbles_whistled_dead", 0))

	# Rare enough that a short run may have none.
	if _totals.get(&"snaps", 0) >= 300 and _failures.is_empty():
		if _totals.get(&"overthrows", 0) <= 0:
			_failures.append("no pass was led too far in the whole run")
		elif _totals.get(&"jump_catches", 0) + _totals.get(&"dive_catches", 0) <= 0:
			_failures.append("nobody caught a pass with a jump or a dive in the whole run")
	print("bodies: worst overlap %.3f yd, %d of %d pairs still overlapping" % [_worst_overlap, _pairs_touching, _pairs_checked])
	if _worst_overlap > MAX_OVERLAP and _failures.is_empty():
		_failures.append("two players overlapped by %.2f yd" % _worst_overlap)

	print("passes called incomplete before the ball was down: %d" % _early_whistles)
	print("points: home %d, away %d (edge: %s)" % [_home_points, _away_points, _edge if _edge != "" else "both"])
	for team: Team in [_game.home, _game.away]:
		print("%s calls run x%.2f, short x%.2f, deep x%.2f" % [team.short_name, team.call_bias[0], team.call_bias[1], team.call_bias[2]])
	print("totals: %s" % _totals)
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("SMOKE TEST FAILED: %s" % failure)
		quit(1)
	return true
