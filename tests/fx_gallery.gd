extends SceneTree
## Lets the CPU play both teams for a while, then saves screenshots of the turf,
## the marks left on it and the ball from a few extra cameras. Needs a window.
##
## Run:  godot --path . --script res://tests/fx_gallery.gd -- out=<folder> [seconds=N]

var _out_dir: String = "user://fx_gallery"
var _seconds: float = 30.0
var _game: Game


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("seconds="):
			_seconds = float(arg.trim_prefix("seconds="))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	_run()


func _run() -> void:
	Game.base_time_scale = 4.0
	Engine.time_scale = 4.0
	await create_timer(_seconds).timeout
	Game.base_time_scale = 1.0
	Engine.time_scale = 1.0
	await create_timer(0.3).timeout
	await _shot("1_game_camera")

	var camera: Camera3D = Camera3D.new()
	camera.fov = 45.0
	root.add_child(camera)
	camera.make_current()
	var ball: Vector3 = _game.ball.global_position
	var focus: Vector3 = Vector3(ball.x, 0.0, 0.0)
	await _view(camera, focus + Vector3(-4.0, 30.0, 14.0), focus, "2_overhead")
	await _view(camera, focus + Vector3(-9.0, 4.5, 7.0), focus, "3_low_angle")
	await _view(camera, focus + Vector3(-2.2, 1.7, 2.6), focus, "4_turf_close")
	# A spare ball lying in the open, for a clear look at the model.
	var ball_scene: PackedScene = load("res://scenes/ball.tscn")
	var spare: Ball = ball_scene.instantiate() as Ball
	root.add_child(spare)
	spare.position = focus + Vector3(-6.0, Ball.GROUND_HEIGHT, -9.0)
	spare.reset_physics_interpolation()
	await _view(camera, spare.position + Vector3(-0.5, 0.35, 0.7), spare.position, "5_ball_close")
	print("stats: %s" % [_game.stats])
	quit(0)


func _view(camera: Camera3D, eye: Vector3, target: Vector3, label: String) -> void:
	camera.look_at_from_position(eye, target, Vector3.UP)
	camera.reset_physics_interpolation()
	await _shot(label)


func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(label + ".png")
	image.save_png(path)
	print("saved %s" % path)
