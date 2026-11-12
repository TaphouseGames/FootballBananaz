class_name Ball
extends Node3D
## The football: carried, flying on a ballistic arc, or loose on the turf.

## The ball hit the turf hard enough to hear. `strength` is 0..1.
signal bounced(strength: float)

enum State { HELD, FLIGHT, LOOSE }

## Nose-to-nose length in metres (a real ball is 0.28; this reads better from the
## game camera). The model is 1 unit long and about 0.6 wide.
const BALL_LENGTH: float = 0.4
const GROUND_HEIGHT: float = 0.12
const LEATHER_SHADER: Shader = preload("res://assets/ball/ball_leather.gdshader")
## Radians per second around the long axis on a thrown spiral.
const SPIRAL_SPIN: float = 26.0
const TUMBLE_SPIN: float = 14.0
## A fumbled ball: coming down slower than this it rolls instead of bouncing,
## how far (radians) a bounce can turn it, and how quickly a roll dies (yd/s2).
const WILD_ROLL_SPEED: float = 2.0
const WILD_BOUNCE_TURN: float = 0.9
const WILD_ROLL_FRICTION: float = 5.0

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
## A fumbled ball: it hops off line on every bounce and rolls on afterwards.
var _wild: bool = false
## How fast the ball is moving right now, whatever it is doing.
var velocity: Vector3 = Vector3.ZERO

## Late in its flight a pass bends toward the hands waiting for it: `_guide` is
## where its end point should move to (as an offset), `_guide_now` the eased
## value in use, and `_guide_window` how many seconds before arrival it starts.
var _guide: Vector3 = Vector3.ZERO
var _guide_now: Vector3 = Vector3.ZERO
var _guide_window: float = 0.0
## A ball just caught is still where the hands met it, not tucked away yet:
## that spot, in the carrier's body frame. Over `_settle_time` the ball moves
## from there to the hand that carries it.
var _settle_local: Vector3 = Vector3.ZERO
var _settle_time: float = 0.0
var _settle_left: float = 0.0
## A toss: the ball comes from a fixed spot on the field (`_toss_from`) instead,
## on an arc this high at its top.
var _tossed: bool = false
var _toss_from: Vector3 = Vector3.ZERO
var _toss_height: float = 0.0

var _spin: float = 0.0
## The ball in flight was kicked: it tumbles end over end instead of spiralling.
var _kicked: bool = false

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


## With `settle` above 0 the ball stays where it is and eases into the carrier's
## hand over that many seconds, instead of jumping there.
func give_to(player: Player, settle: float = 0.0) -> void:
	_release()
	carrier = player
	carrier.has_ball = true
	state = State.HELD
	landing_marker.visible = false
	_settle_time = settle
	_settle_left = settle
	_tossed = false
	_wild = false
	if settle > 0.0:
		_settle_local = carrier.hold_frame().affine_inverse() * position
	_follow_carrier()


## A short underhand toss from whoever has the ball. `player` has it from now
## on as far as the rules go; for `time` seconds the ball is seen on its way.
func toss_to(player: Player, time: float, height: float) -> void:
	var from: Vector3 = position
	give_to(player, time)
	_tossed = true
	_toss_from = from
	_toss_height = height
	_follow_carrier()


func place_on_ground(spot: Vector3) -> void:
	_release()
	state = State.LOOSE
	_loose_velocity = Vector3.ZERO
	_wild = false
	landing_marker.visible = false
	position = Vector3(spot.x, GROUND_HEIGHT, spot.z)
	visual.basis = Basis.IDENTITY
	reset_physics_interpolation()


## `speed` is the flat speed; gravity is fixed, so a slower pass arcs higher.
func throw_to(p_thrower: Player, p_intended: Player, point: Vector3, speed: float, tuning: Tuning) -> void:
	_launch(p_thrower, p_intended, p_thrower.position + Vector3(0.0, tuning.pass_release_height + p_thrower.air_height(), 0.0), point, speed, tuning)
	_kicked = false


## A kick off the ground from where the ball lies, end over end.
func kick_to(kicker: Player, p_intended: Player, point: Vector3, speed: float, tuning: Tuning) -> void:
	_launch(kicker, p_intended, position, point, speed, tuning)
	_kicked = true


func _launch(p_thrower: Player, p_intended: Player, from: Vector3, point: Vector3, speed: float, tuning: Tuning) -> void:
	_release()
	thrower = p_thrower
	intended = p_intended
	state = State.FLIGHT
	_wild = false
	_gravity = tuning.pass_gravity
	_flight_start = from
	target_point = Vector3(point.x, 0.0, point.z)
	var flat: Vector3 = target_point - _flight_start
	flat.y = 0.0
	flight_time = maxf(flat.length() / speed, 0.2)
	flight_elapsed = 0.0
	_guide = Vector3.ZERO
	_guide_now = Vector3.ZERO
	_guide_window = 0.0
	_flight_velocity = flat / flight_time
	_flight_vy = (tuning.pass_catch_height - _flight_start.y + 0.5 * _gravity * flight_time * flight_time) / flight_time
	position = _flight_start
	landing_marker.visible = true
	landing_marker.global_position = target_point + Vector3(0.0, 0.06, 0.0)
	landing_marker.reset_physics_interpolation()


## Where the pass in flight ends up if nothing guides it.
func end_position() -> Vector3:
	var end: Vector3 = _flight_start + _flight_velocity * flight_time
	end.y = _flight_start.y + _flight_vy * flight_time - 0.5 * _gravity * flight_time * flight_time
	return end


## Bends the last `window` seconds of the flight so it ends at `point` instead.
## Call every tick while it applies; `point` may move.
func guide_to(point: Vector3, window: float) -> void:
	_guide = point - end_position()
	_guide_window = window


## Where a pass is `elapsed` seconds into its flight, guiding included.
func _flight_position(elapsed: float) -> Vector3:
	var t: float = minf(elapsed, flight_time)
	var pos: Vector3 = _flight_start + _flight_velocity * t
	pos.y = _flight_start.y + _flight_vy * t - 0.5 * _gravity * t * t
	if _guide_window > 0.0:
		pos += _guide_now * smoothstep(0.0, 1.0, 1.0 - (flight_time - t) / _guide_window)
	return pos


## Where the pass in flight will be after one more tick of `delta` seconds.
func next_flight_position(delta: float) -> Vector3:
	return _flight_position(flight_elapsed + delta)


## How much of the way a ball just caught still has to go to the carrying hand
## (1 at the catch, 0 once it is there), `ahead` seconds from now.
func settle_share(ahead: float = 0.0) -> float:
	if _settle_time <= 0.0:
		return 0.0
	return smoothstep(0.0, 1.0, maxf(_settle_left - ahead, 0.0) / _settle_time)


## Where a ball just caught is while it is brought in: on the line from the spot
## it was caught at (which moves with the carrier's body) to `anchor`, the hand
## that will carry it.
func settle_position(anchor: Vector3, share: float) -> Vector3:
	if _tossed:
		return anchor.lerp(_toss_from, share) + Vector3(0.0, _toss_height * 4.0 * share * (1.0 - share), 0.0)
	return anchor.lerp(carrier.hold_frame() * _settle_local, share)


## Incomplete pass: the ball falls to the turf.
func drop() -> void:
	_release()
	state = State.LOOSE
	_loose_velocity = _flight_velocity * 0.35 + Vector3(0.0, 3.0, 0.0)
	_wild = false
	landing_marker.visible = false


## Knocked out of the carrier's hands (or off somebody's fingers): it leaves from
## where it is at `p_velocity` and bounces wherever it likes until it is picked up.
func fumble(p_velocity: Vector3) -> void:
	_release()
	state = State.LOOSE
	_loose_velocity = p_velocity
	_wild = true
	landing_marker.visible = false


## Thrown down after a score: it bounces where it lands and stays about there.
func spike(p_velocity: Vector3) -> void:
	_release()
	state = State.LOOSE
	_loose_velocity = p_velocity
	_wild = false
	landing_marker.visible = false


## How fast a ball on the loose is moving, bounce included.
func loose_velocity() -> Vector3:
	return _loose_velocity if state == State.LOOSE else Vector3.ZERO


## A fumbled ball meets the turf. Coming down hard it bounces, and being the
## shape it is, not straight on; otherwise it rolls until the grass stops it.
func _bounce_wild(delta: float) -> void:
	var flat: Vector3 = Vector3(_loose_velocity.x, 0.0, _loose_velocity.z)
	if _loose_velocity.y < -WILD_ROLL_SPEED:
		bounced.emit(clampf(-_loose_velocity.y / 8.0, 0.0, 1.0))
		var up: float = -_loose_velocity.y * randf_range(0.35, 0.65)
		flat = flat.rotated(Vector3.UP, randf_range(-WILD_BOUNCE_TURN, WILD_BOUNCE_TURN)) * randf_range(0.55, 0.9)
		_loose_velocity = flat + Vector3(0.0, up, 0.0)
	else:
		_loose_velocity = flat.move_toward(Vector3.ZERO, WILD_ROLL_FRICTION * delta)


## Returns true on the tick a pass reaches its target point.
func integrate(delta: float) -> bool:
	_update_visual(delta)
	var before: Vector3 = position
	var arrived: bool = false
	match state:
		State.HELD:
			_settle_left = maxf(_settle_left - delta, 0.0)
			_follow_carrier()
		State.FLIGHT:
			flight_elapsed += delta
			if _guide_window > 0.0:
				_guide_now = _guide_now.lerp(_guide, 1.0 - exp(-30.0 * delta))
			position = _flight_position(flight_elapsed)
			arrived = flight_elapsed >= flight_time
		State.LOOSE:
			_loose_velocity.y -= _gravity * delta
			position += _loose_velocity * delta
			if position.y <= GROUND_HEIGHT:
				position.y = GROUND_HEIGHT
				if _wild:
					_bounce_wild(delta)
				else:
					if _loose_velocity.y < -WILD_ROLL_SPEED:
						bounced.emit(clampf(-_loose_velocity.y / 8.0, 0.0, 1.0))
					_loose_velocity.y = -_loose_velocity.y * 0.4
					_loose_velocity.x *= 0.6
					_loose_velocity.z *= 0.6
					if absf(_loose_velocity.y) < 1.0:
						_loose_velocity = Vector3.ZERO
	if delta > 0.0:
		velocity = (position - before) / delta
	return arrived


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
			_spin = fmod(_spin + (TUMBLE_SPIN if _kicked else SPIRAL_SPIN) * delta, TAU)
			if _kicked:
				var flat: Vector3 = Vector3(_flight_velocity.x, 0.0, _flight_velocity.z)
				if flat.length_squared() < 0.01:
					flat = Vector3.RIGHT
				visual.basis = _aim_basis(flat).rotated(Vector3.UP.cross(flat).normalized(), -_spin)
			else:
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
	if _settle_left > 0.0 and _settle_time > 0.0:
		position = settle_position(position, settle_share())
	position.y = maxf(position.y, GROUND_HEIGHT)
