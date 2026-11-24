extends SceneTree
## Checks the network path of the buttons, with a server and two people's ends
## in this one process, over the loopback:
##  - both are given a seat and the match starts with two people on it,
##  - a build that says another version is turned away,
##  - the stick arrives as a move on the field as each person's camera has it,
##  - with random buttons on both ends the server's game gets every press once,
##    and the match goes on to snap the ball,
##  - when one leaves, the other is told they won.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/net_input_check.gd

const PORT: int = 24731
const MONKEY_TICKS: int = 2500
const WATCHED: StringName = &"spin"

var _server: NetServer
var _clients: Array[NetClient] = []
var _stranger: NetClient
var _pads: Array[PadInput] = []
## What each end is holding down.
var _held: Array[Dictionary] = [{}, {}]
var _welcomed: PackedInt32Array = PackedInt32Array([-1, -1])
var _started: int = 0
var _stranger_told: String = ""
var _ended: Array[Dictionary] = []

var _listening: bool = false
var _tick: int = 0
var _phase: int = 0
var _phase_start: int = 0
var _sent_presses: int = 0
var _got_presses: int = 0
var _was_down: bool = false
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_server = NetServer.new()
	_server.port = PORT
	_server.quit_when_done = false
	root.add_child(_server)
	for i: int in 2:
		_clients.append(_make_client(i))
	_stranger = _make_client(2)
	_stranger.version = NetProtocol.VERSION + 100
	_stranger.rejected.connect(func(reason: String) -> void: _stranger_told = reason)


func _make_client(i: int) -> NetClient:
	var client: NetClient = NetClient.new()
	var pad: PadInput = PadInput.new()
	pad.remote = true
	client.pad = pad
	client.name = "Client%d" % i
	root.add_child(client)
	if i < 2:
		_pads.append(pad)
		client.welcomed.connect(func(seat: int) -> void: _welcomed[i] = seat)
		client.started.connect(func(_home: int, _away: int) -> void: _started += 1)
		client.ended.connect(func(result: Dictionary) -> void: _ended.append(result))
	else:
		_pads.append(pad)
	return client


func _process(_delta: float) -> bool:
	# From the first frame, so this comes after the server's and the ends' own
	# start of the tick.
	if not _listening:
		_listening = true
		physics_frame.connect(_on_tick)
	return false


func _on_tick() -> void:
	_tick += 1
	var since: int = _tick - _phase_start
	match _phase:
		0:
			for client: NetClient in _clients:
				if not client.join("127.0.0.1", PORT):
					_fail("an end could not set out for the server")
			_next()
		1:
			_push_held()
			if _started == 2:
				var seats: Array = Array(_welcomed)
				seats.sort()
				if seats != [0, 1]:
					_fail("the seats given were %s" % [_welcomed])
				elif _server.game == null or _server.game.humans.size() != 2:
					_fail("the match did not start with two people on it")
				elif not _server.game.humans[0].pad.remote or _server.game.humans[0].team != _server.game.home:
					_fail("seat 0 is not the home team on the network's buttons")
				else:
					_stranger.join("127.0.0.1", PORT)
					_next()
			elif since > 600:
				_fail("no match after ten seconds (welcomed %s, started %d)" % [_welcomed, _started])
		2:
			_push_held()
			if _stranger_told == "version":
				_next()
			elif since > 600:
				_fail("the other version was not turned away (told '%s')" % _stranger_told)
		3:
			# Both push the stick to their right; the second one's camera looks
			# the other way.
			_seat_client(1).view = Basis(Vector3.UP, PI)
			for held: Dictionary in _held:
				held[&"move_right"] = true
			_push_held()
			if since == 20:
				var first: Vector3 = _server.pad_of(0).world_move
				var second: Vector3 = _server.pad_of(1).world_move
				if first.distance_to(Vector3.RIGHT) > 0.01 or second.distance_to(Vector3.LEFT) > 0.01:
					_fail("the stick came in as %s and %s" % [first, second])
				elif absf(_server.pad_of(1).view_right.x + 1.0) > 0.01:
					_fail("the second camera's right came in as %s" % _server.pad_of(1).view_right)
				else:
					for held: Dictionary in _held:
						held.clear()
					_next()
		4:
			if since <= MONKEY_TICKS:
				_mash()
			else:
				# Hands off, and time for the last of it to arrive.
				for held: Dictionary in _held:
					held.clear()
			_push_held()
			_count_presses()
			if since > MONKEY_TICKS + 30:
				var snaps: int = _server.game.get_stat(&"snaps")
				var line: NetInputQueue = _server.queue(0)
				print("presses of '%s': %d sent, %d arrived; ticks held %d, stepped over %d; snaps %d" % [WATCHED, _sent_presses, _got_presses, line.held, line.skipped, snaps])
				if _sent_presses < 50 or _got_presses != _sent_presses:
					_fail("%d presses were sent and %d arrived" % [_sent_presses, _got_presses])
				elif snaps <= 0:
					_fail("the ball was never snapped")
				else:
					_seat_client(1).leave()
					_next()
		5:
			_push_held()
			if not _ended.is_empty():
				var result: Dictionary = _ended[0]
				if result.get("reason") != "left" or result.get("winner") != 0:
					_fail("the one who stayed was told %s" % result)
				elif _server.result != result:
					_fail("the server has it as %s" % _server.result)
				else:
					_report()
			elif since > 900:
				_fail("the one who stayed was told nothing")


## The end that was given `seat`.
func _seat_client(seat: int) -> NetClient:
	return _clients[0] if _welcomed[0] == seat else _clients[1]


func _next() -> void:
	_phase += 1
	_phase_start = _tick


## Gives every end its buttons for the next tick.
func _push_held() -> void:
	for i: int in 2:
		var frame: Dictionary[StringName, Vector2] = {}
		for plain: StringName in _held[i]:
			frame[plain] = Vector2.ONE
		_pads[i].push(frame)
	_pads[2].push({})


func _mash() -> void:
	for i: int in 2:
		for plain: StringName in PadInput.plain_actions():
			if randf() < 0.12:
				if _held[i].has(plain):
					_held[i].erase(plain)
				else:
					_held[i][plain] = true


## Presses of the watched button on seat 0: as its end holds it, and as the
## server's game is told.
func _count_presses() -> void:
	var end: int = 0 if _welcomed[0] == 0 else 1
	var down: bool = _held[end].has(WATCHED)
	if down and not _was_down:
		_sent_presses += 1
	_was_down = down
	if _server.pad_of(0).just_pressed(WATCHED):
		_got_presses += 1


func _fail(text: String) -> void:
	_failures.append(text)
	_report()


func _report() -> void:
	_phase = 99
	if _failures.is_empty():
		print("NET INPUT CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("NET INPUT CHECK FAILED: %s" % failure)
		quit(1)
