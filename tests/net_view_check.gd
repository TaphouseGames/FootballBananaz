extends SceneTree
## Checks the picture of an online match: a server and a second person (with
## random buttons) are started as programs of their own, and this one joins as
## the first person, also with random buttons, and watches what it is shown.
##  - the match starts here and states keep coming, one a tick near enough,
##  - the game here goes through the states of a match (line-up, live, dead),
##  - players and the ball move, and a person's own player is marked as theirs,
##  - things that happen once (falls, resets) are done here too,
##  - the clock runs.
##
## In real time, so no --fixed-fps. About a minute.
## Run:  godot --headless --path . --script res://tests/net_view_check.gd [-- seconds=40]
## With a window (no --headless) and out=<dir> it saves a picture every few seconds.

const PORT: int = 24741

var _seconds: float = 40.0
var _out: String = ""
var _shots: int = 0
var _server_pid: int = -1
var _bot_pid: int = -1
var _play: NetPlay
var _started_at: int = -1
var _begun_at: int = 0
var _states_seen: Dictionary[StringName, bool] = {}
var _first_places: PackedVector3Array = PackedVector3Array()
var _moved: int = 0
var _ball_moved: float = 0.0
var _first_ball: Vector3 = Vector3.INF
var _first_clock: float = -1.0
var _own_seen: bool = false
var _done: bool = false
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_seconds = float(arg.trim_prefix("seconds="))
		elif arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
	var godot: String = OS.get_executable_path()
	var server_args: PackedStringArray = ["--headless", "--path", ".", "res://scenes/server.tscn"]
	var bot_args: PackedStringArray = ["--headless", "--path", ".", "res://scenes/online_dev.tscn"]
	if _out != "":
		# What the other two programs print, beside the pictures.
		server_args.append_array(["--log-file", "%s/server.log" % _out])
		bot_args.append_array(["--log-file", "%s/bot.log" % _out])
	server_args.append_array(["--", "port=%d" % PORT])
	bot_args.append_array(["--", "join=127.0.0.1", "port=%d" % PORT, "bot"])
	_server_pid = OS.create_process(godot, server_args)
	_bot_pid = OS.create_process(godot, bot_args)
	_begun_at = Time.get_ticks_msec()
	_play = NetPlay.new()
	_play.port = PORT
	_play.bot = true
	_play.leave_when_over = false
	root.add_child(_play)


func _process(_delta: float) -> bool:
	if _done:
		return true
	var now: int = Time.get_ticks_msec()
	if _play.game == null:
		if not _play.result.is_empty():
			_fail("no match: %s" % _play.result)
		elif now - _begun_at > 60000:
			_fail("no match after a minute")
		return _done
	if _started_at < 0:
		_started_at = now
	if not _play.result.is_empty():
		_fail("the match ended early: %s" % _play.result)
		return true
	_watch()
	if _out != "" and now - _started_at > 4000 + _shots * 4000:
		_shots += 1
		root.get_texture().get_image().save_png("%s/net_view_%02d_%s.png" % [_out, _shots, _play.game.play_controller.state_machine.current_name()])
	if now - _started_at > _seconds * 1000.0:
		_judge((now - _started_at) / 1000.0)
	return _done


func _watch() -> void:
	var game: Game = _play.game
	var view: NetView = _play.view
	if view == null or view.shown == 0:
		return
	var pc: PlayController = game.play_controller
	_states_seen[pc.state_machine.current_name()] = true
	if _first_places.is_empty():
		for player: Player in pc.players:
			_first_places.append(player.position)
		_first_ball = game.ball.position
		_first_clock = game.clock
	_moved = 0
	for i: int in pc.players.size():
		if pc.players[i].position.distance_to(_first_places[i]) > 3.0:
			_moved += 1
	_ball_moved = maxf(_ball_moved, game.ball.position.distance_to(_first_ball))
	var mine: Player = game.human.controlled
	if mine != null and mine.control_ring.visible and mine.team == game.human.team:
		_own_seen = true


func _judge(seconds: float) -> void:
	var game: Game = _play.game
	var view: NetView = _play.view
	var names: Array = _states_seen.keys()
	print("this end: %.0f frames a second, states received %d, refused %d" % [Engine.get_frames_per_second(), view.received, view.refused])
	print("states shown %d in %.0f s (%.0f a second), held %d, stepped over %d; things done once %d" % [view.shown, seconds, view.shown / seconds, view.held, view.skipped, view.replayed])
	print("states of the match seen: %s; players moved %d of %d; ball moved %.1f yd; clock %.1f -> %.1f" % [names, _moved, game.play_controller.players.size(), _ball_moved, _first_clock, game.clock])
	# Saving a picture holds this program up for a moment each time.
	if view.shown < seconds * (20.0 if _out != "" else 45.0):
		_failures.append("only %d states were shown in %.0f seconds" % [view.shown, seconds])
	if not _states_seen.has(&"Live") or not _states_seen.has(&"PreSnap"):
		_failures.append("the match here never got to the line and a live ball: %s" % [names])
	if _moved < 8:
		_failures.append("only %d players moved" % _moved)
	if _ball_moved < 5.0:
		_failures.append("the ball moved %.1f yd" % _ball_moved)
	if view.refused > 0:
		_failures.append("%d states were not what a state should be" % view.refused)
	if view.replayed <= 0:
		_failures.append("nothing that happens once was done here")
	if not _own_seen:
		_failures.append("the person's own player was never marked as theirs")
	if game.clock >= _first_clock:
		_failures.append("the clock did not run")
	_end()


func _fail(text: String) -> void:
	_failures.append(text)
	_end()


func _end() -> void:
	_done = true
	for pid: int in [_bot_pid, _server_pid]:
		if pid > 0:
			OS.kill(pid)
	if _failures.is_empty():
		print("NET VIEW CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("NET VIEW CHECK FAILED: %s" % failure)
		quit(1)
