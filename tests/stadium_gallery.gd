extends SceneTree
## Pictures of the stadium: the game camera at both ends and midfield, the
## looks across at each stand, the intro's opening shot, close-ups of the
## crowd, the wall and the props, the mascots standing by, then a home cheer
## and a wave. Needs a window (no
## --headless), since headless does not render.
##
## Run:  godot --path . --resolution 1280x720 --script res://tests/stadium_gallery.gd -- out=<folder> [only=<text>] [home=<team>] [away=<team>]
## (teams by short name, e.g. home=peachez away=bananaz)

var _out_dir: String = "user://stadium_gallery"
var _only: String = ""
var _game: Game
var _teams: PackedStringArray = ["", ""]


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("only="):
			_only = arg.trim_prefix("only=")
		elif arg.begins_with("home="):
			_teams[0] = arg.trim_prefix("home=")
		elif arg.begins_with("away="):
			_teams[1] = arg.trim_prefix("away=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.tuning = _game.tuning.duplicate() as Tuning
	_game.tuning.audio_enabled = false
	for side: int in 2:
		for i: int in _game.league.teams.size():
			if _game.league.teams[i].short_name.to_lower() == _teams[side].to_lower():
				Game.team_picks[side] = i
	root.add_child(_game)
	_run()


func _run() -> void:
	var t: Tuning = _game.tuning
	var length: float = t.field_length
	var back: Vector3 = Vector3(-t.camera_distance, t.camera_height, 0.0)
	var ahead: Vector3 = Vector3(t.camera_look_ahead, 0.0, 0.0)
	var flip: Vector3 = Vector3(-1.0, 1.0, 1.0)
	# The shots at the sides were set up on a field 40 yards wide: `out` moves
	# them with the sidelines.
	var out: float = t.half_width() - 20.0
	await _wait(2.0)
	var stadium: Stadium = _game.field.stadium
	# The game's own camera, behind a player at these places.
	await _shoot("cam_own_goal", Vector3(-8.0, 0.0, 0.0) + back, Vector3(-8.0, 0.0, 0.0) + ahead)
	await _shoot("cam_midfield", Vector3(50.0, 0.0, 0.0) + back, Vector3(50.0, 0.0, 0.0) + ahead)
	await _shoot("cam_sideline", Vector3(50.0, 0.0, 17.0 + out) + back, Vector3(50.0, 0.0, 17.0 + out) + ahead)
	await _shoot("cam_red_zone", Vector3(88.0, 0.0, -8.0) + back, Vector3(88.0, 0.0, -8.0) + ahead)
	await _shoot("cam_other_way", Vector3(60.0, 0.0, 0.0) + back * flip, Vector3(60.0, 0.0, 0.0) + ahead * flip)
	# Half way round a swing: looking across at each stand.
	await _shoot("swing_home_stand", Vector3(50.0, t.camera_height, t.camera_distance), Vector3(50.0, 0.0, -t.camera_look_ahead))
	await _shoot("swing_away_stand", Vector3(50.0, t.camera_height, -t.camera_distance), Vector3(50.0, 0.0, t.camera_look_ahead))
	await _shoot("intro_start", Vector3(50.0 - 38.0, 24.0, 54.0 + out), Vector3(59.0, 1.5, 0.0))
	await _shoot("intro_end", Vector3(50.0 - 12.0, 4.5, 17.0 + out), Vector3(59.0, 1.5, 0.0))
	await _shoot("overview", Vector3(length * 0.5, 120.0, 150.0), Vector3(length * 0.5, 0.0, 0.0))
	await _shoot("crowd_close", Vector3(40.0, 4.0, -12.0 - out), Vector3(47.0, 5.0, -32.0 - out))
	await _shoot("fans_front", Vector3(45.0, 2.6, -16.0 - out), Vector3(45.0, 2.4, -24.0 - out))
	# Along a row from the aisle: the fans on their seats, and the empty ones.
	await _shoot("seats_side", Vector3(49.7, 2.9, -22.6 - out), Vector3(45.0, 2.2, -23.6 - out))
	await _shoot("signs_close", Vector3(60.0, 7.5, -12.0 - out), Vector3(62.0, 7.0, -34.0 - out))
	await _shoot("aisle_close", Vector3(55.0, 9.0, 8.0 + out), Vector3(62.0, 6.0, 32.0 + out))
	# The modelled pieces: a tunnel mouth, the roof from the walkway, the press
	# box, and the outside wall with what lies round the bowl.
	await _shoot("tunnel", Vector3(47.0, 6.5, -20.0 - out), Vector3(43.0, 5.0, -30.0 - out))
	await _shoot("roof", Vector3(30.0, 13.5, -36.0 - out), Vector3(60.0, 14.0, -48.0 - out))
	await _shoot("press_box", Vector3(50.0, 12.0, -8.0 - out), Vector3(50.0, 16.0, -48.0 - out))
	await _shoot("facade", Vector3(20.0, 9.0, -95.0 - out), Vector3(50.0, 8.0, -50.0 - out))
	await _shoot("corner", Vector3(92.0, 5.0, 4.0 + out), Vector3(111.0, 2.0, 21.0 + out))
	# The wall, right on the lines: along a sideline and at an end.
	await _shoot("wall_sideline", Vector3(40.0, 1.8, 15.0 + out), Vector3(60.0, 1.0, 20.5 + out))
	await _shoot("wall_end", Vector3(98.0, 2.2, -6.0), Vector3(111.0, 1.5, 4.0))
	# What is painted on the turf: the mascots at the 50, the numbers from each
	# side, and a corner of an end zone (no lines round the edge).
	await _shoot("field_midfield", Vector3(50.0, 24.0, 16.0), Vector3(50.0, 0.0, 0.5))
	await _shoot("field_numbers", Vector3(30.0, 13.0, 19.0), Vector3(30.0, 0.0, 12.0))
	await _shoot("field_numbers_far", Vector3(70.0, 13.0, -19.0), Vector3(70.0, 0.0, -12.0))
	await _shoot("field_corner", Vector3(88.0, 7.0, 6.0 + out), Vector3(108.0, 0.0, 19.0 + out))
	await _shoot("field_overhead", Vector3(50.0, 95.0, 0.5), Vector3(50.0, 0.0, 0.0))
	# The mascots stand by with their teams. A play is lined up at midfield and
	# stopped there, so that they are where a play puts them.
	var pc: PlayController = _game.play_controller
	_game.start_drive(_game.home, 50.0)
	pc.line_up(_game.offense_playbook.plays[0], _game.defense_playbook.plays[0])
	await _wait(0.3)
	pc.process_mode = Node.PROCESS_MODE_DISABLED
	_game.ball.process_mode = Node.PROCESS_MODE_DISABLED
	var dir: Vector3 = Vector3(float(_game.home.attack_dir), 1.0, 1.0)
	await _shoot("mascots_cam", Vector3(50.0, 0.0, 0.0) + back * dir, Vector3(50.0, 0.0, 0.0) + ahead * dir)
	var home_mascot: Mascot = _game.home.mascot
	var away_mascot: Mascot = _game.away.mascot
	var close_home: Array[Vector3] = [home_mascot.position + Vector3(2.5, 1.8, 6.0), home_mascot.position + Vector3(0.0, 1.5, 0.0)]
	var close_away: Array[Vector3] = [away_mascot.position + Vector3(2.5, 1.8, -6.0), away_mascot.position + Vector3(0.0, 1.5, 0.0)]
	await _shoot("mascot", close_home[0], close_home[1])
	await _shoot("mascot_away", close_away[0], close_away[1])
	# What it acts out where it stands, and what it looks like run over.
	for act: Array in [[&"point", 0.5], [&"flex", 0.5], [&"faint", 1.4]]:
		home_mascot.react(act[0], 6.0)
		home_mascot._update_visual(0.0, false)
		await _wait(act[1])
		await _shoot("mascot_%s" % act[0], close_home[0], close_home[1], 0.0)
	home_mascot.react(&"idle", 0.0)
	away_mascot.knock_down(Vector3(0.0, 0.0, 1.0), 5.0)
	for i: int in 30:
		away_mascot._update_visual(1.0 / 30.0, false)
		await process_frame
	await _shoot("mascot_down", close_away[0], close_away[1], 0.0)
	# The wall is solid. One player stands by it for its height; one dives into
	# it chest first and one is knocked into it backwards: flat against it, then
	# peeling off.
	if _only == "" or "wall_splat wall_peel wall_cam".contains(_only):
		var side: float = t.half_width() + t.wall_gap
		var men: Array[Player] = [_game.home.players[1], _game.home.players[2], _game.away.players[1]]
		var spots: Array[Vector3] = [Vector3(46.5, 0.0, side - t.wall_standoff), Vector3(49.0, 0.0, side - 1.6), Vector3(51.5, 0.0, side - 1.5)]
		var faces: Array[Vector3] = [Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0)]
		for i: int in men.size():
			men[i].position = spots[i]
			men[i].velocity = Vector3.ZERO
			men[i].move_input = Vector3.ZERO
			men[i].frozen = false
			men[i].state = Player.State.NORMAL
			men[i].facing = faces[i]
			men[i]._update_visual(0.0, true)
		men[1].start_dive(Vector3(0.0, 0.0, 1.0))
		men[2].knock_down(Vector3(0.0, 0.0, 1.0) * t.shove_knockdown_impulse, t.knockdown_time)
		var eye: Vector3 = Vector3(49.5, 1.7, side - 6.5)
		var aim: Vector3 = Vector3(49.5, 1.1, side)
		var shots: Dictionary = {8: "wall_splat_hit", 30: "wall_splat", 62: "wall_peel_0", 72: "wall_peel_1", 84: "wall_peel_2", 110: "wall_peel_3"}
		for tick: int in 111:
			for man: Player in men:
				man.integrate(1.0 / 60.0)
			await process_frame
			if shots.has(tick):
				await _shoot(shots[tick], eye, aim, 0.0)
			if tick == 30:
				await _shoot("wall_splat_side", Vector3(44.0, 1.6, side - 0.9), Vector3(52.0, 1.0, side - 0.3), 0.0)
				await _shoot("wall_cam", Vector3(50.0, 0.0, side - 3.0) + back * dir, Vector3(50.0, 0.0, side - 3.0) + ahead * dir, 0.0)
	await _wait(6.0)
	await _shoot("jumbotron", Vector3(70.0, 8.0, 0.0), Vector3(140.0, 24.0, 0.0))
	await _shoot("hot_dog_stand", Vector3(20.0, 16.0, -30.0 - out), Vector3(17.0, 12.0, -48.0 - out))
	# The home crowd up, the visitors sunk; then the same a little later.
	var across_eye: Vector3 = Vector3(50.0, 10.0, 6.0)
	stadium.react(true, 1.0)
	await _wait(0.5)
	await _shoot("cheer_home", across_eye, Vector3(50.0, 5.0, -30.0 - out), 0.0)
	await _shoot("cheer_away_sulks", across_eye * Vector3(1.0, 1.0, -1.0), Vector3(50.0, 5.0, 30.0 + out), 0.0)
	stadium.cheer[0] = 0.0
	stadium.slump[1] = 0.0
	stadium.start_wave()
	for i: int in 3:
		await _wait(1.2)
		await _shoot("wave_%d" % i, Vector3(length * 0.5, 60.0, 80.0), Vector3(length * 0.5, 0.0, 0.0), 0.0)
	# The crest of a wave as it passes the middle of the home stand.
	stadium.start_wave()
	stadium._wave_from = 0.25
	stadium.wave_progress = 0.48
	await _wait(0.15)
	await _shoot("wave_close", Vector3(50.0, 9.0, 2.0), Vector3(50.0, 6.0, -30.0 - out), 0.0)
	if stadium.sign_atlas != null and (_only == "" or "signs".contains(_only)):
		stadium.sign_atlas.get_image().save_png(_out_dir.path_join("signs.png"))
	print("STADIUM GALLERY DONE: ", _out_dir, "  fans ", stadium.fan_count)
	_game.free()
	_game = null
	quit(0)


func _shoot(shot_name: String, eye: Vector3, aim: Vector3, settle: float = 0.25) -> void:
	if _only != "" and not shot_name.contains(_only):
		return
	_game.camera_rig.shot(eye, aim, true)
	if settle > 0.0:
		await _wait(settle)
	_game.camera_rig.shot(eye, aim, true)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(shot_name + ".png"))


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
