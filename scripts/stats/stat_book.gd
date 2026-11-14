class_name StatBook
extends RefCounted
## The game's box score: a line for each team and each footballer, written once
## a play at the whistle, and the tables the pause menu shows.
## (Game.stats is something else: event counters for the tests.)

const PASSING_HEAD: PackedStringArray = ["", "C/ATT", "YDS", "AVG", "TD", "INT", "SACKS"]
const RUSHING_HEAD: PackedStringArray = ["", "CAR", "YDS", "AVG", "TD", "LONG"]
const RECEIVING_HEAD: PackedStringArray = ["", "REC", "YDS", "AVG", "TD", "LONG", "TGTS"]
const DEFENSE_HEAD: PackedStringArray = ["", "TKL", "SACK", "INT", "FF", "FR", "TD"]
## The red zone is the last this many yards before the goal line.
const RED_ZONE_YARDS: float = 20.0

var teams: Dictionary[Team, TeamLine] = {}
var players: Dictionary[Player, PlayerLine] = {}
var _home: Team
var _away: Team


func setup(home: Team, away: Team) -> void:
	_home = home
	_away = away
	teams.clear()
	players.clear()
	for team: Team in [home, away]:
		teams[team] = TeamLine.new()
		for player: Player in team.squad:
			players[player] = PlayerLine.new()
		# The mascot can come up with a scramble's ball and score: it has a line
		# to write to, which no table shows.
		players[team.mascot] = PlayerLine.new()


func team_line(team: Team) -> TeamLine:
	return teams[team]


func player_line(player: Player) -> PlayerLine:
	return players[player]


# --- Writing ---------------------------------------------------------------------

func begin_drive(team: Team) -> void:
	var line: TeamLine = teams[team]
	line.drives += 1
	line.in_red_zone = false


func add_possession(team: Team, seconds: float) -> void:
	teams[team].possession += seconds


func add_late_hit(team: Team) -> void:
	teams[team].late_hits += 1


func add_dive(team: Team) -> void:
	teams[team].dives += 1


func add_fumble(team: Team) -> void:
	teams[team].fumbles += 1


## The score has changed: keeps the most each team has been behind by.
func note_score() -> void:
	for team: Team in teams:
		var line: TeamLine = teams[team]
		line.max_deficit = maxi(line.max_deficit, team.opponent.score - team.score)


## The team's longest run so far, in yards (0 with none).
func longest_run(team: Team) -> int:
	var longest: int = 0
	for player: Player in team.squad:
		if players[player].rush_att > 0:
			longest = maxi(longest, players[player].rush_long)
	return longest


## The most touchdowns any one of the team's players has scored himself.
func top_scorer_tds(team: Team) -> int:
	var most: int = 0
	for player: Player in team.squad:
		var p: PlayerLine = players[player]
		most = maxi(most, p.rush_td + p.rec_td + p.return_td)
	return most


## Books the play that has just been whistled dead. Called from
## PlayController.end_play(), before Game moves the ball or the down.
func record_play(game: Game) -> void:
	var pc: PlayController = game.play_controller
	var tuning: Tuning = game.tuning
	var offense: Team = pc.offense
	var final_team: Team = pc.final_team
	var off: TeamLine = teams[offense]
	var touchdown: bool = pc.result == PlayController.Result.TOUCHDOWN
	var holder: Player = pc.ball.carrier

	if game.conversion:
		off.tries_att += 1
		if touchdown:
			if final_team == offense:
				off.tries_made += 1
			else:
				teams[final_team].tries_returned += 1
		return

	if pc.scramble:
		# Nobody's play: only what came of it counts.
		_record_fumble(pc, final_team)
		if touchdown:
			teams[final_team].touchdowns += 1
			teams[final_team].return_td += 1
			if holder != null:
				players[holder].return_td += 1
		return

	var dir: float = pc.off_dir
	var kept: bool = final_team == offense
	_record_fumble(pc, final_team)
	if touchdown:
		teams[final_team].touchdowns += 1
		if pc.kickoff or not kept:
			teams[final_team].return_td += 1
			if holder != null:
				players[holder].return_td += 1
	if pc.result == PlayController.Result.TACKLED and not pc.was_dive and holder != null and pc.tackled_by != null and pc.tackled_by.team != holder.team:
		players[pc.tackled_by].tackles += 1

	# Where the offense's own part of the play ended: at the whistle, or where
	# it lost the ball.
	var lost_fumble: bool = not kept and pc.fumbler != null and pc.fumbler.team == offense
	var end_x: float = pc.fumble_x if lost_fumble else pc.dead_spot_x

	if pc.kickoff:
		off.kick_returns += 1
		if (kept or lost_fumble) and not pc.was_touchback:
			off.kick_return_yds += maxi(roundi((end_x - pc.return_from_x) * dir), 0)
		return

	# Never past the goal line, however deep in the end zone he ran.
	var to_goal: float = (tuning.goal_x(offense.attack_dir) - pc.los_x) * dir
	var gain: int = roundi(minf((end_x - pc.los_x) * dir, to_goal))
	off.plays += 1
	if to_goal <= RED_ZONE_YARDS and not off.in_red_zone:
		off.in_red_zone = true
		off.red_zone_att += 1
	if touchdown and kept and off.in_red_zone:
		off.red_zone_made += 1
	if kept and (pc.result == PlayController.Result.TACKLED or pc.result == PlayController.Result.OUT_OF_BOUNDS):
		if (pc.dead_spot_x - tuning.own_goal_x(offense.attack_dir)) * dir <= 0.0:
			teams[offense.opponent].safeties += 1

	var passing: bool = true
	if pc.passer != null:
		_record_pass(pc, off, gain, touchdown and kept)
	elif pc.was_sack and not pc.off_play.is_run:
		var lost: int = maxi(-gain, 0)
		off.sacked += 1
		off.sacked_yds += lost
		players[pc.qb].sacked += 1
		players[pc.qb].sacked_yds += lost
		if pc.tackled_by != null and pc.tackled_by.team != offense:
			players[pc.tackled_by].sacks += 1
	else:
		passing = false
		_record_rush(pc, off, holder, gain, touchdown and kept)

	var moved_chains: bool = kept and (touchdown or (not game.goal_to_go and (pc.dead_spot_x - game.first_down_x) * dir >= 0.0))
	if moved_chains:
		if passing:
			off.first_downs_pass += 1
		else:
			off.first_downs_rush += 1
	if game.down == 3:
		off.third_att += 1
		off.third_made += int(moved_chains)
	elif game.down == 4:
		off.fourth_att += 1
		off.fourth_made += int(moved_chains)


func _record_pass(pc: PlayController, off: TeamLine, gain: int, scored: bool) -> void:
	var passer: PlayerLine = players[pc.passer]
	passer.pass_att += 1
	off.pass_att += 1
	# A ball that came off somebody's hands to another receiver was his target.
	var target: Player = pc.catcher if pc.catcher != null else pc.pass_intended
	if target != null and players.has(target):
		players[target].targets += 1
	if pc.interceptor != null:
		passer.pass_int += 1
		off.pass_int += 1
		players[pc.interceptor].interceptions += 1
	elif pc.catcher != null:
		var catcher: PlayerLine = players[pc.catcher]
		passer.pass_comp += 1
		passer.pass_yds += gain
		off.pass_comp += 1
		off.pass_yds += gain
		catcher.add_catch(gain)
		if scored:
			passer.pass_td += 1
			catcher.rec_td += 1
			off.pass_td += 1


## The carry goes to whoever had the ball for the offense: the man who lost it,
## the man holding it at the whistle, or the quarterback.
func _record_rush(pc: PlayController, off: TeamLine, holder: Player, gain: int, scored: bool) -> void:
	var rusher: Player = pc.qb
	if pc.fumbler != null and pc.fumbler.team == pc.offense:
		rusher = pc.fumbler
	elif holder != null and holder.team == pc.offense:
		rusher = holder
	var line: PlayerLine = players[rusher]
	line.add_rush(gain)
	off.rush_att += 1
	off.rush_yds += gain
	if scored:
		line.rush_td += 1
		off.rush_td += 1


func _record_fumble(pc: PlayController, final_team: Team) -> void:
	if pc.fumbler == null:
		return
	if pc.fumble_forcer != null and pc.fumble_forcer.team != pc.fumbler.team:
		players[pc.fumble_forcer].forced_fumbles += 1
	if final_team == pc.fumbler.team:
		return
	players[pc.fumbler].fumbles_lost += 1
	teams[pc.fumbler.team].fumbles_lost += 1
	if pc.fumble_recoverer != null and pc.fumble_recoverer.team != pc.fumbler.team:
		players[pc.fumble_recoverer].fumble_recoveries += 1


# --- Tables ----------------------------------------------------------------------
# Each row matches the *_HEAD above it. The last row is the team's.

func passing_rows(team: Team) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for player: Player in team.squad:
		var p: PlayerLine = players[player]
		if p.has_passing():
			rows.append(PackedStringArray([label_of(player), "%d/%d" % [p.pass_comp, p.pass_att], str(p.pass_yds), _average(p.pass_yds, p.pass_att), str(p.pass_td), str(p.pass_int), "%d-%d" % [p.sacked, p.sacked_yds]]))
	var t: TeamLine = teams[team]
	rows.append(PackedStringArray(["TEAM", "%d/%d" % [t.pass_comp, t.pass_att], str(t.net_pass_yds()), _average(t.net_pass_yds(), t.pass_att), str(t.pass_td), str(t.pass_int), "%d-%d" % [t.sacked, t.sacked_yds]]))
	return rows


func rushing_rows(team: Team) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var longest: int = 0
	var any: bool = false
	for player: Player in _sorted(team, func(p: PlayerLine) -> int: return p.rush_yds):
		var p: PlayerLine = players[player]
		if p.rush_att > 0:
			rows.append(PackedStringArray([label_of(player), str(p.rush_att), str(p.rush_yds), _average(p.rush_yds, p.rush_att), str(p.rush_td), str(p.rush_long)]))
			longest = p.rush_long if not any else maxi(longest, p.rush_long)
			any = true
	var t: TeamLine = teams[team]
	rows.append(PackedStringArray(["TEAM", str(t.rush_att), str(t.rush_yds), _average(t.rush_yds, t.rush_att), str(t.rush_td), str(longest)]))
	return rows


func receiving_rows(team: Team) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var longest: int = 0
	var any: bool = false
	var targets: int = 0
	for player: Player in _sorted(team, func(p: PlayerLine) -> int: return p.rec_yds):
		var p: PlayerLine = players[player]
		targets += p.targets
		if p.targets > 0 or p.rec > 0:
			rows.append(PackedStringArray([label_of(player), str(p.rec), str(p.rec_yds), _average(p.rec_yds, p.rec), str(p.rec_td), str(p.rec_long), str(p.targets)]))
		if p.rec > 0:
			longest = p.rec_long if not any else maxi(longest, p.rec_long)
			any = true
	var t: TeamLine = teams[team]
	rows.append(PackedStringArray(["TEAM", str(t.pass_comp), str(t.pass_yds), _average(t.pass_yds, t.pass_comp), str(t.pass_td), str(longest), str(targets)]))
	return rows


func defense_rows(team: Team) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var sum: PlayerLine = PlayerLine.new()
	for player: Player in _sorted(team, func(p: PlayerLine) -> int: return p.tackles):
		var p: PlayerLine = players[player]
		if not p.has_defense():
			continue
		rows.append(_defense_row(label_of(player), p))
		sum.tackles += p.tackles
		sum.sacks += p.sacks
		sum.interceptions += p.interceptions
		sum.forced_fumbles += p.forced_fumbles
		sum.fumble_recoveries += p.fumble_recoveries
		sum.return_td += p.return_td
	rows.append(_defense_row("TEAM", sum))
	return rows


## [label, home value, away value, indented] for every line of the team stats.
func team_rows() -> Array[Array]:
	var h: TeamLine = teams[_home]
	var a: TeamLine = teams[_away]
	return [
		["1st Downs", str(h.first_downs()), str(a.first_downs()), false],
		["Passing 1st downs", str(h.first_downs_pass), str(a.first_downs_pass), true],
		["Rushing 1st downs", str(h.first_downs_rush), str(a.first_downs_rush), true],
		["3rd down efficiency", "%d-%d" % [h.third_made, h.third_att], "%d-%d" % [a.third_made, a.third_att], true],
		["4th down efficiency", "%d-%d" % [h.fourth_made, h.fourth_att], "%d-%d" % [a.fourth_made, a.fourth_att], true],
		["Total Plays", str(h.plays), str(a.plays), false],
		["Total Yards", str(h.total_yds()), str(a.total_yds()), false],
		["Total Drives", str(h.drives), str(a.drives), false],
		["Yards per Play", _average(h.total_yds(), h.plays), _average(a.total_yds(), a.plays), false],
		["Passing", str(h.net_pass_yds()), str(a.net_pass_yds()), false],
		["Comp/Att", "%d/%d" % [h.pass_comp, h.pass_att], "%d/%d" % [a.pass_comp, a.pass_att], true],
		["Yards per pass", _average(h.net_pass_yds(), h.pass_att + h.sacked), _average(a.net_pass_yds(), a.pass_att + a.sacked), true],
		["Interceptions thrown", str(h.pass_int), str(a.pass_int), true],
		["Sacks-Yards Lost", "%d-%d" % [h.sacked, h.sacked_yds], "%d-%d" % [a.sacked, a.sacked_yds], true],
		["Rushing", str(h.rush_yds), str(a.rush_yds), false],
		["Rushing Attempts", str(h.rush_att), str(a.rush_att), true],
		["Yards per rush", _average(h.rush_yds, h.rush_att), _average(a.rush_yds, a.rush_att), true],
		["Red Zone (Made-Att)", "%d-%d" % [h.red_zone_made, h.red_zone_att], "%d-%d" % [a.red_zone_made, a.red_zone_att], false],
		["2-Point Tries (Made-Att)", "%d-%d" % [h.tries_made, h.tries_att], "%d-%d" % [a.tries_made, a.tries_att], false],
		["Turnovers", str(h.turnovers()), str(a.turnovers()), false],
		["Fumbles lost", str(h.fumbles_lost), str(a.fumbles_lost), true],
		["Possession", _clock(h.possession), _clock(a.possession), false],
	]


## What `player` has done in this game, a line for each part of it he had a hand in.
func player_summary(player: Player) -> PackedStringArray:
	return summary_of(players[player])


## The same for any line: a game's, or a season's.
static func summary_of(p: PlayerLine) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if p.has_passing():
		lines.append("PASSING   %d/%d,  %d YDS,  %d TD,  %d INT" % [p.pass_comp, p.pass_att, p.pass_yds, p.pass_td, p.pass_int])
	if p.rush_att > 0:
		lines.append("RUSHING   %d CAR,  %d YDS,  %d TD" % [p.rush_att, p.rush_yds, p.rush_td])
	if p.targets > 0 or p.rec > 0:
		lines.append("RECEIVING   %d REC,  %d YDS,  %d TD" % [p.rec, p.rec_yds, p.rec_td])
	if p.has_defense():
		var parts: PackedStringArray = PackedStringArray(["%d TKL" % p.tackles])
		if p.sacks > 0:
			parts.append("%d SACK" % p.sacks)
		if p.interceptions > 0:
			parts.append("%d INT" % p.interceptions)
		if p.forced_fumbles > 0:
			parts.append("%d FF" % p.forced_fumbles)
		if p.fumble_recoveries > 0:
			parts.append("%d FR" % p.fumble_recoveries)
		if p.return_td > 0:
			parts.append("%d TD" % p.return_td)
		lines.append("DEFENSE   " + ",  ".join(parts))
	if lines.is_empty():
		lines.append("Nothing in the book yet")
	return lines


## "#12 Dash Plantain", or his position and place on the team if he has no name.
static func label_of(player: Player) -> String:
	return label_of_ratings(player.ratings, player.index)


## The same from his ratings and his place (from 0) on the roster.
static func label_of_ratings(ratings: PlayerRatings, index: int) -> String:
	var who: String = ratings.display_name if ratings.display_name != "" else "%s %d" % [ratings.position, index + 1]
	return "#%d %s" % [ratings.number, who] if ratings.number > 0 else who


func _defense_row(label: String, p: PlayerLine) -> PackedStringArray:
	return PackedStringArray([label, str(p.tackles), str(p.sacks), str(p.interceptions), str(p.forced_fumbles), str(p.fumble_recoveries), str(p.return_td)])


## The team's players, the one with the most of `key` first.
func _sorted(team: Team, key: Callable) -> Array[Player]:
	var sorted: Array[Player] = team.squad.duplicate()
	sorted.sort_custom(func(a: Player, b: Player) -> bool:
		var left: int = key.call(players[a])
		var right: int = key.call(players[b])
		return left > right if left != right else a.index < b.index)
	return sorted


func _average(total: int, count: int) -> String:
	return "%.1f" % (float(total) / float(count)) if count > 0 else "0.0"


func _clock(seconds: float) -> String:
	var whole: int = roundi(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [whole / 60, whole % 60]
