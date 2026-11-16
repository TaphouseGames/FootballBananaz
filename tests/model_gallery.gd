extends SceneTree
## Pictures of the player models PlayerModel builds from the bodies and heads
## in PlayerParts, from in front, a quarter turned, the side and behind:
##   body_<id>.png   one body in away and home kits, short and tall, with long
##                   and short names
##   heads_<gender>.png   every head of a gender close up, on the first body
##                   of that gender
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/model_gallery.gd -- out=<folder>
## Optional user args after "--":
##   only=<text>      only the sheets whose name contains the text
##   build=<build>    the body the heads sheet puts the heads on (athletic)
##   describe=<path>  no pictures: prints what the model at a res:// path is
##                    made of (triangles, size, bones). Works headless.

## The bones a body must have: what KitBase and PlayerAnimator go by.
const BODY_BONES: PackedStringArray = [
	"Hip", "Waist", "Spine02", "NeckTwist01", "Head",
	"L_Upperarm", "L_Forearm", "L_Hand", "R_Upperarm", "R_Forearm", "R_Hand",
	"L_Thigh", "L_Calf", "L_Foot", "R_Thigh", "R_Calf", "R_Foot",
]

var _out_dir: String = "user://model_gallery"
var _only: String = ""
var _heads_build: int = PlayerLook.Build.ATHLETIC
var _cam: Camera3D
var _view: SubViewport
var _models: Array[PlayerModel] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("only="):
			_only = arg.trim_prefix("only=")
		elif arg.begins_with("build="):
			_heads_build = maxi(PlayerParts.BUILDS.find(arg.trim_prefix("build=")), 0)
		elif arg.begins_with("describe="):
			_describe(arg.trim_prefix("describe="))
			quit()
			return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# Off screen, so a picture can be wider than the window.
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
	for gender: int in PlayerParts.GENDERS.size():
		for build: int in PlayerParts.BUILDS.size():
			if not PlayerParts.has_body(gender, build):
				continue
			var looks: Array[PlayerLook] = []
			for height: int in [64, 70, 72, 72, 76, 82]:
				looks.append(_look(gender, build, "", height))
			await _sheet("body_%s" % PlayerParts.body_id(gender, build), looks, false)
		var heads: PackedStringArray = PlayerParts.heads_of(gender)
		if heads.is_empty():
			continue
		var faces: Array[PlayerLook] = []
		for head: String in heads:
			faces.append(_look(gender, _heads_build, head, 72))
		await _sheet("heads_%s" % PlayerParts.GENDERS[gender], faces, true)
	print("model gallery saved to ", ProjectSettings.globalize_path(_out_dir))
	quit()


func _look(gender: int, build: int, head: String, height: int) -> PlayerLook:
	var look: PlayerLook = PlayerLook.new()
	look.gender = gender as PlayerLook.Gender
	look.build = build as PlayerLook.Build
	look.head = head
	look.height_in = height
	return look


## One picture of `looks` side by side, a row for each side they are seen
## from: in front, a quarter turned, the side, from behind at an angle and behind. Of the head
## (`close`) or of the whole body.
func _sheet(sheet: String, looks: Array[PlayerLook], close: bool) -> void:
	if _only != "" and not sheet.contains(_only):
		return
	for model: PlayerModel in _models:
		model.queue_free()
	_models.clear()
	const TURNS: PackedFloat32Array = [0.0, 0.7, 1.5708, 2.4, 3.14159]
	const TEAM_COLORS: Array[Color] = [Color(0.1, 0.3, 0.8), Color(0.98, 0.8, 0.1), Color(0.6, 0.1, 0.5), Color(0.1, 0.5, 0.25)]
	const NAMES: PackedStringArray = ["Gee", "Longerman", "Ox", "Kay", "Banana", "Fly", "Wu"]
	# Metres from one model to the next and from the bottom of a row to its top.
	var spacing: float = 0.7 if close else 2.1
	var tall: float = 0.8 if close else 2.35
	var row_px: int = 520 if close else 800
	var cell_px: int = roundi(spacing / tall * float(row_px))
	_view.size = Vector2i(cell_px * looks.size(), row_px)
	_cam.size = tall
	for i: int in looks.size():
		var model: PlayerModel = PlayerModel.new()
		_view.add_child(model)
		model.show_look(looks[i], TEAM_COLORS[i % TEAM_COLORS.size()], 1 + i * 17, "Tester Mc%s" % NAMES[i % NAMES.size()], i % 2 == 1)
		# Heads are lined up for a close look, feet for the whole body.
		model.position = Vector3((float(i) - float(looks.size() - 1) / 2.0) * spacing, -model.head_height() if close else 0.0, 0.0)
		_models.append(model)
	var middle_y: float = -0.06 if close else tall / 2.0 - 0.08
	_cam.look_at_from_position(Vector3(0.0, middle_y, 10.0), Vector3(0.0, middle_y, 0.0))
	var picture: Image = Image.create_empty(_view.size.x, row_px * TURNS.size(), false, Image.FORMAT_RGBA8)
	for row: int in TURNS.size():
		for model: PlayerModel in _models:
			model.rotation.y = TURNS[row]
		for frame: int in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot: Image = _view.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		picture.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(0, row * row_px))
	picture.save_png(_out_dir.path_join("%s.png" % sheet))
	print("saved ", sheet)


## Prints what the model at `path` is made of, and for a rigged one whether
## it has the bones a body needs.
func _describe(path: String) -> void:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		print("NOT A MODEL: ", path)
		return
	var root_node: Node = scene.instantiate()
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: ArrayMesh = (node as MeshInstance3D).mesh as ArrayMesh
		var arrays: Array = mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var size: Vector3 = mesh.get_aabb().size
		@warning_ignore("integer_division")
		print("mesh: %d vertices, %d triangles, %d surface(s), %.3f across, %.3f deep, %.3f tall" % [points.size(), indices.size() / 3, mesh.get_surface_count(), size.x, size.y, size.z])
		var material: BaseMaterial3D = mesh.surface_get_material(0) as BaseMaterial3D
		if material != null and material.albedo_texture != null:
			print("texture: ", material.albedo_texture.get_size(), ", normal map: ", material.normal_texture != null)
	var skeletons: Array[Node] = root_node.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		print("rig: none (fine for a head, not for a body)")
	else:
		var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
		var missing: PackedStringArray = PackedStringArray()
		for bone: String in BODY_BONES:
			if skeleton.find_bone(bone) < 0:
				missing.append(bone)
		print("rig: %d bones, %s" % [skeleton.get_bone_count(), "all the bones a body needs" if missing.is_empty() else "MISSING " + ", ".join(missing)])
	root_node.free()
