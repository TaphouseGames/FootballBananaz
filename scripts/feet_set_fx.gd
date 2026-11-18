class_name FeetSetFx
extends Node3D
## The ring on the turf round a quarterback who can throw. While his feet are
## not set it is orange, thin and open, closing as they come under him; the
## moment they are set it snaps shut, turns green and pops outward, and a few
## green sparks rise off it. Purely cosmetic: it reads the player and changes
## nothing.

const SEGMENTS: int = 48
const RADIUS: float = 1.25
const WIDTH_UNSET: float = 0.07
const WIDTH_SET: float = 0.16
const HEIGHT: float = 0.07
const POP_TIME: float = 0.28
const POP_SIZE: float = 0.55
const UNSET_COLOR: Color = Color(1.0, 0.5, 0.1)
const SET_COLOR: Color = Color(0.3, 1.0, 0.4)
const FLASH_COLOR: Color = Color(0.85, 1.0, 0.85)
const SPARKS: int = 16
const SPARK_TIME: float = 0.5
const SPARK_SIZE: float = 0.14

var _ring: MeshInstance3D
var _sparks: CPUParticles3D
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _was_set: bool = true
var _pop: float = 0.0
var _age: float = 0.0
## What was last drawn, so the mesh is only rebuilt when it changes.
var _drawn_share: float = -1.0
var _drawn_width: float = -1.0


func _init() -> void:
	name = "FeetSetFx"
	visible = false
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = ImmediateMesh.new()
	_ring = MeshInstance3D.new()
	_ring.mesh = _mesh
	_ring.material_override = _material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_sparks = _make_sparks()
	add_child(_sparks)


## One burst of small green sparks off the ring, rising and fading.
func _make_sparks() -> CPUParticles3D:
	var sparks: CPUParticles3D = CPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = SPARKS
	sparks.lifetime = SPARK_TIME
	# Left behind where his feet came set, not carried along with him.
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_axis = Vector3.UP
	sparks.emission_ring_radius = RADIUS
	sparks.emission_ring_inner_radius = RADIUS - 0.1
	sparks.emission_ring_height = 0.0
	sparks.direction = Vector3.UP
	sparks.spread = 12.0
	sparks.gravity = Vector3(0.0, -1.5, 0.0)
	sparks.initial_velocity_min = 1.4
	sparks.initial_velocity_max = 2.6
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var fade: Gradient = Gradient.new()
	fade.set_color(0, FLASH_COLOR)
	fade.set_color(1, Color(SET_COLOR, 0.0))
	sparks.color_ramp = fade
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	# A soft round dot, not a square.
	var dot: Gradient = Gradient.new()
	dot.set_color(0, Color.WHITE)
	dot.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = dot
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	material.albedo_texture = texture
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SPARK_SIZE, SPARK_SIZE)
	quad.material = material
	sparks.mesh = quad
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sparks


## Call every tick. `shown` is whether he is a quarterback who can throw now.
func update(player: Player, shown: bool, delta: float) -> void:
	if not shown:
		if visible:
			visible = false
		_was_set = true
		_pop = 0.0
		return
	var is_set: bool = player.feet_set >= 1.0
	if not visible:
		visible = true
		_was_set = is_set
		reset_physics_interpolation()
	_age += delta
	global_position = Vector3(player.global_position.x, HEIGHT, player.global_position.z)
	# Level and unturned, whichever way he faces or spins.
	global_rotation = Vector3.ZERO
	if is_set and not _was_set:
		_pop = POP_TIME
		_sparks.restart()
		player.feet_planted()
	_was_set = is_set
	_pop = maxf(_pop - delta, 0.0)

	var popped: float = _pop / POP_TIME
	var share: float = 1.0
	var width: float = WIDTH_SET
	var color: Color = SET_COLOR.lerp(FLASH_COLOR, popped)
	var size: float = 1.0 + POP_SIZE * popped * popped
	if not is_set:
		# A quarter of it is always there, so there is something to see fill up.
		share = lerpf(0.25, 0.95, clampf(player.feet_set, 0.0, 1.0))
		width = WIDTH_UNSET
		color = UNSET_COLOR
		color.a = 0.65 + 0.35 * sin(_age * 14.0)
		size = 1.0 + 0.06 * sin(_age * 14.0)
	_material.albedo_color = color
	_ring.scale = Vector3(size, 1.0, size)
	_draw(share, width)


## A flat band `width` yards wide, `share` of the way round the circle.
func _draw(share: float, width: float) -> void:
	if is_equal_approx(share, _drawn_share) and is_equal_approx(width, _drawn_width):
		return
	_drawn_share = share
	_drawn_width = width
	_mesh.clear_surfaces()
	var steps: int = maxi(roundi(float(SEGMENTS) * share), 2)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in steps + 1:
		var angle: float = TAU * share * float(i) / float(steps)
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		_mesh.surface_add_vertex(out * (RADIUS - width * 0.5))
		_mesh.surface_add_vertex(out * (RADIUS + width * 0.5))
	_mesh.surface_end()
