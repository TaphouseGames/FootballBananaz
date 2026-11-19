# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#extends SceneTree
### Screenshots of a jump dive: in the air, the burst as he lands, and lying
### dazed with the stars going round his head.
### Needs a window (no --headless), since headless does not render.
###
### Run:  godot --path . --resolution 1100x700 --script res://tests/jump_dive_gallery.gd -- out=<folder>

#var _out_dir: String = "user://jump_dive_gallery"
#var _game: Game
#var _pc: PlayController
#var _cam: Camera3D


#func _initialize() -> void:
#	for arg: String in OS.get_cmdline_user_args():
#		if arg.begins_with("out="):
#			_out_dir = arg.trim_prefix("out=")
#	DirAccess.make_dir_recursive_absolute(_out_dir)
#	var scene: PackedScene = load("res://scenes/main.tscn")
#	_game = scene.instantiate() as Game
#	_game.autoplay = true
#	root.add_child(_game)
#	_cam = Camera3D.new()
#	_cam.fov = 32.0
#	root.add_child(_cam)
#	_run()


#func _run() -> void:
#	await create_timer(0.6).timeout
#	_pc = _game.play_controller
#	var tuning: Tuning = _game.tuning
#	var offense: Team = _game.home
#	var dir: float = float(offense.attack_dir)
#	_game.clock = 1.0e6
#	_game.start_drive(offense, tuning.yard_to_x(offense.attack_dir, 30.0))
#	var play: OffensePlay = _game.offense_playbook.plays[0]
#	for candidate: OffensePlay in _game.offense_playbook.plays:
#		if not candidate.is_run and not candidate.play_action:
#			play = candidate
#			break
#	_pc.line_up(play, _game.defense_playbook.plays[0])
#	_pc.snap()
#	_pc.state_machine.transition(&"Live")

#	# One defender on his own in the middle of the field; the rest stand still.
#	var man: Player = offense.opponent.players[0]
#	for player: Player in _pc.players:
#		player.velocity = Vector3.ZERO
#		player.frozen = true
#	man.position = Vector3(tuning.field_length * 0.5, 0.0, 0.0)
#	man.facing = Vector3(dir, 0.0, 0.0)
#	man.frozen = false
#	_pc.do_jump(man)
#	while man.state == Player.State.JUMPING and man.state_timer > tuning.jump_time * 0.5:
#		await physics_frame
#	_pc.do_jump_dive(man, Vector3(dir, 0.0, 0.0))
#	for i: int in 12:
#		await physics_frame
#	await _shots("1_flying", man)
#	while man.state == Player.State.DIVING:
#		await physics_frame
#	for i: int in 5:
#		await physics_frame
#	await _shots("2_landing", man)
#	for i: int in 12:
#		await physics_frame
#	await _shots("3_burst", man)
#	for i: int in 40:
#		await physics_frame
#	await _shots("4_dazed", man)
#	for i: int in 55:
#		await physics_frame
#	await _shots("5_dazed_later", man)
#	while man.is_down():
#		await physics_frame
#	for i: int in 10:
#		await physics_frame
#	await _shots("6_up_again", man)
#	quit(0)


### One from the side, close, and one from high up where the game's camera sits.
#func _shots(label: String, subject: Player) -> void:
#	var at: Vector3 = subject.position + Vector3(0.0, 0.8 + subject.air_height(), 0.0)
#	var side: Vector3 = Vector3.UP.cross(subject.facing).normalized()
#	await _shot(label + "_side", at + side * 6.0 + Vector3(0.0, 1.2, 0.0), at)
#	await _shot(label + "_high", at - subject.facing * 9.0 + Vector3(0.0, 8.0, 0.0), at)


### Freezes the game for the picture so both shots of one moment match.
#func _shot(label: String, eye: Vector3, target: Vector3) -> void:
#	paused = true
#	_cam.look_at_from_position(eye, target, Vector3.UP)
#	_cam.reset_physics_interpolation()
#	_cam.make_current()
#	await process_frame
#	await RenderingServer.frame_post_draw
#	var image: Image = root.get_texture().get_image()
#	image.save_png(_out_dir.path_join(label + ".png"))
#	print("saved ", label)
#	paused = false
