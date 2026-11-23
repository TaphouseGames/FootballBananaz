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
## What a shot play's chance of being called is multiplied by on an ordinary
## down, and when the offense needs a lot at once. See _shot_scale().
const SHOT_ORDINARY: float = 0.2
const SHOT_NEEDED: float = 3.0
## Points behind in the second half that make every down a down for a shot.
const SHOT_DEFICIT: float = 12.0

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
	return plays[_weighted(_defense_weights(plays, game))]


func pick_offense(plays: Array[OffensePlay], game: Game) -> OffensePlay:
	if situation(game).heave:
		var deep: PackedFloat32Array = _heave_weights(plays)
		if _sum(deep) > 0.0:
			return plays[_weighted(deep)]
	return plays[_weighted(_offense_weights(plays, game))]


## The coach's advice to an offense: `count` plays for this down, the first one
## his first choice. As many runs, short and deep passes as the situation asks
## for, the kind it asks for most first. Which plays of a kind is drawn afresh
## every time, as plays of a kind mostly fit an ordinary down equally well.
func coach_offense(plays: Array[OffensePlay], game: Game, count: int = HUD.PAGE_SIZE) -> Array[OffensePlay]:
	var picks: Array[OffensePlay] = []
	if situation(game).heave:
		# The deepest throws in the book, deepest first.
		var deep: PackedFloat32Array = _heave_weights(plays)
		for i: int in _ranked(deep):
			if picks.size() < count and deep[i] > 0.0:
				picks.append(plays[i])
		if picks.size() >= count:
			return picks
	var weights: PackedFloat32Array = _offense_weights(plays, game)
	# What can be drawn, by kind. A goal line play away from the goal line and
	# the heave-only play are not advice for this down.
	var pools: Array[Array] = [[], [], []]
	for i: int in plays.size():
		var play: OffensePlay = plays[i]
		if weights[i] > 0.0 and not picks.has(play) and _goal_line_scale(play.goal_line, game) >= 1.0:
			pools[play.category].append(i)
			# Nine draws with no play twice would thin the goal line plays out
			# among the many others of the book: here they come first.
			if play.goal_line:
				weights[i] *= GOAL_LINE_NEAR
	var sizes: PackedInt32Array = PackedInt32Array([pools[0].size(), pools[1].size(), pools[2].size()])
	var want: PackedFloat32Array = _offense_want(game)
	if situation(game).to_goal <= game.tuning.ai_goal_line_distance:
		# No room left for a deep ball: those slots go to short passes.
		want[OffensePlay.Category.SHORT] += want[OffensePlay.Category.DEEP]
		want[OffensePlay.Category.DEEP] = 0.0
	var slots: PackedInt32Array = _share_out(want, count - picks.size(), sizes)
	var order: Array[int] = [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return slots[a] > slots[b] or (slots[a] == slots[b] and a < b))
	for category: int in order:
		var pool: Array = pools[category]
		for n: int in slots[category]:
			var left: PackedFloat32Array = PackedFloat32Array()
			for i: int in pool:
				left.append(weights[i])
			var drawn: int = _weighted(left)
			picks.append(plays[pool[drawn]])
			pool.remove_at(drawn)
	return picks


## The coach's advice to a defense: the `count` plays that hold up best against
## what the offense is likely to call, the best first.
func coach_defense(plays: Array[DefensePlay], game: Game, count: int = HUD.PAGE_SIZE) -> Array[DefensePlay]:
	var weights: PackedFloat32Array = _defense_weights(plays, game)
	var picks: Array[DefensePlay] = []
	var spare: Array[DefensePlay] = []
	for i: int in _ranked(weights):
		# A goal line stand away from the goal line only when nothing else is left.
		if _goal_line_scale(plays[i].goal_line, game) >= 1.0:
			picks.append(plays[i])
		else:
			spare.append(plays[i])
	picks.append_array(spare)
	return picks.slice(0, count)


## How much each defensive play is worth calling now: how well it holds up
## against what the offense is likely to call, by the situation and by what it
## has been calling and gaining with.
func _defense_weights(plays: Array[DefensePlay], game: Game) -> PackedFloat32Array:
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
	return weights


## One play to reach the end zone: a deep pass, the deeper the better, and no
## time for a fake. All zero in a book with no deep pass.
func _heave_weights(plays: Array[OffensePlay]) -> PackedFloat32Array:
	var deep: PackedFloat32Array = PackedFloat32Array()
	for play: OffensePlay in plays:
		var depth: float = play.deepest_route() if play.category == OffensePlay.Category.DEEP else 0.0
		if play.play_action or play.flea_flicker:
			depth *= 0.5
		deep.append(depth * depth)
	return deep


## How much the offense wants a run, a short and a deep pass now: what the
## situation asks for, and what this team likes to call, less and less as the
## clock takes over.
func _offense_want(game: Game) -> PackedFloat32Array:
	var want: PackedFloat32Array = _situation(game)
	var now: GameSituation = situation(game)
	var own_way: float = 1.0 - maxf(now.urgency, now.clock_kill)
	for i: int in CATEGORIES:
		want[i] *= lerpf(1.0, game.offense.call_bias[i], own_way)
	return want


## How much each offensive play is worth calling now, the last-play heave aside.
func _offense_weights(plays: Array[OffensePlay], game: Game) -> PackedFloat32Array:
	var want: PackedFloat32Array = _offense_want(game)
	var now: GameSituation = situation(game)
	var history: Array = _history.get(game.offense, [])
	# Shared out over the plays of a category, so a playbook with more runs than
	# deep passes does not run more often for it.
	var per_category: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	# Goal line plays away from the goal line are as good as not in the book.
	for play: OffensePlay in plays:
		if _goal_line_scale(play.goal_line, game) >= 1.0 and not play.heave_only:
			per_category[play.category] += 1.0
	var weights: PackedFloat32Array = PackedFloat32Array()
	for play: OffensePlay in plays:
		if play.heave_only:
			weights.append(0.0)
			continue
		var weight: float = (want[play.category] + 0.05) / maxf(per_category[play.category], 1.0)
		weight *= _goal_line_scale(play.goal_line, game) * play.cpu_weight
		if play.shot_play:
			weight *= _shot_scale(game, now)
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
	return weights


## How likely each kind of play is: run, short, deep. From down and distance
## first, then moved by what the score and the clock ask for.
func _situation(game: Game) -> PackedFloat32Array:
	var tuning: Tuning = game.tuning
	var need: float = _need(game)
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


## Yards needed per remaining down, against what a series needs on average:
## 1 is on schedule, 2 is second and twice as long.
func _need(game: Game) -> float:
	var tuning: Tuning = game.tuning
	var to_go: float = absf(game.first_down_x - game.los_x)
	var downs_left: int = maxi(tuning.downs_per_series - game.down + 1, 1)
	return (to_go / float(downs_left)) / (tuning.yards_to_gain / float(tuning.downs_per_series))


## How much more or less often a shot play (OffensePlay.shot_play) is called:
## seldom on an ordinary down, often in long yardage, with the half running
## out, or well behind in the second half.
func _shot_scale(game: Game, now: GameSituation) -> float:
	var long_yardage: float = clampf(_need(game) - 1.0, 0.0, 1.0)
	var behind: float = 0.0
	if game.half >= 2 and now.margin < 0:
		behind = clampf(float(-now.margin) / SHOT_DEFICIT, 0.0, 1.0)
	return lerpf(SHOT_ORDINARY, SHOT_NEEDED, maxf(long_yardage, maxf(now.urgency, behind)))


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


## `count` slots shared out over the three kinds of play in proportion to
## `want`, no kind getting more than it has plays (`sizes`). Whole slots first,
## then the largest remainders.
func _share_out(want: PackedFloat32Array, count: int, sizes: PackedInt32Array) -> PackedInt32Array:
	var slots: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var total: float = maxf(_sum(want), 0.001)
	var left: int = count
	for i: int in CATEGORIES:
		slots[i] = mini(floori(want[i] / total * float(count)), sizes[i])
		left -= slots[i]
	while left > 0:
		var best: int = -1
		var best_due: float = -INF
		for i: int in CATEGORIES:
			var due: float = want[i] / total * float(count) - float(slots[i])
			if slots[i] < sizes[i] and due > best_due:
				best = i
				best_due = due
		if best < 0:
			break
		slots[best] += 1
		left -= 1
	return slots


## The indices of `weights`, the heaviest first; equal ones in their own order.
func _ranked(weights: PackedFloat32Array) -> Array[int]:
	var order: Array[int] = []
	for i: int in weights.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return weights[a] > weights[b] or (weights[a] == weights[b] and a < b))
	return order


func _sum(values: PackedFloat32Array) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total


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
