class_name LookBase
extends RefCounted
## One of the two base models every player is built on, made ready once and
## shared by every PlayerModel: its mesh with what the body shader and the
## sliders need baked in, and the measurements of its head that hair, nose and
## glasses are fitted to.
##
## Everything here is in the mesh's own space: x across (the player's left is
## positive), y back (the face looks down negative y), z up, 1 tall.

const PATHS: PackedStringArray = [
	"res://TripoModels/rugged_humanoid_3d_model/rugged_humanoid_3d_model.fbx",
	"res://TripoModels/armored_humanoid_3d_model/armored_humanoid_3d_model.fbx",
]
## Per base (see PlayerLook.Base): the height of the point of the chin, and of
## the bottom of the map the face is painted in.
const CHIN_Z: PackedFloat32Array = [0.742, 0.782]
const MAP_LOW_Z: PackedFloat32Array = [0.7, 0.745]
const BELT_Z: PackedFloat32Array = [0.5, 0.515]
## Where the jersey is printed: centre height, half width, half height.
const FRONT_NUMBER: PackedVector3Array = [Vector3(0.61, 0.058, 0.044), Vector3(0.628, 0.05, 0.038)]
const BACK_NUMBER: PackedVector3Array = [Vector3(0.585, 0.07, 0.052), Vector3(0.61, 0.064, 0.048)]
const BACK_NAME: PackedVector3Array = [Vector3(0.668, 0.084, 0.021), Vector3(0.69, 0.078, 0.0195)]

## Where the features sit on the head: heights as a share of chin to crown,
## the eyes' distance from the middle as a share of half the head's width.
const EYE_HEIGHT: float = 0.47
const EYE_APART: float = 0.4
const NOSE_HEIGHT: float = 0.33
const MOUTH_HEIGHT: float = 0.17

## How far a vertex moves with each slider all the way up.
const FAT_DEPTH: float = 0.04
const BELLY_DEPTH: float = 0.05
const FOREHEAD_RISE: float = 0.2
## How far the new points of the finer head are pulled out onto the curve its
## normals describe: 0 leaves it as faceted as it was.
const HEAD_ROUNDING: float = 0.75
## How often the head is cut finer again for the hair grown from it.
const HAIR_CUTS: int = 0

static var _cache: Dictionary[int, LookBase] = {}

var base: int
var scene: PackedScene
## The base's mesh with the vertex colour and CUSTOM0 the body shader reads
## (see look_body.gdshader) and the blend shapes "weight", "forehead", "chin".
var mesh: ArrayMesh
var albedo: Texture2D
var normal_map: Texture2D

var chin_z: float
var top_z: float
var map_low_z: float
## The upright line through the middle of the head.
var axis_y: float
var half_width: float
## From that line to the front of the face.
var face_radius: float

## The head as a mesh of its own, cut finer, for the hair: places at rest,
## normals, how far each moves with the forehead and the chin slider, and the
## corners of its triangles.
var scalp_points: PackedVector3Array = PackedVector3Array()
var scalp_normals: PackedVector3Array = PackedVector3Array()
var scalp_forehead: PackedVector3Array = PackedVector3Array()
var scalp_chin: PackedVector3Array = PackedVector3Array()
var scalp_indices: PackedInt32Array = PackedInt32Array()


static func of(which: int) -> LookBase:
	if not _cache.has(which):
		_cache[which] = LookBase.new(which)
	return _cache[which]


func _init(which: int) -> void:
	base = which
	chin_z = CHIN_Z[which]
	map_low_z = MAP_LOW_Z[which]
	scene = load(PATHS[which])
	_bake()


## How high `z` is on the head: 0 at the chin, 1 at the crown.
func head_height(z: float) -> float:
	return (z - chin_z) / (top_z - chin_z)


func head_z(height: float) -> float:
	return chin_z + height * (top_z - chin_z)


## Which way round the head `point` is: 0 at the front, positive to the
## player's left, PI at the back.
func azimuth(point: Vector3) -> float:
	return atan2(point.x, -(point.y - axis_y))


## The y of the face's surface at `x`, `z`: the front-most point nearby.
func front_y(x: float, z: float) -> float:
	var best: float = INF
	var best_y: float = axis_y - face_radius
	for i: int in scalp_points.size():
		var point: Vector3 = scalp_points[i]
		if point.y > axis_y:
			continue
		var gap: float = Vector2(point.x - x, point.z - z).length_squared()
		if gap < best:
			best = gap
			best_y = point.y
	return best_y


## The point of the head nearest to `azimuth_at` round it and `height` up it,
## with the forehead and chin sliders at `forehead` and `chin` (blend weights).
func scalp_point(azimuth_at: float, height: float, forehead: float, chin: float) -> Vector3:
	var best: float = INF
	var found: int = 0
	for i: int in scalp_points.size():
		var point: Vector3 = scalp_points[i]
		var turn: float = angle_difference(azimuth(point), azimuth_at)
		var gap: float = turn * turn + pow((head_height(point.z) - height) * 2.0, 2.0)
		if gap < best:
			best = gap
			found = i
	return scalp_points[found] + scalp_forehead[found] * forehead + scalp_chin[found] * chin


# --- Baking --------------------------------------------------------------------------

func _bake() -> void:
	var root: Node = scene.instantiate()
	var instance: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skeleton: Skeleton3D = instance.get_parent() as Skeleton3D
	var source: ArrayMesh = instance.mesh as ArrayMesh
	var skin: Skin = instance.skin
	var material: BaseMaterial3D = source.surface_get_material(0) as BaseMaterial3D
	if material != null:
		albedo = material.albedo_texture
		normal_map = material.normal_texture

	# What each bone of the skin is worth: [head, neck, hand, arm, fat].
	var worth: Array[PackedFloat32Array] = []
	for bind: int in skin.get_bind_count():
		var bone: String = skin.get_bind_name(bind)
		if bone == "" and skeleton != null:
			bone = skeleton.get_bone_name(skin.get_bind_bone(bind))
		worth.append(_bone_worth(bone))
	root.free()

	var arrays: Array = source.surface_get_arrays(0)
	HeadRefiner.new(arrays, worth).refine()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count: int = points.size()
	@warning_ignore("integer_division")
	var per: int = bones.size() / count

	# The texture's seams split the mesh into many pieces that share places:
	# one number per place, and the normal all its pieces agree on.
	var welded: PackedInt32Array = PackedInt32Array()
	welded.resize(count)
	var place_of: Dictionary[Vector3i, int] = {}
	var smooth_sum: PackedVector3Array = PackedVector3Array()
	for i: int in count:
		var key: Vector3i = Vector3i((points[i] * 20000.0).round())
		if not place_of.has(key):
			place_of[key] = smooth_sum.size()
			smooth_sum.append(Vector3.ZERO)
		welded[i] = place_of[key]
		smooth_sum[welded[i]] += normals[i]

	var shares: Array[PackedFloat32Array] = []
	var low: Vector3 = Vector3.INF
	var high: Vector3 = -Vector3.INF
	for i: int in count:
		var share: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
		for k: int in per:
			var weight: float = weights[i * per + k]
			if weight <= 0.0:
				continue
			var bone_worth: PackedFloat32Array = worth[bones[i * per + k]]
			for part: int in 5:
				share[part] += weight * bone_worth[part]
		shares.append(share)
		if share[0] > 0.9:
			low = low.min(points[i])
			high = high.max(points[i])
	top_z = high.z
	axis_y = (low.y + high.y) / 2.0
	half_width = (high.x - low.x) / 2.0
	face_radius = axis_y - low.y

	var colors: PackedColorArray = PackedColorArray()
	colors.resize(count)
	var custom: PackedFloat32Array = PackedFloat32Array()
	custom.resize(count * 4)
	var fat: PackedVector3Array = PackedVector3Array()
	fat.resize(count)
	var forehead: PackedVector3Array = PackedVector3Array()
	forehead.resize(count)
	var chin: PackedVector3Array = PackedVector3Array()
	chin.resize(count)
	for i: int in count:
		var share: PackedFloat32Array = shares[i]
		var point: Vector3 = points[i]
		var smooth: Vector3 = smooth_sum[welded[i]].normalized()
		colors[i] = Color(minf(share[0] + share[1], 1.0), share[2], share[3], 1.0)
		custom[i * 4] = point.x
		custom[i * 4 + 1] = point.y
		custom[i * 4 + 2] = point.z
		custom[i * 4 + 3] = smooth.y
		fat[i] = _fat_move(point, smooth, share[4])
		forehead[i] = _forehead_move(point) * share[0]
		chin[i] = _chin_move(point) * share[0]

	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	mesh = ArrayMesh.new()
	# A blend shape is handed over as how far each vertex moves, not where it
	# ends up. The normals and tangents stay as they are.
	var still_normals: PackedVector3Array = PackedVector3Array()
	still_normals.resize(count)
	var still_tangents: PackedFloat32Array = PackedFloat32Array()
	still_tangents.resize(count * 4)
	var shapes: Array[Array] = []
	for shape: PackedVector3Array in [fat, forehead, chin]:
		var shape_arrays: Array = []
		shape_arrays.resize(Mesh.ARRAY_MAX)
		shape_arrays[Mesh.ARRAY_VERTEX] = shape
		shape_arrays[Mesh.ARRAY_NORMAL] = still_normals
		shape_arrays[Mesh.ARRAY_TANGENT] = still_tangents
		shapes.append(shape_arrays)
	for shape_name: StringName in [&"weight", &"forehead", &"chin"]:
		mesh.add_blend_shape(shape_name)
	var format: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes, {}, format)
	_bake_scalp(points, indices, welded, smooth_sum, shares)


## The head alone, its pieces joined at the seams, then cut finer.
func _bake_scalp(points: PackedVector3Array, indices: PackedInt32Array, welded: PackedInt32Array,
		smooth_sum: PackedVector3Array, shares: Array[PackedFloat32Array]) -> void:
	var scalp_of: Dictionary[int, int] = {}
	var head_share: PackedFloat32Array = PackedFloat32Array()
	@warning_ignore("integer_division")
	for triangle: int in indices.size() / 3:
		var corners: PackedInt32Array = PackedInt32Array()
		for k: int in 3:
			var vertex: int = indices[triangle * 3 + k]
			if shares[vertex][0] < 0.5:
				break
			var place: int = welded[vertex]
			if not scalp_of.has(place):
				scalp_of[place] = scalp_points.size()
				scalp_points.append(points[vertex])
				scalp_normals.append(smooth_sum[place].normalized())
				head_share.append(shares[vertex][0])
			corners.append(scalp_of[place])
		if corners.size() == 3 and corners[0] != corners[1] and corners[1] != corners[2] and corners[0] != corners[2]:
			scalp_indices.append_array(corners)
	for cut: int in HAIR_CUTS:
		var middle_of: Dictionary[Vector2i, int] = {}
		var finer: PackedInt32Array = PackedInt32Array()
		@warning_ignore("integer_division")
		for triangle: int in scalp_indices.size() / 3:
			var a: int = scalp_indices[triangle * 3]
			var b: int = scalp_indices[triangle * 3 + 1]
			var c: int = scalp_indices[triangle * 3 + 2]
			var ab: int = _middle(a, b, middle_of, head_share)
			var bc: int = _middle(b, c, middle_of, head_share)
			var ca: int = _middle(c, a, middle_of, head_share)
			finer.append_array(PackedInt32Array([a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca]))
		scalp_indices = finer
	for i: int in scalp_points.size():
		scalp_forehead.append(_forehead_move(scalp_points[i]) * head_share[i])
		scalp_chin.append(_chin_move(scalp_points[i]) * head_share[i])


func _middle(a: int, b: int, middle_of: Dictionary[Vector2i, int], head_share: PackedFloat32Array) -> int:
	var key: Vector2i = Vector2i(mini(a, b), maxi(a, b))
	if not middle_of.has(key):
		middle_of[key] = scalp_points.size()
		scalp_points.append((scalp_points[a] + scalp_points[b]) / 2.0)
		scalp_normals.append((scalp_normals[a] + scalp_normals[b]).normalized())
		head_share.append((head_share[a] + head_share[b]) / 2.0)
	return middle_of[key]


## [head, neck, hand, arm, how much it fills out with weight] for a bone.
func _bone_worth(bone: String) -> PackedFloat32Array:
	for finger: String in ["Hand", "Pinky", "Ring", "Mid", "Index", "Thumb"]:
		if bone.contains(finger):
			return PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0])
	if bone.contains("Head") or bone.contains("Facial") or bone.contains("Eye"):
		return PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0])
	if bone.contains("Neck"):
		return PackedFloat32Array([0.0, 1.0, 0.0, 0.0, 0.3])
	if bone.contains("Upperarm"):
		return PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.55])
	if bone.contains("Forearm") or bone.contains("Elbow"):
		return PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.35])
	var fat: float = 0.0
	if bone.contains("Waist") or bone.contains("Spine01"):
		fat = 1.0
	elif bone.contains("Pelvis") or bone.contains("Hip") or bone.contains("BoneRoot"):
		fat = 0.9
	elif bone.contains("Spine02"):
		fat = 0.75
	elif bone.contains("Clavicle"):
		fat = 0.5
	elif bone.contains("Thigh"):
		fat = 0.75
	elif bone.contains("Calf") or bone.contains("Knee"):
		fat = 0.4
	return PackedFloat32Array([0.0, 0.0, 0.0, 0.0, fat])


## Heavier: out along the surface everywhere, and a belly out in front.
func _fat_move(point: Vector3, smooth: Vector3, fat: float) -> Vector3:
	var move: Vector3 = smooth * FAT_DEPTH * fat
	var belly: float = exp(-pow((point.z - 0.56) / 0.085, 2.0)) * maxf(-smooth.y, 0.0) * fat
	move.y -= BELLY_DEPTH * belly
	return move


## A bigger forehead: everything above the brow rises and swells a little.
func _forehead_move(point: Vector3) -> Vector3:
	var height: float = head_height(point.z)
	var rise: float = smoothstep(EYE_HEIGHT + 0.08, 1.0, height)
	var swell: float = smoothstep(EYE_HEIGHT + 0.08, 0.85, height) * 0.1
	return Vector3(point.x * swell, (point.y - axis_y) * swell, (top_z - chin_z) * FOREHEAD_RISE * rise)


## A bigger chin: the front of the jaw grows away from the mouth.
func _chin_move(point: Vector3) -> Vector3:
	var height: float = head_height(point.z)
	var low: float = smoothstep(MOUTH_HEIGHT + 0.14, 0.02, height)
	var front: float = smoothstep(axis_y + 0.2 * face_radius, axis_y - 0.4 * face_radius, point.y)
	var grow: float = low * front
	return Vector3(point.x * 0.3, (point.y - axis_y) * 0.22, (point.z - head_z(MOUTH_HEIGHT + 0.14)) * 0.55) * grow


## Cuts every triangle of the head in four and rounds it off, so the face is
## not the few flat faces the base model has there. The triangles next to the
## head are cut to match, so no gap opens. Works on a surface's arrays in place.
class HeadRefiner:
	var arrays: Array
	var points: PackedVector3Array
	var normals: PackedVector3Array
	var tangents: PackedFloat32Array
	var uvs: PackedVector2Array
	var bones: PackedInt32Array
	var weights: PackedFloat32Array
	var per: int
	var on_head: PackedByteArray = PackedByteArray()
	## Per vertex the normal everything at its place agrees on (the texture's
	## seams split the mesh into pieces that share places).
	var smooth: PackedVector3Array = PackedVector3Array()
	var middle_of: Dictionary[Vector2i, int] = {}

	func _init(surface: Array, worth: Array[PackedFloat32Array]) -> void:
		arrays = surface
		points = arrays[Mesh.ARRAY_VERTEX]
		normals = arrays[Mesh.ARRAY_NORMAL]
		tangents = arrays[Mesh.ARRAY_TANGENT]
		uvs = arrays[Mesh.ARRAY_TEX_UV]
		bones = arrays[Mesh.ARRAY_BONES]
		weights = arrays[Mesh.ARRAY_WEIGHTS]
		var count: int = points.size()
		@warning_ignore("integer_division")
		per = bones.size() / count
		var sums: Dictionary[Vector3i, Vector3] = {}
		var keys: Array[Vector3i] = []
		for i: int in count:
			var share: float = 0.0
			for k: int in per:
				share += weights[i * per + k] * worth[bones[i * per + k]][0]
			on_head.append(1 if share > 0.5 else 0)
			var key: Vector3i = Vector3i((points[i] * 20000.0).round())
			keys.append(key)
			sums[key] = sums.get(key, Vector3.ZERO) + normals[i]
		for i: int in count:
			smooth.append(sums[keys[i]].normalized())

	func refine() -> void:
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var finer: PackedInt32Array = PackedInt32Array()
		@warning_ignore("integer_division")
		for triangle: int in indices.size() / 3:
			var corner: PackedInt32Array = indices.slice(triangle * 3, triangle * 3 + 3)
			# The middle of the edge from each corner to the next, where it is cut.
			var middle: PackedInt32Array = PackedInt32Array([-1, -1, -1])
			var cuts: int = 0
			for k: int in 3:
				var a: int = corner[k]
				var b: int = corner[(k + 1) % 3]
				if on_head[a] == 1 and on_head[b] == 1:
					middle[k] = _middle(a, b)
					cuts += 1
			if cuts == 0:
				finer.append_array(corner)
			elif cuts == 3:
				finer.append_array(PackedInt32Array([
					corner[0], middle[0], middle[2], middle[0], corner[1], middle[1],
					middle[2], middle[1], corner[2], middle[0], middle[1], middle[2],
				]))
			elif cuts == 1:
				var k: int = 0 if middle[0] >= 0 else (1 if middle[1] >= 0 else 2)
				var a: int = corner[k]
				var b: int = corner[(k + 1) % 3]
				var other: int = corner[(k + 2) % 3]
				finer.append_array(PackedInt32Array([a, middle[k], other, middle[k], b, other]))
			else:
				# From the one edge left whole.
				var k: int = 0 if middle[0] < 0 else (1 if middle[1] < 0 else 2)
				var a: int = corner[k]
				var b: int = corner[(k + 1) % 3]
				var other: int = corner[(k + 2) % 3]
				var after: int = middle[(k + 1) % 3]
				var before: int = middle[(k + 2) % 3]
				finer.append_array(PackedInt32Array([a, b, after, a, after, before, before, after, other]))
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_INDEX] = finer

	## The new vertex in the middle of the edge from `a` to `b`: half way
	## between them in everything, and pulled out onto the curve their
	## normals describe.
	func _middle(a: int, b: int) -> int:
		var key: Vector2i = Vector2i(mini(a, b), maxi(a, b))
		if middle_of.has(key):
			return middle_of[key]
		var index: int = points.size()
		middle_of[key] = index
		var half_way: Vector3 = (points[a] + points[b]) / 2.0
		var on_a: Vector3 = half_way - smooth[a] * (half_way - points[a]).dot(smooth[a])
		var on_b: Vector3 = half_way - smooth[b] * (half_way - points[b]).dot(smooth[b])
		points.append(half_way.lerp((on_a + on_b) / 2.0, LookBase.HEAD_ROUNDING))
		normals.append((normals[a] + normals[b]).normalized())
		smooth.append((smooth[a] + smooth[b]).normalized())
		on_head.append(1)
		uvs.append((uvs[a] + uvs[b]) / 2.0)
		var tangent: Vector3 = Vector3(tangents[a * 4] + tangents[b * 4], tangents[a * 4 + 1] + tangents[b * 4 + 1], tangents[a * 4 + 2] + tangents[b * 4 + 2]).normalized()
		tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, tangents[a * 4 + 3]]))
		# Half of each end's bones, the heaviest of them kept.
		var shares: Dictionary[int, float] = {}
		for end: int in [a, b]:
			for k: int in per:
				var bone: int = bones[end * per + k]
				shares[bone] = shares.get(bone, 0.0) + weights[end * per + k] * 0.5
		var heaviest: Array[int] = shares.keys()
		heaviest.sort_custom(func(one: int, two: int) -> bool: return shares[one] > shares[two])
		var total: float = 0.0
		for k: int in mini(per, heaviest.size()):
			total += shares[heaviest[k]]
		for k: int in per:
			if k < heaviest.size() and total > 0.0:
				bones.append(heaviest[k])
				weights.append(shares[heaviest[k]] / total)
			else:
				bones.append(0)
				weights.append(0.0)
		return index
