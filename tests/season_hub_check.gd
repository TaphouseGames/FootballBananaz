extends SceneTree
## Check of the season on the main menu (SeasonHub) and of a game of it on the
## field. SEASON with no season on asks for a team; down and (A) start one as
## the league's second team; every page builds; (A) on THIS WEEK loads the
## match as a game of the season, the person on their own team against the
## opponent the schedule names; the final whistle books the result and plays
## the rest of the week on paper; the pause menu's way out reads BACK TO
## SEASON; and the menu comes back up on the season's screen, a week on.
##
## The season goes to a file of its own, never the person's.
## With `out=<dir>` (and a window, so no --headless) it first plays some weeks
## on paper and saves a picture of the team choice and of each page.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/season_hub_check.gd

const SAVE_PATH: String = "user://season_hub_check.cfg"
const STORY_PATH: String = "user://season_hub_check_story.cfg"
## Frames between one press and the look at what it did.
const STEP_FRAMES: int = 12
## Long enough for the booth's send-off and the fade into the match.
const WAIT_FRAMES: int = 600
## Weeks played on paper before the pictures are taken.
const PICTURE_WEEKS: int = 6
## Times round the league the paper seasons are played at most.
const PASSES: int = 8

var _menu: MainMenu
var _frame: int = 0
var _step: int = 0
var _waiting: StringName = &""
var _waited: int = 0
var _fixture: Array = []
var _out: String = ""
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
	Season.save_path = SAVE_PATH
	BoothStory.save_path = STORY_PATH
	Season.clear()
	Game.season_match = false
	_load_menu()
	process_frame.connect(_tick)


func _load_menu() -> void:
	var scene: PackedScene = load("res://scenes/main_menu.tscn")
	_menu = scene.instantiate() as MainMenu
	root.add_child(_menu)
	current_scene = _menu


func _tick() -> void:
	_frame += 1
	if _waiting == &"match":
		_wait_for_match()
		return
	if _waiting == &"menu":
		_wait_for_menu()
		return
	if _frame < 20 or _frame % STEP_FRAMES != 0:
		return
	_step += 1
	var hub: SeasonHub = _menu.season_hub
	match _step:
		1:
			_expect(_menu.season_button.has_focus() and _menu.season_button.text == "SEASON", "SEASON is not the button in focus")
			_press(JOY_BUTTON_A)
		2:
			_expect(hub != null and hub.visible and hub.mode == SeasonHub.Mode.PICK, "SEASON did not ask for a team")
			_expect(Season.current == null, "there is a season before a team was picked")
			_expect(not _menu.season_button.is_visible_in_tree(), "the buttons are still up behind the season")
			_save("pick")
			_press(JOY_BUTTON_DPAD_DOWN)
		3:
			_expect(hub.pick_cursor == 1, "down did not move to the second team")
			_press(JOY_BUTTON_A)
		4:
			var season: Season = Season.current
			_expect(season != null and season.user_team == 1, "the season did not start as the second team")
			_expect(hub.mode == SeasonHub.Mode.PAGES and hub.page == SeasonHub.Page.WEEK, "the season did not open on THIS WEEK")
			if season != null and _out != "":
				for week: int in PICTURE_WEEKS:
					var own: Array = season.fixture()
					SeasonSim.play(season, own[0], own[1])
					season.finish_round()
				hub.refresh()
		5:
			_save("week")
			_press(JOY_BUTTON_RIGHT_SHOULDER)
		6:
			_expect(hub.page == SeasonHub.Page.STANDINGS, "RB did not turn to STANDINGS")
			_save("standings")
			_press(JOY_BUTTON_RIGHT_SHOULDER)
		7:
			_expect(hub.page == SeasonHub.Page.TEAMS, "RB did not turn to TEAM STATS")
			_save("teams")
			_press(JOY_BUTTON_RIGHT_SHOULDER)
		8:
			_expect(hub.page == SeasonHub.Page.PLAYERS and hub.players_view == -1, "RB did not turn to the leaders")
			_save("leaders")
			_press(JOY_BUTTON_A)
		9:
			_expect(hub.players_view == 0, "(A) on PLAYER STATS did not go to the first team")
			_save("players")
			_press(JOY_BUTTON_RIGHT_SHOULDER)
		10:
			_expect(hub.page == SeasonHub.Page.SCHEDULE, "RB did not turn to SCHEDULE")
			_save("schedule")
			_press(JOY_BUTTON_Y)
		11:
			_expect(Season.current != null, "one press of (Y) threw the season away")
			_press(JOY_BUTTON_B)
		12:
			_expect(hub.visible and Season.current != null, "(B) on the question left the season's screen")
			_press(JOY_BUTTON_RIGHT_SHOULDER)
		13:
			_expect(hub.page == SeasonHub.Page.WEEK, "the pages do not go round")
			_fixture = Season.current.fixture()
			_expect(not _fixture.is_empty(), "the person has no game to play")
			_press(JOY_BUTTON_A)
			_waiting = &"match"
			_waited = 0
		14:
			# Back on the menu after the game.
			_expect(hub != null and hub.visible and hub.page == SeasonHub.Page.WEEK, "the menu did not come back up on the season's screen")
			_expect(not _menu.season_button.is_visible_in_tree(), "the buttons are up behind the season's screen")
			_save("after")
			_press(JOY_BUTTON_B)
		15:
			_expect(not hub.visible and _menu.season_button.has_focus(), "(B) did not go back to the title")
			_expect(_menu.season_button.text == "CONTINUE SEASON", "the button reads %s with a season on" % _menu.season_button.text)
			_check_playoff_pages(hub)
		16:
			_save("champion")
			_finish()


## The match loads as the person's game of the week; it is then cut short at
## the final whistle with a score on the board.
func _wait_for_match() -> void:
	_waited += 1
	var game: Game = current_scene as Game
	if game == null or not game.is_node_ready() or game.offense == null:
		if _waited > WAIT_FRAMES:
			_failures.append("(A) on THIS WEEK did not load the match")
			_finish()
		return
	var season: Season = Season.current
	var before: int = season.week
	_expect(Game.season_match and game.season() == season, "the match is not a game of the season")
	_expect(game.season_round == before and not game.is_playoff(), "the match does not know its round")
	_expect(game.home.short_name == season.teams[_fixture[0]] and game.away.short_name == season.teams[_fixture[1]], "the match is %s against %s, not the week's game" % [game.home.short_name, game.away.short_name])
	_expect(game.human.team != null and game.human.team.short_name == season.teams[season.user_team], "the person is not on their own team")
	_expect(game.audio.story_on, "the booth's story is off in a game of the season")
	game.home.score = 14
	game.away.score = 6
	game.half = 2
	game.clock = 0.0
	game.play_controller.state_machine.transition(&"GameOver")
	_expect(season.week == before + 1, "the final whistle did not move the season on")
	_expect(season.results_of_round(before).size() == 3, "the week has %d results, not 3" % season.results_of_round(before).size())
	var result: Dictionary = season.result_of(before, _fixture[0], _fixture[1])
	_expect(not result.is_empty() and result["home_score"] == 14 and result["away_score"] == 6, "the result booked is not the one on the board")
	_expect(season.team_line(_fixture[0]).games == before + 1,"the home team's line does not have the game")
	var menu: PauseMenu = game.hud.pause_menu
	menu.open()
	_expect(_labels(menu).has("BACK TO SEASON"), "the pause menu does not read BACK TO SEASON")
	menu.close(true)
	_waiting = &"menu"
	_waited = 0


func _wait_for_menu() -> void:
	_waited += 1
	var menu: MainMenu = current_scene as MainMenu
	if menu == null or not menu.is_node_ready():
		if _waited > WAIT_FRAMES:
			_failures.append("the way out of the match did not lead to the menu")
			_finish()
		return
	_menu = menu
	_waiting = &""
	# The step counter carries on from the frame the menu is back.
	_frame = 20 - (20 % STEP_FRAMES)


## Whole seasons on paper as each team in turn: every page builds in every
## round, the week off and the season being over are said in so many words, and
## with nothing to play (A) moves the round on. Left on the last season's
## last page, with its champion.
func _check_playoff_pages(hub: SeasonHub) -> void:
	var seen: Dictionary[String, bool] = {}
	# Who finishes first is down to the dice, so more seasons are played until
	# the person has had both a week off and an early end (PASSES at most).
	for turn: int in _menu.league.teams.size() * PASSES:
		var team: int = turn % _menu.league.teams.size()
		if turn >= _menu.league.teams.size() and seen.has("bye") and seen.has("out"):
			break
		var season: Season = Season.start(_menu.league, team)
		hub.open()
		var rounds: int = 0
		while not season.is_over() and rounds < 20:
			rounds += 1
			for page: int in SeasonHub.PAGE_NAMES.size():
				hub.page = page as SeasonHub.Page
				hub.refresh()
			hub.page = SeasonHub.Page.WEEK
			hub.refresh()
			var texts: String = " | ".join(_labels(hub))
			var own: Array = season.fixture()
			if not own.is_empty():
				SeasonSim.play(season, own[0], own[1])
				season.finish_round()
				continue
			var before: int = season.current_round()
			if season.on_bye(team):
				seen["bye"] = true
				_expect(texts.contains("HAVE THE WEEK OFF"), "the first seed's week off is not on the screen")
			else:
				seen["out"] = true
				_expect(texts.contains("YOUR SEASON IS OVER"), "the end of the person's season is not on the screen")
			_expect(texts.contains("SIMULATE"), "with nothing to play the screen does not offer to simulate")
			_press_now(hub, &"confirm")
			_expect(season.is_over() or season.current_round() == before + 1, "(A) with nothing to play did not move the round on")
		hub.page = SeasonHub.Page.SCHEDULE
		hub.refresh()
		_expect(" | ".join(_labels(hub)).contains(Season.CUP_NAME), "the schedule does not name the cup")
		hub.page = SeasonHub.Page.WEEK
		hub.refresh()
		_expect(" | ".join(_labels(hub)).contains("ARE THE CHAMPIONS"), "the champions are not on the screen")
		seen["champion" if season.champion == team else "not champion"] = true
	_expect(seen.has("bye") and seen.has("out"), "the seasons never had the person on a week off and out of the playoffs (%s)" % [seen.keys()])


## An action pressed and handed straight to `hub`, not left for the next frame.
func _press_now(hub: SeasonHub, action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	hub._unhandled_input(event)


func _finish() -> void:
	process_frame.disconnect(_tick)
	Season.clear()
	Game.season_match = false
	Game.human_side = -1
	Game.team_picks = PackedInt32Array([-1, -1])
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("season hub check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


## Every text written under `node`.
func _labels(node: Node) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for child: Node in node.find_children("*", "Label", true, false):
		found.append((child as Label).text)
	return found


func _press(button: JoyButton) -> void:
	for down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)


func _save(name: String) -> void:
	if _out == "":
		return
	var path: String = _out.path_join("season_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
