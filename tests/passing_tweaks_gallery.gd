extends SceneTree
## Screenshots of the passing tweaks: the ring at the quarterback's feet (set,
## not set, and the pop as they come set), the pump fake, and the three
## acrobatic throws on the run (spin, leap, fade).
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --resolution 1100x700 --script res://tests/passing_tweaks_gallery.gd -- out=<folder>

var _out_dir: String = "user://passing_tweaks_gallery"
var _game: Game
var _pc: PlayController
var _cam: Camera3D
var _qb: Player
var _receiver: Player
var _dir: float = 1.0


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
	_cam.fov = 32.0
	root.add_child(_cam)
	_run()


func _run() -> void:
	await create_timer(0.6).timeout
	_pc = _game.play_controller
	_game.clock = 1.0e6

	_setup()
	await _frames(20)
	await _shots("1_feet_set")
	_run_to(Vector3(0.0, 0.0, 1.0), true)
	await _frames(14)
	_run_to(Vector3.ZERO, false)
	await _frames(12)
	await _shots("2_feet_not_set")
	while _qb.feet_set < 1.0:
		await physics_frame
	# A few frames in, so the sparks are up off the ring.
	await _frames(8)
	await _shots("3_feet_planted")
	await _frames(30)
	_pc.pump_fake()
	await _frames(5)
	await _shots("4_pump_fake")

	# Toward the target: the spin. Across it: the leap. Away from it: the fade.
	var runs: Array[Vector3] = [Vector3(_dir, 0.0, 0.3), Vector3(0.0, 0.0, -1.0), Vector3(-_dir, 0.0, 0.0)]
	var names: Array[String] = ["5_spin", "6_leap", "7_fade"]
	for i: int in runs.size():
		_setup()
		await _frames(5)
		_run_to(runs[i].normalized(), true)
		await _frames(16)
		_run_to(runs[i].normalized(), false)
		await _frames(2)
		_pc.throw_ball(_receiver, 0.6)
		print(names[i], " -> ", Player.Flair.keys()[_qb.flair], "  running ", _qb.velocity, ", thrown ", _pc.ball.target_point - _qb.position)
		for at: int in [4, 10, 18]:
			await _frames(6 if at > 4 else 4)
			await _shots("%s_%02d" % [names[i], at])
	quit(0)


## A pass play just snapped: the quarterback well behind the line with nobody
## near him, his first receiver 18 yards downfield, everyone else standing
## still out of the way. He is moved by this script, not by his brain.
func _setup() -> void:
	var tuning: Tuning = _game.tuning
	var offense: Team = _game.home
	_dir = float(offense.attack_dir)
	_game.start_drive(offense, tuning.yard_to_x(offense.attack_dir, 40.0))
	var play: OffensePlay = _game.offense_playbook.plays[0]
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if not candidate.is_run and not candidate.play_action and not candidate.flea_flicker:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_qb = _pc.qb
	_receiver = _pc.eligible[0]
	for player: Player in _pc.players:
		if player == _qb:
			continue
		player.velocity = Vector3.ZERO
		player.frozen = true
		player.position = Vector3(_pc.los_x + _dir * 40.0, 0.0, float(player.index) * 2.0 - 20.0)
	_qb.position = Vector3(_pc.los_x - _dir * 12.0, 0.0, 0.0)
	_receiver.position = _qb.position + Vector3(_dir * 18.0, 0.0, 0.0)
	_game.human.controlled = _qb
	_run_to(Vector3.ZERO, false)


func _run_to(way: Vector3, turbo: bool) -> void:
	_qb.move_input = way
	_qb.wants_turbo = turbo


func _frames(count: int) -> void:
	for i: int in count:
		await physics_frame


## One from the front and to the side, close, and one from high up behind him,
## about where the game's camera sits.
func _shots(label: String) -> void:
	var at: Vector3 = _qb.position + Vector3(0.0, 0.9, 0.0)
	await _shot(label + "_close", at + Vector3(_dir * 4.5, 1.6, 3.5), at)
	await _shot(label + "_high", at + Vector3(-_dir * 9.0, 7.0, 0.0), at)


## Freezes the game for the picture so both shots of one moment match.
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
