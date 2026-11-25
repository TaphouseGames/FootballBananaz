class_name NetClient
extends Node
## A person's end of an online match: joins the server, and from the start of
## the match sends it their buttons every tick.
##
## What the match looks like on this machine is not here yet.

## The server gave this machine a seat (0 the home team's, 1 the away team's).
signal welcomed(seat: int)
## The server will not have this machine: "version", "full", "bad hello".
signal rejected(reason: String)
## Both people are in and the match is on, with these league teams.
signal started(home_pick: int, away_pick: int)
## The match is over: NetProtocol's END body.
signal ended(result: Dictionary)
## The line to the server is gone with no END.
signal lost
## How the match stood on the server's `tick`: what NetState.pack() made.
signal state(tick: int, state: Variant)
## What happened on the server's `tick` that the picture has to hear of
## (NetEvents' notes).
signal events(tick: int, notes: Array)
## The numbers of the box score as the server has them: StatBook.net_pack().
signal stats(book: Array)

## The buttons that are sent. Every pad's unless something else is put here.
var pad: PadInput
## The league team asked for, -1 for whichever.
var team_pick: int = -1
## The person's camera: the stick is sent as a move on the field as they see it.
var view: Basis = Basis.IDENTITY
## Says the match is loaded as soon as the server says start. Off when there
## is a match to load here first: loaded() then says it.
var auto_ready: bool = true
## No buttons are sent, only that none are held: a menu is open here.
var muted: bool = false
## For trying things out: milliseconds added to the line each way (NetSocket.lag_ms).
var lag_ms: int = 0
var jitter_ms: int = 0
var loss: float = 0.0
## What is said to the server about this build. Only the tests change it.
var version: int = NetProtocol.VERSION

var seat: int = -1
var playing: bool = false
## The tick whose buttons were sent last, counted from the start of the match.
var tick: int = -1

var _socket: NetSocket
var _said_hello: bool = false
var _over: bool = false
## The last few ticks of buttons, newest first.
var _sent: Array[PackedFloat32Array] = []
## The buttons of each tick sent that the server has not answered for yet, and
## of the last one it has: [the move on the field, the buttons (PadInput.frame),
## the camera's right]. NetView runs the person's own player through them ahead
## of the server's word.
var moves: Dictionary[int, Array] = {}
var _joiner: NetProtocol.StateJoiner = NetProtocol.StateJoiner.new()
## The newest state that came in whole (-1: none yet), which the server is told
## with the buttons; and the tables of the last states, by tick: the server
## sends a state as what differs from one of them.
var have: int = -1
var _bases: Dictionary[int, Array] = {}


func _ready() -> void:
	get_tree().physics_frame.connect(_before_tick)


func _exit_tree() -> void:
	leave()


## Sets out for the server. False when that cannot even be tried.
func join(address: String, port: int = NetProtocol.DEFAULT_PORT) -> bool:
	leave()
	if pad == null:
		pad = Controllers.of(get_tree()).any
	_socket = NetSocket.join(address, port)
	if _socket == null:
		return false
	_socket.message.connect(_on_message)
	_socket.lag_ms = lag_ms
	_socket.jitter_ms = jitter_ms
	_socket.loss = loss
	_said_hello = false
	_over = false
	return true


## The match is loaded on this machine: the server may begin it.
func loaded() -> void:
	if _socket != null:
		_socket.send(NetSocket.SERVER, NetProtocol.Kind.READY, [])


## Once the match has been running a little: a server that says nothing for a
## few seconds is gone.
func be_strict() -> void:
	if _socket != null:
		_socket.set_patience(NetSocket.PLAYING_PATIENCE)


## What NetState.pack() made on the server for `tick`, from what was sent of
## it: the tables whole, or what differs from a state this machine has. Empty
## when it cannot be that.
func _rebuild(of_tick: int, sent: Variant) -> Array:
	if typeof(sent) != TYPE_ARRAY or (sent as Array).size() != 3:
		return []
	if typeof(sent[0]) != TYPE_ARRAY or (sent[0] as Array).size() != 4 or typeof(sent[2]) != TYPE_INT:
		return []
	var tables: Array[PackedInt32Array] = []
	for table: Variant in sent[0] as Array:
		if typeof(table) != TYPE_PACKED_INT32_ARRAY or (table as PackedInt32Array).size() * 4 > NetProtocol.MAX_STATE_BYTES:
			return []
		tables.append(table)
	var base: int = sent[2]
	if base >= 0:
		if not _bases.has(base):
			return []
		var of_base: Array[PackedInt32Array] = []
		of_base.assign(_bases[base])
		tables = NetProtocol.cross(tables, of_base)
	_bases[of_tick] = tables
	have = maxi(have, of_tick)
	for old: int in _bases.keys():
		if old < of_tick - 2 * NetProtocol.BASE_TICKS:
			_bases.erase(old)
	var rebuilt: Array = []
	for table: PackedInt32Array in tables:
		rebuilt.append(NetProtocol.table_floats(table))
	rebuilt.append(sent[1])
	return rebuilt


## Asks the server to hold the match (the pause menu is open here), or says it
## need not any longer. It holds it for as long as this person has pause time.
func want_pause(on: bool) -> void:
	if _socket != null and playing:
		_socket.send(NetSocket.SERVER, NetProtocol.Kind.PAUSE, [on])


## Bytes on the wire so far: [sent, received].
func traffic() -> PackedInt64Array:
	return PackedInt64Array([_socket.bytes_out, _socket.bytes_in]) if _socket != null else PackedInt64Array([0, 0])


## Off the line. In a match that is giving it up.
func leave() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	playing = false
	seat = -1
	tick = -1
	_sent.clear()
	moves.clear()
	have = -1
	_bases.clear()


## The server has played the buttons up to `ack`: the moves before that one are
## done with. (That one's are what was held going into the next.)
func forget_moves(ack: int) -> void:
	for sent: int in moves.keys():
		if sent < ack:
			moves.erase(sent)


func _before_tick() -> void:
	if _socket == null:
		return
	_socket.poll()
	if _socket == null:
		return
	if _socket.failed():
		var told: bool = _over
		leave()
		if not told:
			lost.emit()
		return
	if _socket.joining():
		return
	if not _said_hello:
		_said_hello = true
		_socket.send(NetSocket.SERVER, NetProtocol.Kind.HELLO, [version, NetProtocol.input_signature(), team_pick])
	if playing:
		_send_buttons()
	_socket.flush()


func _send_buttons() -> void:
	tick += 1
	var stick: Vector2 = pad.vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var buttons: Dictionary[StringName, Vector2] = pad.frame()
	if muted:
		stick = Vector2.ZERO
		buttons = {}
	var move: Vector3 = view.x * stick.x + view.z * stick.y
	var right: Vector3 = Vector3(view.x.x, 0.0, view.x.z)
	moves[tick] = [Vector3(move.x, 0.0, move.z).limit_length(1.0), buttons, right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT]
	_sent.push_front(NetProtocol.pack_frame(buttons, Vector3(move.x, 0.0, move.z), view.x))
	if _sent.size() > NetProtocol.INPUT_REPEATS:
		_sent.pop_back()
	# Mostly noughts, and three ticks that are nearly the same: squeezed it is a
	# tenth of the size.
	var plain: PackedByteArray = var_to_bytes([tick, _sent, have])
	_socket.send(NetSocket.SERVER, NetProtocol.Kind.INPUT, [plain.size(), plain.compress(FileAccess.COMPRESSION_ZSTD)], false)


func _on_message(from: int, kind: int, body: Variant) -> void:
	if from != NetSocket.SERVER:
		return
	match kind:
		NetProtocol.Kind.WELCOME:
			var welcome: Array = body if typeof(body) == TYPE_ARRAY else []
			if welcome.size() == 1 and typeof(welcome[0]) == TYPE_INT:
				seat = welcome[0]
				welcomed.emit(seat)
		NetProtocol.Kind.REJECT:
			var reject: Array = body if typeof(body) == TYPE_ARRAY else []
			_over = true
			rejected.emit(str(reject[0]) if reject.size() == 1 else "")
		NetProtocol.Kind.START:
			var start: Array = body if typeof(body) == TYPE_ARRAY else []
			if seat >= 0 and start.size() == 2 and typeof(start[0]) == TYPE_INT and typeof(start[1]) == TYPE_INT:
				playing = true
				tick = -1
				_sent.clear()
				started.emit(start[0], start[1])
				if auto_ready:
					loaded()
		NetProtocol.Kind.STATE:
			var whole: Array = _joiner.add(body) if playing else []
			if not whole.is_empty():
				var rebuilt: Array = _rebuild(whole[0], whole[1])
				if not rebuilt.is_empty():
					state.emit(whole[0], rebuilt)
		NetProtocol.Kind.EVENTS:
			var parts: Array = body if typeof(body) == TYPE_ARRAY else []
			if playing and parts.size() == 2 and typeof(parts[0]) == TYPE_INT and typeof(parts[1]) == TYPE_ARRAY:
				events.emit(parts[0], parts[1])
		NetProtocol.Kind.STATS:
			var packed: Array = body if typeof(body) == TYPE_ARRAY else []
			if playing and packed.size() == 2 and typeof(packed[0]) == TYPE_INT and typeof(packed[1]) == TYPE_PACKED_BYTE_ARRAY \
					and packed[0] > 0 and packed[0] <= NetProtocol.MAX_STATE_BYTES:
				var plain: PackedByteArray = (packed[1] as PackedByteArray).decompress(packed[0], FileAccess.COMPRESSION_ZSTD)
				var book: Variant = bytes_to_var(plain) if plain.size() == packed[0] else null
				if typeof(book) == TYPE_ARRAY:
					stats.emit(book)
		NetProtocol.Kind.END:
			if typeof(body) == TYPE_DICTIONARY:
				playing = false
				_over = true
				var result: Dictionary = body
				ended.emit(result)
