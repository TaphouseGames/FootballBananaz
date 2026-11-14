extends SceneTree
## Receivers at the end of their routes: screenshots of an open receiver calling
## for the ball (standing and on the run), and a log of when each receiver sets
## off to find space, to check that they do not all go at once.
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/wave_gallery.gd -- out=<folder> play=<n>

var _out_dir: String = "user://wave_gallery"
## Which of the playbook's pass plays to run.
var _play: int = 0
var _game: Game
var _cam: Camera3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("play="):
			_play = int(arg.trim_prefix("play="))
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
	# Put the wanted pass play on the first card, where the cursor starts.
	var plays: Array[OffensePlay] = _game.offense_playbook.plays
	var passes: Array[int] = []
	for i: int in plays.size():
		if not plays[i].is_run:
			passes.append(i)
	var pick: int = passes[_play % passes.size()]
	var chosen: OffensePlay = plays[pick]
	plays[pick] = plays[0]
	plays[0] = chosen
	# On the tab the screen opens with.
	chosen.group = OffensePlay.Group.RUN
	print("play: ", chosen.resource_path.get_file())
	await _tap(&"confirm")
	await _wait(1.0)
	await _tap(&"confirm")
	# The human quarterback just holds the ball while the routes play out.
	var set_off: Dictionary = {}
	var standing: int = 0
	var running: int = 0
	var live: bool = false
	for i: int in 160:
		await _wait(0.05)
		var in_pocket: bool = not pc.ball_dead and pc.phase == PlayController.Phase.POCKET and pc.qb != null and pc.qb.has_ball and not pc.qb.frozen
		if not in_pocket:
			if live:
				print("play over at %.2f s (dead %s, phase %d, run play %s)" % [pc.live_time, pc.ball_dead, pc.phase, pc.off_play.is_run])
				break
			continue
		live = true
		# Hold the pass rush back so the quarterback has time to stand there.
		for defender: Player in pc.defense.players:
			if defender.brain.def_assign != null and defender.brain.def_assign.job == DefenseAssignment.Job.RUSH:
				defender.frozen = true
		for receiver: Player in pc.eligible:
			var brain: PlayerBrain = receiver.brain
			if not set_off.has(receiver) and brain._open_delay >= 0.0 and brain._wait_time >= brain._open_delay:
				set_off[receiver] = true
				print("receiver %d sets off at %.2f s (own delay %.2f s)" % [receiver.index, pc.live_time, brain._open_delay])
			if not receiver.calling_for_ball or receiver.animator._wave < 1.0:
				continue
			var speed: float = receiver.velocity.length()
			if speed < 1.5 and standing < 3:
				standing += 1
				await _front("standing_%d_r%d" % [standing, receiver.index], receiver, pc)
			elif speed > 4.5 and running < 2:
				running += 1
				await _front("running_%d_r%d" % [running, receiver.index], receiver, pc)
	print("shots: %d standing, %d running" % [standing, running])
	quit(0)


## From the quarterback's side, so the receiver is seen the way the passer sees him.
func _front(label: String, receiver: Player, pc: PlayController) -> void:
	var toward: Vector3 = (pc.qb.position - receiver.position).normalized()
	await _shot(label, receiver.position + toward * 5.5 + Vector3(0.0, 1.6, 0.0), receiver.position + Vector3(0.0, 1.2, 0.0))


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _wait(0.08)
	Input.action_release(action)
	await _wait(0.08)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


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
