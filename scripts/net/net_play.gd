class_name NetPlay
extends Node
## An online match on a person's machine: joins the server, and once both
## people are in makes the match here (a Game that decides nothing, see
## Game.NetMode.CLIENT) with a NetView to draw it. When it is over it says so
## and goes back to the main menu.
##
## Until there is a way in from the main menu, run it as scenes/online_dev.tscn:
##   godot --path . res://scenes/online_dev.tscn -- join=127.0.0.1 [port=24642] [team=<n>] [bot]
##         [lag=<ms>] [nopredict]
## `bot` plays with random buttons: someone to play against on one machine.
## `lag` makes the line that much slower each way (lag=50 is 100 ms more there
## and back); `nopredict` draws the person's own player where the server has
## him, to compare.

## The match is over, or never came about: NetProtocol's END body, or
## { "reason": "rejected: ..." | "lost" | "no line" }.
signal over(result: Dictionary)

const MENU: String = "res://scenes/main_menu.tscn"
## Seconds the result stays up before the main menu.
const RESULT_TIME: float = 5.0

var address: String = "127.0.0.1"
var port: int = NetProtocol.DEFAULT_PORT
var team_pick: int = -1
## Random buttons in place of the gamepad.
var bot: bool = false
## For trying things out: milliseconds added to the line each way, and the
## person's own player drawn where the server has him (no running ahead).
var lag_ms: int = 0
var predict: bool = true
## Back to the main menu when it is over (quits, for a bot). Off in the tests.
var leave_when_over: bool = true

var client: NetClient
var game: Game
var view: NetView
var result: Dictionary = {}

var _bot_pad: PadInput
## The pause menu is open here (or the gamepad is gone): the server was asked
## to hold the match.
var _wants_pause: bool = false
var _notice: PanelContainer
var _notice_text: Label
var _scene: PackedScene
var _bot_held: Dictionary[StringName, bool] = {}


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("join="):
			address = arg.trim_prefix("join=")
		elif arg.begins_with("port="):
			port = int(arg.trim_prefix("port="))
		elif arg.begins_with("team="):
			team_pick = int(arg.trim_prefix("team="))
		elif arg == "bot":
			bot = true
		elif arg.begins_with("lag="):
			lag_ms = int(arg.trim_prefix("lag="))
		elif arg == "nopredict":
			predict = false
	# Loaded before the server is looked for: the other person does not wait for it.
	_scene = load("res://scenes/main.tscn")
	client = NetClient.new()
	client.team_pick = team_pick
	client.lag_ms = lag_ms
	client.auto_ready = false
	if bot:
		_bot_pad = PadInput.new()
		_bot_pad.remote = true
		client.pad = _bot_pad
		# Before the client's own start of the tick: its buttons are there to send.
		get_tree().physics_frame.connect(_mash)
	add_child(client)
	client.started.connect(_on_started)
	client.state.connect(func(tick: int, state: Variant) -> void: view.add_state(tick, state))
	client.events.connect(func(tick: int, notes: Array) -> void: view.add_events(tick, notes))
	client.stats.connect(func(book: Array) -> void:
		if game != null:
			game.stat_book.net_unpack(book))
	client.ended.connect(_finish)
	client.rejected.connect(func(reason: String) -> void: _finish({"reason": "rejected: %s" % reason}))
	client.lost.connect(func() -> void: _finish({"reason": "lost"}))
	if not client.join(address, port):
		_finish({"reason": "no line"})
	else:
		print("NetPlay: looking for the server at %s:%d" % [address, port])


func _exit_tree() -> void:
	if Game.net_mode == Game.NetMode.CLIENT:
		Game.net_mode = Game.NetMode.OFFLINE
		Game.human_side = -1
		Game.team_picks = PackedInt32Array([-1, -1])


func _physics_process(_delta: float) -> void:
	# The stick is sent as a move on the field as this person's camera has it.
	if game != null and game.camera_rig != null:
		client.view = game.camera_rig.basis
	if view != null and view.shown == NetSocket.SETTLE_TICKS:
		client.be_strict()
	if game != null and not bot and result.is_empty():
		_update_pause()


## With the pause menu open here, or the gamepad gone, the server is asked to
## hold the match and no buttons are sent; and the notice says how a pause
## stands (see NetServer).
func _update_pause() -> void:
	var wants: bool = game.hud.pause_menu.holds_pause() or Controllers.of(get_tree()).blocked()
	if wants != _wants_pause:
		_wants_pause = wants
		client.want_pause(wants)
	client.muted = wants
	var pause: PackedInt32Array = game.net_pause
	var me: int = clampi(client.seat, 0, 1)
	var text: String = ""
	if pause.size() == 6:
		if pause[0] == 0:
			if wants and pause[4 + me] <= 0 and view != null and view.shown > 0:
				text = "NO PAUSE TIME LEFT  -  THE GAME IS ON"
		elif pause[1] > 0:
			text = "GET READY"
		elif wants:
			text = "PAUSED  -  %s of your pause time left" % _minutes(pause[4 + me])
		elif pause[2 + (1 - me)] != 0:
			text = "THE OTHER PLAYER PAUSED  -  back on in %s at the latest" % _minutes(pause[4 + (1 - me)])
	if _notice == null:
		_build_notice()
	_notice_text.text = text
	_notice.visible = text != ""


func _minutes(seconds: int) -> String:
	@warning_ignore("integer_division")
	return "%d:%02d" % [seconds / 60, seconds % 60]


## A line at the top of the screen, over the pause menu too.
func _build_notice() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_notice = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	style.set_corner_radius_all(6)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_notice.add_theme_stylebox_override(&"panel", style)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.offset_top = 18.0
	_notice_text = Label.new()
	_notice_text.add_theme_font_size_override(&"font_size", 24)
	_notice_text.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.1))
	_notice.add_child(_notice_text)
	_notice.visible = false


func _on_started(home_pick: int, away_pick: int) -> void:
	Game.net_mode = Game.NetMode.CLIENT
	Game.two_players = false
	Game.human_side = client.seat
	Game.show_intro = false
	Game.season_match = false
	Game.team_picks = PackedInt32Array([home_pick, away_pick])
	game = _scene.instantiate() as Game
	add_child(game)
	view = NetView.new()
	add_child(view)
	view.setup(game, client.seat, client)
	view.predict = predict
	client.loaded()
	print("NetPlay: match on, seat %d" % client.seat)


func _finish(p_result: Dictionary) -> void:
	if not result.is_empty():
		return
	result = p_result
	print("NetPlay: over, %s" % result)
	over.emit(result)
	if game != null and not bot:
		game.hud.show_banner(_headline(), _line())
	if not leave_when_over:
		return
	await get_tree().create_timer(0.5 if bot or game == null else RESULT_TIME, true, false, true).timeout
	if bot:
		get_tree().quit()
	elif is_inside_tree():
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU)


func _headline() -> String:
	var winner: int = result.get("winner", -1)
	if result.get("reason") == "lost":
		return "CONNECTION LOST"
	if winner < 0:
		return "FINAL"
	return "YOU WIN!" if winner == client.seat else "YOU LOSE"


func _line() -> String:
	var score: Array = result.get("score", [])
	var text: String = ""
	if score.size() == 2:
		text = "%s %d  -  %d %s" % [game.home.short_name, score[0], score[1], game.away.short_name]
	if result.get("reason") == "left":
		text = "Opponent left the match.   " + text
	return text


## Random presses and releases on every button, as the smoke test's monkey.
func _mash() -> void:
	for plain: StringName in PadInput.plain_actions():
		if randf() < 0.12:
			if _bot_held.has(plain):
				_bot_held.erase(plain)
			else:
				_bot_held[plain] = true
	var frame: Dictionary[StringName, Vector2] = {}
	for plain: StringName in _bot_held:
		frame[plain] = Vector2.ONE
	_bot_pad.push(frame)
