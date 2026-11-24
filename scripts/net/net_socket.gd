class_name NetSocket
extends RefCounted
## The line between the server and the people's machines: messages of
## [kind, body] (see NetProtocol) over ENet. poll() once a tick takes in what
## has arrived. The server's id is 1; everyone else gets one when they join.
##
## Nothing but this class knows that it is ENet underneath.

signal peer_joined(id: int)
signal peer_left(id: int)
signal message(from: int, kind: int, body: Variant)

const SERVER: int = 1
## Messages longer than this are not looked at.
const MAX_BYTES: int = 16384

var _peer: ENetMultiplayerPeer
## For trying things out: milliseconds added to every message on its way out
## and again on its way in, at this end. 50 here is a line with 100 ms more
## there and back.
var lag_ms: int = 0
## Messages held back by lag_ms: [when it may go on, ...what it is].
var _held_in: Array[Array] = []
var _held_out: Array[Array] = []
## Seconds of silence after which the other end counts as gone.
var _patience: float = LOADING_PATIENCE

## While a match is being loaded a machine says nothing for seconds on end; in
## a match, silence that long means it is gone. Not much shorter than this: a
## machine that hangs for a second or two (a window dragged, a file saved)
## loses what came in meanwhile, and what has to arrive is slow to be sent
## again after that.
const LOADING_PATIENCE: float = 45.0
const PLAYING_PATIENCE: float = 10.0
## Ticks of a match that pass before the patience is cut down to that.
const SETTLE_TICKS: int = 180


## Listens on `port` for up to `seats` machines. Null when the port cannot be had.
static func host(port: int, seats: int) -> NetSocket:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if peer.create_server(port, seats) != OK:
		return null
	return NetSocket.new(peer)


## Sets out for the server at `address`. peer_joined(SERVER) says it got there;
## failed() that it did not.
static func join(address: String, port: int) -> NetSocket:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		return null
	return NetSocket.new(peer)


func _init(peer: ENetMultiplayerPeer) -> void:
	_peer = peer
	_peer.peer_connected.connect(func(id: int) -> void:
		_be_patient(id)
		peer_joined.emit(id))
	_peer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))


func poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	while _peer != null and _peer.get_available_packet_count() > 0:
		var from: int = _peer.get_packet_peer()
		var bytes: PackedByteArray = _peer.get_packet()
		if bytes.size() > MAX_BYTES:
			continue
		# No objects come out of this: only plain values.
		var data: Variant = bytes_to_var(bytes)
		if typeof(data) != TYPE_ARRAY:
			continue
		var parts: Array = data
		if parts.size() == 2 and typeof(parts[0]) == TYPE_INT:
			if lag_ms > 0:
				_held_in.append([Time.get_ticks_msec() + lag_ms, from, parts[0], parts[1]])
			else:
				message.emit(from, parts[0], parts[1])
	var now: int = Time.get_ticks_msec()
	while not _held_out.is_empty() and int(_held_out[0][0]) <= now:
		var out: Array = _held_out.pop_front()
		_put(out[1], out[2], out[3], out[4])
	while not _held_in.is_empty() and int(_held_in[0][0]) <= now:
		var held: Array = _held_in.pop_front()
		message.emit(held[1], held[2], held[3])


## `to` 0 is everyone. `reliable` messages arrive, and in order; the others may
## be lost, and are not waited for.
func send(to: int, kind: int, body: Variant, reliable: bool = true) -> void:
	if lag_ms > 0:
		_held_out.append([Time.get_ticks_msec() + lag_ms, to, kind, body, reliable])
	else:
		_put(to, kind, body, reliable)


func _put(to: int, kind: int, body: Variant, reliable: bool) -> void:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_peer.set_target_peer(to)
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	_peer.put_packet(var_to_bytes([kind, body]))


## How long the other ends may be silent before they count as gone, from now on.
func set_patience(seconds: float) -> void:
	_patience = seconds
	if _peer == null:
		return
	for line: ENetPacketPeer in _peer.host.get_peers():
		if line.get_state() == ENetPacketPeer.STATE_CONNECTED:
			line.set_timeout(0, roundi(seconds * 1000.0), roundi(seconds * 2000.0))


func _be_patient(id: int) -> void:
	var line: ENetPacketPeer = _peer.get_peer(id)
	if line != null:
		line.set_timeout(0, roundi(_patience * 1000.0), roundi(_patience * 2000.0))
		# ENet throws away messages that may be lost when the line has been slow
		# (after a machine was busy loading, for one), and is slow to stop doing
		# so. Every state and every tick of buttons is wanted: never throttle.
		line.throttle_configure(1000, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)


## The server takes `id` off the line, once what was sent to it has gone out.
func drop(id: int) -> void:
	if _peer != null:
		var line: ENetPacketPeer = _peer.get_peer(id)
		if line != null:
			line.peer_disconnect_later()


## Still on its way to the server.
func joining() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING


## The line is gone, or never came about.
func failed() -> bool:
	return _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED


func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
