class_name SeasonSim
extends RefCounted
## A game of the season played on paper: the ones the person is not in. It goes
## play by play, by the rules of the real thing (four downs for Tuning's yards,
## two halves that each open with a scramble, a try after every touchdown,
## sudden death if it ends level), with dice in place of the footballers. What
## the dice are loaded with comes from the two rosters (Roster.team_ratings()
## and call_bias()), and every play is written into the same TeamLine and
## PlayerLine the real game keeps, so the season's numbers read the same
## whoever played.
##
## The numbers below were set against the box scores of CPU games
## (tests/stats_check.gd -- print): about 35 plays and 10 drives a side, 15
## yards a play, three passes in four caught, and scores in the fifties.

## Seconds of clock a play takes.
const PLAY_TIME: float = 4.2
const PLAY_TIME_SPREAD: float = 2.0
## How often it is a run, before the roster's leaning.
const RUN_SHARE: float = 0.5
## Of the passes, how many go deep.
const DEEP_SHARE: float = 0.4
const SACK_CHANCE: float = 0.2
const SACK_LOSS_MAX: int = 6
const INTERCEPTION_CHANCE: float = 0.06
const COMPLETION_SHORT: float = 0.86
const COMPLETION_DEEP: float = 0.7
const SHORT_YARDS: float = 15.0
const DEEP_YARDS: float = 40.0
## A run is stopped near the line, or breaks into the open.
const RUN_BREAK_CHANCE: float = 0.33
const RUN_SHORT_MAX: float = 9.0
const RUN_BREAK_YARDS: float = 40.0
const FUMBLE_CHANCE: float = 0.07
## A turnover is run back all the way this often.
const RETURN_TD_CHANCE: float = 0.45
const TRY_CHANCE: float = 0.44
## How often the man who brings the carrier down gets a tackle for it (the
## rest are dives, which the book does not count).
const TACKLE_CHANCE: float = 0.85
const FORCED_FUMBLE_CHANCE: float = 0.7
## Where a drive starts after a kickoff, and how far from midfield the
## scramble that opens a half is won, in yards from the team's own goal.
const KICKOFF_START_MIN: int = 18
const KICKOFF_START_MAX: int = 42
const SCRAMBLE_SPREAD: int = 14
## How much a point of rating between an offense and the defense in front of
## it moves the dice: yards (a share), and chances (added).
const EDGE_YARDS: float = 0.003
const EDGE_CHANCE: float = 0.0009
const FIELD: int = 100
## Sudden death that nobody wins in this many plays goes to a coin.
const OVERTIME_PLAYS_MAX: int = 200

var _tuning: Tuning
var _rosters: Array[Roster] = []
var _ratings: Array[Array] = []
var _bias: Array[PackedFloat32Array] = []
var _lines: Array[TeamLine] = []
var _players: Array[Array] = []
var _score: Array[int] = [0, 0]
var _clock: float = 0.0
var _overtime: bool = false
## Side with the ball (0 home, 1 away), yards from its own goal, down and yards to go.
var _offense: int = 0
var _spot: int = 0
var _down: int = 1
var _to_go: int = 0


## Plays the game between `home` and `away` of `season`'s round and books it.
static func play(season: Season, home: int, away: int) -> void:
	var sim: SeasonSim = SeasonSim.new()
	sim.run(season.team_data(home).roster, season.team_data(away).roster)
	season.record(home, away, sim._score[0], sim._score[1], sim._overtime, sim._lines, sim._players)


## The game between the two rosters, from the first scramble to the last
## whistle. The score is in `_score`, the book in `_lines` and `_players`.
func run(home: Roster, away: Roster, tuning: Tuning = null) -> void:
	_tuning = tuning if tuning != null else Tuning.new()
	_rosters = [home, away]
	for roster: Roster in _rosters:
		_ratings.append(roster.team_ratings())
		_bias.append(roster.call_bias())
		_lines.append(TeamLine.new())
		var lines: Array[PlayerLine] = []
		for i: int in roster.players.size():
			lines.append(PlayerLine.new())
		_players.append(lines)
	for half: int in 2:
		_clock = _tuning.game_length * 0.5
		_scramble()
		while _clock > 0.0:
			_play()
	if _score[0] == _score[1]:
		_overtime = true
		_scramble()
		var plays: int = 0
		while _score[0] == _score[1] and plays < OVERTIME_PLAYS_MAX:
			_play()
			plays += 1
		if _score[0] == _score[1]:
			_touchdown(randi() % 2, false)


# --- The game ------------------------------------------------------------------------

## The ball goes up at midfield and somebody comes down with it.
func _scramble() -> void:
	var side: int = randi() % 2
	_start_drive(side, FIELD / 2 + randi_range(-SCRAMBLE_SPREAD, SCRAMBLE_SPREAD))


func _start_drive(side: int, spot: int) -> void:
	_offense = side
	_spot = clampi(spot, 1, FIELD - 1)
	_down = 1
	_to_go = mini(roundi(_tuning.yards_to_gain), FIELD - _spot)
	_lines[side].drives += 1
	_lines[side].in_red_zone = false


## The kickoff after a score: `side` receives and runs it back.
func _kickoff_to(side: int) -> void:
	var start: int = randi_range(KICKOFF_START_MIN, KICKOFF_START_MAX)
	_lines[side].kick_returns += 1
	_lines[side].kick_return_yds += start
	_start_drive(side, start)


func _play() -> void:
	var off: int = _offense
	var def: int = 1 - off
	var line: TeamLine = _lines[off]
	var time: float = maxf(PLAY_TIME + randf_range(-PLAY_TIME_SPREAD, PLAY_TIME_SPREAD), 1.0)
	if not _overtime:
		time = minf(time, _clock)
		_clock -= time
		line.possession += time
	line.plays += 1
	var to_goal: int = FIELD - _spot
	if to_goal <= roundi(StatBook.RED_ZONE_YARDS) and not line.in_red_zone:
		line.in_red_zone = true
		line.red_zone_att += 1

	var bias: PackedFloat32Array = _bias[off]
	var run_weight: float = RUN_SHARE * bias[0]
	var short_weight: float = (1.0 - RUN_SHARE) * (1.0 - DEEP_SHARE) * bias[1]
	var deep_weight: float = (1.0 - RUN_SHARE) * DEEP_SHARE * bias[2]
	var roll: float = randf() * (run_weight + short_weight + deep_weight)
	var passing: bool = roll >= run_weight
	var gain: int = 0
	var turnover: bool = false
	var carrier: int = -1
	var down_by_contact: bool = true
	if passing:
		var edge: float = float(_rating(off, 0) - _rating(def, 2))
		var qb: int = _pick(off, ["QB"], &"accuracy")
		if randf() < clampf(SACK_CHANCE - edge * EDGE_CHANCE * 0.5, 0.02, 0.3):
			gain = -mini(randi_range(1, SACK_LOSS_MAX), _spot - 1)
			line.sacked += 1
			line.sacked_yds += -gain
			_line(off, qb).sacked += 1
			_line(off, qb).sacked_yds += -gain
			_line(def, _pick(def, ["LINE", "LINE", "RB", "QB"], &"tackling")).sacks += 1
			down_by_contact = false
		else:
			var deep: bool = roll >= run_weight + short_weight
			var target: int = _pick(off, ["WR", "WR", "RB"] if not deep else ["WR"], &"get_open")
			line.pass_att += 1
			_line(off, qb).pass_att += 1
			_line(off, target).targets += 1
			if randf() < clampf(INTERCEPTION_CHANCE - edge * EDGE_CHANCE * 0.3, 0.005, 0.2):
				line.pass_int += 1
				_line(off, qb).pass_int += 1
				_line(def, _pick(def, ["QB", "WR", "RB"], &"coverage")).interceptions += 1
				_change_hands(def, _spot + randi_range(3, 25), -1)
				return
			if randf() >= clampf((COMPLETION_DEEP if deep else COMPLETION_SHORT) + edge * EDGE_CHANCE, 0.2, 0.97):
				_next_down(0, false, false)
				return
			gain = mini(maxi(roundi(_spread(DEEP_YARDS if deep else SHORT_YARDS) * (1.0 + edge * EDGE_YARDS)), 1), to_goal)
			line.pass_comp += 1
			line.pass_yds += gain
			_line(off, qb).pass_comp += 1
			_line(off, qb).pass_yds += gain
			_line(off, target).add_catch(gain)
			carrier = target
			if gain >= to_goal:
				line.pass_td += 1
				_line(off, qb).pass_td += 1
				_line(off, target).rec_td += 1
	else:
		var edge: float = float(_rating(off, 1) - _rating(def, 3))
		# The back, now and then the quarterback keeping it or a receiver coming round.
		var who: float = randf()
		carrier = _pick(off, ["RB"] if who < 0.62 else (["QB"] if who < 0.94 else ["WR"]), &"speed")
		var yards: float = randf_range(-2.0, RUN_SHORT_MAX)
		if randf() < clampf(RUN_BREAK_CHANCE + edge * EDGE_CHANCE, 0.05, 0.6):
			yards = RUN_SHORT_MAX + _spread(RUN_BREAK_YARDS)
		gain = mini(roundi(yards * (1.0 + edge * EDGE_YARDS) if yards > 0.0 else yards), to_goal)
		gain = maxi(gain, -_spot + 1)
		_line(off, carrier).add_rush(gain)
		line.rush_att += 1
		line.rush_yds += gain
		if gain >= to_goal:
			line.rush_td += 1
			_line(off, carrier).rush_td += 1

	if gain >= to_goal:
		_next_down(gain, passing, true)
		_touchdown(off, true)
		return
	# Somebody brought him down, and perhaps knocked the ball out.
	if carrier >= 0 and down_by_contact:
		var tackler: int = _pick(def, ["QB", "LINE", "WR", "RB"], &"tackling")
		if randf() < FUMBLE_CHANCE:
			line.fumbles += 1
			if randf() < FORCED_FUMBLE_CHANCE:
				_line(def, tackler).forced_fumbles += 1
			if randf() < 0.6:
				turnover = true
				line.fumbles_lost += 1
				_line(off, carrier).fumbles_lost += 1
				_change_hands(def, _spot + gain, _pick(def, ["QB", "LINE", "WR", "RB"], &"speed"))
				return
		elif randf() < TACKLE_CHANCE:
			_line(def, tackler).tackles += 1
	if not turnover:
		_next_down(gain, passing, false)


## The down is over with the offense still in possession, `gain` yards on.
func _next_down(gain: int, passing: bool, scored: bool) -> void:
	var line: TeamLine = _lines[_offense]
	var moved: bool = scored or gain >= _to_go
	if moved:
		if passing:
			line.first_downs_pass += 1
		else:
			line.first_downs_rush += 1
	if _down == 3:
		line.third_att += 1
		line.third_made += int(moved)
	elif _down == 4:
		line.fourth_att += 1
		line.fourth_made += int(moved)
	if scored:
		return
	_spot += gain
	if moved:
		_down = 1
		_to_go = mini(roundi(_tuning.yards_to_gain), FIELD - _spot)
		return
	_down += 1
	_to_go -= gain
	if _down > _tuning.downs_per_series:
		_start_drive(1 - _offense, FIELD - _spot)


## `side` took the ball away at `spot` (in the old offense's yards). `recoverer`
## is who fell on a fumble, -1 for an interception.
func _change_hands(side: int, spot: int, recoverer: int) -> void:
	if recoverer >= 0:
		_line(side, recoverer).fumble_recoveries += 1
	if randf() < RETURN_TD_CHANCE:
		var scorer: int = recoverer if recoverer >= 0 else _pick(side, ["QB", "WR", "RB"], &"speed")
		_lines[side].return_td += 1
		_line(side, scorer).return_td += 1
		_touchdown(side, false)
		return
	_start_drive(side, FIELD - clampi(spot, 1, FIELD - 1))


## Six points for `side`, its try, and the kickoff to the other team. In
## sudden death the touchdown is the end of it.
func _touchdown(side: int, from_scrimmage: bool) -> void:
	var line: TeamLine = _lines[side]
	_score[side] += _tuning.touchdown_points
	line.touchdowns += 1
	if from_scrimmage and line.in_red_zone:
		line.red_zone_made += 1
	if _overtime:
		return
	line.tries_att += 1
	if randf() < TRY_CHANCE:
		line.tries_made += 1
		_score[side] += _tuning.conversion_points
	_kickoff_to(1 - side)


# --- The dice ------------------------------------------------------------------------

## The team's rating `row` of Roster.team_ratings(): 0 pass offense, 1 run
## offense, 2 pass defense, 3 run defense.
func _rating(side: int, row: int) -> int:
	return _ratings[side][row][1]


func _line(side: int, index: int) -> PlayerLine:
	return _players[side][index]


## One of the side's players at one of `positions` (a position named twice
## counts double), the better at `rating` the likelier. The first man of the
## roster if nobody plays there.
func _pick(side: int, positions: Array, rating: StringName) -> int:
	var roster: Roster = _rosters[side]
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total: float = 0.0
	for player: PlayerRatings in roster.players:
		var weight: float = 0.0
		if player != null:
			var value: int = player.get(rating)
			weight = float(positions.count(player.position)) * pow(maxf(float(value), 5.0) / 50.0, 2.0)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return 0
	var roll: float = randf() * total
	for i: int in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			return i
	return weights.size() - 1


## A gain of about `mean` yards: mostly less, now and then a great deal more.
func _spread(mean: float) -> float:
	return -log(maxf(randf(), 0.0001)) * mean
