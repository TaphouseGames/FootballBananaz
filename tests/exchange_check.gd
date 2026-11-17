extends SceneTree
## Headless check that the person cannot walk the quarterback away from a
## handoff: with the stick held to one side and turbo down from the snap, on
## every run play the quarterback is still where the play puts him when the
## ball changes hands and the back gets it, and on every flea flicker the ball
## goes to the back and comes back to the quarterback.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/exchange_check.gd

## Yards the quarterback may be off his line when the ball changes hands.
const DRIFT: float = 0.5
const STUCK_TICKS: int = 600

var _game: Game
var _pc: PlayController
var _team: Team
var _plays: Array[OffensePlay] = []
var _index: int = -1
var _ticks: int = 0
var _start_z: float = 0.0
var _holders: Array[Player] = []
var _drift: float = 0.0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
		_team = _game.human.team
		if _team == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		for play: OffensePlay in _game.offense_playbook.plays:
			if play.is_run or play.flea_flicker:
				_plays.append(play)
		_next()
		return
	var play: OffensePlay = _plays[_index]
	_ticks += 1
	var carrier: Player = _pc.ball.carrier
	if carrier != null and (_holders.is_empty() or _holders[_holders.size() - 1] != carrier):
		_holders.append(carrier)
	# The exchange is on: the stick is held over and it must not matter.
	var exchanging: bool = (play.is_run and not _pc.handoff_done) or (play.flea_flicker and _pc.flicking())
	if exchanging:
		_drift = maxf(_drift, absf(_pc.qb.position.z - _start_z))
		return
	_release()
	var done: bool = false
	if play.is_run and _holders.has(_pc.runner):
		done = true
	elif play.flea_flicker and _holders.size() >= 3:
		done = true
	if done or _pc.ball_dead or _ticks > STUCK_TICKS:
		var came_back: bool = _holders.size() >= 3 and _holders[0] == _pc.qb and _holders[1] == _pc.runner and _holders[2] == _pc.qb
		var ok: bool = _drift <= DRIFT and (_holders.has(_pc.runner) if play.is_run else came_back)
		print("%-18s  quarterback off his line by %.2f yd, %s  %s" % [play.play_name, _drift, "back has the ball" if play.is_run else ("ball came back" if came_back else "ball did not come back"), "ok" if ok else "FAILED"])
		_expect(_drift <= DRIFT, "%s: the quarterback was walked %.1f yd off his line before the exchange" % [play.play_name, _drift])
		if play.is_run:
			_expect(_holders.has(_pc.runner), "%s: the back never got the ball" % play.play_name)
		else:
			_expect(came_back, "%s: the ball did not go to the back and come back" % play.play_name)
		if not _pc.ball_dead:
			_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
		_next()


func _next() -> void:
	_index += 1
	if _index >= _plays.size():
		_finish()
		return
	_game.start_drive(_team, _game.tuning.yard_to_x(_team.attack_dir, 30.0))
	_pc.line_up(_plays[_index], _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_start_z = _pc.qb.position.z
	_holders.clear()
	_drift = 0.0
	_ticks = 0
	# Hard to one side, alternating, with turbo.
	Input.action_press(&"move_right" if _index % 2 == 0 else &"move_left", 1.0)
	Input.action_press(&"turbo")


func _release() -> void:
	for action: StringName in [&"move_right", &"move_left", &"turbo"]:
		Input.action_release(action)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	_release()
	for failure: String in _failures:
		print("FAIL: " + failure)
	print("exchange_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message):
		_failures.append(message)
