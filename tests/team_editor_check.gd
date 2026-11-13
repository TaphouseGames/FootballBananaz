extends SceneTree
## Checks the team editor (tools/team_editor.tscn): edits through its controls
## reach the team, the overall and the team ratings follow, Save writes files
## that read back the same and Revert undoes what was not saved. Saves go to
## copies under user://, never to resources/.
##
## Run:  godot --headless --path . --script res://tests/team_editor_check.gd
## Optional user args after "--":
##   out=<folder>   with a window (no --headless): saves a picture of the editor

const SAVE_DIR: String = "user://team_editor_check"

var _out_dir: String = ""
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
	var scene: PackedScene = load("res://tools/team_editor.tscn")
	var editor: TeamEditor = scene.instantiate() as TeamEditor
	root.add_child(editor)
	_run(editor)


func _run(editor: TeamEditor) -> void:
	await process_frame
	var league: League = editor.league
	_expect(editor.team_list.item_count == league.teams.size(), "the list does not show every team")
	_expect(editor.selected == 0, "the first team is not the one shown at the start")

	editor.select_team(1)
	var team: TeamData = league.teams[1]
	var qb: PlayerRatings = team.roster.players[0]
	var files: PackedStringArray = PackedStringArray([team.resource_path, team.roster.resource_path])
	var before: PackedStringArray = PackedStringArray()
	for path: String in files:
		before.append(FileAccess.get_file_as_string(path))
	var old_name: String = team.team_name
	var old_short: String = team.short_name
	var old_color: Color = team.team_color
	var old_accuracy: int = qb.accuracy
	var old_player: String = qb.display_name
	_expect(editor.name_edit.text == old_name, "the name field does not show the team's name")
	_expect(editor.rating_spins.size() == team.roster.players.size(), "not a column for every player")

	# The team itself.
	_type(editor.name_edit, "Test Town Testers")
	_type(editor.short_edit, "tst")
	var color: Color = Color(0.1, 0.6, 0.3)
	editor.color_button.color = color
	editor.color_button.color_changed.emit(color)
	_expect(team.team_name == "Test Town Testers", "the name typed did not reach the team")
	_expect(team.short_name == "TST" and editor.short_edit.text == "TST", "the short name is not put in capitals")
	_expect(team.team_color.is_equal_approx(color), "the colour picked did not reach the team")
	_expect(editor.dirty[1] and not editor.dirty[0], "the wrong teams are marked as edited")
	_expect(editor.team_list.get_item_text(1) == "TST  *", "the list shows '%s'" % editor.team_list.get_item_text(1))

	# A player.
	var new_accuracy: int = 99 if old_accuracy != 99 else 1
	var spin: SpinBox = editor.rating_spins[0][&"accuracy"]
	spin.value = float(new_accuracy)
	_type(editor.player_name_edits[0], "Testy McTest")
	editor.number_spins[0].value = 42.0
	_expect(qb.accuracy == new_accuracy, "the rating set did not reach the player")
	_expect(qb.display_name == "Testy McTest" and qb.number == 42, "the player's name or number did not reach him")
	_expect(editor.overall_labels[0].text == str(qb.overall()), "the overall did not follow the rating")
	var ratings: Array[Array] = team.roster.team_ratings()
	for row: int in ratings.size():
		var value: int = ratings[row][1]
		_expect(roundi(editor.rating_bars[row].value) == value, "the bar for %s did not follow the rating" % ratings[row][0])

	# A short name another team has is pointed out.
	_type(editor.short_edit, league.teams[0].short_name)
	_expect(editor.status.text.contains("also the short name"), "a short name used twice is not pointed out")
	_type(editor.short_edit, "TST")

	# Saved copies read back the same, and the real files are as they were.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	editor.save_dir = SAVE_DIR
	_expect(editor.save_all(), "saving failed: %s" % editor.status.text)
	_expect(not editor.dirty[1], "the team is still marked as edited after the save")
	var team_copy: TeamData = _load_copy(files[0]) as TeamData
	var roster_copy: Roster = _load_copy(files[1]) as Roster
	if team_copy == null or roster_copy == null:
		_failures.append("the saved files do not load")
	else:
		_expect(team_copy.team_name == "Test Town Testers" and team_copy.short_name == "TST", "the saved team has other names")
		_expect(team_copy.team_color.is_equal_approx(color), "the saved team has another colour")
		_expect(team_copy.roster != null, "the saved team has lost its roster")
		_expect(roster_copy.players.size() == team.roster.players.size(), "the saved roster has lost players")
		var saved_qb: PlayerRatings = roster_copy.players[0]
		_expect(saved_qb.accuracy == new_accuracy and saved_qb.number == 42 and saved_qb.display_name == "Testy McTest", "the saved player has other values")
		_expect(saved_qb.position == "QB" and saved_qb.speed == qb.speed, "the saved player lost what was not edited")
	for i: int in files.size():
		_expect(FileAccess.get_file_as_string(files[i]) == before[i], "%s was written to" % files[i])

	if _out_dir != "":
		DirAccess.make_dir_recursive_absolute(_out_dir)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out_dir.path_join("team_editor.png"))
		print("saved team_editor.png")

	# Revert: back to what the real files say.
	editor.revert_selected()
	_expect(team.team_name == old_name and team.short_name == old_short, "revert did not bring the names back")
	_expect(team.team_color.is_equal_approx(old_color), "revert did not bring the colour back")
	_expect(qb.accuracy == old_accuracy and qb.display_name == old_player, "revert did not bring the player back")
	_expect(editor.name_edit.text == old_name, "the name field does not show the reverted name")
	var reverted: SpinBox = editor.rating_spins[0][&"accuracy"]
	_expect(roundi(reverted.value) == old_accuracy, "the rating shown is not the reverted one")

	for failure: String in _failures:
		print("FAIL: ", failure)
	print("team editor check: ", "PASSED" if _failures.is_empty() else "FAILED")
	quit(0 if _failures.is_empty() else 1)


## Setting a LineEdit's text from code says nothing: this is somebody typing it.
func _type(edit: LineEdit, text: String) -> void:
	edit.text = text
	edit.text_changed.emit(text)


func _load_copy(path: String) -> Resource:
	var copy: String = SAVE_DIR.path_join(path.trim_prefix("res://").replace("/", "_"))
	return ResourceLoader.load(copy, "", ResourceLoader.CACHE_MODE_IGNORE)


func _expect(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
