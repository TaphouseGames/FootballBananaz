extends SceneTree
## Headless check of sudden death. A CPU game is put level with a second left
## in the second half: it has to go to the Overtime state, open that with a
## scramble, show "OT" for a clock, and end on the first score, a touchdown
## without its try, with the scores no longer level.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/overtime_check.gd

const SPEED: float = 8.0
const STUCK_FRAMES: int = 40000

var _game: Game
var _frames: int = 0
var _state: StringName = &""
var _forced: bool = false
## The states gone through since the game was put level.
var _seen: Array[StringName] = []
var _tries_at_overtime: int = -1
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready():
		return false
	_frames += 1
	if _frames > STUCK_FRAMES:
		_failures.append("the game did not end (state '%s', seen %s)" % [_state, _seen])
		return _finish()
	var now: StringName = _game.play_controller.state_machine.current_name()
	if now == _state:
		return false
	_state = now
	if not _forced:
		# The first line-up from scrimmage: level, and the half all but over.
		if now == &"PreSnap" and not _game.play_controller.kickoff and not _game.conversion:
			_forced = true
			_game.half = 2
			_game.warning_half = 2
			_game.clock = 0.5
			_game.home.score = 8
			_game.away.score = 8
		return false
	_seen.append(now)
	match now:
		&"Overtime":
			_tries_at_overtime = _game.get_stat(&"conversion_tries")
			_expect(_game.overtime, "Game.overtime is not set in the Overtime state")
			_expect(_game.clock_text() == "OT", "the clock reads '%s', not 'OT'" % _game.clock_text())
		&"Halftime", &"Warning":
			_failures.append("a %s came up after the end of the second half" % now)
		&"GameOver":
			return _finish()
	return false


func _finish() -> bool:
	var overtime_at: int = _seen.find(&"Overtime")
	_expect(overtime_at >= 0, "the level game did not go to overtime (%s)" % [_seen])
	if overtime_at >= 0:
		_expect(_seen.size() > overtime_at + 1 and _seen[overtime_at + 1] == &"Scramble", "overtime did not open with a scramble")
		_expect(_seen.back() == &"GameOver", "the game did not end")
		_expect(not _game.is_tied(), "the game ended level, %d - %d" % [_game.home.score, _game.away.score])
		_expect(_game.get_stat(&"conversion_tries") == _tries_at_overtime, "a try was played in sudden death")
		_expect(is_zero_approx(_game.clock), "the clock ran in overtime")
		var margin: int = absi(_game.home.score - _game.away.score)
		_expect(margin == _game.tuning.touchdown_points or margin == _game.tuning.safety_points, "sudden death was won by %d points" % margin)
	print("overtime: %s, final %d - %d" % [_seen, _game.home.score, _game.away.score])
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("overtime check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
	return true


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
