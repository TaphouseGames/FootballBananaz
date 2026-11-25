class_name NetProtocol
extends RefCounted
## What the server and the people's machines say to each other, and how a
## tick's buttons are packed.
##
## Every message is [kind, body]:
##   HELLO    to the server   [VERSION, input_signature(), team pick, pass]
##            the pass is what the matchmaker gave that person for this match
##            ("" without one): a server started for a match lets in only
##            those it was started for, each once
##   WELCOME  to one person   [seat]
##   REJECT   to one person   [reason]
##   START    to everyone     [home's team pick, away's]
##   READY    to the server   []   the match is loaded on that machine
##   INPUT    to the server   [size, bytes]: [newest tick, [that tick's buttons, the
##            tick before's, ...], the newest state this machine has whole]
##            squeezed   (may be lost)
##   STATE    to one person   [tick, piece, pieces, size, bytes]   (may be lost)
##            [the state's tables, the rest of it, base tick] squeezed and cut
##            into pieces that each fit one packet: see cut_state() and
##            StateJoiner. The tables are NetState.pack()'s numbers as bits; with
##            a base tick (not -1) only what differs from the state of that tick,
##            which that person's machine has said it has: see state_tables()
##            and cross(). A state like that is half the size.
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
const VERSION: int = 10
## The longest pass a HELLO may carry.
const MAX_PASS: int = 128
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
## The same for a message of buttons.
const MAX_INPUT_BYTES: int = 8192
## Ticks the server keeps a state to send later ones against. A person's
## machine keeps them twice as long.
const BASE_TICKS: int = 120
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


## The four tables of numbers in `state` (NetState.pack()), each as its bits.
static func state_tables(state: Array) -> Array[PackedInt32Array]:
	var tables: Array[PackedInt32Array] = []
	for at: int in 4:
		tables.append((state[at] as PackedFloat32Array).to_byte_array().to_int32_array())
	return tables


## `tables` with every bit turned that is set in `base`: what differs from it,
## and done again to that, the tables themselves. A table that is not the size
## of its base (a player more or fewer) is left as it is, both ways.
static func cross(tables: Array[PackedInt32Array], base: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for at: int in tables.size():
		var table: PackedInt32Array = tables[at].duplicate()
		if at < base.size() and base[at].size() == table.size():
			var other: PackedInt32Array = base[at]
			for i: int in table.size():
				table[i] ^= other[i]
		out.append(table)
	return out


## The tables back as the numbers NetState.unpack() takes.
static func table_floats(table: PackedInt32Array) -> PackedFloat32Array:
	return table.to_byte_array().to_float32_array()


## Puts the pieces of states back together as they come in. On an uneven line
## a state can come in after a later one: it is put together all the same, as
## long as it is not older than LATE_TICKS ticks behind the newest seen.
class StateJoiner:
	extends RefCounted
	const LATE_TICKS: int = 30
	## The states being put together, by tick: [pieces, how many are here, size].
	var _parts: Dictionary[int, Array] = {}
	## The ticks whose state is whole already (a piece may come twice).
	var _done: Dictionary[int, bool] = {}
	var _newest: int = -1

	## Takes the body of one STATE message. Returns [tick, state] when that was
	## the last piece of a state, and nothing otherwise.
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
		if pieces < 1 or pieces > 64 or piece < 0 or piece >= pieces or size <= 0 or size > NetProtocol.MAX_STATE_BYTES:
			return []
		if tick < _newest - LATE_TICKS or _done.has(tick):
			return []
		if tick > _newest:
			_newest = tick
			for old: int in _parts.keys():
				if old < _newest - LATE_TICKS:
					_parts.erase(old)
			for old: int in _done.keys():
				if old < _newest - LATE_TICKS:
					_done.erase(old)
		if not _parts.has(tick) or (_parts[tick][0] as Array).size() != pieces or _parts[tick][2] != size:
			var empty: Array[PackedByteArray] = []
			empty.resize(pieces)
			_parts[tick] = [empty, 0, size]
		var entry: Array = _parts[tick]
		var held: Array[PackedByteArray] = entry[0]
		if held[piece].is_empty():
			held[piece] = parts[4]
			entry[1] += 1
		if entry[1] < pieces:
			return []
		var squeezed: PackedByteArray = PackedByteArray()
		for part: PackedByteArray in held:
			squeezed.append_array(part)
		_parts.erase(tick)
		_done[tick] = true
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
