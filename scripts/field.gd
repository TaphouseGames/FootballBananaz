class_name Field
extends Node3D
## Builds the field from Tuning dimensions: one turf plane whose shader draws the
## grass, mowing stripes, painted lines and end zones, plus the yard numbers and
## the line-of-scrimmage / first-down markers. Marks left during play live in `fx`.
## Playing field runs x = 0..field_length, z = -width/2..width/2.

const TURF_SHADER: Shader = preload("res://assets/field/turf.gdshader")
const LINE_COLOR: Color = Color(0.95, 0.95, 0.92, 0.85)
const LOS_COLOR: Color = Color(0.2, 0.5, 1.0)
const FIRST_DOWN_COLOR: Color = Color(1.0, 0.85, 0.1)
## Grass beyond the lines on every side, so the camera never sees the edge.
const SURROUND: float = 90.0
const LABEL_HEIGHT: float = 0.008

var _los_marker: MeshInstance3D
var _first_down_marker: MeshInstance3D

@onready var geometry: Node3D = $Geometry
@onready var markers: Node3D = $Markers
@onready var fx: FieldFx = $Fx


func setup(tuning: Tuning, home: Team, away: Team) -> void:
	var length: float = tuning.field_length
	var ez: float = tuning.end_zone_depth
	var width: float = tuning.field_width

	# A team's own end zone is the one behind it.
	var left_team: Team = home if home.attack_dir > 0 else away
	var right_team: Team = away if home.attack_dir > 0 else home

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TURF_SHADER
	material.set_shader_parameter(&"field_length", length)
	material.set_shader_parameter(&"field_width", width)
	material.set_shader_parameter(&"end_zone_depth", ez)
	material.set_shader_parameter(&"left_color", left_team.team_color)
	material.set_shader_parameter(&"right_color", right_team.team_color)
	material.set_shader_parameter(&"patch_noise", _noise_texture(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 4, false))
	material.set_shader_parameter(&"blade_noise", _noise_texture(FastNoiseLite.TYPE_SIMPLEX, 0.09, 3, false))
	material.set_shader_parameter(&"blade_normal", _noise_texture(FastNoiseLite.TYPE_SIMPLEX, 0.09, 3, true))
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(length + ez * 2.0 + SURROUND * 2.0, width + SURROUND * 2.0)
	var turf: MeshInstance3D = MeshInstance3D.new()
	turf.mesh = plane
	turf.material_override = material
	turf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	turf.position = Vector3(length * 0.5, 0.0, 0.0)
	geometry.add_child(turf)

	_add_label(left_team.short_name, Vector3(-ez * 0.5, LABEL_HEIGHT, 0.0), PI * 0.5, 160, Color(left_team.team_color.lightened(0.35), 0.85))
	_add_label(right_team.short_name, Vector3(length + ez * 0.5, LABEL_HEIGHT, 0.0), -PI * 0.5, 160, Color(right_team.team_color.lightened(0.35), 0.85))
	var yard: int = 10
	while yard < int(length):
		var number: String = str(mini(yard, int(length) - yard))
		_add_label(number, Vector3(float(yard), LABEL_HEIGHT, width * 0.5 - 5.0), 0.0, 110, LINE_COLOR)
		_add_label(number, Vector3(float(yard), LABEL_HEIGHT, -width * 0.5 + 5.0), 0.0, 110, LINE_COLOR)
		yard += 10

	_los_marker = _add_box(markers, Vector3(0.0, 0.03, 0.0), Vector3(0.22, 0.02, width), LOS_COLOR, false)
	_first_down_marker = _add_box(markers, Vector3(0.0, 0.03, 0.0), Vector3(0.22, 0.02, width), FIRST_DOWN_COLOR, false)
	fx.setup(tuning)


func set_markers(los_x: float, first_down_x: float, show_first_down: bool) -> void:
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
func _noise_texture(type: FastNoiseLite.NoiseType, frequency: float, octaves: int, as_normal: bool) -> NoiseTexture2D:
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


## Flat text painted on the turf. `yaw` rotates it around the vertical axis.
func _add_label(text: String, center: Vector3, yaw: float, font_size: int, color: Color) -> void:
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
