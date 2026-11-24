class_name FieldFx
extends Node3D
## Everything the players leave on the turf: cleat prints, scuffs where someone
## went down, and blood. Drops fly on simple arcs and turn into splats where they
## land. Marks and splats stay for the whole game; when a layer is full the
## oldest one is reused.
## Purely cosmetic, with its own random numbers, so the game plays the same.

const MARK_SHADER: Shader = preload("res://assets/field/ground_mark.gdshader")
const SPLAT_SHADER: Shader = preload("res://assets/field/blood_splat.gdshader")
const MAX_DROPS: int = 320
const DROP_GRAVITY: float = 18.0
const MARK_HEIGHT: float = 0.014
const SPLAT_HEIGHT: float = 0.02
const PRINT_COLOR: Color = Color(0.06, 0.12, 0.04, 0.55)
const DIRT_COLOR: Color = Color(0.25, 0.18, 0.09, 0.62)
const BLOOD_COLOR: Color = Color(0.42, 0.015, 0.02, 0.93)
## Jump dives that can land at nearly the same moment and each get their burst.
const IMPACT_POOL: int = 4


## A MultiMesh of ground quads used as a ring buffer.
class Layer:
	extends RefCounted

	var multimesh: MultiMesh
	var next: int = 0

	func stamp(xform: Transform3D, color: Color, custom: Color) -> void:
		var capacity: int = multimesh.instance_count
		if capacity <= 0:
			return
		multimesh.set_instance_transform(next, xform)
		# Instance colours reach the shader as-is, so convert to linear here.
		multimesh.set_instance_color(next, color.srgb_to_linear())
		multimesh.set_instance_custom_data(next, custom)
		next += 1
		if multimesh.visible_instance_count < capacity:
			multimesh.visible_instance_count = next
		next %= capacity


var tuning: Tuning

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _marks: Layer
var _splats: Layer
var _drops: MultiMesh
var _drop_pos: PackedVector3Array = PackedVector3Array()
var _drop_vel: PackedVector3Array = PackedVector3Array()
var _drop_size: PackedFloat32Array = PackedFloat32Array()

## Per player, in the order track() receives them.
var _last_pos: PackedVector3Array = PackedVector3Array()
var _travelled: PackedFloat32Array = PackedFloat32Array()
var _foot_side: PackedFloat32Array = PackedFloat32Array()
var _last_state: PackedInt32Array = PackedInt32Array()

## Emitters for jump-dive landings, made at the first one and used in turn.
var _dust: Array[CPUParticles3D] = []
var _star_bursts: Array[CPUParticles3D] = []
## Small dust puffs (see dust_puff), used in turn.
const PUFF_POOL: int = 6
var _puffs: Array[CPUParticles3D] = []
var _next_puff: int = 0
var _next_impact: int = 0


func setup(p_tuning: Tuning) -> void:
	tuning = p_tuning
	# Instances are moved every rendered frame and reused out of order, so
	# physics interpolation would smear them.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var bounds: AABB = AABB(
		Vector3(-tuning.end_zone_depth - 5.0, -0.5, -tuning.half_width() - 5.0),
		Vector3(tuning.field_length + tuning.end_zone_depth * 2.0 + 10.0, 8.0, tuning.field_width + 10.0))

	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2.ONE
	_marks = _add_layer(quad, _shader_material(MARK_SHADER, 1), tuning.max_footprints, bounds)
	_splats = _add_layer(quad, _shader_material(SPLAT_SHADER, 2), tuning.max_blood_splats, bounds)

	var bead: SphereMesh = SphereMesh.new()
	bead.radius = 0.5
	bead.height = 1.0
	bead.radial_segments = 8
	bead.rings = 4
	var bead_material: StandardMaterial3D = StandardMaterial3D.new()
	bead_material.albedo_color = Color(0.5, 0.02, 0.03)
	bead_material.roughness = 0.2
	_drops = MultiMesh.new()
	_drops.transform_format = MultiMesh.TRANSFORM_3D
	_drops.mesh = bead
	_drops.instance_count = MAX_DROPS
	_drops.visible_instance_count = 0
	_drops.custom_aabb = bounds
	_add_instance(_drops, bead_material)


## Sprays `drops` of blood from chest height at `pos`, thrown mostly along `dir`.
## With `pool`, a bigger splat lands right away where the victim falls.
func blood_burst(pos: Vector3, dir: Vector3, drops: int, pool: bool) -> void:
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.FX, &"blood_burst", [pos, dir, drops, pool])
	if tuning == null or not tuning.blood_enabled:
		return
	var origin: Vector3 = Vector3(pos.x, 1.0, pos.z)
	for i: int in drops:
		if _drop_pos.size() >= MAX_DROPS:
			break
		var spread: Vector3 = Vector3(_rng.randf_range(-2.5, 2.5), _rng.randf_range(1.5, 6.0), _rng.randf_range(-2.5, 2.5))
		_drop_pos.append(origin + Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.3, 0.4), _rng.randf_range(-0.2, 0.2)))
		_drop_vel.append(dir * _rng.randf_range(1.0, 6.5) + spread)
		_drop_size.append(_rng.randf_range(0.07, 0.17))
	if pool:
		var size: float = _rng.randf_range(0.9, 1.4)
		_splat(pos + dir * 0.7, dir, size * 1.3, size)


## A jump dive coming down at `pos`, sliding along `dir` at `speed`: turf and
## dust thrown up the way he is going, stars knocked out of his head, and a
## long gouge in the grass.
func daze_impact(pos: Vector3, dir: Vector3, speed: float) -> void:
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.FX, &"daze_impact", [pos, dir, speed])
	if tuning == null:
		return
	var along: Vector3 = Vector3(dir.x, 0.0, dir.z)
	along = along.normalized() if along.length_squared() > 0.01 else Vector3.RIGHT
	# `speed` is what he slides on at: the dust goes with him.
	var force: float = clampf(speed / 6.0, 0.5, 1.6)
	if _dust.is_empty():
		for i: int in IMPACT_POOL:
			_dust.append(_make_dust())
			_star_bursts.append(_make_star_burst())
	var dust: CPUParticles3D = _dust[_next_impact]
	dust.position = Vector3(pos.x, 0.12, pos.z) + along * 0.5
	dust.direction = (along + Vector3(0.0, 0.7, 0.0)).normalized()
	dust.initial_velocity_min = 1.5 * force
	dust.initial_velocity_max = 6.0 * force
	dust.restart()
	var stars: CPUParticles3D = _star_bursts[_next_impact]
	stars.position = Vector3(pos.x, 0.5, pos.z) + along * 1.2
	stars.direction = (Vector3.UP + along * 0.5).normalized()
	stars.restart()
	_next_impact = (_next_impact + 1) % IMPACT_POOL
	_mark(pos + along * 1.2, along, _rng.randf_range(2.6, 3.4), _rng.randf_range(1.0, 1.4), DIRT_COLOR, 1.0)


## A small puff of dust at `pos`, thrown along `dir` (flat; zero for all round)
## and up: feet planted hard, or a throw off one foot. `force` of 1 is a stamp.
func dust_puff(pos: Vector3, dir: Vector3, force: float) -> void:
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.FX, &"dust_puff", [pos, dir, force])
	if tuning == null:
		return
	if _puffs.is_empty():
		for i: int in PUFF_POOL:
			var small: CPUParticles3D = _make_dust()
			small.amount = 10
			small.lifetime = 0.5
			_puffs.append(small)
	var along: Vector3 = Vector3(dir.x, 0.0, dir.z)
	var puff: CPUParticles3D = _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % PUFF_POOL
	puff.position = Vector3(pos.x, 0.1, pos.z)
	if along.length_squared() > 0.01:
		puff.direction = (along.normalized() + Vector3(0.0, 0.6, 0.0)).normalized()
		puff.spread = 40.0
	else:
		puff.direction = Vector3.UP
		puff.spread = 80.0
	puff.initial_velocity_min = 0.8 * force
	puff.initial_velocity_max = 2.6 * force
	puff.restart()


func _make_dust() -> CPUParticles3D:
	var puff: QuadMesh = QuadMesh.new()
	puff.size = Vector2(0.5, 0.5)
	var fill: Gradient = Gradient.new()
	fill.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fill.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var round_spot: GradientTexture2D = GradientTexture2D.new()
	round_spot.gradient = fill
	round_spot.fill = GradientTexture2D.FILL_RADIAL
	round_spot.fill_from = Vector2(0.5, 0.5)
	round_spot.fill_to = Vector2(1.0, 0.5)
	round_spot.width = 32
	round_spot.height = 32
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = round_spot
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(0.62, 0.52, 0.34, 0.85))
	fade.set_color(1, Color(0.45, 0.5, 0.3, 0.0))
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))

	var dust: CPUParticles3D = _make_burst(puff, material, 30, 0.8)
	dust.spread = 40.0
	dust.gravity = Vector3(0.0, -5.0, 0.0)
	dust.damping_min = 3.0
	dust.damping_max = 6.0
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.2
	dust.scale_amount_curve = grow
	dust.color_ramp = fade
	return dust


func _make_star_burst() -> CPUParticles3D:
	var shrink: Curve = Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.6, 0.9))
	shrink.add_point(Vector2(1.0, 0.0))
	var stars: CPUParticles3D = _make_burst(DazeFx.star_mesh(), DazeFx.star_material(true), 9, 0.85)
	stars.direction = Vector3.UP
	stars.spread = 65.0
	stars.gravity = Vector3(0.0, -11.0, 0.0)
	stars.initial_velocity_min = 3.0
	stars.initial_velocity_max = 6.5
	stars.scale_amount_min = 0.09
	stars.scale_amount_max = 0.17
	stars.scale_amount_curve = shrink
	return stars


## A one-shot emitter that fires its whole `amount` at once on restart().
func _make_burst(mesh: Mesh, material: Material, amount: int, lifetime: float) -> CPUParticles3D:
	var burst: CPUParticles3D = CPUParticles3D.new()
	burst.mesh = mesh
	burst.material_override = material
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.amount = amount
	burst.lifetime = lifetime
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.emitting = false
	add_child(burst)
	return burst


## Call once per physics tick, after the players have moved.
func track(players: Array[Player]) -> void:
	if tuning == null:
		return
	if _last_pos.size() != players.size():
		_last_pos.resize(players.size())
		_travelled.resize(players.size())
		_foot_side.resize(players.size())
		_last_state.resize(players.size())
		for i: int in players.size():
			_last_pos[i] = players[i].position
			_travelled[i] = 0.0
			_foot_side[i] = 1.0
			_last_state[i] = players[i].state
		return

	for i: int in players.size():
		var player: Player = players[i]
		var step: Vector3 = player.position - _last_pos[i]
		step.y = 0.0
		var moved: float = step.length()
		_last_pos[i] = player.position
		var down: bool = player.state == Player.State.DOWN
		if down and _last_state[i] != Player.State.DOWN:
			# Hit the ground: tear up a patch of turf.
			_mark(player.position, player.facing, _rng.randf_range(1.2, 1.7), _rng.randf_range(0.9, 1.3), DIRT_COLOR, 1.0)
		_last_state[i] = player.state

		# A big jump in position is the lineup, not running.
		if moved < 0.0005 or moved > 2.0:
			continue
		if player.state == Player.State.JUMPING or player.state == Player.State.DIVING:
			continue
		_travelled[i] += moved
		var dir: Vector3 = step / moved
		if down:
			# Sliding on the ground leaves a skid.
			if _travelled[i] >= 0.4:
				_travelled[i] = 0.0
				_mark(player.position, dir, 0.95, 0.6, Color(DIRT_COLOR, 0.4), 1.0)
		elif _travelled[i] >= tuning.footprint_stride:
			_travelled[i] = 0.0
			_foot_side[i] = -_foot_side[i]
			var side: Vector3 = Vector3(-dir.z, 0.0, dir.x) * (0.16 * _foot_side[i])
			_mark(player.position + side, dir, 0.38, 0.18, PRINT_COLOR, 0.0)


func _process(delta: float) -> void:
	var count: int = _drop_pos.size()
	if count == 0:
		if _drops != null and _drops.visible_instance_count != 0:
			_drops.visible_instance_count = 0
		return
	var i: int = 0
	while i < count:
		var vel: Vector3 = _drop_vel[i]
		vel.y -= DROP_GRAVITY * delta
		var pos: Vector3 = _drop_pos[i] + vel * delta
		if pos.y <= 0.0:
			var flat: Vector3 = Vector3(vel.x, 0.0, vel.z)
			var speed: float = flat.length()
			var dir: Vector3 = flat / speed if speed > 0.01 else Vector3.RIGHT
			var width: float = _drop_size[i] * _rng.randf_range(2.6, 4.2)
			_splat(pos, dir, width * (1.0 + minf(speed * 0.16, 1.3)), width)
			# Swap in the last drop and look at this slot again.
			count -= 1
			_drop_pos[i] = _drop_pos[count]
			_drop_vel[i] = _drop_vel[count]
			_drop_size[i] = _drop_size[count]
			continue
		_drop_pos[i] = pos
		_drop_vel[i] = vel
		_drops.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * _drop_size[i]), pos))
		i += 1
	_drop_pos.resize(count)
	_drop_vel.resize(count)
	_drop_size.resize(count)
	_drops.visible_instance_count = count


func _splat(pos: Vector3, dir: Vector3, length: float, width: float) -> void:
	var color: Color = BLOOD_COLOR.darkened(_rng.randf_range(0.0, 0.3))
	color.a = BLOOD_COLOR.a
	_splats.stamp(_ground_transform(pos, dir, length, width, SPLAT_HEIGHT), color, Color(_rng.randf(), 0.0, 0.0, 0.0))


## `kind` is 0 for a cleat print, 1 for a scuff (see ground_mark.gdshader).
func _mark(pos: Vector3, dir: Vector3, length: float, width: float, color: Color, kind: float) -> void:
	_marks.stamp(_ground_transform(pos, dir, length, width, MARK_HEIGHT), color, Color(_rng.randf(), kind, 0.0, 0.0))


## A flat quad `length` x `width`, its long side along `dir`.
func _ground_transform(pos: Vector3, dir: Vector3, length: float, width: float, height: float) -> Transform3D:
	var yaw: float = atan2(-dir.z, dir.x)
	return Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(length, 1.0, width)), Vector3(pos.x, height, pos.z))


func _shader_material(shader: Shader, priority: int) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	return material


func _add_layer(mesh: Mesh, material: Material, capacity: int, bounds: AABB) -> Layer:
	var layer: Layer = Layer.new()
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_colors = true
	layer.multimesh.use_custom_data = true
	layer.multimesh.mesh = mesh
	layer.multimesh.instance_count = maxi(capacity, 0)
	layer.multimesh.visible_instance_count = 0
	layer.multimesh.custom_aabb = bounds
	_add_instance(layer.multimesh, material)
	return layer


func _add_instance(multimesh: MultiMesh, material: Material) -> void:
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
