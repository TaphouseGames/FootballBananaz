extends SceneTree
## The play drawn on the field before the snap (PlayArt), to look at: an
## offensive play and each defensive play asked for, from above and from the
## game's own camera. Needs a window (no --headless), since headless does not
## render.
##
## Run:  godot --path . --resolution 1280x720 --script res://tests/play_reveal_gallery.gd -- out=<folder>
## Optional user args after "--":
##   off=<text>    offensive play whose name contains the text (default "gun stick")
##   def=<text>    defensive plays whose name contains the text (default "cover")
##   flipped       both plays mirrored

const START_YARD: float = 30.0

var _out_dir: String = "user://play_reveal_gallery"
var _off_filter: String = "gun stick"
var _def_filter: String = "cover"
var _flipped: bool = false
var _game: Game
var _pc: PlayController
var _cam: Camera3D


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
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_run()


func _run() -> void:
	await create_timer(0.6).timeout
	_pc = _game.play_controller
	var tuning: Tuning = _game.tuning
	tuning.cpu_snap_delay_min = 1.0e9
	tuning.cpu_snap_delay_max = 1.0e9
	tuning.ai_motion_chance = 0.0
	tuning.audio_enabled = false
	_game.clock = 1.0e6

	var offense: OffensePlay = _game.offense_playbook.plays[0]
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.play_name.to_lower().contains(_off_filter):
			offense = candidate
			break
	var defenses: Array[DefensePlay] = []
	for candidate: DefensePlay in _game.defense_playbook.plays:
		if candidate.play_name.to_lower().contains(_def_filter):
			defenses.append(candidate)
	if defenses.is_empty():
		defenses.append(_game.defense_playbook.plays[0])

	_line_up(offense, defenses[0])
	await _wait(0.8)
	_game.play_art.show_offense(offense, _flipped)
	await _shots("offense_" + _tag(offense.play_name))
	# The man in motion on his way: his job as the snap would give it.
	if _pc.motion.call_motion():
		await _wait(0.5)
		await _shots("offense_" + _tag(offense.play_name) + "_motion")
	for defense: DefensePlay in defenses:
		_line_up(offense, defense)
		await _wait(0.8)
		_game.play_art.show_defense(defense, _flipped)
		await _shots("defense_" + _tag(defense.play_name))
	quit(0)


func _line_up(offense: OffensePlay, defense: DefensePlay) -> void:
	_game.play_art.clear()
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, START_YARD))
	_pc.line_up(offense, defense, _flipped, _flipped)
	_pc.state_machine.transition(&"PreSnap")
	_game.snap_camera()


func _tag(play_name: String) -> String:
	return play_name.to_lower().replace(" ", "_")


## One picture from above and one as the person sees it.
func _shots(label: String) -> void:
	var los: Vector3 = Vector3(_pc.los_x, 0.0, 0.0)
	var dir: Vector3 = Vector3(_pc.off_dir, 0.0, 0.0)
	_cam.fov = 38.0
	_cam.look_at_from_position(los - dir * 30.0 + Vector3(0.0, 40.0, 0.0), los + dir * 7.0, Vector3.UP)
	_cam.reset_physics_interpolation()
	await _shot(label + "_above", true)
	await _shot(label + "_game", false)


func _wait(seconds: float) -> void:
	for _i: int in roundi(seconds * float(Engine.physics_ticks_per_second)):
		await physics_frame


## Freezes the game for the picture. `own`: from this script's camera.
func _shot(label: String, own: bool) -> void:
	paused = true
	if own:
		_cam.make_current()
	else:
		_cam.clear_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(_out_dir.path_join(label + ".png"))
	print("saved ", label)
	paused = false
	await physics_frame
