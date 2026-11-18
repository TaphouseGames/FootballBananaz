class_name PlayerModel
extends Node3D
## One player's model: a uniform body (see KitBase) dressed in his team's kit
## by kit_body.gdshader, with his number front and back and his name across
## the shoulders, and a head model on its head bone.
##
## Which body and which head come from his PlayerLook (see PlayerParts). A
## look that names a person (PlayerParts.PEOPLE) is that whole character
## instead, dressed by kit_person.gdshader, and has no separate head.
##
## Stands at the origin facing +Z, feet on the ground, as tall as the look
## says in metres. Call show_look() again after any change.
##
## Its skeleton is made ready for PlayerAnimator (see _ready_rig()): upright,
## RIG_HEIGHT tall in its own units, and with a T-pose for its rest, whatever
## pose the body was modelled in. Left alone it stands as modelled.

const BODY_SHADER: Shader = preload("res://assets/player/kit_body.gdshader")
const PERSON_SHADER: Shader = preload("res://assets/player/kit_person.gdshader")
const KIT_MAP_SIZE: Vector2i = Vector2i(512, 512)
## The top quarter of the kit map is the name, the rest the number.
const NAME_ROWS: int = 128
const NAME_FONT_SIZE: int = 118
const NUMBER_FONT_SIZE: int = 325
## The print is in college block letters. A number is a solid figure with a
## line round it: the figure, a gap this wide (the jersey shows through) and
## an outline as far out as NUMBER_OUTLINE, in pixels of the kit map.
const PRINT_FONT: FontFile = preload("res://assets/fonts/Graduate-Regular.ttf")
const PRINT_EMBOLDEN: float = 1.1
const NUMBER_GAP: int = 22
## The print on a whole character is the same size on everybody, whatever the
## size of the body: half the width and half the height, in metres, of the
## number on the chest, the number on the back and the name. (Each has the
## shape of its part of the kit map.)
const PRINT_FRONT: Vector2 = Vector2(0.2, 0.15)
const PRINT_BACK: Vector2 = Vector2(0.215, 0.161)
const PRINT_NAME: Vector2 = Vector2(0.225, 0.056)
const NUMBER_OUTLINE: int = 40
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
var _person_id: String = ""
var _material: ShaderMaterial
var _kit_view: SubViewport
var _name_label: Label
## The layers of the number, from the back: outline, gap, figure.
var _number_labels: Array[Label] = []
var _print_font: FontVariation
## How many times the kit map has been asked for: only the last copy is used.
var _kit_bakes: int = 0


func _ready() -> void:
	_kit_view = SubViewport.new()
	_kit_view.name = "KitMap"
	_kit_view.size = KIT_MAP_SIZE
	# Ink is white on black: with no clear texels in it, the map's mipmaps are
	# exactly how much ink there is in an area.
	_kit_view.transparent_bg = false
	_kit_view.disable_3d = true
	_kit_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_kit_view)
	var paper: ColorRect = ColorRect.new()
	paper.color = Color.BLACK
	paper.size = Vector2(KIT_MAP_SIZE)
	_kit_view.add_child(paper)
	_print_font = FontVariation.new()
	_print_font.base_font = PRINT_FONT
	_print_font.variation_embolden = PRINT_EMBOLDEN
	_name_label = _print_label(Rect2(0.0, 0.0, KIT_MAP_SIZE.x, NAME_ROWS), NAME_FONT_SIZE, Color.WHITE, 0)
	var number_box: Rect2 = Rect2(0.0, NAME_ROWS, KIT_MAP_SIZE.x, KIT_MAP_SIZE.y - NAME_ROWS)
	_number_labels = [
		_print_label(number_box, NUMBER_FONT_SIZE, Color.WHITE, NUMBER_OUTLINE),
		_print_label(number_box, NUMBER_FONT_SIZE, Color.BLACK, NUMBER_GAP),
		_print_label(number_box, NUMBER_FONT_SIZE, Color.WHITE, 0),
	]

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
	if rig == null or look.body_id() != _body_id or look.head_id() != _head_id or look.person_id() != _person_id:
		_build_rig()
	rig.scale = Vector3.ONE * look.height_m() * _info.body_scale / RIG_HEIGHT
	if _info.is_person:
		# What a metre is in the body's own units, at the height this player has.
		var metre: float = _info.top_z(_head_id) / (look.height_m() * _info.body_scale)
		var back_z: float = _info.back_number.x
		_material.set_shader_parameter(&"front_number", Vector3(_info.front_number.x, PRINT_FRONT.x * metre, PRINT_FRONT.y * metre))
		_material.set_shader_parameter(&"back_number", Vector3(back_z, PRINT_BACK.x * metre, PRINT_BACK.y * metre))
		_material.set_shader_parameter(&"back_name", Vector3(back_z + (PRINT_BACK.y + PRINT_NAME.y * 0.75) * metre, PRINT_NAME.x * metre, PRINT_NAME.y * metre))

	_material.set_shader_parameter(&"team_color", team_color)
	_material.set_shader_parameter(&"white_kit", white_kit)
	var print_color: Color = DARK_PRINT if team_color.get_luminance() > 0.5 else LIGHT_PRINT
	if white_kit:
		# On white the print is the team's colour, unless that is too pale to read.
		print_color = team_color if team_color.get_luminance() < 0.6 else DARK_PRINT
	_material.set_shader_parameter(&"text_color", print_color)

	var last_name: String = PlayerLook.last_name(display_name)
	var number_text: String = str(number) if number > 0 else ""
	if _name_label.text != last_name or _number_labels[0].text != number_text:
		_name_label.text = last_name
		# A long name is set smaller so it still fits across the shoulders.
		var fitted: int = mini(NAME_FONT_SIZE, int(float(KIT_MAP_SIZE.x) * 1.27 / maxf(float(last_name.length()), 1.0)))
		_name_label.add_theme_font_size_override(&"font_size", fitted)
		for label: Label in _number_labels:
			label.text = number_text
		_kit_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		_bake_kit_map()


## Gives the material a copy of the kit map that has mipmaps, once the map has
## been drawn. A viewport's own texture has none, and print sampled without
## them breaks up on a player far from the camera: the thin lines of a number's
## outline most of all. Until the copy is there (and where nothing is drawn at
## all, as when run headless) the material reads the viewport itself.
func _bake_kit_map() -> void:
	_kit_bakes += 1
	var bake: int = _kit_bakes
	_material.set_shader_parameter(&"kit_tex", _kit_view.get_texture())
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if bake != _kit_bakes or not is_inside_tree():
		return
	var image: Image = _kit_view.get_texture().get_image()
	if image == null or image.is_empty():
		return
	image.generate_mipmaps()
	_material.set_shader_parameter(&"kit_tex", ImageTexture.create_from_image(image))


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
	_person_id = look.person_id()
	head = null
	_info = KitBase.of(_body_id) if _person_id == "" else KitBase.of_person(_person_id)
	_material.shader = PERSON_SHADER if _info.is_person else BODY_SHADER
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
	if _info.is_person:
		_material.set_shader_parameter(&"rough_tex", _info.roughness_map)
		_material.set_shader_parameter(&"mask_tex", _info.mask)
		return
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


## A label of the kit map in `color`, with an outline of it `outline` wide.
func _print_label(box: Rect2, font_size: int, color: Color, outline: int) -> Label:
	var label: Label = Label.new()
	label.position = box.position
	label.size = box.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override(&"font", _print_font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", color)
	label.add_theme_constant_override(&"outline_size", outline)
	_kit_view.add_child(label)
	return label
