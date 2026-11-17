class_name PreSnapMotion
extends RefCounted
## Motion before the snap: one receiver (MotionRules.pick) leaves his spot on
## the quarterback's call and the defense answers it. Owned by PlayController.
##
## Before the snap every player is frozen and nothing is simulated, so this
## moves the few who move by itself: it steers them and calls their integrate().
##
## What the defense does is the read the motion is for:
##  - MAN: whoever has the motion man goes with him, a step behind, along a
##    lane at his own depth that is clear of his teammates (in front of the
##    linebackers for a corner up at the line, over the top of them otherwise).
##    Who covers whom never changes.
##  - ZONE: nobody goes with him. The defense reads the new formation the way
##    it read the first one (DefenseAligner) and each man walks a few yards
##    toward where that puts him: a safety rotates, a linebacker bumps over.

## READY: the play has a motion and it has not been called. MOVING: he is on
## his way. SET: he has stopped where the motion ends.
enum State { NONE, READY, MOVING, SET }

## Closer than this to where he is going, a mover is there.
const ARRIVE: float = 0.15
## A follower runs along his lane until he is this close across to his man.
const LANE_MARGIN: float = 1.0
## How many times a follower's lane is moved back to clear his teammates.
const LANE_TRIES: int = 4
## A zone defender moved less than this stays where he is.
const SHIFT_MIN: float = 0.3
## Jet sweep: yards up the field the lead blocker's path is from the sweep's.
const SWEEP_LEAD: float = 2.5

var pc: PlayController
var tuning: Tuning
var state: State = State.NONE
var man: Player
## The ball was snapped while a jet man ran and goes to him (see settle()).
var jet_sweep: bool = false
## Seconds since the motion was called, and when (on that clock) he set.
var time: float = 0.0
var set_time: float = 0.0

## His job as the play draws it.
var _drawn: OffenseAssignment
## The path in world space, the point he is running to, how long the path is
## and how much of it is behind him.
var _path: PackedVector3Array = PackedVector3Array()
var _leg: int = 0
var _length: float = 0.0
var _covered: float = 0.0
## Man defenders going with him, each with the depth (world x) of his lane.
var _followers: Dictionary[Player, float] = {}
## Zone defenders on their way to a new spot.
var _shifts: Dictionary[Player, Vector3] = {}
## Movers who have stopped and are frozen again.
var _settled: Array[Player] = []
## The one follower has left his lane for the depth he plays at.
var _stepping_up: bool = false
## Seconds the quarterback's leg kick still has to run.
var _kick_left: float = 0.0


func _init(p_pc: PlayController) -> void:
	pc = p_pc
	tuning = pc.tuning


## A new line-up: nothing is left of the last play's motion.
func reset() -> void:
	state = State.NONE
	man = null
	jet_sweep = false
	time = 0.0
	set_time = 0.0
	_drawn = null
	_path = PackedVector3Array()
	_leg = 0
	_length = 0.0
	_covered = 0.0
	_followers.clear()
	_shifts.clear()
	_settled.clear()
	_stepping_up = false
	_kick_left = 0.0


## Both teams are on their spots: is there a motion to call on this play?
func prepare() -> void:
	reset()
	var play: OffensePlay = pc.off_play
	if pc.kickoff or not MotionRules.has_motion(play):
		return
	var index: int = MotionRules.pick(play)
	if index >= pc.offense.players.size():
		return
	man = pc.offense.players[index]
	_drawn = man.brain.off_assign
	state = State.READY


func available() -> bool:
	return state == State.READY


func is_jet() -> bool:
	return man != null and pc.off_play.motion == OffensePlay.Motion.JET


## The quarterback sends him. Once per play. False when there is nothing to call.
func call_motion() -> bool:
	if state != State.READY or not pc.ball_dead:
		return false
	var play: OffensePlay = pc.off_play
	var flip: float = _flip()
	_path = PackedVector3Array()
	_length = 0.0
	var from: Vector3 = man.position
	for point: Vector2 in MotionRules.path(play):
		var spot: Vector3 = pc.to_world(point, flip)
		_length += _flat(from, spot)
		_path.append(spot)
		from = spot
	if _path.is_empty():
		return false
	_leg = 0
	_covered = 0.0
	time = 0.0
	state = State.MOVING
	man.frozen = false
	_plan_defense()

	# The quarterback kicks a leg out toward the side he sends him to. He faces
	# downfield, so his right is toward +z for a team attacking toward +x.
	var toward: Vector3 = _path[0] if play.motion == OffensePlay.Motion.RETURN else _path[_path.size() - 1]
	var across: float = (toward.z - man.position.z) * pc.off_dir
	if pc.qb != null and pc.qb.animator != null:
		pc.qb.animator.motion_kick(1.0 if across >= 0.0 else -1.0)
		# A little longer than the kick, so he is back in his stance at the end.
		_kick_left = PlayerAnimator.MOTION_KICK_TIME + 0.5
	pc.game.audio.qb_motion()
	pc.game.add_stat(&"motions")
	return true


## One tick before the snap.
func tick(delta: float) -> void:
	if _kick_left > 0.0:
		_kick_left -= delta
		if pc.qb != null and pc.qb.frozen:
			pc.qb.integrate(delta)
	if state != State.MOVING and state != State.SET:
		return
	time += delta
	if state == State.MOVING:
		_move_man(delta)
	_move_followers(delta)
	_move_shifts(delta)
	# Whoever has stopped turns to face the ball again and gets back in his stance.
	for player: Player in _settled:
		player.integrate(delta)


## JET: he is where the ball should be snapped: close to the quarterback and
## still coming, or just past him.
func jet_in_window() -> bool:
	if state != State.MOVING or not is_jet():
		return false
	var before: float = _jet_before()
	return before <= MotionRules.JET_WINDOW_BEFORE and before >= -MotionRules.JET_WINDOW_AFTER


## Share of the path that is behind him (0..1).
func progress() -> float:
	if state == State.SET:
		return 1.0
	if state != State.MOVING or _length <= 0.0:
		return 0.0
	var done: float = _covered
	if _leg < _path.size():
		var from: Vector3 = _leg_start()
		done += minf(_flat(from, man.position), _flat(from, _path[_leg]))
	return clampf(done / _length, 0.0, 1.0)


## The snap: gives the motion man the job that goes with where he is now.
## Returns whether anything about the play changed.
func settle() -> bool:
	if state != State.MOVING and state != State.SET:
		return false
	var play: OffensePlay = pc.off_play
	var moving: bool = state == State.MOVING
	var after: OffenseAssignment = _drawn
	var anchored: bool = true
	jet_sweep = false
	match play.motion:
		OffensePlay.Motion.RETURN:
			pass
		OffensePlay.Motion.JET:
			if moving and _jet_before() >= -MotionRules.JET_WINDOW_AFTER:
				# Snapped on the run: he keeps going, along the path the play
				# draws from the point in front of the quarterback.
				after = play.motion_assignment
				anchored = false
				jet_sweep = play.motion_handoff
			elif play.motion_set_assignment != null:
				# Too late for that: the job the play has for him on the far side.
				after = play.motion_set_assignment
			else:
				# Too late: he is a blocker on the far side.
				after = OffenseAssignment.new()
				after.label = _drawn.label
				after.job = OffenseAssignment.Job.BLOCK
				after.start = play.motion_to
		_:
			if not moving or progress() >= 0.5:
				after = play.motion_assignment

	# His route starts where he stands, not where the play draws him.
	var flip: float = _flip()
	var here: Vector2 = Vector2((man.position.x - pc.los_x) * pc.off_dir, man.position.z * pc.off_dir * flip)
	var base: Vector2 = here if anchored else after.start
	var route: PackedVector3Array = PackedVector3Array()
	if not anchored:
		# A jet man on the run first finishes the way to the point in front of
		# the quarterback: cutting the corner would take him out of reach.
		if _leg == 0 and _path.size() > 1:
			route.append(_path[0])
		if _jet_before() > 0.5:
			route.append(pc.to_world(after.start, flip))
	for waypoint: Vector2 in after.route:
		route.append(pc.to_world(base + waypoint, flip))
	man.brain.assign_offense(after, man.position, route)
	man.speed_scale = tuning.line_speed_scale if after.job == OffenseAssignment.Job.BLOCK and after.route.is_empty() else 1.0
	man.ai_speed_scale = 1.0
	man.wants_turbo = false
	for defender: Player in _followers:
		defender.ai_speed_scale = 1.0
	for defender: Player in _shifts:
		defender.ai_speed_scale = 1.0
	if jet_sweep:
		_lead_sweep(pc.runner, after, flip)
		pc.runner = man
		pc.game.add_stat(&"jet_sweeps")
	if moving:
		pc.game.add_stat(&"motion_snaps")
	return true


## A jet sweep: the back the play draws the ball for goes out in front of the
## sweep instead, along the same path a few yards further up the field, and
## takes on the first man there.
func _lead_sweep(back: Player, sweep: OffenseAssignment, flip: float) -> void:
	if back == null or back == man or back == pc.qb:
		return
	var lead: OffenseAssignment = OffenseAssignment.new()
	lead.label = back.brain.off_assign.label
	lead.job = OffenseAssignment.Job.BLOCK
	lead.start = back.brain.off_assign.start
	var route: PackedVector3Array = PackedVector3Array()
	for waypoint: Vector2 in sweep.route:
		var point: Vector2 = sweep.start + waypoint + Vector2(SWEEP_LEAD, 0.0)
		lead.route.append(point - lead.start)
		route.append(pc.to_world(point, flip))
	back.brain.assign_offense(lead, back.position, route)
	back.speed_scale = 1.0


# --- The motion man ------------------------------------------------------------

func _move_man(delta: float) -> void:
	var play: OffensePlay = pc.off_play
	var target: Vector3 = _path[_leg]
	var last: bool = _leg == _path.size() - 1
	var dist: float = _flat(man.position, target)
	if dist < (ARRIVE if last else 0.6):
		_covered += _flat(_leg_start(), target)
		_leg += 1
		if _leg >= _path.size():
			_stop(man, target, Vector3(pc.off_dir, 0.0, 0.0))
			state = State.SET
			set_time = time
			return
		target = _path[_leg]
		last = _leg == _path.size() - 1
		dist = _flat(man.position, target)
	var jet: bool = play.motion == OffensePlay.Motion.JET
	var runs: bool = jet or play.motion == OffensePlay.Motion.ACROSS
	man.ai_speed_scale = 1.0 if runs else tuning.motion_jog_scale
	man.wants_turbo = jet
	_steer(man, target, last)
	man.integrate(delta)


## Yards he still has to run, along his path, before he passes the
## quarterback (negative: past him).
func _jet_before() -> float:
	var end: Vector3 = _path[_path.size() - 1]
	var dir: float = 1.0 if end.z >= pc.qb.position.z else -1.0
	var across: float = (pc.qb.position.z - man.position.z) * dir
	if _leg == 0 and _path.size() > 1:
		# Still dropping back to the depth he crosses at.
		var bend: Vector3 = _path[0]
		return _flat(man.position, bend) + (pc.qb.position.z - bend.z) * dir
	return across


func _leg_start() -> Vector3:
	return _path[_leg - 1] if _leg > 0 else man.brain.start_point


# --- The defense ---------------------------------------------------------------

## Decided at the call: who goes with him and along which lane, and where the
## zone defenders shift to.
func _plan_defense() -> void:
	_followers.clear()
	_shifts.clear()
	var play: OffensePlay = pc.off_play
	var end: Vector3 = _path[_path.size() - 1]
	if play.motion != OffensePlay.Motion.RETURN:
		_plan_shifts(end)

	# The stretch of field he crosses, as far as it goes to either side.
	var low: float = man.position.z
	var high: float = man.position.z
	for point: Vector3 in _path:
		low = minf(low, point.z)
		high = maxf(high, point.z)
	var taken: Array[float] = []
	for defender: Player in pc.defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		if assignment == null or assignment.job != DefenseAssignment.Job.MAN or defender.brain.man_target != man:
			continue
		var lane: float = defender.position.x
		for _try: int in LANE_TRIES:
			if _lane_clear(defender, lane, low, high) and not _near_any(lane, taken):
				break
			lane += pc.off_dir * DefenseAligner.STACK_STEP
		# Never past the back of the end zone.
		var back: float = tuning.goal_x(pc.offense.attack_dir) + pc.off_dir * (tuning.end_zone_depth - 1.5)
		if (lane - back) * pc.off_dir > 0.0:
			lane = back
		taken.append(lane)
		_followers[defender] = lane


## No teammate stands on the lane at depth `lane`, between `low` and `high`
## across, now or where the shift is taking him.
func _lane_clear(defender: Player, lane: float, low: float, high: float) -> bool:
	for mate: Player in pc.defense.players:
		if mate == defender or _followers.has(mate):
			continue
		for spot: Vector3 in [mate.position, _shifts.get(mate, mate.position)]:
			if absf(spot.x - lane) < DefenseAligner.STACK_GAP and spot.z > low - LANE_MARGIN and spot.z < high + LANE_MARGIN:
				return false
	return true


## No teammate stands at `spot` or between it and the lane at depth `lane`
## straight behind it, now or where the shift is taking him; and no other
## follower plays at that depth.
func _way_clear(defender: Player, spot: Vector3, lane: float) -> bool:
	var gap: float = DefenseAligner.STACK_GAP
	var near: float = minf(spot.x, lane) - gap
	var far: float = maxf(spot.x, lane) + gap
	for mate: Player in pc.defense.players:
		if mate == defender:
			continue
		if _followers.has(mate):
			if absf(mate.brain.start_point.x - spot.x) < gap or absf(_followers[mate] - spot.x) < gap:
				return false
			continue
		for at: Vector3 in [mate.position, _shifts.get(mate, mate.position)]:
			if absf(at.z - spot.z) < gap and at.x > near and at.x < far:
				return false
	return true


func _near_any(value: float, others: Array[float]) -> bool:
	for other: float in others:
		if absf(other - value) < DefenseAligner.STACK_GAP:
			return true
	return false


## The zone defenders' answer: the formation is read again with the motion man
## where he is going, and each of them goes a few yards toward his new spot.
func _plan_shifts(end: Vector3) -> void:
	var seen: Array[Vector2] = []
	for player: Player in pc.offense.players:
		if player == pc.qb:
			continue
		var at: Vector3 = end if player == man else player.position
		seen.append(Vector2((at.x - pc.los_x) * pc.off_dir, at.z * pc.off_dir))
	var spots: PackedVector2Array = pc.defense_spots(seen)
	for i: int in pc.defense.players.size():
		var defender: Player = pc.defense.players[i]
		var assignment: DefenseAssignment = defender.brain.def_assign
		if assignment == null or assignment.job != DefenseAssignment.Job.ZONE:
			continue
		var slot: int = mini(i, spots.size() - 1)
		var to: Vector3 = pc.to_world(spots[slot])
		var move: Vector3 = to - defender.position
		move.y = 0.0
		if move.length() < SHIFT_MIN:
			continue
		_shifts[defender] = defender.position + move.limit_length(tuning.motion_zone_shift_max)
	# Nobody ends up inside a teammate who stays, or one who moves.
	for defender: Player in _shifts.keys():
		for mate: Player in pc.defense.players:
			if mate == defender:
				continue
			var his: Vector3 = _shifts.get(mate, mate.position)
			if _flat(his, _shifts[defender]) < DefenseAligner.STACK_GAP:
				_shifts.erase(defender)
				break


func _move_followers(delta: float) -> void:
	var play: OffensePlay = pc.off_play
	var jet: bool = play.motion == OffensePlay.Motion.JET
	if time < tuning.motion_follow_delay:
		return
	for defender: Player in _followers:
		if _settled.has(defender):
			continue
		# Across from his man, wherever he is right now: so he trails him.
		var spot: Vector3 = Vector3(_followers[defender], 0.0, man.position.z)
		if state == State.SET and _followers.size() == 1 and (_stepping_up or absf(defender.position.z - spot.z) < 0.3):
			# His man has stopped and he is across from him: he comes back up
			# to the depth he plays at, if nobody is standing there or in the way.
			var own: Vector3 = Vector3(defender.brain.start_point.x, 0.0, man.position.z)
			if _stepping_up or _way_clear(defender, own, spot.x):
				_stepping_up = true
				spot = own
		# A lane that is not at his own depth: he drops back on to it before he
		# sets off across, so he goes round his teammates and not through them.
		var off_lane: float = absf(defender.position.x - spot.x)
		if off_lane > 0.4:
			spot.z = defender.position.z + clampf(spot.z - defender.position.z, -0.5, 0.5)
		if state == State.SET and _flat(defender.position, spot) < ARRIVE:
			_stop(defender, spot, Vector3(-pc.off_dir, 0.0, 0.0))
			continue
		defender.frozen = false
		defender.ai_speed_scale = 1.0
		defender.wants_turbo = jet
		_steer(defender, spot, true)
		defender.integrate(delta)


func _move_shifts(delta: float) -> void:
	if time < tuning.motion_zone_delay:
		return
	for defender: Player in _shifts:
		if _settled.has(defender):
			continue
		if _flat(defender.position, _shifts[defender]) < ARRIVE:
			_stop(defender, _shifts[defender], Vector3(-pc.off_dir, 0.0, 0.0))
			continue
		defender.frozen = false
		defender.ai_speed_scale = tuning.motion_zone_walk_scale
		defender.wants_turbo = false
		_steer(defender, _shifts[defender], true)
		defender.integrate(delta)


# --- Helpers -------------------------------------------------------------------

## Toward `point`, easing off close to it when he is to stop there.
func _steer(player: Player, point: Vector3, stop: bool) -> void:
	var to: Vector3 = point - player.position
	to.y = 0.0
	var dist: float = to.length()
	if dist < 0.01:
		player.move_input = Vector3.ZERO
		return
	player.move_input = to / dist * (clampf(dist / 1.2, 0.25, 1.0) if stop else 1.0)


## On his spot, still, set again.
func _stop(player: Player, spot: Vector3, face: Vector3) -> void:
	player.position = Vector3(spot.x, 0.0, spot.z)
	player.velocity = Vector3.ZERO
	player.move_input = Vector3.ZERO
	player.wants_turbo = false
	player.ai_speed_scale = 1.0
	player.facing = face
	player.frozen = true
	if not _settled.has(player):
		_settled.append(player)


func _flip() -> float:
	return -1.0 if pc.off_flipped else 1.0


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
