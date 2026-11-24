extends SceneTree
## Headless check of two people playing each other on two gamepads, from the
## team select into a match:
##  - a second gamepad joins on the team select, cannot go under player one's
##    team, changes the team on its own side, leaves with (B), and the match
##    only starts once both are under a team;
##  - in the match each has a team, their own buttons, a stamina bar and a ring
##    in their team's colour under their player;
##  - both pick a play at once, each on their own panel, and the teams line up
##    only when both are in;
##  - at the line each can draw their play and open their own audible menu, and
##    after the snap each stick moves only its own player;
##  - a rumble goes to the pad of the person it happened to;
##  - either pauses, and a gamepad pulled out stops the game with a notice
##    until one is back on that seat and presses (A).
## No gamepad is needed: the presses are made up, as are the pads coming and going.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/versus_check.gd
## With a window (no --headless) and `-- out=<dir>` it saves PNGs of the team
## select, the two play-select panels, the line of scrimmage and the notice.

const WAIT_FRAMES: int = 480

var _menu: MainMenu
var _game: Game
var _pc: PlayController
var _controllers: Controllers
## What is still to do: frames to wait after it, and the thing itself.
var _steps: Array[Array] = []
var _wait: int = 20
var _waited: int = 0
var _kept: Dictionary = {}
var _out: String = ""
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
	Season.save_path = "user://versus_check_season.cfg"
	Season.clear()
	var scene: PackedScene = load("res://scenes/main_menu.tscn")
	_menu = scene.instantiate() as MainMenu
	root.add_child(_menu)
	current_scene = _menu
	_controllers = Controllers.of(self)
	_plan_team_select()
	process_frame.connect(_tick)


func _tick() -> void:
	if _wait > 0:
		_wait -= 1
		return
	if _steps.is_empty():
		_finish()
		return
	var step: Array = _steps.pop_front()
	_wait = step[0]
	(step[1] as Callable).call()


func _do(wait: int, what: Callable) -> void:
	_steps.append([wait, what])


# --- The team select -----------------------------------------------------------------

func _plan_team_select() -> void:
	_do(8, func() -> void: _menu.start_button.pressed.emit())
	_do(8, func() -> void: _button(0, JOY_BUTTON_DPAD_RIGHT))
	_do(8, func() -> void:
		var select: TeamSelect = _menu.team_select
		_expect(select != null and select.visible, "EXHIBITION did not bring the team select up")
		_expect(select.side == 1, "player one is at %d, not under the right team" % select.side)
		_expect(not select.joined, "there is a player two before a second gamepad pressed anything")
		_expect(_controllers.seat_of(0) == 0, "the first gamepad is not player one's")
		_button(1, JOY_BUTTON_A))
	_do(8, func() -> void:
		var select: TeamSelect = _menu.team_select
		_expect(select.joined and select.side2 == 0, "the second gamepad's first button did not bring player two in, in the middle")
		_expect(_controllers.seat_of(1) == 1, "the second gamepad is not player two's")
		# Player two has no team yet: no match.
		_button(0, JOY_BUTTON_A))
	_do(8, func() -> void:
		_expect(current_scene == _menu and _menu.team_select.visible and not _menu.team_select.versus, "the match started with player two in the middle")
		_button(1, JOY_BUTTON_DPAD_RIGHT))
	_do(8, func() -> void:
		_expect(_menu.team_select.side2 == 0, "player two went under the team player one has")
		_button(1, JOY_BUTTON_DPAD_LEFT))
	_do(8, func() -> void:
		var select: TeamSelect = _menu.team_select
		_expect(select.side2 == -1, "player two is at %d, not under the left team" % select.side2)
		_kept["picks"] = select.picks.duplicate()
		_button(1, JOY_BUTTON_DPAD_DOWN))
	_do(8, func() -> void:
		var select: TeamSelect = _menu.team_select
		var before: Array = _kept["picks"]
		_expect(select.picks[0] != before[0] and select.picks[1] == before[1], "player two's down did not change the left team alone")
		_button(1, JOY_BUTTON_B))
	_do(8, func() -> void:
		var select: TeamSelect = _menu.team_select
		_expect(not select.joined and select.visible, "player two's (B) did not take them out and leave the screen up")
		_expect(_controllers.seat_of(1) < 0, "the gamepad that left is still player two's")
		_button(1, JOY_BUTTON_X))
	_do(8, func() -> void:
		_expect(_menu.team_select.joined, "the gamepad that left could not come back in")
		_button(1, JOY_BUTTON_DPAD_LEFT))
	_do(8, func() -> void:
		_expect(_menu.team_select.side2 == -1, "player two did not get back under the left team")
		_save("team_select")
		_button(0, JOY_BUTTON_A))
	_do(0, func() -> void:
		_expect(Game.two_players, "(A) with both under a team did not start a match for two")
		_expect(Game.human_side == 1, "player one's side is %d, not the right team's" % Game.human_side)
		_wait_for_match())


func _wait_for_match() -> void:
	var loaded: bool = current_scene != null and current_scene.scene_file_path == MainMenu.GAME_SCENE
	if loaded and (current_scene as Game).is_node_ready() and (current_scene as Game).offense != null:
		_game = current_scene as Game
		_pc = _game.play_controller
		_plan_match()
		return
	_waited += 1
	if _waited > WAIT_FRAMES:
		_failures.append("the team select did not load the match")
		return
	_steps.push_front([0, _wait_for_match])


# --- The match -----------------------------------------------------------------------

func _plan_match() -> void:
	_do(30, func() -> void:
		_expect(_game.humans.size() == 2, "%d people are playing, not 2" % _game.humans.size())
		if _game.humans.size() != 2:
			_steps.clear()
			return
		var one: HumanController = _game.humans[0]
		var two: HumanController = _game.humans[1]
		_expect(one.team == _game.away and two.team == _game.home, "player one is not the away team and player two the home team")
		_expect(_game.home.human == two and _game.away.human == one, "the teams do not know who plays them")
		_expect(one.pad.prefix == "p1_" and two.pad.prefix == "p2_", "the two do not have their own buttons")
		_expect(_game.screen_slot(two) == 0 and _game.screen_slot(one) == 1, "the home team's person does not have the left half")
		var bars: Array = _game.hud.get(&"_turbo_bars")
		_expect(bars.size() == 2, "there are %d stamina bars, not 2" % bars.size())
		# The home team with the ball, straight to the cards.
		_game.kickoff_to = null
		_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 30.0))
		_pc.state_machine.transition(&"PlaySelect"))
	_do(4, func() -> void:
		_expect(_state() == &"PlaySelect", "the game is in '%s', not at the cards" % _state())
		var panels: Array = _game.hud.get(&"_play_panels")
		_expect(panels.size() == 2 and (panels[0].root as Control).visible and (panels[1].root as Control).visible, "there are not two play-select panels up")
		if panels.size() == 2:
			_expect((panels[0].root as Control).anchor_right <= 0.5 and (panels[1].root as Control).anchor_left >= 0.5, "the two panels are not on a half each")
		Input.action_press(&"p2_move_right"))
	_do(2, func() -> void: Input.action_release(&"p2_move_right"))
	_do(4, func() -> void:
		_expect(_picker(1).cursor == 1, "player two's stick did not move their cursor (it is at %d)" % _picker(1).cursor)
		_expect(_picker(0).cursor == 0, "player two's stick moved player one's cursor")
		_expect(_picker(1).on_offense and not _picker(0).on_offense, "the two are not picking for their own side of the ball")
		_save("play_select")
		Input.action_press(&"p2_confirm"))
	_do(4, func() -> void: Input.action_release(&"p2_confirm"))
	_do(0, func() -> void:
		_expect(_state() == &"PlaySelect", "one pick was enough to leave the cards")
		_expect(_picker(1).choice == _picker(1).plays[1], "player two's (A) did not pick the play under their cursor")
		_expect(_picker(0).choice == null, "player two's (A) picked for player one")
		_save("play_select_ready")
		_kept["offense"] = _picker(1).choice
		_kept["defense"] = _picker(0).plays[0]
		Input.action_press(&"p1_confirm"))
	_do(4, func() -> void: Input.action_release(&"p1_confirm"))
	# The teams have to be set before a play can be changed.
	_do(ceili(_game.tuning.pre_snap_delay * 60.0) + 20, func() -> void:
		_expect(_state() == &"PreSnap", "both picked and the game is in '%s'" % _state())
		_expect(_pc.off_play == _kept["offense"], "the offense is not in the play player two picked")
		_expect(_pc.def_play == _kept["defense"], "the defense is not in the play player one picked")
		# Each has their buttons on their own half, and neither play is named.
		var lines: Array = _game.hud.get(&"_line_hints")
		_expect(lines.size() == 2, "there are %d lines of buttons at the line, not 2" % lines.size())
		for line: Label in lines:
			_expect(line.visible and line.text != "", "a line of buttons at the line is not up")
			var box: Rect2 = line.get_global_rect()
			_expect(box.size.x > 100.0 and box.size.y < 120.0 and root.get_visible_rect().encloses(box), "a line of buttons is not in its place on the screen: %s" % box)
			_expect(not line.text.contains(_pc.off_play.play_name) and not line.text.contains(_pc.def_play.play_name), "a line of buttons names the play")
		if lines.size() == 2:
			_expect((lines[0] as Label).get_global_rect().end.x <= (lines[1] as Label).get_global_rect().position.x, "the two lines of buttons are not on a half each")
		_expect(not _game.hud.sub_banner.visible, "the banner with the play's name is up with two at the line")
		_save("line"))
	_do(0, func() -> void:
		var one: HumanController = _game.humans[0]
		var two: HumanController = _game.humans[1]
		_expect(two.controlled == _pc.qb, "player two does not have their quarterback")
		_expect(one.controlled != null and one.controlled.team == _game.away, "player one does not have a defender of their own")
		for person: HumanController in [one, two]:
			if person.controlled == null:
				continue
			var ring: MeshInstance3D = person.controlled.control_ring
			var paint: StandardMaterial3D = ring.get_surface_override_material(0) as StandardMaterial3D
			_expect(ring.visible and paint != null and paint.albedo_color.is_equal_approx(person.team.marker_color()), "the ring under %s's player is not in their colour" % person.team.short_name)
		_expect(not _game.home.marker_color().is_equal_approx(_game.away.marker_color()), "both teams have the same colour: the rings cannot be told apart")
		# Both hold the left trigger and push up: both plays are on the field.
		for action: StringName in [&"p1_reveal_play", &"p1_move_up", &"p2_reveal_play", &"p2_move_up"]:
			Input.action_press(action))
	_do(4, func() -> void: pass)
	_do(4, func() -> void:
		_expect(_game.play_art.get(&"_offense") == _pc.off_play, "player two's play is not drawn on the field")
		_expect(_game.play_art.get(&"_defense") == _pc.def_play, "player one's play is not drawn on the field")
		_save("line_both_plays")
		for action: StringName in [&"p1_reveal_play", &"p1_move_up", &"p2_reveal_play", &"p2_move_up"]:
			Input.action_release(action))
	_do(4, func() -> void:
		_expect(_game.play_art.shown == null, "the plays are still drawn with the triggers let go")
		Input.action_press(&"p1_audible"))
	_do(4, func() -> void:
		Input.action_release(&"p1_audible")
		var menus: Array = _game.hud.get(&"_audibles")
		_expect(menus[1] != null and (menus[1] as Control).visible, "player one's (X) did not open their audible menu, on the right")
		_expect(menus[0] == null or not (menus[0] as Control).visible, "player one's (X) opened player two's audible menu")
		_save("line_audible")
		Input.action_press(&"p1_back"))
	_do(4, func() -> void:
		Input.action_release(&"p1_back")
		_expect(not _game.hud.audible_shown(), "player one's (B) did not close their audible menu")
		_kept["defender"] = _game.humans[0].controlled
		Input.action_press(&"p1_switch_player"))
	_do(4, func() -> void:
		Input.action_release(&"p1_switch_player")
		_expect(_game.humans[0].controlled != _kept["defender"], "player one's (B) did not pick another defender")
		_expect(_game.humans[1].controlled == _pc.qb, "player one's (B) took player two's quarterback away")
		# Player one's (A) is not a snap: the ball is the other team's.
		Input.action_press(&"p1_confirm"))
	_do(4, func() -> void:
		Input.action_release(&"p1_confirm")
		_expect(_state() == &"PreSnap", "the defense's (A) snapped the ball")
		Input.action_press(&"p2_confirm"))
	_do(12, func() -> void:
		Input.action_release(&"p2_confirm")
		_expect(_state() == &"Live", "the offense's (A) did not snap the ball (the game is in '%s')" % _state())
		_kept["qb_at"] = _pc.qb.position
		_kept["mine"] = _game.humans[0].controlled
		_kept["mine_at"] = _game.humans[0].controlled.position
		Input.action_press(&"p1_move_right", 1.0))
	_do(0, func() -> void:
		Input.action_release(&"p1_move_right")
		var mine: Player = _kept["mine"]
		var moved: float = (mine.position - (_kept["mine_at"] as Vector3)).length()
		_expect(_game.humans[0].controlled != mine or moved > 0.05, "player one's stick did not move their player")
		_check_rumble()
		_check_pause())


func _check_rumble() -> void:
	var rumble: Rumble = _game.rumble
	var one: HumanController = _game.humans[0]
	var two: HumanController = _game.humans[1]
	if one.controlled == null or two.controlled == null:
		_failures.append("somebody has no player to rumble for")
		return
	rumble.stop()
	rumble.play_mine(&"tackle", two.controlled)
	rumble.advance(0.0)
	_expect(rumble.level(1) != Vector2.ZERO, "player two's tackle did not shake player two's pad")
	_expect(rumble.level(0) == Vector2.ZERO, "player two's tackle shook player one's pad")
	rumble.stop()
	rumble.play_team(&"touchdown", one.team)
	rumble.advance(0.0)
	_expect(rumble.level(0) != Vector2.ZERO and rumble.level(1) == Vector2.ZERO, "a touchdown for player one's team did not shake their pad alone")
	rumble.stop()
	rumble.play(&"kick")
	rumble.advance(0.0)
	_expect(rumble.level(0) != Vector2.ZERO and rumble.level(1) != Vector2.ZERO, "the kick did not shake both pads")
	rumble.stop()


# --- Pausing, and a pad going away ---------------------------------------------------

func _check_pause() -> void:
	_do(6, func() -> void: _action(&"pause", true))
	_do(6, func() -> void:
		_action(&"pause", false)
		_expect(_game.hud.pause_menu.is_open() and paused, "Start did not pause the game"))
	_do(6, func() -> void: _action(&"pause", true))
	_do(6, func() -> void: _action(&"pause", false))
	_do(4, func() -> void:
		_expect(not _game.hud.pause_menu.is_open() and not paused, "Start did not start the game again")
		# The second gamepad is a real one, and it is pulled out.
		_controllers.joy_changed(1, true)
		_controllers.joy_changed(1, false))
	_do(6, func() -> void:
		_expect(paused, "a gamepad was pulled out and the game went on")
		_expect(_controllers.blocked(), "the game is not waiting for the gamepad")
		_expect(_controllers.notice().contains("PLAYER 2") and _controllers.notice().contains("DISCONNECTED"), "the notice reads '%s'" % _controllers.notice())
		_save("notice")
		# The other one can still get to the pause menu, and out of it.
		_action(&"pause", true))
	_do(6, func() -> void:
		_action(&"pause", false)
		_expect(_game.hud.pause_menu.is_open(), "Start did not open the pause menu under the notice"))
	_do(6, func() -> void: _action(&"pause", true))
	_do(6, func() -> void: _action(&"pause", false))
	_do(4, func() -> void:
		_expect(not _game.hud.pause_menu.is_open() and paused, "closing the pause menu started the game with a gamepad still missing")
		# Another pad is plugged in: it is player two's now.
		_controllers.joy_changed(4, true))
	_do(6, func() -> void:
		_expect(_controllers.device_of(1) == 4, "the gamepad plugged in is not player two's")
		var bound: bool = false
		for event: InputEvent in InputMap.action_get_events(&"p2_confirm"):
			bound = bound or event.device == 4
		_expect(bound, "player two's buttons are not those of the new gamepad")
		_expect(paused and _controllers.notice().contains("CONNECTED") and not _controllers.notice().contains("DIS"), "the game did not wait for the new gamepad's (A) (the notice reads '%s')" % _controllers.notice())
		_button(4, JOY_BUTTON_A))
	_do(0, func() -> void:
		_expect(not paused and not _controllers.blocked() and _controllers.notice() == "", "the new gamepad's (A) did not start the game again"))


# --- Helpers -------------------------------------------------------------------------

func _state() -> StringName:
	return _pc.state_machine.current_name()


## The person at the cards who is player `seat` + 1.
func _picker(seat: int) -> Variant:
	var pickers: Array = _pc.state_machine.get_node(^"PlaySelect").get(&"_pickers")
	for picker: Variant in pickers:
		if picker.human == _game.humans[seat]:
			return picker
	_failures.append("player %d is not at the cards" % (seat + 1))
	return pickers[0]


func _save(shot: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_texture().get_image().save_png(_out.path_join("versus_%s.png" % shot))


## A button of gamepad `device` pressed and let go.
func _button(device: int, button: JoyButton) -> void:
	for down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)


## An action as an event, which is what code that polls in _process sees.
func _action(action: StringName, down: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = down
	Input.parse_input_event(event)


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message):
		_failures.append(message)


func _finish() -> void:
	process_frame.disconnect(_tick)
	paused = false
	Game.human_side = -1
	Game.two_players = false
	Game.team_picks = PackedInt32Array([-1, -1])
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("versus_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
