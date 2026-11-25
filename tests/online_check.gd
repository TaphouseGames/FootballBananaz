extends SceneTree
## Checks the way from ONLINE to a match, without the real matchmaker: a
## stand-in for it runs beside this (tools/fake_matchmaker.py, needs python).
##  - what the host tells a server it starts is read right (NetHost),
##  - two people who search are given the same server and a pass each; a search
##    that is called off leaves no ticket behind; a wrong token is said so,
##  - a server started for those two lets in nobody else, and nobody twice,
##  - the online screen goes from the team to the search to "found", and (B)
##    calls a search off.
##
## Run:  godot --headless --path . --script res://tests/online_check.gd
## (not with --fixed-fps: it waits on the stand-in in real time). Half a minute.

const PORT: int = 24747
const WEB_PORT: int = 8799
const URL: String = "http://127.0.0.1:8799"

var _web: int = -1
var _server: NetServer
var _failures: PackedStringArray = PackedStringArray()
var _begun: bool = false


func _initialize() -> void:
	_web = OS.create_process("python", ["tools/fake_matchmaker.py", "--port", str(WEB_PORT), "--token", "dev", "--server-port", str(PORT), "--delay", "1"])


func _process(_delta: float) -> bool:
	if not _begun:
		_begun = true
		_run()
	return false


func _run() -> void:
	_check_host()
	if _web < 0:
		_fail("python did not start the stand-in matchmaker")
		_done()
		return
	await create_timer(1.5).timeout

	# Two people search: the same server for both, a pass each.
	var found: Array[Array] = [[], []]
	var makers: Array[EdgegapMatchmaker] = []
	for i: int in 2:
		var maker: EdgegapMatchmaker = _maker("dev")
		makers.append(maker)
		maker.found.connect(func(address: String, port: int, match_pass: String) -> void: found[i] = [address, port, match_pass])
		maker.failed.connect(func(reason: String) -> void: _fail("search %d failed: %s" % [i, reason]))
	makers[0].search()
	await create_timer(2.5).timeout
	if not found[0].is_empty():
		_fail("a match was found with nobody else looking")
	makers[1].search()
	await _until(func() -> bool: return not found[0].is_empty() and not found[1].is_empty(), 12.0)
	if found[0].is_empty() or found[1].is_empty():
		_fail("two searches did not find each other: %s" % [found])
		_done()
		return
	if found[0][0] != "127.0.0.1" or found[0][1] != PORT or found[1][1] != PORT:
		_fail("the server found is %s and %s" % [found[0], found[1]])
	if found[0][2] == "" or found[0][2] == found[1][2]:
		_fail("the passes are %s and %s" % [found[0][2], found[1][2]])

	# Called off: no ticket is left waiting for somebody.
	var before: int = (await _debug()).get("tickets", -1)
	var third: EdgegapMatchmaker = _maker("dev")
	var third_found: Array[bool] = [false]
	third.found.connect(func(_a: String, _p: int, _m: String) -> void: third_found[0] = true)
	third.search()
	await create_timer(1.0).timeout
	if (await _debug()).get("tickets", -1) != before + 1:
		_fail("a search made no ticket")
	third.cancel()
	await create_timer(1.0).timeout
	if (await _debug()).get("tickets", -1) != before:
		_fail("a search that was called off left its ticket")
	if third_found[0]:
		_fail("a search that was called off found a match")

	# A token the matchmaker does not know.
	var stranger: EdgegapMatchmaker = _maker("wrong")
	var said: PackedStringArray = PackedStringArray()
	stranger.failed.connect(func(reason: String) -> void: said.append(reason))
	stranger.search()
	await _until(func() -> bool: return not said.is_empty(), 5.0)
	if said.is_empty() or not said[0].contains("version"):
		_fail("a wrong token was answered with %s" % [said])

	# The server of that match: only those two, each once.
	_server = NetServer.new()
	_server.port = PORT
	_server.quit_when_done = false
	_server.passes = PackedStringArray([found[0][2], found[1][2]])
	root.add_child(_server)
	var answers: Array[String] = ["", "", "", ""]
	var passes: PackedStringArray = ["somebody else", found[0][2], found[0][2], found[1][2]]
	for i: int in 4:
		var client: NetClient = NetClient.new()
		var pad: PadInput = PadInput.new()
		pad.remote = true
		client.pad = pad
		client.match_pass = passes[i]
		root.add_child(client)
		client.welcomed.connect(func(seat: int) -> void: answers[i] = "seat %d" % seat)
		client.rejected.connect(func(reason: String) -> void: answers[i] = reason)
		client.join("127.0.0.1", PORT)
		await _until(func() -> bool: return answers[i] != "", 5.0)
	if answers != ["not in this match", "seat 0", "not in this match", "seat 1"]:
		_fail("the server answered the four who came with %s" % [answers])

	await _check_lobby()
	_done()


func _check_host() -> void:
	var host: NetHost = NetHost.new()
	host.read('["cusfn10msflc73beiik0","cusfn18msflc73beiil0"]', '{"ports": {"gameport": {"name": "Game Port", "internal": 7777, "external": 31504, "protocol": "UDP"}}}')
	if host.passes != PackedStringArray(["cusfn10msflc73beiik0", "cusfn18msflc73beiil0"]) or host.port != 7777:
		_fail("the host's word was read as %s, port %d" % [host.passes, host.port])
	host.read("5", "[]")
	if not host.passes.is_empty() or host.port != 0:
		_fail("nonsense from the host was read as %s, port %d" % [host.passes, host.port])
	host.free()
	var place: Array = EdgegapMatchmaker.server_of({"status": "HOST_ASSIGNED", "assignment": {"fqdn": "x.edgegap.net", "public_ip": "", "ports": {
		"web": {"external": 30000, "protocol": "TCP"}, "game": {"external": 31504, "internal": 7777, "protocol": "UDP"}}}})
	if place != ["x.edgegap.net", 31504]:
		_fail("the server in a ticket was read as %s" % [place])
	if not EdgegapMatchmaker.server_of({"status": "SEARCHING", "assignment": null}).is_empty():
		_fail("a ticket without a server was read as having one")


## The screen itself, with a matchmaker that finds a server at once.
func _check_lobby() -> void:
	var league: League = load("res://resources/league.tres")
	var direct: DirectMatchmaker = DirectMatchmaker.new()
	direct.address = "10.1.2.3"
	direct.port = 4242
	var lobby: OnlineLobby = OnlineLobby.new()
	lobby.setup(SystemFont.new(), league.teams, direct)
	root.add_child(lobby)
	var went: Array = []
	var back: Array[int] = [0]
	lobby.ready_to_play.connect(func(address: String, port: int, match_pass: String, team: int) -> void: went.append_array([address, port, match_pass, team]))
	lobby.cancelled.connect(func() -> void: back[0] += 1)
	lobby.open()
	_press(&"ui_down")
	_press(&"ui_down")
	if lobby.pick != 2 or lobby.stage != OnlineLobby.Stage.TEAM:
		_fail("two downs put the screen at team %d, stage %d" % [lobby.pick, lobby.stage])
	# Called off before it finds anything: back at the team, and nothing comes.
	_press(&"ui_accept")
	if lobby.stage != OnlineLobby.Stage.SEARCHING:
		_fail("(A) did not start a search")
	_press(&"ui_cancel")
	await create_timer(1.0).timeout
	if lobby.stage != OnlineLobby.Stage.TEAM or not went.is_empty() or back[0] != 0:
		_fail("(B) in a search left the screen at stage %d (%s)" % [lobby.stage, went])
	_press(&"ui_accept")
	await create_timer(1.0).timeout
	if went != ["10.1.2.3", 4242, "", 2] or lobby.stage != OnlineLobby.Stage.FOUND:
		_fail("the search ended with %s at stage %d" % [went, lobby.stage])
	# With no matchmaker set up, it says so and goes back to the team.
	var bare: OnlineLobby = OnlineLobby.new()
	bare.setup(SystemFont.new(), league.teams, null)
	lobby.visible = false
	root.add_child(bare)
	bare.open()
	_press(&"ui_accept")
	if bare.stage != OnlineLobby.Stage.FAILED:
		_fail("without a matchmaker the screen is at stage %d" % bare.stage)
	_press(&"ui_accept")
	_press(&"ui_cancel")
	if bare.stage != OnlineLobby.Stage.TEAM or back[0] != 0:
		_fail("after its notice the screen is at stage %d" % bare.stage)


func _press(action: StringName) -> void:
	for down: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = down
		root.push_input(event)


func _maker(token: String) -> EdgegapMatchmaker:
	var maker: EdgegapMatchmaker = EdgegapMatchmaker.new()
	maker.url = URL
	maker.token = token
	maker.profile = "quick-1v1"
	root.add_child(maker)
	return maker


func _debug() -> Dictionary:
	var request: HTTPRequest = HTTPRequest.new()
	root.add_child(request)
	request.request(URL + "/debug")
	var answer: Array = await request.request_completed
	request.queue_free()
	var body: Variant = JSON.parse_string((answer[3] as PackedByteArray).get_string_from_utf8())
	return body if typeof(body) == TYPE_DICTIONARY else {}


func _until(done: Callable, seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while not done.call() and Time.get_ticks_msec() < until:
		await process_frame


func _fail(text: String) -> void:
	_failures.append(text)


func _done() -> void:
	if _web > 0:
		OS.kill(_web)
	if _failures.is_empty():
		print("online_check: PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("online_check: FAILED: %s" % failure)
		quit(1)
