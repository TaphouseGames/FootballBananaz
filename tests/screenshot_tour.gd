extends SceneTree
## Plays the first snap with simulated button presses and saves screenshots along
## the way. Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/screenshot_tour.gd -- out=<folder>

var _out_dir: String = "user://screenshots"
var _game: Game


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	root.add_child(_game)
	_tour()


func _tour() -> void:
	await _wait(0.6)
	await _shot("1_play_select")
	await _tap(&"move_down")
	await _tap(&"move_up")
	await _tap(&"pass_switch")
	await _wait(0.8)
	await _shot("2_pre_snap")
	await _tap(&"pass_switch")
	await _wait(0.3)
	await _tap(&"action")
	await _wait(0.5)
	await _shot("3_pocket")
	await _tap(&"pass_switch")
	await _wait(0.2)
	await _shot("4_ball_in_air")
	Input.action_press(&"move_right")
	Input.action_press(&"turbo")
	await _wait(1.2)
	await _shot("5_after_catch")
	await _wait(1.5)
	Input.action_release(&"move_right")
	Input.action_release(&"turbo")
	await _shot("6_later")
	print("state at end: %s   stats: %s" % [_game.play_controller.state_machine.current_name(), _game.stats])
	quit(0)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _wait(0.08)
	Input.action_release(action)
	await _wait(0.08)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(label + ".png")
	image.save_png(path)
	print("saved %s  (state %s)" % [path, _game.play_controller.state_machine.current_name()])
