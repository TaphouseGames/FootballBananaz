extends SceneTree
## Close-up screenshots of the procedural player animation: stances, the pocket,
## running, and forced jump / dive / knock-down / shove poses.
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/pose_gallery.gd -- out=<folder>

var _out_dir: String = "user://pose_gallery"
var _game: Game
var _cam: Camera3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	root.add_child(_game)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_run()


func _run() -> void:
	await _wait(0.6)
	var pc: PlayController = _game.play_controller
	await _tap(&"confirm")
	await _wait(1.0)
	var los: Vector3 = Vector3(pc.los_x, 0.0, 0.0)
	await _shot("1_line_side", los + Vector3(0.0, 2.0, 9.0), los + Vector3(0.0, 0.9, 0.0))
	await _shot("2_line_behind", los + Vector3(-9.0 * pc.off_dir, 3.0, 2.0), los + Vector3(0.0, 0.9, 0.0))
	var wide: Player = pc.eligible[0]
	await _shot("3_receiver_stance", wide.position + Vector3(2.0 * pc.off_dir, 1.4, 4.5), wide.position + Vector3(0.0, 0.9, 0.0))

	await _tap(&"confirm")
	await _wait(0.7)
	var qb: Player = pc.qb
	await _shot("4_qb_pocket", qb.position + Vector3(4.0 * pc.off_dir, 1.8, 3.0), qb.position + Vector3(0.0, 1.1, 0.0))
	await _shot("5_line_blocking", los + Vector3(0.0, 2.2, 8.0), los + Vector3(0.0, 0.9, 0.0))
	await _shot("6_receiver_running", wide.position + Vector3(1.0, 1.4, 5.0), wide.position + Vector3(0.0, 0.9, 0.0))

	# Force one of each special move on the far-side defenders.
	var defenders: Array[Player] = pc.defense.players
	var jumper: Player = defenders[defenders.size() - 1]
	var diver: Player = defenders[defenders.size() - 2]
	var victim: Player = defenders[defenders.size() - 3]
	var shover: Player = defenders[defenders.size() - 4]
	jumper.start_jump()
	diver.start_dive(diver.facing)
	shover.start_shove(shover.facing)
	victim.knock_down(victim.facing * -6.0, 1.1)
	# Ball-carrier moves, forced on the defenders that are left.
	var spinner: Player = defenders[defenders.size() - 5]
	var arm_left: Player = defenders[defenders.size() - 6]
	var arm_right: Player = defenders[defenders.size() - 7]
	spinner.start_spin(1.0)
	arm_left.start_stiff_arm(1.0)
	arm_right.start_stiff_arm(-1.0)
	await _wait(0.16)
	for mover: Player in [spinner, arm_left, arm_right]:
		# From above and behind, clear of the crowd: his left arm is on the left of the picture.
		var label: String = "spin" if mover == spinner else ("stiff_arm_left" if mover == arm_left else "stiff_arm_right")
		await _shot("7_" + label, mover.position - mover.facing * 2.6 + Vector3(0.0, 3.4, 0.0), mover.position + Vector3(0.0, 1.0, 0.0))
	await _shot("7_jump", jumper.position + Vector3(1.5, 1.6, 5.0), jumper.position + Vector3(0.0, 1.3, 0.0))
	await _shot("8_dive", diver.position + Vector3(1.0, 1.4, 5.0), diver.position + Vector3(0.0, 0.7, 0.0))
	await _shot("9_shove", shover.position + Vector3(1.0, 1.4, 5.0), shover.position + Vector3(0.0, 0.9, 0.0))
	await _wait(0.3)
	await _shot("10_on_back", victim.position + Vector3(1.0, 2.2, 4.5), victim.position + Vector3(0.0, 0.3, 0.0))
	await _shot("11_face_down", diver.position + Vector3(1.0, 2.2, 4.5), diver.position + Vector3(0.0, 0.3, 0.0))

	await _tap(&"pass_1")
	await _wait(0.12)
	await _shot("12_throw", qb.position + Vector3(4.0 * pc.off_dir, 1.8, 3.0), qb.position + Vector3(0.0, 1.1, 0.0))
	for i: int in 40:
		if pc.ball.state != Ball.State.FLIGHT or pc.ball.flight_time - pc.ball.flight_elapsed < 0.12:
			break
		await _wait(0.03)
	await _shot("13_catch", wide.position + Vector3(1.0, 1.6, 5.5), wide.position + Vector3(0.0, 1.2, 0.0))
	await _wait(0.5)
	var carrier: Player = pc.ball.carrier
	if carrier != null:
		await _shot("14_carrier", carrier.position + Vector3(1.0, 1.5, 5.0), carrier.position + Vector3(0.0, 0.9, 0.0))
	quit(0)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _wait(0.08)
	Input.action_release(action)
	await _wait(0.08)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Freezes the game for the picture so every shot of one moment matches.
func _shot(label: String, eye: Vector3, target: Vector3) -> void:
	paused = true
	_cam.look_at_from_position(eye, target, Vector3.UP)
	_cam.reset_physics_interpolation()
	_cam.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(_out_dir.path_join(label + ".png"))
	print("saved ", label)
	paused = false
