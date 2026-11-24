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

## The buttons that are sent. Every pad's unless something else is put here.
var pad: PadInput
## The league team asked for, -1 for whichever.
var team_pick: int = -1
## The person's camera: the stick is sent as a move on the field as they see it.
var view: Basis = Basis.IDENTITY
## Says the match is loaded as soon as the server says start. Off when there
## is a match to load here first: loaded() then says it.
var auto_ready: bool = true
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
var _joiner: NetProtocol.StateJoiner = NetProtocol.StateJoiner.new()


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


## Off the line. In a match that is giving it up.
func leave() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	playing = false
	seat = -1
	tick = -1
	_sent.clear()


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


func _send_buttons() -> void:
	tick += 1
	var stick: Vector2 = pad.vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var move: Vector3 = view.x * stick.x + view.z * stick.y
	_sent.push_front(NetProtocol.pack_frame(pad.frame(), Vector3(move.x, 0.0, move.z), view.x))
	if _sent.size() > NetProtocol.INPUT_REPEATS:
		_sent.pop_back()
	_socket.send(NetSocket.SERVER, NetProtocol.Kind.INPUT, [tick, _sent], false)


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
				state.emit(whole[0], whole[1])
		NetProtocol.Kind.EVENTS:
			var parts: Array = body if typeof(body) == TYPE_ARRAY else []
			if playing and parts.size() == 2 and typeof(parts[0]) == TYPE_INT and typeof(parts[1]) == TYPE_ARRAY:
				events.emit(parts[0], parts[1])
		NetProtocol.Kind.END:
			if typeof(body) == TYPE_DICTIONARY:
				playing = false
				_over = true
				var result: Dictionary = body
				ended.emit(result)
