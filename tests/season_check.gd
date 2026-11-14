extends SceneTree
## Headless check of the season (Season, SeasonSim). No match is played on the
## field: every game is played on paper.
##
## - The schedule: ten weeks, every team once a week, every pair twice, once at
##   each ground.
## - A whole season: nobody ties, every team has ten results, the league's
##   points for and against are the same, each team's and each footballer's
##   numbers add up the way a real box score does (as tests/stats_check.gd
##   asks of one), the table is in order, the best three are seeded, the
##   second hosts the third, the winner goes to the first, and there is a
##   champion.
## - The save: read back, it is the same season, at every stage.
## - The person's own game holds the round up until it is booked.
## - A new season starts the booth's stories over.
##
## With `sim=<n>` it also plays n games on paper and prints what an average
## one looks like, to set SeasonSim's numbers against the real thing
## (tests/stats_check.gd -- print).
##
## Run:  godot --headless --path . --script res://tests/season_check.gd [-- sim=200]

const SAVE_PATH: String = "user://season_check.cfg"
const STORY_PATH: String = "user://season_check_story.cfg"
const SEASONS: int = 5

var _league: League
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var sim_games: int = 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("sim="):
			sim_games = int(arg.trim_prefix("sim="))
	Season.save_path = SAVE_PATH
	BoothStory.save_path = STORY_PATH
	_league = load("res://resources/league.tres") as League
	_expect(_league != null and _league.teams.size() == 6, "the league does not have six teams")
	if _league != null:
		_check_schedule()
		for i: int in SEASONS:
			_check_season(i % _league.teams.size())
		_check_own_game()
		_check_story()
		if sim_games > 0:
			_print_average(sim_games)
	Season.clear()
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("season check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


func _check_schedule() -> void:
	for attempt: int in 20:
		var schedule: Array[Array] = Season.make_schedule(6)
		_expect(schedule.size() == Season.WEEKS, "the schedule has %d weeks" % schedule.size())
		var meetings: Dictionary[String, int] = {}
		for games: Array in schedule:
			var busy: Dictionary[int, bool] = {}
			_expect(games.size() == 3, "a week has %d games" % games.size())
			for game: Array in games:
				_expect(game[0] != game[1], "a team plays itself")
				_expect(not busy.has(game[0]) and not busy.has(game[1]), "a team plays twice in a week")
				busy[game[0]] = true
				busy[game[1]] = true
				var key: String = "%d at %d" % [game[1], game[0]]
				meetings[key] = meetings.get(key, 0) + 1
		_expect(meetings.size() == 30, "%d different fixtures, not 30" % meetings.size())
		# In each half of the season a team is at home two or three times of five.
		for half: int in 2:
			var at_home: Dictionary[int, int] = {}
			for games: Array in schedule.slice(half * 5, half * 5 + 5):
				for game: Array in games:
					at_home[game[0]] = at_home.get(game[0], 0) + 1
			for team: int in 6:
				_expect(at_home.get(team, 0) == 2 or at_home.get(team, 0) == 3, "a team is at home %d times in half a season" % at_home.get(team, 0))
		for key: String in meetings:
			_expect(meetings[key] == 1, "%s is played %d times" % [key, meetings[key]])


## A whole season with nobody playing: `team` is the person's, and its games
## go to the paper too.
func _check_season(team: int) -> void:
	var season: Season = Season.start(_league, team)
	_expect(Season.current == season, "the new season is not the current one")
	var rounds: int = 0
	while not season.is_over() and rounds < 20:
		var before: int = season.current_round()
		var own: Array = season.fixture()
		if rounds < Season.WEEKS:
			_expect(season.phase == Season.Phase.REGULAR and season.round_name() == "WEEK %d" % (rounds + 1), "round %d is called %s" % [rounds, season.round_name()])
			_expect(not own.is_empty(), "the person has no game in week %d" % (rounds + 1))
		if not own.is_empty():
			season.finish_round()
			_expect(season.current_round() == before and not season.is_over(), "the round went by without the person's game")
			SeasonSim.play(season, own[0], own[1])
			_expect(season.fixture().is_empty(), "the person's game is still to play after it was booked")
		season.finish_round()
		rounds += 1
		_expect_same_after_reload(season)
		if rounds == Season.WEEKS:
			_check_table(season)
	_expect(rounds == 12, "the season took %d rounds, not 12" % rounds)
	_expect(season.is_over() and season.champion >= 0, "the season has no champion")
	if season.seeds.size() == Season.PLAYOFF_TEAMS:
		var semifinal: Dictionary = season.result_of(Season.SEMIFINAL_ROUND, season.seeds[1], season.seeds[2])
		_expect(not semifinal.is_empty(), "the second seed did not host the third")
		if not semifinal.is_empty():
			_expect(season.semifinal_winner == Season.winner_of(semifinal), "the wrong team went on from the semifinal")
		var final: Dictionary = season.result_of(Season.FINAL_ROUND, season.seeds[0], season.semifinal_winner)
		_expect(not final.is_empty(), "the first seed did not host the final")
		if not final.is_empty():
			_expect(season.champion == Season.winner_of(final), "the champion did not win the final")
		_expect(season.results.size() == 32, "%d games were played, not 32" % season.results.size())
	_check_lines(season)


## The table at the end of the regular season.
func _check_table(season: Season) -> void:
	var rows: Array[Dictionary] = season.standings()
	var points_for: int = 0
	var points_against: int = 0
	var wins: int = 0
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		_expect(row["wins"] + row["losses"] == Season.WEEKS, "%s has %d results" % [season.teams[row["team"]], row["wins"] + row["losses"]])
		_expect(row["place"] == i + 1, "the table's places are out of order")
		if i > 0:
			_expect(rows[i - 1]["wins"] >= row["wins"], "a team with fewer wins is higher in the table")
		points_for += row["pf"]
		points_against += row["pa"]
		wins += row["wins"]
		_expect(season.record_text(row["team"]) == "%d-%d" % [row["wins"], row["losses"]], "record_text() disagrees with the table")
		_expect(season.place_of(row["team"]) == i + 1, "place_of() disagrees with the table")
	_expect(points_for == points_against, "the league scored %d and gave up %d" % [points_for, points_against])
	_expect(wins == 30, "%d wins in 30 games" % wins)
	_expect(season.phase == Season.Phase.SEMIFINAL, "the playoffs did not start after week ten")
	_expect(season.seeds.size() == Season.PLAYOFF_TEAMS, "%d teams were seeded" % season.seeds.size())
	for i: int in mini(season.seeds.size(), rows.size()):
		_expect(season.seeds[i] == rows[i]["team"], "seed %d is not the team in place %d" % [i + 1, i + 1])
	if season.seeds.size() == Season.PLAYOFF_TEAMS:
		_expect(season.on_bye(season.seeds[0]) and not season.on_bye(season.seeds[1]), "the first seed does not have the week off")
		_expect(season.round_games() == [[season.seeds[1], season.seeds[2]]], "the semifinal is not second against third")
		_expect(not season.alive(rows[3]["team"]) and season.alive(season.seeds[2]), "alive() is wrong about who made the playoffs")
	for result: Dictionary in season.results:
		_expect(result["home_score"] != result["away_score"], "a game ended level")


## Every team's numbers against its results and its footballers' numbers.
func _check_lines(season: Season) -> void:
	var tuning: Tuning = Tuning.new()
	for team: int in season.teams.size():
		var who: String = season.teams[team]
		var t: TeamLine = season.team_line(team)
		var games: int = 0
		var scored: int = 0
		var given_up: int = 0
		var overtime_wins: int = 0
		for result: Dictionary in season.results:
			for side: String in ["home", "away"]:
				if result[side] == team:
					games += 1
					scored += result[side + "_score"]
					given_up += result[("away" if side == "home" else "home") + "_score"]
					if result["overtime"] and Season.winner_of(result) == team:
						overtime_wins += 1
		_expect(t.games == games and games >= Season.WEEKS, "%s: the line has %d games, the results %d" % [who, t.games, games])
		_expect(t.points_for == scored and t.points_against == given_up, "%s: points do not match the results" % who)
		var points: int = t.touchdowns * tuning.touchdown_points + (t.tries_made + t.tries_returned) * tuning.conversion_points + t.safeties * tuning.safety_points
		_expect(points == scored, "%s scored %d but its line makes it %d" % [who, scored, points])
		_expect(t.tries_att == t.touchdowns - overtime_wins, "%s: %d touchdowns, %d tries, %d wins in overtime" % [who, t.touchdowns, t.tries_att, overtime_wins])
		var sum: PlayerLine = PlayerLine.new()
		var count: int = season.team_data(team).roster.players.size()
		for index: int in count:
			var p: PlayerLine = season.player_line(team, index)
			_expect(p.pass_comp <= p.pass_att and p.rec <= p.targets, "%s: more caught than thrown" % who)
			sum.add(p)
		_expect(sum.pass_att == t.pass_att and sum.pass_comp == t.pass_comp and sum.pass_yds == t.pass_yds, "%s: passing lines do not add up to the team's" % who)
		_expect(sum.pass_td == t.pass_td and sum.pass_int == t.pass_int, "%s: passing touchdowns or interceptions do not add up" % who)
		_expect(sum.sacked == t.sacked and sum.sacked_yds == t.sacked_yds, "%s: sacks do not add up" % who)
		_expect(sum.rush_att == t.rush_att and sum.rush_yds == t.rush_yds and sum.rush_td == t.rush_td, "%s: rushing lines do not add up" % who)
		_expect(sum.rec == t.pass_comp and sum.rec_yds == t.pass_yds and sum.rec_td == t.pass_td, "%s: receiving does not match passing" % who)
		_expect(sum.targets == t.pass_att, "%s: %d targets for %d passes" % [who, sum.targets, t.pass_att])
		_expect(sum.fumbles_lost == t.fumbles_lost and sum.return_td == t.return_td, "%s: fumbles or returns do not add up" % who)
		_expect(t.touchdowns >= t.pass_td + t.rush_td + t.return_td, "%s: more touchdowns in the parts than in all" % who)


## The season on file is the one in hand.
func _expect_same_after_reload(season: Season) -> void:
	var loaded: Season = Season.load_saved(_league)
	if loaded == null:
		_failures.append("the season could not be read back in round %d" % season.current_round())
		Season.current = season
		return
	var same: bool = loaded.teams == season.teams and loaded.user_team == season.user_team and loaded.phase == season.phase \
			and loaded.week == season.week and loaded.seeds == season.seeds and loaded.champion == season.champion \
			and loaded.semifinal_winner == season.semifinal_winner and loaded.schedule == season.schedule \
			and loaded.results.size() == season.results.size() and loaded.standings() == season.standings()
	for team: int in season.teams.size():
		same = same and _same_numbers(loaded.team_line(team).to_dict(), season.team_line(team).to_dict())
	for key: String in season.player_lines:
		same = same and loaded.player_lines.has(key) and _same_numbers(loaded.player_lines[key].to_dict(), season.player_lines[key].to_dict())
	_expect(same, "the season read back is not the one saved (round %d)" % season.current_round())
	Season.current = season


## The two hold the same numbers: a float comes back from the file a hair off.
func _same_numbers(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: String in a:
		if not b.has(key) or absf(float(a[key]) - float(b[key])) > 0.01:
			return false
	return true


## A result that is level is not booked, and one booked twice counts once.
func _check_own_game() -> void:
	var season: Season = Season.start(_league, 2)
	var own: Array = season.fixture()
	_expect(own.has(2), "the person's game is not their team's")
	var lines: Array[TeamLine] = [TeamLine.new(), TeamLine.new()]
	var players: Array[Array] = [[], []]
	season.record(own[0], own[1], 20, 20, false, lines, players)
	_expect(season.results.is_empty(), "a level game was booked")
	season.record(own[0], own[1], 28, 20, false, lines, players)
	season.record(own[0], own[1], 6, 40, false, [TeamLine.new(), TeamLine.new()], players)
	_expect(season.results.size() == 1 and season.team_line(own[0]).points_for == 28, "a game was booked twice")
	_expect(season.record_text(own[0]) == "1-0" and season.record_text(own[1]) == "0-1", "the records after one game are wrong")
	season.finish_round()
	_expect(season.week == 1 and season.results.size() == 3, "the week did not finish after the person's game")


func _check_story() -> void:
	BoothStory.reset()
	var first: Dictionary = BoothStory.next(BoothStory.CAROL)
	BoothStory.mark_heard(first[&"id"])
	_expect(BoothStory.heard(BoothStory.CAROL) == 1, "the story did not move on")
	Season.start(_league, 0)
	_expect(BoothStory.heard(BoothStory.CAROL) == 0, "a new season did not start the stories over")


## What an average game on paper comes to, per team.
func _print_average(games: int) -> void:
	var total: TeamLine = TeamLine.new()
	var points: int = 0
	var overtimes: int = 0
	var home_wins: int = 0
	var tackles: int = 0
	var wins: Dictionary[String, int] = {}
	var count: int = _league.teams.size()
	for i: int in games:
		var home: int = i % count
		@warning_ignore("integer_division")
		var away: int = (home + 1 + (i / count) % (count - 1)) % count
		var sim: SeasonSim = SeasonSim.new()
		sim.run(_league.teams[home].roster, _league.teams[away].roster)
		points += sim._score[0] + sim._score[1]
		overtimes += int(sim._overtime)
		home_wins += int(sim._score[0] > sim._score[1])
		var winner: String = _league.teams[home if sim._score[0] > sim._score[1] else away].short_name
		wins[winner] = wins.get(winner, 0) + 1
		for side: int in 2:
			total.add(sim._lines[side])
			for line: PlayerLine in sim._players[side]:
				tackles += line.tackles
	var n: float = float(games * 2)
	print("on paper, per team per game (%d games):" % games)
	print("  points %.1f   plays %.1f   drives %.1f   yards %.0f   yards/play %.1f" % [points / n, total.plays / n, total.drives / n, total.total_yds() / n, float(total.total_yds()) / float(maxi(total.plays, 1))])
	print("  pass %.1f/%.1f for %.0f   int %.2f   sacks %.1f   rush %.1f for %.0f" % [total.pass_comp / n, total.pass_att / n, total.pass_yds / n, total.pass_int / n, total.sacked / n, total.rush_att / n, total.rush_yds / n])
	print("  touchdowns %.1f (returns %.1f)   tries %.1f of %.1f   fumbles lost %.2f   first downs %.1f   tackles %.1f" % [total.touchdowns / n, total.return_td / n, total.tries_made / n, total.tries_att / n, total.fumbles_lost / n, total.first_downs() / n, tackles / n])
	print("  third down %d-%d   fourth down %d-%d   red zone %d-%d" % [total.third_made, total.third_att, total.fourth_made, total.fourth_att, total.red_zone_made, total.red_zone_att])
	print("  overtime %d of %d   home wins %d   wins by team %s" % [overtimes, games, home_wins, wins])


func _expect(ok: bool, what: String) -> void:
	if not ok and not _failures.has(what):
		_failures.append(what)
