extends SceneTree
## Pictures of the player models PlayerModel builds from a PlayerLook: both
## base models with every hairstyle, eye, nose, mouth, facial hair and pair of
## glasses, light and heavy, from in front, the side and behind.
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/model_gallery.gd -- out=<folder>
## Optional user args after "--":
##   only=<text>   only the sheets whose name contains the text

var _out_dir: String = "user://model_gallery"
var _only: String = ""
var _cam: Camera3D
var _view: SubViewport
var _models: Array[PlayerModel] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("only="):
			_only = arg.trim_prefix("only=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# Off screen, so a picture can be wider than the window.
	_view = SubViewport.new()
	_view.own_world_3d = true
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
	for base: int in 2:
		var who: String = PlayerLook.BASE_NAMES[base].to_lower()
		# Every hairstyle, from four sides.
		var looks: Array[PlayerLook] = []
		for style: int in 7:
			var look: PlayerLook = _plain(base)
			look.hair_style = style
			look.hair_color = PlayerLook.HAIR_PRESETS[style % PlayerLook.HAIR_PRESETS.size()]
			looks.append(look)
		await _sheet("%s_hair" % who, looks, true)
		# Every eye, nose and mouth, with the glasses and the sizes mixed in.
		looks = []
		for type: int in 6:
			var look: PlayerLook = _plain(base)
			look.hair_style = 1 + type
			look.eye_type = type
			look.nose_type = type
			look.mouth_type = type
			look.skin_color = PlayerLook.SKIN_PRESETS[type]
			looks.append(look)
		var patched: PlayerLook = _plain(base)
		patched.glasses = PlayerLook.Glasses.EYEPATCH
		patched.eyepatch_side = PlayerLook.Eye.RIGHT
		looks.append(patched)
		await _sheet("%s_faces" % who, looks, true)
		looks = []
		for type: int in 7:
			var look: PlayerLook = _plain(base)
			look.facial_hair = type
			look.hair_style = 2
			look.glasses = [0, 1, 2, 3, 0, 1, 2][type] as PlayerLook.Glasses
			look.nose_type = type % 6
			look.nose_size = [0.5, 0.0, 1.0, 0.5, 0.2, 0.8, 0.5][type]
			look.mouth_size = [0.5, 0.0, 1.0, 0.5, 0.5, 0.5, 0.5][type]
			look.mouth_type = [0, 1, 1, 2, 4, 5, 3][type]
			looks.append(look)
		await _sheet("%s_extras" % who, looks, true)
		# The build and the sliders, whole body.
		looks = []
		var builds: Array[Vector2i] = [Vector2i(64, 135), Vector2i(70, 190), Vector2i(72, 215), Vector2i(76, 260), Vector2i(76, 340), Vector2i(82, 400), Vector2i(72, 215)]
		for i: int in 7:
			var look: PlayerLook = _plain(base)
			look.height_in = builds[i].x
			look.weight_lb = builds[i].y
			look.forehead_size = [0.5, 0.0, 1.0, 0.5, 0.5, 0.5, 1.0][i]
			look.chin_size = [0.5, 0.5, 0.5, 0.0, 1.0, 0.5, 1.0][i]
			look.hair_style = [1, 2, 3, 5, 0, 6, 4][i]
			look.skin_color = PlayerLook.SKIN_PRESETS[i % 6]
			looks.append(look)
		await _sheet("%s_build" % who, looks, false)
	print("model gallery saved to ", ProjectSettings.globalize_path(_out_dir))
	quit()


func _plain(base: int) -> PlayerLook:
	var look: PlayerLook = PlayerLook.new()
	look.base = base as PlayerLook.Base
	return look


## One picture of `looks` side by side, a row for each side they are seen
## from: in front, a quarter turned, the side and behind. Of the head
## (`close`) or of the whole body.
func _sheet(sheet: String, looks: Array[PlayerLook], close: bool) -> void:
	if _only != "" and not sheet.contains(_only):
		return
	for model: PlayerModel in _models:
		model.queue_free()
	_models.clear()
	const TURNS: PackedFloat32Array = [0.0, 0.7, 1.5708, 3.14159]
	const TEAM_COLORS: Array[Color] = [Color(0.1, 0.3, 0.8), Color(0.98, 0.8, 0.1), Color(0.6, 0.1, 0.5), Color(0.1, 0.5, 0.25)]
	const NAMES: PackedStringArray = ["Gee", "Longerman", "Ox", "Kay", "Banana", "Fly", "Wu"]
	# Metres from one model to the next and from the bottom of a row to its top.
	var spacing: float = 0.56 if close else 1.35
	var tall: float = 0.66 if close else 2.35
	var row_px: int = 520 if close else 800
	var cell_px: int = roundi(spacing / tall * float(row_px))
	_view.size = Vector2i(cell_px * looks.size(), row_px)
	_cam.size = tall
	for i: int in looks.size():
		var model: PlayerModel = PlayerModel.new()
		_view.add_child(model)
		model.show_look(looks[i], TEAM_COLORS[i % TEAM_COLORS.size()], 10 + i * 13, "Tester Mc%s" % NAMES[i])
		# Heads are lined up for a close look, feet for the whole body.
		model.position = Vector3((float(i) - float(looks.size() - 1) / 2.0) * spacing, -model.head_height() if close else 0.0, 0.0)
		_models.append(model)
	var middle_y: float = 0.02 if close else tall / 2.0 - 0.08
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
