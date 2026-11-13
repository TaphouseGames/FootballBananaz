extends SceneTree
## Headless check of the box score and the pause menu: the CPU plays whole games,
## and at the end of each the book has to add up (the score from its touchdowns,
## tries and safeties; the players' lines to their team's) and every screen of
## the pause menu has to open.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/stats_check.gd
## Optional user args after "--":
##   games=<n>   play n games (default 1)
##   print       print the box score of every game
##   home=<short name>, away=<short name>   the league teams that play; the
##               scene's own two otherwise

const SPEED: float = 8.0
const STUCK_FRAMES: int = 600

var _game: Game
var _state: StringName = &""
var _state_frames: int = 0
var _games_left: int = 1
var _print: bool = false
## Short names of the league teams to play as home and away, "" for the scene's.
var _teams: PackedStringArray = PackedStringArray(["", ""])
## Frames since the menu was told to close at the end of a game; -1 before that.
var _closing_frames: int = -1
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("games="):
			_games_left = maxi(int(arg.trim_prefix("games=")), 1)
		elif arg == "print":
			_print = true
		elif arg.begins_with("home=") or arg.begins_with("away="):
			_teams[0 if arg.begins_with("home=") else 1] = arg.get_slice("=", 1)
	# See smoke_test.gd: the tick rate goes up with the time scale.
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	_start_game()


func _start_game() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	for i: int in 2:
		if _teams[i] != "":
			Game.team_picks[i] = _game.league.find(_teams[i])
	root.add_child(_game)
	_state = &""
	_state_frames = 0
	_closing_frames = -1


func _process(_delta: float) -> bool:
	if _game == null:
		return true
	if _closing_frames >= 0:
		return _wait_for_resume()
	var now: StringName = _game.play_controller.state_machine.current_name()
	if now != _state:
		_state = now
		_state_frames = 0
	_state_frames += 1
	if _state == &"GameOver":
		_check_book()
		_check_menu()
		_closing_frames = 0
		return false
	if _state_frames > STUCK_FRAMES:
		_failures.append("stuck in state '%s'" % _state)
		return _report()
	return false


## The menu lets go of the pause a frame or two after it is closed.
func _wait_for_resume() -> bool:
	_closing_frames += 1
	if paused and _closing_frames < 10:
		return false
	if paused:
		_failures.append("the game stayed paused after the menu was closed")
		paused = false
	_games_left -= 1
	if _games_left > 0 and _failures.is_empty():
		_game.free()
		_start_game()
		return false
	return _report()


func _check_book() -> void:
	var book: StatBook = _game.stat_book
	var tuning: Tuning = _game.tuning
	var touchdowns: int = 0
	var drives: int = 0
	var possession: float = 0.0
	for team: Team in [_game.home, _game.away]:
		var t: TeamLine = book.team_line(team)
		var who: String = team.short_name
		touchdowns += t.touchdowns
		drives += t.drives
		possession += t.possession
		var points: int = t.touchdowns * tuning.touchdown_points + (t.tries_made + t.tries_returned) * tuning.conversion_points + t.safeties * tuning.safety_points
		_expect(points == team.score, "%s scored %d but the book makes it %d" % [who, team.score, points])
		_expect(t.tries_att == t.touchdowns, "%s: %d touchdowns, %d tries" % [who, t.touchdowns, t.tries_att])

		var sum: PlayerLine = PlayerLine.new()
		var defense: PlayerLine = PlayerLine.new()
		for player: Player in team.players:
			var p: PlayerLine = book.player_line(player)
			sum.pass_att += p.pass_att
			sum.pass_comp += p.pass_comp
			sum.pass_yds += p.pass_yds
			sum.pass_td += p.pass_td
			sum.pass_int += p.pass_int
			sum.sacked += p.sacked
			sum.sacked_yds += p.sacked_yds
			sum.rush_att += p.rush_att
			sum.rush_yds += p.rush_yds
			sum.rush_td += p.rush_td
			sum.rec += p.rec
			sum.rec_yds += p.rec_yds
			sum.rec_td += p.rec_td
			sum.targets += p.targets
			sum.fumbles_lost += p.fumbles_lost
			_expect(p.pass_comp <= p.pass_att and p.rec <= p.targets, "%s: more caught than thrown for %s" % [who, StatBook.label_of(player)])
		for player: Player in team.opponent.players:
			var p: PlayerLine = book.player_line(player)
			defense.sacks += p.sacks
			defense.interceptions += p.interceptions
		_expect(sum.pass_att == t.pass_att and sum.pass_comp == t.pass_comp and sum.pass_yds == t.pass_yds, "%s: passing lines do not add up to the team's" % who)
		_expect(sum.pass_td == t.pass_td and sum.pass_int == t.pass_int, "%s: passing touchdowns or interceptions do not add up" % who)
		_expect(sum.sacked == t.sacked and sum.sacked_yds == t.sacked_yds, "%s: sacks do not add up" % who)
		_expect(sum.rush_att == t.rush_att and sum.rush_yds == t.rush_yds and sum.rush_td == t.rush_td, "%s: rushing lines do not add up" % who)
		_expect(sum.rec == t.pass_comp and sum.rec_yds == t.pass_yds and sum.rec_td == t.pass_td, "%s: receiving does not match passing" % who)
		_expect(sum.targets == t.pass_att, "%s: %d targets for %d passes" % [who, sum.targets, t.pass_att])
		_expect(sum.fumbles_lost == t.fumbles_lost, "%s: fumbles lost do not add up" % who)
		_expect(t.fumbles >= t.fumbles_lost, "%s lost %d fumbles out of %d" % [who, t.fumbles_lost, t.fumbles])
		_expect(t.dives > 0, "%s never dived" % who)
		_expect(t.late_hits >= 0 and t.max_deficit >= 0, "%s: late hits or deficit below zero" % who)
		_expect(book.top_scorer_tds(team) <= t.touchdowns and book.longest_run(team) >= 0 and book.longest_run(team) <= roundi(tuning.field_length),"%s: best scorer or longest run does not fit the team's line" % who)
		_expect(defense.interceptions == t.pass_int, "%s threw %d interceptions, the other team caught %d" % [who, t.pass_int, defense.interceptions])
		_expect(defense.sacks <= t.sacked, "%s was sacked %d times, the other team has %d" % [who, t.sacked, defense.sacks])
		_expect(t.plays == t.pass_att + t.rush_att + t.sacked, "%s: %d plays is not passes + runs + sacks" % [who, t.plays])
		_expect(t.total_yds() == t.pass_yds - t.sacked_yds + t.rush_yds, "%s: total yards" % who)
		_expect(t.third_made <= t.third_att and t.fourth_made <= t.fourth_att, "%s: more downs made than tried" % who)
		_expect(t.red_zone_made <= t.red_zone_att and t.red_zone_att <= t.drives, "%s: red zone %d-%d in %d drives" % [who, t.red_zone_made, t.red_zone_att, t.drives])
		_expect(t.pass_td + t.rush_td + t.return_td == t.touchdowns, "%s: touchdowns by kind do not add up" % who)
		_expect(t.plays > 0, "%s never ran a play" % who)
		# Every table ends with the team's row and is as wide as its heading.
		for table: Array in [
			[StatBook.PASSING_HEAD, book.passing_rows(team)], [StatBook.RUSHING_HEAD, book.rushing_rows(team)],
			[StatBook.RECEIVING_HEAD, book.receiving_rows(team)], [StatBook.DEFENSE_HEAD, book.defense_rows(team)],
		]:
			var head: PackedStringArray = table[0]
			var rows: Array[PackedStringArray] = table[1]
			_expect(not rows.is_empty() and rows[rows.size() - 1][0] == "TEAM", "%s: a table has no team row" % who)
			for row: PackedStringArray in rows:
				_expect(row.size() == head.size(), "%s: a row of %d cells under %d headings" % [who, row.size(), head.size()])
			if _print:
				print(who, " ", head)
				for row: PackedStringArray in rows:
					print("   ", row)
	_expect(touchdowns == _game.get_stat(&"touchdowns"), "%d touchdowns in the book, %d in the game" % [touchdowns, _game.get_stat(&"touchdowns")])
	_expect(drives == _game.get_stat(&"drives"), "%d drives in the book, %d in the game" % [drives, _game.get_stat(&"drives")])
	_expect(possession >= tuning.game_length * 0.9, "only %.0f seconds of possession in the book" % possession)
	if _print:
		for row: Array in book.team_rows():
			print("%-28s %10s %10s" % [("   " if row[3] else "") + str(row[0]), row[1], row[2]])
	print("final: %s %d - %d %s" % [_game.home.short_name, _game.home.score, _game.away.score, _game.away.short_name])


## Opens the pause menu and goes through everything it can show.
func _check_menu() -> void:
	var menu: PauseMenu = _game.hud.pause_menu
	menu.open()
	_expect(paused and menu.is_open() and menu.visible, "opening the menu did not pause the game")
	menu.show_screen(PauseMenu.Screen.BOX_SCORE, 0)
	menu.show_screen(PauseMenu.Screen.BOX_SCORE, 1)
	menu.show_screen(PauseMenu.Screen.TEAM_STATS)
	for side: int in 2:
		menu.show_screen(PauseMenu.Screen.ROSTER, side)
		var team: Team = _game.home if side == 0 else _game.away
		for i: int in team.players.size():
			menu._roster_cursor = i
			menu._refresh()
			var ratings: PlayerRatings = team.players[i].ratings
			_expect(ratings.overall() > 0 and ratings.card_ratings().size() >= 10, "%s has no card" % StatBook.label_of(team.players[i]))
			_expect(ratings.number > 0 and ratings.display_name != "", "player %d of %s has no name or number" % [i, team.short_name])
	menu.show_screen(PauseMenu.Screen.CONTROLS)
	_expect(menu.screen == PauseMenu.Screen.CONTROLS and menu._body.get_child_count() == 1, "the controls screen did not build")
	menu.show_screen(PauseMenu.Screen.MENU)
	var items: Array[String] = menu._items()
	_expect(not items.has(PauseMenu.RESUME) and items.back() == PauseMenu.MAIN_MENU, "the game-over menu should have no resume and end in the main menu")
	menu.close()
	_expect(not menu.visible, "closing the menu left it on screen")


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message):
		_failures.append(message)


func _report() -> bool:
	if _failures.is_empty():
		print("STATS CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("STATS CHECK FAILED: %s" % failure)
		quit(1)
	return true
