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
## Run, short and deep shares an offense out of time moves toward, and the ones
## an offense running the clock down moves toward.
const HURRY_MIX: Array[float] = [0.0, 0.25, 0.75]
const KILL_MIX: Array[float] = [0.8, 0.18, 0.02]
## Plays the starting guess of a play's length is worth. See situation().
const TIME_PRIOR: float = 4.0
## What a goal line play's chance of being called is multiplied by near the goal
## line and away from it. See _goal_line_scale().
const GOAL_LINE_NEAR: float = 6.0
const GOAL_LINE_FAR: float = 0.02

## Per offensive team: how often it has called each category lately, and the
## yards it made with it. Both decay by MEMORY every play.
var _calls: Dictionary[Team, PackedFloat32Array] = {}
var _yards: Dictionary[Team, PackedFloat32Array] = {}
## Per offensive team: its last calls, newest last.
var _history: Dictionary[Team, Array] = {}
## Seconds of clock the plays so far have taken, and how many there were.
var _time_sum: float = 0.0
var _time_count: float = 0.0


## What the score and the clock ask of the offense on the next play.
func situation(game: Game) -> GameSituation:
	return GameSituation.read(game, play_time(game))


## Seconds of clock a play takes on average, as seen so far.
func play_time(game: Game) -> float:
	# The starting guess counts as a few plays, so one odd play does not swing it.
	return (game.tuning.ai_call_play_time * TIME_PRIOR + _time_sum) / (TIME_PRIOR + _time_count)


## Called at the whistle with the yards the offense made (0 on a turnover) and
## the seconds the play took off the clock.
func record(team: Team, play: OffensePlay, gain: float, seconds: float = -1.0) -> void:
	if seconds >= 0.0:
		_time_sum += seconds
		_time_count += 1.0
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


## Share of `team`'s recent calls that were runs (0..1). A third before it has
## called anything.
func run_share(team: Team) -> float:
	var calls: PackedFloat32Array = _row(_calls, team)
	var seen: float = calls[0] + calls[1] + calls[2]
	if seen <= 0.0:
		return 1.0 / 3.0
	return calls[OffensePlay.Category.RUN] / seen


func pick_defense(plays: Array[DefensePlay], game: Game) -> DefensePlay:
	var expect: PackedFloat32Array = _situation(game)
	var calls: PackedFloat32Array = _row(_calls, game.offense)
	var yards: PackedFloat32Array = _row(_yards, game.offense)
	var seen: float = calls[0] + calls[1] + calls[2]
	if seen > 0.0:
		# The more that has been seen, the more the tendency counts (up to half).
		var trust: float = minf(seen / 4.0, 1.0) * 0.5
		# When the clock dictates the call, what they did earlier says little.
		var now: GameSituation = situation(game)
		trust *= 1.0 - (1.0 if now.heave else maxf(now.urgency, now.clock_kill))
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
		weights.append((pow(fit, SHARPNESS) + 0.01) * _goal_line_scale(play.goal_line, game))
	return plays[_weighted(weights)]


func pick_offense(plays: Array[OffensePlay], game: Game) -> OffensePlay:
	if situation(game).heave:
		# One play to reach the end zone: a deep pass, the deeper the better, and
		# no time for a fake.
		var deep: PackedFloat32Array = PackedFloat32Array()
		var any: float = 0.0
		for play: OffensePlay in plays:
			var depth: float = play.deepest_route() if play.category == OffensePlay.Category.DEEP else 0.0
			if play.play_action:
				depth *= 0.5
			deep.append(depth * depth)
			any += depth
		if any > 0.0:
			return plays[_weighted(deep)]
	var want: PackedFloat32Array = _situation(game)
	# What this team likes to call, less and less as the clock takes over.
	var now: GameSituation = situation(game)
	var own_way: float = 1.0 - maxf(now.urgency, now.clock_kill)
	for i: int in CATEGORIES:
		want[i] *= lerpf(1.0, game.offense.call_bias[i], own_way)
	var history: Array = _history.get(game.offense, [])
	# Shared out over the plays of a category, so a playbook with more runs than
	# deep passes does not run more often for it.
	var per_category: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	# Goal line plays away from the goal line are as good as not in the book.
	for play: OffensePlay in plays:
		if _goal_line_scale(play.goal_line, game) >= 1.0:
			per_category[play.category] += 1.0
	var weights: PackedFloat32Array = PackedFloat32Array()
	for play: OffensePlay in plays:
		var weight: float = (want[play.category] + 0.05) / maxf(per_category[play.category], 1.0)
		weight *= _goal_line_scale(play.goal_line, game)
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


## How likely each kind of play is: run, short, deep. From down and distance
## first, then moved by what the score and the clock ask for.
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

	var now: GameSituation = situation(game)
	if now.heave:
		return PackedFloat32Array([0.0, 0.0, 1.0])
	# With no punts a failed fourth down hands the ball over where it lies, so
	# well behind schedule the first down still matters more than the clock.
	var kill: float = now.clock_kill * (0.5 if need > 1.5 else 1.0)
	for i: int in CATEGORIES:
		result[i] = lerpf(result[i], HURRY_MIX[i], now.urgency)
		result[i] = lerpf(result[i], KILL_MIX[i], kill)
	# Comeback assist: well behind, take a few more shots; well ahead, sit on it.
	var lean: float = tuning.comeback_ai_shift * RubberBand.strength(game)
	if lean > 0.0 and now.margin != 0:
		var mix: Array[float] = HURRY_MIX if now.margin < 0 else KILL_MIX
		if now.margin > 0:
			lean *= tuning.comeback_max_penalty / maxf(tuning.comeback_max_boost, 0.001)
		for i: int in CATEGORIES:
			result[i] = lerpf(result[i], mix[i], lean)
	return result


## How much more or less often a play is called for where the ball is: a goal
## line play close to the goal line comes up more, anywhere else almost never.
func _goal_line_scale(goal_line_play: bool, game: Game) -> float:
	if not goal_line_play:
		return 1.0
	var dir: int = game.offense.attack_dir
	var to_goal: float = (game.tuning.goal_x(dir) - game.los_x) * float(dir)
	return GOAL_LINE_NEAR if to_goal <= game.tuning.ai_goal_line_distance else GOAL_LINE_FAR


func _row(table:Dictionary[Team, PackedFloat32Array], team: Team) -> PackedFloat32Array:
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
