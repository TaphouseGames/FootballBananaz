extends SceneTree
## Checks pausing and skipping in an online match, with a server and two ends
## in this one program:
##  - the pregame intro is skipped only once both people have pressed (A), and
##    each is told how it stands in the meantime,
##  - an end that asks for a pause has the match held: the game on the server
##    stands still, both ends are told who holds it, and that person's pause
##    time runs down,
##  - let go, the match goes on after a moment (not at once),
##  - out of pause time, the match goes on although the pause is still asked for.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/net_pause_check.gd
## A few seconds.

const PORT: int = 24743
const PAUSE_SECONDS: float = 4.0

var _server: NetServer
var _clients: Array[NetClient] = []
var _pads: Array[PadInput] = []
var _welcomed: PackedInt32Array = PackedInt32Array([-1, -1])
var _started: int = 0
## For each end: the confirm button is held, the last skip note it was sent,
## and how the pause stood in the last state it was sent.
var _confirm: Array[bool] = [false, false]
var _skip_notes: PackedStringArray = PackedStringArray(["", ""])
var _pause_seen: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _stats_got: int = 0
var _tick: int = 0
var _phase: int = 0
var _phase_start: int = 0
var _listening: bool = false
var _time_held: float = -1.0
var _left_before: float = 0.0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_server = NetServer.new()
	_server.port = PORT
	_server.quit_when_done = false
	_server.pause_seconds = PAUSE_SECONDS
	root.add_child(_server)
	for i: int in 2:
		var client: NetClient = NetClient.new()
		var pad: PadInput = PadInput.new()
		pad.remote = true
		client.pad = pad
		client.name = "Client%d" % i
		root.add_child(client)
		_pads.append(pad)
		_clients.append(client)
		client.welcomed.connect(func(seat: int) -> void: _welcomed[i] = seat)
		client.started.connect(func(_home: int, _away: int) -> void: _started += 1)
		client.events.connect(func(_tick_of: int, notes: Array) -> void: _read_notes(i, notes))
		client.state.connect(func(_tick_of: int, state: Variant) -> void: _read_state(i, state))
		client.stats.connect(func(_book: Array) -> void: _stats_got += 1)


func _process(_delta: float) -> bool:
	if not _listening:
		_listening = true
		physics_frame.connect(_on_tick)
	return false


func _read_notes(i: int, notes: Array) -> void:
	for note: Variant in notes:
		var parts: Array = note
		if StringName(str(parts[2])) == &"set_skip_note":
			_skip_notes[i] = str(parts[3][0])


func _read_state(i: int, state: Variant) -> void:
	if typeof(state) == TYPE_ARRAY and (state as Array).size() == 5 and (state[4] as Array).size() == 13:
		_pause_seen[i] = state[4][12]


func _state_name() -> StringName:
	return _server.game.play_controller.state_machine.current_name()


func _time_in_state() -> float:
	return _server.game.play_controller.state_machine.current.time_in_state


func _on_tick() -> void:
	_tick += 1
	var since: int = _tick - _phase_start
	for i: int in 2:
		var frame: Dictionary[StringName, Vector2] = {}
		if _confirm[i]:
			frame[&"confirm"] = Vector2.ONE
		_pads[i].push(frame)
	match _phase:
		0:
			for client: NetClient in _clients:
				if not client.join("127.0.0.1", PORT):
					_fail("an end could not set out for the server")
			_next()
		1:
			if _started == 2 and _server.game != null:
				if _state_name() != &"Intro":
					_fail("the match did not open with the intro but in %s" % _state_name())
				else:
					_next()
			elif since > 900:
				_fail("no match after fifteen seconds")
		2:
			# The first end presses (A): nothing is skipped yet, and both are told.
			_confirm[0] = since >= 45 and since < 50
			_confirm[1] = since >= 120 and since < 125
			if since == 110:
				if _state_name() != &"Intro":
					_fail("one press skipped the intro for both")
				elif not _skip_notes[0].contains("WAITING") or not _skip_notes[1].contains("WANTS TO SKIP"):
					_fail("after one press the ends were told '%s' and '%s'" % [_skip_notes[0], _skip_notes[1]])
			elif since == 160:
				if _state_name() == &"Intro":
					_fail("both pressed and the intro was not skipped")
				else:
					print("intro: one press left it on, told '%s' / '%s'; the second skipped it" % [_skip_notes[0], _skip_notes[1]])
					_next()
		3:
			var seat: int = _welcomed[0]
			if since == 10:
				_clients[0].want_pause(true)
			elif since == 40:
				_time_held = _time_in_state()
				if not _server.paused:
					_fail("the match was not held for the pause")
			elif since == 100:
				var seen: PackedInt32Array = _pause_seen[1]
				if _time_in_state() != _time_held:
					_fail("the game went on while it was held (%.3f -> %.3f)" % [_time_held, _time_in_state()])
				elif seen.size() != 6 or seen[0] != 1 or seen[2 + seat] != 1 or seen[2 + (1 - seat)] != 0:
					_fail("the other end was told %s of the pause" % [seen])
				elif _server.pause_left(seat) > PAUSE_SECONDS - 1.0 or _server.pause_left(1 - seat) != PAUSE_SECONDS:
					_fail("pause time left: %.2f and %.2f" % [_server.pause_left(seat), _server.pause_left(1 - seat)])
				_left_before = _server.pause_left(seat)
				_clients[0].want_pause(false)
			elif since == 140:
				if not _server.paused or _pause_seen[1][1] <= 0:
					_fail("the match went on at once when the pause was let go (%s)" % [_pause_seen[1]])
			elif since == 100 + NetServer.RESUME_TICKS + 40:
				if _server.paused or _time_in_state() == _time_held or _pause_seen[1][0] != 0:
					_fail("the match did not go on after the pause (%s)" % [_pause_seen[1]])
				else:
					print("pause: held for %d ticks, %.2f s of %.0f left, on again %d ticks after letting go" % [90, _server.pause_left(seat), PAUSE_SECONDS, NetServer.RESUME_TICKS])
					_next()
		4:
			var seat: int = _welcomed[0]
			if since == 10:
				_clients[0].want_pause(true)
			elif since == 10 + int(_left_before * 60.0) + NetServer.RESUME_TICKS + 60:
				if _server.paused:
					_fail("the match is still held with no pause time left")
				elif _server.pause_left(seat) != 0.0 or _pause_seen[1][4 + seat] != 0:
					_fail("pause time left %.2f, the other end told %s" % [_server.pause_left(seat), _pause_seen[1]])
				elif _stats_got <= 0:
					_fail("no box score was sent")
				else:
					print("out of pause time: the match went on with the pause still asked for; box scores received %d" % _stats_got)
					_report()


func _next() -> void:
	_phase += 1
	_phase_start = _tick


func _fail(text: String) -> void:
	_failures.append(text)
	_report()


func _report() -> void:
	_phase = 99
	if _failures.is_empty():
		print("NET PAUSE CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("NET PAUSE CHECK FAILED: %s" % failure)
		quit(1)
