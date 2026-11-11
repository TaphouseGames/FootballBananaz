class_name CameraRig
extends Node3D
## Sideline camera. The rig slides along the field after the ball; the camera
## child keeps a fixed angle. Shake is trauma-based and runs in real time so it
## still plays during hit-stop.

var tuning: Tuning
var trauma: float = 0.0

var _shake_clock: float = 0.0

@onready var camera: Camera3D = $Camera3D


func setup(p_tuning: Tuning) -> void:
	tuning = p_tuning
	camera.fov = tuning.camera_fov
	camera.position = Vector3(0.0, tuning.camera_height, tuning.camera_distance)
	camera.look_at(global_position + Vector3(0.0, 0.0, 2.0), Vector3.UP)
	camera.make_current()


func snap_to(target: Vector3) -> void:
	position = _goal(target)
	reset_physics_interpolation()
	camera.reset_physics_interpolation()


## Called once per physics tick.
func follow(target: Vector3, delta: float) -> void:
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
	var x: float = clampf(target.x, 8.0, tuning.field_length - 8.0)
	return Vector3(x, 0.0, target.z * tuning.camera_z_follow)
