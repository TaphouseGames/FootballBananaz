extends SceneTree
## Motion before the snap, to look at: one offensive play lined up against a
## man defense and against a zone defense, the motion man sent, and a picture
## from above before he goes, while he is on his way and once everybody has
## settled. In man his defender goes with him; in zone nobody does and the
## coverage slides a few yards. Plus close-ups of the quarterback's leg kick.
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --resolution 1280x720 --script res://tests/presnap_motion_gallery.gd -- out=<folder>
## Optional user args after "--":
##   off=<text>    offensive play whose name contains the text (default "gun stick")
##   def=<text>    one defensive play instead of the two (name contains the text)
##   flipped       run the offensive play mirrored
##   hold          no pictures: keep showing it on screen, man and zone in turn,
##                 until the window is closed

const START_YARD: float = 30.0

var _out_dir: String = "user://presnap_motion_gallery"
var _off_filter: String = "gun stick"
var _def_filter: String = ""
var _flipped: bool = false
var _hold: bool = false
var _game: Game
var _pc: PlayController
var _cam: Camera3D
var _label: Label


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("off="):
			_off_filter = arg.trim_prefix("off=").to_lower()
		elif arg.begins_with("def="):
			_def_filter = arg.trim_prefix("def=").to_lower()
		elif arg == "flipped":
			_flipped = true
		elif arg == "hold":
			_hold = true
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	root.add_child(_cam)
	_label = Label.new()
	_label.position = Vector2(24.0, 64.0)
	_label.add_theme_font_size_override(&"font_size", 28)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 8)
	root.add_child(_label)
	_run()


func _run() -> void:
	await create_timer(0.6).timeout
	_pc = _game.play_controller
	var tuning: Tuning = _game.tuning
	# Nobody snaps and nobody calls a motion but this script.
	tuning.cpu_snap_delay_min = 1.0e9
	tuning.cpu_snap_delay_max = 1.0e9
	tuning.ai_motion_chance = 0.0
	# Nor does the CPU change its play at the line.
	tuning.ai_audible_chance = 0.0
	tuning.ai_hot_route_chance = 0.0
	tuning.audio_enabled = false
	_game.clock = 1.0e6

	var offense: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.play_name.to_lower().contains(_off_filter):
			offense = candidate
			break
	if offense == null or not MotionRules.has_motion(offense):
		print("FAILED: no play with a motion called '%s'" % _off_filter)
		quit(1)
		return
	var defenses: Array[DefensePlay] = []
	for candidate: DefensePlay in _game.defense_playbook.plays:
		var name: String = candidate.play_name.to_lower()
		if (_def_filter != "" and name.contains(_def_filter)) or (_def_filter == "" and (name == "man cover 1" or name == "zone cover 2")):
			defenses.append(candidate)
	if defenses.is_empty():
		print("FAILED: no defensive play called '%s'" % _def_filter)
		quit(1)
		return

	var first: bool = true
	while true:
		for defense: DefensePlay in defenses:
			await _show(offense, defense, first)
			first = false
		if not _hold:
			break
	quit(0)


func _show(offense: OffensePlay, defense: DefensePlay, kick_shots: bool) -> void:
	var tag: String = defense.play_name.to_lower().replace(" ", "_")
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, START_YARD))
	_pc.line_up(offense, defense, _flipped, false)
	_pc.state_machine.transition(&"PreSnap")
	var motion: PreSnapMotion = _pc.motion
	var kind: String = OffensePlay.Motion.keys()[offense.motion]
	_label.text = "%s (%s)  vs  %s" % [offense.play_name, kind, defense.play_name]
	_aim_above()
	await _wait(0.8)
	var before: Dictionary[Player, Vector3] = {}
	for defender: Player in _pc.defense.players:
		before[defender] = defender.position
	if not _hold:
		await _shot("%s_1_before" % tag)
	motion.call_motion()
	if kick_shots and not _hold:
		for moment: float in [0.12, 0.3, 0.45]:
			await _wait_until(func() -> bool: return motion.time >= moment)
			_aim_quarterback()
			await _shot("kick_%d" % roundi(moment * 100.0))
		_aim_above()
	await _wait_until(func() -> bool: return motion.progress() >= 0.5 or motion.state == PreSnapMotion.State.SET)
	if not _hold:
		await _shot("%s_2_on_his_way" % tag)
	await _wait_until(func() -> bool: return motion.state == PreSnapMotion.State.SET)
	await _wait(1.2)
	if not _hold:
		await _shot("%s_3_set" % tag)
	var followers: int = 0
	var shifted: int = 0
	var furthest: float = 0.0
	for defender: Player in _pc.defense.players:
		var moved: float = Vector2(defender.position.x - before[defender].x, defender.position.z - before[defender].z).length()
		if defender.brain.man_target == motion.man and defender.brain.def_assign.job == DefenseAssignment.Job.MAN:
			followers += 1
		elif moved > 0.3:
			shifted += 1
			furthest = maxf(furthest, moved)
	print("%s (%s) against %s: %d went with him, %d others shifted (at most %.1f yd)" % [offense.play_name, kind, defense.play_name, followers, shifted, furthest])
	if _hold:
		await _wait(1.5)


## From behind and above the offense, the whole formation and the coverage in view.
func _aim_above() -> void:
	var los: Vector3 = Vector3(_pc.los_x, 0.0, 0.0)
	var dir: Vector3 = Vector3(_pc.off_dir, 0.0, 0.0)
	_cam.fov = 38.0
	_cam.look_at_from_position(los - dir * 30.0 + Vector3(0.0, 40.0, 0.0), los + dir * 7.0, Vector3.UP)
	_cam.reset_physics_interpolation()
	_cam.make_current()


## The quarterback from in front and a little to one side.
func _aim_quarterback() -> void:
	var at: Vector3 = _pc.qb.position + Vector3(0.0, 1.0, 0.0)
	var dir: Vector3 = Vector3(_pc.off_dir, 0.0, 0.0)
	_cam.fov = 30.0
	_cam.look_at_from_position(at + dir * 6.0 + Vector3(0.0, 0.8, 2.5), at, Vector3.UP)
	_cam.reset_physics_interpolation()
	_cam.make_current()


func _wait(seconds: float) -> void:
	var ticks: int = roundi(seconds * float(Engine.physics_ticks_per_second))
	for _i: int in ticks:
		await physics_frame
		# The game's own camera takes over every tick: take it back.
		_cam.make_current()


func _wait_until(done: Callable) -> void:
	for _i: int in 900:
		if done.call():
			return
		await physics_frame
		_cam.make_current()


## Freezes the game for the picture.
func _shot(label: String) -> void:
	paused = true
	_cam.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(_out_dir.path_join(label + ".png"))
	print("saved ", label)
	paused = false
