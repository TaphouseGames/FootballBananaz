class_name Field
extends Node3D
## Builds the field from Tuning dimensions: one turf plane whose shader draws the
## grass, mowing stripes, yard lines, yard numbers, end zones and the two mascots
## at midfield, plus the end zone names and the line-of-scrimmage / first-down
## markers. Nothing marks the edge: the stadium wall is the edge. Marks left
## during play live in `fx`.
## Playing field runs x = 0..field_length, z = -width/2..width/2.

const TURF_SHADER: Shader = preload("res://assets/field/turf.gdshader")
## Flat pictures of the mascots (tools/mascot_decal.py), by the team's short name.
const MASCOT_DECAL: String = "res://assets/field/mascot_%s.png"
const MASCOT_DECAL_FALLBACK: String = "res://assets/field/mascot_bananaz.png"
const LOS_COLOR: Color = Color(0.2, 0.5, 1.0)
const FIRST_DOWN_COLOR: Color = Color(1.0, 0.85, 0.1)
## Grass beyond the lines on every side, so the camera never sees the edge.
const SURROUND: float = 90.0
const LABEL_HEIGHT: float = 0.008
## The lettering painted on the turf is drawn once with a real typeface into
## one picture (see _bake_paint): a row of the numerals 0 to 5, a cell each,
## and a row for each end zone's name. Pixels of a numeral's cell and of a
## name's row, and the clear edge kept inside each.
const PAINT_CELL: Vector2i = Vector2i(320, 512)
const PAINT_NAME: Vector2i = Vector2i(1920, 300)
const PAINT_PAD: int = 14
const NUMBER_FONTS: PackedStringArray = ["Rockwell Extra Bold", "Arial Black", "Impact"]
const NAME_FONTS: PackedStringArray = ["Impact", "Haettenschweiler", "Arial Black"]
## How deep a name's row is, as a share of the end zone's depth.
const NAME_DEPTH: float = 0.62

var _los_marker: MeshInstance3D
var _first_down_marker: MeshInstance3D

@onready var geometry: Node3D = $Geometry
@onready var markers: Node3D = $Markers
@onready var fx: FieldFx = $Fx
@onready var stadium: Stadium = $Stadium


func setup(tuning: Tuning, home: Team, away: Team) -> void:
	var length: float = tuning.field_length
	var ez: float = tuning.end_zone_depth
	var width: float = tuning.field_width

	# A team's own end zone is the one behind it.
	var left_team: Team = home if home.attack_dir > 0 else away
	var right_team: Team = away if home.attack_dir > 0 else home

	# The turf, and what is painted across it, runs on under the foot of the wall.
	var margin: float = tuning.wall_gap + Stadium.WALL_THICKNESS * 0.5
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TURF_SHADER
	material.set_shader_parameter(&"field_length", length)
	material.set_shader_parameter(&"field_width", width)
	material.set_shader_parameter(&"end_zone_depth", ez)
	material.set_shader_parameter(&"margin", margin)
	# What lies round the stadium starts where the bowl ends.
	if tuning.stadium_enabled:
		material.set_shader_parameter(&"bowl_reach", tuning.wall_gap + Stadium.WALL_THICKNESS + float(maxi(tuning.stadium_rows, 1)) * Stadium.ROW_DEPTH + Stadium.CONCOURSE_DEPTH + Stadium.BACK_WALL_THICKNESS + Stadium.FACADE_DEPTH)
	material.set_shader_parameter(&"left_mascot", mascot_decal(left_team))
	material.set_shader_parameter(&"right_mascot", mascot_decal(right_team))
	material.set_shader_parameter(&"left_color", left_team.team_color)
	material.set_shader_parameter(&"right_color", right_team.team_color)
	material.set_shader_parameter(&"patch_noise", noise_texture(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 4, false))
	material.set_shader_parameter(&"blade_noise", noise_texture(FastNoiseLite.TYPE_SIMPLEX, 0.09, 3, false))
	material.set_shader_parameter(&"blade_normal", noise_texture(FastNoiseLite.TYPE_SIMPLEX, 0.09, 3, true))
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(length + ez * 2.0 + SURROUND * 2.0, width + SURROUND * 2.0)
	var turf: MeshInstance3D = MeshInstance3D.new()
	turf.mesh = plane
	turf.material_override = material
	turf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	turf.position = Vector3(length * 0.5, 0.0, 0.0)
	geometry.add_child(turf)

	# Plain names until the drawn lettering is ready (and for good when
	# nothing is drawn, headless).
	var plain: Array[Label3D] = [
		_add_label(left_team.short_name, Vector3(-ez * 0.5, LABEL_HEIGHT, 0.0), PI * 0.5, 160, Color(left_team.team_color.lightened(0.35), 0.85)),
		_add_label(right_team.short_name, Vector3(length + ez * 0.5, LABEL_HEIGHT, 0.0), -PI * 0.5, 160, Color(right_team.team_color.lightened(0.35), 0.85))]
	var rows: int = PAINT_CELL.y + PAINT_NAME.y * 2
	material.set_shader_parameter(&"atlas_rows", Vector2(float(PAINT_CELL.y) / float(rows), float(PAINT_NAME.y) / float(rows)))
	material.set_shader_parameter(&"name_size", Vector2(ez * NAME_DEPTH * float(PAINT_NAME.x) / float(PAINT_NAME.y), ez * NAME_DEPTH))
	_bake_paint(material, [left_team.short_name, right_team.short_name], plain)
	_los_marker = _add_box(markers, Vector3(0.0, 0.03, 0.0), Vector3(0.22, 0.02, width + margin * 2.0), LOS_COLOR, false)
	_first_down_marker = _add_box(markers, Vector3(0.0, 0.03, 0.0), Vector3(0.22, 0.02, width + margin * 2.0), FIRST_DOWN_COLOR, false)
	fx.setup(tuning)
	stadium.setup(tuning, home, away, left_team == home)


## The picture of `team`'s mascot that is painted at midfield.
static func mascot_decal(team: Team) -> Texture2D:
	var path: String = MASCOT_DECAL % team.short_name.to_lower()
	if not ResourceLoader.exists(path):
		path = MASCOT_DECAL_FALLBACK
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func set_markers(los_x: float, first_down_x: float, show_first_down: bool) -> void:
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.FIELD, &"set_markers", [los_x, first_down_x, show_first_down])
	_los_marker.position.x = los_x
	_first_down_marker.position.x = first_down_x
	_first_down_marker.visible = show_first_down
	_los_marker.reset_physics_interpolation()
	_first_down_marker.reset_physics_interpolation()


func _add_box(parent: Node3D, center: Vector3, size: Vector3, color: Color, lit: bool) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if not lit:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = center
	parent.add_child(instance)
	return instance


## Seamless tiling noise for the turf shader, as greyscale or as a normal map.
static func noise_texture(type: FastNoiseLite.NoiseType, frequency: float, octaves: int, as_normal: bool) -> NoiseTexture2D:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = type
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	var texture: NoiseTexture2D = NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.as_normal_map = as_normal
	texture.bump_strength = 10.0
	texture.noise = noise
	return texture


## Draws the numerals and the two end zone names with a real typeface into one
## picture, by a viewport that is thrown away afterwards, and hands it to the
## turf shader, which paints them into the grass; the plain `labels` go then.
## Each numeral is stretched to fill its cell, so the shader knows where its
## edges are whatever the typeface; a name is as big as fits its row.
func _bake_paint(material: ShaderMaterial, names: PackedStringArray, labels: Array[Label3D]) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var size: Vector2i = Vector2i(PAINT_CELL.x * 6, PAINT_CELL.y + PAINT_NAME.y * 2)
	var viewport: SubViewport = SubViewport.new()
	viewport.name = "PaintBake"
	viewport.size = size
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var number_font: SystemFont = SystemFont.new()
	number_font.font_names = NUMBER_FONTS
	number_font.font_weight = 900
	var name_font: SystemFont = SystemFont.new()
	name_font.font_names = NAME_FONTS
	# Red is the paint and green its outline: the picture comes back with the
	# colours already multiplied by how much of a pixel they cover.
	for digit: int in 6:
		var numeral: Label = _paint_label(str(digit), number_font, 300, Rect2i(Vector2i(PAINT_CELL.x * digit, 0), PAINT_CELL))
		viewport.add_child(numeral)
	for row: int in names.size():
		var text: String = names[row].to_upper()
		var cell: Rect2i = Rect2i(Vector2i(0, PAINT_CELL.y + PAINT_NAME.y * row), PAINT_NAME)
		var font_size: int = 190
		while font_size > 40 and name_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size).x > float(PAINT_NAME.x) * 0.9:
			font_size -= 6
		var word: Label = _paint_label(text, name_font, font_size, cell)
		@warning_ignore("integer_division")
		word.add_theme_constant_override(&"outline_size", font_size / 6)
		word.add_theme_color_override(&"font_outline_color", Color(0.0, 1.0, 0.0))
		viewport.add_child(word)
	geometry.add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	# setup() may have run again, or the field may be gone.
	if not is_instance_valid(viewport):
		return
	var drawn: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	if drawn == null or drawn.is_empty():
		return
	drawn.convert(Image.FORMAT_RGBA8)
	var atlas: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for digit: int in 6:
		_fit_ink(drawn, Rect2i(Vector2i(PAINT_CELL.x * digit, 0), PAINT_CELL), atlas, true)
	for row: int in names.size():
		_fit_ink(drawn, Rect2i(Vector2i(0, PAINT_CELL.y + PAINT_NAME.y * row), PAINT_NAME), atlas, false)
	atlas.generate_mipmaps()
	material.set_shader_parameter(&"paint_atlas", ImageTexture.create_from_image(atlas))
	material.set_shader_parameter(&"painted", true)
	for label: Label3D in labels:
		if is_instance_valid(label):
			label.queue_free()


## `text` in red in the middle of `cell` of the picture of the lettering.
func _paint_label(text: String, font: Font, font_size: int, cell: Rect2i) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = Vector2(cell.position)
	label.size = Vector2(cell.size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.0, 0.0))
	return label


## Copies what is drawn in `cell` of `drawn` into the same cell of `atlas`,
## PAINT_PAD in from its edges: stretched to fill it (`stretch`), or as big as
## fits with its shape kept, in the middle.
func _fit_ink(drawn: Image, cell: Rect2i, atlas: Image, stretch: bool) -> void:
	var region: Image = drawn.get_region(cell)
	var used: Rect2i = region.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	var ink: Image = region.get_region(used)
	var room: Vector2i = cell.size - Vector2i(PAINT_PAD, PAINT_PAD) * 2
	var fitted: Vector2i = room
	if not stretch:
		var scale_by: float = minf(float(room.x) / float(used.size.x), float(room.y) / float(used.size.y))
		fitted = Vector2i(maxi(roundi(float(used.size.x) * scale_by), 1), maxi(roundi(float(used.size.y) * scale_by), 1))
	ink.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
	@warning_ignore("integer_division")
	atlas.blit_rect(ink, Rect2i(Vector2i.ZERO, fitted), cell.position + (cell.size - fitted) / 2)


## Flat text painted on the turf. `yaw` rotates it around the vertical axis.
func _add_label(text: String, center: Vector3, yaw: float, font_size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.03
	label.outline_size = 0
	label.modulate = color
	label.shaded = false
	# Under the marks FieldFx leaves on the turf.
	label.render_priority = -1
	label.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5)
	label.position = center
	geometry.add_child(label)
	return label
