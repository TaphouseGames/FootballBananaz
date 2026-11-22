class_name CameraRig
extends Node3D
## Behind-the-player camera. The rig sits on the followed spot and is turned so
## the camera child ends up behind it, looking down the field, in one of two
## views (see View). Shake is
## trauma-based and runs in real time so it still plays during hit-stop.

## The two views Select switches between: high and far back, or low and near
## behind the ball carrier. The game starts in the close one; the choice is
## kept from one game to the next.
enum View { WIDE, CLOSE }
static var view: View = View.CLOSE

var tuning: Tuning
var trauma: float = 0.0
## +1 looks toward +X, -1 toward -X.
var facing: float = 1.0

var _shake_clock: float = 0.0
## A push in (see punch): degrees asked for, falling away at PUNCH_DECAY a
## second, and the eased value taken off the field of view.
const PUNCH_DECAY: float = 14.0
var _punch: float = 0.0
var _punch_now: float = 0.0
## Swing round to the other side: yaw at its start and end, and progress (1 = done).
var _swing_from: float = 0.0
var _swing_to: float = 0.0
var _swing_t: float = 1.0
## The camera's place on the rig, and the shot it has been taken off it for.
var _home: Transform3D
var _shot: bool = false
var _shot_eye: Vector3
var _shot_aim: Vector3
## How far the camera is into the close view (0 = wide, 1 = close), and the
## field of view and sideways follow that go with it.
var _blend: float = 0.0
var _fov: float = 50.0
var _z_follow: float = 1.0

@onready var camera: Camera3D = $Camera3D


func setup(p_tuning: Tuning) -> void:
	tuning = p_tuning
	_set_blend(float(view))
	camera.fov = _fov
	camera.make_current()


## Switches to the other view; the camera glides there (see follow).
func toggle_view() -> void:
	view = View.CLOSE if view == View.WIDE else View.WIDE


## Puts the camera's place on the rig, its field of view and its sideways
## follow this far between the wide view (0) and the close one (1).
func _set_blend(value: float) -> void:
	_blend = value
	var t: float = smoothstep(0.0, 1.0, _blend)
	# In rig space the camera sits at +Z and looks toward -Z.
	var eye: Vector3 = Vector3(0.0, lerpf(tuning.camera_height, tuning.camera_close_height, t), lerpf(tuning.camera_distance, tuning.camera_close_distance, t))
	var aim: Vector3 = Vector3(0.0, 0.0, -lerpf(tuning.camera_look_ahead, tuning.camera_close_look_ahead, t))
	_home = Transform3D(Basis.looking_at(aim - eye, Vector3.UP), eye)
	_fov = lerpf(tuning.camera_fov, tuning.camera_close_fov, t)
	_z_follow = lerpf(tuning.camera_z_follow, tuning.camera_close_z_follow, t)
	if not _shot:
		camera.transform = _home


## A shot of its own (the pregame intro): the camera stands at `eye` in the
## world and looks at `aim`, wherever the rig is, until end_shot(). Call it
## every physics tick to move it; `cut` jumps there without gliding.
func shot(eye: Vector3, aim: Vector3, cut: bool = false) -> void:
	_shot = true
	_shot_eye = eye
	_shot_aim = aim
	camera.look_at_from_position(eye, aim)
	if cut:
		camera.reset_physics_interpolation()


## Back onto the rig, behind the play.
func end_shot() -> void:
	if not _shot:
		return
	_shot = false
	_set_blend(float(view))
	camera.reset_physics_interpolation()


func snap_to(target: Vector3, p_facing: float) -> void:
	facing = p_facing
	_swing_t = 1.0
	_set_blend(float(view))
	rotation.y = _yaw_for(facing)
	position = _goal(target)
	if _shot:
		# Moving the rig took the camera with it.
		camera.look_at_from_position(_shot_eye, _shot_aim)
	reset_physics_interpolation()
	camera.reset_physics_interpolation()


## Called once per physics tick. When the side changes the camera cuts to it,
## or with `swing` circles round the followed spot to get there.
func follow(target: Vector3, p_facing: float, delta: float, swing: bool = false) -> void:
	if _shot:
		return
	if _blend != float(view):
		_set_blend(move_toward(_blend, float(view), delta / maxf(tuning.camera_view_time, 0.01)))
	if p_facing != facing:
		if not swing:
			snap_to(target, p_facing)
			return
		_start_swing(target, p_facing)
	if _swing_t < 1.0:
		_swing_t = minf(_swing_t + delta / maxf(tuning.camera_swing_time, 0.01), 1.0)
		if _swing_t >= 1.0:
			rotation.y = _yaw_for(facing)
		else:
			rotation.y = lerpf(_swing_from, _swing_to, smoothstep(0.0, 1.0, _swing_t))
	position = position.lerp(_goal(target), 1.0 - exp(-tuning.camera_follow_speed * delta))


func is_swinging() -> bool:
	return _swing_t < 1.0


func _start_swing(target: Vector3, p_facing: float) -> void:
	var old_facing: float = facing
	facing = p_facing
	_swing_from = rotation.y
	var turn: float = angle_difference(_swing_from, _yaw_for(facing))
	if absf(turn) > PI - 0.05:
		# A full half circle: go round by the sideline nearer the ball, so the
		# camera looks in across the field on its way and not out over the edge.
		turn = PI * old_facing * (1.0 if target.z >= 0.0 else -1.0)
	_swing_to = _swing_from + turn
	_swing_t = 0.0


func _yaw_for(p_facing: float) -> float:
	return -PI * 0.5 * p_facing


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


## A quick push in: the view narrows by `degrees` at once and eases back out.
func punch(degrees: float) -> void:
	_punch = maxf(_punch, degrees)


func _process(delta: float) -> void:
	if tuning == null:
		return
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_shake_clock += real_delta
	trauma = maxf(trauma - tuning.shake_decay * real_delta, 0.0)
	var amount: float = trauma * trauma * tuning.shake_max_offset
	camera.h_offset = amount * (sin(_shake_clock * 61.3) + 0.5 * sin(_shake_clock * 113.7)) / 1.5
	camera.v_offset = amount * (sin(_shake_clock * 53.1 + 1.3) + 0.5 * sin(_shake_clock * 97.9)) / 1.5
	if _punch > 0.0 or _punch_now > 0.001:
		_punch_now = lerpf(_punch_now, _punch, 1.0 - exp(-30.0 * real_delta))
		_punch = maxf(_punch - PUNCH_DECAY * real_delta, 0.0)
	# A shot of its own keeps the wide view's lens.
	camera.fov = (tuning.camera_fov if _shot else _fov) - _punch_now


func _goal(target: Vector3) -> Vector3:
	return Vector3(target.x, 0.0, target.z * _z_follow)
