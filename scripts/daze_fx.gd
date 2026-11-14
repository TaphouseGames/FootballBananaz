class_name DazeFx
extends Node3D
## Stars going round the head of a player who lies dazed after a jump dive, with
## a few twinkles between them. Purely cosmetic: it reads the player and changes
## nothing.

const STARS: int = 5
const STAR_RADIUS: float = 0.2
const RING_RADIUS: float = 0.55
## How far over the head the ring hangs.
const HOVER: float = 0.55
const ORBIT_SPEED: float = 4.2
## What is left over the head of an injured player: fewer, smaller, closer in
## and slower.
const INJURED_STARS: int = 2
const INJURED_STAR: float = 0.11
const INJURED_RING: float = 0.3
const INJURED_ORBIT: float = 2.2
const POP_IN: float = 0.18
const FADE_OUT: float = 0.4
const STAR_CORE: Color = Color(1.0, 0.98, 0.7)
const STAR_TIP: Color = Color(1.0, 0.78, 0.1)

static var _star_mesh: ArrayMesh
static var _materials: Dictionary[bool, StandardMaterial3D] = {}

var _stars: Array[MeshInstance3D] = []
var _twinkles: CPUParticles3D
var _age: float = 0.0
var _full: float = 1.0
var _turn: float = 0.0


## A flat five-pointed star in the XY plane, 1 across from point to point's
## centre (radius 1), pale in the middle and deep yellow at the tips.
static func star_mesh() -> ArrayMesh:
	if _star_mesh != null:
		return _star_mesh
	var rim: PackedVector3Array = PackedVector3Array()
	for i: int in 10:
		var angle: float = PI * 0.5 + float(i) * TAU / 10.0
		var radius: float = 1.0 if i % 2 == 0 else 0.45
		rim.append(Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	for i: int in 10:
		vertices.append(Vector3.ZERO)
		vertices.append(rim[i])
		vertices.append(rim[(i + 1) % 10])
		colors.append(STAR_CORE)
		colors.append(STAR_TIP if i % 2 == 0 else STAR_CORE.lerp(STAR_TIP, 0.5))
		colors.append(STAR_TIP if i % 2 == 1 else STAR_CORE.lerp(STAR_TIP, 0.5))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	_star_mesh = ArrayMesh.new()
	_star_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _star_mesh


## Unlit, facing the camera, coloured by the mesh (and by the particle, for one
## drawn by a particle system).
static func star_material(particles: bool) -> StandardMaterial3D:
	if _materials.has(particles):
		return _materials[particles]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_keep_scale = true
	if particles:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	else:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_materials[particles] = material
	return material


func _init() -> void:
	name = "DazeFx"
	visible = false
	for i: int in STARS:
		var star: MeshInstance3D = MeshInstance3D.new()
		star.mesh = star_mesh()
		star.material_override = star_material(false)
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(star)
		_stars.append(star)

	_twinkles = CPUParticles3D.new()
	_twinkles.mesh = star_mesh()
	_twinkles.material_override = star_material(true)
	_twinkles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_twinkles.amount = 12
	_twinkles.lifetime = 0.55
	_twinkles.emitting = false
	_twinkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_twinkles.emission_ring_axis = Vector3.UP
	_twinkles.emission_ring_radius = RING_RADIUS
	_twinkles.emission_ring_inner_radius = RING_RADIUS * 0.6
	_twinkles.emission_ring_height = 0.15
	_twinkles.direction = Vector3.UP
	_twinkles.spread = 30.0
	_twinkles.gravity = Vector3.ZERO
	_twinkles.initial_velocity_min = 0.2
	_twinkles.initial_velocity_max = 0.6
	_twinkles.scale_amount_min = 0.03
	_twinkles.scale_amount_max = 0.06
	var shrink: Curve = Curve.new()
	shrink.add_point(Vector2(0.0, 0.0))
	shrink.add_point(Vector2(0.25, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	_twinkles.scale_amount_curve = shrink
	_twinkles.color = Color(1.0, 1.0, 0.85)
	add_child(_twinkles)


## Call every tick. `left` is how much longer he stays dazed. `injured` leaves
## a couple of small stars over his head once the daze is over, for as long
## as it is true.
func update(player: Player, dazed: bool, left: float, delta: float, injured: bool = false) -> void:
	if not dazed and not injured:
		if visible:
			visible = false
			_twinkles.emitting = false
		_age = 0.0
		_full = 1.0
		return
	if not visible:
		visible = true
		_full = 1.0 if dazed else 0.0
		reset_physics_interpolation()
	_twinkles.emitting = dazed
	_age += delta
	global_position = player.head_position() + Vector3(0.0, HOVER, 0.0)
	# The ring stays level whichever way he fell.
	global_rotation = Vector3.ZERO

	# 1 for the whole ring of a daze, easing to 0 for what an injury leaves.
	_full = move_toward(_full, 1.0 if dazed else 0.0, delta / FADE_OUT)
	var size: float = minf(_age / POP_IN, 1.0)
	if not injured:
		size *= clampf(left / FADE_OUT, 0.0, 1.0)
	var radius: float = lerpf(INJURED_RING, RING_RADIUS, _full)
	var speed: float = lerpf(INJURED_ORBIT, ORBIT_SPEED, _full)
	_turn += delta * speed
	for i: int in STARS:
		var angle: float = _turn + float(i) * TAU / float(STARS)
		var star: MeshInstance3D = _stars[i]
		# A tilted ring, each star bobbing and pulsing out of step with the others.
		star.position = Vector3(
			cos(angle) * radius,
			sin(angle) * 0.14 * _full + sin(_age * 6.0 + float(i) * 1.7) * 0.05,
			sin(angle) * radius)
		var pulse: float = 0.8 + 0.2 * sin(_age * 9.0 + float(i) * 2.3)
		# An injury keeps only a few of them, and smaller.
		var kept: float = 1.0 if i % 2 == 0 and i < INJURED_STARS * 2 else _full
		var star_size: float = lerpf(INJURED_STAR, STAR_RADIUS, _full) * kept
		star.scale = Vector3.ONE * maxf(star_size * size * pulse, 0.001)
