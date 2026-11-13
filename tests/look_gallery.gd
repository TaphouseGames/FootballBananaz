extends SceneTree
## Screenshots of each team stood in a row facing the camera, front and back,
## to check the players' skin tones and hair colours. Needs a window (no
## --headless).
##
## Run:  godot --path . --resolution 1500x600 --script res://tests/look_gallery.gd -- out=<folder>

const SPACING: float = 1.25

var _out_dir: String = "user://look_gallery"
var _game: Game
var _cam: Camera3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_run()


func _run() -> void:
	await create_timer(0.5).timeout
	var pc: PlayController = _game.play_controller
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 50.0))
	pc.line_up(_game.offense_playbook.plays[0], _game.defense_playbook.plays[0])
	await physics_frame
	await physics_frame
	paused = true
	for team: Team in [_game.home, _game.away]:
		var count: int = team.players.size()
		for other: Player in pc.players:
			other.visible = other.team == team
		for i: int in count:
			var spot: Vector3 = Vector3((float(i) - float(count - 1) * 0.5) * SPACING, 0.0, 0.0)
			team.players[i].reset_for_play(spot, Vector3(0.0, 0.0, 1.0))
		var kit: String = "home" if team == _game.home else "away"
		var target: Vector3 = Vector3(0.0, 1.0, 0.0)
		await _shot(kit + "_front", Vector3(0.0, 1.6, 7.5), target)
		await _shot(kit + "_back", Vector3(0.0, 1.6, -7.5), target)
		await _shot(kit + "_faces", Vector3(0.0, 1.9, 3.2), Vector3(0.0, 1.6, 0.0))
	quit(0)


func _shot(label: String, eye: Vector3, target: Vector3) -> void:
	_cam.look_at_from_position(eye, target, Vector3.UP)
	_cam.reset_physics_interpolation()
	_cam.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(label + ".png"))
	print("saved ", label)
