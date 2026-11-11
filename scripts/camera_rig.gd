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
	rotation.y = -PI * 0.5 * facing
	position = _goal(target)
	reset_physics_interpolation()
	camera.reset_physics_interpolation()


## Called once per physics tick.
func follow(target: Vector3, p_facing: float, delta: float) -> void:
	if p_facing != facing:
		snap_to(target, p_facing)
		return
	position = position.lerp(_goal(target), 1.0 - exp(-tuning.camera_follow_speed * delta))


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
