extends SceneTree
## A hot route shown on the field before it is called (left trigger held), to
## look at: a pass play lined up, the hot-route panel up, and for one receiver
## a picture of every route the two sticks can show, in white over the route
## he has. Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --resolution 1280x720 --script res://tests/hot_route_gallery.gd -- out=<folder>
## Optional user args after "--":
##   off=<text>    offensive play whose name contains the text (default "gun stick")

const START_YARD: float = 30.0
## The routes, and the way each breaks in the play's frame.
const SHOTS: Array[Array] = [
	["streak", OffenseAssignment.Hot.STREAK, 0.0],
	["curl", OffenseAssignment.Hot.CURL, 0.0],
	["slant", OffenseAssignment.Hot.SLANT, 1.0],
	["post", OffenseAssignment.Hot.POST, 0.0],
	["drag", OffenseAssignment.Hot.DRAG, 0.0],
	["out", OffenseAssignment.Hot.OUT, -1.0],
]

var _out_dir: String = "user://hot_route_gallery"
var _off_filter: String = "gun stick"
var _game: Game
var _pc: PlayController
var _cam: Camera3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("off="):
			_off_filter = arg.trim_prefix("off=").to_lower()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	root.add_child(_cam)
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
		if candidate.play_name.to_lower().contains(_off_filter) and not candidate.is_run:
			offense = candidate
			break
	if offense == null:
		print("FAILED: no pass play called '%s'" % _off_filter)
		quit(1)
		return
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, START_YARD))
	_pc.line_up(offense, _game.defense_playbook.plays[0], false, false)
	_pc.state_machine.transition(&"PreSnap")
	await _wait(0.8)
	# The widest man who goes out on a route.
	var man: Player = null
	for player: Player in _pc.eligible:
		if player.brain.off_assign.job == OffenseAssignment.Job.ROUTE and (man == null or absf(player.position.z) > absf(man.position.z)):
			man = player
	if man == null:
		print("FAILED: %s has no receiver" % offense.play_name)
		quit(1)
		return
	var art: PlayArt = _game.play_art
	art.show_offense(offense, false)
	_game.hud.hide_banner()
	_game.hud.show_hot_routes("(%s) %s" % [_game.human.pass_label(_pc.eligible.find(man)), man.brain.off_assign.label])
	await _shot("0_as_called")
	for shot: Array in SHOTS:
		art.set_hot_preview(man, OffenseAssignment.hot_route(man.brain.off_assign, shot[1], shot[2]))
		await _wait(0.1)
		# The drawing is rebuilt in a frame of its own, and none runs while a
		# picture is taken.
		await process_frame
		await process_frame
		await _shot("%d_%s" % [SHOTS.find(shot) + 1, shot[0]])
	quit(0)


## From behind and above the offense, the whole formation and the coverage in view.
func _aim_above() -> void:
	var los: Vector3 = Vector3(_pc.los_x, 0.0, 0.0)
	var dir: Vector3 = Vector3(_pc.off_dir, 0.0, 0.0)
	_cam.look_at_from_position(los - dir * 30.0 + Vector3(0.0, 40.0, 0.0), los + dir * 7.0, Vector3.UP)
	_cam.reset_physics_interpolation()
	_cam.make_current()


func _wait(seconds: float) -> void:
	var ticks: int = roundi(seconds * float(Engine.physics_ticks_per_second))
	for _i: int in ticks:
		await physics_frame
		# The game's own camera takes over every tick: take it back.
		_aim_above()


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
