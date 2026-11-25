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
##   READY    to the server   []   the match is loaded on that machine
##   INPUT    to the server   [newest tick, [that tick's buttons, the tick before's, ...]]
##   STATE    to everyone     [tick, piece, pieces, size, bytes]   (may be lost)
##            NetState.pack() squeezed and cut into pieces that each fit one
##            packet: see cut_state() and StateJoiner
##   EVENTS   to one person   [tick, NetEvents' notes of that tick for them]
##   END      to everyone     { "reason": "final" | "left", "winner": seat or -1,
##                              "score": [home, away] }
##   PAUSE    to the server   [yes or no]   that person wants the match held
##            (their pause menu is open): see NetServer
##   STATS    to everyone     [size, bytes]   StatBook.net_pack() squeezed: the
##            numbers of the box score and the halftime report

enum Kind { HELLO, WELCOME, REJECT, START, INPUT, END, STATE, EVENTS, READY, PAUSE, STATS }

## Goes up with every change to the messages or to what the game does with them:
## two machines only play each other on the same one.
const VERSION: int = 7
const DEFAULT_PORT: int = 24642
## The ticks of buttons in every INPUT message: one gets through as long as
## that many packets in a row are not all lost.
const INPUT_REPEATS: int = 3
## The most bytes of a state in one message: with the rest of the message it
## stays under what one packet carries. A message that has to be split on the
## way is lost whole when any part of it is.
const PIECE_BYTES: int = 1100
## No state is anywhere near this big; one that says it is, is not looked at.
const MAX_STATE_BYTES: int = 65536
## Floats after the actions' own in a tick's buttons: the stick as a move on
## the field (x, z) and the camera's right (x, z).
const VIEW_FLOATS: int = 4


## The bodies of the STATE messages that carry `state` (NetState.pack()) for `tick`.
static func cut_state(tick: int, state: Array) -> Array[Array]:
	var plain: PackedByteArray = var_to_bytes(state)
	var squeezed: PackedByteArray = plain.compress(FileAccess.COMPRESSION_ZSTD)
	var pieces: int = maxi(ceili(float(squeezed.size()) / PIECE_BYTES), 1)
	var bodies: Array[Array] = []
	for piece: int in pieces:
		bodies.append([tick, piece, pieces, plain.size(), squeezed.slice(piece * PIECE_BYTES, (piece + 1) * PIECE_BYTES)])
	return bodies


## Puts the pieces of states back together as they come in.
class StateJoiner:
	extends RefCounted
	## The tick being put together, and its pieces so far.
	var _tick: int = -1
	var _pieces: Array[PackedByteArray] = []
	var _have: int = 0
	var _size: int = 0

	## Takes the body of one STATE message. Returns [tick, state] when that was
	## the last piece of a state, and nothing otherwise. Pieces of an older tick
	## than the one being put together are too late.
	func add(body: Variant) -> Array:
		if typeof(body) != TYPE_ARRAY:
			return []
		var parts: Array = body
		if parts.size() != 5 or typeof(parts[4]) != TYPE_PACKED_BYTE_ARRAY:
			return []
		for at: int in 4:
			if typeof(parts[at]) != TYPE_INT:
				return []
		var tick: int = parts[0]
		var piece: int = parts[1]
		var pieces: int = parts[2]
		var size: int = parts[3]
		if pieces < 1 or pieces > 64 or piece < 0 or piece >= pieces or size <= 0 or size > NetProtocol.MAX_STATE_BYTES or tick < _tick:
			return []
		if tick != _tick or pieces != _pieces.size() or size != _size:
			_tick = tick
			_size = size
			_have = 0
			_pieces.clear()
			_pieces.resize(pieces)
		if _pieces[piece].is_empty():
			_pieces[piece] = parts[4]
			_have += 1
		if _have < pieces:
			return []
		var squeezed: PackedByteArray = PackedByteArray()
		for part: PackedByteArray in _pieces:
			squeezed.append_array(part)
		_tick = tick + 1
		_have = 0
		_pieces.clear()
		var plain: PackedByteArray = squeezed.decompress(size, FileAccess.COMPRESSION_ZSTD)
		if plain.size() != size:
			return []
		var state: Variant = bytes_to_var(plain)
		return [tick, state] if typeof(state) == TYPE_ARRAY else []


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
