extends SceneTree
## Screenshots of the two kits: a home player (white with a band of the team
## colour) and an away player (the team colour all over) from the front and the
## back, and both teams lined up. Needs a window (no --headless).
##
## Run:  godot --path . --script res://tests/kit_gallery.gd -- out=<folder>
## Optional user args after "--":
##   home=<short name>, away=<short name>   the league teams to dress

var _out_dir: String = "user://kit_gallery"
var _teams: PackedStringArray = PackedStringArray(["", ""])
var _game: Game
var _cam: Camera3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("home=") or arg.begins_with("away="):
			_teams[0 if arg.begins_with("home=") else 1] = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	for i: int in 2:
		if _teams[i] != "":
			Game.team_picks[i] = _game.league.find(_teams[i])
	root.add_child(_game)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_run()


func _run() -> void:
	await create_timer(0.5).timeout
	var pc: PlayController = _game.play_controller
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 50.0))
	pc.line_up(_game.offense_playbook.plays[0], _game.defense_playbook.plays[0])
	await physics_frame
	await physics_frame
	paused = true
	var names: String = "%s_%s" % [_game.home.short_name.to_lower(), _game.away.short_name.to_lower()]
	for team: Team in [_game.home, _game.away]:
		var player: Player = team.players[4]
		var side: Vector3 = Vector3(-player.facing.z, 0.0, player.facing.x)
		for other: Player in pc.players:
			other.visible = other == player
		var kit: String = "home" if team == _game.home else "away"
		await _shot("%s_%s_front" % [names, kit], player.position + player.facing * 4.2 + side * 1.2 + Vector3(0.0, 1.7, 0.0), player.position + Vector3(0.0, 1.0, 0.0))
		await _shot("%s_%s_back" % [names, kit], player.position - player.facing * 4.2 + side * 1.2 + Vector3(0.0, 1.7, 0.0), player.position + Vector3(0.0, 1.0, 0.0))
		for other: Player in pc.players:
			other.visible = true
	var mid: Vector3 = Vector3(_game.los_x, 0.0, 0.0)
	await _shot("%s_field" % names, mid + Vector3(-4.0, 14.0, 20.0), mid)
	Game.team_picks = PackedInt32Array([-1, -1])
	quit(0)


func _shot(label: String, eye: Vector3, target: Vector3) -> void:
	_cam.look_at_from_position(eye, target, Vector3.UP)
	_cam.reset_physics_interpolation()
	_cam.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(label + ".png"))
	print("saved ", label)
