class_name DefenseAligner
extends RefCounted
## Where a defensive play lines up against the offense in front of it. A play
## draws a spot for every defender; this moves those spots to fit the
## formation, the way a defense checks its alignment before the snap:
## corners go out with the widest receivers, somebody walks out over a slot,
## the safeties and linebackers slide toward the side with more receivers. What
## each defender does after the snap (his man, his zone, his rush) stays as the
## play draws it.
##
## Everything is read from where the offense stands, never from what its play
## is going to be. All points are in the offense's frame as it is lined up on
## the field: x = yards past the line of scrimmage, y = yards to the offense's
## right of the ball.

## A receiver this far from the ball is split out: a wideout, a slot or a wing.
const DETACHED: float = 4.6
## Anybody deeper than this behind the line is a back.
const BACKFIELD: float = -2.5
## Closer to the ball than this and up at the line: one of the three linemen.
const LINE_WIDTH: float = 2.6
const LINE_DEPTH: float = -1.5
## How far inside the receiver a zone corner lines up, to see the quarterback.
const CORNER_SHADE: float = 1.5
## A corner who is coming on a blitz cheats this far inside his receiver.
const BLITZ_CHEAT: float = 2.5
## With nobody split out on his side a corner comes in to this far outside the
## last man on the line.
const EDGE_GAP: float = 3.0
## A zone defender walked out over a slot stands this share of the way from the
## edge of the box to him.
const APEX: float = 0.6
## A defender drawn closer to the ball than this can walk out to either side.
const MIDDLE: float = 3.5
const BOX_EDGE: float = 2.5
## Yards the deep men and the men underneath slide toward the strong side for
## every receiver it has more than the other side, and the most they slide.
const DEEP_SHIFT: float = 1.5
const UNDER_SHIFT: float = 1.0
const MAX_LEAD: float = 2.0
## What a tight end counts for when both sides have as many split receivers.
const TIGHT_END_LEAD: float = 0.5
## Defenders this deep or deeper count as the deep men.
const DEEP_START: float = 9.0
## Two defenders closer than this are standing in each other: the second one
## steps back by STACK_STEP.
const STACK_GAP: float = 1.2
const STACK_STEP: float = 1.5

## The offense's players other than the quarterback and the three linemen.
var skill: Array[Vector2] = []
## Indices into `skill` of the men split out on each side, widest first.
var left: Array[int] = []
var right: Array[int] = []
## The side with more to defend: -1 left, +1 right, 0 balanced. `lead` is by
## how many receivers.
var strength: int = 0
var lead: float = 0.0
## How far out the last man on the line stands on the left and on the right.
var edge_left: float = 0.0
var edge_right: float = 0.0


## `spots`: every offensive player but the quarterback.
static func read(spots: Array[Vector2]) -> DefenseAligner:
	var formation: DefenseAligner = DefenseAligner.new()
	var tight: int = 0
	for spot: Vector2 in spots:
		var width: float = absf(spot.y)
		if spot.x > BACKFIELD and width < DETACHED:
			if spot.y < 0.0:
				formation.edge_left = maxf(formation.edge_left, width)
			else:
				formation.edge_right = maxf(formation.edge_right, width)
		if width < LINE_WIDTH and spot.x > LINE_DEPTH:
			continue
		formation.skill.append(spot)
		var index: int = formation.skill.size() - 1
		if spot.x < BACKFIELD:
			continue
		if width >= DETACHED:
			if spot.y < 0.0:
				formation.left.append(index)
			else:
				formation.right.append(index)
		else:
			tight += 1 if spot.y > 0.0 else -1
	var wider: Callable = func(a: int, b: int) -> bool: return absf(formation.skill[a].y) > absf(formation.skill[b].y)
	formation.left.sort_custom(wider)
	formation.right.sort_custom(wider)
	var more: int = formation.right.size() - formation.left.size()
	if more != 0:
		formation.strength = signi(more)
		formation.lead = minf(float(absi(more)), MAX_LEAD)
	elif tight != 0:
		formation.strength = signi(tight)
		formation.lead = TIGHT_END_LEAD
	return formation


## The formation an offensive play lines up in, read from the play itself.
static func read_play(play: OffensePlay, flipped: bool) -> DefenseAligner:
	var spots: Array[Vector2] = []
	for assignment: OffenseAssignment in play.assignments:
		if assignment.job != OffenseAssignment.Job.QB:
			spots.append(Vector2(assignment.start.x, -assignment.start.y if flipped else assignment.start.y))
	return read(spots)


## Whether the CPU runs `play` mirrored against this offense. A play drawn with
## one side different from the other (an overload, a corner blitz, a rolled
## coverage) says with DefensePlay.strength_side where that side belongs;
## everything else goes to either side.
static func cpu_flip(play: DefensePlay, offense: OffensePlay, offense_flipped: bool) -> bool:
	var formation: DefenseAligner = read_play(offense, offense_flipped)
	if play.strength_side == 0 or formation.strength == 0:
		return randf() < 0.5
	return formation.strength * play.strength_side < 0


## Who the man defenders cover, as indices into `skill`: DefenseAssignment
## .man_target 0 is the widest receiver on the left, 1 the widest on the right,
## 2 the back and 3 whoever is left (the tight end, the fullback, a slot). With
## nobody split out on a side its corner takes the next widest man, and without
## a back number 2 is the inside receiver on the right.
func man_order() -> PackedInt32Array:
	var pool: Array[int] = []
	for i: int in skill.size():
		pool.append(i)
	var order: PackedInt32Array = PackedInt32Array()
	if pool.is_empty():
		return order
	var first: int = left[0] if not left.is_empty() else -1
	var second: int = right[0] if not right.is_empty() else -1
	pool.erase(first)
	pool.erase(second)
	if first < 0 and not pool.is_empty():
		first = _pick(pool, -1.0)
		pool.erase(first)
	if second < 0 and not pool.is_empty():
		second = _pick(pool, 1.0)
		pool.erase(second)
	for index: int in [first, second]:
		if index >= 0:
			order.append(index)
	# The back: the deepest man behind the line. Otherwise the one further right.
	var back: int = -1
	for index: int in pool:
		if skill[index].x < BACKFIELD and (back < 0 or skill[index].x < skill[back].x):
			back = index
	if back < 0 and not pool.is_empty():
		back = _pick(pool, 1.0)
	if back >= 0:
		order.append(back)
		pool.erase(back)
	order.append_array(PackedInt32Array(pool))
	return order


## The place in man_order() of the receiver a man defender covers. A mirrored
## play swaps the two outside receivers.
static func man_index(assignment: DefenseAssignment, flip: float) -> int:
	if flip < 0.0 and assignment.man_target <= 1:
		return 1 - assignment.man_target
	return assignment.man_target


## The man in `pool` for a corner with nobody split out on his own side
## (`side` -1 left, +1 right): the widest split receiver that is left, or
## without one the man standing furthest out on his side.
func _pick(pool: Array[int], side: float) -> int:
	var best: int = pool[0]
	var best_score: float = -INF
	for index: int in pool:
		var spot: Vector2 = skill[index]
		var split: bool = absf(spot.y) >= DETACHED and spot.x >= BACKFIELD
		var score: float = 100.0 + absf(spot.y) if split else spot.y * side
		if score > best_score:
			best_score = score
			best = index
	return best


## Where each defender of `play` lines up: one point per assignment. `flip` of
## -1 runs the play mirrored. `depths` are the depths to use instead of the
## drawn ones (the play squeezed up near the goal line), one per assignment.
func starts(play: DefensePlay, flip: float, depths: PackedFloat32Array) -> PackedVector2Array:
	var count: int = play.assignments.size()
	var result: PackedVector2Array = PackedVector2Array()
	var order: PackedInt32Array = man_order()
	var covered: Array[int] = []
	for i: int in count:
		var assignment: DefenseAssignment = play.assignments[i]
		var spot: Vector2 = Vector2(depths[i], assignment.start.y * flip)
		if assignment.job == DefenseAssignment.Job.MAN and not order.is_empty():
			var target: int = order[mini(man_index(assignment, flip), order.size() - 1)]
			spot.y = skill[target].y
			if not covered.has(target):
				covered.append(target)
		result.append(spot)

	# Corners go out with the widest receiver of their side.
	for i: int in count:
		var assignment: DefenseAssignment = play.assignments[i]
		if assignment.job == DefenseAssignment.Job.MAN or assignment.align != DefenseAssignment.Align.OUTSIDE:
			continue
		var side: float = -1.0 if result[i].y < 0.0 else 1.0
		var receivers: Array[int] = left if side < 0.0 else right
		var edge: float = edge_left if side < 0.0 else edge_right
		var drawn: float = absf(result[i].y)
		var wide: int = -1
		for index: int in receivers:
			if not covered.has(index):
				wide = index
				break
		if wide >= 0:
			# A corner who is coming still shows coverage on his man: nobody else
			# leaves his zone for him, and the receiver is the hot throw.
			covered.append(wide)
			var out: float = absf(skill[wide].y)
			if assignment.job == DefenseAssignment.Job.RUSH:
				out = maxf(minf(out - BLITZ_CHEAT, drawn + BLITZ_CHEAT), edge + 1.5)
			else:
				out -= CORNER_SHADE
			result[i] = Vector2(result[i].x, side * out)
		elif receivers.is_empty():
			result[i] = Vector2(result[i].x, side * minf(drawn, edge + EDGE_GAP))

	# Whoever is still uncovered out there gets the nearest man who may walk out.
	var needs: Array[int] = []
	for index: int in left + right:
		if not covered.has(index):
			needs.append(index)
	needs.sort_custom(func(a: int, b: int) -> bool: return absf(skill[a].y) > absf(skill[b].y))
	var walked: Array[int] = []
	for index: int in needs:
		var receiver: Vector2 = skill[index]
		var best: int = -1
		var best_gap: float = INF
		for i: int in count:
			var assignment: DefenseAssignment = play.assignments[i]
			if assignment.job == DefenseAssignment.Job.MAN or assignment.align != DefenseAssignment.Align.SLOT or walked.has(i):
				continue
			# Not across the formation: his zone is on his own side.
			var drawn: float = assignment.start.y * flip
			if absf(drawn) >= MIDDLE and drawn * receiver.y < 0.0:
				continue
			var gap: float = absf(drawn - receiver.y)
			if gap < best_gap:
				best_gap = gap
				best = i
		if best >= 0:
			walked.append(best)
			var side: float = signf(receiver.y)
			result[best] = Vector2(result[best].x, lerpf(side * BOX_EDGE, receiver.y, APEX))

	# The rest of the coverage slides toward the strong side.
	for i: int in count:
		var assignment: DefenseAssignment = play.assignments[i]
		if assignment.job == DefenseAssignment.Job.MAN or walked.has(i):
			continue
		var slides: bool = assignment.align == DefenseAssignment.Align.STRENGTH or assignment.align == DefenseAssignment.Align.SLOT
		if slides and strength != 0:
			var step: float = DEEP_SHIFT if assignment.start.x >= DEEP_START else UNDER_SHIFT
			result[i] = Vector2(result[i].x, result[i].y + float(strength) * lead * step)

	# Nobody stands inside a teammate: the later one steps back.
	for i: int in count:
		for _step: int in count:
			var taken: bool = false
			for j: int in i:
				if result[j].distance_to(result[i]) < STACK_GAP:
					taken = true
			if not taken:
				break
			result[i] = Vector2(result[i].x + STACK_STEP, result[i].y)
	return result
