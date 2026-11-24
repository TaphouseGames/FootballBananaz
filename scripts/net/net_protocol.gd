class_name NetProtocol
extends RefCounted
## What the server and the people's machines say to each other, and how a
## tick's buttons are packed.
##
## Every message is [kind, body]:
##   HELLO    to the server   [VERSION, input_signature(), team pick]
##   WELCOME  to one person   [seat]
##   REJECT   to one person   [reason]
##   START    to everyone     [home's team pick, away's]
##   INPUT    to the server   [newest tick, [that tick's buttons, the tick before's, ...]]
##   END      to everyone     { "reason": "final" | "left", "winner": seat or -1,
##                              "score": [home, away] }

enum Kind { HELLO, WELCOME, REJECT, START, INPUT, END }

## Goes up with every change to the messages or to what the game does with them:
## two machines only play each other on the same one.
const VERSION: int = 1
const DEFAULT_PORT: int = 24642
## The ticks of buttons in every INPUT message: one gets through as long as
## that many packets in a row are not all lost.
const INPUT_REPEATS: int = 3
## Floats after the actions' own in a tick's buttons: the stick as a move on
## the field (x, z) and the camera's right (x, z).
const VIEW_FLOATS: int = 4


## A number that differs when two builds do not have the same actions.
static func input_signature() -> int:
	var names: PackedStringArray = PackedStringArray()
	for plain: StringName in PadInput.plain_actions():
		names.append(plain)
	return hash(",".join(names))


static func frame_size() -> int:
	return PadInput.plain_actions().size() * 2 + VIEW_FLOATS


## One tick of a person's buttons, with the way their stick moves their player
## on the field and their camera's right.
static func pack_frame(buttons: Dictionary[StringName, Vector2], move: Vector3, right: Vector3) -> PackedFloat32Array:
	var floats: PackedFloat32Array = PackedFloat32Array()
	floats.resize(frame_size())
	var at: int = 0
	for plain: StringName in PadInput.plain_actions():
		var read: Vector2 = buttons.get(plain, Vector2.ZERO)
		floats[at] = read.x
		floats[at + 1] = read.y
		at += 2
	floats[at] = move.x
	floats[at + 1] = move.z
	floats[at + 2] = right.x
	floats[at + 3] = right.z
	return floats


static func frame_buttons(floats: PackedFloat32Array) -> Dictionary[StringName, Vector2]:
	var buttons: Dictionary[StringName, Vector2] = {}
	var at: int = 0
	for plain: StringName in PadInput.plain_actions():
		buttons[plain] = Vector2(clampf(floats[at], 0.0, 1.0), clampf(floats[at + 1], 0.0, 1.0))
		at += 2
	return buttons


## Never longer than a full push of the stick, whatever the other side sent.
static func frame_move(floats: PackedFloat32Array) -> Vector3:
	var at: int = floats.size() - VIEW_FLOATS
	return Vector3(floats[at], 0.0, floats[at + 1]).limit_length(1.0)


static func frame_right(floats: PackedFloat32Array) -> Vector3:
	var at: int = floats.size() - VIEW_FLOATS
	var right: Vector3 = Vector3(floats[at + 2], 0.0, floats[at + 3])
	return right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT


## Whether `floats` can be a tick's buttons at all: the right length, and
## nothing in it that is not a number.
static func is_frame(floats: Variant) -> bool:
	if typeof(floats) != TYPE_PACKED_FLOAT32_ARRAY:
		return false
	var packed: PackedFloat32Array = floats
	if packed.size() != frame_size():
		return false
	for value: float in packed:
		if not is_finite(value):
			return false
	return true
