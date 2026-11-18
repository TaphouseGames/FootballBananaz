extends SceneTree
## Pictures of the pause menu's roster screen, with the chosen player's model
## on his card: one of each team, the model seen from in front and, a little
## later, turned round. Needs a window (no --headless), since headless does not
## render.
##
## Run:  godot --path . --resolution 1280x720 --script res://tests/roster_gallery.gd -- out=<folder>
## Optional user args after "--":
##   player=<n>   the place in the roster of the player shown (default 0)

## Frames to wait for the game to stand, for the menu to fade in and the kit to
## be printed, and for the model to turn its back.
const START_FRAMES: int = 60
const SETTLE_FRAMES: int = 30
const TURN_FRAMES: int = 200

var _game: Game
var _out_dir: String = "user://roster_gallery"
var _player: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("player="):
			_player = int(arg.trim_prefix("player="))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	_run()


func _run() -> void:
	await _frames(START_FRAMES)
	var menu: PauseMenu = _game.hud.pause_menu
	menu.open()
	for side: int in 2:
		menu.show_screen(PauseMenu.Screen.ROSTER, side)
		var team: Team = _game.home if side == 0 else _game.away
		menu._roster_cursor = posmod(_player, team.squad.size())
		menu._refresh()
		await _frames(SETTLE_FRAMES)
		await _save("roster_%s_front" % team.short_name.to_lower())
		await _frames(TURN_FRAMES)
		await _save("roster_%s_back" % team.short_name.to_lower())
	print("roster gallery saved to ", ProjectSettings.globalize_path(_out_dir))
	quit()


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join("%s.png" % file))
	print("saved ", file)
