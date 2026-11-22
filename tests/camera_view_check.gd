extends SceneTree
## Headless check of the second camera view (Select): the button glides the
## camera from the wide view to the close one, lower and nearer behind the ball,
## without a jump and without turning the rig (so the stick still means the same
## directions), and the next press brings it back to exactly where it was.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/camera_view_check.gd

enum Step { SETTLE, TO_CLOSE, TO_WIDE }

## Yards the camera may move in one tick of the glide.
const MAX_STEP: float = 2.0

var _game: Game
var _rig: CameraRig
var _step: Step = Step.SETTLE
var _ticks: int = 0
var _wide: Transform3D
var _basis: Basis
var _last: Vector3
var _worst: float = 0.0
var _pressed: bool = false
var _notes: PackedStringArray = []


func _initialize() -> void:
	CameraRig.view = CameraRig.View.WIDE
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _rig == null:
		_rig = _game.camera_rig
		return
	if _pressed:
		Input.action_release(&"camera_view")
		_pressed = false
	var t: Tuning = _game.tuning
	var moved: float = _rig.camera.position.distance_to(_last)
	_last = _rig.camera.position
	_ticks += 1
	match _step:
		Step.SETTLE:
			if _ticks < 20:
				return
			_wide = _rig.camera.transform
			_basis = _rig.basis
			if not _wide.origin.is_equal_approx(Vector3(0.0, t.camera_height, t.camera_distance)):
				_notes.append("wide view is not at the wide numbers")
			_press(Step.TO_CLOSE)
		Step.TO_CLOSE:
			_worst = maxf(_worst, moved)
			if not _arrived(CameraRig.View.CLOSE):
				return
			var eye: Vector3 = _rig.camera.position
			if not eye.is_equal_approx(Vector3(0.0, t.camera_close_height, t.camera_close_distance)):
				_notes.append("close view ended at %s" % eye)
			if eye.y >= _wide.origin.y or eye.z >= _wide.origin.z:
				_notes.append("close view is not lower and nearer")
			if not is_equal_approx(_rig.camera.fov, t.camera_close_fov):
				_notes.append("close view has a field of view of %.1f" % _rig.camera.fov)
			_check_glide("to close")
			_press(Step.TO_WIDE)
		Step.TO_WIDE:
			_worst = maxf(_worst, moved)
			if not _arrived(CameraRig.View.WIDE):
				return
			if not _rig.camera.transform.is_equal_approx(_wide):
				_notes.append("did not come back to the wide view")
			if not is_equal_approx(_rig.camera.fov, t.camera_fov):
				_notes.append("wide view has a field of view of %.1f" % _rig.camera.fov)
			_check_glide("to wide")
			_finish()


func _press(next: Step) -> void:
	Input.action_press(&"camera_view")
	_pressed = true
	_step = next
	_ticks = 0
	_worst = 0.0


## True once the glide is over; gives up after two seconds.
func _arrived(view: CameraRig.View) -> bool:
	if _ticks > 120:
		_notes.append("never got to view %d (the button did nothing?)" % view)
		_finish()
		return false
	return _ticks > 1 and CameraRig.view == view and _rig._blend == float(view)


func _check_glide(what: String) -> void:
	# The press is read one tick after it is made.
	var took: float = float(_ticks - 1) / 60.0
	if absf(took - _game.tuning.camera_view_time) > 0.1:
		_notes.append("%s took %.2f s" % [what, took])
	if _worst > MAX_STEP:
		_notes.append("%s jumped %.1f yd in one tick" % [what, _worst])
	if not _rig.basis.is_equal_approx(_basis):
		_notes.append("%s turned the rig" % what)
	print("%-9s %.2f s, biggest step %.2f yd" % [what, took, _worst])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	Input.action_release(&"camera_view")
	CameraRig.view = CameraRig.View.WIDE
	print("camera view check %s" % ("PASSED" if _notes.is_empty() else "FAILED: " + ", ".join(_notes)))
	quit(0 if _notes.is_empty() else 1)
