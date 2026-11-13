extends SceneTree
## Close-up screenshots of one blocker and the man he is blocking, at several
## moments of the same block: from the side, from in front and from above, with
## everyone else hidden, plus one of the whole line. Prints how far each palm is
## from where it has hold of the other man.
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/block_gallery.gd -- out=<folder>
## Optional user args after "--":
##   play=<text>   offensive play whose name contains the text (default "slants")
##   shots=<n>     how many moments to shoot (default 8)

const START_YARD: float = 25.0
const MOVES: PackedStringArray = ["none", "swim", "rip"]

var _out_dir: String = "user://block_gallery"
var _play_filter: String = "slants"
var _shots: int = 8
var _game: Game
var _pc: PlayController
var _cam: Camera3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("play="):
			_play_filter = arg.trim_prefix("play=").to_lower()
		elif arg.begins_with("shots="):
			_shots = int(arg.trim_prefix("shots="))
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
	# The block lasts, nobody is flattened and the quarterback holds the ball.
	tuning.block_shed_time_min = 60.0
	tuning.block_shed_time_max = 60.0
	tuning.block_pancake_chance = 0.0
	tuning.ai_qb_min_time = 1.0e9
	tuning.possession_flash = 0.0

	var offense_play: OffensePlay = _game.offense_playbook.plays[0]
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.play_name.to_lower().contains(_play_filter):
			offense_play = candidate
	_game.clock = 1.0e6
	_game.start_drive(_game.home, tuning.yard_to_x(_game.home.attack_dir, START_YARD))
	_pc.line_up(offense_play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")

	# The pair nearest the middle of the line, once they have hold of each other.
	var blocker: Player = null
	for i: int in 240:
		await physics_frame
		blocker = _locked_blocker()
		if blocker != null and _pc.live_time > 0.5:
			break
	if blocker == null:
		print("FAILED: nobody was blocked")
		quit(1)
		return
	var rusher: Player = blocker.block_partner
	print("pair: ", blocker.name, " blocks ", rusher.name)
	await _shot("0_whole_line", _mid(blocker, rusher) + Vector3(0.0, 2.4, 9.0), _mid(blocker, rusher))

	var worst: float = 0.0
	for shot: int in _shots:
		if _pc.ball_dead or blocker.block_partner != rusher:
			print("the block ended after ", shot, " shots")
			break
		var hold: Vector2 = blocker.animator.grab_gaps()
		var fight: Vector2 = rusher.animator.grab_gaps()
		worst = maxf(worst, maxf(maxf(hold.x, hold.y), maxf(fight.x, fight.y)))
		var move: String = MOVES[rusher.animator._move] if rusher.animator._move_timer > 0.0 else "none"
		print("%d: blocker palms %.2f / %.2f m off, rusher palms %.2f / %.2f m off, rusher side %+.2f, move %s, %.2f m apart" % [
			shot + 1, hold.x, hold.y, fight.x, fight.y, rusher.animator._fight_now, move, blocker.position.distance_to(rusher.position)])
		await _pair_shots("%d" % (shot + 1), blocker, rusher)
		# Not a whole number of fight beats apart, so the moments differ.
		for i: int in 13:
			await physics_frame
	print("worst palm gap %.2f m" % worst)
	quit(0)


## A blocker who has hold of a man who has hold of him, nearest the ball's line.
func _locked_blocker() -> Player:
	var best: Player = null
	for player: Player in _pc.offense.players:
		var partner: Player = player.block_partner
		if not player.is_blocking or partner == null or partner.block_partner != player:
			continue
		if player.animator.grab_gaps().x < 0.0 or partner.animator.grab_gaps().x < 0.0:
			continue
		if best == null or absf(player.position.z) < absf(best.position.z):
			best = player
	return best


func _mid(a: Player, b: Player) -> Vector3:
	return (a.position + b.position) * 0.5 + Vector3(0.0, 1.0, 0.0)


## The two of them alone, from three sides.
func _pair_shots(label: String, blocker: Player, rusher: Player) -> void:
	var at: Vector3 = _mid(blocker, rusher)
	var along: Vector3 = (rusher.position - blocker.position).normalized()
	var side: Vector3 = Vector3.UP.cross(along).normalized()
	for other: Player in _pc.players:
		other.visible = other == blocker or other == rusher
	await _shot(label + "_side", at + side * 5.5 + Vector3(0.0, 0.5, 0.0), at)
	await _shot(label + "_behind_blocker", at - along * 5.0 + side * 2.0 + Vector3(0.0, 1.4, 0.0), at)
	await _shot(label + "_above", at + Vector3(0.0, 6.0, 0.0) + side * 0.6, at)
	for other: Player in _pc.players:
		other.visible = true


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
