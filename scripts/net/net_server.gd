class_name NetServer
extends Node
## The server of one online match. It waits for two people, plays the match
## with their buttons as they come in over the network, and ends when the game
## does or when one of them is gone (the one who stayed wins).
##
## The match is the same Game as offline, with both teams played by people
## whose PadInput is fed from here (Game.net_mode, Game.remote_pads).
##
## Run as the scene scenes/server.tscn:
##   godot --headless --path . res://scenes/server.tscn -- port=24642

## The match is over: NetProtocol's END body.
signal finished(result: Dictionary)

const SEATS: int = 2
## Ticks the line is kept up after the match, for END to get out.
const LINGER: int = 60

var port: int = NetProtocol.DEFAULT_PORT
## Quits the program after the match. Off in the tests, which run it beside
## other things.
var quit_when_done: bool = true
## The match, once both people are here.
var game: Game
## What was sent as END, or empty while the match is on or not yet begun.
var result: Dictionary = {}

var _socket: NetSocket
## The machine on each seat, 0 for none, and the league team each picked.
var _peers: PackedInt32Array = PackedInt32Array([0, 0])
var _picks: PackedInt32Array = PackedInt32Array([-1, -1])
var _queues: Array[NetInputQueue] = []
var _pads: Array[PadInput] = []
var _linger: int = -1


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("port="):
			port = int(arg.trim_prefix("port="))
	_socket = NetSocket.host(port, SEATS + 2)
	if _socket == null:
		push_error("NetServer: cannot listen on port %d" % port)
		_finish({"reason": "no port", "winner": -1, "score": [0, 0]})
		return
	_socket.peer_left.connect(_on_left)
	_socket.message.connect(_on_message)
	# Before any node's own tick: the buttons are in when the game asks for them.
	get_tree().physics_frame.connect(_before_tick)
	print("NetServer: listening on port %d" % port)


func _exit_tree() -> void:
	if _socket != null:
		_socket.close()
	if Game.net_mode == Game.NetMode.SERVER:
		Game.net_mode = Game.NetMode.OFFLINE
		Game.remote_pads.clear()
		Game.two_players = false


## How many of the two are here.
func seated() -> int:
	return SEATS - _peers.count(0)


## The buttons of `seat` as the game gets them, once the match is on.
func pad_of(seat: int) -> PadInput:
	return _pads[seat] if seat < _pads.size() else null


## The queue of `seat`'s buttons (for the tests and the logs).
func queue(seat: int) -> NetInputQueue:
	return _queues[seat] if seat < _queues.size() else null


func _before_tick() -> void:
	if _socket == null:
		return
	_socket.poll()
	if _linger >= 0:
		_linger -= 1
		if _linger < 0:
			_socket.close()
			_socket = null
			if quit_when_done:
				get_tree().quit()
		return
	if game == null:
		return
	for seat: int in SEATS:
		var frame: PackedFloat32Array = _queues[seat].take()
		var pad: PadInput = _pads[seat]
		if frame.is_empty():
			pad.push({})
			continue
		pad.push(NetProtocol.frame_buttons(frame))
		pad.world_move = NetProtocol.frame_move(frame)
		pad.view_right = NetProtocol.frame_right(frame)
		pad.has_view = true
	if game.play_controller.state_machine.current_name() == &"GameOver":
		var winner: int = -1
		if game.home.score != game.away.score:
			winner = 0 if game.home.score > game.away.score else 1
		_finish({"reason": "final", "winner": winner, "score": [game.home.score, game.away.score]})


func _on_message(from: int, kind: int, body: Variant) -> void:
	match kind:
		NetProtocol.Kind.HELLO:
			_on_hello(from, body)
		NetProtocol.Kind.INPUT:
			_on_input(from, body)


func _on_hello(from: int, body: Variant) -> void:
	if _peers.has(from):
		return
	var reason: String = ""
	var hello: Array = body if typeof(body) == TYPE_ARRAY else []
	if hello.size() != 3 or typeof(hello[0]) != TYPE_INT or typeof(hello[1]) != TYPE_INT or typeof(hello[2]) != TYPE_INT:
		reason = "bad hello"
	elif hello[0] != NetProtocol.VERSION or hello[1] != NetProtocol.input_signature():
		reason = "version"
	elif game != null or not result.is_empty() or seated() >= SEATS:
		reason = "full"
	if reason != "":
		_socket.send(from, NetProtocol.Kind.REJECT, [reason])
		_socket.drop(from)
		return
	var seat: int = _peers.find(0)
	_peers[seat] = from
	_picks[seat] = hello[2]
	_socket.send(from, NetProtocol.Kind.WELCOME, [seat])
	print("NetServer: seat %d taken" % seat)
	if seated() == SEATS:
		_start()


## One tick's buttons and the ticks before it, newest first.
func _on_input(from: int, body: Variant) -> void:
	var seat: int = _peers.find(from)
	if seat < 0 or game == null or typeof(body) != TYPE_ARRAY:
		return
	var input: Array = body
	if input.size() != 2 or typeof(input[0]) != TYPE_INT or typeof(input[1]) != TYPE_ARRAY:
		return
	var newest: int = input[0]
	var frames: Array = input[1]
	if newest < 0 or frames.size() > NetProtocol.INPUT_REPEATS:
		return
	for back: int in frames.size():
		if NetProtocol.is_frame(frames[back]):
			_queues[seat].add(newest - back, frames[back])


func _on_left(id: int) -> void:
	var seat: int = _peers.find(id)
	if seat < 0:
		return
	_peers[seat] = 0
	print("NetServer: seat %d left" % seat)
	if game != null and result.is_empty():
		_finish({"reason": "left", "winner": 1 - seat, "score": [game.home.score, game.away.score]})


func _start() -> void:
	_queues.clear()
	_pads.clear()
	for seat: int in SEATS:
		_queues.append(NetInputQueue.new())
		var pad: PadInput = PadInput.new()
		pad.remote = true
		_pads.append(pad)
	Game.net_mode = Game.NetMode.SERVER
	Game.remote_pads = _pads
	Game.two_players = true
	Game.human_side = 0
	Game.show_intro = false
	Game.season_match = false
	Game.team_picks = _picks.duplicate()
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate() as Game
	add_child(game)
	_socket.send(0, NetProtocol.Kind.START, [_picks[0], _picks[1]])
	print("NetServer: match on")


func _finish(p_result: Dictionary) -> void:
	if not result.is_empty():
		return
	result = p_result
	print("NetServer: match over, %s" % result)
	if _socket != null:
		_socket.send(0, NetProtocol.Kind.END, result)
	_linger = LINGER
	finished.emit(result)
	if _socket == null and quit_when_done:
		get_tree().quit(1)
