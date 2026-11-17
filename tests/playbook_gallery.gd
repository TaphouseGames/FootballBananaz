extends SceneTree
## Screenshots of the play-select screen: every tab of the offense playbook (or
## the defense's) with its cards and diagrams, and the line-up of every play on
## one tab seen from above. Needs a window (no --headless).
##
## Run:  godot --path . --resolution 1280x720 --script res://tests/playbook_gallery.gd -- out=<folder>
## Optional user args after "--":
##   defense        the defense playbook's tabs instead of the offense's
##   lineups=<tab>  also the line-up of every play on the tab whose name
##                  contains the text (e.g. lineups=heavy), against the first
##                  defensive play. With `defense`: every defensive play on
##                  that tab (e.g. lineups=zone) against one offensive formation
##   against=<tab>  the offensive formation the defensive plays line up
##                  against (default: gun trips)

var _out_dir: String = "user://playbook_gallery"
var _defense: bool = false
var _lineups: String = ""
var _against: String = "gun trips"
var _game: Game
var _cam: Camera3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
		elif arg == "defense":
			_defense = true
		elif arg.begins_with("against="):
			_against = arg.trim_prefix("against=").to_lower()
		elif arg.begins_with("lineups="):
			_lineups = arg.trim_prefix("lineups=").to_lower()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	_run()


func _run() -> void:
	await create_timer(0.5).timeout
	var pc: PlayController = _game.play_controller
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 40.0))
	pc.line_up(_game.offense_playbook.plays[0], _game.defense_playbook.plays[0])
	await physics_frame
	await physics_frame
	paused = true

	var names: PackedStringArray = DefensePlay.GROUP_NAMES if _defense else OffensePlay.GROUP_NAMES
	var groups: Array[Array] = []
	for i: int in names.size():
		groups.append([])
	if _defense:
		for play: DefensePlay in _game.defense_playbook.plays:
			groups[play.group].append(play)
	else:
		for play: OffensePlay in _game.offense_playbook.plays:
			groups[play.group].append(play)
	for tab: int in names.size():
		var plays: Array[Resource] = []
		plays.assign(groups[tab])
		_game.hud.show_play_select("DEFENSE" if _defense else "OFFENSE", names, tab, plays)
		await _shot("%s_tab_%d_%s" % ["defense" if _defense else "offense", tab, names[tab].to_lower().replace(" ", "_")])
	_game.hud.hide_play_select()

	if _lineups != "" and not _defense:
		_cam = Camera3D.new()
		_cam.fov = 40.0
		root.add_child(_cam)
		for tab: int in names.size():
			if not names[tab].to_lower().contains(_lineups):
				continue
			for play: OffensePlay in groups[tab]:
				pc.line_up(play, _game.defense_playbook.plays[0])
				var mid: Vector3 = Vector3(_game.los_x, 0.0, 0.0)
				_cam.look_at_from_position(mid + Vector3(-float(_game.offense.attack_dir) * 16.0, 24.0, 0.0), mid, Vector3.UP)
				_cam.make_current()
				await _shot("lineup_%s" % play.play_name.to_lower().replace(" ", "_"))
	if _lineups != "" and _defense:
		# The first play of the offensive formation: they all line up the same.
		var offense_play: OffensePlay = _game.offense_playbook.plays[0]
		for play: OffensePlay in _game.offense_playbook.plays:
			if OffensePlay.GROUP_NAMES[play.group].to_lower().contains(_against):
				offense_play = play
				break
		_cam = Camera3D.new()
		_cam.fov = 40.0
		root.add_child(_cam)
		for tab: int in names.size():
			if not names[tab].to_lower().contains(_lineups):
				continue
			for play: DefensePlay in groups[tab]:
				pc.line_up(offense_play, play)
				var mid: Vector3 = Vector3(_game.los_x + float(_game.offense.attack_dir) * 6.0, 0.0, 0.0)
				_cam.look_at_from_position(mid + Vector3(-float(_game.offense.attack_dir) * 20.0, 34.0, 0.0), mid, Vector3.UP)
				_cam.make_current()
				await _shot("defense_%s_vs_%s" % [play.play_name.to_lower().replace(" ", "_"), _against.replace(" ", "_")])
	quit(0)


func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(label + ".png")
	image.save_png(path)
	print("saved %s" % path)
