extends SceneTree
## Check of the main menu: the three buttons are there with Start chosen,
## Options leaves the menu up and Start loads the match. With `out=<file>` (and
## a window, so no --headless) it saves a picture of the menu first.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/menu_check.gd

const WAIT_FRAMES: int = 120

var _menu: MainMenu
var _frame: int = 0
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
	if _frame < 20:
		return
	if _pressed_at < 0:
		if _out != "":
			root.get_texture().get_image().save_png(_out)
			print("saved %s" % _out)
		for button: Button in [_menu.start_button, _menu.options_button, _menu.exit_button]:
			if button == null or not button.is_visible_in_tree():
				_failures.append("a button is missing")
		if not _menu.start_button.has_focus():
			_failures.append("START GAME does not have the focus")
		_menu.options_button.pressed.emit()
		if current_scene != _menu:
			_failures.append("OPTIONS left the menu")
		# The real thing: (A) on the gamepad with START GAME in focus.
		var press: InputEventJoypadButton = InputEventJoypadButton.new()
		press.button_index = JOY_BUTTON_A
		press.pressed = true
		Input.parse_input_event(press)
		_pressed_at = _frame
		return
	var loaded: bool = current_scene != null and current_scene.scene_file_path == MainMenu.GAME_SCENE
	if not loaded and _frame - _pressed_at < WAIT_FRAMES:
		return
	if not loaded:
		_failures.append("START GAME did not load %s" % MainMenu.GAME_SCENE)
	process_frame.disconnect(_tick)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("menu check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
