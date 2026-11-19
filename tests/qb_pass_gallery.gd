extends SceneTree
## Screenshots of the quarterback with his feet set and of his pass: the hold
## standing and on the move, the pass a few ticks apart from the release to the
## end of the follow through, and the pump fake. Prints where his hands and
## feet are, to set against the clip the poses were measured from (Mixamo's
## "Quarterback Pass", assets/player/source/mixamo).
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --resolution 900x700 --script res://tests/qb_pass_gallery.gd -- out=<folder>

var _out_dir: String = "user://qb_pass_gallery"
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
	_cam.fov = 24.0
	root.add_child(_cam)
	_run()


func _run() -> void:
	await create_timer(0.6).timeout
	_pc = _game.play_controller
	_game.clock = 1.0e6

	_setup()
	await _frames(40)
	_measure("hold")
	await _shots("1_hold")

	_qb.move_input = Vector3(-_dir, 0.0, 0.4).normalized()
	await _frames(24)
	print("moving at ", _qb.velocity.length(), " yd/s, feet set ", _qb.feet_set)
	await _shots("2_hold_moving")
	_qb.move_input = Vector3.ZERO
	await _frames(40)

	_pc.pump_fake()
	await _frames(6)
	await _shots("3_pump")
	await _frames(40)

	_pc.throw_ball(_receiver, 0.6)
	var done: int = 0
	for at: int in [2, 5, 9, 13, 18, 26]:
		await _frames(at - done)
		done = at
		_measure("pass, tick %d" % at)
		await _shots("4_pass_%02d" % at)
	quit(0)


## A pass play just snapped: the quarterback well behind the line with nobody
## near him, his first receiver 18 yards straight downfield, everyone else
## standing still out of the way.
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
	_qb.move_input = Vector3.ZERO
	_qb.wants_turbo = false


func _frames(count: int) -> void:
	for i: int in count:
		await physics_frame


## Wrists from the middle of the shoulders in arm lengths, and ankles from the
## hips in leg lengths: (to his left, up, the way he faces).
func _measure(label: String) -> void:
	var animator: PlayerAnimator = _qb.animator
	var skeleton: Skeleton3D = animator.skeleton
	var at: Callable = func(bone: int) -> Vector3:
		return skeleton.get_bone_global_pose(animator._bone[bone]).origin
	var mid: Vector3 = (at.call(PlayerAnimator.B.ARM_L) + at.call(PlayerAnimator.B.ARM_R)) * 0.5
	var arm: float = (at.call(PlayerAnimator.B.FORE_L) - at.call(PlayerAnimator.B.ARM_L)).length() + (at.call(PlayerAnimator.B.HAND_L) - at.call(PlayerAnimator.B.FORE_L)).length()
	var leg: float = (at.call(PlayerAnimator.B.SHIN_L) - at.call(PlayerAnimator.B.THIGH_L)).length() + (at.call(PlayerAnimator.B.FOOT_L) - at.call(PlayerAnimator.B.SHIN_L)).length()
	print("%s: hands R %.2v L %.2v   feet L %.2v R %.2v" % [
		label,
		(at.call(PlayerAnimator.B.HAND_R) - mid) / arm, (at.call(PlayerAnimator.B.HAND_L) - mid) / arm,
		(at.call(PlayerAnimator.B.FOOT_L) - at.call(PlayerAnimator.B.HIPS)) / leg, (at.call(PlayerAnimator.B.FOOT_R) - at.call(PlayerAnimator.B.HIPS)) / leg,
	])


## From downfield looking back at him, from his open side, and from high up
## behind him, about where the game's camera sits.
func _shots(label: String) -> void:
	var at: Vector3 = _qb.position + Vector3(0.0, 1.0, 0.0)
	await _shot(label + "_front", at + Vector3(_dir * 7.0, 0.5, 0.0), at)
	await _shot(label + "_side", at + Vector3(0.0, 0.5, 7.0 * _dir), at)
	await _shot(label + "_high", at + Vector3(-_dir * 9.0, 7.0, 0.0), at)


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
