extends SceneTree
## Contact sheets of the crowd's kit of parts (assets/stadium/crowd_kit.glb),
## drawn with the crowd's own shader: per gender, every head (across) on every
## outfit (down), at full detail and at the middle level, from the front, from
## behind and in a cheer, then the plainest level. The place to look for gaps
## at the neck and the waist. Needs a window (no --headless), since headless
## does not render.
##
## Where the crowd is made of whole people (assets/stadium/crowd_people.glb)
## the sheets are of them instead: everybody side by side at each level of
## detail (people_<level>_front, ...), and with person=<id>[,<id>] a sheet of
## that person alone (<id>_front, <id>_near, ...).
##
## Run:  godot --path . --resolution 1400x1000 --script res://tests/crowd_gallery.gd -- out=<folder> [person=<id>,<id>]

const COLUMN: float = 2.1
const ROW: float = 2.9
## Where the sheets are set up: well clear of the stadium that is built to get
## at the kit.
const STAGE: Vector3 = Vector3(0.0, 400.0, 0.0)

var _out_dir: String = "user://crowd_gallery"
## The people who get a sheet of their own (person=<id>,<id>).
var _only_people: PackedStringArray = PackedStringArray()
var _stage: Node3D
var _camera: Camera3D
var _stadium: Stadium


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("person="):
			_only_people = arg.trim_prefix("person=").split(",")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run()


func _run() -> void:
	var tuning: Tuning = (load("res://resources/tuning.tres") as Tuning).duplicate() as Tuning
	var home: Team = Team.new()
	home.short_name = "HOME"
	home.team_color = Color(0.95, 0.8, 0.1)
	var away: Team = Team.new()
	away.short_name = "AWAY"
	away.team_color = Color(0.75, 0.1, 0.12)
	_stadium = Stadium.new()
	root.add_child(_stadium)
	_stadium.setup(tuning, home, away, true)

	_stage = Node3D.new()
	_stage.position = STAGE
	root.add_child(_stage)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	root.add_child(sun)
	var sky: Environment = Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.3, 0.32, 0.36)
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(0.8, 0.82, 0.9)
	sky.ambient_light_energy = 0.5
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = sky
	root.add_child(world)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(_camera)
	_camera.make_current()
	await _wait(0.5)

	var shirts: Array[Color] = [home.team_color, away.team_color, Color(0.25, 0.45, 0.75), Color(0.9, 0.9, 0.88)]
	# The whole people (assets/stadium/crowd_people.glb), one sheet each: the
	# three levels of detail down, four shirts and then one with a sign across.
	# Everybody side by side at full detail, in two rows of colours (and a
	# third with signs), then at the two plainer levels.
	if not _stadium._people.is_empty():
		var count: int = _stadium._people.size()
		var wide: float = float(count) * COLUMN * 1000.0 / 1400.0 + 0.6
		for tier: int in 3:
			var everybody: Dictionary = {}
			for column: int in count:
				var person: Stadium.Person = _stadium._people[column]
				for row: int in 3:
					var fan: Array = _fan(column, row, count, 3, shirts[(row * 2 + column) % shirts.size()] if row != 0 else away.team_color)
					_stadium._enter(everybody, person.sign_meshes[tier] if row == 2 else person.meshes[tier], fan)
			_show(everybody)
			var level: String = Stadium.TIER_NAMES[tier].to_lower()
			await _shoot("people_%s_front" % level, Vector3(1.5, 0.6, 10.0), wide)
			if tier == 0:
				await _shoot("people_%s_back" % level, Vector3(-1.5, 0.6, -10.0), wide)
				# Two halves from closer by.
				for half: int in 2:
					var middle: Vector3 = Vector3((float(half) - 0.5) * float(count) * COLUMN * 0.5, 0.0, 0.0)
					await _shoot("people_%s_front_%d" % [level, half + 1], Vector3(1.5, 0.6, 10.0), wide * 0.52, 0.2, middle)
					await _shoot("people_%s_back_%d" % [level, half + 1], Vector3(-1.5, 0.6, -10.0), wide * 0.52, 0.2, middle)
				_stadium.cheer[0] = 1.0
				_stadium._push_uniforms()
				await _wait(0.3)
				_stadium.cheer[0] = 1.0
				_stadium._push_uniforms()
				await _shoot("people_%s_cheer" % level, Vector3(1.5, 0.6, 10.0), wide + 1.0, 0.0)
				_stadium.cheer[0] = 0.0
				_stadium._push_uniforms()
	for person: Stadium.Person in _stadium._people:
		# One sheet each, only for those asked for (person=<id>[,<id>...]).
		if not _only_people.has(person.id):
			continue
		var sheet: Dictionary = {}
		for tier: int in 3:
			for column: int in shirts.size() + 1:
				var holds_sign: bool = column == shirts.size()
				var fan: Array = _fan(column, tier, shirts.size() + 1, 3, shirts[column % shirts.size()])
				_stadium._enter(sheet, person.sign_meshes[tier] if holds_sign else person.meshes[tier], fan)
		_show(sheet)
		var tall: float = 3.0 * ROW + 0.6
		await _shoot("%s_front" % person.id, Vector3(1.5, 0.6, 10.0), tall)
		await _shoot("%s_back" % person.id, Vector3(-1.5, 0.6, -10.0), tall)
		await _shoot("%s_side" % person.id, Vector3(10.0, 0.4, 2.0), tall)
		await _shoot("%s_near" % person.id, Vector3(1.5, 0.6, 10.0), ROW * 1.05, 0.2, Vector3(0.0, ROW + 0.25, 0.0))
		await _shoot("%s_near_side" % person.id, Vector3(10.0, 0.4, 0.0), ROW * 1.05, 0.2, Vector3(0.0, ROW + 0.25, 0.0))
		_stadium.cheer[0] = 1.0
		_stadium._push_uniforms()
		await _wait(0.3)
		_stadium.cheer[0] = 1.0
		_stadium._push_uniforms()
		await _shoot("%s_cheer" % person.id, Vector3(1.5, 0.6, 10.0), tall + 1.0, 0.0)
		_stadium.cheer[0] = 0.0
		_stadium._push_uniforms()
	for kit: Stadium.Kit in _stadium._kits:
		for tier: int in 3:
			var level: String = Stadium.TIER_NAMES[tier].to_lower()
			var heads: Array = kit.heads[tier]
			var torsos: Array = kit.torsos[tier]
			var groups: Dictionary = {}
			for row: int in torsos.size():
				for column: int in heads.size():
					var fan: Array = _fan(column, row, heads.size(), torsos.size(), shirts[row % shirts.size()])
					for mesh: Mesh in [heads[column], torsos[row], (kit.legs[tier] as Array)[(row + column) % (kit.legs[tier] as Array).size()]]:
						_stadium._enter(groups, mesh, fan)
			_show(groups)
			var size: float = maxf(float(torsos.size()) * ROW, float(heads.size()) * COLUMN * 1000.0 / 1400.0) + 0.6
			await _shoot("%s_%s_front" % [kit.gender, level], Vector3(1.5, 0.6, 10.0), size)
			if tier == 0:
				# Row by row from close by: the seams at the neck and the waist.
				for row: int in torsos.size():
					var middle: Vector3 = Vector3(0.0, (float(torsos.size() - 1) * 0.5 - float(row)) * ROW + 0.25, 0.0)
					await _shoot("%s_%s_row%d" % [kit.gender, level, row + 1], Vector3(1.5, 0.6, 10.0), ROW * 1.05, 0.2, middle)
				await _shoot("%s_%s_back" % [kit.gender, level], Vector3(-1.5, 0.6, -10.0), size)
				await _shoot("%s_%s_side" % [kit.gender, level], Vector3(10.0, 0.4, 2.0), size)
				_stadium.cheer[0] = 1.0
				_stadium._push_uniforms()
				await _wait(0.3)
				_stadium.cheer[0] = 1.0
				_stadium._push_uniforms()
				await _shoot("%s_%s_cheer" % [kit.gender, level], Vector3(1.5, 0.6, 10.0), size + 1.0, 0.0)
				_stadium.cheer[0] = 0.0
				_stadium._push_uniforms()
		# A fan with a sign and the plainest level, beside a full one.
		var others: Dictionary = {}
		var first: Array = _fan(0, 0, 4, 1, shirts[0])
		for mesh: Mesh in [kit.heads[0][0], kit.torsos[0][0], kit.legs[0][0]]:
			_stadium._enter(others, mesh, first)
		var holder: Array = _fan(1, 0, 4, 1, shirts[1])
		for mesh: Mesh in [kit.heads[0][0], kit.sign_torsos[0][0], kit.legs[0][0]]:
			_stadium._enter(others, mesh, holder)
		_stadium._enter(others, kit.far, _fan(2, 0, 4, 1, shirts[2]))
		_stadium._enter(others, kit.far_sign, _fan(3, 0, 4, 1, shirts[3]))
		_show(others)
		await _shoot("%s_sign_and_far" % kit.gender, Vector3(1.5, 0.6, 10.0), 5.0)
	print("CROWD GALLERY DONE: ", _out_dir)
	_stadium.free()
	home.free()
	away.free()
	quit(0)


## One fan of the sheet, as Stadium._fan() makes them: a different skin tone
## and hair colour in every cell.
func _fan(column: int, row: int, columns: int, rows: int, shirt: Color) -> Array:
	var at: Vector3 = Vector3((float(column) - float(columns - 1) * 0.5) * COLUMN, (float(rows - 1) * 0.5 - float(row)) * ROW - 0.9, 0.0)
	var color: Color = shirt.srgb_to_linear()
	var cell: int = row * columns + column
	# Home fans (so that a home cheer gets them up), trousers by turns.
	color.a = 0.0 + 2.0 * float(cell % (Stadium.PANTS_COLORS.size() + 2))
	var skin: float = fmod(float(cell) * 0.37, 0.98)
	var hair: int = (cell * 3 + 1) % Stadium.HAIR_COLORS.size()
	return [Transform3D(Basis.from_scale(Vector3.ONE * Stadium.FAN_SCALE), at), color, Color(fmod(float(cell) * 0.61, 1.0), skin + float(hair), 0.0, fmod(float(cell) * 0.23, 1.0))]


func _show(groups: Dictionary) -> void:
	for old: Node in _stage.get_children():
		old.free()
	for mesh: Mesh in groups:
		_stage.add_child(_stadium._scatter(mesh, groups[mesh], Vector3.ZERO, mesh.get_meta(&"material")))


func _shoot(shot_name: String, from: Vector3, size: float, settle: float = 0.2, aim: Vector3 = Vector3.ZERO) -> void:
	_camera.size = size
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.look_at_from_position(STAGE + aim + from, STAGE + aim)
	if settle > 0.0:
		await _wait(settle)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(shot_name + ".png"))


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
