extends SceneTree
## Screenshots of the celebration after a touchdown: the ball held up, the
## spike, every dance, every cheer, every sulk and the huddle round the scorer.
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/celebration_gallery.gd -- out=<folder>

var _out_dir: String = "user://celebration_gallery"
var _game: Game
var _cam: Camera3D
var _worst_overlap: float = 0.0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	# Long enough to get round everybody, and nobody spoiling the pictures.
	_game.tuning.scored_banner_time = 120.0
	_game.tuning.cheap_shot_chance = 0.0
	root.add_child(_game)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_run()


func _run() -> void:
	await _wait(0.5)
	var pc: PlayController = _game.play_controller
	var team: Team = _game.home
	_game.conversion = false
	_game.start_drive(team, _game.tuning.yard_to_x(team.attack_dir, 92.0))
	pc.line_up(_game.offense_playbook.plays[0], _game.defense_playbook.plays[0])
	pc.snap()
	pc.state_machine.transition(&"Live")
	await physics_frame
	await physics_frame
	var scorer: Player = pc.ball.carrier
	var dir: float = float(team.attack_dir)
	scorer.position = Vector3(_game.tuning.goal_x(team.attack_dir) + dir * 4.0, 0.0, 0.0)

	await _wait(0.4)
	await _close("01_ball_up", scorer)
	for i: int in 30:
		if not scorer.has_ball:
			break
		await _wait(0.03)
	await _wait(0.1)
	await _close("02_spike", scorer)

	# Let the others get there.
	await _wait(3.0)
	var mid: Vector3 = scorer.position
	await _shot("03_huddle", mid + Vector3(-11.0 * dir, 5.0, 4.0), mid + Vector3(0.0, 1.0, 0.0))
	await _shot("04_huddle_high", mid + Vector3(-2.0 * dir, 12.0, 9.0), mid)

	for style: int in PlayerAnimator.DANCES:
		pc.celebration_style = style
		await _wait(0.45)
		await _close("1%d_dance_a" % style, scorer)
		await _wait(0.17)
		await _close("1%d_dance_b" % style, scorer)

	for variant: int in PlayerAnimator.CHEERS:
		var mate: Player = _with_variant(pc, scorer.team, PlayerAnimator.CHEERS, variant, scorer)
		if mate != null:
			await _close("2%d_cheer_a" % variant, mate)
			await _wait(0.17)
			await _close("2%d_cheer_b" % variant, mate)

	for variant: int in PlayerAnimator.SULKS:
		var loser: Player = _with_variant(pc, scorer.team.opponent, PlayerAnimator.SULKS, variant, null)
		if loser != null:
			await _close("3%d_sulk_a" % variant, loser)
			await _wait(0.14)
			await _close("3%d_sulk_b" % variant, loser)
	print("deepest: arms %.3f into a body  %s" % [_worst_overlap, "ok" if _worst_overlap < 0.02 else "CLIPPING"])
	quit(0 if _worst_overlap < 0.02 else 1)


func _with_variant(pc: PlayController, team: Team, count: int, variant: int, skip: Player) -> Player:
	for player: Player in team.players:
		if player != skip and not player.is_down() and pc.celebration_variant(player, count) == variant:
			return player
	return null


## From in front of him and a little to one side, with nobody else in the way.
func _close(label: String, player: Player) -> void:
	var side: Vector3 = Vector3(-player.facing.z, 0.0, player.facing.x)
	for other: Player in _game.play_controller.players:
		other.visible = other == player
	# How far his arms are inside his own head or body: 0 is clear of it.
	var overlap: float = player.animator.arm_overlap()
	_worst_overlap = maxf(_worst_overlap, overlap)
	print("%s: arms %.3f into his body" % [label, overlap])
	await _shot(label, player.position + player.facing * 3.0 + side * 1.2 + Vector3(0.0, 1.9, 0.0), player.position + Vector3(0.0, 1.3, 0.0))
	for other: Player in _game.play_controller.players:
		other.visible = true


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
