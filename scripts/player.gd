class_name Player
extends Node3D
## One footballer. Kinematic: PlayController calls integrate() every physics tick.
## Whoever drives the player (PlayerBrain or HumanController) sets move_input and
## wants_turbo before that.

## DRAGGING: a ball carrier wrapped up but still churning forward.
## HOLDING: the tackler hanging on to him.
## SPINNING, STIFF_ARM: ball-carrier moves. A dive with the ball ends the play.
enum State { NORMAL, DIVING, DOWN, SHOVING, JUMPING, DRAGGING, HOLDING, SPINNING, STIFF_ARM }

const JERSEY_SHADER: Shader = preload("res://assets/player/player_jersey.gdshader")

## Which part of the model's texture is repainted in the team colour: the grey
## cloth (true) or the green jersey (false). Set per model in the player scene.
@export var grey_kit: bool = false

var team: Team
var tuning: Tuning
var ratings: PlayerRatings
var brain: PlayerBrain
var animator: PlayerAnimator
## Body tumble for dives, knock-downs and getting up. Visual only.
var fall: PlayerFall = PlayerFall.new()
## Set by PlayController; the animator reads the ball and the play from it.
var play: PlayController
var index: int = 0

var velocity: Vector3 = Vector3.ZERO
## Desired direction, length 0..1, on the XZ plane.
var move_input: Vector3 = Vector3.ZERO
var wants_turbo: bool = false
var facing: Vector3 = Vector3.RIGHT
## When set, the player faces this way instead of the way he is moving
## (a quarterback dropping back keeps his eyes downfield).
var look_dir: Vector3 = Vector3.ZERO

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
## 0 while sprinting on turbo, back to 1 shortly after. A quarterback throws
## accurately only with his feet set.
var feet_set: float = 1.0

## Set each tick by the AI while this player is trying to block.
var is_blocking: bool = false
var block_slow_timer: float = 0.0
var block_engaged_time: float = 0.0
var block_shed_time: float = 0.0
## Seconds into this block at which the blocker flattens him; negative = never.
var block_pancake_time: float = -1.0
var block_immune_timer: float = 0.0

var spin_evade_timer: float = 0.0
## Shared by spin and stiff arm.
var move_cooldown: float = 0.0
var jump_cooldown: float = 0.0
var tackle_cooldown: float = 0.0
## Side of the current spin or stiff arm: +1 is the player's own left,
## -1 his right.
var move_side: float = 1.0
## The other half of a drag: the tackler for the carrier and the other way round.
var drag_partner: Player

@onready var body: Node3D = $Body
@onready var control_ring: MeshInstance3D = $ControlRing
@onready var pass_icon: Label3D = $PassIcon


func setup(p_team: Team, p_index: int, p_tuning: Tuning, p_ratings: PlayerRatings) -> void:
	team = p_team
	index = p_index
	tuning = p_tuning
	ratings = p_ratings
	brain = PlayerBrain.new(self, p_tuning)
	_setup_model()
	set_controlled(false)
	set_pass_icon("", Color.WHITE)


func reset_for_play(spot: Vector3, face_dir: Vector3) -> void:
	position = spot
	velocity = Vector3.ZERO
	move_input = Vector3.ZERO
	wants_turbo = false
	facing = face_dir
	look_dir = Vector3.ZERO
	state = State.NORMAL
	state_timer = 0.0
	frozen = true
	has_ball = false
	speed_scale = 1.0
	ai_speed_scale = 1.0
	turbo = 1.0
	turbo_locked = false
	turbo_active = false
	feet_set = 1.0
	is_blocking = false
	block_slow_timer = 0.0
	block_engaged_time = 0.0
	block_pancake_time = -1.0
	block_immune_timer = 0.0
	spin_evade_timer = 0.0
	move_cooldown = 0.0
	move_side = 1.0
	jump_cooldown = 0.0
	tackle_cooldown = 0.0
	drag_partner = null
	set_pass_icon("", Color.WHITE)
	_update_visual(0.0, true)
	reset_physics_interpolation()


## Dresses the model in the team colour and hooks up the procedural animator.
func _setup_model() -> void:
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var source: BaseMaterial3D = mesh_instance.get_active_material(0) as BaseMaterial3D
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = JERSEY_SHADER
		material.set_shader_parameter(&"team_color", team.team_color)
		material.set_shader_parameter(&"grey_kit", grey_kit)
		if source != null:
			material.set_shader_parameter(&"albedo_tex", source.albedo_texture)
		mesh_instance.material_override = material
	var skeletons: Array[Node] = body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("Player model has no Skeleton3D")
		return
	animator = PlayerAnimator.new(self, skeletons[0] as Skeleton3D)


## Where the ball sits while this player holds it.
func ball_anchor() -> Vector3:
	if animator == null:
		return position + facing * 0.4 + Vector3(0.0, 1.15 + air_height(), 0.0)
	return animator.ball_anchor()


func set_controlled(value: bool) -> void:
	control_ring.visible = value


## Button prompt above the head for "throw to this receiver". Empty text hides it.
func set_pass_icon(text: String, color: Color) -> void:
	pass_icon.visible = text != ""
	pass_icon.text = text
	pass_icon.modulate = color


func can_act() -> bool:
	return state == State.NORMAL and not frozen


func is_down() -> bool:
	return state == State.DOWN


func is_airborne() -> bool:
	return state == State.JUMPING


## Carrying the ball with turbo held: running with it, not looking to throw.
func is_tucked() -> bool:
	return has_ball and wants_turbo


## Height of the feet above the turf during a jump.
func air_height() -> float:
	if state != State.JUMPING:
		return 0.0
	var t: float = clampf(1.0 - state_timer / tuning.jump_time, 0.0, 1.0)
	return 4.0 * tuning.jump_height * t * (1.0 - t)


func max_speed() -> float:
	var speed: float = tuning.run_speed * speed_scale * ai_speed_scale
	speed *= PlayerRatings.blend(ratings.speed, tuning.speed_scale_low, tuning.speed_scale_high)
	if has_ball:
		speed *= tuning.carrier_speed_scale
	if state == State.STIFF_ARM:
		speed *= tuning.stiff_arm_speed_scale
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


## Keeps the run-up momentum; there is no steering in the air.
func start_jump() -> bool:
	if not can_act() or jump_cooldown > 0.0:
		return false
	state = State.JUMPING
	state_timer = tuning.jump_time
	turbo_active = false
	return true


## A full turn on the run: same line, a little slower, no steering.
## `side` is +1 to turn over the player's own left shoulder, -1 over his right.
func start_spin(side: float) -> bool:
	if not can_act() or move_cooldown > 0.0:
		return false
	state = State.SPINNING
	state_timer = tuning.spin_time
	spin_evade_timer = tuning.spin_evade_time
	move_cooldown = tuning.move_cooldown
	move_side = 1.0 if side >= 0.0 else -1.0
	turbo_active = false
	velocity *= tuning.spin_speed_scale
	return true


## Arm out to one side for a moment; the carrier keeps running and steering.
## `side` is +1 for the player's own left arm, -1 for his right.
func start_stiff_arm(side: float) -> bool:
	if not can_act() or move_cooldown > 0.0:
		return false
	state = State.STIFF_ARM
	state_timer = tuning.stiff_arm_time
	move_cooldown = tuning.move_cooldown
	move_side = 1.0 if side >= 0.0 else -1.0
	return true


## True when `other` stands on the side the stiff arm is pointing to.
func stiff_arm_covers(other: Player) -> bool:
	if state != State.STIFF_ARM:
		return false
	var to: Vector3 = other.position - position
	return to.dot(Vector3.UP.cross(facing)) * move_side > 0.0


## The tackler has hold of this ball carrier, who keeps going for `duration`
## seconds. PlayController decides how the drag ends.
func start_drag(tackler: Player, duration: float) -> void:
	release_drag()
	tackler.release_drag()
	state = State.DRAGGING
	state_timer = duration
	turbo_active = false
	drag_partner = tackler
	tackler.state = State.HOLDING
	tackler.turbo_active = false
	tackler.drag_partner = self


## Ends a drag with both players back on their feet.
func release_drag() -> void:
	var partner: Player = drag_partner
	drag_partner = null
	if state == State.DRAGGING or state == State.HOLDING:
		state = State.NORMAL
	if partner != null and partner.drag_partner == self:
		partner.release_drag()


## `kind` only changes how the fall looks.
func knock_down(impulse: Vector3, duration: float, kind: PlayerFall.Kind = PlayerFall.Kind.HIGH) -> void:
	release_drag()
	var was_airborne: bool = state == State.JUMPING
	var before: Vector3 = velocity
	state = State.DOWN
	state_timer = duration
	velocity = impulse
	velocity.y = 0.0
	turbo_active = false

	var strength: float = velocity.length()
	var hit_dir: Vector3 = velocity / strength if strength > 0.1 else -facing
	# Running into the hit makes it harder.
	var closing: float = maxf(-before.dot(hit_dir), 0.0)
	var power: float = clampf((strength + closing) / 16.0, 0.15, 1.0)
	fall.start(_to_local(hit_dir), power, kind, was_airborne, _to_local(before), duration)
	if animator != null:
		animator.jolt(hit_dir, 0.6 + power)


## A hit that staggers the player without knocking him over. Visual only.
func jolt(dir: Vector3, strength: float) -> void:
	if animator != null:
		animator.jolt(dir, strength)


## World direction to the player's own frame, as he is currently drawn.
func _to_local(dir: Vector3) -> Vector3:
	return dir.rotated(Vector3.UP, -rotation.y)


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
				fall.start_dive_landing(state_timer)
		State.SPINNING:
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.NORMAL
		State.STIFF_ARM:
			_move_normal(delta)
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.NORMAL
		State.JUMPING:
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.NORMAL
				jump_cooldown = tuning.jump_cooldown
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
		State.DRAGGING:
			# Legs still driving: steerable, or straight for the goal line.
			var dir: Vector3 = move_input.limit_length(1.0)
			if dir.length_squared() <= 0.01:
				dir = Vector3(float(team.attack_dir), 0.0, 0.0)
			velocity = velocity.move_toward(dir * max_speed() * tuning.drag_speed_scale, tuning.deceleration * delta)
			state_timer -= delta
		State.HOLDING:
			velocity = Vector3.ZERO
			if drag_partner == null:
				state = State.NORMAL
			else:
				var behind: Vector3 = -drag_partner.facing
				position = drag_partner.position + behind * tuning.drag_hold_distance
				facing = drag_partner.facing

	position += velocity * delta
	_clamp_to_field()
	if (state == State.NORMAL or state == State.JUMPING) and look_dir.length_squared() > 0.01:
		facing = look_dir.normalized()
	elif state != State.DOWN and velocity.length_squared() > 0.6:
		facing = velocity.normalized()
	_update_visual(delta, false)


func _move_normal(delta: float) -> void:
	var input: Vector3 = move_input.limit_length(1.0)
	var moving: bool = input.length_squared() > 0.01
	var speed: float = max_speed()

	turbo_active = wants_turbo and moving and not turbo_locked and turbo > 0.0
	if turbo_active:
		speed *= tuning.turbo_speed_multiplier
		var drain: float = tuning.turbo_drain * PlayerRatings.blend(ratings.endurance, tuning.endurance_drain_low, tuning.endurance_drain_high)
		turbo = maxf(turbo - drain * delta, 0.0)
		if turbo <= 0.0:
			turbo_locked = true
	else:
		turbo = minf(turbo + tuning.turbo_refill * delta, 1.0)
		if turbo_locked and turbo >= tuning.turbo_restart_threshold:
			turbo_locked = false

	# A quarterback's feet come unset when he tucks the ball and runs. A more
	# agile one gets them set again sooner.
	var unset: bool = turbo_active or is_tucked()
	var set_time: float = tuning.pass_set_feet_time * PlayerRatings.blend(ratings.agility, tuning.agility_scale_low, tuning.agility_scale_high)
	if unset or set_time <= 0.0:
		feet_set = 0.0 if unset else 1.0
	else:
		feet_set = minf(feet_set + delta / set_time, 1.0)

	if block_slow_timer > 0.0:
		speed *= tuning.block_slow_factor

	var rate: float = tuning.acceleration if moving else tuning.deceleration
	velocity = velocity.move_toward(input * speed, rate * delta)


func _tick_timers(delta: float) -> void:
	spin_evade_timer = maxf(spin_evade_timer - delta, 0.0)
	move_cooldown = maxf(move_cooldown - delta, 0.0)
	jump_cooldown = maxf(jump_cooldown - delta, 0.0)
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
	var target_yaw: float = atan2(-facing.z, facing.x)
	if instant:
		rotation.y = target_yaw
	elif state == State.SPINNING:
		# One full turn over the spin, ending square to the running line again.
		var turned: float = clampf(1.0 - state_timer / tuning.spin_time, 0.0, 1.0)
		rotation.y = target_yaw + move_side * TAU * turned
	elif state != State.DOWN:
		# A player on the turf stays turned the way he fell.
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-18.0 * delta))
	fall.update(self, body, delta, instant)
	if animator != null:
		animator.update(delta, instant)
