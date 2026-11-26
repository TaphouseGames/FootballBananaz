class_name NetSocket
extends RefCounted
## The line between the server and the people's machines: messages of
## [kind, body] (see NetProtocol) over ENet. poll() once a tick takes in what
## has arrived. The server's id is 1; everyone else gets one when they join.
## What is sent only leaves at the next poll() unless flush() is called: call
## it once a tick's messages are all sent, or they wait a tick for nothing.
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
## And a line that is uneven and loses things: up to this many milliseconds
## more for each message, each way; and this share (0 to 1) of the messages
## lost, each way. One that has to arrive is not lost but comes late by
## RESEND_MS and the way there and back, as when it is sent again, and those
## stay in order.
var jitter_ms: int = 0
var loss: float = 0.0
## Messages held back by those: [when it may go on, ...what it is].
var _held_in: Array[Array] = []
var _held_out: Array[Array] = []
var _sure_in: int = 0
var _sure_out: int = 0
## Bytes on the wire so far, with all that ENet adds: out and in.
var bytes_out: int = 0
var bytes_in: int = 0
## Seconds of silence after which the other end counts as gone.
var _patience: float = LOADING_PATIENCE

## While a match is being loaded a machine says nothing for seconds on end; in
## a match, silence that long means it is gone. Not much shorter than this: a
## machine that hangs for a second or two (a window dragged, a file saved)
## loses what came in meanwhile, and what has to arrive is slow to be sent
## again after that.
const LOADING_PATIENCE: float = 45.0
# Long enough for a machine that stands still a while in its first match
# (drawing things for the first time): somebody who quits says so, and is
# gone at once; this is only for a machine that crashed or lost its line.
const PLAYING_PATIENCE: float = 20.0
## Ticks of a match that pass before the patience is cut down to that.
const SETTLE_TICKS: int = 180
const RESEND_MS: int = 100


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
		var sure: bool = _peer.get_packet_mode() == MultiplayerPeer.TRANSFER_MODE_RELIABLE
		var bytes: PackedByteArray = _peer.get_packet()
		if bytes.size() > MAX_BYTES:
			continue
		# No objects come out of this: only plain values.
		var data: Variant = bytes_to_var(bytes)
		if typeof(data) != TYPE_ARRAY:
			continue
		var parts: Array = data
		if parts.size() == 2 and typeof(parts[0]) == TYPE_INT:
			if _slowed():
				var due: int = _due(sure, _sure_in)
				if due >= 0:
					if sure:
						_sure_in = due
					_held_in.append([due, from, parts[0], parts[1]])
			else:
				message.emit(from, parts[0], parts[1])
	if _peer != null and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and _peer.host != null:
		bytes_out += roundi(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
		bytes_in += roundi(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	# This is looked at once a tick: what is due within half a tick goes now, so
	# that the wait comes to lag_ms on average, not to lag_ms and half a tick.
	var now: int = Time.get_ticks_msec() + roundi(500.0 / Engine.physics_ticks_per_second)
	var sent: bool = false
	var waiting: Array[Array] = []
	for out: Array in _held_out:
		if int(out[0]) <= now:
			_put(out[1], out[2], out[3], out[4])
			sent = true
		else:
			waiting.append(out)
	_held_out = waiting
	if sent:
		flush()
	var due_in: Array[Array] = []
	waiting = []
	for held: Array in _held_in:
		if int(held[0]) <= now:
			due_in.append(held)
		else:
			waiting.append(held)
	_held_in = waiting
	for held: Array in due_in:
		message.emit(held[1], held[2], held[3])


## The line is made slower, uneven or lossy at this end.
func _slowed() -> bool:
	return lag_ms > 0 or jitter_ms > 0 or loss > 0.0


## When a message taken now may go on, or -1 when it is lost. `sure`: it has
## to arrive, and after the last such one, which is due at `after`.
func _due(sure: bool, after: int) -> int:
	var due: int = Time.get_ticks_msec() + lag_ms + (randi() % (jitter_ms + 1) if jitter_ms > 0 else 0)
	if loss > 0.0 and randf() < loss:
		if not sure:
			return -1
		due += RESEND_MS + 2 * lag_ms
	return maxi(due, after) if sure else due


## Puts what has been sent on the wire now, not at the next poll().
func flush() -> void:
	if _peer != null and _peer.host != null and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		_peer.host.flush()


## `to` 0 is everyone. `reliable` messages arrive, and in order; the others may
## be lost, and are not waited for.
func send(to: int, kind: int, body: Variant, reliable: bool = true) -> void:
	if _slowed():
		var due: int = _due(reliable, _sure_out)
		if due >= 0:
			if reliable:
				_sure_out = due
			_held_out.append([due, to, kind, body, reliable])
	else:
		_put(to, kind, body, reliable)


func _put(to: int, kind: int, body: Variant, reliable: bool) -> void:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_peer.set_target_peer(to)
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	_peer.put_packet(var_to_bytes([kind, body]))


## The line to the server as ENet measures it: [milliseconds there and back,
## the share of messages lost of late (0..1)]. Empty when there is none.
func quality() -> PackedFloat32Array:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return PackedFloat32Array()
	var line: ENetPacketPeer = _peer.get_peer(SERVER)
	if line == null:
		return PackedFloat32Array()
	return PackedFloat32Array([line.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
			line.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE)])


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
