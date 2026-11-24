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

## Whether a player is the model built from his PlayerLook (see PlayerModel)
## or the one model in the player scene, repainted.
const LOOK_MODELS: bool = true

## The model's meshes with the height at rest baked in. See _with_rest_height().
static var _rest_meshes: Dictionary[Mesh, Mesh] = {}
## A fall that has gone on this long counts as landed whatever it looks like, so
## a play can never be left waiting for one.
const GROUNDED_TIMEOUT: float = 0.4
## World size of one pixel of the name under the control ring, and how far below
## the ring's centre the name starts, in yards on screen.
const NAME_TAG_PIXEL: float = 0.0125
const NAME_TAG_DROP: float = 1.35
## The buttons over a scorer's head while his dance is being picked, in pixels
## of the label: where the diamond's middle is above DANCE_PROMPT_HEIGHT (yards
## off the turf, just over the ball he holds up), how far out each button sits
## (in the order of HumanController.PAD_LABELS, laid out as on the pad) and
## where the caption is.
const DANCE_PROMPT_HEIGHT: float = 3.2
const DANCE_PROMPT_PIXEL: float = 0.012
const DANCE_PROMPT_RISE: float = 120.0
const DANCE_PROMPT_SPREAD: float = 100.0
const DANCE_PROMPT_SPOTS: Array[Vector2] = [Vector2(0.0, -1.0), Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
const DANCE_PROMPT_CAPTION_RISE: float = 300.0
## Seconds the button that was pressed stays up by itself.
const DANCE_PROMPT_LINGER: float = 0.45

## Which part of the model's texture is repainted in the team colour: the grey
## cloth (true) or the green jersey (false). Set per model in the player scene.
@export var grey_kit: bool = false

var team: Team
## The person controlling him right now (see HumanController.set_controlled), or
## null: he runs on his brain.
var human: HumanController
var tuning: Tuning
var ratings: PlayerRatings
var brain: PlayerBrain
var animator: PlayerAnimator
## His model, when it is the one built from his look (see LOOK_MODELS).
var model: PlayerModel
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
## Yards wider than a footballer (a mascot is).
var extra_radius: float = 0.0
var has_ball: bool = false

## Per-play speed factor from the player's job (linemen are slower).
var speed_scale: float = 1.0
## Per-tick speed factor set by the AI (e.g. trailing in coverage).
var ai_speed_scale: float = 1.0

var turbo: float = 1.0
var turbo_locked: bool = false
var turbo_active: bool = false
## 0 while sprinting on turbo, back to 1 shortly after. For show only (a
## quarterback's stance and the acrobatic throw on the run):
## it does not change how well he throws.
var feet_set: float = 1.0
## How long his feet take to set again since they last came unset.
var _feet_set_time: float = 0.0
## Above 0 while a quarterback pumps the ball without letting go of it.
var pump_timer: float = 0.0
## A throw on the run is an acrobatic one. Visual only: which move, how much of
## it is left, which way it turns (+1 over his own left), how big it is (0..1)
## and the turn it makes, from the yaw it started at.
enum Flair { NONE, SPIN, LEAP, FADE }
var flair: Flair = Flair.NONE
var flair_timer: float = 0.0
var flair_side: float = 1.0
var flair_power: float = 1.0
var _flair_from: float = 0.0
var _flair_sweep: float = 0.0
## Whether his feet were set last tick, to stamp into his stance as they come set.
var _feet_were_set: bool = true

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
## The man he is locked up with in a block (either side of it), for as long as
## the timer runs. Only the animation reads it.
var block_partner: Player = null
var block_partner_timer: float = 0.0
## Run blocking: how fast (yards a second) the blocker on him is moving him out
## of the hole, rolled when the block is made, and the push that comes to this
## tick. See PlayController._drive_block.
var block_drive: float = 0.0
var block_drive_side: float = 0.0
var drive_push: Vector3 = Vector3.ZERO
## The blocker that roll was made against: the same two locking up again keep it.
var block_drive_by: Player = null
## The block he is in was rolled at the hole.
var hole_block: bool = false
## A run at a hole (PlayController._assign_run_blocks): which side of it he
## belongs to (+1 / -1 along z, 0 = neither), and for a lineman the defender
## he has.
var hole_side: float = 0.0
var block_target: Player = null
## A defender on the line: how far from the middle of the lane he is taken (the
## second man out on a side further than the first, so they do not jam).
var hole_clear: float = 0.0
## Above 0 while a back who hit the hole on time runs faster.
var burst_timer: float = 0.0

var spin_evade_timer: float = 0.0
## Shared by spin and stiff arm.
var move_cooldown: float = 0.0
## Above 0 while a ball carrier is securing the ball (see start_secure), and
## the time before he can do it again.
var secure_timer: float = 0.0
var secure_cooldown: float = 0.0
## 0..1: how much of the move the turbo he had left paid for (see start_secure).
var secure_strength: float = 1.0
## How strong his last jump, dive, spin and stiff arm were for the stamina he
## had left (see move_strength): 1 for one paid for in full.
var jump_strength: float = 1.0
var dive_strength: float = 1.0
var spin_strength: float = 1.0
var stiff_arm_strength: float = 1.0
var jump_cooldown: float = 0.0
var tackle_cooldown: float = 0.0
## Above 0 during a dive and for a moment after landing: the dive still reaches
## for a pass.
var dive_reach_timer: float = 0.0
## This dive has already flattened a man: it knocks nobody else over (see
## PlayController._dive_into).
var dive_spent: bool = false
## Set when a dive lands; counts down once he is back on his feet and is
## running. While above 0 he picks up speed more slowly.
var dive_get_up_timer: float = 0.0
# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
### The current dive was started in the air, from a jump.
#var jump_dive: bool = false
### Height of the feet when a jump dive began, and how long it lasts in all.
#var dive_start_height: float = 0.0
#var dive_duration: float = 0.0
## Above 0 while he lies dazed after landing a jump dive.
var dazed_timer: float = 0.0
## He was flattened against the wall on this tick: how fast he went into it
## (yd/s). 0 on every other tick. PlayController reads it.
var wall_hit: float = 0.0
## How far his body reaches toward the wall from his middle, in yards: 0 when
## he is nowhere near it. Measured from his pose (see _measure_reach).
var _wall_reach: float = 0.0
## Stars round his head while he is dazed, and a couple left over it while he
## is injured. Made the first time he is.
var daze_fx: DazeFx
## Hurt by landing a jump dive: `ratings` is a weakened copy until he is over
## it, `injured_plays` is how many more plays after this one it lasts.
var injured: bool = false
var injured_plays: int = 0
## How many times he has been hurt this game, hurt again while injured included.
var injuries: int = 0
## He has landed a jump dive or been flattened against the wall, and will be
## injured once he is up.
var _injury_pending: bool = false
## His own ratings, kept while `ratings` holds the injured copy.
var _healthy_ratings: PlayerRatings
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
## Made the first time his dance can be picked: the four buttons, then the caption.
var _dance_prompt: Node3D
var _dance_buttons: Array[Label3D] = []
var _dance_caption: Label3D
var _dance_tween: Tween

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
	# The ring under a person's player is in their team's colour. A material of
	# his own: the scene's is shared by every player.
	var ring: StandardMaterial3D = StandardMaterial3D.new()
	ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.albedo_color = team.marker_color()
	control_ring.set_surface_override_material(0, ring)
	set_controlled(false)
	set_pass_icon("", Color.WHITE)


func reset_for_play(spot: Vector3, face_dir: Vector3) -> void:
	position = spot
	velocity = Vector3.ZERO
	move_input = Vector3.ZERO
	wants_turbo = false
	secure_timer = 0.0
	secure_cooldown = 0.0
	secure_strength = 1.0
	jump_strength = 1.0
	dive_strength = 1.0
	spin_strength = 1.0
	stiff_arm_strength = 1.0
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
	_feet_set_time = 0.0
	pump_timer = 0.0
	flair = Flair.NONE
	flair_timer = 0.0
	is_blocking = false
	calling_for_ball = false
	block_slow_timer = 0.0
	block_engaged_time = 0.0
	block_pancake_time = -1.0
	block_immune_timer = 0.0
	block_partner = null
	block_partner_timer = 0.0
	block_drive = 0.0
	block_drive_side = 0.0
	drive_push = Vector3.ZERO
	block_drive_by = null
	hole_block = false
	hole_side = 0.0
	block_target = null
	hole_clear = 0.0
	burst_timer = 0.0
	spin_evade_timer = 0.0
	move_cooldown = 0.0
	move_side = 1.0
	jump_cooldown = 0.0
	tackle_cooldown = 0.0
	dive_reach_timer = 0.0
	dive_spent = false
	dive_get_up_timer = 0.0
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	jump_dive = false
#	dive_start_height = 0.0
	dazed_timer = 0.0
	catch_timer = 0.0
	ball_grab_cooldown = 0.0
	drag_partner = null
	set_pass_icon("", Color.WHITE)
	set_dance_prompt(false)
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
	if LOOK_MODELS:
		_setup_look_model()
		return
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


## Puts the model built from the player's own look where the scene's model
## stands, in his team's kit with his number and name on it.
func _setup_look_model() -> void:
	var placeholder: Node3D = body.get_node("Model") as Node3D
	model = PlayerModel.new()
	model.name = "LookModel"
	model.transform = placeholder.transform
	body.remove_child(placeholder)
	placeholder.queue_free()
	body.add_child(model)
	model.show_look(ratings.look_or_default(), team.team_color, ratings.number, ratings.display_name, team.white_kit)
	_meshes.append(model.body_mesh)
	if model.head != null:
		_meshes.append(model.head)
	animator = PlayerAnimator.new(self, model.skeleton)


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


## The four face buttons above his head: "pick the dance". Shown while `shown`.
## Hidden with `chosen` (0..3, a place in HumanController.PAD_LABELS) the
## button that was pressed stays up by itself for a moment first.
func set_dance_prompt(shown: bool, chosen: int = -1) -> void:
	if _dance_prompt == null:
		if not shown:
			return
		_make_dance_prompt()
	var lingering: bool = not shown and chosen >= 0 and chosen < _dance_buttons.size() and _dance_prompt.visible
	if shown == _dance_prompt.visible and not lingering:
		return
	if _dance_tween != null:
		_dance_tween.kill()
		_dance_tween = null
	if not lingering:
		_dance_prompt.visible = shown
		_dance_caption.visible = true
		for button: Label3D in _dance_buttons:
			button.visible = true
			button.pixel_size = DANCE_PROMPT_PIXEL
		return
	_dance_caption.visible = false
	for i: int in _dance_buttons.size():
		_dance_buttons[i].visible = i == chosen
	# It swells a little as it goes: the press was taken.
	_dance_tween = create_tween()
	_dance_tween.tween_property(_dance_buttons[chosen], ^"pixel_size", DANCE_PROMPT_PIXEL * 1.35, DANCE_PROMPT_LINGER)
	_dance_tween.tween_callback(_dance_prompt.hide)


func _make_dance_prompt() -> void:
	_dance_prompt = Node3D.new()
	_dance_prompt.position = Vector3(0.0, DANCE_PROMPT_HEIGHT, 0.0)
	_dance_prompt.visible = false
	add_child(_dance_prompt)
	for i: int in DANCE_PROMPT_SPOTS.size():
		var spot: Vector2 = Vector2(0.0, DANCE_PROMPT_RISE) + DANCE_PROMPT_SPOTS[i] * DANCE_PROMPT_SPREAD
		var button: Label3D = _dance_label(HumanController.PAD_LABELS[i], 100, 32, spot)
		button.modulate = HumanController.PAD_COLORS[i]
		_dance_buttons.append(button)
	_dance_caption = _dance_label("CELEBRATE!", 56, 18, Vector2(0.0, DANCE_PROMPT_CAPTION_RISE))


func _dance_label(text: String, font_size: int, outline: int, spot: Vector2) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.pixel_size = DANCE_PROMPT_PIXEL
	label.offset = spot
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 4
	label.outline_render_priority = 3
	label.font_size = font_size
	label.outline_size = outline
	label.outline_modulate = Color(0.05, 0.05, 0.08)
	_dance_prompt.add_child(label)
	return label


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


## The carrier has the ball in both arms against his chest and leans into the
## run: for a moment he is faster, fumbles less, runs over a weaker tackler in
## front of him and shakes off a tackler on his back more often. Not during a
## spin, a stiff arm, a jump or a dive.
func is_securing() -> bool:
	return has_ball and secure_timer > 0.0 and (state == State.NORMAL or state == State.DRAGGING)


## 0 when he is not securing the ball, otherwise how much of the move he has
## (see secure_strength): 1 for one paid for in full.
func secure_power() -> float:
	return secure_strength if is_securing() else 0.0


## One press: he secures the ball for tuning.secure_time, and cannot again
## until the cooldown is over. Also with a tackler on his back, where it lasts
## until the drag ends (see _tick_timers).
## It spends tuning.secure_turbo_cost of his turbo, scaled by his endurance (see
## stamina_cost). With less than that left it spends what there is and is that
## much shorter and weaker, and with none it does nothing. Emptying the meter
## locks turbo, as sprinting it empty does.
func start_secure() -> bool:
	if not has_ball or frozen or secure_cooldown > 0.0:
		return false
	if state != State.NORMAL and state != State.DRAGGING:
		return false
	if tuning.secure_turbo_cost > 0.0 and turbo <= 0.0:
		return false
	secure_strength = _spend_stamina(stamina_cost(tuning.secure_turbo_cost))
	secure_timer = tuning.secure_time * secure_strength
	secure_cooldown = tuning.secure_cooldown
	return true


## Takes `cost` off the stamina meter, or what is left of it, and returns the
## share of the cost that paid: 1 in full, 0 on an empty meter. Emptying the
## meter locks turbo, as sprinting it empty does.
func _spend_stamina(cost: float) -> float:
	if cost <= 0.0:
		return 1.0
	var spent: float = clampf(turbo, 0.0, cost)
	turbo -= spent
	if turbo <= 0.0:
		turbo = 0.0
		turbo_locked = true
	return spent / cost


## What a move with a base cost of `cost` takes off this player's stamina
## meter: less with good endurance, more with poor (as sprinting drains it).
func stamina_cost(cost: float) -> float:
	return cost * PlayerRatings.blend(ratings.endurance, tuning.endurance_drain_low, tuning.endurance_drain_high)


## How strong a jump, dive, spin or stiff arm with a base cost of `cost` of the
## stamina meter comes out, and pays for it (what he pays is scaled by his
## endurance, see stamina_cost): 1 with enough left, down to
## tuning.move_min_strength on an empty meter. With `spend` off it only looks.
func move_strength(cost: float, spend: bool = true) -> float:
	cost = stamina_cost(cost)
	var paid: float = 1.0
	if spend:
		paid = _spend_stamina(cost)
	elif cost > 0.0:
		paid = clampf(turbo, 0.0, cost) / cost
	return lerpf(tuning.move_min_strength, 1.0, paid)


## Lying dazed after a jump dive, or after being flattened against the wall.
func is_dazed() -> bool:
	return state == State.DOWN and dazed_timer > 0.0


## Up from a daze: his ratings drop for the rest of this play and the plays
## after it that tuning.injury_plays says. Already injured, they stay as they
## are and only the count starts again.
func injure() -> void:
	_injury_pending = false
	injured_plays = tuning.injury_plays
	injuries += 1
	if injured or ratings == null:
		return
	injured = true
	_healthy_ratings = ratings
	ratings = ratings.duplicate() as PlayerRatings
	for key: StringName in PlayerRatings.CARD_ORDER:
		var value: int = _healthy_ratings.get(key)
		ratings.set(key, roundi(float(value) * tuning.injury_rating_scale))


## Called once for every new play, before the line-up.
func next_play() -> void:
	if _injury_pending:
		# The whistle went while he was still lying there: the play now starting
		# is the one he is injured for.
		injure()
		injured_plays = maxi(injured_plays - 1, 0)
	elif injured:
		if injured_plays > 0:
			injured_plays -= 1
		else:
			heal()


func heal() -> void:
	_injury_pending = false
	injured_plays = 0
	if not injured:
		return
	injured = false
	ratings = _healthy_ratings
	_healthy_ratings = null


## Height of the feet above the turf during a jump, and on the way down from
## one in a jump dive.
func air_height() -> float:
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	if state == State.DIVING and jump_dive and dive_duration > 0.0:
#		var fallen: float = clampf(1.0 - state_timer / dive_duration, 0.0, 1.0)
#		return dive_start_height * (1.0 - fallen * fallen)
	if state != State.JUMPING:
		return 0.0
	var t: float = clampf(1.0 - state_timer / tuning.jump_time, 0.0, 1.0)
	return 4.0 * jump_height() * t * (1.0 - t)


## How high his feet get at the top of a jump: higher with a better juke
## rating, lower for a jump he was short of stamina for. `strength` below 0
## means that of his last jump (see move_strength).
func jump_height(strength: float = -1.0) -> float:
	if strength < 0.0:
		strength = jump_strength
	if ratings == null:
		return tuning.jump_height * strength
	return tuning.jump_height * strength * PlayerRatings.blend(ratings.juke, tuning.jump_height_scale_low, tuning.jump_height_scale_high)


func max_speed() -> float:
	var speed: float = tuning.run_speed * speed_scale * ai_speed_scale
	speed *= PlayerRatings.blend(ratings.speed, tuning.speed_scale_low, tuning.speed_scale_high)
	if has_ball:
		speed *= tuning.carrier_speed_scale
		if play != null and play.qb == self and (is_tucked() or play.phase == PlayController.Phase.RUN):
			speed *= tuning.qb_run_speed_scale
	if state == State.STIFF_ARM:
		speed *= tuning.stiff_arm_speed_scale
	if is_securing():
		speed *= lerpf(1.0, tuning.secure_speed_scale, secure_strength)
	if burst_timer > 0.0 and has_ball:
		speed *= tuning.hole_burst_speed
	return speed


## `speed` below 0 means the full tuning.dive_speed. It spends
## tuning.dive_stamina_cost and is that much shorter when he is short of it
## (see move_strength), unless it is `free`.
func start_dive(dir: Vector3, speed: float = -1.0, free: bool = false) -> void:
	if not can_act():
		return
	dive_strength = 1.0 if free else move_strength(tuning.dive_stamina_cost)
	state = State.DIVING
	dive_spent = false
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	jump_dive = false
	state_timer = tuning.dive_time
	dive_reach_timer = tuning.dive_time + tuning.dive_catch_grace
	facing = dir
	velocity = dir * (speed if speed >= 0.0 else tuning.dive_speed) * dive_strength


# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
### How long a jump dive started right now would stay in the air: longer from
### higher up in his own jump, however high that goes.
#func jump_dive_time() -> float:
#	var share: float = clampf(air_height() / maxf(jump_height(), 0.01), 0.0, 1.0)
#	return tuning.dive_time + tuning.jump_dive_extra_time * share


### A dive out of a jump: faster and further than one off the ground, and he
### lands dazed. `speed` below 0 means the full jump-dive speed.
#func start_jump_dive(dir: Vector3, speed: float = -1.0) -> bool:
#	if state != State.JUMPING or frozen:
#		return false
#	dive_duration = jump_dive_time()
#	dive_start_height = air_height()
#	# On top of what the jump cost.
#	dive_strength = move_strength(tuning.dive_stamina_cost)
#	state = State.DIVING
#	jump_dive = true
#	state_timer = dive_duration
#	dive_reach_timer = dive_duration + tuning.dive_catch_grace
#	jump_cooldown = tuning.jump_cooldown
#	turbo_active = false
#	facing = dir
#	velocity = dir * (speed if speed >= 0.0 else tuning.dive_speed * tuning.jump_dive_speed_scale) * dive_strength
#	return true


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
	jump_strength = move_strength(tuning.jump_stamina_cost)
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
	# Short of stamina it is slower, sidesteps less and takes less off the tackle
	# (PlayController._on_tackle_contact).
	spin_strength = move_strength(tuning.spin_stamina_cost)
	state = State.SPINNING
	state_timer = tuning.spin_time
	spin_evade_timer = tuning.spin_evade_time
	move_cooldown = tuning.move_cooldown
	move_side = 1.0 if side >= 0.0 else -1.0
	turbo_active = false
	velocity *= tuning.spin_speed_scale * sqrt(spin_strength)
	if juke:
		# He keeps facing down his running line (see integrate), so this slides
		# him across it.
		if velocity.length_squared() > 0.6:
			facing = velocity.normalized()
		velocity += Vector3.UP.cross(facing) * move_side * tuning.spin_juke_distance * spin_strength / maxf(tuning.spin_time, 0.05)
	return true


## Arm out to one side for a moment; the carrier keeps running and steering.
## `side` is +1 for the player's own left arm, -1 for his right.
func start_stiff_arm(side: float) -> bool:
	if not can_act() or move_cooldown > 0.0:
		return false
	stiff_arm_strength = move_strength(tuning.stiff_arm_stamina_cost)
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
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	jump_dive = false
	dazed_timer = 0.0
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
	wall_hit = 0.0
	if frozen:
		velocity = Vector3.ZERO
		_update_visual(delta, false)
		_clear_wall(delta)
		return

	match state:
		State.NORMAL:
			_move_normal(delta)
		State.DIVING:
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.DOWN
				# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
				# (The three lines below this block were its `else:` branch.)
#				if jump_dive:
#					# Came down from a height at speed: he is seeing stars.
#					jump_dive = false
#					_injury_pending = true
#					velocity *= tuning.jump_dive_landing_speed_scale
#					state_timer = tuning.jump_dive_daze_time
#					dazed_timer = state_timer
#					dive_get_up_timer = tuning.jump_dive_get_up_time
#					fall.start_dive_landing(state_timer, true)
#				else:
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
				if _injury_pending:
					injure()
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
	_meet_wall()
	if (state == State.NORMAL or state == State.JUMPING) and look_dir.length_squared() > 0.01:
		facing = look_dir.normalized()
	elif state != State.DOWN and state != State.SPINNING and velocity.length_squared() > 0.6:
		# A spin keeps the facing it started with, sidestep or not.
		facing = velocity.normalized()
	_update_visual(delta, false)
	_clear_wall(delta)


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

	# A quarterback's feet come unset only when he uses turbo (tucks the ball and
	# runs), and take a while to set again. Moving about without turbo never
	# unsets them.
	if turbo_active or is_tucked():
		feet_set = 0.0
		_feet_set_time = tuning.pass_set_feet_time
	elif _feet_set_time <= 0.0:
		feet_set = 1.0
	else:
		feet_set = minf(feet_set + delta / _feet_set_time, 1.0)

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
	secure_cooldown = maxf(secure_cooldown - delta, 0.0)
	pump_timer = maxf(pump_timer - delta, 0.0)
	flair_timer = maxf(flair_timer - delta, 0.0)
	# Wrapped up he hangs on to it until the drag is over.
	if state != State.DRAGGING:
		secure_timer = maxf(secure_timer - delta, 0.0)
	jump_cooldown = maxf(jump_cooldown - delta, 0.0)
	tackle_cooldown = maxf(tackle_cooldown - delta, 0.0)
	dive_reach_timer = maxf(dive_reach_timer - delta, 0.0)
	dazed_timer = maxf(dazed_timer - delta, 0.0)
	catch_timer = maxf(catch_timer - delta, 0.0)
	ball_grab_cooldown = maxf(ball_grab_cooldown - delta, 0.0)
	block_immune_timer = maxf(block_immune_timer - delta, 0.0)
	burst_timer = maxf(burst_timer - delta, 0.0)
	block_partner_timer = maxf(block_partner_timer - delta, 0.0)
	if block_partner != null and (block_partner_timer <= 0.0 or block_partner.state != State.NORMAL or state != State.NORMAL):
		block_partner = null
	if block_slow_timer > 0.0:
		block_slow_timer -= delta
		if block_slow_timer <= 0.0:
			block_engaged_time = 0.0


## Yards of a limb round the bone in the middle of it, and how near the wall
## (in yards) his middle has to be before his reach toward it is measured.
const LIMB_THICKNESS: float = 0.1
const WALL_REACH_RANGE: float = 2.6


## The wall round the field is solid: nobody's middle gets closer to it than
## _wall_room(), on any side.
func keep_on_field() -> void:
	position = Stadium.keep_inside(tuning, position, _wall_room())
	position.y = 0.0


## The room his middle needs from the face of the wall: what a man on his feet
## takes up, less when he is pressed flat against it, and never less than his
## body reaches toward it as it is posed now. So one lying with his head to the
## wall, or diving at it, is held further off than one standing by it.
func _wall_room() -> float:
	return maxf(lerpf(tuning.wall_standoff + extra_radius, PlayerFall.SPLAT_GAP, fall.stick), _wall_reach)


## After he is posed for this tick: no part of him is in the wall. Whatever
## reaches into it moves the whole of him back out.
func _clear_wall(delta: float) -> void:
	var reach: float = _measure_reach()
	if reach >= _wall_reach:
		_wall_reach = reach
	elif state == State.DOWN or state == State.DIVING:
		_wall_reach = lerpf(_wall_reach, reach, 1.0 - exp(-20.0 * delta))
	else:
		# On his feet his arms swing: he is not moved in and out with them.
		_wall_reach = move_toward(_wall_reach, reach, delta)
	if fall.stick >= 1.0:
		# Stuck to it: right up against it, as close as his body lets him.
		position += Stadium.wall_normal(tuning, position.x, position.z) * (Stadium.wall_distance(tuning, position.x, position.z) + _wall_room())
	elif _wall_reach > 0.0:
		keep_on_field()


## How far the furthest part of him is from his middle, toward the nearest
## wall: every bone below the top of the wall, and the thickness of a limb.
func _measure_reach() -> float:
	if animator == null or Stadium.wall_distance(tuning, position.x, position.z) < -WALL_REACH_RANGE:
		return 0.0
	var toward: Vector3 = -Stadium.wall_normal(tuning, position.x, position.z)
	var skeleton: Skeleton3D = animator.skeleton
	var to_world: Transform3D = skeleton.global_transform
	var from: Vector3 = global_position
	var reach: float = 0.0
	for i: int in skeleton.get_bone_count():
		var at: Vector3 = to_world * skeleton.get_bone_global_pose(i).origin
		if at.y < Stadium.WALL_HEIGHT:
			reach = maxf(reach, (at - from).dot(toward))
	return reach + LIMB_THICKNESS


## After his own move this tick: the wall stops him. Going into it on his feet
## he slides along it; thrown, knocked or diving into it he is flattened
## against it if he is fast enough and his body is up against it (his middle
## within tuning.wall_splat_range of it), and comes back off it a little if
## not: one who only touches it with a hand or his head is not flattened.
func _meet_wall() -> void:
	var gap: float = -Stadium.wall_distance(tuning, position.x, position.z)
	if gap >= _wall_room():
		position.y = 0.0
		return
	var normal: Vector3 = Stadium.wall_normal(tuning, position.x, position.z)
	keep_on_field()
	var into: float = -velocity.dot(normal)
	if into <= 0.0:
		return
	var thrown: bool = state == State.DIVING or state == State.DOWN
	if thrown and into >= tuning.wall_splat_speed and gap <= tuning.wall_splat_range and fall.stick <= 0.0:
		splat(normal, into)
	elif state == State.DOWN:
		velocity += normal * into * (1.0 + tuning.wall_bounce)
	else:
		velocity += normal * into


## Flattened against the wall, which faces `normal`, having gone into it at
## `speed`: he sticks to it for tuning.wall_splat_stick_time, then peels off
## and lies on the turf seeing stars for tuning.wall_splat_daze_time. Like one
## who has landed a jump dive, he gets up injured: for the rest of the play
## and tuning.injury_plays after it.
func splat(normal: Vector3, speed: float) -> void:
	release_drag()
	var down: float = tuning.wall_splat_daze_time
	_injury_pending = true
	dazed_timer = tuning.wall_splat_stick_time + down
	dive_get_up_timer = tuning.jump_dive_get_up_time
	state = State.DOWN
	state_timer = tuning.wall_splat_stick_time + down
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	jump_dive = false
	dive_reach_timer = 0.0
	turbo_active = false
	velocity = Vector3.ZERO
	wall_hit = speed
	fall.start_splat(_to_local(normal), clampf(speed / 12.0, 0.3, 1.0), tuning.wall_splat_stick_time, state_timer)
	# Right up against it, as soon as he is turned flat to it.
	position += normal * (Stadium.wall_distance(tuning, position.x, position.z) + PlayerFall.SPLAT_GAP)
	keep_on_field()
	if animator != null:
		animator.jolt(-normal, 1.2)


func _update_visual(delta: float, instant: bool) -> void:
	var target_yaw: float = atan2(-facing.z, facing.x)
	if instant:
		rotation.y = target_yaw
	elif state == State.SPINNING:
		# One full turn over the spin, ending square to the running line again.
		var turned: float = clampf(1.0 - state_timer / tuning.spin_time, 0.0, 1.0)
		rotation.y = target_yaw + move_side * TAU * turned
	elif flair == Flair.SPIN and flair_timer > 0.0 and state == State.NORMAL:
		# The spinning throw: all the way round and on to face where it went,
		# quickest at the start, as the arm comes through.
		var spun: float = clampf(1.0 - flair_timer / maxf(tuning.flair_time, 0.01), 0.0, 1.0)
		rotation.y = _flair_from + _flair_sweep * (1.0 - (1.0 - spun) * (1.0 - spun))
	elif state != State.DOWN:
		# A player on the turf stays turned the way he fell.
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-18.0 * delta))
	fall.update(self, body, delta, instant)
	if animator != null:
		animator.update(delta, instant)
	_update_daze(delta, instant)
	_update_feet_plant(instant)


## A throw on the run, toward `to` (flat): he throws it spinning right round,
## leaping sideways or fading back off one foot, whichever fits the way he is
## running. `power` (0..1) is how far from set his feet were. Visual only: the
## ball has already gone.
func start_flair(to: Vector3, power: float) -> void:
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	to = to.normalized()
	var run: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var pace: float = run.length()
	var ahead: float = run.dot(to) / pace if pace > 0.5 else 1.0
	var across: float = run.dot(Vector3.UP.cross(to)) / pace if pace > 0.5 else 0.0
	flair_side = 1.0 if across >= 0.0 else -1.0
	if ahead < -0.35:
		flair = Flair.FADE
	elif absf(across) > 0.75:
		flair = Flair.LEAP
	else:
		flair = Flair.SPIN
	flair_power = clampf(power, 0.3, 1.0)
	flair_timer = tuning.flair_time
	_flair_from = rotation.y
	# Round the way he is already turning, and one whole turn more.
	var turn: float = angle_difference(rotation.y, atan2(-to.z, to.x))
	var way: float = signf(turn) if absf(turn) > 0.3 else flair_side
	_flair_sweep = turn + way * TAU


## His feet have just come set under him: he stamps down into his stance, with
## dust at his heels. Visual only.
func feet_planted() -> void:
	if animator != null:
		animator.plant()
	if play != null:
		play.on_feet_planted(self)


## A quarterback who can throw stamps into his stance the moment his feet come
## set. Visual only.
func _update_feet_plant(instant: bool) -> void:
	if instant or play == null or not play.plants_feet(self):
		_feet_were_set = true
		return
	var is_set: bool = feet_set >= 1.0
	if is_set and not _feet_were_set:
		feet_planted()
	_feet_were_set = is_set


## Stars round the head for as long as he is dazed. Visual only.
func _update_daze(delta: float, instant: bool) -> void:
	var dazed: bool = is_dazed() and not instant
	if daze_fx == null:
		if not dazed and not injured:
			return
		daze_fx = DazeFx.new()
		add_child(daze_fx)
	daze_fx.update(self, dazed, dazed_timer, delta, injured)


## Where his head is, in world space.
func head_position() -> Vector3:
	if animator != null:
		return animator.head_position()
	return global_position + Vector3(0.0, body.position.y + 0.75, 0.0)
