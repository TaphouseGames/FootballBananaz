extends SceneTree
## Check of the scramble that opens a half: the ball goes up from midfield, the
## two mascots run in, and one comes out of it with the ball. Plays one scramble
## after another (CPU against CPU) and prints how they went: when the first one
## got to where it came down against when it landed, how long until somebody had
## it, how many were on the turf by then, and who won.
## Fails if anybody but the two mascots is out there or they are not rated 50 in
## everything, if nobody may touch it before it lands does not hold, if too many
## end with nobody having it, or if one team wins nearly all of them.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/scramble_check.gd -- scrambles=N [set=name:value,...]

const SPEED: float = 8.0
## A first man this many yards from the landing spot is there.
const ARRIVED: float = 2.0

var _game: Game
var _left: int = 40
var _overrides: Dictionary[String, float] = {}
var _failures: PackedStringArray = PackedStringArray()

var _running: bool = false
var _time: float = 0.0
var _landed_at: float = -1.0
var _arrived_at: float = -1.0
var _spot: Vector3 = Vector3.ZERO

var _played: int = 0
var _do_overs: int = 0
var _early: int = 0
var _wins: Dictionary[String, int] = {}
var _sum_landed: float = 0.0
var _sum_arrived: float = 0.0
var _sum_recovered: float = 0.0
var _longest: float = 0.0
var _sum_down: int = 0
var _touchdowns: int = 0
var _field_failure: String = ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("scrambles="):
			_left = maxi(int(arg.trim_prefix("scrambles=")), 1)
		elif arg.begins_with("set="):
			for pair: String in arg.trim_prefix("set=").split(","):
				var parts: PackedStringArray = pair.split(":")
				if parts.size() == 2:
					_overrides[parts[0]] = float(parts[1])
	# The tick rate goes up with the time scale: each step stays 1/60 s.
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	for key: String in _overrides:
		_game.tuning.set(key, _overrides[key])
	root.add_child(_game)


func _physics_process(delta: float) -> bool:
	if _game == null or _game.play_controller == null:
		return false
	var pc: PlayController = _game.play_controller
	var state: StringName = pc.state_machine.current_name()
	if not _running:
		if state == &"Live" and pc.scramble:
			_running = true
			_time = 0.0
			_landed_at = -1.0
			_arrived_at = -1.0
			_spot = pc.ball.target_point
			_check_field(pc)
		elif state != &"Scramble" and state != &"Live":
			# Whatever came of the last one, the next goes up.
			_game.scramble_due = true
			_game.kickoff_to = null
			_game.conversion = false
			_game.clock = _game.tuning.game_length * 0.5
			pc.state_machine.transition(&"Scramble")
		return false

	# A step is 1/60 s of game time whatever the speed (see _initialize).
	_time += delta
	if _landed_at < 0.0 and pc.ball.grounded:
		_landed_at = _time
	if _arrived_at < 0.0:
		for player: Player in pc.players:
			if Vector2(player.position.x - _spot.x, player.position.z - _spot.z).length() <= ARRIVED:
				_arrived_at = _time
				break
	if pc.scramble_team != null:
		_note_recovery(pc)
	elif pc.ball_dead:
		_do_overs += 1
		_finish()
	return _left <= 0 and _report()


## Only the two mascots are out there, one a side, and neither is the better.
func _check_field(pc: PlayController) -> void:
	if not _field_failure.is_empty():
		return
	if pc.players.size() != 2 or not (pc.players[0] is Mascot) or not (pc.players[1] is Mascot):
		_field_failure = "%d players in the scramble, not the two mascots" % pc.players.size()
	elif pc.players[0].team == pc.players[1].team:
		_field_failure = "both mascots are on the same team"
	else:
		for rating: StringName in PlayerRatings.CARD_ORDER:
			if pc.players[0].ratings.get(rating) != 50 or pc.players[1].ratings.get(rating) != 50:
				_field_failure = "a mascot's %s is not 50" % rating
	for team: Team in [_game.home, _game.away]:
		for player: Player in team.squad:
			if player.visible:
				_field_failure = "a footballer is on the field during the scramble"
	if not _field_failure.is_empty():
		_failures.append(_field_failure)


func _note_recovery(pc: PlayController) -> void:
	if _landed_at < 0.0:
		_early += 1
		_landed_at = _time
	var down: int = 0
	for player: Player in pc.players:
		if player.is_down():
			down += 1
	var winner: String = pc.scramble_team.short_name
	var so_far: int = _wins.get(winner, 0)
	_wins[winner] = so_far + 1
	_sum_landed += _landed_at
	_sum_arrived += _arrived_at if _arrived_at >= 0.0 else _time
	_sum_recovered += _time
	_longest = maxf(_longest, _time)
	_sum_down += down
	_played += 1
	_finish()


func _finish() -> void:
	_running = false
	_left -= 1
	if _game.get_stat(&"touchdowns") > _touchdowns:
		_touchdowns = _game.get_stat(&"touchdowns")
	# On to the next: the run that follows is the smoke test's business.
	var pc: PlayController = _game.play_controller
	_game.scramble_due = true
	_game.kickoff_to = null
	_game.conversion = false
	pc.ball_dead = true
	pc.state_machine.transition(&"Scramble")


func _report() -> bool:
	var n: float = float(maxi(_played, 1))
	print("Scrambles: %d won, %d do-overs.  Winners: %s" % [_played, _do_overs, str(_wins)])
	print("First man at the spot %.2f s, ball down %.2f s, somebody has it %.2f s (longest %.2f s) after it went up." % [_sum_arrived / n, _sum_landed / n, _sum_recovered / n, _longest])
	print("On the turf when it was won: %.1f of %d players." % [float(_sum_down) / n, _game.play_controller.players.size()])
	if _played == 0:
		_failures.append("nobody ever came up with the ball")
	if _early > 0:
		_failures.append("the ball was taken out of the air %d times" % _early)
	if _do_overs * 4 > _played + _do_overs:
		_failures.append("%d of %d scrambles ended with nobody having the ball" % [_do_overs, _played + _do_overs])
	for team: String in _wins:
		if _played >= 20 and _wins[team] * 5 > _played * 4:
			_failures.append("%s won %d of %d" % [team, _wins[team], _played])
	if _failures.is_empty():
		print("SCRAMBLE CHECK PASSED")
	else:
		for failure: String in _failures:
			print("SCRAMBLE CHECK FAILED: %s" % failure)
	quit(0 if _failures.is_empty() else 1)
	return true
