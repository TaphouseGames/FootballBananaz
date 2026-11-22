extends SceneTree
## Headless check of the camera backing away for the person's quarterback: with
## him rolled out to one side and his receivers spread across the field, the
## camera goes back, slowly, until every one of them is in the picture, in both
## views, and comes back in once the ball has left his hands.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/camera_fit_check.gd

const CASE_NAMES: Array[String] = ["close view, rolled to -z", "close view, rolled to +z", "wide view, rolled to -z"]
## Ticks to get there, and to come most of the way back.
const SETTLE: int = 240
const BACK: int = 75
## Share of the way it may have gone after a quarter of a second.
const SLOW: float = 0.5

var _game: Game
var _pc: PlayController
var _rig: CameraRig
var _team: Team
var _case: int = -1
var _ticks: int = 0
var _out_at_start: int = 0
var _early: float = 0.0
var _reached: float = 0.0
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
		_rig = _game.camera_rig
		_team = _game.human.team
		if _team == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_next()
		return
	_ticks += 1
	if _ticks <= SETTLE and (_pc.ball_dead or _pc.ball.carrier != _pc.qb):
		_fail("the quarterback lost the ball at tick %d" % _ticks)
		_next()
		return
	if _ticks == 2:
		_out_at_start = _out_of_picture()
		_expect(_out_at_start > 0, "every receiver was in the picture to begin with, so nothing is checked")
	elif _ticks == 15:
		_early = _rig._pull.length()
	elif _ticks == SETTLE:
		_reached = _rig._pull.length()
		_expect(_reached > 1.0, "the camera did not move")
		_expect(_early < _reached * SLOW, "it had gone %.1f of %.1f yd after a quarter of a second" % [_early, _reached])
		_expect(_out_of_picture() == 0, "%d of %d receivers are out of the picture" % [_out_of_picture(), _pc.eligible.size()])
		_expect(_rig.camera.is_position_in_frustum(_pc.qb.position + Vector3.UP), "the quarterback is out of the picture")
		print("%-26s %d of %d out at first, went %.1f yd back and %.1f yd aside" % [CASE_NAMES[_case], _out_at_start, _pc.eligible.size(), _rig._pull.y, _rig._pull.x])
		_pc.throw_away(1.0)
	elif _ticks == SETTLE + 6:
		_expect(_pc.phase == PlayController.Phase.AIR or _pc.ball_dead, "the ball was not thrown")
		_expect(_rig._pull_goal == Vector2.ZERO, "the camera is not asked back after the throw")
	elif _ticks == SETTLE + BACK:
		# Before the next down lines up, when it backs away again.
		_expect(_rig._pull.length() < _reached * 0.25, "still %.1f of %.1f yd off after the throw" % [_rig._pull.length(), _reached])
		_next()


## Receivers whose chest is off the screen.
func _out_of_picture() -> int:
	var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var out: int = 0
	for receiver: Player in _pc.eligible:
		var spot: Vector3 = receiver.position + Vector3.UP
		if _rig.camera.is_position_behind(spot) or not screen.has_point(_rig.camera.unproject_position(spot)):
			out += 1
	return out


func _next() -> void:
	_case += 1
	if _case >= CASE_NAMES.size():
		_finish()
		return
	CameraRig.view = CameraRig.View.WIDE if _case == 2 else CameraRig.View.CLOSE
	var side: float = 1.0 if _case == 1 else -1.0
	var tuning: Tuning = _game.tuning
	var dir: float = float(_team.attack_dir)
	_game.start_drive(_team, tuning.yard_to_x(_team.attack_dir, 30.0))
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if not candidate.is_run and not candidate.play_action:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")

	# Everybody else out of the way, the receivers spread from sideline to
	# sideline at different depths, and the quarterback rolled out to one side.
	var half: float = tuning.half_width()
	for player: Player in _pc.players:
		if player != _pc.qb:
			player.position = Vector3(tuning.field_length * 0.5 - dir * 40.0, 0.0, float(player.index) * 2.0 - 8.0)
			player.frozen = true
		player.velocity = Vector3.ZERO
	var count: int = _pc.eligible.size()
	for i: int in count:
		var across: float = lerpf(-1.0, 1.0, float(i) / maxf(float(count - 1), 1.0))
		_pc.eligible[i].position = Vector3(_pc.los_x + dir * (3.0 + 5.0 * float(i)), 0.0, across * (half - 3.0))
	_pc.qb.position = Vector3(_pc.los_x - dir * 7.0, 0.0, side * (half - 6.0))
	_game.snap_camera()
	_ticks = 0


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	_failures.append("%s: %s" % [CASE_NAMES[_case], what])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("CAMERA FIT CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("CAMERA FIT CHECK FAILED: %s" % failure)
		quit(1)
