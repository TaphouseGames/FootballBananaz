extends RefCounted
## Shared by play_audit_dump.gd and playbook_rules_check.gd: the offensive
## formations every defensive play is lined up against, and the measures that
## tell whether two plays are the same play (or one the mirror of the other).

## Two plays whose every player does the same within this many yards are one play.
const SAME_PLAY: float = 2.5
## Starts further apart than this are different formations.
const SAME_SPOT: float = 1.5
## Yards of a route that are compared, and the points it is sampled at.
const ROUTE_LENGTH: float = 25.0
const SAMPLES: int = 6
## A receiver this far from the ball is split out from the formation.
const DETACHED: float = 4.6

const LINE: Array[Vector2] = [Vector2(-0.6, 0.0), Vector2(-0.9, -1.7), Vector2(-0.9, 1.7)]


## Name -> a bare offensive play in that formation (every skill player with a
## short route, so all of them count as receivers).
static func formations() -> Dictionary[String, OffensePlay]:
	var result: Dictionary[String, OffensePlay] = {}
	result["2-wide"] = _formation(-4.0, [Vector2(-0.6, -18.4), Vector2(-0.6, 18.4), Vector2(-6.5, 0.4), Vector2(-0.6, 3.4)])
	result["trips"] = _formation(-7.0, [Vector2(-0.6, 11.2), Vector2(-0.6, 19.9), Vector2(-7.0, -2.5), Vector2(-1.5, 5.4)])
	result["4-wide"] = _formation(-7.0, [Vector2(-0.6, -18.4), Vector2(-0.6, 18.4), Vector2(-1.2, -8.3), Vector2(-1.2, 8.3)])
	result["empty 3x1"] = _formation(-7.0, [Vector2(-0.6, -18.4), Vector2(-0.6, 19.9), Vector2(-1.2, 12.0), Vector2(-1.2, 6.0)])
	result["bunch"] = _formation(-7.0, [Vector2(-0.6, 10.0), Vector2(-1.6, 12.2), Vector2(-7.0, -2.5), Vector2(-1.6, 7.8)])
	result["heavy"] = _formation(-4.0, [Vector2(-0.6, -3.4), Vector2(-0.6, 3.4), Vector2(-6.5, 0.4), Vector2(-4.5, 1.8)])
	return result


static func _formation(qb_depth: float, skill: Array[Vector2]) -> OffensePlay:
	var play: OffensePlay = OffensePlay.new()
	play.play_name = "Probe"
	play.assignments.append(_assignment("QB", OffenseAssignment.Job.QB, Vector2(qb_depth, 0.0)))
	for spot: Vector2 in LINE:
		play.assignments.append(_assignment("L", OffenseAssignment.Job.BLOCK, spot))
	for spot: Vector2 in skill:
		var receiver: OffenseAssignment = _assignment("R", OffenseAssignment.Job.ROUTE, spot)
		receiver.route = PackedVector2Array([Vector2(8.0, 0.0)])
		play.assignments.append(receiver)
	return play


static func _assignment(label: String, job: OffenseAssignment.Job, start: Vector2) -> OffenseAssignment:
	var assignment: OffenseAssignment = OffenseAssignment.new()
	assignment.label = label
	assignment.job = job
	assignment.start = start
	return assignment


## The line-up of a play as text: two plays with the same key look the same
## before the snap.
static func formation_key(play: OffensePlay) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for assignment: OffenseAssignment in play.assignments:
		parts.append("%.1f,%.1f" % [assignment.start.x, assignment.start.y])
	return " | ".join(parts)


## The skill players' spots only, for a table.
static func skill_spots(play: OffensePlay) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for assignment: OffenseAssignment in play.assignments:
		if LINE.has(assignment.start):
			continue
		parts.append("%s (%.1f, %.1f)" % [assignment.label, assignment.start.x, assignment.start.y])
	return ", ".join(parts)


static func play_type(play: OffensePlay) -> String:
	if play.flea_flicker:
		return "trick"
	if play.play_action:
		return "play-action"
	if play.is_run:
		return "run"
	for assignment: OffenseAssignment in play.assignments:
		if assignment.job == OffenseAssignment.Job.ROUTE and assignment.settle and assignment.start.x + _last(assignment.route).x < 0.0:
			return "screen"
	return ["run", "short pass", "deep pass"][play.category]


static func _last(route: PackedVector2Array) -> Vector2:
	return route[route.size() - 1] if route.size() > 0 else Vector2.ZERO


## How far apart two offensive plays are: the most any one player's path
## differs, in yards, with `b` mirrored left to right if `mirror`. INF when they
## line up differently, hand the ball off differently or give a player another job.
static func offense_distance(a: OffensePlay, b: OffensePlay, mirror: bool) -> float:
	if a.is_run != b.is_run or a.play_action != b.play_action or a.flea_flicker != b.flea_flicker:
		return INF
	if a.assignments.size() != b.assignments.size():
		return INF
	var used: Array[int] = []
	var worst: float = 0.0
	for mine: OffenseAssignment in a.assignments:
		var best: int = -1
		var best_gap: float = SAME_SPOT
		for j: int in b.assignments.size():
			if used.has(j):
				continue
			var gap: float = mine.start.distance_to(_side(b.assignments[j].start, mirror))
			if gap <= best_gap:
				best_gap = gap
				best = j
		if best < 0:
			return INF
		used.append(best)
		var other: OffenseAssignment = b.assignments[best]
		if mine.job != other.job or mine.settle != other.settle:
			return INF
		var path_a: PackedVector2Array = _path(mine, false)
		var path_b: PackedVector2Array = _path(other, mirror)
		for i: int in SAMPLES:
			worst = maxf(worst, path_a[i].distance_to(path_b[i]))
	return worst


static func _side(point: Vector2, mirror: bool) -> Vector2:
	return Vector2(point.x, -point.y) if mirror else point


## SAMPLES points along the first ROUTE_LENGTH yards of a player's path.
static func _path(assignment: OffenseAssignment, mirror: bool) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([_side(assignment.start, mirror)])
	for waypoint: Vector2 in assignment.route:
		points.append(_side(assignment.start + waypoint, mirror))
	# Receivers keep running in the direction of the last leg.
	if points.size() > 1 and not assignment.settle and assignment.job != OffenseAssignment.Job.QB:
		var last: Vector2 = points[points.size() - 1]
		points.append(last + (last - points[points.size() - 2]).normalized() * ROUTE_LENGTH)
	var result: PackedVector2Array = PackedVector2Array()
	for i: int in SAMPLES:
		result.append(_along(points, ROUTE_LENGTH * float(i + 1) / float(SAMPLES)))
	return result


static func _along(points: PackedVector2Array, distance: float) -> Vector2:
	var left: float = distance
	for i: int in range(1, points.size()):
		var leg: float = points[i - 1].distance_to(points[i])
		if leg >= left and leg > 0.0:
			return points[i - 1].lerp(points[i], left / leg)
		left -= leg
	return points[points.size() - 1]


## The same for two defensive plays: the most any defender's spot or zone differs.
static func defense_distance(a: DefensePlay, b: DefensePlay, mirror: bool) -> float:
	var used: Array[int] = []
	var worst: float = 0.0
	for mine: DefenseAssignment in a.assignments:
		var best: int = -1
		var best_gap: float = SAME_PLAY
		for j: int in b.assignments.size():
			var other: DefenseAssignment = b.assignments[j]
			if used.has(j) or other.job != mine.job:
				continue
			var gap: float = mine.start.distance_to(_side(other.start, mirror))
			if mine.job == DefenseAssignment.Job.MAN:
				# Man defenders stand where their man stands: only the depth is theirs.
				gap = absf(mine.start.x - other.start.x)
				if _man_side(mine, false) != _man_side(other, mirror) or mine.underneath != other.underneath:
					continue
			elif mine.job == DefenseAssignment.Job.ZONE:
				if mine.deep != other.deep:
					continue
				gap = maxf(gap, mine.zone_center.distance_to(_side(other.zone_center, mirror)))
			if gap <= best_gap:
				best_gap = gap
				best = j
		if best < 0:
			return INF
		used.append(best)
		worst = maxf(worst, best_gap)
	return worst


## Man targets 0 and 1 are the outside receivers on the left and on the right.
static func _man_side(assignment: DefenseAssignment, mirror: bool) -> int:
	if mirror and assignment.man_target <= 1:
		return 1 - assignment.man_target
	return assignment.man_target


## Every defender of the play lined up in `pc`, in the offense's frame:
## { label, job, at, man } with `man` the spot of the receiver he covers.
static func lineup(pc: PlayController) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for defender: Player in pc.defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		var row: Dictionary = {"label": assignment.label, "job": assignment.job, "at": frame(pc, defender.position), "man": null, "deep": assignment.deep}
		if assignment.job == DefenseAssignment.Job.MAN and defender.brain.man_target != null:
			row["man"] = frame(pc, defender.brain.man_target.position)
		rows.append(row)
	return rows


## World position to the offense's frame: x yards past the line, y yards to the
## offense's right of the ball.
static func frame(pc: PlayController, position: Vector3) -> Vector2:
	return Vector2((position.x - pc.los_x) * pc.off_dir, position.z * pc.off_dir)


## The offense's skill players (everyone but the quarterback and the three
## linemen) in the offense's frame.
static func skill(pc: PlayController) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for player: Player in pc.offense.players:
		var spot: Vector2 = frame(pc, player.position)
		if player == pc.qb or (absf(spot.y) < 2.6 and spot.x > -1.5):
			continue
		spots.append(spot)
	return spots
