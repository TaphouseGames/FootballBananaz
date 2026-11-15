class_name PlayerFall
extends RefCounted
## How a player's whole body tips over, tumbles, lands and gets back up. Visual,
## but for one thing: the play reads `landed` to know when a diving ball carrier
## is on the turf. Every knock-down is simulated from the hit that caused it, so
## no two look the same.
##
## Directions are in the Player node's own frame: +X is the way he faces, -Z is
## his left.

## HIGH: shoved or hit up top. LOW: legs taken out by a dive. WRAP: dragged down
## by a standing tackler. BOUNCE_OFF: a tackler who missed. PANCAKE: a blocker
## who got run over. DIVE: landing after the player's own dive. SPLAT: thrown
## or diving into the wall, flattened against it and stuck there for a moment.
enum Kind { HIGH, LOW, WRAP, BOUNCE_OFF, PANCAKE, DIVE, SPLAT }

const STAND_HEIGHT: float = 0.95
const DOWN_HEIGHT: float = 0.3
const DIVE_TILT: float = 1.25
const DIVE_HEIGHT: float = 0.7
const GRAVITY: float = 40.0
const GET_UP_TIME: float = 0.42
const VARIANTS: int = 4
## Flat against the wall: yards from its face to the middle of the body, how
## thin the body is pressed (1 = as he is), how much wider and taller that
## makes him, how far down the wall he slides while he is stuck, and how long
## he takes to come unstuck once he starts to peel off.
const SPLAT_GAP: float = 0.14
const SPLAT_THICKNESS: float = 0.2
const SPLAT_SPREAD: float = 0.3
const SPLAT_SLIDE: float = 0.22
const SPLAT_PEEL_TIME: float = 0.25

## Separate from the global generator, so looks never change how a game plays out.
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var active: bool = false
var kind: Kind = Kind.HIGH
## 0..1: how hard the hit was.
var power: float = 0.0
## Unit vector the head falls toward.
var dir: Vector3 = Vector3.LEFT
var on_back: bool = true
## A full somersault before landing.
var flip: bool = false
var airborne: bool = false
## Which sprawl the limbs end up in, and whether it is mirrored.
var variant: int = 0
var mirror: bool = false
var elapsed: float = 0.0
## The body has tipped all the way over and is lying on the turf. None of the
## random parts of a fall decide when: the play can rely on it.
var landed: bool = false
## 0 while still tumbling, 1 once flat on the turf.
var settle: float = 0.0
## 0 while down, rising to 1 as the player gets back to his feet.
var rise: float = 0.0
## Set when the body slams into the turf; the animator reads and clears it.
var impact: float = 0.0
## Radians per second around the vertical axis.
var spin_speed: float = 0.0
## 1 while he is stuck flat against the wall, down to 0 as he peels off it.
var stick: float = 0.0

var _tip: float = 0.0
var _tip_vel: float = 0.0
var _tip_end: float = PI * 0.5
var _tip_accel: float = 34.0
var _twist_end: float = 0.0
var _spin: float = 0.0
var _height: float = STAND_HEIGHT
var _height_vel: float = 0.0
var _tip_bounced: bool = false
var _ground_bounced: bool = false
var _get_up_time: float = GET_UP_TIME
## Against the wall: how long he sticks and how much of that is left, the way
## the wall faces (in the player's frame), and how thick the body is now (it
## springs, so it wobbles when he hits and when he comes off).
var _stick_time: float = 0.0
var _stick_left: float = 0.0
var _wall: Vector3 = Vector3.RIGHT
var _thick: float = 1.0
var _thick_vel: float = 0.0

var _quat: Quaternion = Quaternion.IDENTITY
var _out_height: float = STAND_HEIGHT
## Body height of a jump dive without the height left from the jump.
var _dive_base: float = STAND_HEIGHT


func reset() -> void:
	active = false
	landed = false
	settle = 0.0
	rise = 0.0
	impact = 0.0
	spin_speed = 0.0
	stick = 0.0
	_stick_left = 0.0
	_thick = 1.0
	_thick_vel = 0.0
	_quat = Quaternion.IDENTITY
	_out_height = STAND_HEIGHT


## `hit_dir` is the unit direction the hit pushes the player, `velocity` what he
## was doing just before it. `duration` is how long he stays down in total.
func start(hit_dir: Vector3, p_power: float, p_kind: Kind, p_airborne: bool, velocity: Vector3, duration: float) -> void:
	_begin(p_kind, p_power, duration)
	airborne = p_airborne
	var jitter: float = _rng.randf_range(-1.0, 1.0)
	var side: float = 1.0 if jitter >= 0.0 else -1.0
	var d: Vector3 = hit_dir
	var speed: float = velocity.length()
	var pop: float = 0.0
	_tip_vel = 2.0 + 7.0 * power
	spin_speed = jitter * 2.5 * power

	match kind:
		Kind.HIGH:
			pop = 4.0 * maxf(power - 0.35, 0.0) / 0.65
		Kind.LOW:
			# Legs cut out from under him: the rest keeps going the way it was.
			if speed > 3.0:
				d = _blend_dir(velocity / speed, d, 0.35)
			if speed > 5.5 and power > 0.55 and _rng.randf() < 0.6:
				flip = true
				_tip_end = PI * 1.5
				_tip_vel = 9.5
				pop = 6.8
			else:
				_tip_vel = 4.0 + 6.0 * power
				pop = 2.0 * power
		Kind.WRAP:
			# Dragged down: momentum carries him on and the tackler twists him.
			if speed > 2.0:
				d = _blend_dir(d, velocity / speed, 0.8)
			_tip_vel = 1.5 + 3.5 * power
			_tip_accel = 24.0
			spin_speed = side * (2.0 + 3.0 * power)
		Kind.BOUNCE_OFF:
			if _rng.randf() < 0.65:
				# Whiffed and eats turf, a little off to one side.
				d = Vector3.RIGHT.rotated(Vector3.UP, jitter * 0.7)
			_tip_vel = 3.0
			spin_speed = jitter * 5.0
		Kind.PANCAKE:
			# Staggers, then sits down hard.
			_tip_vel = 1.6
			_tip_accel = 27.0
			spin_speed = jitter * 1.2

	if airborne:
		# Hit in the air: helicopters round before coming down flat.
		spin_speed = side * (9.0 + 6.0 * power)
		_tip_vel *= 0.6
		pop = maxf(pop, 1.0)

	dir = d
	if flip:
		on_back = true
		_twist_end = jitter * 0.3
	else:
		if absf(d.x) < 0.4:
			# Knocked sideways: rolls onto either side.
			on_back = _rng.randf() < 0.5
		else:
			on_back = d.x < 0.0
		# Turn so the chest ends up facing the sky (on the back) or the turf.
		var chest: Vector3 = -d if on_back else d
		_twist_end = atan2(-chest.z, chest.x)
	_height_vel = pop


## The belly flop at the end of the player's own dive.
## `hard` is the landing of a jump dive: he hits the turf at speed, bounces and
## skids round a little.
func start_dive_landing(duration: float, hard: bool = false) -> void:
	_begin(Kind.DIVE, 0.9 if hard else 0.3, duration)
	airborne = false
	dir = Vector3.RIGHT
	on_back = false
	_tip = DIVE_TILT
	_tip_vel = 2.5
	_twist_end = 0.0
	spin_speed = _rng.randf_range(-1.0, 1.0)
	if hard:
		_tip_vel = 6.0
		_height_vel = 3.2
		spin_speed = _rng.randf_range(2.5, 4.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
		impact = 1.0


## Into the wall. `normal` is the way the wall faces, in the player's frame.
## He is flat against it, chest or back first whichever was nearer, for
## `stick_time`; then he tips off it like a board and lands on the turf.
func start_splat(normal: Vector3, p_power: float, stick_time: float, duration: float) -> void:
	_begin(Kind.SPLAT, p_power, duration)
	airborne = false
	dir = Vector3(normal.x, 0.0, normal.z).normalized()
	_wall = dir
	# Chest to the wall, he comes off it onto his back.
	on_back = dir.x < 0.0
	var chest: Vector3 = -dir if on_back else dir
	_twist_end = atan2(-chest.z, chest.x)
	spin_speed = 0.0
	_stick_time = maxf(stick_time, 0.01)
	_stick_left = _stick_time
	stick = 1.0
	_height = STAND_HEIGHT
	impact = 1.0
	# The play need not wait for him to slide off: he is down where he hit.
	landed = true


func _begin(p_kind: Kind, p_power: float, duration: float) -> void:
	active = true
	kind = p_kind
	power = clampf(p_power, 0.0, 1.0)
	flip = false
	elapsed = 0.0
	landed = false
	settle = 0.0
	rise = 0.0
	impact = 0.0
	stick = 0.0
	_stick_left = 0.0
	variant = _rng.randi_range(0, VARIANTS - 1)
	mirror = _rng.randf() < 0.5
	_tip = 0.0
	_tip_end = PI * 0.5
	_tip_accel = 34.0
	_spin = 0.0
	_height = _out_height
	_height_vel = 0.0
	_tip_bounced = false
	_ground_bounced = false
	_get_up_time = minf(GET_UP_TIME, duration * 0.45)


func _blend_dir(a: Vector3, b: Vector3, b_weight: float) -> Vector3:
	var mixed: Vector3 = a + b * b_weight
	mixed.y = 0.0
	return mixed.normalized() if mixed.length_squared() > 0.0001 else a


## Advances the tumble and writes the result to the player's Body node.
func update(player: Player, body: Node3D, delta: float, instant: bool) -> void:
	if instant:
		reset()
		body.basis = Basis(_quat)
		body.position.y = _out_height
		return

	var target: Quaternion = Quaternion.IDENTITY
	var target_height: float = STAND_HEIGHT
	var rate: float = 18.0
	if player.state == Player.State.DOWN and active:
		_simulate(delta)
		var axis: Vector3 = Vector3.UP.cross(dir).normalized()
		var twist: float = _twist_end * smoothstep(0.0, 1.0, _tip / (PI * 0.5))
		if kind == Kind.SPLAT:
			# Turned to the wall from the moment he hits it.
			twist = _twist_end
		target = Quaternion(Vector3.UP, _spin) * Quaternion(axis, _tip) * Quaternion(Vector3.UP, twist)
		target_height = _height
		rise = 0.0
		if _get_up_time > 0.0 and player.state_timer < _get_up_time:
			rise = smoothstep(0.0, 1.0, 1.0 - player.state_timer / _get_up_time)
			target = target.slerp(Quaternion.IDENTITY, rise)
			target_height = lerpf(target_height, _floor_height((target * Vector3.UP).y), rise)
		rate = 45.0
	elif player.state == Player.State.DIVING:
		target = Quaternion(Vector3.FORWARD, DIVE_TILT)
		target_height = DIVE_HEIGHT
	else:
		active = false
		settle = 0.0
		rise = 0.0
		spin_speed = 0.0
		stick = 0.0
		_thick = 1.0
		_thick_vel = 0.0

	var blend: float = 1.0 - exp(-rate * delta)
	_quat = _quat.slerp(target, blend).normalized()
	if player.state == Player.State.JUMPING:
		# The arc is exact, not eased, so take-off and landing look crisp.
		_out_height = STAND_HEIGHT + player.air_height()
		_dive_base = STAND_HEIGHT
	elif player.state == Player.State.DIVING and player.jump_dive:
		# Down from the jump on an arc, laying out as he comes.
		_dive_base = lerpf(_dive_base, DIVE_HEIGHT, blend)
		_out_height = _dive_base + player.air_height()
	else:
		_out_height = lerpf(_out_height, target_height, blend)
	body.basis = _pressed() * Basis(_quat)
	body.position.y = _out_height


## The body pressed thin against the wall, and wider and taller for it: a
## stretch along the wall's normal in the player's frame. Nothing when he is
## not against it.
func _pressed() -> Basis:
	if absf(_thick - 1.0) < 0.002:
		return Basis.IDENTITY
	var wide: float = 1.0 + (1.0 - _thick) * SPLAT_SPREAD
	var squash: Basis = Basis.IDENTITY
	for axis: int in 3:
		var unit: Vector3 = Basis.IDENTITY[axis]
		squash[axis] = unit * wide + _wall * (_thick - wide) * _wall.dot(unit)
	return squash


## The thickness of the body follows `target` on a spring.
func _spring_thickness(target: float, delta: float) -> void:
	_thick_vel += ((target - _thick) * 900.0 - _thick_vel * 34.0) * delta
	_thick = clampf(_thick + _thick_vel * delta, 0.12, 1.3)


## Height of the body's centre when it rests on the turf, from how upright it is.
func _floor_height(up_y: float) -> float:
	return DOWN_HEIGHT + (STAND_HEIGHT - DOWN_HEIGHT) * absf(up_y)


func _simulate(delta: float) -> void:
	elapsed += delta
	if kind == Kind.SPLAT:
		if _stick_left > 0.0:
			# Stuck to the wall, sliding down it a little.
			_stick_left -= delta
			stick = 1.0
			_height = STAND_HEIGHT - SPLAT_SLIDE * (1.0 - maxf(_stick_left, 0.0) / _stick_time)
			_spring_thickness(SPLAT_THICKNESS, delta)
			if _stick_left <= 0.0:
				_tip_vel = 0.8
				_height_vel = 0.0
			return
		stick = move_toward(stick, 0.0, delta / SPLAT_PEEL_TIME)
		_spring_thickness(1.0, delta)

	# Tipping over: a falling pole, shoved by the hit and pulled on by gravity.
	if _tip < _tip_end:
		_tip_vel += _tip_accel * maxf(absf(sin(_tip)), 0.3) * delta
		_tip += _tip_vel * delta
		if _tip >= _tip_end:
			_tip = _tip_end
			if _tip_vel > 3.5 and not _tip_bounced:
				_tip_bounced = true
				impact = maxf(impact, clampf(_tip_vel / 12.0, 0.2, 1.0))
				_height_vel = maxf(_height_vel, _tip_vel * 0.16)
				_tip_vel = -_tip_vel * 0.16
			else:
				_tip_vel = 0.0
	settle = smoothstep(0.55, 1.0, _tip / _tip_end)

	# Height: thrown up by a big hit, then a single bounce off the turf.
	var floor_height: float = _floor_height(cos(_tip))
	_height_vel -= GRAVITY * delta
	_height += _height_vel * delta
	var grounded: bool = _height <= floor_height
	if grounded:
		_height = floor_height
		if _height_vel < -4.5 and not _ground_bounced:
			_ground_bounced = true
			impact = maxf(impact, clampf(-_height_vel / 10.0, 0.2, 1.0))
			_height_vel = -_height_vel * 0.28
		else:
			_height_vel = 0.0
		if _tip >= _tip_end:
			landed = true

	_spin += spin_speed * delta
	if grounded:
		spin_speed *= exp(-7.0 * delta)
