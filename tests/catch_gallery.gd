extends SceneTree
## Close-up screenshots of a pass being caught three ways: on the run, with a
## jump, and with a dive at a ball led too far. Each is shot just before the
## ball arrives, on the tick of the catch, and as it is brought in.
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/catch_gallery.gd -- out=<folder>
## Optional user args after "--":
##   play=<text>   offensive play whose name contains the text (default "slants")
##   def=<text>    defensive play whose name contains the text (default "prevent")

enum Kind { RUN, JUMP, DIVE }

const START_YARD: float = 25.0
const NAMES: PackedStringArray = ["run", "jump", "dive"]

var _out_dir: String = "user://catch_gallery"
var _play_filter: String = "slants"
var _defense_filter: String = "prevent"
var _game: Game
var _pc: PlayController
var _cam: Camera3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("play="):
			_play_filter = arg.trim_prefix("play=").to_lower()
		elif arg.begins_with("def="):
			_defense_filter = arg.trim_prefix("def=").to_lower()
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
	var tuning: Tuning = _game.tuning
	# Every pass is caught, and nobody leaves his feet unless the test says so.
	tuning.catch_base_chance = 10.0
	tuning.catch_min_chance = 1.0
	tuning.ai_catch_effort_chance = 0.0
	tuning.ai_contest_chance = 0.0
	tuning.ai_qb_min_time = 1.0e9
	for kind: int in [Kind.RUN, Kind.JUMP, Kind.DIVE]:
		await _catch(kind)
	quit(0)


func _catch(kind: int) -> void:
	var tuning: Tuning = _game.tuning
	var label: String = NAMES[kind]
	# The dive is at a ball thrown well ahead of him.
	tuning.pass_overlead_chance = 100.0 if kind == Kind.DIVE else 0.0
	tuning.pass_overlead_min = 4.5
	tuning.pass_overlead_max = 4.5

	var offense_play: OffensePlay = _game.offense_playbook.plays[0]
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.play_name.to_lower().contains(_play_filter):
			offense_play = candidate
	_game.clock = 1.0e6
	_game.start_drive(_game.home, tuning.yard_to_x(_game.home.attack_dir, START_YARD))
	var defense_play: DefensePlay = _game.defense_playbook.plays[0]
	for candidate: DefensePlay in _game.defense_playbook.plays:
		if candidate.play_name.to_lower().contains(_defense_filter):
			defense_play = candidate
	_pc.line_up(offense_play, defense_play)
	_pc.snap()
	_pc.state_machine.transition(&"Live")

	var receiver: Player = _pc.eligible[0]
	while _pc.live_time < 1.1 and not _pc.ball_dead:
		await physics_frame
	_pc.throw_ball(receiver, 0.5)
	await physics_frame
	var ball: Ball = _pc.ball
	if ball.state != Ball.State.FLIGHT:
		print("skipped ", label, ": the pass was never thrown")
		return

	var acted: bool = kind == Kind.RUN
	var early: bool = false
	while ball.state == Ball.State.FLIGHT:
		var left: float = ball.flight_time - ball.flight_elapsed
		if not acted and left <= 0.26:
			acted = true
			if kind == Kind.JUMP:
				_pc.do_jump(receiver)
			else:
				_pc.do_dive(receiver, _pc.ball_dive_direction(receiver))
		if not early and left <= 0.1:
			early = true
			await _shots(label + "_1_reaching", receiver)
		await physics_frame
	if ball.carrier == null:
		print(label, ": not caught (", _pc.result_text(), ")")
		await _shots(label + "_2_missed", receiver)
		return
	var catcher: Player = ball.carrier
	await _shots(label + "_2_caught", catcher)
	for i: int in 5:
		await physics_frame
	await _shots(label + "_3_bringing_in", catcher)
	for i: int in 14:
		await physics_frame
	await _shots(label + "_4_secured", catcher)
	var hand_gap: float = (ball.global_position - catcher.ball_anchor()).length()
	print("%s: caught by %s, ball %.2f m from the hand after settling" % [label, catcher.name, hand_gap])


## One picture from the side and one from in front of him, plus how far each
## palm is from the ball at that moment.
func _shots(label: String, subject: Player) -> void:
	var animator: PlayerAnimator = subject.animator
	var skeleton: Skeleton3D = animator.skeleton
	var ball_at: Vector3 = _pc.ball.global_position
	var left: Vector3 = skeleton.global_transform * (skeleton.get_bone_global_pose(animator._bone[PlayerAnimator.B.HAND_L]) * animator._palm_l)
	var right: Vector3 = skeleton.global_transform * (skeleton.get_bone_global_pose(animator._bone[PlayerAnimator.B.HAND_R]) * animator._palm_r)
	print("%s: ball to left palm %.2f m, to right palm %.2f m" % [label, ball_at.distance_to(left), ball_at.distance_to(right)])
	var at: Vector3 = subject.position + Vector3(0.0, 1.2 + subject.air_height(), 0.0)
	var side: Vector3 = Vector3.UP.cross(subject.facing).normalized()
	# From whichever side has nobody standing in the way.
	var crowd: float = 0.0
	for other: Player in _pc.players:
		var to: Vector3 = other.position - subject.position
		if other != subject and to.length() < 5.0:
			crowd += signf(to.dot(side))
	if crowd > 0.0:
		side = -side
	await _shot(label + "_side", at + side * 5.0 + Vector3(0.0, 0.6, 0.0), at)
	await _shot(label + "_front", at + subject.facing * 4.4 + side * 2.4 + Vector3(0.0, 0.8, 0.0), at)

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
