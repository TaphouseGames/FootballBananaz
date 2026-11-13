class_name PlayerModel
extends Node3D
## One player's model, built from his PlayerLook on one of the two base models
## (see LookBase): scaled and filled out to his build, skin and jersey painted
## by look_body.gdshader, his face painted by a FacePainter, and hair, nose and
## glasses from LookParts hung on the head bone.
##
## Stands at the origin facing +Z, feet on the ground, as tall as the look
## says in metres. Call show_look() again after any change.
##
## Its skeleton is made ready for PlayerAnimator (see _ready_rig()): upright,
## RIG_HEIGHT tall in its own units, and with a T-pose for its rest, whatever
## pose the base model was sculpted in. Left alone it stands as sculpted.

const BODY_SHADER: Shader = preload("res://assets/player/look_body.gdshader")
const HAIR_SHADER: Shader = preload("res://assets/player/look_hair.gdshader")
const FACE_MAP_SIZE: Vector2i = Vector2i(2048, 1024)
const KIT_MAP_SIZE: Vector2i = Vector2i(512, 512)
## The top quarter of the kit map is the name, the rest the number.
const NAME_ROWS: int = 128
const NAME_FONT_SIZE: int = 92
const NUMBER_FONT_SIZE: int = 300
## How tall the skeleton is in its own units: what PlayerAnimator's
## measurements of a body are made for.
const RIG_HEIGHT: float = 1.85
## The bones of an arm and of a leg, from the body out, on the left. The
## right has R_ for L_.
const ARM_BONES: PackedStringArray = ["L_Upperarm", "L_Forearm", "L_Hand"]
const LEG_BONES: PackedStringArray = ["L_Thigh", "L_Calf", "L_Foot"]
const DARK_PRINT: Color = Color(0.07, 0.08, 0.12)
const LIGHT_PRINT: Color = Color(0.97, 0.97, 0.95)

var look: PlayerLook
var team_color: Color = Color(0.1, 0.3, 0.8)
var number: int = 0
var display_name: String = ""
## The home kit: white, with the team's colour on the sleeves and in the print.
var white_kit: bool = false

## The base model's own scene, and the mesh in it.
var rig: Node3D
var body_mesh: MeshInstance3D
var skeleton: Skeleton3D
var hair: MeshInstance3D
var nose: MeshInstance3D
## The locks of the beard or moustache, over what is painted on the face.
var whiskers: MeshInstance3D
## The hairs of the eyebrows, likewise.
var brows: MeshInstance3D
var glasses: Node3D

var _base: int = -1
var _info: LookBase
var _material: ShaderMaterial
var _hair_material: ShaderMaterial
var _skin_material: StandardMaterial3D
## Follows the head bone; what is under it is in the mesh's own space.
var _head: Node3D
var _face_view: SubViewport
var _painter: FacePainter
var _kit_view: SubViewport
var _name_label: Label
var _number_label: Label
## What the hair, the nose and the glasses were last built from.
var _hair_key: Array = []
var _nose_key: Array = []
var _whiskers_key: Array = []
var _brows_key: Array = []
var _glasses_key: Array = []


func _ready() -> void:
	_face_view = _map_view(FACE_MAP_SIZE)
	_face_view.name = "FaceMap"
	_painter = FacePainter.new()
	_painter.size = Vector2(FACE_MAP_SIZE)
	_face_view.add_child(_painter)

	_kit_view = _map_view(KIT_MAP_SIZE)
	_kit_view.name = "KitMap"
	_name_label = _print_label(Rect2(0.0, 0.0, KIT_MAP_SIZE.x, NAME_ROWS), NAME_FONT_SIZE)
	_number_label = _print_label(Rect2(0.0, NAME_ROWS, KIT_MAP_SIZE.x, KIT_MAP_SIZE.y - NAME_ROWS), NUMBER_FONT_SIZE)

	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter(&"face_tex", _face_view.get_texture())
	_material.set_shader_parameter(&"kit_tex", _kit_view.get_texture())
	_hair_material = ShaderMaterial.new()
	_hair_material.shader = HAIR_SHADER
	_skin_material = StandardMaterial3D.new()
	_skin_material.roughness = 0.85
	_skin_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if look != null:
		refresh()


## Shows `new_look` in the kit of a team whose colour is `color`, with the
## number and the last name of `full_name` on the jersey.
func show_look(new_look: PlayerLook, color: Color, jersey_number: int, full_name: String, home_kit: bool = false) -> void:
	look = new_look
	team_color = color
	number = jersey_number
	display_name = full_name
	white_kit = home_kit
	if is_node_ready():
		refresh()


## Brings the model up to date with `look` and the other values.
func refresh() -> void:
	if look == null:
		return
	if look.base != _base or rig == null:
		_build_rig()
	rig.scale = Vector3.ONE * look.height_m() / RIG_HEIGHT

	var forehead: float = slider_weight(look.forehead_size)
	var chin: float = slider_weight(look.chin_size)
	_set_shape(&"weight", look.heaviness())
	_set_shape(&"forehead", forehead)
	_set_shape(&"chin", chin)

	_material.set_shader_parameter(&"skin_color", look.skin_color)
	_material.set_shader_parameter(&"team_color", team_color)
	_material.set_shader_parameter(&"white_kit", white_kit)
	var print_color: Color = DARK_PRINT if team_color.get_luminance() > 0.5 else LIGHT_PRINT
	if white_kit:
		# On white the print is the team's colour, unless that is too pale to read.
		print_color = team_color if team_color.get_luminance() < 0.6 else DARK_PRINT
	_material.set_shader_parameter(&"text_color", print_color)
	_hair_material.set_shader_parameter(&"hair_color", look.hair_color)
	_hair_material.set_shader_parameter(&"skin_color", look.skin_color)
	_skin_material.albedo_color = look.skin_color

	_painter.show_look(look, _info)
	_face_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var last_name: String = PlayerLook.last_name(display_name)
	var number_text: String = str(number) if number > 0 else ""
	if _name_label.text != last_name or _number_label.text != number_text:
		_name_label.text = last_name
		# A long name is set smaller so it still fits across the shoulders.
		var fitted: int = mini(NAME_FONT_SIZE, int(float(KIT_MAP_SIZE.x) * 1.3 / maxf(float(last_name.length()), 1.0)))
		_name_label.add_theme_font_size_override(&"font_size", fitted)
		_number_label.text = number_text
		_kit_view.render_target_update_mode = SubViewport.UPDATE_ONCE

	var styles: Array = LookParts.HAIR_STYLES[look.base]
	var style: int = styles[clampi(look.hair_style, 0, styles.size() - 1)]
	var hair_key: Array = [look.base, style, forehead, chin]
	hair.set_instance_shader_parameter(&"stubble", 1.0 if style == LookParts.Hair.BUZZ else 0.0)
	hair.set_instance_shader_parameter(&"curls", 1.0 if style == LookParts.Hair.AFRO else 0.0)
	hair.set_instance_shader_parameter(&"shell_depth", LookParts.shell_depth(_info, style))
	if hair_key != _hair_key:
		_hair_key = hair_key
		hair.mesh = LookParts.hair_mesh(_info, style, forehead, chin)
	var facial_hair: int = look.facial_hair if look.base == PlayerLook.Base.MALE else 0
	var whiskers_key: Array = [look.base, facial_hair, forehead, chin]
	if whiskers_key != _whiskers_key:
		_whiskers_key = whiskers_key
		whiskers.mesh = LookParts.facial_hair_mesh(_info, facial_hair, forehead, chin)
		whiskers.set_instance_shader_parameter(&"stubble", 1.0 if facial_hair == 1 else 0.0)
		whiskers.set_instance_shader_parameter(&"shell_depth", LookParts.STUBBLE_DEPTH * _info.half_width if facial_hair == 1 else 0.0)
	var brows_key: Array = [look.base, look.eye_type, forehead, chin]
	if brows_key != _brows_key:
		_brows_key = brows_key
		brows.mesh = LookParts.brow_mesh(_info, look.eye_type, forehead, chin)
	var nose_scale: float = lerpf(0.6, 1.5, look.nose_size)
	var nose_key: Array = [look.base, look.nose_type, nose_scale]
	if nose_key != _nose_key:
		_nose_key = nose_key
		nose.mesh = LookParts.nose_mesh(_info, look.nose_type, nose_scale)
	var glasses_key: Array = [look.base, look.glasses]
	if glasses_key != _glasses_key:
		_glasses_key = glasses_key
		if glasses != null:
			_head.remove_child(glasses)
			glasses.queue_free()
			glasses = null
		if look.glasses == PlayerLook.Glasses.NERDY or look.glasses == PlayerLook.Glasses.SUNGLASSES:
			glasses = LookParts.glasses(_info, look.glasses == PlayerLook.Glasses.SUNGLASSES)
			_head.add_child(glasses)


## How high the middle of the head is above the ground, in metres.
func head_height() -> float:
	if _info == null or look == null:
		return 1.6
	var forehead: float = maxf(slider_weight(look.forehead_size), 0.0)
	var top: float = _info.top_z + (_info.top_z - _info.chin_z) * LookBase.FOREHEAD_RISE * forehead
	return (_info.chin_z + top) / 2.0 * look.height_m()


## The blend weight of a 0..1 size slider: 0 in the middle, 1 at the top, and
## not as far the other way, where a feature can only shrink so much.
static func slider_weight(value: float) -> float:
	return (value - 0.5) * (2.0 if value > 0.5 else 1.2)


func _set_shape(shape: StringName, value: float) -> void:
	var index: int = body_mesh.find_blend_shape_by_name(shape)
	if index >= 0:
		body_mesh.set_blend_shape_value(index, value)


## Swaps the base model in: its scene with the baked mesh and the body
## material, and on its head bone the places for hair, nose and glasses.
func _build_rig() -> void:
	if rig != null:
		remove_child(rig)
		rig.queue_free()
	_base = look.base
	_info = LookBase.of(_base)
	_hair_key = []
	_nose_key = []
	_whiskers_key = []
	_brows_key = []
	_glasses_key = []
	glasses = null
	rig = _info.scene.instantiate() as Node3D
	rig.name = "Rig"
	add_child(rig)
	body_mesh = rig.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	skeleton = body_mesh.get_parent() as Skeleton3D
	body_mesh.mesh = _info.mesh
	body_mesh.material_override = _material
	_material.set_shader_parameter(&"albedo_tex", _info.albedo)
	_material.set_shader_parameter(&"normal_tex", _info.normal_map)
	_material.set_shader_parameter(&"head_map", Vector3(_info.axis_y, _info.map_low_z, _info.top_z))
	_material.set_shader_parameter(&"chin_z", _info.chin_z)
	_material.set_shader_parameter(&"belt_z", LookBase.BELT_Z[_base])
	_material.set_shader_parameter(&"front_number", LookBase.FRONT_NUMBER[_base])
	_material.set_shader_parameter(&"back_number", LookBase.BACK_NUMBER[_base])
	_material.set_shader_parameter(&"back_name", LookBase.BACK_NAME[_base])

	var from_mesh: Transform3D = _ready_rig()
	var bone: int = skeleton.find_bone("Head")
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.name = "HeadAttachment"
	skeleton.add_child(attachment)
	attachment.bone_name = "Head"
	_head = Node3D.new()
	_head.name = "HeadParts"
	_head.transform = skeleton.get_bone_global_rest(bone).affine_inverse() * from_mesh
	attachment.add_child(_head)
	hair = MeshInstance3D.new()
	hair.name = "Hair"
	hair.material_override = _hair_material
	_head.add_child(hair)
	whiskers = MeshInstance3D.new()
	whiskers.name = "Whiskers"
	whiskers.material_override = _hair_material
	_head.add_child(whiskers)
	brows = MeshInstance3D.new()
	brows.name = "Brows"
	brows.material_override = _hair_material
	_head.add_child(brows)
	nose = MeshInstance3D.new()
	nose.name = "Nose"
	nose.material_override = _skin_material
	_head.add_child(nose)


## Makes the base model's skeleton the one PlayerAnimator works with, and
## returns what takes a place in the mesh's own space into the skeleton's.
## The base models are sculpted lying in a space with z up, 1 tall, arms half
## lowered. Here the skeleton is stood up (y up, facing +z) and grown to
## RIG_HEIGHT at its root bones, and the rest of each arm and leg is turned
## to a T-pose: arms straight out, legs straight down. Only the rest moves,
## which is what an animator measures its angles from; the pose stays as
## sculpted until something poses it.
func _ready_rig() -> Transform3D:
	var armature: Node3D = skeleton.get_parent() as Node3D
	var upright: Basis = armature.transform.basis.orthonormalized()
	armature.transform = Transform3D.IDENTITY
	var from_mesh: Transform3D = Transform3D(upright.scaled(Vector3.ONE * RIG_HEIGHT), Vector3.ZERO)
	for root: int in skeleton.get_parentless_bones():
		skeleton.set_bone_rest(root, from_mesh * skeleton.get_bone_rest(root))
		skeleton.reset_bone_pose(root)
	for side: String in ["L_", "R_"]:
		var out: Vector3 = Vector3.RIGHT if side == "L_" else Vector3.LEFT
		_straighten(ARM_BONES, side, out)
		_straighten(LEG_BONES, side, Vector3.DOWN)
	return from_mesh


## Turns the rest of each of `bones` but the last (named for the left; `side`
## is the prefix they have on this one) so the next lies `toward` from it.
func _straighten(bones: PackedStringArray, side: String, toward: Vector3) -> void:
	for k: int in bones.size() - 1:
		var bone: int = skeleton.find_bone(bones[k].replace("L_", side))
		var next: int = skeleton.find_bone(bones[k + 1].replace("L_", side))
		if bone < 0 or next < 0:
			continue
		var global: Transform3D = skeleton.get_bone_global_rest(bone)
		var lies: Vector3 = (skeleton.get_bone_global_rest(next).origin - global.origin).normalized()
		var parent: int = skeleton.get_bone_parent(bone)
		var parent_basis: Basis = skeleton.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		rest.basis = parent_basis.inverse() * (Basis(Quaternion(lies, toward)) * global.basis)
		skeleton.set_bone_rest(bone, rest)


## A viewport that is drawn to once whenever what is in it changes, clear
## where nothing is drawn.
func _map_view(map_size: Vector2i) -> SubViewport:
	var view: SubViewport = SubViewport.new()
	view.size = map_size
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	return view


func _print_label(box: Rect2, font_size: int) -> Label:
	var label: Label = Label.new()
	label.position = box.position
	label.size = box.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	# The outline makes block letters of the editor's thin font.
	label.add_theme_color_override(&"font_outline_color", Color.WHITE)
	label.add_theme_constant_override(&"outline_size", 14)
	_kit_view.add_child(label)
	return label
