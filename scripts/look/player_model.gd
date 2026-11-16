class_name PlayerModel
extends Node3D
## One player's model: a uniform body (see KitBase) dressed in his team's kit
## by kit_body.gdshader, with his number front and back and his name across
## the shoulders, and a head model on its head bone.
##
## Which body and which head come from his PlayerLook (see PlayerParts).
##
## Stands at the origin facing +Z, feet on the ground, as tall as the look
## says in metres. Call show_look() again after any change.
##
## Its skeleton is made ready for PlayerAnimator (see _ready_rig()): upright,
## RIG_HEIGHT tall in its own units, and with a T-pose for its rest, whatever
## pose the body was modelled in. Left alone it stands as modelled.

const BODY_SHADER: Shader = preload("res://assets/player/kit_body.gdshader")
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

## The body's own scene, and the mesh in it.
var rig: Node3D
var body_mesh: MeshInstance3D
var skeleton: Skeleton3D
var head: MeshInstance3D

var _info: KitBase
## The body and the head the rig was last built from.
var _body_id: String = ""
var _head_id: String = ""
var _material: ShaderMaterial
var _kit_view: SubViewport
var _name_label: Label
var _number_label: Label


func _ready() -> void:
	_kit_view = SubViewport.new()
	_kit_view.name = "KitMap"
	_kit_view.size = KIT_MAP_SIZE
	_kit_view.transparent_bg = true
	_kit_view.disable_3d = true
	_kit_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_kit_view)
	_name_label = _print_label(Rect2(0.0, 0.0, KIT_MAP_SIZE.x, NAME_ROWS), NAME_FONT_SIZE)
	_number_label = _print_label(Rect2(0.0, NAME_ROWS, KIT_MAP_SIZE.x, KIT_MAP_SIZE.y - NAME_ROWS), NUMBER_FONT_SIZE)

	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter(&"kit_tex", _kit_view.get_texture())
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
	if rig == null or look.body_id() != _body_id or look.head_id() != _head_id:
		_build_rig()
	rig.scale = Vector3.ONE * look.height_m() * _info.body_scale / RIG_HEIGHT

	_material.set_shader_parameter(&"team_color", team_color)
	_material.set_shader_parameter(&"white_kit", white_kit)
	var print_color: Color = DARK_PRINT if team_color.get_luminance() > 0.5 else LIGHT_PRINT
	if white_kit:
		# On white the print is the team's colour, unless that is too pale to read.
		print_color = team_color if team_color.get_luminance() < 0.6 else DARK_PRINT
	_material.set_shader_parameter(&"text_color", print_color)

	var last_name: String = PlayerLook.last_name(display_name)
	var number_text: String = str(number) if number > 0 else ""
	if _name_label.text != last_name or _number_label.text != number_text:
		_name_label.text = last_name
		# A long name is set smaller so it still fits across the shoulders.
		var fitted: int = mini(NAME_FONT_SIZE, int(float(KIT_MAP_SIZE.x) * 1.3 / maxf(float(last_name.length()), 1.0)))
		_name_label.add_theme_font_size_override(&"font_size", fitted)
		_number_label.text = number_text
		_kit_view.render_target_update_mode = SubViewport.UPDATE_ONCE


## How high the middle of the head is above the ground, in metres.
func head_height() -> float:
	if _info == null or look == null:
		return 1.6
	return _info.head_middle_z(_head_id) / _info.top_z(_head_id) * look.height_m() * _info.body_scale


## Puts the body in: its scene with the baked mesh and the kit material, and
## the head on its head bone.
func _build_rig() -> void:
	if rig != null:
		remove_child(rig)
		rig.queue_free()
	_body_id = look.body_id()
	_head_id = look.head_id()
	_info = KitBase.of(_body_id)
	rig = _info.scene.instantiate() as Node3D
	rig.name = "Rig"
	add_child(rig)
	body_mesh = rig.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	skeleton = body_mesh.get_parent() as Skeleton3D
	body_mesh.mesh = _info.mesh
	body_mesh.material_override = _material
	_material.set_shader_parameter(&"albedo_tex", _info.albedo)
	_material.set_shader_parameter(&"normal_tex", _info.normal_map)
	_material.set_shader_parameter(&"belt_z", _info.belt_z)
	_material.set_shader_parameter(&"hem_z", _info.hem_z)
	_material.set_shader_parameter(&"boot_z", _info.boot_z)
	_material.set_shader_parameter(&"front_number", _info.front_number)
	_material.set_shader_parameter(&"back_number", _info.back_number)
	_material.set_shader_parameter(&"back_name", _info.back_name)

	var from_mesh: Transform3D = _ready_rig()
	var bone: int = skeleton.find_bone("Head")
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.name = "HeadAttachment"
	skeleton.add_child(attachment)
	attachment.bone_name = "Head"
	head = MeshInstance3D.new()
	head.name = "Head"
	head.mesh = _info.head_mesh(_head_id)
	# The head's mesh is in the body's own space: from there to the head bone's.
	head.transform = skeleton.get_bone_global_rest(bone).affine_inverse() * from_mesh
	attachment.add_child(head)


## Makes the body's skeleton the one PlayerAnimator works with, and returns
## what takes a place in the mesh's own space into the skeleton's.
## The body is modelled lying in a space with z up. Here the skeleton is stood
## up (y up, facing +z) and grown at its root bones so that the player, head
## and all, is RIG_HEIGHT tall, and the rest of each arm and leg is turned to
## a T-pose: arms straight out, legs straight down. Only the rest moves, which
## is what an animator measures its angles from; the pose stays as modelled
## until something poses it.
func _ready_rig() -> Transform3D:
	var armature: Node3D = skeleton.get_parent() as Node3D
	var upright: Basis = armature.transform.basis.orthonormalized()
	armature.transform = Transform3D.IDENTITY
	var from_mesh: Transform3D = Transform3D(upright.scaled(Vector3.ONE * RIG_HEIGHT / _info.top_z(_head_id)), Vector3.ZERO)
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
