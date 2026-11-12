class_name CameraRig
extends Node3D
## Behind-the-player camera. The rig sits on the followed spot and is turned so
## the camera child ends up behind it, looking down the field. Shake is
## trauma-based and runs in real time so it still plays during hit-stop.

var tuning: Tuning
var trauma: float = 0.0
## +1 looks toward +X, -1 toward -X.
var facing: float = 1.0

var _shake_clock: float = 0.0
## Swing round to the other side: yaw at its start and end, and progress (1 = done).
var _swing_from: float = 0.0
var _swing_to: float = 0.0
var _swing_t: float = 1.0

@onready var camera: Camera3D = $Camera3D


func setup(p_tuning: Tuning) -> void:
	tuning = p_tuning
	camera.fov = tuning.camera_fov
	# In rig space the camera sits at +Z and looks toward -Z.
	var eye: Vector3 = Vector3(0.0, tuning.camera_height, tuning.camera_distance)
	var aim: Vector3 = Vector3(0.0, 0.0, -tuning.camera_look_ahead)
	camera.transform = Transform3D(Basis.looking_at(aim - eye, Vector3.UP), eye)
	camera.make_current()


func snap_to(target: Vector3, p_facing: float) -> void:
	facing = p_facing
	_swing_t = 1.0
	rotation.y = _yaw_for(facing)
	position = _goal(target)
	reset_physics_interpolation()
	camera.reset_physics_interpolation()


## Called once per physics tick. When the side changes the camera cuts to it,
## or with `swing` circles round the followed spot to get there.
func follow(target: Vector3, p_facing: float, delta: float, swing: bool = false) -> void:
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


func _process(delta: float) -> void:
	if tuning == null:
		return
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_shake_clock += real_delta
	trauma = maxf(trauma - tuning.shake_decay * real_delta, 0.0)
	var amount: float = trauma * trauma * tuning.shake_max_offset
	camera.h_offset = amount * (sin(_shake_clock * 61.3) + 0.5 * sin(_shake_clock * 113.7)) / 1.5
	camera.v_offset = amount * (sin(_shake_clock * 53.1 + 1.3) + 0.5 * sin(_shake_clock * 97.9)) / 1.5


func _goal(target: Vector3) -> Vector3:
	return Vector3(target.x, 0.0, target.z * tuning.camera_z_follow)
