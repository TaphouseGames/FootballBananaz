class_name FacePainter
extends Control
## Paints a player's face for PlayerModel: the map look_body.gdshader wraps
## round the head, the front of the face in the middle of it, the crown at the
## top edge. Eyes and brows, mouth, facial hair and the eyepatch; the nose and
## the glasses are meshes (see LookParts).
##
## Features are drawn in "face units": 1 is half the width of the head.

const IRIS: Color = Color(0.3, 0.19, 0.1)
const INK: Color = Color(0.07, 0.05, 0.05)
const EYE_WHITE: Color = Color(0.97, 0.96, 0.94)
const PATCH: Color = Color(0.05, 0.05, 0.06)
## Half the width of an eye and of a mouth of size 0.5, in face units.
const EYE_HALF: float = LookParts.EYE_HALF
## How much of the brow is paint: the rest is the hairs LookParts lays on it.
const BROW_PAINT: float = 0.5
const MOUTH_HALF: float = 0.3
## Where the beard's edge meets the sideburn, round the face from its middle.
const BURN_X: float = 1.55

var look: PlayerLook
var info: LookBase

## Where the feature being drawn is, and how many pixels one of its units is
## across and down. A negative x mirrors it.
var _origin: Vector2 = Vector2.ZERO
var _unit: Vector2 = Vector2.ONE


func show_look(new_look: PlayerLook, new_info: LookBase) -> void:
	look = new_look
	info = new_info
	queue_redraw()


func _draw() -> void:
	if look == null or info == null:
		return
	var hair: Color = look.hair_color
	var eye_y: float = LookBase.EYE_HEIGHT
	var mouth_y: float = LookBase.MOUTH_HEIGHT
	_draw_shading(eye_y, mouth_y)
	if look.base == PlayerLook.Base.MALE and look.facial_hair > 0:
		_face_frame()
		_draw_facial_hair(look.facial_hair, hair, mouth_y)

	var mouth_half: float = MOUTH_HALF * lerpf(0.55, 1.45, look.mouth_size)
	_frame(0.0, mouth_y, mouth_half, 1.0)
	_draw_mouth(look.mouth_type)

	var brow: Color = Color(hair.darkened(0.25), BROW_PAINT)
	for sign_x: float in [-1.0, 1.0]:
		_frame(sign_x * LookBase.EYE_APART, eye_y, EYE_HALF, sign_x)
		_draw_eye(look.eye_type)
		var line: PackedVector2Array = PackedVector2Array()
		for step: int in 13:
			line.append(LookParts.brow_point(look.eye_type, float(step) / 12.0))
		var thick: float = LookParts.BROWS[look.eye_type][6]
		_stroke(line, thick * 0.75, brow)

	if look.glasses == PlayerLook.Glasses.EYEPATCH:
		# The player's left is to the right of the map.
		_draw_eyepatch(1.0 if look.eyepatch_side == PlayerLook.Eye.LEFT else -1.0, eye_y)


# --- Where things go -----------------------------------------------------------------

## Pixels for one face unit, across and down.
func _face_px() -> Vector2:
	var across: float = size.x / (TAU * info.face_radius)
	var down: float = size.y / (info.top_z - info.map_low_z)
	return Vector2(across, down) * info.half_width


## The pixel row of `height` up the head (0 chin, 1 crown).
func _row(height: float) -> float:
	return (info.top_z - info.head_z(height)) / (info.top_z - info.map_low_z) * size.y


## Draw from here on round a point `x` face units from the middle of the face
## and `height` up the head, in units of `scale` face units, mirrored when
## `mirror` is negative.
func _frame(x: float, height: float, scale: float, mirror: float) -> void:
	var px: Vector2 = _face_px()
	_origin = Vector2(size.x / 2.0 + x * px.x, _row(height))
	_unit = Vector2(px.x * scale * mirror, px.y * scale)


## Draw in whole-face terms: x in face units from the middle, y the height up
## the head (so up is up).
func _face_frame() -> void:
	_origin = Vector2(size.x / 2.0, _row(0.0))
	_unit = Vector2(_face_px().x, _row(1.0) - _row(0.0))


func _p(x: float, y: float) -> Vector2:
	return _origin + Vector2(x, y) * _unit


func _px(points: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		out.append(_p(point.x, point.y))
	return out


func _width(units: float) -> float:
	return absf(units * _unit.y)


# --- Shapes --------------------------------------------------------------------------

func _oval(x: float, y: float, rx: float, ry: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for step: int in 36:
		var turn: float = TAU * float(step) / 36.0
		points.append(_p(x + cos(turn) * rx, y + sin(turn) * ry))
	draw_colored_polygon(points, color)


func _fill(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(_px(points), color)


func _stroke(points: PackedVector2Array, width: float, color: Color) -> void:
	var line: PackedVector2Array = _px(points)
	draw_polyline(line, color, _width(width), true)
	# Round ends.
	draw_circle(line[0], _width(width) / 2.0, color)
	draw_circle(line[line.size() - 1], _width(width) / 2.0, color)


## A curve from `from` to `to`, pulled towards `pull`.
func _bend(from: Vector2, pull: Vector2, to: Vector2, steps: int = 16) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for step: int in steps + 1:
		var t: float = float(step) / float(steps)
		points.append(from.lerp(pull, t).lerp(pull.lerp(to, t), t))
	return points


## `points` with its corners rounded off.
func _rounded(points: PackedVector2Array, passes: int = 2) -> PackedVector2Array:
	var out: PackedVector2Array = points
	for pass_index: int in passes:
		var next: PackedVector2Array = PackedVector2Array()
		for i: int in out.size():
			var a: Vector2 = out[i]
			var b: Vector2 = out[(i + 1) % out.size()]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		out = next
	return out


func _skin_shade(amount: float) -> Color:
	return look.skin_color.darkened(amount)


# --- Shading -------------------------------------------------------------------------

## What makes the features sit in the face and not on it: the hollows the
## eyes lie in, the shadow under the nose and the lower lip, the hollow of
## the cheeks, and the folds from the nose to the corners of the mouth.
func _draw_shading(eye_y: float, mouth_y: float) -> void:
	var shadow: Color = Color(look.skin_color.r * 0.5, look.skin_color.g * 0.36, look.skin_color.b * 0.34)
	for sign_x: float in [-1.0, 1.0]:
		_frame(sign_x * LookBase.EYE_APART, eye_y, EYE_HALF, sign_x)
		_soft(-0.1, -0.15, 1.9, 1.75, shadow, 0.3)
		# The crease of the lid, and the bag under the eye.
		_stroke(_bend(Vector2(-1.0, -1.08), Vector2(0.0, -1.42), Vector2(1.1, -1.05)), 0.07, Color(shadow, 0.4))
		_stroke(_bend(Vector2(-0.8, 1.15), Vector2(0.0, 1.45), Vector2(0.85, 1.1)), 0.06, Color(shadow, 0.22))
	_face_frame()
	_soft(0.0, LookBase.NOSE_HEIGHT - 0.035, 0.34, 0.05, shadow, 0.34)
	_soft(0.0, mouth_y - 0.065, 0.3, 0.035, shadow, 0.26)
	for sign_x: float in [-1.0, 1.0]:
		_soft(sign_x * 1.02, 0.2, 0.34, 0.14, shadow, 0.2)
		_soft(sign_x * 1.45, 0.62, 0.3, 0.14, shadow, 0.16)
		_stroke(_bend(Vector2(sign_x * 0.3, LookBase.NOSE_HEIGHT - 0.01), Vector2(sign_x * 0.52, mouth_y + 0.1),
			Vector2(sign_x * 0.5, mouth_y + 0.05), 8), 0.012, Color(shadow, 0.1))


## A shadow with no edge: darkest in the middle, gone at `rx`, `ry`.
func _soft(x: float, y: float, rx: float, ry: float, color: Color, strength: float) -> void:
	const RINGS: int = 9
	for ring: int in RINGS:
		var size_share: float = 1.0 - float(ring) / float(RINGS)
		_oval(x, y, rx * size_share, ry * size_share, Color(color, strength / float(RINGS) * 1.6))


# --- Eyes ----------------------------------------------------------------------------

## One eye. x runs away from the nose, y down; 1 is half the eye's width.
## Its brow is LookParts.BROWS.
func _draw_eye(type: int) -> void:
	match type:
		1: # Almond
			var shape: PackedVector2Array = _bend(Vector2(-1.15, 0.12), Vector2(0.0, -1.15), Vector2(1.2, -0.12))
			shape.append_array(_bend(Vector2(1.2, -0.12), Vector2(0.0, 0.95), Vector2(-1.15, 0.12)).slice(1, 16))
			_fill(shape, EYE_WHITE)
			_iris(0.0, -0.03, 0.46)
			_stroke(_bend(Vector2(-1.15, 0.12), Vector2(0.0, -1.15), Vector2(1.2, -0.12)), 0.17, INK)
			_stroke(PackedVector2Array([Vector2(1.2, -0.12), Vector2(1.55, -0.5)]), 0.14, INK)
		2: # Sleepy
			_oval(0.0, 0.0, 1.1, 0.92, INK)
			_oval(0.0, 0.0, 0.98, 0.8, EYE_WHITE)
			_iris(0.0, 0.18, 0.5)
			var lid: PackedVector2Array = PackedVector2Array()
			for step: int in 19:
				var turn: float = PI + PI * float(step) / 18.0
				lid.append(Vector2(cos(turn) * 1.12, sin(turn) * 0.94))
			lid.append(Vector2(1.12, 0.02))
			lid.append(Vector2(-1.12, 0.02))
			_fill(lid, _skin_shade(0.12))
			_stroke(PackedVector2Array([Vector2(-1.12, 0.02), Vector2(1.12, 0.02)]), 0.16, INK)
		3: # Fierce
			_oval(0.0, 0.05, 1.08, 0.82, INK)
			_oval(0.0, 0.05, 0.96, 0.7, EYE_WHITE)
			_iris(-0.1, 0.12, 0.44)
			# The lid comes down towards the nose.
			_fill(PackedVector2Array([Vector2(-1.3, -1.0), Vector2(1.3, -1.0), Vector2(1.3, -0.62), Vector2(-1.3, 0.12)]), look.skin_color)
			_stroke(PackedVector2Array([Vector2(-1.1, 0.02), Vector2(1.1, -0.55)]), 0.16, INK)
		4: # Dots
			_oval(0.0, 0.0, 0.5, 0.64, INK)
			_oval(-0.14, -0.22, 0.15, 0.17, Color.WHITE)
		5: # Wide
			_oval(0.0, -0.1, 1.08, 1.3, INK)
			_oval(0.0, -0.1, 0.97, 1.19, EYE_WHITE)
			_iris(0.0, 0.0, 0.5)
			for lash: Vector2 in [Vector2(0.45, -1.2), Vector2(0.8, -0.95), Vector2(1.0, -0.55)]:
				_stroke(PackedVector2Array([lash, lash * 1.3 + Vector2(0.08, -0.08)]), 0.12, INK)
		_: # Round
			_oval(0.0, 0.0, 1.1, 1.02, INK)
			_oval(0.0, 0.0, 0.98, 0.9, EYE_WHITE)
			_iris(0.0, 0.03, 0.55)


func _iris(x: float, y: float, radius: float) -> void:
	_oval(x, y, radius, radius, IRIS)
	_oval(x, y, radius * 0.52, radius * 0.52, INK)
	_oval(x - radius * 0.35, y - radius * 0.4, radius * 0.24, radius * 0.24, Color.WHITE)


# --- Mouths --------------------------------------------------------------------------

## y runs down; 1 is half the mouth's width.
func _draw_mouth(type: int) -> void:
	var line: Color = look.skin_color.darkened(0.6).lerp(Color(0.35, 0.05, 0.05), 0.4)
	var lips: Color = look.skin_color.lerp(Color(0.78, 0.2, 0.26), 0.6)
	match type:
		1: # Smile
			_stroke(_bend(Vector2(-1.0, -0.2), Vector2(0.0, 0.8), Vector2(1.0, -0.2)), 0.14, line)
			for sign_x: float in [-1.0, 1.0]:
				_stroke(_bend(Vector2(sign_x * 1.12, -0.34), Vector2(sign_x * 0.98, -0.22), Vector2(sign_x * 1.1, -0.06), 6), 0.09, line)
		2: # Grin
			var open: PackedVector2Array = _bend(Vector2(1.0, -0.22), Vector2(0.0, 1.55), Vector2(-1.0, -0.22))
			_fill(open, Color(0.24, 0.04, 0.06))
			var teeth: PackedVector2Array = _bend(Vector2(0.93, -0.2), Vector2(0.0, 0.62), Vector2(-0.93, -0.2))
			_fill(teeth, Color(0.98, 0.97, 0.94))
			_oval(0.0, 0.5, 0.34, 0.13, Color(0.85, 0.36, 0.4))
			open.append(open[0])
			_stroke(open, 0.11, line)
		3: # Frown
			_stroke(_bend(Vector2(-1.0, 0.3), Vector2(0.0, -0.55), Vector2(1.0, 0.3)), 0.14, line)
		4: # Lips
			var upper: PackedVector2Array = PackedVector2Array([
				Vector2(-1.0, 0.0), Vector2(-0.55, -0.3), Vector2(-0.18, -0.42), Vector2(0.0, -0.3),
				Vector2(0.18, -0.42), Vector2(0.55, -0.3), Vector2(1.0, 0.0), Vector2(0.0, 0.08),
			])
			_fill(upper, lips.darkened(0.12))
			var lower: PackedVector2Array = _bend(Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0))
			lower.append(Vector2(0.0, 0.08))
			_fill(lower, lips)
			_stroke(_bend(Vector2(-1.0, 0.0), Vector2(0.0, 0.14), Vector2(1.0, 0.0)), 0.07, line)
		5: # Smirk
			_stroke(_bend(Vector2(-1.0, 0.12), Vector2(0.25, 0.4), Vector2(1.0, -0.42)), 0.14, line)
			_stroke(_bend(Vector2(1.1, -0.68), Vector2(1.26, -0.5), Vector2(1.12, -0.3), 6), 0.09, line)
		_: # Line
			_stroke(_bend(Vector2(-1.0, 0.0), Vector2(0.0, 0.16), Vector2(1.0, 0.0)), 0.14, line)


# --- Facial hair ---------------------------------------------------------------------

## In whole-face terms (see _face_frame()).
func _draw_facial_hair(type: int, hair: Color, mouth_y: float) -> void:
	match type:
		1: # Stubble: a shadow under the hairs LookParts stands on it
			_fill(_beard(mouth_y, 0.05), Color(hair, 0.14))
		2: # Moustache
			_fill(_moustache(mouth_y, 0.62, 0.11), hair)
		3: # Goatee
			_fill(_moustache(mouth_y, 0.56, 0.1), hair)
			for sign_x: float in [-1.0, 1.0]:
				_stroke(PackedVector2Array([
					Vector2(sign_x * 0.5, mouth_y + 0.05), Vector2(sign_x * 0.52, mouth_y - 0.06),
					Vector2(sign_x * 0.36, mouth_y - 0.14),
				]), 0.05, hair)
			_fill(_rounded(PackedVector2Array([
				Vector2(-0.42, mouth_y - 0.075), Vector2(0.42, mouth_y - 0.075), Vector2(0.4, -0.02),
				Vector2(0.0, -0.06), Vector2(-0.4, -0.02),
			])), hair)
		4: # Full beard
			_fill(_beard(mouth_y, 0.07), hair)
			_fill(_moustache(mouth_y, 0.66, 0.12), hair)
			# The lips show through.
			_oval(0.0, mouth_y, 0.36, 0.035, look.skin_color)
		5: # Handlebar
			_fill(_moustache(mouth_y, 0.6, 0.1), hair)
			for sign_x: float in [-1.0, 1.0]:
				_stroke(_bend(Vector2(sign_x * 0.5, mouth_y + 0.045), Vector2(sign_x * 0.95, mouth_y - 0.03), Vector2(sign_x * 1.0, mouth_y + 0.13)), 0.035, hair)
		6: # Mutton chops
			for sign_x: float in [-1.0, 1.0]:
				_fill(_rounded(PackedVector2Array([
					Vector2(sign_x * BURN_X, 0.56), Vector2(sign_x * 1.25, 0.54), Vector2(sign_x * 1.1, 0.32),
					Vector2(sign_x * 0.62, mouth_y + 0.03), Vector2(sign_x * 0.6, mouth_y - 0.07),
					Vector2(sign_x * 1.05, 0.02), Vector2(sign_x * 1.6, 0.16),
				])), hair)
			_fill(_moustache(mouth_y, 0.64, 0.1), hair)


## The outline of a moustache `half` wide and `thick` up the head.
func _moustache(mouth_y: float, half: float, thick: float) -> PackedVector2Array:
	var low: float = mouth_y + 0.035
	var shape: PackedVector2Array = _bend(Vector2(-half, low - 0.01), Vector2(0.0, low + thick * 1.5), Vector2(half, low - 0.01))
	shape.append_array(_bend(Vector2(half, low - 0.01), Vector2(0.0, low + 0.03), Vector2(-half, low - 0.01)).slice(1, 16))
	return shape


## The outline of a beard: from sideburn to sideburn under the cheeks, round
## the mouth, and down over the jaw. `over_lip` is how far above the mouth its
## edge runs.
func _beard(mouth_y: float, over_lip: float) -> PackedVector2Array:
	var top: float = mouth_y + over_lip
	return _rounded(PackedVector2Array([
		Vector2(-BURN_X, 0.56), Vector2(-1.3, 0.55), Vector2(-1.15, 0.34), Vector2(-0.72, top - 0.01),
		Vector2(-0.3, top + 0.02), Vector2(0.3, top + 0.02), Vector2(0.72, top - 0.01),
		Vector2(1.15, 0.34), Vector2(1.3, 0.55), Vector2(BURN_X, 0.56),
		Vector2(1.66, 0.2), Vector2(1.25, -0.07), Vector2(0.0, -0.13), Vector2(-1.25, -0.07), Vector2(-1.66, 0.2),
	]))


# --- Eyepatch ------------------------------------------------------------------------

## A patch over the eye on the `side` of the map (-1 left, 1 right) and its
## strap: a band round the head, low behind the ear on the patch's side and
## high over the brow on the other.
func _draw_eyepatch(side: float, eye_y: float) -> void:
	_face_frame()
	var px: Vector2 = _face_px()
	var eye_turn: float = side * LookBase.EYE_APART * info.half_width / info.face_radius
	var low_turn: float = side * 1.2
	const SWING: float = 0.17
	var middle: float = eye_y + SWING * cos(eye_turn - low_turn)
	var strap: PackedVector2Array = PackedVector2Array()
	for step: int in 97:
		var turn: float = -PI + TAU * float(step) / 96.0
		strap.append(Vector2(turn * info.face_radius / info.half_width, middle - SWING * cos(turn - low_turn)))
	draw_polyline(_px(strap), PATCH, px.y * 0.07, true)
	_frame(side * LookBase.EYE_APART, eye_y, EYE_HALF, side)
	_fill(_rounded(PackedVector2Array([
		Vector2(-1.45, -1.25), Vector2(1.5, -1.3), Vector2(1.55, 0.5), Vector2(0.4, 1.5), Vector2(-0.6, 1.45), Vector2(-1.5, 0.4),
	]), 3), PATCH)
