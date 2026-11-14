class_name Season
extends RefCounted
## A season of the league. Every team plays every other twice, once at each
## ground: ten weeks of three games. Then the playoffs: the first seed has the
## week off while the second plays the third at home, and the winner goes to
## the first seed's ground for the championship, the Fruit Cup.
##
## The person plays one team's games; the others are played on paper
## (SeasonSim). The season keeps every result and what each team and each
## footballer has done, and is saved after every round, so it carries on from
## one session to the next. There is one season at a time (`current`).
##
## A round is a week of the regular season (0 to 9), then the semifinal (10)
## and the final (11). Teams are numbered by their place in `teams`, which
## holds their short names: the save survives the league being put in another
## order, but not a team leaving it.

enum Phase { REGULAR, SEMIFINAL, FINAL, DONE }

const WEEKS: int = 10
const SEMIFINAL_ROUND: int = 10
const FINAL_ROUND: int = 11
## How many teams go on to the playoffs.
const PLAYOFF_TEAMS: int = 3
const CUP_NAME: String = "THE FRUIT CUP"
const SECTION: String = "season"

## The season being played, or null. MainMenu loads it.
static var current: Season
## Where it is kept. A test points this somewhere else.
static var save_path: String = "user://season.cfg"

var league: League
## The short names of the teams, in the league's order when the season began.
var teams: PackedStringArray = PackedStringArray()
## The team the person plays.
var user_team: int = 0
## For each week its games, each [home, away].
var schedule: Array[Array] = []
## Every game played so far: {round, home, away, home_score, away_score, overtime}.
var results: Array[Dictionary] = []
var phase: Phase = Phase.REGULAR
## The week being played, while the regular season lasts.
var week: int = 0
## The playoff teams, best first, once the regular season is over.
var seeds: Array[int] = []
var semifinal_winner: int = -1
var champion: int = -1
## Each team's numbers so far, and each footballer's under `player_key()`.
var team_lines: Array[TeamLine] = []
var player_lines: Dictionary[String, PlayerLine] = {}


# --- Starting, saving, loading -------------------------------------------------------

## A new season of `p_league` with the person as its team `team`, in place of
## any that was going on. The booth's stories start over with it.
static func start(p_league: League, team: int) -> Season:
	var season: Season = Season.new()
	season.league = p_league
	for data: TeamData in p_league.teams:
		season.teams.append(data.short_name)
		season.team_lines.append(TeamLine.new())
	season.user_team = clampi(team, 0, season.teams.size() - 1)
	season.schedule = make_schedule(season.teams.size())
	BoothStory.reset()
	current = season
	season.save()
	return season


## The saved season, or null if there is none or it is of another league.
static func load_saved(p_league: League) -> Season:
	current = null
	var file: ConfigFile = ConfigFile.new()
	if file.load(save_path) != OK or not file.has_section_key(SECTION, "teams"):
		return null
	var season: Season = Season.new()
	season.league = p_league
	season.teams = PackedStringArray(file.get_value(SECTION, "teams", PackedStringArray()))
	if season.teams.size() != p_league.teams.size() or season.teams.size() < PLAYOFF_TEAMS:
		return null
	for short_name: String in season.teams:
		if p_league.find(short_name) < 0:
			return null
	season.user_team = clampi(int(file.get_value(SECTION, "user_team", 0)), 0, season.teams.size() - 1)
	season.phase = clampi(int(file.get_value(SECTION, "phase", 0)), 0, Phase.DONE) as Phase
	season.week = int(file.get_value(SECTION, "week", 0))
	season.semifinal_winner = int(file.get_value(SECTION, "semifinal_winner", -1))
	season.champion = int(file.get_value(SECTION, "champion", -1))
	season.seeds.assign(file.get_value(SECTION, "seeds", []) as Array)
	for games: Array in file.get_value(SECTION, "schedule", []) as Array:
		season.schedule.append(games)
	for result: Dictionary in file.get_value(SECTION, "results", []) as Array:
		season.results.append(result)
	var saved_teams: Array = file.get_value(SECTION, "team_lines", []) as Array
	for i: int in season.teams.size():
		season.team_lines.append(TeamLine.from_dict(saved_teams[i]) if i < saved_teams.size() else TeamLine.new())
	var saved_players: Dictionary = file.get_value(SECTION, "player_lines", {}) as Dictionary
	for key: String in saved_players:
		season.player_lines[key] = PlayerLine.from_dict(saved_players[key])
	if season.schedule.size() != WEEKS:
		return null
	current = season
	return season


func save() -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION, "teams", teams)
	file.set_value(SECTION, "user_team", user_team)
	file.set_value(SECTION, "phase", int(phase))
	file.set_value(SECTION, "week", week)
	file.set_value(SECTION, "seeds", seeds)
	file.set_value(SECTION, "semifinal_winner", semifinal_winner)
	file.set_value(SECTION, "champion", champion)
	file.set_value(SECTION, "schedule", schedule)
	file.set_value(SECTION, "results", results)
	var lines: Array[Dictionary] = []
	for line: TeamLine in team_lines:
		lines.append(line.to_dict())
	file.set_value(SECTION, "team_lines", lines)
	var players: Dictionary = {}
	for key: String in player_lines:
		players[key] = player_lines[key].to_dict()
	file.set_value(SECTION, "player_lines", players)
	var error: Error = file.save(save_path)
	if error != OK:
		push_warning("Season: could not save to %s (%s)" % [save_path, error_string(error)])


## Forgets the season, on file as well.
static func clear() -> void:
	current = null
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Twice round: every pair of `count` teams (an even number) meets once in the
## first half of the weeks and once more, at the other ground, in the second.
## The weeks of each half come in a random order, and in each half a team is
## at home about as often as away.
static func make_schedule(count: int) -> Array[Array]:
	var ring: Array[int] = []
	ring.assign(range(count))
	var pairings: Array[Array] = []
	for turn: int in count - 1:
		var games: Array[Array] = []
		@warning_ignore("integer_division")
		for i: int in count / 2:
			games.append([ring[i], ring[count - 1 - i]])
		pairings.append(games)
		ring.insert(1, ring.pop_back())
	pairings.shuffle()
	# Whoever has been at home less so far is at home.
	var at_home: Array[int] = []
	at_home.resize(count)
	at_home.fill(0)
	var first: Array[Array] = []
	for pairing: Array in pairings:
		var games: Array[Array] = []
		for pair: Array in pairing:
			var a: int = pair[0]
			var b: int = pair[1]
			if at_home[a] > at_home[b] or (at_home[a] == at_home[b] and randf() < 0.5):
				a = pair[1]
				b = pair[0]
			at_home[a] += 1
			games.append([a, b])
		first.append(games)
	var second: Array[Array] = []
	for games: Array in first:
		var back: Array[Array] = []
		for game: Array in games:
			back.append([game[1], game[0]])
		second.append(back)
	second.shuffle()
	return first + second


# --- Where the season stands ---------------------------------------------------------

func team_data(team: int) -> TeamData:
	return league.teams[league.find(teams[team])]


## The team's place in the league's own list (what Game.team_picks wants).
func league_index(team: int) -> int:
	return league.find(teams[team])


func team_of(short_name: String) -> int:
	for i: int in teams.size():
		if teams[i].to_lower() == short_name.to_lower():
			return i
	return -1


func current_round() -> int:
	match phase:
		Phase.REGULAR:
			return week
		Phase.SEMIFINAL:
			return SEMIFINAL_ROUND
	return FINAL_ROUND


## "WEEK 4", "SEMIFINAL", the cup's name.
func round_name(round_index: int = -1) -> String:
	var which: int = current_round() if round_index < 0 else round_index
	if which < WEEKS:
		return "WEEK %d" % (which + 1)
	return "SEMIFINAL" if which == SEMIFINAL_ROUND else CUP_NAME


func is_playoffs() -> bool:
	return phase == Phase.SEMIFINAL or phase == Phase.FINAL


func is_over() -> bool:
	return phase == Phase.DONE


## The games of the round being played, each [home, away]. None once it is over.
func round_games() -> Array[Array]:
	var games: Array[Array] = []
	match phase:
		Phase.REGULAR:
			games.assign(schedule[week])
		Phase.SEMIFINAL:
			games.append([seeds[1], seeds[2]])
		Phase.FINAL:
			games.append([seeds[0], semifinal_winner])
	return games


## The person's game of this round, [home, away], or nothing: it has been
## played, the team has the week off, or its season is over.
func fixture() -> Array:
	for game: Array in round_games():
		if (game[0] == user_team or game[1] == user_team) and result_of(current_round(), game[0], game[1]).is_empty():
			return game
	return []


## The result of the game between the two in `round_index`, or nothing yet.
func result_of(round_index: int, home: int, away: int) -> Dictionary:
	for result: Dictionary in results:
		if result["round"] == round_index and result["home"] == home and result["away"] == away:
			return result
	return {}


func results_of_round(round_index: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for result: Dictionary in results:
		if result["round"] == round_index:
			found.append(result)
	return found


## The team is still playing for the cup: the regular season is on, or it is
## in the playoffs and has not lost there.
func alive(team: int) -> bool:
	match phase:
		Phase.REGULAR:
			return true
		Phase.SEMIFINAL:
			return seeds.has(team)
		Phase.FINAL:
			return team == seeds[0] or team == semifinal_winner
	return team == champion


## The first seed in the week of the semifinal.
func on_bye(team: int) -> bool:
	return phase == Phase.SEMIFINAL and not seeds.is_empty() and seeds[0] == team


static func winner_of(result: Dictionary) -> int:
	return result["home"] if result["home_score"] > result["away_score"] else result["away"]


static func loser_of(result: Dictionary) -> int:
	return result["away"] if result["home_score"] > result["away_score"] else result["home"]


# --- Standings -----------------------------------------------------------------------

## The table of the regular season, best first. Each row: {team, wins, losses,
## pf, pa, diff, pct, streak ("W3", "L1", "-"), place (from 1)}. Level on wins,
## the teams are told apart by the games among themselves, then by points
## difference, then by points scored.
func standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for team: int in teams.size():
		rows.append({"team": team, "wins": 0, "losses": 0, "pf": 0, "pa": 0, "streak": "-", "among": 0})
	var runs: Array[int] = []
	runs.resize(teams.size())
	runs.fill(0)
	for result: Dictionary in results:
		if result["round"] >= WEEKS:
			continue
		var winner: int = winner_of(result)
		for side: String in ["home", "away"]:
			var team: int = result[side]
			var row: Dictionary = rows[team]
			var won: bool = team == winner
			row["wins" if won else "losses"] += 1
			row["pf"] += result[side + "_score"]
			row["pa"] += result[("away" if side == "home" else "home") + "_score"]
			# A run of wins counts up from zero, a run of defeats down.
			runs[team] = (maxi(runs[team], 0) + 1) if won else (mini(runs[team], 0) - 1)
	for row: Dictionary in rows:
		var played: int = row["wins"] + row["losses"]
		var run: int = runs[row["team"]]
		row["diff"] = row["pf"] - row["pa"]
		row["pct"] = float(row["wins"]) / float(played) if played > 0 else 0.0
		row["streak"] = "-" if run == 0 else ("W%d" % run if run > 0 else "L%d" % -run)
	# Wins against the others on the same number of wins.
	for result: Dictionary in results:
		if result["round"] >= WEEKS:
			continue
		var winner: int = winner_of(result)
		var loser: int = loser_of(result)
		if rows[winner]["wins"] == rows[loser]["wins"] and rows[winner]["losses"] == rows[loser]["losses"]:
			rows[winner]["among"] += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		for key: String in ["pct", "among", "diff", "pf"]:
			if a[key] != b[key]:
				return a[key] > b[key]
		return a["team"] < b["team"])
	for place: int in rows.size():
		rows[place]["place"] = place + 1
	return rows


## "7-3" for the team's regular season so far.
func record_text(team: int) -> String:
	for row: Dictionary in standings():
		if row["team"] == team:
			return "%d-%d" % [row["wins"], row["losses"]]
	return "0-0"


## The team's place in the table, from 1.
func place_of(team: int) -> int:
	for row: Dictionary in standings():
		if row["team"] == team:
			return row["place"]
	return teams.size()


# --- Playing -------------------------------------------------------------------------

static func player_key(short_name: String, index: int) -> String:
	return "%s/%d" % [short_name, index]


func team_line(team: int) -> TeamLine:
	return team_lines[team]


## What the footballer at place `index` of the team's roster has done, or an
## empty line.
func player_line(team: int, index: int) -> PlayerLine:
	var key: String = player_key(teams[team], index)
	return player_lines[key] if player_lines.has(key) else PlayerLine.new()


## Books a game of the round being played: the score, and each team's line and
## its footballers' lines (in roster order) for it. Nothing is booked twice.
func record(home: int, away: int, home_score: int, away_score: int, overtime: bool, lines: Array[TeamLine], players: Array[Array]) -> void:
	var round_index: int = current_round()
	if is_over() or not result_of(round_index, home, away).is_empty() or home_score == away_score:
		return
	results.append({"round": round_index, "home": home, "away": away, "home_score": home_score, "away_score": away_score, "overtime": overtime})
	var sides: Array[int] = [home, away]
	var scores: Array[int] = [home_score, away_score]
	for side: int in 2:
		var line: TeamLine = lines[side]
		line.games = 1
		line.points_for = scores[side]
		line.points_against = scores[1 - side]
		team_lines[sides[side]].add(line)
		for index: int in players[side].size():
			var key: String = player_key(teams[sides[side]], index)
			if not player_lines.has(key):
				player_lines[key] = PlayerLine.new()
			player_lines[key].add(players[side][index])


## Books the match that has just ended on the field. False if it is not a game
## of this round.
func record_match(game: Game) -> bool:
	var home: int = team_of(game.home.short_name)
	var away: int = team_of(game.away.short_name)
	if home < 0 or away < 0 or not round_games().has([home, away]) or game.is_tied():
		return false
	var lines: Array[TeamLine] = []
	var players: Array[Array] = []
	for team: Team in [game.home, game.away]:
		# A copy: the match's own book stays as it is for the pause menu.
		var line: TeamLine = TeamLine.new()
		line.add(game.stat_book.team_line(team))
		lines.append(line)
		var roster: Array[PlayerLine] = []
		for player: Player in team.players:
			roster.append(game.stat_book.player_line(player))
		players.append(roster)
	record(home, away, game.home.score, game.away.score, game.overtime, lines, players)
	return true


## Plays the games of this round that have not been played on paper, moves on
## to the next round and saves. Does nothing while the person's game is still
## to play.
func finish_round() -> void:
	if is_over() or not fixture().is_empty():
		return
	var round_index: int = current_round()
	for game: Array in round_games():
		if result_of(round_index, game[0], game[1]).is_empty():
			SeasonSim.play(self, game[0], game[1])
	match phase:
		Phase.REGULAR:
			week += 1
			if week >= WEEKS:
				seeds.clear()
				for row: Dictionary in standings().slice(0, PLAYOFF_TEAMS):
					seeds.append(row["team"])
				phase = Phase.SEMIFINAL
		Phase.SEMIFINAL:
			semifinal_winner = winner_of(result_of(SEMIFINAL_ROUND, seeds[1], seeds[2]))
			phase = Phase.FINAL
		Phase.FINAL:
			champion = winner_of(result_of(FINAL_ROUND, seeds[0], semifinal_winner))
			phase = Phase.DONE
	save()
