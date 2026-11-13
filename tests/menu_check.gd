extends SceneTree
## Check of the main menu and the team select behind START GAME: the three
## buttons are there with Start chosen, Options leaves the menu up, Start brings
## up the team select, (B) goes back, the D-pad slides the controller from side
## to side, up and down change the team on the controller's side without ever
## showing the other side's, and (A) on a team loads the match with the person
## on that team and the two teams picked.
## With `out=<file>` (and a window, so no --headless) it saves a picture of the
## menu and one of the team select (`<file>_select.png`).
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/menu_check.gd

const WAIT_FRAMES: int = 120
## Frames between one press and the look at what it did.
const STEP_FRAMES: int = 12

var _menu: MainMenu
var _frame: int = 0
var _step: int = 0
var _pressed_at: int = -1
var _out: String = ""
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
	var scene: PackedScene = load("res://scenes/main_menu.tscn")
	_menu = scene.instantiate() as MainMenu
	root.add_child(_menu)
	current_scene = _menu
	process_frame.connect(_tick)


func _tick() -> void:
	_frame += 1
	if _pressed_at >= 0:
		_wait_for_match()
		return
	if _frame < 20 or _frame % STEP_FRAMES != 0:
		return
	_step += 1
	match _step:
		1:
			_save("")
			for button: Button in [_menu.start_button, _menu.options_button, _menu.exit_button]:
				if button == null or not button.is_visible_in_tree():
					_failures.append("a button is missing")
			if not _menu.start_button.has_focus():
				_failures.append("START GAME does not have the focus")
			_menu.options_button.pressed.emit()
			if current_scene != _menu or _menu.team_select != null:
				_failures.append("OPTIONS left the menu")
			# The real thing: (A) on the gamepad with START GAME in focus.
			_press(JOY_BUTTON_A)
		2:
			_expect_select(0, "after START GAME")
			_expect_ratings("after START GAME")
			_expect_better_defense("GRAPES", "BERRIES")
			if _menu.start_button.is_visible_in_tree():
				_failures.append("the buttons are still up behind the team select")
			_press(JOY_BUTTON_A)
		3:
			_expect_select(0, "after (A) in the middle")
			_press(JOY_BUTTON_B)
		4:
			if _menu.team_select.visible:
				_failures.append("(B) did not close the team select")
			if not _menu.start_button.has_focus():
				_failures.append("START GAME does not have the focus after (B)")
			_press(JOY_BUTTON_A)
		5:
			_expect_select(0, "opened a second time")
			_press(JOY_BUTTON_DPAD_RIGHT)
		6:
			_expect_select(1, "after right")
			_press(JOY_BUTTON_DPAD_LEFT)
		7:
			_expect_select(0, "after right, left")
			_press(JOY_BUTTON_DPAD_LEFT)
		8:
			_expect_select(-1, "after left from the middle")
			_press(JOY_BUTTON_DPAD_LEFT)
		9:
			_expect_select(-1, "after left at the left end")
			_press(JOY_BUTTON_DPAD_RIGHT)
		10:
			_press(JOY_BUTTON_DPAD_RIGHT)
		11:
			_expect_select(1, "after right twice from the left")
			_expect_picks(0, 1, "before any change")
			_press(JOY_BUTTON_DPAD_DOWN)
		12:
			_expect_picks(0, 2, "after down on the right")
			_press(JOY_BUTTON_DPAD_UP)
		13:
			_expect_picks(0, 1, "after down, up on the right")
			# Up from the second team would be the first, which the left has.
			_press(JOY_BUTTON_DPAD_UP)
		14:
			_expect_picks(0, 3, "after up past the left side's team")
			_press(JOY_BUTTON_DPAD_LEFT)
		15:
			# In the middle there is no team to change.
			_press(JOY_BUTTON_DPAD_DOWN)
		16:
			_expect_picks(0, 3, "after down in the middle")
			_press(JOY_BUTTON_DPAD_LEFT)
		17:
			_press(JOY_BUTTON_DPAD_DOWN)
		18:
			_expect_picks(1, 3, "after down on the left")
			_press(JOY_BUTTON_DPAD_DOWN)
		19:
			_expect_picks(2, 3, "after down twice on the left")
			_expect_ratings("after both sides changed team")
			_press(JOY_BUTTON_DPAD_RIGHT)
		20:
			_press(JOY_BUTTON_DPAD_RIGHT)
		21:
			_expect_select(1, "back on the right")
			_save("_select")
			_press(JOY_BUTTON_A)
			_pressed_at = _frame


func _wait_for_match() -> void:
	var loaded: bool = current_scene != null and current_scene.scene_file_path == MainMenu.GAME_SCENE
	if not loaded and _frame - _pressed_at < WAIT_FRAMES:
		return
	if not loaded:
		_failures.append("the team select did not load %s" % MainMenu.GAME_SCENE)
	else:
		var game: Game = current_scene as Game
		if Game.human_side != 1:
			_failures.append("Game.human_side is %d, not 1" % Game.human_side)
		if game.human.team != game.away:
			_failures.append("the person is not on the away team")
		var league: League = game.league
		if game.home.short_name != league.teams[2].short_name or game.away.short_name != league.teams[3].short_name:
			_failures.append("the match is %s against %s, not the teams picked" % [game.home.short_name, game.away.short_name])
		if game.away.roster != league.teams[3].roster:
			_failures.append("the away team does not have its own roster")
	Game.human_side = -1
	Game.team_picks = PackedInt32Array([-1, -1])
	process_frame.disconnect(_tick)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("menu check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


## The team select is up, the menu is still the scene and the controller is at `side`.
func _expect_select(side: int, when: String) -> void:
	var select: TeamSelect = _menu.team_select
	if current_scene != _menu:
		_failures.append("left the menu %s" % when)
	elif select == null or not select.visible:
		_failures.append("the team select is not up %s" % when)
	elif select.side != side:
		_failures.append("the controller is at %d, not %d, %s" % [select.side, side, when])


## The left side has the league's team `left` and the right side `right`.
func _expect_picks(left: int, right: int, when: String) -> void:
	var select: TeamSelect = _menu.team_select
	if select != null and (select.picks[0] != left or select.picks[1] != right):
		_failures.append("the teams are %d and %d, not %d and %d, %s" % [select.picks[0], select.picks[1], left, right, when])


## Each side shows four bars, at what the roster of its team comes to.
func _expect_ratings(when: String) -> void:
	var select: TeamSelect = _menu.team_select
	if select == null:
		return
	for i: int in 2:
		var team: TeamData = _menu.league.teams[select.picks[i]]
		var ratings: Array[Array] = team.roster.team_ratings()
		var bars: Array = select.rating_bars[i]
		if ratings.size() != 4 or bars.size() != 4:
			_failures.append("side %d has %d bars for %d ratings %s" % [i, bars.size(), ratings.size(), when])
			continue
		for row: int in 4:
			var bar: ProgressBar = bars[row]
			var value: int = ratings[row][1]
			if not bar.is_visible_in_tree() or roundi(bar.value) != value or value < 1 or value > 100:
				_failures.append("%s %s shows %d, not %d, %s" % [team.short_name, ratings[row][0], roundi(bar.value), value, when])


## The roster of `better` defends the pass and the run better than `worse`'s.
func _expect_better_defense(better: String, worse: String) -> void:
	var found: Dictionary[String, Array] = {}
	for team: TeamData in _menu.league.teams:
		found[team.short_name] = team.roster.team_ratings()
		print("%s: %s" % [team.short_name, found[team.short_name]])
	if not found.has(better) or not found.has(worse):
		_failures.append("no %s or no %s in the league" % [better, worse])
		return
	for row: int in [2, 3]:
		var high: int = found[better][row][1]
		var low: int = found[worse][row][1]
		if high <= low:
			_failures.append("%s %s is %d, no better than %s at %d" % [better, found[better][row][0], high, worse, low])


func _press(button: JoyButton) -> void:
	for down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)


func _save(suffix: String) -> void:
	if _out == "":
		return
	var path: String = "%s%s.png" % [_out.get_basename(), suffix]
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)
