class_name Ball
extends Node3D
## The football: carried, flying on a ballistic arc, or loose on the turf.

enum State { HELD, FLIGHT, LOOSE }

const GROUND_HEIGHT: float = 0.25

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

@onready var landing_marker: MeshInstance3D = $LandingMarker


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
	reset_physics_interpolation()


func throw_to(p_thrower: Player, p_intended: Player, point: Vector3, tuning: Tuning) -> void:
	_release()
	thrower = p_thrower
	intended = p_intended
	state = State.FLIGHT
	_gravity = tuning.pass_gravity
	_flight_start = p_thrower.position + Vector3(0.0, tuning.pass_release_height, 0.0)
	target_point = Vector3(point.x, 0.0, point.z)
	var flat: Vector3 = target_point - _flight_start
	flat.y = 0.0
	flight_time = maxf(flat.length() / tuning.pass_speed, 0.2)
	flight_elapsed = 0.0
	_flight_velocity = flat / flight_time
	_flight_vy = (tuning.pass_catch_height - tuning.pass_release_height + 0.5 * _gravity * flight_time * flight_time) / flight_time
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


func _follow_carrier() -> void:
	var height: float = 0.55 if carrier.is_down() else 1.15
	position = carrier.position + carrier.facing * 0.4 + Vector3(0.0, height, 0.0)
