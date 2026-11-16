extends SceneTree
## Trial of a new uniform body (white all over, headless) with a head model on
## it, dressed by assets/player/kit_body.gdshader: pictures of it as delivered,
## in away and home kits, and bent into a running pose, from four sides.
## Nothing of the game uses this yet. Needs a window (no --headless).
##
## Run:  godot --path . --script res://tests/base_proof.gd -- out=<folder>
## Optional user args after "--":
##   describe       only prints what the models are made of (works headless)
##   head=<n>       which of HEADS goes on the body

const BODY: String = "res://TripoModels/player_body_male_athletic/player_body_male_athletic.fbx"
const HEADS: PackedStringArray = [
	"res://TripoModels/crowd_head_m5_brown_beard/crowd_head_m5_brown_beard.fbx",
	"res://TripoModels/crowd_head_m8_grey_beard/crowd_head_m8_grey_beard.fbx",
	"res://TripoModels/crowd_head_m11_blond_grin/crowd_head_m11_blond_grin.fbx",
	"res://TripoModels/player_head_dash_plantain/player_head_dash_plantain.fbx",
]
## Per head: how far forward it is moved and how many degrees it is tipped back
## round its neck. The crowd's heads are modelled with the chin pushed forward.
const HEAD_FORWARD: PackedFloat32Array = [0.05, 0.05, 0.05, 0.058]
## Per head: how tall the model is (neck and all) in the body's units, and how
## far below the top of the collar its neck line sits.
const HEAD_SIZES: PackedFloat32Array = [0.27, 0.27, 0.27, 0.3]
const NECK_SINKS: PackedFloat32Array = [0.04, 0.04, 0.04, 0.05]
const HEAD_TILTS: PackedFloat32Array = [6.0, 6.0, 6.0, 0.0]
const SHADER: Shader = preload("res://assets/player/kit_body.gdshader")
## How tall the head model is (neck and all) in the body's units, how far up it
## its neck line is, and how far below the top of the collar that line sits.
const HEAD_NECK: float = 0.15
const PLAYER_HEIGHT: float = 1.85
const KIT_MAP_SIZE: Vector2i = Vector2i(512, 512)
const NAME_ROWS: int = 128

var _out_dir: String = "user://base_proof"
var _head: int = 0
var _view: SubViewport
var _cam: Camera3D


func _initialize() -> void:
	var describe: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("head="):
			_head = int(arg.trim_prefix("head="))
		elif arg == "describe":
			describe = true
	if describe:
		_describe(BODY)
		for path: String in HEADS:
			_describe(path)
		quit()
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.34, 0.4, 0.46)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.55
	_view.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	_view.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_view.add_child(_cam)
	_run()


func _run() -> void:
	await process_frame
	# What each is: plain, the team's colour, the home kit, posed, number, name.
	var kits: Array[Array] = [
		[true, Color.WHITE, false, false, 0, ""],
		[false, Color(0.1, 0.3, 0.8), false, false, 12, "Banana"],
		[false, Color(0.1, 0.3, 0.8), true, false, 12, "Banana"],
		[false, Color(0.98, 0.8, 0.1), false, false, 7, "Longfellow"],
		[false, Color(0.6, 0.1, 0.5), false, true, 88, "Ox"],
		[false, Color(0.1, 0.5, 0.25), true, true, 34, "Peachtree"],
	]
	const SPACING: float = 2.0
	const TALL: float = 2.2
	const ROW_PX: int = 760
	var cell_px: int = roundi(SPACING / TALL * float(ROW_PX))
	_view.size = Vector2i(cell_px * kits.size(), ROW_PX)
	_cam.size = TALL
	var models: Array[Node3D] = []
	for i: int in kits.size():
		var kit: Array = kits[i]
		var model: Node3D = _model(kit[0], kit[1], kit[2], kit[3], kit[4], kit[5])
		model.position.x = (float(i) - float(kits.size() - 1) / 2.0) * SPACING
		models.append(model)
	_cam.look_at_from_position(Vector3(0.0, TALL / 2.0 - 0.1, 10.0), Vector3(0.0, TALL / 2.0 - 0.1, 0.0))
	const TURNS: PackedFloat32Array = [0.0, 0.7, 1.5708, 3.14159]
	var picture: Image = Image.create_empty(_view.size.x, ROW_PX * TURNS.size(), false, Image.FORMAT_RGBA8)
	for row: int in TURNS.size():
		for model: Node3D in models:
			model.rotation.y = TURNS[row]
		for frame: int in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot: Image = _view.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		picture.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(0, row * ROW_PX))
	picture.save_png(_out_dir.path_join("base_proof.png"))

	# The head and shoulders close up, front and side.
	_view.size = Vector2i(1500, 700)
	_cam.size = 0.9
	for i: int in models.size():
		models[i].visible = i >= 1 and i <= 3
		models[i].position.x = float(i - 2) * 0.95
	_cam.look_at_from_position(Vector3(0.0, 1.5, 10.0), Vector3(0.0, 1.5, 0.0))
	var turns: PackedFloat32Array = [0.0, 1.5708, 3.14159]
	for i: int in 3:
		models[i + 1].rotation.y = turns[i]
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(_out_dir.path_join("base_proof_close.png"))
	# The legs close up, the same three.
	_cam.look_at_from_position(Vector3(0.0, 0.45, 10.0), Vector3(0.0, 0.45, 0.0))
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(_out_dir.path_join("base_proof_legs.png"))
	print("saved to ", ProjectSettings.globalize_path(_out_dir))
	quit()


## The body with the head on it, standing at the origin facing +Z,
## PLAYER_HEIGHT tall to the top of the head.
func _model(plain: bool, team_color: Color, white_kit: bool, posed: bool, number: int, last_name: String) -> Node3D:
	var holder: Node3D = Node3D.new()
	_view.add_child(holder)
	var rig: Node3D = (load(BODY) as PackedScene).instantiate() as Node3D
	holder.add_child(rig)
	var body: MeshInstance3D = rig.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skeleton: Skeleton3D = body.get_parent() as Skeleton3D
	var source: ArrayMesh = body.mesh as ArrayMesh
	var painted: BaseMaterial3D = source.surface_get_material(0) as BaseMaterial3D
	var baked: Dictionary = _bake(body, skeleton)
	body.mesh = baked["mesh"]

	var kit_view: SubViewport = SubViewport.new()
	kit_view.size = KIT_MAP_SIZE
	kit_view.transparent_bg = true
	kit_view.disable_3d = true
	kit_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	holder.add_child(kit_view)
	var name_label: Label = _print_label(kit_view, Rect2(0.0, 0.0, KIT_MAP_SIZE.x, NAME_ROWS), 92)
	name_label.text = last_name.to_upper()
	name_label.add_theme_font_size_override(&"font_size", mini(92, int(float(KIT_MAP_SIZE.x) * 1.3 / maxf(float(last_name.length()), 1.0))))
	var number_label: Label = _print_label(kit_view, Rect2(0.0, NAME_ROWS, KIT_MAP_SIZE.x, KIT_MAP_SIZE.y - NAME_ROWS), 300)
	number_label.text = str(number) if number > 0 else ""

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"albedo_tex", painted.albedo_texture)
	material.set_shader_parameter(&"normal_tex", painted.normal_texture)
	material.set_shader_parameter(&"kit_tex", kit_view.get_texture())
	material.set_shader_parameter(&"plain", plain)
	material.set_shader_parameter(&"team_color", team_color)
	material.set_shader_parameter(&"white_kit", white_kit)
	var print_color: Color = Color(0.07, 0.08, 0.12) if team_color.get_luminance() > 0.5 else Color(0.97, 0.97, 0.95)
	if white_kit:
		print_color = team_color if team_color.get_luminance() < 0.6 else Color(0.07, 0.08, 0.12)
	material.set_shader_parameter(&"text_color", print_color)
	body.material_override = material

	# The head: its neck line a little inside the collar, over the collar's middle.
	var head_scene: Node3D = (load(HEADS[_head]) as PackedScene).instantiate() as Node3D
	var head_source: MeshInstance3D = head_scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var head_mesh: Mesh = head_source.mesh
	head_scene.free()
	var collar: Vector3 = baked["collar"]
	var neck: Vector3 = _neck_middle(head_mesh)
	var head_basis: Basis = Basis(Vector3.RIGHT, deg_to_rad(-HEAD_TILTS[_head])).scaled(Vector3.ONE * HEAD_SIZES[_head])
	var at: Vector3 = Vector3(collar.x, collar.y, collar.z - NECK_SINKS[_head]) + Vector3(0.0, -HEAD_FORWARD[_head], 0.0) - head_basis * neck
	var in_mesh: Transform3D = Transform3D(head_basis, at)
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	skeleton.add_child(attachment)
	attachment.bone_name = "Head"
	var head: MeshInstance3D = MeshInstance3D.new()
	head.mesh = head_mesh
	head.transform = skeleton.get_bone_global_rest(skeleton.find_bone("Head")).affine_inverse() * in_mesh
	attachment.add_child(head)

	var top: float = at.z + HEAD_SIZES[_head]
	rig.scale = Vector3.ONE * PLAYER_HEIGHT / top
	if posed:
		_pose(skeleton)
	return holder


## The body's mesh with what the shader reads baked in (see kit_body.gdshader),
## and the middle of the top of its collar.
func _bake(body: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var source: ArrayMesh = body.mesh as ArrayMesh
	var skin: Skin = body.skin
	var worth: Array[Color] = []
	for bind: int in skin.get_bind_count():
		var bone: String = skin.get_bind_name(bind)
		if bone == "":
			bone = skeleton.get_bone_name(skin.get_bind_bone(bind))
		worth.append(_bone_worth(bone))
	var arrays: Array = source.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count: int = points.size()
	@warning_ignore("integer_division")
	var per: int = bones.size() / count
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(count)
	var custom: PackedFloat32Array = PackedFloat32Array()
	custom.resize(count * 4)
	var top: float = -INF
	for point: Vector3 in points:
		top = maxf(top, point.z)
	var collar: Vector3 = Vector3.ZERO
	var collar_count: int = 0
	for i: int in count:
		var share: Color = Color(0.0, 0.0, 0.0, 0.0)
		for k: int in per:
			share += worth[bones[i * per + k]] * weights[i * per + k]
		colors[i] = share
		custom[i * 4] = points[i].x
		custom[i * 4 + 1] = points[i].y
		custom[i * 4 + 2] = points[i].z
		custom[i * 4 + 3] = normals[i].y
		if points[i].z > top - 0.012:
			collar += points[i]
			collar_count += 1
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var mesh: ArrayMesh = ArrayMesh.new()
	var format: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	format |= source.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
	collar /= float(maxi(collar_count, 1))
	collar.z = top
	return {"mesh": mesh, "collar": collar}


## What a bone is to the shader: r head or neck, g hand, b arm, a foot.
func _bone_worth(bone: String) -> Color:
	for finger: String in ["Hand", "Pinky", "Ring", "Mid", "Index", "Thumb"]:
		if bone.contains(finger):
			return Color(0.0, 1.0, 0.0, 0.0)
	if bone.contains("Head") or bone.contains("Facial") or bone.contains("Eye") or bone.contains("Neck"):
		return Color(1.0, 0.0, 0.0, 0.0)
	if bone.contains("Upperarm") or bone.contains("Forearm") or bone.contains("Elbow"):
		return Color(0.0, 0.0, 1.0, 0.0)
	if bone.contains("Foot") or bone.contains("Toe"):
		return Color(0.0, 0.0, 0.0, 1.0)
	return Color(0.0, 0.0, 0.0, 0.0)


## The middle of a head model's neck, in its own space (z up, 1 tall).
func _neck_middle(mesh: Mesh) -> Vector3:
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low: float = INF
	var high: float = -INF
	for point: Vector3 in points:
		low = minf(low, point.z)
		high = maxf(high, point.z)
	var line: float = low + (high - low) * HEAD_NECK
	var sum: Vector3 = Vector3.ZERO
	var count: int = 0
	for point: Vector3 in points:
		if absf(point.z - line) < 0.05:
			sum += point
			count += 1
	var middle: Vector3 = sum / float(maxi(count, 1))
	return Vector3(middle.x, middle.y, line)


## A running pose, to see how the body bends. The skeleton's own space: x the
## player's left, y back, z up.
func _pose(skeleton: Skeleton3D) -> void:
	_turn(skeleton, "Spine01", Vector3.RIGHT, -12.0)
	_turn(skeleton, "L_Upperarm", Vector3.UP, 72.0)
	_turn(skeleton, "L_Upperarm", Vector3.RIGHT, -35.0)
	_turn(skeleton, "L_Forearm", Vector3.RIGHT, -80.0)
	_turn(skeleton, "R_Upperarm", Vector3.UP, -72.0)
	_turn(skeleton, "R_Upperarm", Vector3.RIGHT, 40.0)
	_turn(skeleton, "R_Forearm", Vector3.RIGHT, -70.0)
	_turn(skeleton, "L_Thigh", Vector3.RIGHT, 30.0)
	_turn(skeleton, "L_Calf", Vector3.RIGHT, 55.0)
	_turn(skeleton, "R_Thigh", Vector3.RIGHT, -60.0)
	_turn(skeleton, "R_Calf", Vector3.RIGHT, 75.0)


## Turns a bone, and all that hangs on it, round `axis` of the skeleton's space.
func _turn(skeleton: Skeleton3D, bone_name: String, axis: Vector3, degrees: float) -> void:
	var bone: int = skeleton.find_bone(bone_name)
	var pose: Transform3D = skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(axis, deg_to_rad(degrees)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)


func _print_label(view: SubViewport, box: Rect2, font_size: int) -> Label:
	var label: Label = Label.new()
	label.position = box.position
	label.size = box.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_outline_color", Color.WHITE)
	label.add_theme_constant_override(&"outline_size", 14)
	view.add_child(label)
	return label


func _describe(path: String) -> void:
	print("=== ", path)
	var root_node: Node = (load(path) as PackedScene).instantiate()
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: ArrayMesh = (node as MeshInstance3D).mesh as ArrayMesh
		var arrays: Array = mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		@warning_ignore("integer_division")
		print("  ", points.size(), " vertices, ", indices.size() / 3, " triangles, aabb ", mesh.get_aabb())
	for node: Node in root_node.find_children("*", "Skeleton3D", true, false):
		var skeleton: Skeleton3D = node as Skeleton3D
		print("  skeleton: ", skeleton.get_bone_count(), " bones")
		for bone: int in skeleton.get_bone_count():
			var parent: int = skeleton.get_bone_parent(bone)
			var at: Vector3 = skeleton.get_bone_global_rest(bone).origin
			print("    %s <- %s  (%.3f, %.3f, %.3f)" % [skeleton.get_bone_name(bone), skeleton.get_bone_name(parent) if parent >= 0 else "-", at.x, at.y, at.z])
	root_node.free()
