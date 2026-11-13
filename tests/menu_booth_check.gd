extends SceneTree
## Check of Jim and Tony on the main menu (MenuBooth, the `menu_*` files): every
## moment has its lines and no set is broken; left alone, the menu gets its
## welcome; running the highlight over the buttons says nothing; resting it on
## EXIT gets a line every time and never the same one twice running; a press
## gets its line; the two never talk at once; and a second visit gets the
## welcome back.
## With `quit` it presses EXIT instead and passes if the game then quits by
## itself (exit code 0; 1 if it is still there ten seconds of game time later).
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/menu_booth_check.gd [-- quit]

const MOMENTS: Array[StringName] = [
	&"welcome", &"welcome_back", &"start", &"options", &"exit", &"start_pick",
	&"options_pick", &"exit_pick", &"team", &"side", &"back", &"go", &"idle",
]
## Times the highlight is rested on EXIT.
const EXIT_VISITS: int = 16
## Frames (60 a second) to let a dwell or a rest run out.
const WELCOME_FRAMES: int = 110
const DWELL_FRAMES: int = 20
const REST_FRAMES: int = 100

var _menu: MainMenu
var _frame: int = 0
var _at: int = 0
var _step: int = 0
var _visit: int = 0
var _quit_mode: bool = false
var _said_before: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_quit_mode = OS.get_cmdline_user_args().has("quit")
	_open_menu()
	process_frame.connect(_tick)


func _open_menu() -> void:
	var scene: PackedScene = load("res://scenes/main_menu.tscn")
	_menu = scene.instantiate() as MainMenu
	root.add_child(_menu)
	current_scene = _menu
	_at = _frame


func _tick() -> void:
	_frame += 1
	var booth: MenuBooth = _menu.booth
	if booth != null and booth._jim.playing and booth._tony.playing:
		_fail("Jim and Tony are talking at once")
	var waited: int = _frame - _at
	match _step:
		0:
			if waited < WELCOME_FRAMES:
				return
			_check_lines(booth)
			_expect_last(booth, &"welcome", "left alone on the menu")
			if _quit_mode:
				print("pressing EXIT")
				_menu.exit_button.pressed.emit()
				_next(10)
				return
			# Up and down the buttons, one a frame: nobody has time to say a thing.
			_said_before = booth.history.size()
			_next(1)
		1, 2, 3, 4:
			var buttons: Array[Button] = [_menu.exit_button, _menu.options_button, _menu.exit_button, _menu.start_button]
			buttons[_step - 1].grab_focus()
			_next(_step + 1)
		5:
			if waited < DWELL_FRAMES * 3:
				return
			for line: Array in booth.history.slice(_said_before):
				if line[0] == &"exit":
					_fail("running the highlight past EXIT got a line")
			_next(6)
		6:
			# Rested on EXIT, then away for long enough to be asked again.
			_menu.exit_button.grab_focus()
			_said_before = _exit_lines(booth).size()
			_next(7)
		7:
			if waited < DWELL_FRAMES:
				return
			var exits: Array[int] = _exit_lines(booth)
			if exits.size() != _said_before + 1:
				_fail("resting on EXIT (visit %d) got %d lines" % [_visit + 1, exits.size() - _said_before])
			elif exits.size() >= 2 and exits[-1] == exits[-2]:
				_fail("the same EXIT line twice running")
			_menu.start_button.grab_focus()
			_next(8)
		8:
			if waited < REST_FRAMES:
				return
			_visit += 1
			_next(6 if _visit < EXIT_VISITS else 9)
		9:
			var heard: Dictionary[int, bool] = {}
			for index: int in _exit_lines(booth):
				heard[index] = true
			print("EXIT lines in the order heard: %s" % str(_exit_lines(booth)))
			if heard.size() != booth.line_count(&"exit"):
				_fail("%d visits to EXIT got %d of its %d lines" % [EXIT_VISITS, heard.size(), booth.line_count(&"exit")])
			_menu.options_button.pressed.emit()
			_expect_last(booth, &"options_pick", "after OPTIONS")
			if current_scene != _menu or _menu.team_select != null:
				_fail("OPTIONS left the menu")
			# A second visit to the menu.
			_menu.free()
			_open_menu()
			_next(10)
		10:
			if _quit_mode:
				if waited > 600:
					print("FAIL: EXIT did not quit the game")
					quit(1)
				return
			if waited < WELCOME_FRAMES:
				return
			_expect_last(booth, &"welcome_back", "on the second visit")
			_report(booth)


## Which of EXIT's lines were said, in order.
func _exit_lines(booth: MenuBooth) -> Array[int]:
	var said: Array[int] = []
	for line: Array in booth.history:
		if line[0] == &"exit":
			said.append(line[1])
	return said


func _next(step: int) -> void:
	_step = step
	_at = _frame


func _check_lines(booth: MenuBooth) -> void:
	if booth == null:
		_fail("the menu has no booth")
		return
	for moment: StringName in MOMENTS:
		if not booth.has(moment):
			_fail("no lines for '%s'" % moment)
	for moment: StringName in booth.moments():
		if not MOMENTS.has(moment):
			_fail("lines for '%s', which nothing asks for" % moment)
	for line: String in booth.broken:
		_fail("'%s' has a part missing or a bad name" % line)


func _expect_last(booth: MenuBooth, moment: StringName, when: String) -> void:
	if booth.history.is_empty() or booth.history.back()[0] != moment:
		_fail("no '%s' line %s (said: %s)" % [moment, when, str(booth.history)])


func _fail(text: String) -> void:
	if not _failures.has(text):
		_failures.append(text)


func _report(booth: MenuBooth) -> void:
	process_frame.disconnect(_tick)
	var counts: PackedStringArray = PackedStringArray()
	for moment: StringName in MOMENTS:
		counts.append("%s %d" % [moment, booth.line_count(moment)])
	print("Lines: %s" % ", ".join(counts))
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("menu booth check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
