class_name LookParts
extends RefCounted
## The parts PlayerModel hangs on a base model's head, made in code: the hair
## (guide strands blended into locks), the nose and the glasses. All in the mesh's own space (see LookBase).

enum Hair { BALD, BUZZ, CROP, FLAT_TOP, MOHAWK, AFRO, MULLET, PIXIE, BOB, PONYTAIL, BUN, LONG, PIGTAILS }

## Per base: what each place of PlayerLook.HAIR_NAMES is.
const HAIR_STYLES: Array[Array] = [
	[Hair.BALD, Hair.BUZZ, Hair.CROP, Hair.FLAT_TOP, Hair.MOHAWK, Hair.AFRO, Hair.MULLET],
	[Hair.BALD, Hair.PIXIE, Hair.BOB, Hair.PONYTAIL, Hair.BUN, Hair.LONG, Hair.PIGTAILS],
]
## Share of the head's height over which hair thins out to the hairline.
const HAIRLINE_FADE: float = 0.07

## Per nose type (see PlayerLook.NOSE_NAMES), in shares of half the head's
## width: height, width at the nostrils and at the bridge, how far it stands
## out at the tip and at the bridge, how far the tip turns up, and the bump on
## its ridge.
const NOSES: Array[Array] = [
	[0.24, 0.21, 0.15, 0.2, 0.1, 0.0, 0.0],
	[0.42, 0.19, 0.1, 0.27, 0.07, 0.0, 0.0],
	[0.36, 0.33, 0.13, 0.25, 0.07, 0.0, 0.0],
	[0.46, 0.2, 0.11, 0.3, 0.1, -0.06, 0.1],
	[0.3, 0.22, 0.09, 0.27, 0.04, 0.09, 0.0],
	[0.4, 0.15, 0.08, 0.4, 0.05, 0.0, 0.0],
]


## Collects triangles and hands out the mesh. Every point carries how far
## inside the hairline it is (see look_hair.gdshader); 1 for anything solid.
class Builder:
	var tool: SurfaceTool = SurfaceTool.new()
	var count: int = 0
	## Set once a point was given its normal: then they are not worked out.
	var own_normals: bool = false
	## For hair (see look_hair.gdshader), set before its points are added:
	## where across its lock a point is (-1 one edge, 1 the other; CAP for the
	## cap), and which way the hair runs there, for the sheen on it.
	var across: float = 0.0
	var grain: Vector3 = Vector3.ZERO

	func _init() -> void:
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	## With a `normal` the point keeps it; then every point has to have one.
	func point(at: Vector3, uv: Vector2 = Vector2.ZERO, cover: float = 1.0, normal: Vector3 = Vector3.ZERO) -> int:
		if normal != Vector3.ZERO:
			own_normals = true
			tool.set_normal(normal)
			if grain != Vector3.ZERO:
				var run: Vector3 = grain - normal * grain.dot(normal)
				tool.set_tangent(Plane(run.normalized() if run.length() > 0.001 else normal.cross(Vector3.RIGHT).normalized(), 1.0))
		tool.set_uv(uv)
		tool.set_uv2(Vector2(cover, across))
		tool.add_vertex(at)
		count += 1
		return count - 1

	func triangle(a: int, b: int, c: int) -> void:
		tool.add_index(a)
		tool.add_index(b)
		tool.add_index(c)

	## A round tube along `path`, `radii[i]` thick at each of its points, its
	## ends closed. `closed` joins the last point to the first instead.
	func tube(path: PackedVector3Array, radii: PackedFloat32Array, closed: bool = false, sides: int = 10) -> void:
		var rings: Array[int] = []
		var side: Vector3 = Vector3.ZERO
		for i: int in path.size():
			var before: Vector3 = path[(i - 1 + path.size()) % path.size()] if closed or i > 0 else path[i]
			var after: Vector3 = path[(i + 1) % path.size()] if closed or i < path.size() - 1 else path[i]
			var along: Vector3 = (after - before).normalized()
			if side == Vector3.ZERO:
				side = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.UP).normalized()
			# Carried from ring to ring so the tube does not twist.
			side = (side - along * side.dot(along)).normalized()
			var up: Vector3 = along.cross(side)
			rings.append(count)
			for k: int in sides:
				var turn: float = TAU * float(k) / float(sides)
				point(path[i] + (side * cos(turn) + up * sin(turn)) * radii[i], Vector2(float(k) / float(sides), float(i)))
		var spans: int = path.size() if closed else path.size() - 1
		for i: int in spans:
			var here: int = rings[i]
			var there: int = rings[(i + 1) % path.size()]
			for k: int in sides:
				var next: int = (k + 1) % sides
				triangle(here + k, there + k, here + next)
				triangle(here + next, there + k, there + next)
		if closed:
			return
		for cap: int in 2:
			var ring: int = rings[0] if cap == 0 else rings[rings.size() - 1]
			var middle: int = point(path[0] if cap == 0 else path[path.size() - 1])
			for k: int in sides:
				triangle(middle, ring + k, ring + (k + 1) % sides)

	## A ball round `center`, `radius` along each axis. `shade` goes into its
	## UV the way a lock's does (see look_hair.gdshader).
	func blob(center: Vector3, radius: Vector3, rings: int = 8, sides: int = 12, shade: float = 0.5) -> void:
		var first: int = count
		for ring: int in rings + 1:
			var tilt: float = PI * float(ring) / float(rings)
			for k: int in sides:
				var turn: float = TAU * float(k) / float(sides)
				var unit: Vector3 = Vector3(sin(tilt) * cos(turn), sin(tilt) * sin(turn), cos(tilt))
				if own_normals:
					point(center + unit * radius, Vector2(shade, 0.6), 1.0, unit)
				else:
					point(center + unit * radius, Vector2(float(k) / float(sides), float(ring)))
		for ring: int in rings:
			for k: int in sides:
				var a: int = first + ring * sides + k
				var b: int = first + ring * sides + (k + 1) % sides
				triangle(a, b, a + sides)
				triangle(b, b + sides, a + sides)

	func mesh() -> ArrayMesh:
		if count == 0:
			return null
		if not own_normals:
			tool.generate_normals()
		return tool.commit()


# --- Hair ----------------------------------------------------------------------------
#
# Hair is a thin cap over the scalp, so no skin shows through, and on it a
# couple of hundred solid locks. A style is a handful of guide strands: where
# on the head each sits and how hair grows there. Every lock takes the blend
# of the guides near its root, then is combed along the head step by step:
# it bends under its own weight and slides over the skull and the shoulders
# instead of going through them.

## Places of a guide strand's numbers. TURN and HEIGHT say where on the head
## it sits (see LookBase.azimuth() and head_height()). SIDE, DOWN and OUT are
## the way the hair sets off there: round the head towards the player's left,
## down the scalp away from the crown, and straight out. LENGTH, WIDTH and
## LIFT (how far it rides above the scalp) are in halves of the head's width.
## DRAPE is the share of the way down to the style's "ends_at" it also grows.
## GRAVITY bends it down, CURL out (or in, below zero) towards its tip.
enum Guide { TURN, HEIGHT, SIDE, DOWN, OUT, LENGTH, DRAPE, GRAVITY, CURL, WIDTH, LIFT }

## Per Hair: "guides" (see Guide; they hold for both halves of the head, the
## hair parting in the middle, unless the style is "lopsided"), "cap" (how thick the cap is, in halves of the head's width),
## and where they apply:
##   "ends_at"  the height on the head (below 0 is under the chin) draped hair hangs to
##   "flat"     how far above the crown the top is cut level
##   "strip"    hair only this far either side of the middle line
##   "ties"     [turn, height] of each point the hair is combed back to
##   "tails"    [how many, length, gravity] of the locks hanging from each tie
##   "bun"      the size of a ball of hair on each tie
##   "frizz"    how much each lock goes its own way
##   "shells"   very short hair: the cap is drawn SHELLS times over, out to
##              this many halves of the head's width from it, each time
##              with more cut away (see look_hair.gdshader)
##   "round"    the cap swells into a ball this many halves of the head's width
##              across, for hair that stands out all round
const STYLES: Dictionary = {
	Hair.BUZZ: {"cap": 0.012, "shells": 0.07, "guides": []},
	Hair.CROP: {"cap": 0.05, "lopsided": true, "guides": [
		[0.0, 0.97, 0.7, 0.6, 0.15, 0.8, 0.0, 0.5, 0.0, 0.17, 0.1],
		[0.0, 0.72, 0.6, 0.15, 0.55, 0.62, 0.0, 0.8, 0.0, 0.17, 0.07],
		[1.0, 0.62, 0.3, 0.9, 0.12, 0.55, 0.0, 0.6, 0.0, 0.12, 0.04],
		[-1.0, 0.62, 0.3, 0.9, 0.12, 0.55, 0.0, 0.6, 0.0, 0.12, 0.04],
		[1.7, 0.5, 0.0, 1.0, 0.08, 0.5, 0.0, 0.6, 0.0, 0.12, 0.035],
		[-1.7, 0.5, 0.0, 1.0, 0.08, 0.5, 0.0, 0.6, 0.0, 0.12, 0.035],
		[PI, 0.5, 0.0, 1.0, 0.08, 0.55, 0.0, 0.6, 0.0, 0.12, 0.04],
		[PI, 0.18, 0.0, 1.0, 0.05, 0.35, 0.0, 0.6, 0.0, 0.11, 0.03],
	]},
	Hair.FLAT_TOP: {"cap": 0.06, "flat": 0.05, "shells": 0.07, "guides": [
		[0.0, 0.9, 0.0, 0.0, 1.0, 0.3, 0.0, 0.0, 0.0, 0.17, 0.04],
		[1.5, 0.5, 0.0, 1.0, 0.08, 0.4, 0.0, 0.4, 0.0, 0.12, 0.03],
		[PI, 0.4, 0.0, 1.0, 0.08, 0.4, 0.0, 0.4, 0.0, 0.12, 0.03],
	]},
	Hair.MOHAWK: {"cap": 0.03, "strip": 0.26, "frizz": 0.1, "guides": [
		[0.0, 0.72, 0.0, 0.1, 1.0, 0.7, 0.0, 0.0, 0.0, 0.16, 0.02],
		[0.0, 1.0, 0.0, 0.0, 1.0, 0.95, 0.0, 0.0, 0.0, 0.16, 0.02],
		[PI, 0.5, 0.0, 0.3, 1.0, 0.8, 0.0, 0.0, 0.0, 0.16, 0.02],
		[PI, 0.2, 0.0, 0.5, 1.0, 0.5, 0.0, 0.0, 0.0, 0.14, 0.02],
	]},
	Hair.AFRO: {"cap": 0.1, "round": 1.42, "shells": 0.2, "frizz": 0.5, "guides": [
		[0.0, 0.9, 0.0, 0.0, 1.0, 0.2, 0.0, 0.0, 0.0, 0.13, 0.0],
	]},
	Hair.MULLET: {"cap": 0.05, "ends_at": -0.8, "frizz": 0.1, "guides": [
		[0.0, 0.72, 0.5, 0.7, 0.4, 0.6, 0.0, 0.8, 0.0, 0.16, 0.07],
		[0.0, 0.98, 0.4, 0.9, 0.3, 0.85, 0.0, 0.6, 0.0, 0.17, 0.1],
		[1.2, 0.6, 0.2, 1.0, 0.12, 0.55, 0.0, 0.7, 0.0, 0.13, 0.05],
		[2.1, 0.5, 0.2, 1.0, 0.12, 0.8, 0.0, 0.9, 0.1, 0.15, 0.05],
		[PI, 0.55, 0.0, 1.0, 0.15, 0.0, 1.0, 1.3, 0.25, 0.19, 0.07],
		[PI, 0.15, 0.0, 1.0, 0.15, 0.0, 1.0, 1.3, 0.25, 0.19, 0.05],
	]},
	Hair.PIXIE: {"cap": 0.05, "lopsided": true, "guides": [
		[0.0, 0.97, -0.8, 0.6, 0.15, 0.85, 0.0, 0.6, 0.0, 0.17, 0.1],
		[0.0, 0.72, -0.9, 0.5, 0.3, 0.7, 0.0, 0.9, 0.0, 0.17, 0.07],
		[1.1, 0.6, 0.2, 1.0, 0.1, 0.55, 0.0, 0.7, 0.0, 0.13, 0.05],
		[-1.1, 0.6, 0.2, 1.0, 0.1, 0.62, 0.0, 0.7, 0.0, 0.13, 0.05],
		[1.8, 0.48, 0.0, 1.0, 0.08, 0.5, 0.0, 0.7, 0.0, 0.12, 0.04],
		[-1.8, 0.48, 0.0, 1.0, 0.08, 0.5, 0.0, 0.7, 0.0, 0.12, 0.04],
		[PI, 0.5, 0.0, 1.0, 0.08, 0.52, 0.0, 0.7, 0.0, 0.12, 0.04],
		[PI, 0.18, 0.0, 1.0, 0.05, 0.32, 0.0, 0.7, 0.0, 0.11, 0.03],
	]},
	Hair.BOB: {"cap": 0.05, "ends_at": 0.04, "guides": [
		[0.5, 0.96, 1.0, 0.4, 0.1, 0.0, 1.0, 1.4, -0.12, 0.22, 0.12],
		[0.0, 0.72, 0.0, 1.0, 0.3, 0.38, 0.0, 1.2, 0.0, 0.18, 0.05],
		[0.85, 0.68, 0.7, 1.0, 0.12, 0.0, 1.0, 1.4, -0.15, 0.22, 0.09],
		[1.6, 0.5, 0.0, 1.0, 0.1, 0.0, 1.0, 1.4, -0.2, 0.22, 0.09],
		[PI, 0.5, 0.0, 1.0, 0.1, 0.0, 1.0, 1.4, -0.2, 0.22, 0.09],
		[PI, 0.15, 0.0, 1.0, 0.08, 0.0, 1.0, 1.4, -0.2, 0.2, 0.05],
	]},
	Hair.LONG: {"cap": 0.05, "ends_at": -0.4, "guides": [
		[0.5, 0.96, 1.0, 0.4, 0.1, 0.0, 1.0, 1.5, 0.0, 0.22, 0.12],
		[0.3, 0.72, 1.0, 0.3, 0.15, 0.0, 1.0, 1.5, 0.0, 0.2, 0.07],
		[1.6, 0.5, 0.0, 1.0, 0.1, 0.0, 1.0, 1.5, 0.0, 0.22, 0.09],
		[PI, 0.5, 0.0, 1.0, 0.1, 0.0, 1.0, 1.5, 0.0, 0.22, 0.09],
		[PI, 0.15, 0.0, 1.0, 0.08, 0.0, 1.0, 1.5, 0.0, 0.2, 0.05],
	]},
	Hair.PONYTAIL: {"cap": 0.05, "ties": [[PI, 0.72]], "tails": [16, 2.2, 1.5], "guides": [
		[0.0, 0.8, 0.0, 1.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.17, 0.05],
	]},
	Hair.BUN: {"cap": 0.05, "ties": [[PI, 0.93]], "bun": 0.5, "guides": [
		[0.0, 0.8, 0.0, 1.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.17, 0.05],
	]},
	Hair.PIGTAILS: {"cap": 0.05, "ties": [[1.75, 0.62], [-1.75, 0.62]], "tails": [11, 1.5, 1.6], "guides": [
		[0.0, 0.8, 0.0, 1.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.17, 0.05],
	]},
}
## About how many locks a head of hair is made of.
const LOCKS: int = 300
## What a guide's WIDTH is multiplied by: finer locks, and more of them.
const LOCK_WIDTH: float = 0.85
## What Builder.across is for the cap, which is not a lock, and for the
## outermost of the shells stacked on it.
const CAP: float = 2.0
const CAP_TOP: float = 3.0
## How many times the cap is drawn for hair that is shells.
const SHELLS: int = 6
## How long one piece of a lock is, in halves of the head's width, and the
## fewest and the most pieces a lock has.
const LOCK_STEP: float = 0.24
const LOCK_STEPS_MIN: int = 3
## How far under the skin a lock is rooted, in halves of the head's width.
const ROOT_DEPTH: float = 0.035
const LOCK_STEPS_MAX: int = 10
## How much more a lock bends under its weight for each half head-width of it.
const LOCK_SAG: float = 1.5


## Combs locks over one head: knows how far the skull reaches every way from
## its middle, and where the shoulders are, and keeps the hair out of both.
class Groom:
	const TURNS: int = 44
	const TILTS: int = 26
	## The face, for hair that is kept off it: up to this height on the head
	## and this far round it from the nose.
	const FACE_TOP: float = 0.6
	const FACE_EDGE: float = 1.0

	var builder: Builder
	var center: Vector3
	var half: float
	## How far the head reaches from `center`, TURNS round by TILTS down.
	var reach: PackedFloat32Array = PackedFloat32Array()
	var chest: Vector3
	var chest_size: Vector3
	var axis_y: float
	var chin_z: float
	var tall: float
	## How high the ridge of a lock stands, as a share of half its width, and
	## whether it comes to a point at its root as well as at its tip (short,
	## fine hair lying flat, like a beard's).
	var ridge: float = 0.5
	var spindle: bool = false
	## Whether the lock being combed grows out of the head (and so starts
	## in its skin) or hangs from a tie.
	var rooted: bool = true
	## For the lock being combed: which side of the face it is kept to (the
	## sign of its side of the parting), or 0 for hair that may hang over it.
	var face_side: float = 0.0

	func _init(into: Builder, info: LookBase, points: PackedVector3Array, middle: Vector3) -> void:
		builder = into
		center = middle
		half = info.half_width
		axis_y = info.axis_y
		chin_z = info.chin_z
		tall = info.top_z - info.chin_z
		chest = Vector3(0.0, info.axis_y + 0.012, info.chin_z - 0.085)
		chest_size = Vector3(0.19, 0.125, 0.085)
		reach.resize(TURNS * TILTS)
		# The surface itself, not the furthest point near it: hair has to lie
		# on the skin, and anything further out would hold it off.
		var found: PackedInt32Array = PackedInt32Array()
		found.resize(TURNS * TILTS)
		for point: Vector3 in points:
			var away: Vector3 = point - center
			var cell: Vector2 = _cell(away.normalized())
			var at: int = (roundi(cell.x) % TURNS) + clampi(roundi(cell.y), 0, TILTS - 1) * TURNS
			reach[at] += away.length()
			found[at] += 1
		for at: int in reach.size():
			if found[at] > 0:
				reach[at] /= float(found[at])
		# Where the head has no points (under the neck), what is around it.
		for sweep: int in 8:
			for at: int in reach.size():
				if reach[at] > 0.0:
					continue
				var sum: float = 0.0
				var count: int = 0
				@warning_ignore("integer_division")
				var tilt: int = at / TURNS
				for near: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var other_tilt: int = tilt + near.y
					if other_tilt < 0 or other_tilt >= TILTS:
						continue
					var other: float = reach[(at % TURNS + near.x + TURNS) % TURNS + other_tilt * TURNS]
					if other > 0.0:
						sum += other
						count += 1
				if count > 0:
					reach[at] = sum / float(count)

	func _cell(way: Vector3) -> Vector2:
		return Vector2((atan2(way.x, -way.y) / TAU + 0.5) * float(TURNS), acos(clampf(way.z, -1.0, 1.0)) / PI * float(TILTS - 1))

	## How far the head reaches from its middle towards `way`.
	func skull(way: Vector3) -> float:
		var cell: Vector2 = _cell(way)
		var turn: int = floori(cell.x)
		var tilt: int = clampi(floori(cell.y), 0, TILTS - 2)
		var across: float = cell.x - float(turn)
		var down: float = clampf(cell.y - float(tilt), 0.0, 1.0)
		var a: int = (turn % TURNS + TURNS) % TURNS
		var b: int = (a + 1) % TURNS
		var upper: float = lerpf(reach[a + tilt * TURNS], reach[b + tilt * TURNS], across)
		var lower: float = lerpf(reach[a + (tilt + 1) * TURNS], reach[b + (tilt + 1) * TURNS], across)
		return lerpf(upper, lower, down)

	## `point`, moved out of the head (by at least `clear`; below 0 the head
	## is not looked at) and the shoulders,
	## and for hair kept off the face, round to the side of it.
	func keep_out(point: Vector3, clear: float) -> Vector3:
		if face_side != 0.0:
			var height: float = (point.z - chin_z) / tall
			var turn: float = atan2(point.x, -(point.y - axis_y))
			if height < FACE_TOP and height > -0.3 and absf(turn) < FACE_EDGE:
				var off: float = Vector2(point.x, point.y - axis_y).length()
				point.x = sin(face_side * FACE_EDGE) * off
				point.y = axis_y - cos(face_side * FACE_EDGE) * off
		var away: Vector3 = point - center
		var far: float = away.length()
		if far > 0.0001 and clear >= 0.0:
			var least: float = skull(away / far) + clear
			if far < least:
				point = center + away / far * least
		var inside: Vector3 = (point - chest) / chest_size
		if inside.length_squared() < 1.0:
			point = chest + inside.normalized() * chest_size
		return point

	## One lock from `start`, setting off towards `heading`, `length` long.
	## With `tied` it is combed over the head to `tie` instead. `shade` (0..1)
	## tells it apart from its neighbours in colour.
	func lock(start: Vector3, heading: Vector3, length: float, gravity: float, curl: float,
			width: float, clear: float, shade: float, tied: bool = false, tie: Vector3 = Vector3.ZERO,
			blunt: bool = false) -> void:
		var steps: int = clampi(ceili(length / (half * LOCK_STEP)), LOCK_STEPS_MIN, LOCK_STEPS_MAX)
		var step: float = length / float(steps)
		# Rooted just under the skin, so nothing shows between it and the lock.
		var at: Vector3 = start - (start - center).normalized() * half * ROOT_DEPTH if rooted else keep_out(start, clear)
		var way: Vector3 = heading.normalized()
		var path: PackedVector3Array = PackedVector3Array([at])
		for i: int in steps:
			var outward: Vector3 = (at - center).normalized()
			if tied:
				var to: Vector3 = tie - at
				if to.length() <= step:
					path.append(tie)
					break
				# Round the head, not through it.
				var along_head: Vector3 = to - outward * to.dot(outward)
				way = along_head.normalized() if along_head.length() > 0.0001 else way
			else:
				var done: float = float(i + 1) / float(steps)
				var sag: float = gravity * LOCK_SAG * step / half
				way = (way + Vector3(0.0, 0.0, -sag) + outward * curl * 0.5 * done).normalized()
			# It rises off the skin over its first pieces.
			var risen: float = clear * minf(float(i + 1) / 2.0, 1.0) if rooted else clear
			var next: Vector3 = keep_out(at + way * step, risen)
			if next.distance_to(at) > 0.00001:
				way = (next - at).normalized()
			at = next
			path.append(at)
		_ribbon(path, width, shade, blunt)

	## The lock itself: a ridge along `path`, widest near the root and coming
	## to a point (or, `blunt`, cut off square). Its underside, against the
	## head, is left open. Its normals lean only a little off the head's, so a
	## head of hair is lit as one shape with the locks as detail on it.
	func _ribbon(path: PackedVector3Array, width: float, shade: float, blunt: bool) -> void:
		var first: int = builder.count
		var last: int = path.size() - 1
		var outward: Vector3 = Vector3.UP
		for i: int in path.size():
			var done: float = float(i) / float(last)
			var along: Vector3 = (path[mini(i + 1, last)] - path[maxi(i - 1, 0)]).normalized()
			var away: Vector3 = (path[i] - center).normalized()
			away -= along * away.dot(along)
			if away.length() > 0.01:
				outward = away.normalized()
			var across: Vector3 = along.cross(outward)
			var taper: float = 0.85 if blunt else 1.0 - pow(done, 2.5)
			var swell: float = sin(PI * minf(done * 1.6, 0.5)) if spindle else 0.65 + 0.35 * smoothstep(0.0, 0.25, done)
			var wide: float = width * swell * taper
			builder.grain = along
			builder.across = -1.0
			builder.point(path[i] - across * wide, Vector2(shade, done), 1.0, (outward - across * 0.55).normalized())
			builder.across = 0.0
			builder.point(path[i] + outward * wide * ridge, Vector2(shade, done), 1.0, outward)
			builder.across = 1.0
			builder.point(path[i] + across * wide, Vector2(shade, done), 1.0, (outward + across * 0.55).normalized())
		for i: int in last:
			var here: int = first + i * 3
			var there: int = here + 3
			builder.triangle(here, there, here + 1)
			builder.triangle(here + 1, there, there + 1)
			builder.triangle(here + 1, there + 1, here + 2)
			builder.triangle(here + 2, there + 1, there + 2)


## How far out the shells of `style` reach, in the mesh's own units: what
## look_hair.gdshader's shell_depth is to be for its hair. 0 without shells.
static func shell_depth(info: LookBase, style: int) -> float:
	var spec: Dictionary = STYLES.get(style, {})
	var depth: float = spec.get("shells", 0.0)
	return depth * info.half_width


## The hair of `style` (a Hair) for the base `info`, grown from its head with
## the forehead and chin sliders at `forehead` and `chin` (blend weights).
## Null for a bald head.
static func hair_mesh(info: LookBase, style: int, forehead: float, chin: float) -> ArrayMesh:
	if style == Hair.BALD or not STYLES.has(style):
		return null
	var spec: Dictionary = STYLES[style]
	var builder: Builder = Builder.new()
	var half: float = info.half_width
	var tall: float = info.top_z - info.chin_z
	var crown_z: float = info.top_z + tall * LookBase.FOREHEAD_RISE * maxf(forehead, 0.0)
	var center: Vector3 = Vector3(0.0, info.axis_y, info.chin_z + 0.55 * tall)
	var crown: Vector3 = Vector3(0.0, info.axis_y + 0.25 * half, crown_z)
	var cap: float = spec.get("cap", 0.05)
	var strip: float = spec.get("strip", 0.0)
	var flat: float = spec.get("flat", 0.0)
	var ball: float = spec.get("round", 0.0)
	var count: int = info.scalp_points.size()

	# The cap: the scalp itself, a little out, cut off at the hairline.
	var points: PackedVector3Array = PackedVector3Array()
	points.resize(count)
	var covers: PackedFloat32Array = PackedFloat32Array()
	covers.resize(count)
	## Where the cap is over each point of the scalp.
	var caps: PackedVector3Array = PackedVector3Array()
	caps.resize(count)
	var cap_normals: PackedVector3Array = PackedVector3Array()
	cap_normals.resize(count)
	for i: int in count:
		var rest: Vector3 = info.scalp_points[i]
		var at: Vector3 = rest + info.scalp_forehead[i] * forehead + info.scalp_chin[i] * chin
		points[i] = at
		var turn: float = info.azimuth(rest)
		var height: float = info.head_height(rest.z)
		var cover: float = (height - _hairline(absf(turn))) / HAIRLINE_FADE
		if strip > 0.0:
			# Shaved at the sides.
			cover = minf(cover, (1.0 - absf(rest.x) / (strip * half)) * 3.0)
		covers[i] = cover
		var out: Vector3 = (info.scalp_normals[i] + (at - center).normalized()).normalized()
		var fade: float = smoothstep(0.0, 1.0, cover)
		var cap_at: Vector3 = at + out * half * cap * fade
		var cap_normal: Vector3 = info.scalp_normals[i]
		if flat > 0.0:
			# Standing up all over the top, and cut level above the crown.
			var standing: float = smoothstep(0.6, 0.78, height) * fade
			cap_at += Vector3(out.x * 0.12, out.y * 0.12, 0.42) * half * standing
			var level: float = crown_z + flat * half
			if cap_at.z > level:
				cap_at.z = level
				cap_normal = Vector3(0.0, 0.0, 1.0)
		# As dark as the roots of the locks, so a parting reads as depth.
		if ball > 0.0:
			# Out to a ball round the top of the head, lumpy like curls are.
			var middle: Vector3 = center + Vector3(0.0, 0.0, 0.08 * tall)
			var from_middle: Vector3 = cap_at - middle
			var lumps: float = 1.0 + 0.06 * sin(turn * 7.0 + height * 9.0) * sin(height * 13.0 + turn * 3.0) + 0.03 * sin(turn * 17.0) * sin(height * 31.0)
			var far: float = lerpf(from_middle.length(), maxf(from_middle.length(), ball * half * lumps), fade)
			cap_at = middle + from_middle.normalized() * far
			cap_normal = cap_normal.lerp(from_middle.normalized(), fade).normalized()
		caps[i] = cap_at
		cap_normals[i] = cap_normal
		builder.across = CAP
		builder.grain = Vector3(0.0, 0.0, -1.0)
		builder.point(cap_at, Vector2(0.2, 0.15), cover, cap_normal)
	# For shells, the same cap again and again: the shader moves each out.
	var layers: int = SHELLS if spec.has("shells") else 1
	for layer: int in range(1, layers):
		builder.across = lerpf(CAP, CAP_TOP, float(layer) / float(layers - 1))
		for i: int in count:
			builder.point(caps[i], Vector2(0.2, 0.15), covers[i], cap_normals[i])
	@warning_ignore("integer_division")
	for triangle: int in info.scalp_indices.size() / 3:
		var a: int = info.scalp_indices[triangle * 3]
		var b: int = info.scalp_indices[triangle * 3 + 1]
		var c: int = info.scalp_indices[triangle * 3 + 2]
		if covers[a] > 0.0 or covers[b] > 0.0 or covers[c] > 0.0:
			for layer: int in layers:
				builder.triangle(a + layer * count, b + layer * count, c + layer * count)

	var guides: Array = spec["guides"]
	if guides.is_empty():
		return builder.mesh()
	# One half of the head is the other in a mirror, the hair parting between.
	var parted: bool = not spec.get("lopsided", false)

	var groom: Groom = Groom.new(builder, info, points, center)
	var ties: PackedVector3Array = PackedVector3Array()
	for tie: Array in spec.get("ties", []):
		var on_scalp: Vector3 = info.scalp_point(tie[0], tie[1], forehead, chin)
		ties.append(on_scalp + (on_scalp - center).normalized() * half * 0.14)
	var ends_z: float = info.head_z(spec.get("ends_at", 0.0))
	var off_face: bool = spec.has("ends_at")
	var frizz: float = spec.get("frizz", 0.06)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261113 + style

	var roots: PackedInt32Array = PackedInt32Array()
	for i: int in count:
		if covers[i] > 0.25:
			roots.append(i)
	var keep: float = minf(float(LOCKS) / maxf(float(roots.size()), 1.0), 1.0)
	var blend: PackedFloat32Array = PackedFloat32Array()
	blend.resize(Guide.size())
	for i: int in roots:
		# Drawn for every root, kept or not, so the same roots are kept
		# whatever the sliders say.
		var chance: float = rng.randf()
		var own: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var shade: float = rng.randf()
		if chance > keep:
			continue
		var rest: Vector3 = info.scalp_points[i]
		var at: Vector3 = points[i]
		var normal: Vector3 = info.scalp_normals[i]
		var turn: float = info.azimuth(rest)
		var height: float = info.head_height(rest.z)

		# The guides near this root, the nearest counting most. Near the crown
		# which way round the head a point is means little.
		blend.fill(0.0)
		var total: float = 0.0
		for guide: Array in guides:
			var guide_height: float = guide[Guide.HEIGHT]
			var round: float = pow(clampf((1.0 - minf(height, guide_height)) * 2.5, 0.05, 1.0), 2.0)
			var guide_turn: float = guide[Guide.TURN]
			var apart: float = absf(turn) - absf(guide_turn) if parted else angle_difference(turn, guide_turn)
			var gap: float = pow(apart, 2.0) * round + pow((height - guide_height) * 2.5, 2.0)
			var weight: float = 1.0 / (pow(gap, 1.5) + 0.0005)
			total += weight
			for k: int in Guide.size():
				blend[k] += weight * float(guide[k])
		for k: int in Guide.size():
			blend[k] /= total
		if parted:
			# Away from the parting on both sides.
			blend[Guide.SIDE] *= 1.0 if turn >= 0.0 else -1.0

		var down: Vector3 = at - crown
		down -= normal * down.dot(normal)
		down = down.normalized() if down.length() > 0.0001 else Vector3(0.0, -1.0, 0.0)
		var side: Vector3 = normal.cross(down)
		var heading: Vector3 = side * blend[Guide.SIDE] + down * blend[Guide.DOWN] + normal * blend[Guide.OUT] + own * frizz
		var off_axis: float = Vector2(at.x, at.y - info.axis_y).length()
		var hang: float = maxf(at.z - ends_z, 0.0) + maxf(half - off_axis, 0.0) * 0.8
		var length: float = (blend[Guide.LENGTH] * half + blend[Guide.DRAPE] * hang) * (1.0 + own.x * 0.14)
		var gravity: float = blend[Guide.GRAVITY]
		var width: float = blend[Guide.WIDTH] * LOCK_WIDTH * half * (1.0 + own.y * 0.15)
		# On the cap, and hair rooted higher over what is rooted below it.
		var clear: float = half * (cap + 0.006 + blend[Guide.LIFT] * 0.45 * (0.6 + 0.8 * height) + shade * 0.012)
		groom.face_side = (1.0 if turn >= 0.0 else -1.0) if off_face else 0.0
		if flat > 0.0 and height > 0.7:
			# The cap is the top of a flat top.
			continue
		if ball > 0.0:
			# The ball is all there is to it.
			continue
		if ties.is_empty():
			groom.lock(at, heading, maxf(length, half * 0.1), gravity, blend[Guide.CURL], width, clear, shade)
		else:
			var tie: Vector3 = ties[0]
			for other: Vector3 in ties:
				if other.distance_to(at) < tie.distance_to(at):
					tie = other
			var arc: float = (at - center).angle_to(tie - center) * half * 1.15 + half * 0.2
			groom.lock(at, down, arc, 0.0, 0.0, width, clear, shade, true, tie)

	# What hangs from, or sits on, each tie.
	var tails: Array = spec.get("tails", [])
	var bun: float = spec.get("bun", 0.0)
	groom.face_side = 0.0
	groom.rooted = false
	builder.across = 0.0
	builder.grain = Vector3(1.0, 0.0, 0.0)
	for tie: Vector3 in ties:
		var out: Vector3 = (tie - center).normalized()
		if bun > 0.0:
			builder.blob(tie + out * half * bun * 0.55, Vector3.ONE * half * bun)
			continue
		builder.blob(tie, Vector3.ONE * half * 0.2, 5, 8)
		for k: int in int(tails[0]):
			var spread: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0))
			var tail_length: float = float(tails[1]) * half * rng.randf_range(0.8, 1.1)
			groom.lock(tie, out + spread * 0.4, tail_length, tails[2], 0.0, half * 0.3, half * (0.05 + 0.012 * float(k)), rng.randf())
	return builder.mesh()


## How high up the head hair starts at `side` round it from the front (0..PI),
## as a share of chin to crown: across the forehead, down past the temple to
## in front of the ear, and round to the nape.
static func _hairline(side: float) -> float:
	if side < 0.7:
		return 0.7 - 0.03 * pow(side / 0.7, 2.0)
	if side < 1.4:
		return lerpf(0.67, 0.46, smoothstep(0.7, 1.4, side))
	return lerpf(0.46, 0.12, smoothstep(1.4, PI, side))


# --- Facial hair ---------------------------------------------------------------------

## About how many locks a full beard is made of.
const BEARD_LOCKS: int = 520

## The facial hair of `type` (a place in PlayerLook.FACIAL_HAIR_NAMES) as short
## locks grown from the face, over what FacePainter paints there. Null for a
## clean shave and for stubble, which is paint alone.
static func facial_hair_mesh(info: LookBase, type: int, forehead: float, chin: float) -> ArrayMesh:
	if type < 1:
		return null
	if type == 1:
		return _stubble_mesh(info, forehead, chin)
	var builder: Builder = Builder.new()
	var half: float = info.half_width
	var tall: float = info.top_z - info.chin_z
	var center: Vector3 = Vector3(0.0, info.axis_y, info.chin_z + 0.55 * tall)
	var count: int = info.scalp_points.size()
	var points: PackedVector3Array = PackedVector3Array()
	points.resize(count)
	for i: int in count:
		points[i] = info.scalp_points[i] + info.scalp_forehead[i] * forehead + info.scalp_chin[i] * chin
	var groom: Groom = Groom.new(builder, info, points, center)
	groom.ridge = 0.28
	groom.spindle = true
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7411 + type

	# Where each point of the face is, the way FacePainter measures it: face
	# units round from the nose, and the height on the head.
	var roots: PackedInt32Array = PackedInt32Array()
	var kinds: PackedInt32Array = PackedInt32Array()
	for i: int in count:
		var rest: Vector3 = info.scalp_points[i]
		var x: float = info.azimuth(rest) * info.face_radius / half
		var kind: int = _whiskers(type, x, info.head_height(rest.z))
		if kind != Whiskers.NONE:
			roots.append(i)
			kinds.append(kind)
	var keep: float = minf(float(BEARD_LOCKS) / maxf(float(roots.size()), 1.0), 1.0)
	for at_root: int in roots.size():
		var chance: float = rng.randf()
		var own: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var shade: float = rng.randf()
		if chance > keep:
			continue
		var i: int = roots[at_root]
		var at: Vector3 = points[i]
		var normal: Vector3 = info.scalp_normals[i]
		var x: float = info.azimuth(info.scalp_points[i]) * info.face_radius / half
		var away: float = 1.0 if x >= 0.0 else -1.0
		var down: Vector3 = Vector3(0.0, 0.0, -1.0) - normal * -normal.z
		down = down.normalized() if down.length() > 0.001 else Vector3(0.0, -1.0, 0.0)
		var sideways: Vector3 = normal.cross(down) * away
		var clear: float = half * (0.006 + 0.014 * shade)
		if kinds[at_root] == Whiskers.MOUSTACHE:
			# Combed out from under the nose; a handlebar's ends are longer
			# and turn up.
			var out_there: float = clampf(absf(x) / 0.6, 0.0, 1.0)
			var handlebar: float = out_there if type == 5 else 0.0
			var heading: Vector3 = sideways * (0.9 + 0.3 * out_there) + down * (0.3 - 0.25 * handlebar) + normal * 0.06 + own * 0.05
			var length: float = half * (0.17 + 0.05 * out_there + 0.3 * handlebar) * (1.0 + own.x * 0.12)
			groom.lock(at, heading, length, 0.15 - 1.2 * handlebar, 0.4 * handlebar, half * 0.04, clear, shade)
		else:
			var heading: Vector3 = down + normal * 0.12 + sideways * 0.1 + own * 0.07
			var length: float = half * (0.26 if type != 4 else 0.32) * (1.0 + own.x * 0.2)
			groom.lock(at, heading, length, 0.3, 0.0, half * 0.048, clear, shade)
	return builder.mesh()


## How far out the shells of stubble reach, in halves of the head's width.
const STUBBLE_DEPTH: float = 0.035
const STUBBLE_SHELLS: int = 4

## Stubble: where a full beard would grow, the skin of the face again as
## shells (see look_hair.gdshader), thinning out at its edge.
static func _stubble_mesh(info: LookBase, forehead: float, chin: float) -> ArrayMesh:
	var builder: Builder = Builder.new()
	var half: float = info.half_width
	var count: int = info.scalp_points.size()
	var covers: PackedFloat32Array = PackedFloat32Array()
	covers.resize(count)
	builder.grain = Vector3(0.0, 0.0, -1.0)
	for layer: int in STUBBLE_SHELLS:
		builder.across = lerpf(CAP, CAP_TOP, float(layer) / float(STUBBLE_SHELLS - 1))
		for i: int in count:
			var rest: Vector3 = info.scalp_points[i]
			var x: float = info.azimuth(rest) * info.face_radius / half
			# Inside or out; across a triangle of the edge that is a fade.
			covers[i] = 1.2 if _whiskers(4, x, info.head_height(rest.z)) != Whiskers.NONE else -0.6
			var at: Vector3 = rest + info.scalp_forehead[i] * forehead + info.scalp_chin[i] * chin
			builder.point(at + info.scalp_normals[i] * half * 0.004, Vector2(0.5, 0.15), covers[i], info.scalp_normals[i])
	@warning_ignore("integer_division")
	for triangle: int in info.scalp_indices.size() / 3:
		var a: int = info.scalp_indices[triangle * 3]
		var b: int = info.scalp_indices[triangle * 3 + 1]
		var c: int = info.scalp_indices[triangle * 3 + 2]
		if covers[a] > 0.0 or covers[b] > 0.0 or covers[c] > 0.0:
			for layer: int in STUBBLE_SHELLS:
				builder.triangle(a + layer * count, b + layer * count, c + layer * count)
	return builder.mesh()


# --- Eyebrows ------------------------------------------------------------------------

## Per eye type (see PlayerLook.EYE_NAMES) the brow over it: where it starts
## by the nose, the point it bends towards and where it ends, each x then y,
## and how thick it is. In halves of the eye's width from the middle of the
## eye, x away from the nose and y down, as FacePainter draws an eye.
const BROWS: Array[Array] = [
	[-1.1, -1.45, 0.0, -1.9, 1.25, -1.4, 0.28],
	[-1.1, -1.15, 0.1, -1.75, 1.35, -1.2, 0.22],
	[-1.1, -1.3, 0.1, -1.4, 1.25, -1.2, 0.26],
	[-1.25, -0.45, 0.02, -0.85, 1.3, -1.25, 0.36],
	[-0.8, -1.3, 0.0, -1.6, 0.9, -1.3, 0.18],
	[-1.0, -1.95, 0.1, -2.5, 1.3, -1.85, 0.18],
]
## Half the width of an eye, in halves of the head's width.
const EYE_HALF: float = 0.2
const BROW_ROWS: int = 4
const BROW_HAIRS: int = 22

## The point of the brow of `type` a share `along` of the way from the nose
## end to the far end, `across` of its thickness above (below 0) or below its
## middle line, in the terms of BROWS.
static func brow_point(type: int, along: float, across: float = 0.0) -> Vector2:
	var brow: Array = BROWS[clampi(type, 0, BROWS.size() - 1)]
	var from: Vector2 = Vector2(brow[0], brow[1])
	var pull: Vector2 = Vector2(brow[2], brow[3])
	var to: Vector2 = Vector2(brow[4], brow[5])
	var thick: float = brow[6]
	return from.lerp(pull, along).lerp(pull.lerp(to, along), along) + Vector2(0.0, across * thick)


## Both eyebrows for eyes of `type`, as fine hairs lying along the brow over
## what FacePainter paints there.
static func brow_mesh(info: LookBase, type: int, forehead: float, chin: float) -> ArrayMesh:
	var builder: Builder = Builder.new()
	var half: float = info.half_width
	var tall: float = info.top_z - info.chin_z
	var center: Vector3 = Vector3(0.0, info.axis_y, info.chin_z + 0.55 * tall)
	var points: PackedVector3Array = PackedVector3Array()
	points.resize(info.scalp_points.size())
	for i: int in points.size():
		points[i] = info.scalp_points[i] + info.scalp_forehead[i] * forehead + info.scalp_chin[i] * chin
	var groom: Groom = Groom.new(builder, info, points, center)
	groom.ridge = 0.3
	groom.spindle = true
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5150 + type
	for sign_x: float in [-1.0, 1.0]:
		for row: int in BROW_ROWS:
			var across: float = (float(row) / float(BROW_ROWS - 1) - 0.5) * 0.7
			for hair: int in BROW_HAIRS:
				var along: float = (float(hair) + rng.randf()) / float(BROW_HAIRS)
				var at: Vector3 = _on_face(groom, info, type, sign_x, along, across, forehead)
				var ahead: Vector3 = _on_face(groom, info, type, sign_x, minf(along + 0.12, 1.1), across, forehead)
				# Up by the nose, then lying over along the brow.
				var heading: Vector3 = (ahead - at).normalized() + Vector3(0.0, 0.0, lerpf(0.55, 0.06, smoothstep(0.0, 0.3, along)))
				var length: float = EYE_HALF * half * rng.randf_range(0.6, 0.85) * lerpf(0.7, 1.0, 1.0 - absf(along - 0.45))
				groom.lock(at, heading, length, 0.0, 0.0, half * 0.026, half * (0.003 + 0.007 * rng.randf()), rng.randf())
	return builder.mesh()


## Where on the face the brow_point() of the brow on the `sign_x` side is.
static func _on_face(groom: Groom, info: LookBase, type: int, sign_x: float, along: float, across: float, forehead: float) -> Vector3:
	var half: float = info.half_width
	var brow: Vector2 = brow_point(type, along, across)
	var turn: float = sign_x * (LookBase.EYE_APART + brow.x * EYE_HALF) * half / info.face_radius
	var z: float = info.head_z(LookBase.EYE_HEIGHT) - brow.y * EYE_HALF * half
	# What the forehead slider does to the face it is painted on.
	z += info._forehead_move(Vector3(0.0, info.axis_y - info.face_radius, z)).z * forehead
	var level: Vector3 = Vector3(sin(turn), -cos(turn), 0.0)
	var rise: float = z - groom.center.z
	var off: float = info.face_radius
	var at: Vector3 = groom.center
	for step: int in 5:
		var way: Vector3 = (level * off + Vector3(0.0, 0.0, rise)).normalized()
		var far: float = groom.skull(way)
		at = groom.center + way * far
		off = sqrt(maxf(far * far - rise * rise, 0.000001))
	return at


enum Whiskers { NONE, MOUSTACHE, BEARD }

## Which kind of whisker, if any, grows `x` face units round from the nose and
## `height` up the head, for the facial hair of `type`. The same shapes
## FacePainter paints.
static func _whiskers(type: int, x: float, height: float) -> int:
	var mouth: float = LookBase.MOUTH_HEIGHT
	var side: float = absf(x)
	var lip: float = mouth + 0.035
	var moustache_half: float = 0.56
	# The strip between the lip and the nose, deepest under the nose.
	var under_nose: float = minf(lip + 0.02 + 0.075 * (1.0 - pow(side / moustache_half, 2.0)), LookBase.NOSE_HEIGHT - 0.035)
	if side < moustache_half and height > lip and height < under_nose:
		return Whiskers.MOUSTACHE
	if side < 0.36 and absf(height - mouth) < 0.04:
		return Whiskers.NONE
	match type:
		3: # Goatee
			if side < 0.42 and height < mouth - 0.06 and height > -0.07:
				return Whiskers.BEARD
			if side > 0.34 and side < 0.56 and height > mouth - 0.15 and height < lip:
				return Whiskers.BEARD
		4: # Full beard
			var top: float = mouth + 0.06
			if side > 0.72:
				top = lerpf(mouth + 0.06, 0.34, smoothstep(0.72, 1.15, side))
			if side > 1.15:
				top = lerpf(0.34, 0.55, smoothstep(1.15, 1.32, side))
			if side < 1.58 and height < top and height > -0.14:
				return Whiskers.BEARD
		6: # Mutton chops
			if side > 0.6 and side < 1.58:
				var top: float = lerpf(mouth + 0.02, 0.32, smoothstep(0.62, 1.1, side))
				if side > 1.1:
					top = lerpf(0.32, 0.55, smoothstep(1.1, 1.28, side))
				var low: float = lerpf(mouth - 0.08, 0.0, smoothstep(0.6, 1.05, side))
				if side > 1.05:
					low = lerpf(0.0, 0.17, smoothstep(1.05, 1.6, side))
				if height < top and height > low:
					return Whiskers.BEARD
	return Whiskers.NONE


# --- Nose ----------------------------------------------------------------------------

## The nose of `type` (a place in NOSES) at `scale` times its size.
static func nose_mesh(info: LookBase, type: int, scale: float) -> ArrayMesh:
	var shape: PackedFloat32Array = PackedFloat32Array(NOSES[clampi(type, 0, NOSES.size() - 1)])
	var half: float = info.half_width * scale
	var tall: float = shape[0] * half
	var middle_z: float = info.head_z(LookBase.NOSE_HEIGHT) + tall * 0.75
	var builder: Builder = Builder.new()
	const RINGS: int = 10
	const SIDES: int = 14
	for ring: int in RINGS + 1:
		var tilt: float = PI * float(ring) / float(RINGS)
		# 0 under the nostrils, 1 at the bridge between the eyes.
		var up: float = (1.0 - cos(tilt)) / 2.0
		var wide: float = lerpf(shape[1], shape[2], smoothstep(0.1, 0.75, up)) * half
		var deep: float = lerpf(shape[3], shape[4], pow(up, 0.75)) * half + shape[6] * half * sin(PI * up)
		var z: float = middle_z + (up - 0.5) * 2.0 * tall + shape[5] * half * (1.0 - up)
		# The face it grows out of, a little inside it.
		var face_y: float = info.front_y(0.0, z) + 0.006
		for k: int in SIDES:
			var turn: float = TAU * float(k) / float(SIDES)
			var round: float = sin(tilt)
			var x: float = cos(turn) * round * wide
			var y: float = face_y - maxf(sin(turn), -0.35) * round * deep
			# The tip hangs a little lower than where it joins the face.
			var droop: float = maxf(sin(turn), 0.0) * round * (1.0 - up) * (shape[5] - 0.03) * half
			builder.point(Vector3(x, y, z + droop), Vector2(float(k) / float(SIDES), up))
	for ring: int in RINGS:
		for k: int in SIDES:
			var a: int = ring * SIDES + k
			var b: int = ring * SIDES + (k + 1) % SIDES
			builder.triangle(a, a + SIDES, b)
			builder.triangle(b, a + SIDES, b + SIDES)
	return builder.mesh()


# --- Glasses -------------------------------------------------------------------------

## Glasses for the base `info`: the frame and the two lenses, each with its
## own material. `dark` makes them sunglasses.
static func glasses(info: LookBase, dark: bool) -> Node3D:
	var half: float = info.half_width
	var eye_x: float = LookBase.EYE_APART * half
	var eye_z: float = info.head_z(LookBase.EYE_HEIGHT)
	var lens: Vector2 = Vector2(0.37, 0.3) * half if dark else Vector2(0.33, 0.31) * half
	var rim: float = half * (0.03 if dark else 0.055)
	# Squarer for the nerdy pair, a teardrop for the sunglasses.
	var corner: float = 0.8 if dark else 0.55
	var plane_y: float = minf(info.front_y(eye_x - lens.x * 0.9, eye_z), info.front_y(eye_x, eye_z)) - half * 0.1

	var frame: Builder = Builder.new()
	var glass: Builder = Builder.new()
	const STEPS: int = 28
	for sign_x: float in [-1.0, 1.0]:
		var middle: Vector3 = Vector3(sign_x * eye_x, plane_y, eye_z)
		var outline: PackedVector3Array = PackedVector3Array()
		var radii: PackedFloat32Array = PackedFloat32Array()
		for step: int in STEPS:
			var turn: float = TAU * float(step) / float(STEPS)
			var across: float = signf(cos(turn)) * pow(absf(cos(turn)), corner)
			var up: float = signf(sin(turn)) * pow(absf(sin(turn)), corner)
			if dark and up < 0.0:
				# Deeper towards the cheek on the outside.
				up *= 1.0 + 0.25 * maxf(across, 0.0)
			# The lens wraps round the face a little.
			var wrap: float = half * 0.35 * pow(maxf(across, 0.0), 2.0)
			outline.append(middle + Vector3(sign_x * across * lens.x, wrap, up * lens.y))
			radii.append(rim)
		frame.tube(outline, radii, true, 8)
		var hub: int = glass.point(middle)
		var first: int = glass.count
		for at: Vector3 in outline:
			glass.point(at)
		for step: int in STEPS:
			glass.triangle(hub, first + step, first + (step + 1) % STEPS)
		# The arm, back over the ear.
		var hinge: Vector3 = middle + Vector3(sign_x * lens.x, half * 0.35, lens.y * 0.35)
		frame.tube(PackedVector3Array([
			hinge,
			Vector3(sign_x * half * 1.04, lerpf(hinge.y, info.axis_y, 0.55), hinge.z),
			Vector3(sign_x * half * 1.03, info.axis_y + half * 0.15, hinge.z - half * 0.04),
		]), PackedFloat32Array([rim * 0.8, rim * 0.7, rim * 0.6]), false, 6)
	var bridge_z: float = eye_z + lens.y * 0.3
	frame.tube(PackedVector3Array([
		Vector3(-(eye_x - lens.x), plane_y, bridge_z),
		Vector3(0.0, plane_y - half * 0.04, bridge_z + half * 0.03),
		Vector3(eye_x - lens.x, plane_y, bridge_z),
	]), PackedFloat32Array([rim, rim, rim]), false, 8)

	var frame_material: StandardMaterial3D = StandardMaterial3D.new()
	frame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	frame_material.albedo_color = Color(0.75, 0.65, 0.3) if dark else Color(0.04, 0.04, 0.05)
	frame_material.metallic = 0.8 if dark else 0.0
	frame_material.roughness = 0.3
	var glass_material: StandardMaterial3D = StandardMaterial3D.new()
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass_material.roughness = 0.08
	if dark:
		glass_material.albedo_color = Color(0.03, 0.035, 0.05)
		glass_material.metallic = 0.5
	else:
		glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass_material.albedo_color = Color(0.8, 0.92, 1.0, 0.22)

	var node: Node3D = Node3D.new()
	node.name = "Glasses"
	for part: Array in [[frame, frame_material, "Frame"], [glass, glass_material, "Lenses"]]:
		var builder: Builder = part[0]
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = part[2]
		instance.mesh = builder.mesh()
		instance.material_override = part[1]
		node.add_child(instance)
	return node
