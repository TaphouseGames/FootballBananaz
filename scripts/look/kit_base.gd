class_name KitBase
extends RefCounted
## One of the uniform bodies players are built on (see PlayerParts.BODIES:
## white all over, no skin, no head), made ready once and shared by every
## PlayerModel: its mesh with what kit_body.gdshader needs baked in, where the
## parts of the kit and its print go, and the head models fitted to its collar.
##
## Everything here is in the body's own space: x across (the player's left is
## positive), y back (the front looks down negative y), z up, the feet at 0.

## How much of the collar's width the neck fills where it goes into it, and
## how far up the head model (as a share of its height) it is back to the
## width it was modelled with.
const NECK_FILL: float = 0.8
const NECK_FLARE: float = 0.12
## How much of the collar's opening a neck may fill below the collar's rim.
const NECK_HOLD: float = 0.9
## How far above the rim (as a share of the head model's height) that hold ends.
const NECK_HOLD_FADE: float = 0.06
## How deep the band at the top of the body is that counts as the collar's rim.
const COLLAR_RIM: float = 0.035
## How far above the top of the waistband the jersey is back to its own bones
## (see _tuck()), on a body HEAD_UNIT tall.
const TUCK_FADE: float = 0.05
## How tall, to the top of its collar, the body is that the heads' fit
## (PlayerParts.HEADS) is given for.
const HEAD_UNIT: float = 0.8

static var _cache: Dictionary[String, KitBase] = {}
## The whole characters still to be made ahead of time (see warm_start()).
static var _warming: PackedStringArray = PackedStringArray()

var id: String
var scene: PackedScene
## The body's mesh with the vertex colour and CUSTOM0 the shader reads.
var mesh: ArrayMesh
var albedo: Texture2D
var normal_map: Texture2D
## A whole character (PlayerParts.PEOPLE) and not a body that takes a head:
## its roughness, and the mask kit_person.gdshader repaints it by.
var is_person: bool = false
var roughness_map: Texture2D
var mask: Texture2D
## How high the top of a person and the middle of the head are.
var _top: float = 0.0
var _head_middle: float = 0.0
## The top of the collar, and the middle and half the size of its rim.
var collar_top: float = 0.0
var collar_middle: Vector2 = Vector2.ZERO
var collar_half: Vector2 = Vector2.ZERO
## Heights at rest: the waistband, the hem of the pants, the top of the boots.
var belt_z: float
var hem_z: float
var boot_z: float
## Where the jersey is printed: centre height, half width, half height.
var front_number: Vector3
var back_number: Vector3
var back_name: Vector3

## Per head id: [its mesh fitted to this body, in the body's space; the
## height of the top of it; the height of the middle of the head].
var _heads: Dictionary[String, Array] = {}
## How much bigger than usual heads are on this body (PlayerParts.BODIES).
var _head_scale: float = 1.0
## How much bigger than his height says a player with this body is.
var body_scale: float = 1.0


## The body with this id in PlayerParts.BODIES.
static func of(body: String) -> KitBase:
	if not _cache.has(body):
		_cache[body] = KitBase.new(body)
	return _cache[body]


## The whole character with this id in PlayerParts.PEOPLE.
static func of_person(person: String) -> KitBase:
	var key: String = "person:" + person
	if not _cache.has(key):
		_cache[key] = KitBase.new(person, true)
	return _cache[key]


## Gets the whole characters `people` ready ahead of the screen that shows
## them: their files are read on another thread from now on, and warm_step()
## makes one of them at a time. Anything asked for before its turn is made
## there and then, as without this.
static func warm_start(people: PackedStringArray) -> void:
	for person: String in people:
		if _cache.has("person:" + person) or _warming.has(person) or not PlayerParts.PEOPLE.has(person):
			continue
		var who: Dictionary = PlayerParts.PEOPLE[person]
		if not ResourceLoader.exists(who["path"]) or not ResourceLoader.exists(who["mask"]):
			continue
		ResourceLoader.load_threaded_request(who["path"])
		ResourceLoader.load_threaded_request(who["mask"])
		_warming.append(person)


## Makes the next character of warm_start() whose files have been read, if
## there is one: at most one a call, so a frame is not held up for long. False
## once there is nothing left to make.
static func warm_step() -> bool:
	for i: int in _warming.size():
		var person: String = _warming[i]
		var who: Dictionary = PlayerParts.PEOPLE[person]
		var waiting: bool = false
		for path: String in [who["path"], who["mask"]]:
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				waiting = true
		if waiting:
			continue
		of_person(person)
		return true
	return not _warming.is_empty()


## The resource at `path`: taken over from the thread that is reading it for
## warm_start() (waiting for it if it is not done), or loaded here.
static func _take(path: String) -> Resource:
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var read: Resource = ResourceLoader.load_threaded_get(path)
		if read != null:
			return read
	return load(path)


func _init(body: String, person: bool = false) -> void:
	id = body
	is_person = person
	if person:
		var who: Dictionary = PlayerParts.PEOPLE[body]
		scene = _take(who["path"])
		mask = _take(who["mask"])
		var warming: int = _warming.find(body)
		if warming >= 0:
			_warming.remove_at(warming)
		_bake_person(who)
		return
	var entry: Dictionary = PlayerParts.BODIES[body]
	_head_scale = entry.get("head_scale", 1.0)
	body_scale = entry.get("scale", 1.0)
	scene = load(entry["path"])
	_bake(entry)


## The head with this id in PlayerParts.HEADS as a mesh that sits in this
## body's collar.
func head_mesh(head: String) -> ArrayMesh:
	return null if is_person else _head(head)[0]


## How high the top of that head is, which is how tall the player is.
func top_z(head: String) -> float:
	return _top if is_person else _head(head)[1]


## How high the middle of that head is.
func head_middle_z(head: String) -> float:
	return _head_middle if is_person else _head(head)[2]


func _head(head: String) -> Array:
	if not _heads.has(head):
		_heads[head] = _fit_head(head)
	return _heads[head]


## Brings a head model into the body's space: its neck line in the collar,
## over the collar's middle, and the neck below its flare narrowed to go into
## the collar, whatever width it was modelled with.
func _fit_head(head: String) -> Array:
	# A head's fit is in the units of a body HEAD_UNIT tall to its collar; the
	# models come in at whatever size their longest side makes them.
	var unit: float = collar_top / HEAD_UNIT
	var size: float = PlayerParts.head_fit(head, "size") * unit * _head_scale
	var sink: float = PlayerParts.head_fit(head, "sink") * unit
	var forward: float = PlayerParts.head_fit(head, "forward") * unit
	var neck_share: float = PlayerParts.head_fit(head, "neck")
	var flare_share: float = PlayerParts.head_fit(head, "flare")
	var tilt: float = deg_to_rad(PlayerParts.head_fit(head, "tilt"))
	var path: String = PlayerParts.HEADS[head]["path"]
	var root: Node = (load(path) as PackedScene).instantiate()
	var source: ArrayMesh = (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh as ArrayMesh
	root.free()
	var arrays: Array = source.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var low: float = INF
	var high: float = -INF
	for point: Vector3 in points:
		low = minf(low, point.z)
		high = maxf(high, point.z)
	var tall: float = high - low
	var line: float = low + tall * neck_share
	# The neck where it meets the collar: its middle and half its size.
	var neck_low: Vector2 = Vector2.INF
	var neck_high: Vector2 = -Vector2.INF
	for point: Vector3 in points:
		if absf(point.z - line) < tall * 0.04:
			neck_low = neck_low.min(Vector2(point.x, point.y))
			neck_high = neck_high.max(Vector2(point.x, point.y))
	var neck_middle: Vector2 = (neck_low + neck_high) / 2.0
	var neck_half: Vector2 = (neck_high - neck_low) / 2.0
	# A neck leans: the middle of its bottom is not under the middle of the
	# line. What is below the line is stood up straight, so it stays inside
	# the collar all the way down.
	var foot_low: Vector2 = Vector2.INF
	var foot_high: Vector2 = -Vector2.INF
	for point: Vector3 in points:
		if point.z < low + tall * 0.03:
			foot_low = foot_low.min(Vector2(point.x, point.y))
			foot_high = foot_high.max(Vector2(point.x, point.y))
	var lean: Vector2 = neck_middle - (foot_low + foot_high) / 2.0
	var grow: float = size / tall
	var narrow: Vector2 = Vector2(
		clampf(NECK_FILL * collar_half.x / maxf(neck_half.x * grow, 0.0001), 0.3, 1.0),
		clampf(NECK_FILL * collar_half.y / maxf(neck_half.y * grow, 0.0001), 0.3, 1.0))
	# Where the rim of the collar is on the model.
	var rim: float = line + sink / grow
	var at: Vector3 = Vector3(collar_middle.x, collar_middle.y - forward, collar_top - sink)
	for i: int in points.size():
		var point: Vector3 = points[i]
		var flare: float = smoothstep(line, line + tall * flare_share, point.z)
		var upright: Vector2 = lean * clampf((line - point.z) / maxf(line - low, 0.0001), 0.0, 1.0)
		var across: Vector2 = (Vector2(point.x, point.y) + upright - neck_middle) * narrow.lerp(Vector2.ONE, flare)
		# The head nods about its neck line as one piece, so the face keeps
		# its shape; the neck below the line follows less the deeper it is.
		var nod: Vector2 = Vector2(across.y, point.z - line).rotated(tilt * clampf((point.z - low) / maxf(line - low, 0.0001), 0.0, 1.0))
		var fitted_point: Vector3 = at + Vector3(across.x, nod.x, nod.y) * grow
		# Below the rim nothing may be behind the collar's opening, however
		# the neck was modelled: the back of a thick neck is pulled in, less
		# and less just above the rim. (In front the chin and what hangs
		# from it lie over the collar, so the front is left alone.)
		var off: Vector2 = Vector2(fitted_point.x, fitted_point.y) - collar_middle
		var out: float = (off / (collar_half * NECK_HOLD)).length()
		if out > 1.0 and off.y > 0.0:
			off /= lerpf(out, 1.0, smoothstep(rim, rim + tall * NECK_HOLD_FADE, point.z))
		points[i] = Vector3(collar_middle.x + off.x, collar_middle.y + off.y, fitted_point.z)
	arrays[Mesh.ARRAY_VERTEX] = points
	var fitted: ArrayMesh = ArrayMesh.new()
	fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	fitted.surface_set_material(0, source.surface_get_material(0))
	var top: float = at.z + (high - line) * grow
	# The head itself is what is above the flare of the neck.
	var chin: float = at.z + tall * NECK_FLARE * grow
	return [fitted, top, (chin + top) / 2.0]


func _bake(entry: Dictionary) -> void:
	var root: Node = scene.instantiate()
	var instance: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skeleton: Skeleton3D = instance.get_parent() as Skeleton3D
	var source: ArrayMesh = instance.mesh as ArrayMesh
	var skin: Skin = instance.skin
	var material: BaseMaterial3D = source.surface_get_material(0) as BaseMaterial3D
	if material != null:
		albedo = material.albedo_texture
		normal_map = material.normal_texture
	var worth: Array[Color] = []
	for bind: int in skin.get_bind_count():
		var bone: String = skin.get_bind_name(bind)
		if bone == "" and skeleton != null:
			bone = skeleton.get_bone_name(skin.get_bind_bone(bind))
		worth.append(_bone_worth(bone))
	_measure(skeleton, entry)
	root.free()

	var arrays: Array = source.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count: int = points.size()
	@warning_ignore("integer_division")
	var per: int = bones.size() / count
	_tuck(points, arrays[Mesh.ARRAY_INDEX], bones, weights, per, worth)
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	for point: Vector3 in points:
		collar_top = maxf(collar_top, point.z)
	var rim_low: Vector2 = Vector2.INF
	var rim_high: Vector2 = -Vector2.INF
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(count)
	var custom: PackedFloat32Array = PackedFloat32Array()
	custom.resize(count * 4)
	for i: int in count:
		var share: Color = Color(0.0, 0.0, 0.0, 0.0)
		for k: int in per:
			share += worth[bones[i * per + k]] * weights[i * per + k]
		var point: Vector3 = points[i]
		# A body whose neck bones do not reach all round its collar says how
		# deep the collar is instead.
		if entry.has("collar_depth"):
			var depth: float = entry["collar_depth"]
			share.r = maxf(share.r, smoothstep(depth + 0.008, depth - 0.008, collar_top - point.z))
		colors[i] = share
		custom[i * 4] = point.x
		custom[i * 4 + 1] = point.y
		custom[i * 4 + 2] = point.z
		custom[i * 4 + 3] = normals[i].y
		if point.z > collar_top - COLLAR_RIM:
			rim_low = rim_low.min(Vector2(point.x, point.y))
			rim_high = rim_high.max(Vector2(point.x, point.y))
	collar_middle = (rim_low + rim_high) / 2.0
	collar_half = (rim_high - rim_low) / 2.0
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	mesh = ArrayMesh.new()
	var format: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	format |= source.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)


## The mesh of a whole character with what kit_person.gdshader needs baked in.
## The model stands in the space Godot uses (y up, facing +z); what is baked
## and measured is in the space this class works in (x across, y back, z up).
func _bake_person(entry: Dictionary) -> void:
	var root: Node = scene.instantiate()
	var instance: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skeleton: Skeleton3D = instance.get_parent() as Skeleton3D
	var source: ArrayMesh = instance.mesh as ArrayMesh
	var skin: Skin = instance.skin
	var material: BaseMaterial3D = source.surface_get_material(0) as BaseMaterial3D
	if material != null:
		albedo = material.albedo_texture
		normal_map = material.normal_texture
		roughness_map = material.roughness_texture
	var worth: Array[Color] = []
	for bind: int in skin.get_bind_count():
		var bone: String = skin.get_bind_name(bind)
		if bone == "" and skeleton != null:
			bone = skeleton.get_bone_name(skin.get_bind_bone(bind))
		worth.append(_bone_worth(bone))
	_measure(skeleton, entry)
	_measure_print(skeleton, entry)
	_head_middle = _joint(skeleton, "Head").z
	root.free()

	var arrays: Array = source.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count: int = points.size()
	@warning_ignore("integer_division")
	var per: int = bones.size() / count
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(count)
	var custom: PackedFloat32Array = PackedFloat32Array()
	custom.resize(count * 4)
	for i: int in count:
		var share: Color = Color(0.0, 0.0, 0.0, 0.0)
		for k: int in per:
			share += worth[bones[i * per + k]] * weights[i * per + k]
		colors[i] = share
		var point: Vector3 = _to_kit(points[i])
		custom[i * 4] = point.x
		custom[i * 4 + 1] = point.y
		custom[i * 4 + 2] = point.z
		custom[i * 4 + 3] = -normals[i].z
		_top = maxf(_top, point.z)
	collar_top = _top
	_head_middle = (_head_middle + _top) / 2.0
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	mesh = ArrayMesh.new()
	var format: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	format |= source.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)


## A place in the model of a person (y up, facing +z) in the space of this class.
func _to_kit(point: Vector3) -> Vector3:
	return Vector3(point.x, -point.z, point.y)


## Keeps the jersey in the pants. The two are separate shells, the bottom of
## the jersey inside the waistband, and as modelled the one goes with the
## waist and the other with the pelvis: a player who bends forward pulls his
## jersey out at the back and can be looked into. Here the jersey takes the
## bones of the waistband next to it up to the waistband's top, and goes back
## to its own over TUCK_FADE above that. `worth` is what each bone is (see
## _bone_worth()).
func _tuck(points: PackedVector3Array, index: PackedInt32Array, bones: PackedInt32Array, weights: PackedFloat32Array, per: int, worth: Array[Color]) -> void:
	var count: int = points.size()
	# The shells: vertices in the same place are one, joined by triangles.
	var welded: Dictionary[Vector3i, int] = {}
	var piece: PackedInt32Array = PackedInt32Array()
	piece.resize(count)
	for i: int in count:
		var key: Vector3i = Vector3i((points[i] * 100000.0).round())
		if not welded.has(key):
			welded[key] = i
		piece[i] = welded[key]
	for t: int in range(0, index.size(), 3):
		var a: int = _piece_of(piece, index[t])
		for k: int in [1, 2]:
			var b: int = _piece_of(piece, index[t + k])
			if a != b:
				piece[b] = a
	var size: Dictionary[int, int] = {}
	var low: Dictionary[int, float] = {}
	var high: Dictionary[int, float] = {}
	var top: float = 0.0
	for i: int in count:
		var of: int = _piece_of(piece, i)
		size[of] = size.get(of, 0) + 1
		low[of] = minf(low.get(of, INF), points[i].z)
		high[of] = maxf(high.get(of, -INF), points[i].z)
		top = maxf(top, points[i].z)
	# The pants are the biggest shell round the thighs, the jersey the biggest
	# round the chest.
	var pants: int = _biggest(size, low, high, (hem_z + belt_z) / 2.0)
	var jersey: int = _biggest(size, low, high, (belt_z + top) / 2.0)
	if pants < 0 or jersey < 0 or pants == jersey:
		return
	var band_top: float = high[pants]
	var fade: float = TUCK_FADE * top / HEAD_UNIT
	var band: PackedInt32Array = PackedInt32Array()
	for i: int in count:
		if _piece_of(piece, i) == pants and points[i].z > band_top - fade * 2.0:
			band.append(i)
	for i: int in count:
		if _piece_of(piece, i) != jersey or points[i].z > band_top + fade:
			continue
		var share: float = 1.0 - smoothstep(band_top, band_top + fade, points[i].z)
		var near: int = band[0]
		for other: int in band:
			if points[other].distance_squared_to(points[i]) < points[near].distance_squared_to(points[i]):
				near = other
		# A sleeve that hangs down beside the waistband is not tucked into it.
		var arm: float = 0.0
		for k: int in per:
			arm += (worth[bones[i * per + k]].b + worth[bones[i * per + k]].g) * weights[i * per + k]
		share *= 1.0 - smoothstep(0.0, 0.3, arm)
		share *= 1.0 - smoothstep(fade * 1.5, fade * 2.5, points[near].distance_to(points[i]))
		if share <= 0.0:
			continue
		var mixed: Dictionary[int, float] = {}
		for k: int in per:
			mixed[bones[i * per + k]] = mixed.get(bones[i * per + k], 0.0) + weights[i * per + k] * (1.0 - share)
			mixed[bones[near * per + k]] = mixed.get(bones[near * per + k], 0.0) + weights[near * per + k] * share
		var order: Array[int] = mixed.keys()
		order.sort_custom(func(a: int, b: int) -> bool: return mixed[a] > mixed[b])
		var sum: float = 0.0
		for k: int in mini(per, order.size()):
			sum += mixed[order[k]]
		for k: int in per:
			var kept: bool = k < order.size() and sum > 0.0
			bones[i * per + k] = order[k] if kept else 0
			weights[i * per + k] = mixed[order[k]] / sum if kept else 0.0


func _piece_of(piece: PackedInt32Array, i: int) -> int:
	while piece[i] != i:
		piece[i] = piece[piece[i]]
		i = piece[i]
	return i


## The shell with the most vertices that reaches from below `z` to above it.
func _biggest(size: Dictionary[int, int], low: Dictionary[int, float], high: Dictionary[int, float], z: float) -> int:
	var best: int = -1
	for of: int in size:
		if low[of] < z and high[of] > z and (best < 0 or size[of] > size[best]):
			best = of
	return best


## Where the parts of the kit and its print go, from where the body's joints
## are, unless the body's entry in PlayerParts.BODIES says otherwise.
func _measure(skeleton: Skeleton3D, entry: Dictionary) -> void:
	var hip: float = _joint(skeleton, "Hip").z
	var knee: float = _joint(skeleton, "L_Calf").z
	var ankle: float = _joint(skeleton, "L_Foot").z
	var neck: float = _joint(skeleton, "NeckTwist01").z
	var shoulder: float = absf(_joint(skeleton, "L_Upperarm").x)
	var chest: float = neck - hip
	belt_z = entry.get("belt_z", hip)
	hem_z = entry.get("hem_z", lerpf(ankle, knee, 0.62))
	boot_z = entry.get("boot_z", lerpf(ankle, knee, 0.2))
	front_number = _box(entry, "front_number", Vector3(hip + chest * 0.52, shoulder * 0.56, chest * 0.18))
	back_number = _box(entry, "back_number", Vector3(hip + chest * 0.46, shoulder * 0.65, chest * 0.21))
	back_name = _box(entry, "back_name", Vector3(hip + chest * 0.815, shoulder * 0.89, chest * 0.105))


## Where the print goes on a whole character: big, as on a real jersey. The
## number fills the chest and the back from the belly to the shoulder blades,
## the name runs from shoulder to shoulder above it. Each box has the shape
## of its part of the kit map, so nothing is stretched.
func _measure_print(skeleton: Skeleton3D, entry: Dictionary) -> void:
	var hip: float = _joint(skeleton, "Hip").z
	var chest: float = _joint(skeleton, "NeckTwist01").z - hip
	var shoulder: float = absf(_joint(skeleton, "L_Upperarm").x)
	const NUMBER_SHAPE: float = 512.0 / 384.0
	const NAME_SHAPE: float = 512.0 / 128.0
	var front: float = minf(chest * 0.38, shoulder * 1.1 / NUMBER_SHAPE)
	var back: float = minf(chest * 0.4, shoulder * 1.2 / NUMBER_SHAPE)
	var name_wide: float = shoulder * 1.25
	front_number = _box(entry, "front_number", Vector3(hip + chest * 0.48, front * NUMBER_SHAPE, front))
	back_number = _box(entry, "back_number", Vector3(hip + chest * 0.37, back * NUMBER_SHAPE, back))
	back_name = _box(entry, "back_name", Vector3(hip + chest * 0.37 + back + name_wide / NAME_SHAPE * 0.75, name_wide, name_wide / NAME_SHAPE))


func _joint(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var bone: int = skeleton.find_bone(bone_name)
	if bone < 0:
		push_error("Body %s has no bone %s" % [id, bone_name])
		return Vector3.ZERO
	var at: Vector3 = skeleton.get_bone_global_rest(bone).origin
	return _to_kit(at) if is_person else at


func _box(entry: Dictionary, key: String, usual: Vector3) -> Vector3:
	if not entry.has(key):
		return usual
	var given: Array = entry[key]
	return Vector3(given[0], given[1], given[2])


## What a bone is to the shader: r collar (head and neck), g hand, b arm, a foot.
func _bone_worth(bone: String) -> Color:
	for finger: String in ["Hand", "Pinky", "Ring", "Mid", "Index", "Thumb"]:
		if bone.contains(finger):
			return Color(0.0, 1.0, 0.0, 0.0)
	if bone.contains("Head") or bone.contains("Facial") or bone.contains("Eye") or bone.contains("Neck"):
		return Color(1.0, 0.0, 0.0, 0.0)
	if bone.contains("Upperarm") or bone.contains("Forearm") or bone.contains("Elbow"):
		return Color(0.0, 0.0, 1.0, 0.0)
	if bone.contains("Foot") or bone.contains("Toe"):
		return Color(0.0, 0.0, 0.0, 1.0)
	return Color(0.0, 0.0, 0.0, 0.0)
