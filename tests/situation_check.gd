extends SceneTree
## Headless check of the CPU's reading of score and clock. First it puts the
## game in a number of situations and counts what the play caller picks for
## each; then it plays a last-play, need-a-touchdown snap over and over and
## looks at what the quarterback does with it.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/situation_check.gd
## Optional user args after "--":
##   plays=<n>   last plays to run (default 30)

const SPEED: float = 8.0
const SAMPLES: int = 4000
const NAMES: Array[String] = ["run", "short", "deep"]

var _game: Game
var _pc: PlayController
var _failures: PackedStringArray = PackedStringArray()
var _plays_left: int = 30
var _plays_run: int = 0
var _thrown: bool = false
var _depths: PackedFloat32Array = PackedFloat32Array()
var _runs_called: int = 0
var _touchdowns: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("plays="):
			_plays_left = maxi(int(arg.trim_prefix("plays=")), 1)
	# See smoke_test.gd: the tick rate has to go up with the time scale.
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
		_check_calls()
		_start_last_play()
		return
	if not _thrown and _pc.phase == PlayController.Phase.AIR:
		_thrown = true
		_depths.append((_pc.ball.target_point.x - _pc.los_x) * _pc.off_dir)
	if _pc.ball_dead or _pc.live_time > 20.0:
		if _pc.result == PlayController.Result.TOUCHDOWN and _pc.final_team == _pc.offense:
			_touchdowns += 1
		_plays_run += 1
		if _plays_run >= _plays_left:
			_finish()
		else:
			_start_last_play()


# --- Play calls --------------------------------------------------------------

func _check_calls() -> void:
	# Early in a half with the score level: the mix down and distance gives.
	_put(2, 150.0, 0, 0, 25.0, 1, 30.0)
	var neutral: PackedFloat32Array = _offense("neutral: tied, 2:30 left, 1st & 30")
	var neutral_fit: PackedFloat32Array = _defense()
	_expect(absf(neutral[0] - 0.304) < 0.04 and absf(neutral[2] - 0.304) < 0.04, "neutral mix moved")
	_expect(not _game.play_caller.situation(_game).heave, "heave called with 2:30 left")

	_put(2, 5.0, 0, 6, 20.0, 1, 30.0)
	var last: PackedFloat32Array = _offense("down 6, 0:05 left, own 20")
	var last_fit: PackedFloat32Array = _defense()
	_expect(last[2] >= 0.999, "last play from the own 20 was not always a deep pass")
	_expect(last_fit[2] > neutral_fit[2] + 0.03, "defense did not play the deep ball on the last play")

	_put(2, 40.0, 0, 6, 20.0, 1, 30.0)
	var hurry: PackedFloat32Array = _offense("down 6, 0:40 left, own 20")
	_defense()
	_expect(hurry[0] < 0.2 and hurry[2] > 0.45, "trailing with 0:40 left did not go downfield")

	_put(2, 60.0, 0, 14, 20.0, 1, 30.0)
	var two_scores: PackedFloat32Array = _offense("down 14, 1:00 left, own 20")
	_put(2, 60.0, 0, 6, 20.0, 1, 30.0)
	var one_score: PackedFloat32Array = _offense("down 6, 1:00 left, own 20")
	_expect(two_scores[2] > one_score[2] + 0.05, "two scores down was in no more of a hurry than one")

	_put(2, 30.0, 10, 6, 40.0, 1, 30.0)
	var kill: PackedFloat32Array = _offense("up 4, 0:30 left, 1st & 30")
	var kill_fit: PackedFloat32Array = _defense()
	_expect(kill[0] > 0.5, "leading with 0:30 left did not run the clock")
	_expect(kill_fit[0] > neutral_fit[0] + 0.03, "defense did not play the run against a team killing the clock")

	_put(2, 30.0, 10, 6, 40.0, 4, 25.0)
	var fourth: PackedFloat32Array = _offense("up 4, 0:30 left, 4th & 25")
	_expect(fourth[1] + fourth[2] > 0.6, "leading on 4th and long did not throw for it")

	_put(2, 150.0, 10, 6, 40.0, 1, 30.0)
	var early_lead: PackedFloat32Array = _offense("up 4, 2:30 left, 1st & 30")
	_expect(absf(early_lead[0] - neutral[0]) < 0.04, "leading with 2:30 left already ran the clock")

	_put(1, 8.0, 0, 0, 50.0, 1, 30.0)
	var half: PackedFloat32Array = _offense("tied, 0:08 left in the first half, midfield")
	_defense()
	_expect(half[2] > 0.6, "end of the first half was not treated as a deadline")

	_put(1, 8.0, 6, 0, 50.0, 1, 30.0)
	var half_lead: PackedFloat32Array = _offense("up 6, 0:08 left in the first half, midfield")
	_expect(half_lead[2] > neutral[2] and half_lead[2] < half[2], "leading before the half: expected some hurry, less than when tied")

	_put(2, 4.0, 0, 6, 95.0, 1, 0.0)
	_offense("down 6, 0:04 left, opp 5")
	_expect(not _game.play_caller.situation(_game).heave, "heave called from the 5")

	# Goal line plays are for the goal line, on both sides of the ball.
	_put(2, 150.0, 0, 0, 50.0, 1, 30.0)
	var far: PackedFloat32Array = _goal_line_shares()
	_put(2, 150.0, 0, 0, 96.0, 1, 0.0)
	var near: PackedFloat32Array = _goal_line_shares()
	print("goal line plays called at midfield: offense %.0f%% defense %.0f%%; at the 4: offense %.0f%% defense %.0f%%" % [far[0] * 100.0, far[1] * 100.0, near[0] * 100.0, near[1] * 100.0])
	_expect(far[0] < 0.03 and far[1] < 0.03, "goal line plays called at midfield")
	_expect(near[0] > 0.4 and near[1] > 0.4, "goal line plays not called at the goal line")

	# The try is untimed: the clock must not change it.
	_put(2, 150.0, 6, 6, 50.0, 1, 30.0)
	_game.start_conversion(_game.home)
	var try_early: PackedFloat32Array = _offense("2-point try, 2:30 left")
	_game.clock = 0.0
	_game.away.score = 14
	var try_late: PackedFloat32Array = _offense("2-point try, 0:00 left, down 8")
	_game.conversion = false
	for i: int in 3:
		_expect(absf(try_early[i] - try_late[i]) < 0.04, "the clock changed the call on a try (%s)" % NAMES[i])


## Home has the ball on its own `yard` line, `off_score` to `def_score`.
## `to_go` of 0 leaves the marker where the drive puts it.
func _put(half: int, clock: float, off_score: int, def_score: int, yard: float, down: int, to_go: float) -> void:
	var team: Team = _game.home
	_game.conversion = false
	_game.half = half
	_game.clock = clock
	_game.start_drive(team, _game.tuning.yard_to_x(team.attack_dir, yard))
	team.score = off_score
	team.opponent.score = def_score
	_game.down = down
	if to_go > 0.0:
		_game.goal_to_go = false
		_game.first_down_x = _game.los_x + float(team.attack_dir) * to_go


## Shares of run, short and deep calls in this situation.
func _offense(label: String) -> PackedFloat32Array:
	var shares: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	for i: int in SAMPLES:
		var play: OffensePlay = _game.play_caller.pick_offense(_game.offense_playbook.plays, _game)
		shares[play.category] += 1.0 / float(SAMPLES)
	var now: GameSituation = _game.play_caller.situation(_game)
	print("%-48s run %3.0f%%  short %3.0f%%  deep %3.0f%%   urgency %.2f  kill %.2f  heave %s" % [label, shares[0] * 100.0, shares[1] * 100.0, shares[2] * 100.0, now.urgency, now.clock_kill, now.heave])
	return shares


## Share of the calls in this situation that are goal line plays: offense, defense.
func _goal_line_shares() -> PackedFloat32Array:
	var shares: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
	for i: int in SAMPLES:
		if _game.play_caller.pick_offense(_game.offense_playbook.plays, _game).goal_line:
			shares[0] += 1.0 / float(SAMPLES)
		if _game.play_caller.pick_defense(_game.defense_playbook.plays, _game).goal_line:
			shares[1] += 1.0 / float(SAMPLES)
	return shares


## Average run, short and deep fit of the defenses called in this situation.
func _defense() -> PackedFloat32Array:
	var fit: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	var counts: Dictionary[String, int] = {}
	for i: int in SAMPLES:
		var play: DefensePlay = _game.play_caller.pick_defense(_game.defense_playbook.plays, _game)
		var so_far: int = counts.get(play.play_name, 0)
		counts[play.play_name] = so_far + 1
		for c: int in 3:
			fit[c] += play.fit(c as OffensePlay.Category) / float(SAMPLES)
	var names: Array[String] = []
	names.assign(counts.keys())
	names.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	var top: PackedStringArray = PackedStringArray()
	for i: int in mini(3, names.size()):
		top.append("%s %d%%" % [names[i], roundi(100.0 * float(counts[names[i]]) / float(SAMPLES))])
	print("    defense: %s   (fit run %.2f short %.2f deep %.2f)" % [", ".join(top), fit[0], fit[1], fit[2]])
	return fit


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


# --- The last play -----------------------------------------------------------

func _start_last_play() -> void:
	# Little enough that it stays the last play however long the plays before
	# it turned out to take.
	_put(2, 2.0, 0, 6, 20.0, 1, 30.0)
	var play: OffensePlay = _game.play_caller.pick_offense(_game.offense_playbook.plays, _game)
	if play.is_run:
		_runs_called += 1
	_pc.line_up(play, _game.play_caller.pick_defense(_game.defense_playbook.plays, _game), randf() < 0.5)
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_thrown = false


func _finish() -> void:
	physics_frame.disconnect(_tick)
	var heaves: int = _game.get_stat(&"heaves")
	var total: float = 0.0
	var shortest: float = INF
	for depth: float in _depths:
		total += depth
		shortest = minf(shortest, depth)
	var mean: float = total / maxf(float(_depths.size()), 1.0)
	print("last plays: %d run, %d passes thrown (%d heaves), aimed %.1f yd downfield on average (shortest %.1f), %d touchdowns, %d scrambles" % [_plays_run, _depths.size(), heaves, mean, shortest if _depths.size() > 0 else 0.0, _touchdowns, _game.get_stat(&"scrambles")])
	_expect(_runs_called == 0, "%d run plays called on the last play" % _runs_called)
	_expect(float(_depths.size()) >= 0.8 * float(_plays_run), "the quarterback threw on only %d of %d last plays" % [_depths.size(), _plays_run])
	_expect(heaves >= _depths.size() and heaves > 0, "passes on the last play were not heaves")
	_expect(mean >= 25.0, "heaves were aimed only %.1f yd downfield on average" % mean)
	_expect(_game.get_stat(&"scrambles") == 0, "the quarterback ran on the last play")
	if _failures.is_empty():
		print("SITUATION CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("SITUATION CHECK FAILED: %s" % failure)
		quit(1)
