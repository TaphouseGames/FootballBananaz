class_name MotionRules
extends RefCounted
## Who may go in motion before the snap, the path he takes, and what a play's
## motion has to keep to. Everything is read from the play as drawn: x = yards
## past the line of scrimmage (negative = behind it), y = yards to the right of
## the ball. A flipped play is mirrored by whoever uses the result.
##
## The rules, as on a real field:
##  - a man on the line of scrimmage may not move, so only a receiver who
##    stands off it can be sent;
##  - a back is not a receiver;
##  - of the receivers who may, it is the one nearest the ball (the slot, the
##    wing, a flanker);
##  - he never moves toward the line, and he ends off it, so the offense has as
##    many men on the line after the motion as before;
##  - nobody else moves.

## Further up than this is on the line of scrimmage.
const ON_LINE: float = -1.0
## He ends at least this far from every teammate.
const CLEAR: float = 1.0
## ...and this far inside the sideline.
const FIELD_MARGIN: float = 1.0
## ACROSS: yards he runs sideways while dropping to the depth he crosses at.
const ACROSS_LEAD: float = 1.5
## JET: yards sideways per yard he drops back on the way to his crossing depth.
const JET_BEND: float = 1.1
## JET: the ball should be snapped from this many yards of his path before he
## passes the quarterback to this many after.
const JET_WINDOW_BEFORE: float = 4.0
const JET_WINDOW_AFTER: float = 1.0


static func is_lineman(assignment: OffenseAssignment) -> bool:
	return absf(assignment.start.y) < DefenseAligner.LINE_WIDTH and assignment.start.x > DefenseAligner.LINE_DEPTH


static func on_line(assignment: OffenseAssignment) -> bool:
	return assignment.start.x > ON_LINE


## A receiver who may be sent in motion.
static func may_move(assignment: OffenseAssignment) -> bool:
	if assignment.job == OffenseAssignment.Job.QB or is_lineman(assignment):
		return false
	return not on_line(assignment) and assignment.start.x >= DefenseAligner.BACKFIELD


## The motion man's place in `play.assignments`, or -1 when nobody may move.
## Two men equally near the ball: the one on the side with more receivers,
## then the one on the right.
static func pick(play: OffensePlay) -> int:
	var sides: Array[int] = [0, 0]
	for assignment: OffenseAssignment in play.assignments:
		if assignment.job == OffenseAssignment.Job.QB or is_lineman(assignment) or assignment.start.x < DefenseAligner.BACKFIELD:
			continue
		sides[1 if assignment.start.y > 0.0 else 0] += 1
	var best: int = -1
	for i: int in play.assignments.size():
		var assignment: OffenseAssignment = play.assignments[i]
		if not may_move(assignment):
			continue
		if best < 0:
			best = i
			continue
		var held: Vector2 = play.assignments[best].start
		var gap: float = absf(assignment.start.y) - absf(held.y)
		if gap < -0.05:
			best = i
		elif gap <= 0.05:
			var mine: int = sides[1 if assignment.start.y > 0.0 else 0]
			var his: int = sides[1 if held.y > 0.0 else 0]
			if mine > his or (mine == his and assignment.start.y > held.y):
				best = i
	return best


## The play has a motion and somebody who may run it.
static func has_motion(play: OffensePlay) -> bool:
	return play != null and play.motion != OffensePlay.Motion.NONE and pick(play) >= 0


## The points he runs through after leaving his spot, the last one being where
## he stops. Empty when the play has no motion.
static func path(play: OffensePlay) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if not has_motion(play):
		return points
	var from: Vector2 = play.assignments[pick(play)].start
	var to: Vector2 = play.motion_to
	var dir: float = 1.0 if to.y >= from.y else -1.0
	match play.motion:
		OffensePlay.Motion.ACROSS:
			points.append(Vector2(to.x, from.y + dir * ACROSS_LEAD))
			points.append(to)
		OffensePlay.Motion.JET:
			points.append(Vector2(to.x, from.y + dir * absf(to.x - from.x) * JET_BEND))
			points.append(to)
		OffensePlay.Motion.RETURN:
			points.append(to)
			points.append(from)
		_:
			points.append(to)
	return points


## Where he stands once the motion is over.
static func end_spot(play: OffensePlay) -> Vector2:
	var points: PackedVector2Array = path(play)
	return points[points.size() - 1] if not points.is_empty() else Vector2.ZERO


## JET: the point in front of the quarterback his path goes through.
static func jet_mesh(play: OffensePlay) -> Vector2:
	return Vector2(play.motion_to.x, 0.0)


## How many of the offense stand on the line of scrimmage, before the motion
## or (`moved`) after it.
static func line_count(play: OffensePlay, moved: bool) -> int:
	var man: int = pick(play) if moved and has_motion(play) else -1
	var count: int = 0
	for i: int in play.assignments.size():
		var assignment: OffenseAssignment = play.assignments[i]
		if assignment.job == OffenseAssignment.Job.QB:
			continue
		var depth: float = end_spot(play).x if i == man else assignment.start.x
		if depth > ON_LINE:
			count += 1
	return count


## Everything wrong with the motion of `play`, in words. Empty = fine.
## `half_width`: half the width of the field, in yards.
static func problems(play: OffensePlay, half_width: float) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if play.motion == OffensePlay.Motion.NONE:
		if play.motion_assignment != null or play.motion_set_assignment != null or play.motion_handoff:
			found.append("motion details on a play with no motion")
		return found
	var man: int = pick(play)
	if man < 0:
		found.append("has a motion but nobody who may move")
		return found
	var drawn: OffenseAssignment = play.assignments[man]
	var to: Vector2 = play.motion_to
	var limit: float = half_width - FIELD_MARGIN
	var is_return: bool = play.motion == OffensePlay.Motion.RETURN
	var is_jet: bool = play.motion == OffensePlay.Motion.JET

	if to.x > ON_LINE:
		found.append("the motion ends on the line of scrimmage")
	if absf(to.y) > limit:
		found.append("the motion ends off the field")
	# Never toward the line.
	var depth: float = drawn.start.x
	for point: Vector2 in path(play):
		if point.x > depth + 0.01:
			found.append("the motion goes toward the line")
			break
		depth = point.x
	var spot: Vector2 = end_spot(play)
	for i: int in play.assignments.size():
		if i != man and play.assignments[i].start.distance_to(spot) < CLEAR:
			found.append("the motion ends inside %s" % play.assignments[i].label)
	if line_count(play, true) != line_count(play, false):
		found.append("the motion changes how many are on the line")
	if is_return and absf(to.x - drawn.start.x) > 0.01:
		found.append("a return motion that changes his depth")

	var after: OffenseAssignment = play.motion_assignment
	if is_return:
		if after != null or play.motion_set_assignment != null:
			found.append("a return motion with a new job")
		if play.motion_handoff:
			found.append("a handoff to a man on a return motion")
		return found
	if after == null:
		found.append("no job after the motion")
		return found
	var anchor: Vector2 = jet_mesh(play) if is_jet else to
	if after.start.distance_to(anchor) > 0.01:
		found.append("the job after the motion does not start where the motion puts him")
	for waypoint: Vector2 in after.route:
		if absf(after.start.y + waypoint.y) > limit:
			found.append("the route after the motion leaves the field")
			break
	if after.job == OffenseAssignment.Job.QB:
		found.append("the motion man becomes the quarterback")
	if after.job != OffenseAssignment.Job.BLOCK and after.route.is_empty():
		found.append("nowhere to run after the motion")
	var late: OffenseAssignment = play.motion_set_assignment
	if late != null:
		if not is_jet:
			found.append("a job for a jet man who has set on a motion that is not a jet")
		if late.start.distance_to(to) > 0.01:
			found.append("the job of a jet man who has set does not start where he sets")
		for waypoint: Vector2 in late.route:
			if absf(late.start.y + waypoint.y) > limit:
				found.append("the route of a jet man who has set leaves the field")
				break
		if late.job == OffenseAssignment.Job.QB or late.job == OffenseAssignment.Job.RUNNER:
			found.append("a jet man who has set is the quarterback or the runner")
		elif late.job != OffenseAssignment.Job.BLOCK and late.route.is_empty():
			found.append("nowhere to run for a jet man who has set")
	if is_jet and not play.is_run:
		# Snapped late he has to be a receiver still, or the pass buttons change.
		if late == null or late.job == OffenseAssignment.Job.BLOCK:
			found.append("a jet motion on a pass play with no route for a man who has set")
	if play.motion_handoff:
		if not is_jet or not play.is_run:
			found.append("a handoff to the motion man on a play that is not a jet run")
		if after.job != OffenseAssignment.Job.RUNNER:
			found.append("a handoff to a motion man who is not a runner")
	elif after.job == OffenseAssignment.Job.RUNNER:
		found.append("the motion man is a runner but the ball does not go to him")
	if not play.is_run:
		# The pass buttons are handed out by who is a receiver: that must not
		# change under the person's thumb.
		var was: bool = drawn.job != OffenseAssignment.Job.BLOCK
		var now: bool = after.job != OffenseAssignment.Job.BLOCK
		if was != now:
			found.append("the motion changes who can be thrown to")
	return found
