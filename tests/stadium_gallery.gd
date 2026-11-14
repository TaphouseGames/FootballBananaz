extends SceneTree
## Pictures of the stadium: the game camera at both ends and midfield, the
## looks across at each stand, the intro's opening shot, close-ups of the
## crowd and the props, then a home cheer and a wave. Needs a window (no
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
	await _wait(2.0)
	var stadium: Stadium = _game.field.stadium
	# The game's own camera, behind a player at these places.
	await _shoot("cam_own_goal", Vector3(-8.0, 0.0, 0.0) + back, Vector3(-8.0, 0.0, 0.0) + ahead)
	await _shoot("cam_midfield", Vector3(50.0, 0.0, 0.0) + back, Vector3(50.0, 0.0, 0.0) + ahead)
	await _shoot("cam_sideline", Vector3(50.0, 0.0, 17.0) + back, Vector3(50.0, 0.0, 17.0) + ahead)
	await _shoot("cam_red_zone", Vector3(88.0, 0.0, -8.0) + back, Vector3(88.0, 0.0, -8.0) + ahead)
	await _shoot("cam_other_way", Vector3(60.0, 0.0, 0.0) + back * flip, Vector3(60.0, 0.0, 0.0) + ahead * flip)
	# Half way round a swing: looking across at each stand.
	await _shoot("swing_home_stand", Vector3(50.0, t.camera_height, t.camera_distance), Vector3(50.0, 0.0, -t.camera_look_ahead))
	await _shoot("swing_away_stand", Vector3(50.0, t.camera_height, -t.camera_distance), Vector3(50.0, 0.0, t.camera_look_ahead))
	await _shoot("intro_start", Vector3(50.0 - 38.0, 24.0, 54.0), Vector3(59.0, 1.5, 0.0))
	await _shoot("overview", Vector3(length * 0.5, 120.0, 150.0), Vector3(length * 0.5, 0.0, 0.0))
	await _shoot("crowd_close", Vector3(40.0, 4.0, -18.0), Vector3(47.0, 5.0, -32.0))
	await _shoot("fans_front", Vector3(45.0, 3.2, -22.5), Vector3(45.0, 3.0, -30.0))
	await _shoot("signs_close", Vector3(60.0, 7.5, -16.0), Vector3(62.0, 7.0, -34.0))
	await _shoot("aisle_close", Vector3(55.0, 9.0, 12.0), Vector3(62.0, 6.0, 32.0))
	await _shoot("corner", Vector3(80.0, 6.0, 0.0), Vector3(116.0, 6.0, 26.0))
	await _shoot("mascot", Vector3(42.0, 2.5, -14.0), Vector3(36.0, 1.5, -23.0))
	await _shoot("mascot_away", Vector3(58.0, 2.5, 14.0), Vector3(64.0, 1.5, 23.0))
	# Both from the game camera at midfield, then each in turn up close:
	# cheering, sulking, waving.
	await _shoot("mascots_cam", Vector3(40.0, 0.0, 0.0) + back, Vector3(40.0, 0.0, 0.0) + ahead)
	var close_home: Array[Vector3] = [Vector3(38.5, 1.8, -19.0), Vector3(36.0, 1.5, -24.5)]
	var close_away: Array[Vector3] = [Vector3(61.5, 1.8, 19.0), Vector3(64.0, 1.5, 24.5)]
	stadium.react(true, 1.0)
	await _wait(0.45)
	await _shoot("mascot_cheer", close_home[0], close_home[1], 0.0)
	await _shoot("mascot_away_sulk", close_away[0], close_away[1], 0.3)
	stadium.cheer[0] = 0.0
	stadium.slump[1] = 0.0
	stadium.start_wave()
	await _wait(0.6)
	await _shoot("mascot_wave", close_home[0], close_home[1], 0.0)
	stadium.wave_progress = -1.0
	await _wait(0.5)
	await _shoot("jumbotron", Vector3(70.0, 8.0, 0.0), Vector3(140.0, 24.0, 0.0))
	await _shoot("hot_dog_stand", Vector3(20.0, 16.0, -30.0), Vector3(17.0, 12.0, -48.0))
	# The home crowd up, the visitors sunk; then the same a little later.
	var across_eye: Vector3 = Vector3(50.0, 10.0, 6.0)
	stadium.react(true, 1.0)
	await _wait(0.5)
	await _shoot("cheer_home", across_eye, Vector3(50.0, 5.0, -30.0), 0.0)
	await _shoot("cheer_away_sulks", across_eye * Vector3(1.0, 1.0, -1.0), Vector3(50.0, 5.0, 30.0), 0.0)
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
	await _shoot("wave_close", Vector3(50.0, 9.0, 2.0), Vector3(50.0, 6.0, -30.0), 0.0)
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
