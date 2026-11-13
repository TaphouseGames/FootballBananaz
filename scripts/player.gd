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
## Looks a player can have, picked by his name so he keeps his from game to
## game. A skin tint multiplies the painted skin (white leaves it as it is).
const SKIN_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.96, 0.9, 0.82),
	Color(0.86, 0.75, 0.65),
	Color(0.74, 0.62, 0.54),
	Color(0.62, 0.5, 0.44),
	Color(0.5, 0.4, 0.36),
]
## Hair colours. Fully transparent stands for the hair as painted (brown).
const HAIR_COLORS: Array[Color] = [
	Color(0.0, 0.0, 0.0, 0.0),
	Color(0.09, 0.08, 0.08),
	Color(0.24, 0.15, 0.1),
	Color(0.62, 0.27, 0.12),
	Color(0.8, 0.64, 0.36),
	Color(0.56, 0.55, 0.53),
]

## The model's meshes with the height at rest baked in. See _with_rest_height().
static var _rest_meshes: Dictionary[Mesh, Mesh] = {}
## A fall that has gone on this long counts as landed whatever it looks like, so
## a play can never be left waiting for one.
const GROUNDED_TIMEOUT: float = 0.4
## World size of one pixel of the name under the control ring, and how far below
## the ring's centre the name starts, in yards on screen.
const NAME_TAG_PIXEL: float = 0.0125
const NAME_TAG_DROP: float = 1.35

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
## Set each tick by the AI while this receiver is open and wants the ball.
var calling_for_ball: bool = false
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
## Above 0 during a dive and for a moment after landing: the dive still reaches
## for a pass.
var dive_reach_timer: float = 0.0
## Set when a dive lands; counts down once he is back on his feet and is
## running. While above 0 he picks up speed more slowly.
var dive_get_up_timer: float = 0.0
## Counts down from tuning.catch_blend_time after a catch, while the hands bring
## the ball in.
var catch_timer: float = 0.0
## Above 0 after he failed to get hold of a loose ball: he cannot try again yet.
var ball_grab_cooldown: float = 0.0
## Side of the current spin or stiff arm: +1 is the player's own left,
## -1 his right.
var move_side: float = 1.0
## The other half of a drag: the tackler for the carrier and the other way round.
var drag_partner: Player

## Meshes of the model, and the tint laid over them while he flashes.
var _meshes: Array[MeshInstance3D] = []
var _flash_material: StandardMaterial3D
var _flash_color: Color = Color.WHITE
var _flash_strength: float = 0.0
var _flash_left: float = 0.0
## Made the first time the person takes this player over.
var _name_tag: Label3D

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
	calling_for_ball = false
	block_slow_timer = 0.0
	block_engaged_time = 0.0
	block_pancake_time = -1.0
	block_immune_timer = 0.0
	spin_evade_timer = 0.0
	move_cooldown = 0.0
	move_side = 1.0
	jump_cooldown = 0.0
	tackle_cooldown = 0.0
	dive_reach_timer = 0.0
	dive_get_up_timer = 0.0
	catch_timer = 0.0
	ball_grab_cooldown = 0.0
	drag_partner = null
	set_pass_icon("", Color.WHITE)
	_update_visual(0.0, true)
	reset_physics_interpolation()


## Tints the whole model `color` for a moment, fading out. `strength` is how
## much of the tint shows at the start, 0..1.
func flash(color: Color, strength: float) -> void:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_color = color
	_flash_strength = strength
	_flash_left = tuning.flash_time
	for mesh_instance: MeshInstance3D in _meshes:
		mesh_instance.material_overlay = _flash_material
	_process(0.0)
	set_process(true)


func _process(delta: float) -> void:
	if _flash_material == null:
		set_process(false)
		return
	_flash_left -= delta
	var share: float = clampf(_flash_left / maxf(tuning.flash_time, 0.01), 0.0, 1.0)
	_flash_material.albedo_color = Color(_flash_color, _flash_strength * share)
	if _flash_left <= 0.0:
		for mesh_instance: MeshInstance3D in _meshes:
			mesh_instance.material_overlay = null
		set_process(false)


## Dresses the model in the team colour and hooks up the procedural animator.
func _setup_model() -> void:
	var look: int = hash([team.team_color, index])
	if ratings != null and not ratings.display_name.is_empty():
		look = hash(ratings.display_name)
	var skin_tint: Color = SKIN_TINTS[look % SKIN_TINTS.size()]
	var hair_color: Color = HAIR_COLORS[(look / 64) % HAIR_COLORS.size()]
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var source: BaseMaterial3D = mesh_instance.get_active_material(0) as BaseMaterial3D
		mesh_instance.mesh = _with_rest_height(mesh_instance.mesh)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = JERSEY_SHADER
		material.set_shader_parameter(&"team_color", team.team_color)
		material.set_shader_parameter(&"white_kit", team.white_kit)
		material.set_shader_parameter(&"grey_kit", grey_kit)
		material.set_shader_parameter(&"skin_tint", skin_tint)
		material.set_shader_parameter(&"recolor_hair", hair_color.a > 0.0)
		material.set_shader_parameter(&"hair_color", hair_color)
		if source != null:
			material.set_shader_parameter(&"albedo_tex", source.albedo_texture)
		mesh_instance.material_override = material
		_meshes.append(mesh_instance)
	var skeletons: Array[Node] = body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("Player model has no Skeleton3D")
		return
	animator = PlayerAnimator.new(self, skeletons[0] as Skeleton3D)


## A copy of `mesh` whose vertex colour holds, in its red, how high up the
## model each vertex is as it stands at rest (0 at the feet, 1 at the top of the
## head). The jersey shader cuts the home kit's chest band by it. Made once per
## mesh and shared by every player. A mesh it cannot copy comes back as it is.
static func _with_rest_height(mesh: Mesh) -> Mesh:
	if _rest_meshes.has(mesh):
		return _rest_meshes[mesh]
	var source: ArrayMesh = mesh as ArrayMesh
	var result: Mesh = mesh
	if source != null and source.get_blend_shape_count() == 0:
		var low: float = INF
		var high: float = -INF
		var surfaces: Array[Array] = []
		for surface: int in source.get_surface_count():
			var arrays: Array = source.surface_get_arrays(surface)
			surfaces.append(arrays)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				low = minf(low, vertex.y)
				high = maxf(high, vertex.y)
		var copy: ArrayMesh = ArrayMesh.new()
		for surface: int in surfaces.size():
			var arrays: Array = surfaces[surface]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = PackedColorArray()
			colors.resize(vertices.size())
			for i: int in vertices.size():
				colors[i] = Color(inverse_lerp(low, high, vertices[i].y), 0.0, 0.0)
			arrays[Mesh.ARRAY_COLOR] = colors
			var flags: int = source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			copy.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, flags)
			copy.surface_set_material(surface, source.surface_get_material(surface))
		result = copy
	_rest_meshes[mesh] = result
	return result


## Where the ball sits while this player holds it.
func ball_anchor() -> Vector3:
	if animator == null:
		return position + facing * 0.4 + Vector3(0.0, 1.15 + air_height(), 0.0)
	return animator.ball_anchor()


## Which way the long axis of the ball he carries points, in world space.
func ball_axis() -> Vector3:
	if animator == null:
		var dir: Vector3 = facing
		if not is_down():
			dir = dir + Vector3(0.0, 0.45, 0.0)
		return dir
	return animator.ball_axis()


## The frame his upper body is in: it leans, jumps and dives with him.
func hold_frame() -> Transform3D:
	if animator == null:
		return global_transform
	return animator.skeleton.global_transform


func set_controlled(value: bool) -> void:
	control_ring.visible = value
	if value and _name_tag == null and ratings != null and ratings.display_name != "":
		_name_tag = _make_name_tag()
	if _name_tag != null:
		_name_tag.visible = value


## His name in small letters, just below the ring on screen whichever way the
## camera looks.
func _make_name_tag() -> Label3D:
	var tag: Label3D = Label3D.new()
	tag.text = ratings.display_name.to_upper()
	tag.position = control_ring.position
	tag.pixel_size = NAME_TAG_PIXEL
	tag.offset = Vector2(0.0, -NAME_TAG_DROP / NAME_TAG_PIXEL)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.render_priority = 4
	tag.outline_render_priority = 3
	tag.font_size = 44
	tag.outline_size = 14
	tag.outline_modulate = Color(0.05, 0.05, 0.08)
	add_child(tag)
	return tag


## Button prompt above the head for "throw to this receiver". Empty text hides it.
func set_pass_icon(text: String, color: Color) -> void:
	pass_icon.visible = text != ""
	pass_icon.text = text
	pass_icon.modulate = color


func can_act() -> bool:
	return state == State.NORMAL and not frozen


func is_down() -> bool:
	return state == State.DOWN


## Down and actually lying on the turf: a dive counts as down from its first
## tick after the leap, a moment before the body lands.
func is_grounded() -> bool:
	return state == State.DOWN and (fall.landed or not fall.active or fall.elapsed > GROUNDED_TIMEOUT)


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
		if play != null and play.qb == self and (is_tucked() or play.phase == PlayController.Phase.RUN):
			speed *= tuning.qb_run_speed_scale
	if state == State.STIFF_ARM:
		speed *= tuning.stiff_arm_speed_scale
	return speed


## `speed` below 0 means the full tuning.dive_speed.
func start_dive(dir: Vector3, speed: float = -1.0) -> void:
	if not can_act():
		return
	state = State.DIVING
	state_timer = tuning.dive_time
	dive_reach_timer = tuning.dive_time + tuning.dive_catch_grace
	facing = dir
	velocity = dir * (speed if speed >= 0.0 else tuning.dive_speed)


## Where he will be `time` seconds from now if he keeps doing what he is doing.
func position_in(time: float) -> Vector3:
	match state:
		State.DOWN, State.HOLDING:
			return position
		State.DIVING:
			return position + velocity * minf(time, maxf(state_timer, 0.0))
	return position + velocity * time


## Where his hands meet a ball that would otherwise end its flight at `ball_end`,
## `time` seconds from now: as close to it as his arms reach.
func catch_point(ball_end: Vector3, time: float) -> Vector3:
	if animator == null:
		return ball_end
	# His shoulders stay where they are on his body: upright, in the air or
	# stretched out in a dive.
	var shift: Vector3 = position_in(time) - position
	var shoulders: Vector3 = animator.shoulders() + shift
	var reach: float = animator.hands_reach()
	var offset: Vector3 = ball_end - shoulders
	if state == State.JUMPING:
		# He went up for it: taken overhead, not down at his waist.
		offset.y = maxf(offset.y, reach * 0.6)
	# In front of him, never in his chest or behind his back.
	var ahead: float = offset.dot(facing)
	if ahead < reach * 0.5:
		offset += facing * (reach * 0.5 - ahead)
	return animator.nearest_reach(shoulders + offset, shift)


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
## With `juke` he also sidesteps to that side while he turns.
func start_spin(side: float, juke: bool = false) -> bool:
	if not can_act() or move_cooldown > 0.0:
		return false
	state = State.SPINNING
	state_timer = tuning.spin_time
	spin_evade_timer = tuning.spin_evade_time
	move_cooldown = tuning.move_cooldown
	move_side = 1.0 if side >= 0.0 else -1.0
	turbo_active = false
	velocity *= tuning.spin_speed_scale
	if juke:
		# He keeps facing down his running line (see integrate), so this slides
		# him across it.
		if velocity.length_squared() > 0.6:
			facing = velocity.normalized()
		velocity += Vector3.UP.cross(facing) * move_side * tuning.spin_juke_distance / maxf(tuning.spin_time, 0.05)
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
	dive_reach_timer = 0.0
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
				dive_get_up_timer = tuning.dive_get_up_time
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
	elif state != State.DOWN and state != State.SPINNING and velocity.length_squared() > 0.6:
		# A spin keeps the facing it started with, sidestep or not.
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
	# Fresh up off the turf after a dive: legs come back slowly.
	if moving and dive_get_up_timer > 0.0 and tuning.dive_get_up_time > 0.0:
		var t: float = 1.0 - dive_get_up_timer / tuning.dive_get_up_time
		rate *= lerpf(tuning.dive_get_up_accel_scale, 1.0, t)
		dive_get_up_timer = maxf(dive_get_up_timer - delta, 0.0)
	velocity = velocity.move_toward(input * speed, rate * delta)


func _tick_timers(delta: float) -> void:
	spin_evade_timer = maxf(spin_evade_timer - delta, 0.0)
	move_cooldown = maxf(move_cooldown - delta, 0.0)
	jump_cooldown = maxf(jump_cooldown - delta, 0.0)
	tackle_cooldown = maxf(tackle_cooldown - delta, 0.0)
	dive_reach_timer = maxf(dive_reach_timer - delta, 0.0)
	catch_timer = maxf(catch_timer - delta, 0.0)
	ball_grab_cooldown = maxf(ball_grab_cooldown - delta, 0.0)
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
