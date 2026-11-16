class_name SeasonTables
extends RefCounted
## The season's numbers as rows of text, for the season's screen: the table,
## the teams side by side, the league's leaders and one team's footballers.
## Each list of rows goes under the `*_HEAD` of the same name; the footballers'
## tables use the box score's heads (StatBook).

const STANDINGS_HEAD: PackedStringArray = ["", "W", "L", "PCT", "PF", "PA", "DIFF", "STRK"]
const TEAMS_HEAD: PackedStringArray = ["", "GP", "PTS", "YDS", "PASS", "RUSH", "ALLOW", "GIVE", "3RD %", "SACKED"]
## How many footballers a list of leaders names.
const LEADERS: int = 5

## What a list of leaders is ordered by, most first.
enum Leaders { PASSING, RUSHING, RECEIVING, TACKLES }


static func standings_rows(season: Season) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for row: Dictionary in season.standings():
		var team: int = row["team"]
		rows.append(PackedStringArray([
			"%d.  %s" % [row["place"], season.team_data(team).team_name.to_upper()],
			str(row["wins"]), str(row["losses"]), ("%.3f" % row["pct"]).trim_prefix("0"),
			str(row["pf"]), str(row["pa"]), "%+d" % row["diff"], row["streak"]]))
	return rows


## Every team's numbers a game, in the order of the table.
static func team_rows(season: Season) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for row: Dictionary in season.standings():
		var team: int = row["team"]
		var t: TeamLine = season.team_line(team)
		var games: float = maxf(float(t.games), 1.0)
		var third: String = "%d" % roundi(100.0 * float(t.third_made) / float(t.third_att)) if t.third_att > 0 else "-"
		rows.append(PackedStringArray([
			season.team_data(team).team_name.to_upper(), str(t.games),
			"%.1f" % (float(t.points_for) / games), "%.0f" % (float(t.total_yds()) / games),
			"%.0f" % (float(t.net_pass_yds()) / games), "%.0f" % (float(t.rush_yds) / games),
			"%.1f" % (float(t.points_against) / games), str(t.turnovers()), third, str(t.sacked)]))
	return rows


## The league's best at one thing: a row of that part of the box score for
## each, his team after his name.
static func leader_rows(season: Season, by: Leaders) -> Array[PackedStringArray]:
	var found: Array[Array] = []
	for team: int in season.teams.size():
		var roster: Roster = season.team_data(team).roster
		for index: int in roster.players.size():
			var p: PlayerLine = season.player_line(team, index)
			var amount: int = _amount(p, by)
			if amount > 0 or (by == Leaders.PASSING and p.pass_att > 0):
				found.append([amount, team, index])
	found.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] if a[0] != b[0] else (a[1] < b[1] if a[1] != b[1] else a[2] < b[2]))
	var rows: Array[PackedStringArray] = []
	for entry: Array in found.slice(0, LEADERS):
		var team: int = entry[1]
		var index: int = entry[2]
		var ratings: PlayerRatings = season.team_data(team).roster.players[index]
		# Without his number: the team's name has to fit beside his.
		var who: String = "%s  %s" % [ratings.display_name if ratings.display_name != "" else StatBook.label_of_ratings(ratings, index), season.teams[team]]
		rows.append(_row(who, season.player_line(team, index), by))
	return rows


## One team's footballers at one part of the game, the most first, and the
## team's own line last.
static func roster_rows(season: Season, team: int, by: Leaders) -> Array[PackedStringArray]:
	var roster: Roster = season.team_data(team).roster
	var order: Array[int] = []
	order.assign(range(roster.players.size()))
	order.sort_custom(func(a: int, b: int) -> bool:
		var left: int = _amount(season.player_line(team, a), by)
		var right: int = _amount(season.player_line(team, b), by)
		return left > right if left != right else a < b)
	var rows: Array[PackedStringArray] = []
	var sum: PlayerLine = PlayerLine.new()
	for index: int in order:
		var p: PlayerLine = season.player_line(team, index)
		if _took_part(p, by):
			rows.append(_row(StatBook.label_of_ratings(roster.players[index], index), p, by))
			sum.add(p)
	rows.append(_row("TEAM", sum, by))
	return rows


static func head(by: Leaders) -> PackedStringArray:
	match by:
		Leaders.PASSING:
			return StatBook.PASSING_HEAD
		Leaders.RUSHING:
			return StatBook.RUSHING_HEAD
		Leaders.RECEIVING:
			return StatBook.RECEIVING_HEAD
	return StatBook.DEFENSE_HEAD


static func title(by: Leaders) -> String:
	return ["PASSING", "RUSHING", "RECEIVING", "DEFENSE"][by]


static func _amount(p: PlayerLine, by: Leaders) -> int:
	match by:
		Leaders.PASSING:
			return p.pass_yds
		Leaders.RUSHING:
			return p.rush_yds
		Leaders.RECEIVING:
			return p.rec_yds
	return p.tackles * 2 + p.sacks * 3 + p.interceptions * 4 + p.forced_fumbles + p.fumble_recoveries + p.return_td * 4


static func _took_part(p: PlayerLine, by: Leaders) -> bool:
	match by:
		Leaders.PASSING:
			return p.has_passing()
		Leaders.RUSHING:
			return p.rush_att > 0
		Leaders.RECEIVING:
			return p.targets > 0 or p.rec > 0
	return p.has_defense()


static func _row(who: String, p: PlayerLine, by: Leaders) -> PackedStringArray:
	match by:
		Leaders.PASSING:
			return PackedStringArray([who, "%d/%d" % [p.pass_comp, p.pass_att], str(p.pass_yds), _average(p.pass_yds, p.pass_att), str(p.pass_td), str(p.pass_int), "%d-%d" % [p.sacked, p.sacked_yds]])
		Leaders.RUSHING:
			return PackedStringArray([who, str(p.rush_att), str(p.rush_yds), _average(p.rush_yds, p.rush_att), str(p.rush_td), str(p.rush_long)])
		Leaders.RECEIVING:
			return PackedStringArray([who, str(p.rec), str(p.rec_yds), _average(p.rec_yds, p.rec), str(p.rec_td), str(p.rec_long), str(p.targets)])
	return PackedStringArray([who, str(p.tackles), str(p.sacks), str(p.interceptions), str(p.forced_fumbles), str(p.fumble_recoveries), str(p.return_td)])


static func _average(total: int, count: int) -> String:
	return "%.1f" % (float(total) / float(count)) if count > 0 else "0.0"
