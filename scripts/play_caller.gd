class_name PlayCaller
extends RefCounted
## Picks plays for the CPU. Never deterministic: every play keeps some chance.
## The defense weighs what the situation calls for against what the other team
## has actually been calling and gaining with, so leaning on one kind of play
## brings out its counters more and more often.

## How much one older play counts next to the newest one.
const MEMORY: float = 0.8
## Yards per play that count as the offense doing well.
const GOOD_GAIN: float = 8.0
## Higher = the best-fitting plays are picked more often.
const SHARPNESS: float = 3.0
const CATEGORIES: int = 3

## Per offensive team: how often it has called each category lately, and the
## yards it made with it. Both decay by MEMORY every play.
var _calls: Dictionary[Team, PackedFloat32Array] = {}
var _yards: Dictionary[Team, PackedFloat32Array] = {}
## Per offensive team: its last calls, newest last.
var _history: Dictionary[Team, Array] = {}


## Called at the whistle with the yards the offense made (0 on a turnover).
func record(team: Team, play: OffensePlay, gain: float) -> void:
	var calls: PackedFloat32Array = _row(_calls, team)
	var yards: PackedFloat32Array = _row(_yards, team)
	for i: int in CATEGORIES:
		calls[i] *= MEMORY
		yards[i] *= MEMORY
	calls[play.category] += 1.0
	yards[play.category] += gain
	_calls[team] = calls
	_yards[team] = yards
	var history: Array = _history.get(team, [])
	history.append(play)
	if history.size() > 4:
		history.pop_front()
	_history[team] = history


func pick_defense(plays: Array[DefensePlay], game: Game) -> DefensePlay:
	var expect: PackedFloat32Array = _situation(game)
	var calls: PackedFloat32Array = _row(_calls, game.offense)
	var yards: PackedFloat32Array = _row(_yards, game.offense)
	var seen: float = calls[0] + calls[1] + calls[2]
	if seen > 0.0:
		# The more that has been seen, the more the tendency counts (up to half).
		var trust: float = minf(seen / 4.0, 1.0) * 0.5
		var tendency: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
		var total: float = 0.0
		for i: int in CATEGORIES:
			# A category that is also working gets extra attention.
			var average: float = yards[i] / calls[i] if calls[i] > 0.05 else 0.0
			tendency[i] = calls[i] * clampf(0.5 + average / GOOD_GAIN, 0.5, 2.5)
			total += tendency[i]
		for i: int in CATEGORIES:
			expect[i] = lerpf(expect[i], tendency[i] / maxf(total, 0.001), trust)

	var weights: PackedFloat32Array = PackedFloat32Array()
	for play: DefensePlay in plays:
		var fit: float = 0.0
		for i: int in CATEGORIES:
			fit += expect[i] * play.fit(i as OffensePlay.Category)
		weights.append(pow(fit, SHARPNESS) + 0.01)
	return plays[_weighted(weights)]


func pick_offense(plays: Array[OffensePlay], game: Game) -> OffensePlay:
	var want: PackedFloat32Array = _situation(game)
	var history: Array = _history.get(game.offense, [])
	var weights: PackedFloat32Array = PackedFloat32Array()
	for play: OffensePlay in plays:
		var weight: float = want[play.category] + 0.05
		# Do not call the same play three times in a row.
		var repeats: int = 0
		for i: int in range(history.size() - 1, -1, -1):
			if history[i] != play:
				break
			repeats += 1
		if repeats >= 2:
			weight *= 0.05
		elif repeats == 1:
			weight *= 0.6
		weights.append(weight)
	return plays[_weighted(weights)]


## How likely each kind of play is from down and distance alone: run, short, deep.
func _situation(game: Game) -> PackedFloat32Array:
	var tuning: Tuning = game.tuning
	var to_go: float = absf(game.first_down_x - game.los_x)
	var downs_left: int = maxi(tuning.downs_per_series - game.down + 1, 1)
	# Yards needed per remaining down, against what a series needs on average.
	var need: float = (to_go / float(downs_left)) / (tuning.yards_to_gain / float(tuning.downs_per_series))
	var result: PackedFloat32Array = PackedFloat32Array([0.3, 0.4, 0.3])
	if need > 1.0:
		# Behind schedule: fewer runs, more shots downfield.
		var behind: float = clampf((need - 1.0) / 1.5, 0.0, 1.0)
		result = PackedFloat32Array([lerpf(0.3, 0.05, behind), lerpf(0.4, 0.3, behind), lerpf(0.3, 0.65, behind)])
	else:
		var ahead: float = clampf((1.0 - need) / 0.7, 0.0, 1.0)
		result = PackedFloat32Array([lerpf(0.3, 0.5, ahead), lerpf(0.4, 0.4, ahead), lerpf(0.3, 0.1, ahead)])
	return result


func _row(table: Dictionary[Team, PackedFloat32Array], team: Team) -> PackedFloat32Array:
	var fallback: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	return table.get(team, fallback)


func _weighted(weights: PackedFloat32Array) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += weight
	var roll: float = randf() * total
	for i: int in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1
