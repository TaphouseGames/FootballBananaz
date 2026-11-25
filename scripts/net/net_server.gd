class_name NetServer
extends Node
## The server of one online match. It waits for two people, plays the match
## with their buttons as they come in over the network, and ends when the game
## does or when one of them is gone (the one who stayed wins).
##
## Both are told to start as soon as the second is here; the match itself
## begins when both have said that it is loaded on their machine.
##
## The match is the same Game as offline, with both teams played by people
## whose PadInput is fed from here (Game.net_mode, Game.remote_pads).
##
## Either of them can have the match held: with their pause menu open (or
## their gamepad gone) their machine asks for it, and the game here stands
## still for as long as that person has pause time left (`pause_seconds` for
## the whole match each). Both are told who holds it and for how long yet.
## When nobody holds it any more it goes on after RESUME_TICKS, so the other
## one is not caught out. Out of pause time, the match just goes on.
##
## Run as the scene scenes/server.tscn:
##   godot --headless --path . res://scenes/server.tscn -- port=24642
##         [pause=<seconds each, 0 for none>] [rubber=0] [intro=0] [length=<seconds>]
##         [wait=<seconds to wait for both people, 0 for ever>]
## What a queue of matches wants of its matches goes there: how much pausing,
## whether the team behind is helped (RubberBand), the pregame intro.

## The match is over: NetProtocol's END body.
signal finished(result: Dictionary)

const SEATS: int = 2
## Ticks the line is kept up after the match, for END to get out.
const LINGER: int = 60
## Ticks to wait for both to have the match loaded before it begins anyway.
const READY_WAIT: int = 2700
## Ticks from the last person letting go of a pause until the match goes on.
const RESUME_TICKS: int = 90

var port: int = NetProtocol.DEFAULT_PORT
## Quits the program after the match. Off in the tests, which run it beside
## other things.
var quit_when_done: bool = true
## Seconds of pausing each person has for the whole match; the team behind is
## helped as offline; the match opens with the pregame intro.
var pause_seconds: float = 120.0
var rubber_band: bool = true
var intro: bool = true
## Seconds on the clock for the whole match, 0 for the game's own.
var game_length: float = 0.0
## Whom the match is for: the passes of the people the matchmaker put together
## (NetProtocol's HELLO). Empty lets anyone in. On the host they come from what
## it tells a server it starts (see NetHost).
var passes: PackedStringArray = PackedStringArray()
## Seconds to wait for both people before giving up, 0 for ever. A server the
## host started must not stay up (and cost) for a match that never begins.
var wait_seconds: float = 0.0
## The match is held for a pause right now.
var paused: bool = false
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
## Both are here and were told to start; who has the match loaded, and how many
## ticks they have had.
var _told_to_start: bool = false
var _loaded: Array[bool] = [false, false]
var _ready_wait: int = 0
var _scene: PackedScene
## Ticks of the match played.
var _tick: int = 0
## For the tests, in a debug build only (`-- touchdown=<tick>`): from that tick
## on, whoever first carries a live ball is put over the goal line.
var _test_touchdown: int = 0
## Who wants the match held, the seconds of it each has left, the one whose
## time is running (-1 nobody), and the ticks until it goes on.
var _wants: Array[bool] = [false, false]
var _pause_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _holder: int = -1
var _resume: int = 0
## The tables of the last states by tick, and the newest state each seat's
## machine has said it has: a state goes out as what differs from that one.
var _history: Dictionary[int, Array] = {}
var _have: PackedInt32Array = PackedInt32Array([-1, -1])
## The box score as it was sent last.
var _stats_sent: PackedByteArray = PackedByteArray()
## The passes that are on a seat, the pass of each seat, and the ticks waited
## for both people.
var _passes_used: Dictionary[String, bool] = {}
var _seat_pass: PackedStringArray = PackedStringArray(["", ""])
var _waited: int = 0
## Tells the host when this server is done (null anywhere else).
var _host: NetHost


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("port="):
			port = int(arg.trim_prefix("port="))
		elif arg.begins_with("pause="):
			pause_seconds = maxf(float(arg.trim_prefix("pause=")), 0.0)
		elif arg.begins_with("rubber="):
			rubber_band = int(arg.trim_prefix("rubber=")) != 0
		elif arg.begins_with("intro="):
			intro = int(arg.trim_prefix("intro=")) != 0
		elif arg.begins_with("length="):
			game_length = maxf(float(arg.trim_prefix("length=")), 0.0)
		elif arg.begins_with("wait="):
			wait_seconds = maxf(float(arg.trim_prefix("wait=")), 0.0)
		elif arg.begins_with("touchdown=") and OS.is_debug_build():
			_test_touchdown = int(arg.trim_prefix("touchdown="))
	_host = NetHost.from_environment()
	if _host != null:
		add_child(_host)
		passes = _host.passes
		if _host.port > 0:
			port = _host.port
		if wait_seconds <= 0.0:
			wait_seconds = NetHost.WAIT_SECONDS
		print("NetServer: started by the host for %d people" % passes.size())
	# No picture to draw: no need for more frames than ticks.
	Engine.max_fps = Engine.physics_ticks_per_second
	# Loaded before anyone is here: nobody waits for it.
	_scene = load("res://scenes/main.tscn")
	_socket = NetSocket.host(port, SEATS + 2)
	if _socket == null:
		push_error("NetServer: cannot listen on port %d" % port)
		_finish({"reason": "no port", "winner": -1, "score": [0, 0]})
		return
	_socket.peer_left.connect(_on_left)
	_socket.message.connect(_on_message)
	# Before any node's own tick: the buttons are in when the game asks for them.
	get_tree().physics_frame.connect(_before_tick)
	# And after every one of them: the tick is played, and can be sent.
	process_physics_priority = 1000
	print("NetServer: listening on port %d" % port)


func _exit_tree() -> void:
	if _socket != null:
		_socket.close()
	if Game.net_mode == Game.NetMode.SERVER:
		NetEvents.recording = false
		NetEvents.game = null
		NetEvents.clear()
		Game.net_mode = Game.NetMode.OFFLINE
		Game.remote_pads.clear()
		Game.two_players = false


## The tick is played: everyone is sent how the match stands, and what
## happened in it that the picture has to hear of.
func _physics_process(_delta: float) -> void:
	if game == null or _socket == null or not result.is_empty():
		return
	_tick += 1
	# From here on someone who says nothing for a few seconds is gone. Not at
	# once: making the match kept this machine itself silent for a while.
	if _tick == NetSocket.SETTLE_TICKS:
		_socket.set_patience(NetSocket.PLAYING_PATIENCE)
	var acks: PackedInt32Array = PackedInt32Array()
	for line: NetInputQueue in _queues:
		acks.append(line.taken)
	_send_state(NetState.pack(game, acks))
	var notes: Array[Array] = NetEvents.take(SEATS)
	for seat: int in SEATS:
		if not notes[seat].is_empty() and _peers[seat] != 0:
			_socket.send(_peers[seat], NetProtocol.Kind.EVENTS, [_tick, notes[seat]])
	_socket.flush()


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
				_quit(0)
		return
	if game == null:
		if _told_to_start and result.is_empty():
			_ready_wait += 1
			if not _loaded.has(false) or _ready_wait > READY_WAIT:
				_start()
		elif result.is_empty() and wait_seconds > 0.0:
			_waited += 1
			if _waited > wait_seconds * Engine.physics_ticks_per_second:
				_finish({"reason": "nobody", "winner": -1, "score": [0, 0]})
		return
	for seat: int in SEATS:
		var frame: PackedFloat32Array = _queues[seat].take()
		var pad: PadInput = _pads[seat]
		# Held for a pause: nobody's buttons do anything.
		if frame.is_empty() or paused:
			pad.push({})
			continue
		pad.push(NetProtocol.frame_buttons(frame))
		pad.world_move = NetProtocol.frame_move(frame)
		pad.view_right = NetProtocol.frame_right(frame)
		pad.has_view = true
	_update_pause()
	if _test_touchdown > 0 and _tick >= _test_touchdown:
		var pc: PlayController = game.play_controller
		var carrier: Player = pc.ball.carrier
		if pc.state_machine.current_name() == &"Live" and not pc.ball_dead and carrier != null and not game.conversion:
			carrier.position.x = game.tuning.field_length + 0.5 if carrier.team.attack_dir > 0 else -0.5
			_test_touchdown = 0
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
		NetProtocol.Kind.READY:
			var seat: int = _peers.find(from)
			if seat >= 0:
				_loaded[seat] = true
		NetProtocol.Kind.PAUSE:
			var pauser: int = _peers.find(from)
			var want: Array = body if typeof(body) == TYPE_ARRAY else []
			if pauser >= 0 and want.size() == 1 and typeof(want[0]) == TYPE_BOOL:
				_wants[pauser] = want[0]


func _on_hello(from: int, body: Variant) -> void:
	if _peers.has(from):
		return
	var reason: String = ""
	var hello: Array = body if typeof(body) == TYPE_ARRAY else []
	if hello.size() != 4 or typeof(hello[0]) != TYPE_INT or typeof(hello[1]) != TYPE_INT or typeof(hello[2]) != TYPE_INT:
		reason = "bad hello"
	elif typeof(hello[3]) != TYPE_STRING or (hello[3] as String).length() > NetProtocol.MAX_PASS:
		reason = "bad hello"
	elif hello[0] != NetProtocol.VERSION or hello[1] != NetProtocol.input_signature():
		reason = "version"
	elif _told_to_start or not result.is_empty() or seated() >= SEATS:
		reason = "full"
	elif not passes.is_empty() and (not passes.has(hello[3]) or _passes_used.has(hello[3])):
		reason = "not in this match"
	if reason != "":
		_socket.send(from, NetProtocol.Kind.REJECT, [reason])
		_socket.drop(from)
		return
	var seat: int = _peers.find(0)
	_peers[seat] = from
	_picks[seat] = hello[2]
	_seat_pass[seat] = hello[3]
	_passes_used[hello[3]] = true
	_socket.send(from, NetProtocol.Kind.WELCOME, [seat])
	print("NetServer: seat %d taken" % seat)
	if seated() == SEATS:
		_told_to_start = true
		_ready_wait = 0
		_socket.send(0, NetProtocol.Kind.START, [_picks[0], _picks[1]])


## One tick's buttons and the ticks before it, newest first.
func _on_input(from: int, body: Variant) -> void:
	var seat: int = _peers.find(from)
	if seat < 0 or game == null or typeof(body) != TYPE_ARRAY:
		return
	var packed: Array = body
	if packed.size() != 2 or typeof(packed[0]) != TYPE_INT or typeof(packed[1]) != TYPE_PACKED_BYTE_ARRAY or packed[0] <= 0 or packed[0] > NetProtocol.MAX_INPUT_BYTES:
		return
	var plain: PackedByteArray = (packed[1] as PackedByteArray).decompress(packed[0], FileAccess.COMPRESSION_ZSTD)
	var unpacked: Variant = bytes_to_var(plain) if plain.size() == packed[0] else null
	if typeof(unpacked) != TYPE_ARRAY:
		return
	var input: Array = unpacked
	if input.size() != 3 or typeof(input[0]) != TYPE_INT or typeof(input[1]) != TYPE_ARRAY or typeof(input[2]) != TYPE_INT:
		return
	_have[seat] = maxi(_have[seat], input[2])
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
	# Not yet a match: that person may come back (their line broke on the way in).
	if not _told_to_start:
		_passes_used.erase(_seat_pass[seat])
	print("NetServer: seat %d left" % seat)
	if _told_to_start and result.is_empty():
		var score: Array = [game.home.score, game.away.score] if game != null else [0, 0]
		_finish({"reason": "left", "winner": 1 - seat, "score": score})


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
	Game.show_intro = intro
	Game.season_match = false
	Game.team_picks = _picks.duplicate()
	NetEvents.clear()
	NetEvents.recording = true
	_history.clear()
	_have = PackedInt32Array([-1, -1])
	_wants = [false, false]
	_pause_left = PackedFloat32Array([pause_seconds, pause_seconds])
	_holder = -1
	paused = false
	game = _scene.instantiate() as Game
	NetEvents.game = game
	# Before the match sets itself up by them.
	if not rubber_band:
		game.tuning.comeback_enabled = false
	if game_length > 0.0:
		game.tuning.game_length = game_length
	add_child(game)
	# The box score goes out whenever the match moves on to something else.
	game.play_controller.state_machine.state_changed.connect(func(_from: StringName, _to: StringName) -> void: _send_stats())
	print("NetServer: match on")


## Holds the match while somebody with pause time left wants it held, and lets
## it go on a moment after the last of them lets go.
func _update_pause() -> void:
	if _holder >= 0 and not (_wants[_holder] and _pause_left[_holder] > 0.0 and _peers[_holder] != 0):
		_holder = -1
	if _holder < 0:
		for seat: int in SEATS:
			if _wants[seat] and _pause_left[seat] > 0.0 and _peers[seat] != 0:
				_holder = seat
				break
	if _holder >= 0:
		_pause_left[_holder] = maxf(_pause_left[_holder] - 1.0 / Engine.physics_ticks_per_second, 0.0)
		_resume = RESUME_TICKS
		paused = true
	elif paused:
		_resume -= 1
		paused = _resume > 0
	game.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	game.net_pause = PackedInt32Array([
		1 if paused else 0, _resume if paused and _holder < 0 else 0,
		1 if _wants[0] else 0, 1 if _wants[1] else 0, ceili(_pause_left[0]), ceili(_pause_left[1]),
	])


## Seconds of pausing `seat` has left.
func pause_left(seat: int) -> float:
	return _pause_left[seat]


## Each person is sent this tick's state as what differs from the newest one
## their machine has said it has, or whole when that one is not kept any more.
func _send_state(state: Array) -> void:
	var tables: Array[PackedInt32Array] = NetProtocol.state_tables(state)
	_history[_tick] = tables
	_history.erase(_tick - NetProtocol.BASE_TICKS)
	var cut: Dictionary[int, Array] = {}
	for seat: int in SEATS:
		if _peers[seat] == 0:
			continue
		var base: int = _have[seat] if _history.has(_have[seat]) and _have[seat] < _tick else -1
		if not cut.has(base):
			var sent: Array[PackedInt32Array] = tables
			if base >= 0:
				var of_base: Array[PackedInt32Array] = []
				of_base.assign(_history[base])
				sent = NetProtocol.cross(tables, of_base)
			cut[base] = NetProtocol.cut_state(_tick, [sent, state[4], base])
		for body: Array in cut[base]:
			_socket.send(_peers[seat], NetProtocol.Kind.STATE, body, false)


func _send_stats() -> void:
	if _socket == null or game == null:
		return
	var plain: PackedByteArray = var_to_bytes(game.stat_book.net_pack())
	if plain == _stats_sent:
		return
	_stats_sent = plain
	_socket.send(0, NetProtocol.Kind.STATS, [plain.size(), plain.compress(FileAccess.COMPRESSION_ZSTD)])


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
		_quit(1)


## The program ends; on the host, that is told first that this server is done.
func _quit(code: int) -> void:
	if _host != null:
		await _host.stop()
	get_tree().quit(code)
