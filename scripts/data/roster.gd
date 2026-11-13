class_name Roster
extends Resource
## A team's players, in the order of the Player nodes under the Team. Every play
## lists its assignments in the same order: QB, three linemen, two receivers,
## then the back.

## How strongly the CPU's play calling follows what the roster is good at: the
## power each strength's share of the average is raised to, and the least and
## the most a kind of play can come out at.
const BIAS_SHARPNESS: float = 3.0
const BIAS_MIN: float = 0.4
const BIAS_MAX: float = 2.0

@export var players: Array[PlayerRatings] = []


## How the CPU leans when it calls this roster's offense: a multiplier for each
## OffensePlay.Category (run, short, deep), worked out from who is on it, so it
## follows the players and not the team's name. A strong back behind good
## blockers runs more, a big arm with fast receivers goes deep more, an
## accurate quarterback with sure hands around him throws short more.
func call_bias() -> PackedFloat32Array:
	var strengths: PackedFloat32Array = _strengths()
	var average: float = maxf((strengths[0] + strengths[1] + strengths[2]) / 3.0, 1.0)
	var bias: PackedFloat32Array = PackedFloat32Array()
	for strength: float in strengths:
		bias.append(clampf(pow(strength / average, BIAS_SHARPNESS), BIAS_MIN, BIAS_MAX))
	return bias


## What the team select shows of this roster: [label, 0..100] for its passing
## and its running game and for how it defends each. Everyone plays both ways:
## the quarterback is the safety, the receivers the corners, the back the
## linebacker and the linemen the rush.
func team_ratings() -> Array[Array]:
	var strengths: PackedFloat32Array = _strengths()
	var qb: PlayerRatings = _first("QB")
	var pass_offense: float = (strengths[1] + strengths[2]) / 2.0
	# The back and his blockers, and a quarterback who can run it himself.
	var blocking: float = _mean(["LINE", "WR"], &"blocking")
	var run_offense: float = (float(_first("RB").overall()) * 2.0 + blocking * 2.0 + float(qb.speed + qb.juke) / 2.0) / 5.0
	var rush: float = _mean(["LINE"], &"strength")
	var pass_defense: float = (_mean(["QB", "WR", "RB"], &"coverage") * 2.0 + rush) / 3.0
	var run_defense: float = (_mean(["QB", "LINE", "WR", "RB"], &"tackling") * 2.0 + rush) / 3.0
	return [
		["PASS OFF", roundi(pass_offense)],
		["RUN OFF", roundi(run_offense)],
		["PASS DEF", roundi(pass_defense)],
		["RUN DEF", roundi(run_defense)],
	]


## How good this roster is at each OffensePlay.Category (run, short, deep), 0..100.
func _strengths() -> PackedFloat32Array:
	var qb: PlayerRatings = _first("QB")
	var back: PlayerRatings = _first("RB")
	var run: float = (float(back.overall()) + _mean(["LINE", "WR"], &"blocking")) / 2.0
	var short: float = (float(qb.accuracy) + _mean(["WR", "RB"], &"catching") + _mean(["WR", "RB"], &"get_open")) / 3.0
	# The arm counts double: nobody runs under a ball that does not get there.
	var deep: float = (float(qb.power) * 2.0 + (_mean(["WR"], &"speed") + _mean(["WR"], &"get_open")) / 2.0) / 3.0
	return PackedFloat32Array([run, short, deep])


## The first player at `position`, or an average one if there is none.
func _first(position: String) -> PlayerRatings:
	for player: PlayerRatings in players:
		if player != null and player.position == position:
			return player
	return PlayerRatings.new()


## The mean of `rating` over everyone at one of `positions`, 50 with nobody there.
func _mean(positions: Array[String], rating: StringName) -> float:
	var sum: float = 0.0
	var count: int = 0
	for player: PlayerRatings in players:
		if player != null and positions.has(player.position):
			var value: int = player.get(rating)
			sum += float(value)
			count += 1
	return sum / float(count) if count > 0 else 50.0
