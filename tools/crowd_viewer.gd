extends Node3D
## Developer tool, not part of the game: one fan out of the crowd's kit of
## parts (assets/stadium/crowd_kit.glb), drawn with the crowd's own shader, to
## turn round and take apart. Run tools/crowd_viewer.tscn by itself (F6).
##
## Every part is picked on its own, so any head can be put on any outfit and
## looked at by itself, at each level of detail, in any of the colours the
## stadium gives a fan, sitting still, cheering or holding a sign. The keys are
## listed on the screen (KEYS below).
##
## To check a change to tools/prep_crowd.py: run it, come back to the editor
## (which re-imports the kit) and press F6 again.
##
## From a command line, `-- shot=<file.png> [look=<head>,<outfit>,<legs>]`
## saves one picture and quits.

const KEYS: String = """Left / Right   head
Up / Down      outfit
L              legs
G              gender
Tab            level of detail
1  2  3        show / hide head, outfit, legs
E              pull the parts apart
C              cheer          X  sulk
S              holding a sign (first outfit only)
T  K  H  P     shirt, skin, hair, trouser colour
R              a random fan
W              wireframe      F  flat (no lighting tricks: the raw atlas)
Space          turn by itself
Drag / wheel   turn / zoom    Home  reset the view"""
const PART_NAMES: PackedStringArray = ["head", "outfit", "legs"]
const SHIRTS: Array[Color] = [
	Color(0.95, 0.8, 0.1), Color(0.75, 0.1, 0.12), Color(0.92, 0.92, 0.9), Color(0.2, 0.4, 0.75),
	Color(0.2, 0.55, 0.3), Color(0.5, 0.25, 0.6), Color(0.1, 0.1, 0.12)]
const SKIN_STEPS: int = 6
## How far apart the parts are pulled, in the fan's own units.
const APART: float = 0.45
const ORBIT_PER_PIXEL: float = 0.008
const ZOOM_LIMITS: Vector2 = Vector2(0.8, 9.0)
const BACK_COLOR: Color = Color(0.3, 0.32, 0.36)

var _stadium: Stadium
var _home: Team
var _away: Team
var _stage: Node3D
var _camera: Camera3D
var _label: Label
var _flat: StandardMaterial3D

var _kit: int = 0
var _head: int = 0
var _torso: int = 0
var _legs: int = 0
var _tier: int = 0
var _shown: Array[bool] = [true, true, true]
var _apart: bool = false
var _cheer: bool = false
var _sulk: bool = false
var _sign: bool = false
var _shirt: int = 0
var _skin: int = 1
var _hair: int = 1
var _pants: int = 0
var _wire: bool = false
var _raw: bool = false
var _spin: bool = false
var _yaw: float = 0.35
var _pitch: float = 0.15
var _distance: float = 5.2
var _shot: String = ""


func _ready() -> void:
	# Has to be asked for before the meshes are loaded.
	RenderingServer.set_debug_generate_wireframes(true)
	var tuning: Tuning = (load("res://resources/tuning.tres") as Tuning).duplicate() as Tuning
	# Only the kit is wanted: the smallest stadium, with nobody in it, hidden.
	tuning.stadium_enabled = true
	tuning.stadium_rows = 1
	tuning.crowd_density = 0.0
	tuning.wave_min_gap = 100000.0
	tuning.wave_max_gap = 100000.0
	_home = Team.new()
	_home.short_name = "HOME"
	_home.team_color = SHIRTS[0]
	_away = Team.new()
	_away.short_name = "AWAY"
	_away.team_color = SHIRTS[1]
	_stadium = Stadium.new()
	add_child(_stadium)
	_stadium.setup(tuning, _home, _away, true)
	_stadium.visible = false

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(sun)
	var sky: Environment = Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = BACK_COLOR
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(0.8, 0.82, 0.9)
	sky.ambient_light_energy = 0.5
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = sky
	add_child(world)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	add_child(_camera)
	_camera.make_current()
	_stage = Node3D.new()
	add_child(_stage)
	_flat = StandardMaterial3D.new()
	_flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flat.albedo_texture = load(Stadium.KIT_ATLAS) as Texture2D

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override(&"font_size", 15)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	var mono: SystemFont = SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New"])
	_label.add_theme_font_override(&"font", mono)
	layer.add_child(_label)

	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			_shot = arg.trim_prefix("shot=")
		elif arg.begins_with("look="):
			var picks: PackedStringArray = arg.trim_prefix("look=").split(",")
			_head = int(picks[0]) if picks.size() > 0 else 0
			_torso = int(picks[1]) if picks.size() > 1 else 0
			_legs = int(picks[2]) if picks.size() > 2 else 0
	_build()
	if _shot != "":
		_save_shot()


func _exit_tree() -> void:
	if _home != null:
		_home.free()
	if _away != null:
		_away.free()


func _process(delta: float) -> void:
	if _stadium._kits.is_empty():
		return
	if _spin:
		_yaw += delta * 0.8
	# The stadium lets a cheer and a sulk wear off: hold them while they are on.
	_stadium.cheer[0] = 1.0 if _cheer else 0.0
	_stadium.slump[0] = 1.0 if _sulk else 0.0
	var aim: Vector3 = Vector3(0.0, 0.3 * Stadium.FAN_SCALE, 0.0)
	var away: Vector3 = Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.look_at_from_position(aim + away * _distance, aim)


func _unhandled_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		_yaw -= motion.relative.x * ORBIT_PER_PIXEL
		_pitch = clampf(_pitch + motion.relative.y * ORBIT_PER_PIXEL, -1.2, 1.4)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, ZOOM_LIMITS.x)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance / 0.9, ZOOM_LIMITS.y)
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or _stadium._kits.is_empty():
		return
	var kit: Stadium.Kit = _stadium._kits[_kit]
	match key.keycode:
		KEY_RIGHT:
			_head = posmod(_head + 1, (kit.heads[0] as Array).size())
		KEY_LEFT:
			_head = posmod(_head - 1, (kit.heads[0] as Array).size())
		KEY_UP:
			_torso = posmod(_torso + 1, (kit.torsos[0] as Array).size())
		KEY_DOWN:
			_torso = posmod(_torso - 1, (kit.torsos[0] as Array).size())
		KEY_L:
			_legs = posmod(_legs + 1, (kit.legs[0] as Array).size())
		KEY_G:
			_kit = posmod(_kit + 1, _stadium._kits.size())
		KEY_TAB:
			_tier = posmod(_tier + 1, Stadium.TIER_NAMES.size())
		KEY_1:
			_shown[0] = not _shown[0]
		KEY_2:
			_shown[1] = not _shown[1]
		KEY_3:
			_shown[2] = not _shown[2]
		KEY_E:
			_apart = not _apart
		KEY_C:
			_cheer = not _cheer
			_sulk = false
		KEY_X:
			_sulk = not _sulk
			_cheer = false
		KEY_S:
			_sign = not _sign
		KEY_T:
			_shirt = posmod(_shirt + 1, SHIRTS.size())
		KEY_K:
			_skin = posmod(_skin + 1, SKIN_STEPS)
		KEY_H:
			_hair = posmod(_hair + 1, Stadium.HAIR_COLORS.size())
		KEY_P:
			_pants = posmod(_pants + 1, Stadium.PANTS_COLORS.size() + 2)
		KEY_R:
			_head = randi() % (kit.heads[0] as Array).size()
			_torso = randi() % (kit.torsos[0] as Array).size()
			_legs = randi() % (kit.legs[0] as Array).size()
			_shirt = randi() % SHIRTS.size()
			_skin = randi() % SKIN_STEPS
			_hair = randi() % Stadium.HAIR_COLORS.size()
			_pants = randi() % (Stadium.PANTS_COLORS.size() + 2)
		KEY_W:
			_wire = not _wire
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if _wire else Viewport.DEBUG_DRAW_DISABLED
		KEY_F:
			_raw = not _raw
		KEY_SPACE:
			_spin = not _spin
		KEY_HOME:
			_yaw = 0.35
			_pitch = 0.15
			_distance = 5.2
		_:
			return
	_build()


## Puts the fan that is picked on the stage, part by part, and says what it is.
func _build() -> void:
	for old: Node in _stage.get_children():
		old.free()
	if _stadium._kits.is_empty():
		_label.text = "No kit of parts: run tools/prep_crowd.py (see docs/stadium.md)."
		return
	var kit: Stadium.Kit = _stadium._kits[_kit]
	_head = mini(_head, (kit.heads[0] as Array).size() - 1)
	_torso = mini(_torso, (kit.torsos[0] as Array).size() - 1)
	_legs = mini(_legs, (kit.legs[0] as Array).size() - 1)

	# What Stadium._fan() would give a home fan with these looks.
	var color: Color = SHIRTS[_shirt].srgb_to_linear()
	color.a = 0.0 + 2.0 * float(_pants)
	var skin: float = float(_skin) / float(SKIN_STEPS - 1) * 0.98
	var custom: Color = Color(0.3, skin + float(_hair), 0.0, 0.5)

	# [mesh, what it is, how far up it goes when the parts are pulled apart]
	var parts: Array = []
	if _tier == 2:
		parts.append([kit.far_sign if _sign else kit.far, "whole fan", 0.0])
	else:
		var torso: Mesh = kit.sign_torsos[_tier][0] if _sign else kit.torsos[_tier][_torso]
		if _shown[0]:
			parts.append([kit.heads[_tier][_head], "head", APART])
		if _shown[1]:
			parts.append([torso, "outfit", 0.0])
		if _shown[2]:
			parts.append([kit.legs[_tier][_legs], "legs", -APART])
	var lines: PackedStringArray = PackedStringArray()
	var total: int = 0
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var lift: float = float(part[2]) if _apart else 0.0
		var fan: Array = [Transform3D(Basis.from_scale(Vector3.ONE * Stadium.FAN_SCALE), Vector3(0.0, lift, 0.0)), color, custom]
		var material: Material = _flat if _raw else (mesh.get_meta(&"material") as Material)
		_stage.add_child(_stadium._scatter(mesh, [fan], Vector3.ZERO, material))
		@warning_ignore("integer_division")
		var triangles: int = (mesh as ArrayMesh).surface_get_array_index_len(0) / 3
		total += triangles
		lines.append("  %-10s %-18s %5d triangles" % [part[1], mesh.resource_name, triangles])

	var text: String = "%s   %s   head %d/%d   outfit %d/%d   legs %d/%d\n" % [
		"men" if kit.gender == "m" else "women", Stadium.TIER_NAMES[_tier].to_lower(),
		_head + 1, (kit.heads[0] as Array).size(), _torso + 1, (kit.torsos[0] as Array).size(),
		_legs + 1, (kit.legs[0] as Array).size()]
	text += "\n".join(lines) + "\n  %-29s %5d triangles\n" % ["in all", total]
	var state: PackedStringArray = PackedStringArray()
	for flag: Array in [[_cheer, "cheering"], [_sulk, "sulking"], [_sign, "holding a sign"], [_apart, "pulled apart"], [_wire, "wireframe"], [_raw, "raw atlas"]]:
		if flag[0]:
			state.append(flag[1])
	text += "  shirt %d  skin %d  hair %d  trousers %d%s\n\n" % [_shirt + 1, _skin + 1, _hair + 1, _pants + 1, ("   " + ", ".join(state)) if not state.is_empty() else ""]
	_label.text = text + KEYS


func _save_shot() -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot)
	get_tree().quit()
