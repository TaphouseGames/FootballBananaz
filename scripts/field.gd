class_name Field
extends Node3D
## Builds the placeholder field from Tuning dimensions: turf, end zones, yard
## lines, numbers, and the line-of-scrimmage / first-down markers.
## Playing field runs x = 0..field_length, z = -width/2..width/2.

const LINE_COLOR: Color = Color(0.95, 0.95, 0.95)
const TURF_A: Color = Color(0.16, 0.45, 0.2)
const TURF_B: Color = Color(0.14, 0.4, 0.18)
const APRON: Color = Color(0.08, 0.22, 0.11)
const LOS_COLOR: Color = Color(0.2, 0.5, 1.0)
const FIRST_DOWN_COLOR: Color = Color(1.0, 0.85, 0.1)

var _los_marker: MeshInstance3D
var _first_down_marker: MeshInstance3D

@onready var geometry: Node3D = $Geometry
@onready var markers: Node3D = $Markers


func setup(tuning: Tuning, home: Team, away: Team) -> void:
	var length: float = tuning.field_length
	var ez: float = tuning.end_zone_depth
	var width: float = tuning.field_width

	_add_box(geometry, Vector3(length * 0.5, -0.15, 0.0), Vector3(length + ez * 2.0 + 20.0, 0.2, width + 20.0), APRON, true)

	var stripe_count: int = int(length / 10.0)
	for i: int in stripe_count:
		var color: Color = TURF_A if i % 2 == 0 else TURF_B
		_add_box(geometry, Vector3(i * 10.0 + 5.0, -0.05, 0.0), Vector3(10.0, 0.1, width), color, true)

	# A team's own end zone is the one behind it.
	var left_team: Team = home if home.attack_dir > 0 else away
	var right_team: Team = away if home.attack_dir > 0 else home
	_add_box(geometry, Vector3(-ez * 0.5, -0.05, 0.0), Vector3(ez, 0.1, width), left_team.team_color.darkened(0.45), true)
	_add_box(geometry, Vector3(length + ez * 0.5, -0.05, 0.0), Vector3(ez, 0.1, width), right_team.team_color.darkened(0.45), true)
	_add_label(left_team.short_name, Vector3(-ez * 0.5, 0.03, 0.0), PI * 0.5, 160, left_team.team_color.lightened(0.3))
	_add_label(right_team.short_name, Vector3(length + ez * 0.5, 0.03, 0.0), -PI * 0.5, 160, right_team.team_color.lightened(0.3))

	var yard: int = 0
	while yard <= int(length):
		var line_width: float = 0.08
		if yard == 0 or yard == int(length):
			line_width = 0.35
		elif yard % 10 == 0:
			line_width = 0.14
		_add_box(geometry, Vector3(float(yard), 0.01, 0.0), Vector3(line_width, 0.02, width), LINE_COLOR, false)
		if yard % 10 == 0 and yard > 0 and yard < int(length):
			var number: String = str(mini(yard, int(length) - yard))
			_add_label(number, Vector3(float(yard), 0.03, width * 0.5 - 5.0), 0.0, 110, LINE_COLOR)
			_add_label(number, Vector3(float(yard), 0.03, -width * 0.5 + 5.0), 0.0, 110, LINE_COLOR)
		yard += 5

	var total: float = length + ez * 2.0
	for side: float in [-1.0, 1.0]:
		_add_box(geometry, Vector3(length * 0.5, 0.01, side * (width * 0.5 + 0.2)), Vector3(total + 0.8, 0.02, 0.4), LINE_COLOR, false)
	_add_box(geometry, Vector3(-ez - 0.2, 0.01, 0.0), Vector3(0.4, 0.02, width), LINE_COLOR, false)
	_add_box(geometry, Vector3(length + ez + 0.2, 0.01, 0.0), Vector3(0.4, 0.02, width), LINE_COLOR, false)

	_los_marker = _add_box(markers, Vector3(0.0, 0.03, 0.0), Vector3(0.22, 0.02, width), LOS_COLOR, false)
	_first_down_marker = _add_box(markers, Vector3(0.0, 0.03, 0.0), Vector3(0.22, 0.02, width), FIRST_DOWN_COLOR, false)


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


## Flat text painted on the turf. `yaw` rotates it around the vertical axis.
func _add_label(text: String, center: Vector3, yaw: float, font_size: int, color: Color) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.03
	label.outline_size = 0
	label.modulate = color
	label.shaded = false
	label.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5)
	label.position = center
	geometry.add_child(label)
