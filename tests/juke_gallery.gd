extends SceneTree
## Close-up screenshots of a receiver selling a cut in his route
## (PlayerAnimator.route_juke) and of a coverage defender who fell for one
## (PlayerAnimator.faked_out), each to his right and to his left, early and late
## in the move. Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --resolution 900x600 --script res://tests/juke_gallery.gd -- out=<folder>

var _out_dir: String = "user://juke_gallery"
var _game: Game
var _cam: Camera3D
var _started: bool = false


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
	physics_frame.connect(_tick)


func _tick() -> void:
	if _started or _game == null or not _game.is_node_ready() or _game.play_controller == null:
		return
	_started = true
	_run()


func _run() -> void:
	await _wait(0.5)
	var pc: PlayController = _game.play_controller
	var tuning: Tuning = _game.tuning
	# Nobody throws, nobody is fooled by himself: the moves are forced below.
	tuning.ai_qb_min_time = 1.0e9
	tuning.ai_qb_keeper_chance = 0.0
	tuning.ai_cover_bust_chance = 0.0
	tuning.ai_blown_coverage_chance = 0.0
	tuning.ai_takeout_chance = 0.0
	_game.clock = 1.0e6
	_game.start_drive(_game.home, tuning.yard_to_x(_game.home.attack_dir, 25.0))
	var play: OffensePlay = _game.offense_playbook.plays[0]
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.play_name.to_lower().contains("gun verts"):
			play = candidate
	# Man Cover 1: a man on every receiver.
	pc.line_up(play, _game.defense_playbook.plays[0])
	pc.snap()
	pc.state_machine.transition(&"Live")
	await _wait(1.1)

	var cutters: Array[Player] = []
	var cover: Array[Player] = []
	for receiver: Player in pc.eligible:
		for defender: Player in pc.defense.players:
			if defender.brain.man_target == receiver and cutters.size() < 2 and not receiver.is_down() and not defender.is_down():
				cutters.append(receiver)
				cover.append(defender)
	if cutters.size() < 2:
		print("FAIL: fewer than two receivers with a man on them")
		quit(1)
		return
	for i: int in 2:
		cutters[i].animator.route_juke(1.0 if i == 0 else -1.0)
		cover[i].animator.faked_out(1.0 if i == 0 else -1.0)
	for moment: int in 2:
		await _wait(0.12 if moment == 0 else 0.2)
		for i: int in 2:
			var side: String = "right" if i == 0 else "left"
			await _shot("route_juke_%s_%s" % [side, "fake" if moment == 0 else "cut"], cutters[i])
			await _shot("faked_out_%s_%s" % [side, "lunge" if moment == 0 else "look_back"], cover[i])
	quit(0)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## From above and behind him, so his left is on the left of the picture. The
## game is frozen for it.
func _shot(label: String, who: Player) -> void:
	paused = true
	_cam.look_at_from_position(who.position - who.facing * 2.6 + Vector3(0.0, 3.0, 0.0), who.position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	_cam.reset_physics_interpolation()
	_cam.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(_out_dir.path_join(label + ".png"))
	print("saved ", label)
	paused = false
