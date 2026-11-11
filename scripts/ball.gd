class_name Ball
extends Node3D
## The football: carried, flying on a ballistic arc, or loose on the turf.

enum State { HELD, FLIGHT, LOOSE }

## Nose-to-nose length in metres (a real ball is 0.28; this reads better from the
## game camera). The model is 1 unit long and about 0.6 wide.
const BALL_LENGTH: float = 0.4
const GROUND_HEIGHT: float = 0.12
const LEATHER_SHADER: Shader = preload("res://assets/ball/ball_leather.gdshader")
## Radians per second around the long axis on a thrown spiral.
const SPIRAL_SPIN: float = 26.0
const TUMBLE_SPIN: float = 14.0

var state: State = State.LOOSE
var carrier: Player
var thrower: Player
var intended: Player
## Where a pass in flight comes down (y = 0).
var target_point: Vector3 = Vector3.ZERO
var flight_time: float = 0.0
var flight_elapsed: float = 0.0

var _flight_start: Vector3 = Vector3.ZERO
var _flight_velocity: Vector3 = Vector3.ZERO
var _flight_vy: float = 0.0
var _gravity: float = 20.0
var _loose_velocity: Vector3 = Vector3.ZERO

var _spin: float = 0.0

@onready var landing_marker: MeshInstance3D = $LandingMarker
@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model


func _ready() -> void:
	model.scale = Vector3.ONE * BALL_LENGTH
	var grain: FastNoiseLite = FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_CELLULAR
	grain.frequency = 0.09
	grain.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var grain_tex: NoiseTexture2D = NoiseTexture2D.new()
	grain_tex.noise = grain
	grain_tex.seamless = true
	grain_tex.as_normal_map = true
	grain_tex.bump_strength = 6.0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var source: BaseMaterial3D = mesh_instance.get_active_material(0) as BaseMaterial3D
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = LEATHER_SHADER
		material.set_shader_parameter(&"grain_normal", grain_tex)
		if source != null:
			material.set_shader_parameter(&"albedo_tex", source.albedo_texture)
		mesh_instance.material_override = material


## Time until something moving at `speed` from `from` can meet a target moving at
## a constant velocity. Used for both pass leading and pursuit angles.
static func intercept_time(from: Vector3, target: Vector3, target_velocity: Vector3, speed: float) -> float:
	var to_target: Vector3 = target - from
	to_target.y = 0.0
	var vel: Vector3 = target_velocity
	vel.y = 0.0
	var fallback: float = to_target.length() / maxf(speed, 0.01)
	var a: float = vel.length_squared() - speed * speed
	var b: float = 2.0 * to_target.dot(vel)
	var c: float = to_target.length_squared()
	if absf(a) < 0.0001:
		if b >= -0.0001:
			return fallback
		return -c / b
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0:
		return fallback
	var root: float = sqrt(disc)
	var t1: float = (-b - root) / (2.0 * a)
	var t2: float = (-b + root) / (2.0 * a)
	var best: float = -1.0
	if t1 > 0.0:
		best = t1
	if t2 > 0.0 and (best < 0.0 or t2 < best):
		best = t2
	return best if best > 0.0 else fallback


func give_to(player: Player) -> void:
	_release()
	carrier = player
	carrier.has_ball = true
	state = State.HELD
	landing_marker.visible = false
	_follow_carrier()


func place_on_ground(spot: Vector3) -> void:
	_release()
	state = State.LOOSE
	_loose_velocity = Vector3.ZERO
	landing_marker.visible = false
	position = Vector3(spot.x, GROUND_HEIGHT, spot.z)
	visual.basis = Basis.IDENTITY
	reset_physics_interpolation()


## `speed` is the flat speed; gravity is fixed, so a slower pass arcs higher.
func throw_to(p_thrower: Player, p_intended: Player, point: Vector3, speed: float, tuning: Tuning) -> void:
	_release()
	thrower = p_thrower
	intended = p_intended
	state = State.FLIGHT
	_gravity = tuning.pass_gravity
	_flight_start = p_thrower.position + Vector3(0.0, tuning.pass_release_height + p_thrower.air_height(), 0.0)
	target_point = Vector3(point.x, 0.0, point.z)
	var flat: Vector3 = target_point - _flight_start
	flat.y = 0.0
	flight_time = maxf(flat.length() / speed, 0.2)
	flight_elapsed = 0.0
	_flight_velocity = flat / flight_time
	_flight_vy = (tuning.pass_catch_height - _flight_start.y + 0.5 * _gravity * flight_time * flight_time) / flight_time
	position = _flight_start
	landing_marker.visible = true
	landing_marker.global_position = target_point + Vector3(0.0, 0.06, 0.0)
	landing_marker.reset_physics_interpolation()


## Incomplete pass: the ball falls to the turf.
func drop() -> void:
	_release()
	state = State.LOOSE
	_loose_velocity = _flight_velocity * 0.35 + Vector3(0.0, 3.0, 0.0)
	landing_marker.visible = false


## Returns true on the tick a pass reaches its target point.
func integrate(delta: float) -> bool:
	_update_visual(delta)
	match state:
		State.HELD:
			_follow_carrier()
		State.FLIGHT:
			flight_elapsed += delta
			var t: float = minf(flight_elapsed, flight_time)
			var pos: Vector3 = _flight_start + _flight_velocity * t
			pos.y = _flight_start.y + _flight_vy * t - 0.5 * _gravity * t * t
			position = pos
			if flight_elapsed >= flight_time:
				return true
		State.LOOSE:
			_loose_velocity.y -= _gravity * delta
			position += _loose_velocity * delta
			if position.y <= GROUND_HEIGHT:
				position.y = GROUND_HEIGHT
				_loose_velocity.y = -_loose_velocity.y * 0.4
				_loose_velocity.x *= 0.6
				_loose_velocity.z *= 0.6
				if absf(_loose_velocity.y) < 1.0:
					_loose_velocity = Vector3.ZERO
	return false


func flat_position() -> Vector3:
	return Vector3(position.x, 0.0, position.z)


func _release() -> void:
	if carrier != null:
		carrier.has_ball = false
	carrier = null


## Turns the model only; the ball's position is not affected.
func _update_visual(delta: float) -> void:
	match state:
		State.FLIGHT:
			# A spiral: nose along the arc, spinning around the long axis.
			var t: float = minf(flight_elapsed, flight_time)
			var vel: Vector3 = _flight_velocity + Vector3(0.0, _flight_vy - _gravity * t, 0.0)
			if vel.length_squared() < 0.0001:
				return
			_spin = fmod(_spin + SPIRAL_SPIN * delta, TAU)
			visual.basis = _aim_basis(vel).rotated(vel.normalized(), _spin)
		State.HELD:
			var dir: Vector3 = carrier.facing
			if not carrier.is_down():
				dir = dir + Vector3(0.0, 0.45, 0.0)
			visual.basis = visual.basis.orthonormalized().slerp(_aim_basis(dir), 1.0 - exp(-14.0 * delta))
		State.LOOSE:
			if _loose_velocity.length_squared() > 0.01:
				# Bouncing: tumble end over end across the direction of travel.
				var flat: Vector3 = Vector3(_loose_velocity.x, 0.0, _loose_velocity.z)
				var axis: Vector3 = Vector3.UP.cross(flat).normalized() if flat.length_squared() > 0.01 else Vector3.BACK
				visual.basis = visual.basis.rotated(axis, TUMBLE_SPIN * delta).orthonormalized()
			else:
				var nose: Vector3 = visual.basis.x
				nose.y = 0.0
				if nose.length_squared() < 0.01:
					nose = Vector3.RIGHT
				visual.basis = visual.basis.orthonormalized().slerp(_aim_basis(nose), 1.0 - exp(-10.0 * delta))


## Basis with the ball's long axis (X) along `dir` and the laces up.
func _aim_basis(dir: Vector3) -> Basis:
	var x: Vector3 = dir.normalized()
	var ref: Vector3 = Vector3.UP if absf(x.y) < 0.99 else Vector3.FORWARD
	var z: Vector3 = x.cross(ref).normalized()
	return Basis(x, z.cross(x), z)


func _follow_carrier() -> void:
	position = carrier.ball_anchor()
	position.y = maxf(position.y, GROUND_HEIGHT)
