class_name Pylon
extends RigidBody3D
## An orange end zone pylon. It is a real rigid body (standing on the Field's
## floor), but players and the ball are moved by hand, so Field.touch_pylons()
## knocks it over with impulses rather than collisions. Stands back up between
## plays.

## Collision layer shared by the pylons and the floor they stand on, and nothing else.
const LAYER: int = 1 << 9
const COLOR: Color = Color(1.0, 0.4, 0.05)

## The goal line (or end line) X this pylon marks the corner of.
var line_x: float = 0.0
## On the goal line: a carried ball touching it is a touchdown.
var front: bool = false
var size: float = 0.16
var height: float = 0.65

var _home: Transform3D


func build(p_size: float, p_height: float, p_mass: float) -> void:
	size = p_size
	height = p_height
	mass = p_mass
	collision_layer = LAYER
	collision_mask = LAYER
	can_sleep = true
	continuous_cd = true

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(size, height, size)
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = height * 0.5
	add_child(collider)
	# Centre of mass at the middle of the box, not at the base the node sits on.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, height * 0.5, 0.0)

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = shape.size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.roughness = 0.8
	# Fluorescent: it should still read orange on its shaded side.
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 0.45
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position.y = height * 0.5
	add_child(visual)


## Call once it is placed: where reset() puts it back.
func set_home() -> void:
	_home = transform
	sleeping = true


## Still where it was put, the right way up.
func is_standing() -> bool:
	return basis.y.y > 0.9 and transform.origin.distance_to(_home.origin) < size


func is_disturbed() -> bool:
	return transform.origin.distance_to(_home.origin) > 0.01 or basis.y.dot(_home.basis.y) < 0.999 \
		or linear_velocity.length_squared() > 0.0025 or angular_velocity.length_squared() > 0.0025


## A shove of `impulse` (yd/s * mass), `at_height` up from its base, so it
## tips over rather than sliding along the turf.
func knock(impulse: Vector3, at_height: float) -> void:
	sleeping = false
	# The offset is from the body's origin (its base), in world axes.
	apply_impulse(impulse, global_basis * Vector3(0.0, at_height, 0.0))


## Back where it was put, standing still.
func reset() -> void:
	if not is_disturbed():
		return
	freeze = true
	transform = _home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	freeze = false
	sleeping = true
	reset_physics_interpolation()


## `point` (world space) is inside the box, grown by `margin` on every side.
func contains(point: Vector3, margin: float) -> bool:
	var local: Vector3 = global_transform.affine_inverse() * point
	var half: float = size * 0.5 + margin
	return absf(local.x) <= half and absf(local.z) <= half and local.y >= -margin and local.y <= height + margin
