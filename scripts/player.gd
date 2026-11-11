class_name Player
extends Node3D
## One footballer. Kinematic: PlayController calls integrate() every physics tick.
## Whoever drives the player (PlayerBrain or HumanController) sets move_input and
## wants_turbo before that.

enum State { NORMAL, DIVING, DOWN, JUKING, SHOVING }

const STAND_HEIGHT: float = 0.95
const DOWN_HEIGHT: float = 0.45

var team: Team
var tuning: Tuning
var brain: PlayerBrain
var index: int = 0

var velocity: Vector3 = Vector3.ZERO
## Desired direction, length 0..1, on the XZ plane.
var move_input: Vector3 = Vector3.ZERO
var wants_turbo: bool = false
var facing: Vector3 = Vector3.RIGHT

var state: State = State.NORMAL
var state_timer: float = 0.0
## True before the snap: the player holds his spot.
var frozen: bool = true
var has_ball: bool = false

## Per-play speed factor from the player's job (linemen are slower).
var speed_scale: float = 1.0
## Per-tick speed factor set by the AI (e.g. trailing in coverage).
var ai_speed_scale: float = 1.0

var turbo: float = 1.0
var turbo_locked: bool = false
var turbo_active: bool = false

## Set each tick by the AI while this player is trying to block.
var is_blocking: bool = false
var block_slow_timer: float = 0.0
var block_engaged_time: float = 0.0
var block_shed_time: float = 0.0
var block_immune_timer: float = 0.0

var juke_evade_timer: float = 0.0
var juke_cooldown: float = 0.0
var tackle_cooldown: float = 0.0

var _material: StandardMaterial3D

@onready var body: MeshInstance3D = $Body
@onready var control_ring: MeshInstance3D = $ControlRing
@onready var target_marker: MeshInstance3D = $TargetMarker
@onready var name_label: Label3D = $NameLabel


func setup(p_team: Team, p_index: int, p_tuning: Tuning) -> void:
	team = p_team
	index = p_index
	tuning = p_tuning
	brain = PlayerBrain.new(self, p_tuning)
	_material = StandardMaterial3D.new()
	_material.albedo_color = team.team_color
	_material.roughness = 0.6
	body.material_override = _material
	name_label.modulate = team.team_color.lightened(0.6)
	set_controlled(false)
	set_targeted(false)


func reset_for_play(spot: Vector3, face_dir: Vector3) -> void:
	position = spot
	velocity = Vector3.ZERO
	move_input = Vector3.ZERO
	wants_turbo = false
	facing = face_dir
	state = State.NORMAL
	state_timer = 0.0
	frozen = true
	has_ball = false
	speed_scale = 1.0
	ai_speed_scale = 1.0
	turbo = 1.0
	turbo_locked = false
	turbo_active = false
	is_blocking = false
	block_slow_timer = 0.0
	block_engaged_time = 0.0
	block_immune_timer = 0.0
	juke_evade_timer = 0.0
	juke_cooldown = 0.0
	tackle_cooldown = 0.0
	set_targeted(false)
	_update_visual(0.0, true)
	reset_physics_interpolation()


func set_label(text: String) -> void:
	name_label.text = text


func set_controlled(value: bool) -> void:
	control_ring.visible = value


func set_targeted(value: bool) -> void:
	target_marker.visible = value


func can_act() -> bool:
	return state == State.NORMAL and not frozen


func is_down() -> bool:
	return state == State.DOWN


func max_speed() -> float:
	var speed: float = tuning.run_speed * speed_scale * ai_speed_scale
	if has_ball:
		speed *= tuning.carrier_speed_scale
	return speed


func start_dive(dir: Vector3) -> void:
	if not can_act():
		return
	state = State.DIVING
	state_timer = tuning.dive_time
	facing = dir
	velocity = dir * tuning.dive_speed


func start_shove(dir: Vector3) -> void:
	if not can_act():
		return
	state = State.SHOVING
	state_timer = tuning.shove_time
	facing = dir
	velocity = dir * tuning.shove_lunge_speed


## `lateral` is a unit vector along Z, `forward` a unit vector along X.
func start_juke(lateral: Vector3, forward: Vector3) -> bool:
	if not can_act() or juke_cooldown > 0.0:
		return false
	state = State.JUKING
	state_timer = tuning.juke_time
	juke_evade_timer = tuning.juke_evade_time
	juke_cooldown = tuning.juke_cooldown
	velocity = lateral * tuning.juke_speed + forward * tuning.run_speed * tuning.juke_forward_scale
	return true


func knock_down(impulse: Vector3, duration: float) -> void:
	state = State.DOWN
	state_timer = duration
	velocity = impulse
	velocity.y = 0.0
	turbo_active = false
	if impulse.length_squared() > 0.01:
		facing = -impulse.normalized()


func integrate(delta: float) -> void:
	_tick_timers(delta)
	if frozen:
		velocity = Vector3.ZERO
		_update_visual(delta, false)
		return

	match state:
		State.NORMAL:
			_move_normal(delta)
		State.DIVING:
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.DOWN
				state_timer = tuning.dive_recover_time
		State.JUKING:
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.NORMAL
		State.SHOVING:
			velocity = velocity.move_toward(Vector3.ZERO, tuning.deceleration * 0.5 * delta)
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.NORMAL
		State.DOWN:
			turbo = minf(turbo + tuning.turbo_refill * delta, 1.0)
			velocity = velocity.move_toward(Vector3.ZERO, tuning.knockdown_friction * delta)
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.NORMAL

	position += velocity * delta
	_clamp_to_field()
	if state != State.DOWN and velocity.length_squared() > 0.6:
		facing = velocity.normalized()
	_update_visual(delta, false)


func _move_normal(delta: float) -> void:
	var input: Vector3 = move_input.limit_length(1.0)
	var moving: bool = input.length_squared() > 0.01
	var speed: float = max_speed()

	turbo_active = wants_turbo and moving and not turbo_locked and turbo > 0.0
	if turbo_active:
		speed *= tuning.turbo_speed_multiplier
		turbo = maxf(turbo - tuning.turbo_drain * delta, 0.0)
		if turbo <= 0.0:
			turbo_locked = true
	else:
		turbo = minf(turbo + tuning.turbo_refill * delta, 1.0)
		if turbo_locked and turbo >= tuning.turbo_restart_threshold:
			turbo_locked = false

	if block_slow_timer > 0.0:
		speed *= tuning.block_slow_factor

	var rate: float = tuning.acceleration if moving else tuning.deceleration
	velocity = velocity.move_toward(input * speed, rate * delta)


func _tick_timers(delta: float) -> void:
	juke_evade_timer = maxf(juke_evade_timer - delta, 0.0)
	juke_cooldown = maxf(juke_cooldown - delta, 0.0)
	tackle_cooldown = maxf(tackle_cooldown - delta, 0.0)
	block_immune_timer = maxf(block_immune_timer - delta, 0.0)
	if block_slow_timer > 0.0:
		block_slow_timer -= delta
		if block_slow_timer <= 0.0:
			block_engaged_time = 0.0


func _clamp_to_field() -> void:
	var half_w: float = tuning.half_width() + 2.0
	var back: float = tuning.end_zone_depth - 0.5
	position.x = clampf(position.x, -back, tuning.field_length + back)
	position.z = clampf(position.z, -half_w, half_w)
	position.y = 0.0


func _update_visual(delta: float, instant: bool) -> void:
	var target_tilt: float = 0.0
	var target_height: float = STAND_HEIGHT
	match state:
		State.DIVING:
			target_tilt = -1.25
			target_height = 0.7
		State.DOWN:
			target_tilt = -PI * 0.5
			target_height = DOWN_HEIGHT
		State.SHOVING:
			target_tilt = -0.35
		State.JUKING:
			target_tilt = 0.2
	if state == State.NORMAL and turbo_active:
		target_tilt = -0.22

	var target_yaw: float = atan2(-facing.z, facing.x)
	if instant:
		rotation.y = target_yaw
		body.rotation.z = target_tilt
		body.position.y = target_height
	else:
		var blend: float = 1.0 - exp(-18.0 * delta)
		rotation.y = lerp_angle(rotation.y, target_yaw, blend)
		body.rotation.z = lerpf(body.rotation.z, target_tilt, blend)
		body.position.y = lerpf(body.position.y, target_height, blend)
