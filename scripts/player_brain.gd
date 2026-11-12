class_name PlayerBrain
extends RefCounted
## CPU decision-making for one player. think() only sets the player's inputs
## (move_input, wants_turbo) and asks PlayController for actions; it never moves
## the player itself.

## Kickoff: the return team's blockers set up this far in front of where the
## kick comes down and take on anyone who gets this close; the kicking team
## stays in its lanes until it is this close to that spot.
const KICKOFF_WALL_DEPTH: float = 12.0
const KICKOFF_BLOCK_RANGE: float = 9.0
const KICKOFF_LANE_DEPTH: float = 18.0
## A route has cut once its heading is further than this (as a dot product, about
## 25 degrees) from the leg the receiver is on.
const ROUTE_CUT_DOT: float = 0.9

var player: Player
var tuning: Tuning

var off_assign: OffenseAssignment
var def_assign: DefenseAssignment
var is_offense: bool = false

var route: PackedVector3Array = PackedVector3Array()
var route_index: int = 0
var route_exit_dir: Vector3 = Vector3.ZERO
var start_point: Vector3 = Vector3.ZERO
## Set by route_ahead(): which way he is heading at that moment (zero if he has
## stopped), and whether the route has turned him or stopped him by then.
var route_ahead_dir: Vector3 = Vector3.ZERO
var route_ahead_cut: bool = false

var man_target: Player
var zone_center: Vector3 = Vector3.ZERO
var zone_radius: float = 0.0

## Set by PlayController at the line-up: until this long after the snap this
## coverage defender has lost the plot. 0 = he has not.
var blown_time: float = 0.0
## Set by PlayController at the line-up of a play-action play: until this long
## after the snap this coverage defender plays the faked run. 0 = he does not.
var bite_time: float = 0.0

var _decision_timer: float = 0.0
## A carrier's next move against a tackler: how long before contact he starts
## it (negative = not rolled yet) and how long he then still hesitates.
var _move_lead: float = -1.0
var _move_late: float = 0.0
## The CPU quarterback rolls once per play for keeping the ball by design:
## the time he goes (negative = he does not).
var _keeper_rolled: bool = false
var _keeper_time: float = -1.0
var _late_hit_used: bool = false
## Set by PlayController at a score against his team: this long after the
## whistle he goes for one of the players celebrating (negative = he does not),
## and whether it is the scorer he is after or whoever is nearest.
var cheap_shot_delay: float = -1.0
var cheap_shot_scorer: bool = true
## He has reached his place in the huddle round the scorer.
var _at_party: bool = false
var _delta: float = 0.0
## What a coverage defender believes his receiver is doing. It follows the real
## velocity with a short delay, so a sharp cut buys the receiver a step.
var _read_velocity: Vector3 = Vector3.ZERO
## Decided once per pass: whether this defender goes up for the ball.
var _contest_decided: bool = false
## The CPU quarterback has given up on the pass and is running with it.
var _scrambling: bool = false
var _rollout: float = 0.0
var _rollout_width: float = 5.0
var _rollout_forward: float = 1.0
var _keep_ball: bool = false
## A coverage defender who bit on a cut chases `_bust_ghost` (where he thinks
## the receiver went) until the timer runs out.
var _bust_timer: float = 0.0
var _bust_cooldown: float = 0.0
var _bust_ghost: Vector3 = Vector3.ZERO
## A receiver whose route is over: how long he has waited, when he next looks
## for space, and the spot he is working toward.
var _wait_time: float = 0.0
var _open_timer: float = 0.0
var _open_spot: Vector3 = Vector3.ZERO
## His own wait at the end of the route, rolled when he gets there, so two
## receivers who finish together do not set off together. Negative = not rolled.
var _open_delay: float = -1.0
## He is open and calling for the ball.
var _calling: bool = false
## A fumble: whether he has seen that the ball is out, how long after it came
## out he does (if it does not turn up in front of him first), and whether he
## has made up his mind about diving on it this time he is close.
var sees_ball: bool = false
var _notice_time: float = 0.0
var _loose_decided: bool = false


func _init(p_player: Player, p_tuning: Tuning) -> void:
	player = p_player
	tuning = p_tuning


func assign_offense(assignment: OffenseAssignment, start: Vector3, world_route: PackedVector3Array) -> void:
	_reset()
	is_offense = true
	off_assign = assignment
	def_assign = null
	start_point = start
	route = world_route
	if route.size() > 0:
		var from: Vector3 = start if route.size() == 1 else route[route.size() - 2]
		var leg: Vector3 = route[route.size() - 1] - from
		if leg.length_squared() > 0.01:
			route_exit_dir = leg.normalized()


func assign_defense(assignment: DefenseAssignment, start: Vector3, target: Player, p_zone_center: Vector3) -> void:
	_reset()
	is_offense = false
	def_assign = assignment
	off_assign = null
	start_point = start
	man_target = target
	zone_center = p_zone_center
	zone_radius = assignment.zone_radius


func think(pc: PlayController, delta: float) -> void:
	player.move_input = Vector3.ZERO
	player.wants_turbo = false
	player.is_blocking = false
	player.calling_for_ball = false
	player.ai_speed_scale = 1.0
	_delta = delta
	_decision_timer = maxf(_decision_timer - delta, 0.0)
	# A stiff arm is done on the run, so the brain keeps steering through it.
	if not player.can_act() and player.state != Player.State.STIFF_ARM:
		return
	if pc.ball_dead:
		_think_dead(pc, delta)
		return

	if pc.kickoff and pc.phase == PlayController.Phase.AIR:
		_think_kickoff(pc)
		return

	match pc.phase:
		PlayController.Phase.POCKET:
			if is_offense:
				_offense_pocket(pc)
			else:
				_defense_pocket(pc)
		PlayController.Phase.AIR:
			_think_air(pc)
		PlayController.Phase.RUN:
			var carrier: Player = pc.ball.carrier
			if carrier == null:
				return
			if carrier == player:
				_carry(pc)
			elif carrier.team == player.team:
				_block(pc, carrier.position)
			elif _reading_run(pc, carrier):
				_defense_pocket(pc)
			else:
				_pursue(pc, carrier)
		PlayController.Phase.LOOSE:
			_think_loose(pc)


# --- Fumble ------------------------------------------------------------------

## The ball has just come out. Someone close and looking that way sees it at
## once; from further off or with his back turned it takes longer, and now and
## then a man has no idea at all for a while.
func on_fumble(pc: PlayController) -> void:
	_loose_decided = false
	sees_ball = player == pc.fumbler
	if sees_ball:
		return
	var to: Vector3 = pc.ball.flat_position() - player.position
	to.y = 0.0
	var dist: float = to.length()
	# 0 looking straight at it, 1 with his back to it.
	var turned: float = (1.0 - player.facing.dot(to / dist)) * 0.5 if dist > 0.1 else 0.0
	var far: float = clampf(dist / maxf(tuning.ai_fumble_notice_range, 0.01), 0.0, 1.0)
	_notice_time = randf_range(tuning.ai_fumble_notice_min, tuning.ai_fumble_notice_max)
	_notice_time += tuning.ai_fumble_notice_far * maxf(far, turned) * randf_range(0.5, 1.0)
	if randf() < tuning.ai_fumble_clueless_chance * lerpf(0.5, 1.5, turned):
		_notice_time += randf_range(tuning.ai_fumble_clueless_time_min, tuning.ai_fumble_clueless_time_max)
		pc.game.add_stat(&"fumble_clueless")


func _think_loose(pc: PlayController) -> void:
	var spot: Vector3 = pc.ball.flat_position()
	var dist: float = _flat_distance(player.position, spot)
	if not sees_ball:
		var in_front: bool = dist < tuning.ai_fumble_wake_range and (dist < 0.5 or player.facing.dot(_direction_to(spot)) > 0.2)
		sees_ball = in_front or pc.loose_time >= _notice_time
	var loser: Player = pc.fumbler
	if not sees_ball:
		# As far as he knows the man on the ground still has it.
		if loser == null:
			return
		if loser.team == player.team:
			_block(pc, loser.position)
		else:
			# He closes on him and stands over him, not on him: the man gets up
			# again in a moment.
			_seek(loser.position - _direction_to(loser.position) * 1.3)
			player.wants_turbo = _flat_distance(player.position, loser.position) > 3.0
		return
	if not _chases_ball(pc, dist):
		# Enough of his side are after it: he comes over and keeps the others off.
		# With his body only: who is after the ball changes from moment to
		# moment, and a block that switches on and off in a crowd shoves
		# people into each other.
		_block(pc, spot)
		player.is_blocking = false
		player.wants_turbo = dist > 4.0
		return
	# Run to where it is rolling to, not where it is.
	var roll: Vector3 = pc.ball.loose_velocity()
	roll.y = 0.0
	var lead: float = minf(dist / maxf(player.max_speed() * tuning.turbo_speed_multiplier, 0.1), 0.5)
	var aim: Vector3 = spot + roll * lead
	player.move_input = _direction_to(aim)
	player.wants_turbo = dist > 1.5
	if dist > tuning.ai_fumble_dive_range * 1.8:
		_loose_decided = false
	elif dist <= tuning.ai_fumble_dive_range and not _loose_decided:
		# Fall on it, or try to pick it up and run? With an opponent right
		# there he mostly makes sure of it.
		_loose_decided = true
		var contested: bool = false
		for opponent: Player in player.team.opponent.players:
			if not opponent.is_down() and _flat_distance(opponent.position, spot) < tuning.ai_fumble_contest_range:
				contested = true
		if randf() < (tuning.ai_fumble_dive_contested if contested else tuning.ai_fumble_dive_chance):
			pc.do_dive(player, _direction_to(aim))


## Only the few on each team who are nearest the ball (and know it is out) go
## for it.
func _chases_ball(pc: PlayController, dist: float) -> bool:
	var spot: Vector3 = pc.ball.flat_position()
	var closer: int = 0
	for mate: Player in player.team.players:
		if mate == player or not mate.can_act() or not pc.sees_loose_ball(mate):
			continue
		if _flat_distance(mate.position, spot) < dist:
			closer += 1
	return closer < tuning.ai_fumble_chasers


# --- Kickoff -----------------------------------------------------------------

## The kick is in the air. The returner gets under it, his teammates drop back
## to set up in front of him and block whoever gets there, and the kicking team
## runs down the field in its lanes before closing on the spot.
func _think_kickoff(pc: PlayController) -> void:
	var landing: Vector3 = pc.ball.target_point
	var upfield: float = float(player.team.attack_dir)
	if player == pc.returner:
		_seek(landing)
		player.wants_turbo = _flat_distance(player.position, landing) > 3.0
		return
	if is_offense:
		if pc.nearest_opponent_distance(player) < KICKOFF_BLOCK_RANGE:
			_block(pc, landing)
		else:
			_seek(Vector3(landing.x + upfield * KICKOFF_WALL_DEPTH, 0.0, start_point.z * 0.6))
		return
	var aim: Vector3 = landing
	if absf(landing.x - player.position.x) > KICKOFF_LANE_DEPTH:
		aim.z = lerpf(start_point.z, landing.z, 0.4)
	player.move_input = _direction_to(aim)
	player.wants_turbo = true


# --- Offense -----------------------------------------------------------------

func _offense_pocket(pc: PlayController) -> void:
	match off_assign.job:
		OffenseAssignment.Job.QB:
			if player.has_ball:
				_quarterback(pc)
		OffenseAssignment.Job.BLOCK:
			_block(pc, pc.qb.position)
		_:
			_run_route(pc)


func _quarterback(pc: PlayController) -> void:
	if _scrambling:
		_carry(pc)
		var behind_line: bool = (player.position.x - pc.los_x) * pc.off_dir < 0.0
		if _rollout != 0.0 and behind_line and absf(player.position.z - start_point.z) < _rollout_width:
			player.move_input = Vector3(pc.off_dir * _rollout_forward, 0.0, _rollout).normalized()
		player.wants_turbo = true
		if behind_line and not _keep_ball and not pc.off_play.is_run and _decision_timer <= 0.0:
			# Still behind the line: a man running free is worth pulling up for.
			_decision_timer = 0.15
			var open_man: Player = _best_receiver(pc, false)
			if open_man != null and _open_for(pc, open_man) >= tuning.ai_qb_run_throw_open:
				player.wants_turbo = false
				pc.game.add_stat(&"qb_throws_on_the_run")
				var run_power: float = choose_pass(pc, open_man, _open_for(pc, open_man), false)
				pc.throw_ball(open_man, run_power, choose_placement(pc, open_man, run_power))
		return
	var drop_point: Vector3 = route[route.size() - 1] if route.size() > 0 else start_point
	if pc.faking():
		# He stays for the fake, then drops (or rolls out).
		drop_point = start_point
	_seek(drop_point)
	if pc.off_play.is_run:
		return
	if pc.heave:
		if not pc.faking():
			_heave(pc)
		return
	if not pc.faking() and _keeps_it(pc):
		return
	if pc.live_time < tuning.ai_qb_min_time or _decision_timer > 0.0:
		return
	_decision_timer = 0.15

	var pressured: bool = pc.nearest_opponent_distance(player) < tuning.ai_qb_pressure_radius
	var out_of_time: bool = pc.live_time >= tuning.ai_qb_max_time
	var checkdowns: bool = pressured or pc.live_time >= tuning.ai_qb_checkdown_time
	var best: Player = _best_receiver(pc, checkdowns)
	var best_open: float = _open_for(pc, best) if best != null else -1.0

	if best == null or (out_of_time and not pressured and best_open < tuning.ai_qb_scramble_open):
		if out_of_time or pressured:
			# Nobody to throw to: tuck it and run.
			_scrambling = true
		return
	if best_open >= tuning.ai_qb_open_distance or pressured or out_of_time:
		var power: float = choose_pass(pc, best, best_open, pressured)
		pc.throw_ball(best, power, choose_placement(pc, best, power))


## The last play, with the end zone a long way off: nothing short is any use
## and neither is running. He waits until a lob would drop on his deepest man
## in the end zone or at the end of his own range, then puts it up for him. A
## rusher in his face or the wait getting too long makes him let go sooner.
func _heave(pc: PlayController) -> void:
	if pc.live_time < tuning.ai_qb_min_time or _decision_timer > 0.0 or not pc.can_pass():
		return
	_decision_timer = 0.1
	var target: Player = null
	var best_score: float = -INF
	for receiver: Player in pc.eligible:
		if receiver.is_down():
			continue
		# Depth first; how open he is only settles it between men at about the
		# same depth.
		var score: float = (receiver.position.x - pc.los_x) * pc.off_dir + _open_for(pc, receiver)
		if score > best_score:
			best_score = score
			target = receiver
	if target == null:
		return
	var pressured: bool = pc.nearest_opponent_distance(player) < tuning.ai_qb_pressure_radius
	# Always put up high: the longer it hangs, the further he has run under it.
	var power: float = tuning.ai_qb_lob_power
	var spot: Vector3 = pc.pass_spot(target, pc.pass_speed(power))
	var in_end_zone: bool = (spot.x - tuning.goal_x(player.team.attack_dir)) * pc.off_dir >= 2.0
	var at_range: bool = _flat_distance(player.position, spot) >= pc.pass_range() - tuning.ai_qb_heave_range_margin
	if pressured or in_end_zone or at_range or pc.live_time >= tuning.ai_qb_heave_max_time:
		pc.game.add_stat(&"heaves")
		pc.throw_ball(target, power, PlayController.Placement.NORMAL)


## The receiver most worth throwing to right now, or null. `checkdowns` also
## counts the ones short of ai_qb_min_depth.
func _best_receiver(pc: PlayController, checkdowns: bool) -> Player:
	var best: Player = null
	var best_score: float = -INF
	# Short of time, yards count for more next to how open a man is.
	var depth_bonus: float = lerpf(tuning.ai_qb_depth_bonus, tuning.ai_qb_urgent_depth_bonus, pc.qb_urgency)
	for receiver: Player in pc.eligible:
		if receiver.is_down():
			continue
		var downfield: float = (receiver.position.x - pc.los_x) * pc.off_dir
		if not checkdowns and downfield < tuning.ai_qb_min_depth:
			continue
		# No point throwing further than his arm reaches.
		if _flat_distance(receiver.position, player.position) > pc.pass_range():
			continue
		var score: float = _open_for(pc, receiver) + downfield * depth_bonus
		if score > best_score:
			best_score = score
			best = receiver
	return best


## How open `receiver` is, in yards: open now, and still open where the ball
## would come down.
func _open_for(pc: PlayController, receiver: Player) -> float:
	return minf(minf(pc.nearest_opponent_distance(receiver), _open_at_catch(pc, receiver)), 10.0)


## Now and then a quarterback who can run means to from the start: a moment
## after the snap, before the rush gets to him, he goes around the emptier
## side. A quick, agile one does it often, a pocket passer hardly ever. He can
## still pull up and throw if somebody comes open on the way.
func _keeps_it(pc: PlayController) -> bool:
	if not _keeper_rolled:
		_keeper_rolled = true
		@warning_ignore("integer_division")
		var legs: int = (player.ratings.speed + player.ratings.agility) / 2
		var mobility: float = maxf(PlayerRatings.blend(legs, tuning.qb_mobility_scale_low, tuning.qb_mobility_scale_high), 0.0)
		if randf() < tuning.ai_qb_keeper_chance * mobility:
			_keeper_time = randf_range(tuning.ai_qb_keeper_time_min, tuning.ai_qb_keeper_time_max)
	if _keeper_time < 0.0 or pc.live_time < _keeper_time:
		return false
	var crowd: float = 0.0
	for opponent: Player in player.team.opponent.players:
		crowd += signf(opponent.position.z - player.position.z)
	var side: float = -signf(crowd)
	if side == 0.0:
		side = 1.0 if randf() < 0.5 else -1.0
	pc.game.add_stat(&"qb_keepers")
	start_scramble(side, false, tuning.ai_qb_keeper_width, tuning.ai_qb_keeper_forward)
	return true


## Nobody near him: the kind of open a blown coverage leaves.
func is_wide_open(pc: PlayController) -> bool:
	return pc.nearest_opponent_distance(player) >= tuning.ai_get_open_stay_distance + 1.0


## The quarterback gives up on the pass and runs. Tests call this to play a
## person who keeps the ball.
## `rollout` of +1 or -1 has him go around the line on that side: until he is
## `width` yards out he runs sideways, with `forward` as much upfield as across.
## `keep` rules out pulling up to throw on the way.
func start_scramble(rollout: float = 0.0, keep: bool = false, width: float = 5.0, forward: float = 1.0) -> void:
	_scrambling = true
	_rollout = rollout
	_rollout_width = width
	_rollout_forward = forward
	_keep_ball = keep


## Distance from the nearest defender to the spot a regular pass to `receiver`
## would be thrown at.
func _open_at_catch(pc: PlayController, receiver: Player) -> float:
	var speed: float = lerpf(tuning.pass_lob_speed, tuning.pass_bullet_speed, tuning.ai_qb_normal_power)
	var spot: Vector3 = pc.pass_spot(receiver, speed)
	var best: float = INF
	for opponent: Player in receiver.team.opponent.players:
		if not opponent.is_down():
			best = minf(best, _flat_distance(opponent.position, spot))
	return best


## Pass power (0 = lob, 1 = bullet) for a throw to `target`.
## Tight coverage or a rusher in the QB's face: bullet. Deep, running away from
## the coverage with nobody over the top: lob it for him to run under. A long
## throw to anyone else is driven on a line, since a lob hangs long enough for
## the defense to get under it.
func choose_pass(pc: PlayController, target: Player, open: float, pressured: bool) -> float:
	var dist: float = _flat_distance(target.position, player.position)
	if open < tuning.ai_qb_open_distance or pressured:
		return tuning.ai_qb_bullet_power
	if dist < tuning.ai_qb_lob_distance:
		return tuning.ai_qb_normal_power
	if target.velocity.x * pc.off_dir < tuning.ai_qb_lob_min_speed:
		return tuning.ai_qb_drive_power
	for opponent: Player in target.team.opponent.players:
		if opponent.is_down():
			continue
		var deeper: bool = (opponent.position.x - target.position.x) * pc.off_dir > 0.0
		if deeper and _flat_distance(opponent.position, target.position) < tuning.ai_qb_lob_clear:
			return tuning.ai_qb_drive_power
	return tuning.ai_qb_lob_power


## Whether a pass to `target` at `power` is better led or underthrown. Mostly
## neither: he compares how open each spot will be when the ball gets there and
## only moves off the regular one for a clear gain. His judgment is not exact,
## and neither is the throw that follows.
func choose_placement(pc: PlayController, target: Player, power: float) -> PlayController.Placement:
	var speed: float = pc.pass_speed(power)
	var normal: Vector3 = pc.pass_spot(target, speed)
	# About to cut or stop: he throws the route.
	if pc.aim_cuts:
		return PlayController.Placement.NORMAL
	var flight: float = _flat_distance(player.position, normal) / speed
	var run: Vector3 = Vector3(target.velocity.x, 0.0, target.velocity.z)
	if run.length() < tuning.run_speed * 0.5:
		return PlayController.Placement.NORMAL
	var dir: Vector3 = run.normalized()
	var noise: float = tuning.ai_qb_placement_noise * PlayerRatings.blend(player.ratings.accuracy, tuning.accuracy_overlead_scale_low, tuning.accuracy_overlead_scale_high)
	var base: float = _open_at_spot(target, normal, flight)
	var choice: PlayController.Placement = PlayController.Placement.NORMAL
	var lead_gain: float = 0.0

	# Lead him only if he has the legs left to run on to it.
	var ahead: Vector3 = pc.pass_spot(target, speed, PlayController.Placement.LEAD)
	if _flat_distance(ahead, normal) >= 1.0 and not target.turbo_locked and target.turbo >= tuning.ai_qb_lead_min_turbo:
		var gain: float = _open_at_spot(target, ahead, flight) - base + randf_range(-noise, noise)
		if gain >= tuning.ai_qb_lead_margin:
			lead_gain = gain
			choice = PlayController.Placement.LEAD

	# Underthrow him only with nobody trailing: slowing down brings that man in.
	var short: Vector3 = pc.pass_spot(target, speed, PlayController.Placement.UNDER)
	if _flat_distance(short, normal) >= 1.0:
		var trailed: bool = false
		for opponent: Player in target.team.opponent.players:
			var offset: Vector3 = opponent.position - target.position
			offset.y = 0.0
			if not opponent.is_down() and offset.dot(dir) < 0.0 and offset.length() < tuning.ai_qb_under_trail_range:
				trailed = true
		var gain: float = _open_at_spot(target, short, flight) - base + randf_range(-noise, noise)
		if not trailed and gain >= tuning.ai_qb_under_margin and gain > lead_gain:
			choice = PlayController.Placement.UNDER
	return choice


## Distance from `spot` to the nearest defender, each judged by where he will be
## a moment from now (they do not all keep running the same way for the whole
## flight).
func _open_at_spot(target: Player, spot: Vector3, flight: float) -> float:
	var best: float = 10.0
	for opponent: Player in target.team.opponent.players:
		if not opponent.is_down():
			best = minf(best, _flat_distance(opponent.position + opponent.velocity * minf(flight, 0.4), spot))
	return best


func _run_route(pc: PlayController) -> void:
	_call_for_ball(pc)
	if route_index < route.size():
		var target: Vector3 = route[route_index]
		if _flat_distance(player.position, target) < 0.9:
			route_index += 1
		player.move_input = _direction_to(target)
		return
	if route_exit_dir != Vector3.ZERO and not off_assign.settle:
		# Route finished: keep going the same way until the field runs out.
		var ahead: Vector3 = player.position + route_exit_dir * 3.0
		var inside_z: bool = absf(ahead.z) < tuning.half_width() - 1.0
		var inside_x: bool = ahead.x > -tuning.end_zone_depth + 1.5 and ahead.x < tuning.field_length + tuning.end_zone_depth - 1.5
		if inside_z and inside_x:
			player.move_input = route_exit_dir
			return
	if _is_receiver(pc):
		_work_open(pc)


## The CPU is still running him through the waypoints of his route.
func on_route(pc: PlayController) -> bool:
	return is_offense and off_assign != null and pc.phase == PlayController.Phase.POCKET \
			and _is_receiver(pc) and route_index < route.size() \
			and player != pc.human.controlled


## Where his route has him `seconds` from now: along the waypoints still to
## come, then stopped at the end or running on, as the route says. Off his route
## (it is over, or a person has him) it is simply where his run takes him.
## Also sets `route_ahead_dir` and `route_ahead_cut`.
func route_ahead(pc: PlayController, seconds: float) -> Vector3:
	var run: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	route_ahead_cut = false
	if not on_route(pc):
		route_ahead_dir = run.normalized() if run.length() > 0.5 else Vector3.ZERO
		return player.position + run * seconds
	var left: float = maxf(run.length(), player.max_speed()) * maxf(seconds, 0.0)
	var at: Vector3 = player.position
	if off_assign.settle:
		# A route that stops: if he can get to the end of it in time by
		# sprinting, that is where he will be, not somewhere on the way.
		var rest: float = 0.0
		for i: int in range(route_index, route.size()):
			rest += _flat_distance(at, route[i])
			at = route[i]
		if rest <= left * (1.0 if player.turbo_locked else tuning.turbo_speed_multiplier):
			route_ahead_dir = Vector3.ZERO
			route_ahead_cut = true
			return Vector3(at.x, player.position.y, at.z)
		at = player.position
	var first_dir: Vector3 = Vector3.ZERO
	for i: int in range(route_index, route.size()):
		var leg: Vector3 = route[i] - at
		leg.y = 0.0
		var length: float = leg.length()
		if length < 0.001:
			continue
		var dir: Vector3 = leg / length
		if first_dir == Vector3.ZERO:
			first_dir = dir
		if left <= length:
			route_ahead_dir = dir
			route_ahead_cut = dir.dot(first_dir) < ROUTE_CUT_DOT
			return at + dir * left
		left -= length
		at += leg
	if off_assign.settle or route_exit_dir == Vector3.ZERO:
		route_ahead_dir = Vector3.ZERO
		route_ahead_cut = true
		return at
	route_ahead_dir = route_exit_dir
	route_ahead_cut = first_dir != Vector3.ZERO and route_exit_dir.dot(first_dir) < ROUTE_CUT_DOT
	var end: Vector3 = at + route_exit_dir * left
	var limit_z: float = tuning.half_width() - 1.0
	var back: float = tuning.end_zone_depth - 1.5
	end.x = clampf(end.x, -back, tuning.field_length + back)
	end.z = clampf(end.z, -limit_z, limit_z)
	return end


## Running a route to be thrown to. On a play-action play that includes the back
## who took the fake.
func _is_receiver(pc: PlayController) -> bool:
	if pc.off_play.is_run:
		return false
	return off_assign.job == OffenseAssignment.Job.ROUTE or off_assign.job == OffenseAssignment.Job.RUNNER


## Nowhere left to run: after a moment he goes looking for open grass. A better
## get-open rating looks again sooner, judges the space better and moves faster.
func _work_open(pc: PlayController) -> void:
	if _open_delay < 0.0:
		_open_delay = randf_range(tuning.ai_get_open_delay_min, tuning.ai_get_open_delay_max)
		_open_spot = player.position
	# Wide open, he is happy where he is.
	var wide_open: bool = pc.nearest_opponent_distance(player) >= tuning.ai_get_open_stay_distance
	_wait_time += _delta * (tuning.ai_get_open_stay_scale if wide_open else 1.0)
	if _wait_time < _open_delay:
		return
	var skill: int = player.ratings.get_open
	_open_timer -= _delta
	if _open_timer <= 0.0:
		_open_timer = PlayerRatings.blend(skill, tuning.get_open_rethink_low, tuning.get_open_rethink_high) * randf_range(0.75, 1.25)
		_open_spot = player.position if wide_open else _find_open_spot(pc)
	player.ai_speed_scale = PlayerRatings.blend(skill, tuning.get_open_speed_scale_low, tuning.get_open_speed_scale_high)
	_seek(_open_spot)


## A receiver downfield with room around him calls for the ball while the
## quarterback still has it. The gap he needs to start is wider than the gap
## that stops him, so he does not flicker with a defender on the edge of it.
func _call_for_ball(pc: PlayController) -> void:
	if pc.phase != PlayController.Phase.POCKET or not pc.qb.has_ball or pc.faking() \
			or not _is_receiver(pc) \
			or (player.position.x - pc.los_x) * pc.off_dir < 1.0:
		_calling = false
		return
	var gap: float = pc.nearest_opponent_distance(player)
	if _calling:
		_calling = gap >= tuning.ai_qb_open_distance - tuning.ai_call_close_margin
	else:
		_calling = gap >= tuning.ai_qb_open_distance + tuning.ai_call_open_margin
	player.calling_for_ball = _calling


## The best of a ring of spots around him (or staying put): far from any
## defender, clear of other receivers, with nobody in the throwing lane.
func _find_open_spot(pc: PlayController) -> Vector3:
	var noise: float = PlayerRatings.blend(player.ratings.get_open, tuning.get_open_noise_low, tuning.get_open_noise_high)
	var limit_z: float = tuning.half_width() - 1.5
	var back: float = tuning.end_zone_depth - 1.5
	var reach: float = pc.pass_range() - 2.0
	var passer: Vector3 = pc.qb.position
	var best: Vector3 = player.position
	var best_score: float = -INF
	for i: int in 9:
		var spot: Vector3 = player.position
		if i < 8:
			spot += Vector3.RIGHT.rotated(Vector3.UP, TAU * float(i) / 8.0) * tuning.ai_get_open_radius
			if absf(spot.z) > limit_z or spot.x < -back or spot.x > tuning.field_length + back:
				continue
			if _flat_distance(spot, passer) > reach:
				continue
		var lane: Vector2 = Vector2(spot.x - passer.x, spot.z - passer.z)
		var open: float = 10.0
		var score: float = 0.0
		for opponent: Player in player.team.opponent.players:
			if opponent.is_down():
				continue
			open = minf(open, _flat_distance(opponent.position, spot))
			# A defender standing between the quarterback and the spot.
			var rel: Vector2 = Vector2(opponent.position.x - passer.x, opponent.position.z - passer.z)
			var along: float = rel.dot(lane) / maxf(lane.length_squared(), 0.01)
			if along > 0.25 and along < 0.95 and (rel - lane * along).length() < tuning.ai_get_open_lane_width:
				score -= tuning.ai_get_open_lane_penalty
		score += open
		for mate: Player in pc.eligible:
			if mate != player and not mate.is_down():
				score -= maxf(tuning.ai_get_open_spacing - _flat_distance(mate.position, spot), 0.0) * 0.5
		# Drifting back behind the line helps nobody.
		score -= maxf(1.0 - (spot.x - pc.los_x) * pc.off_dir, 0.0)
		if i == 8:
			# Staying put wins a near tie, so he does not dither.
			score += 0.5
		score += randf_range(-noise, noise)
		if score > best_score:
			best_score = score
			best = spot
	return best


func _carry(pc: PlayController) -> void:
	var forward: Vector3 = Vector3(float(player.team.attack_dir), 0.0, 0.0)
	var steer: Vector3 = forward
	var nearest: float = INF
	var nearest_opponent: Player = null
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		var to: Vector3 = opponent.position - player.position
		var dist: float = to.length()
		if dist < nearest:
			nearest = dist
			nearest_opponent = opponent
		if dist < tuning.ai_carrier_avoid_radius and to.dot(forward) > -1.0:
			var side: float = signf(to.z)
			if side == 0.0:
				side = signf(player.position.z)
			steer.z -= side * (1.0 - dist / tuning.ai_carrier_avoid_radius) * 1.3
	var edge: float = tuning.half_width() - 3.0
	if absf(player.position.z) > edge:
		steer.z -= signf(player.position.z) * 2.0
	player.move_input = steer.normalized()
	player.wants_turbo = nearest < tuning.ai_turbo_range

	if nearest_opponent == null or not player.can_act():
		return
	if _dive_for_the_line(pc, nearest):
		pc.do_dive(player, forward)
		return
	if _decision_timer <= 0.0 and _move_due(pc, nearest_opponent, nearest):
		_decision_timer = 0.5
		_move_lead = -1.0
		_carrier_move(pc, nearest_opponent)


## True on the tick this carrier means to start his spin or stiff arm against
## `opponent`. Well timed, that is just before the tackler gets there; but he
## does not always time it well. Too early and the move is over by the time the
## tackler arrives, too late and he has already been hit.
func _move_due(pc: PlayController, opponent: Player, dist: float) -> bool:
	if dist > tuning.ai_move_range:
		return false
	if _move_lead < 0.0:
		_move_lead = tuning.ai_move_lead
		_move_late = 0.0
		if randf() < tuning.ai_move_mistime_chance * _mistime_scale():
			pc.game.add_stat(&"mistimed_moves")
			if randf() < 0.5:
				_move_lead = randf_range(tuning.ai_move_early_min, tuning.ai_move_early_max)
			else:
				_move_late = randf_range(tuning.ai_move_late_min, tuning.ai_move_late_max)
	var to: Vector3 = opponent.position - player.position
	to.y = 0.0
	var closing: float = (player.velocity - opponent.velocity).dot(to / maxf(dist, 0.01))
	# Seconds until the tackler is within reach.
	var contact: float = (dist - tuning.tackle_radius) / maxf(closing, 0.5)
	if contact > _move_lead:
		return false
	if _move_late > 0.0:
		_move_late -= _delta
		return false
	return true


func _mistime_scale() -> float:
	return PlayerRatings.blend(player.ratings.juke, tuning.move_mistime_scale_low, tuning.move_mistime_scale_high)


## With a tackler about to arrive, a dive that reaches the goal line or the
## first-down marker is worth more than staying on his feet.
func _dive_for_the_line(pc: PlayController, nearest: float) -> bool:
	var dir: float = float(player.team.attack_dir)
	var goal_x: float = tuning.field_length if dir > 0.0 else 0.0
	var to_goal: float = (goal_x - player.position.x) * dir
	if to_goal > 0.0 and to_goal <= tuning.ai_dive_reach and nearest < tuning.ai_dive_goal_pressure:
		return true
	if player.team != pc.offense or pc.game.goal_to_go:
		return false
	var to_marker: float = (pc.game.first_down_x - player.position.x) * dir
	return to_marker > 0.0 and to_marker <= tuning.ai_dive_reach and nearest < tuning.ai_dive_marker_pressure


## Picks the move that fits where the tackler is coming from: a stiff arm for one
## closing from the side, a spin for one straight ahead.
func _carrier_move(pc: PlayController, opponent: Player) -> void:
	var to: Vector3 = opponent.position - player.position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	to = to.normalized()
	var ahead: float = to.dot(player.facing)
	var left: float = to.dot(Vector3.UP.cross(player.facing))

	if absf(left) > tuning.ai_stiff_arm_side_dot and ahead > -0.5:
		# Strong carriers use the stiff arm more.
		if randf() < tuning.ai_stiff_arm_chance * float(player.ratings.strength) / 50.0:
			var side: float = signf(left)
			if randf() < tuning.ai_move_wrong_side_chance * _mistime_scale():
				# The wrong arm: it does nothing for him.
				side = -side
				pc.game.add_stat(&"mistimed_moves")
			pc.do_stiff_arm(player, side)
		return

	# Elusive carriers spin more. The spin sidesteps away from the tackler.
	if randf() < tuning.ai_spin_chance * float(player.ratings.juke) / 50.0:
		pc.do_spin(player, -signf(left) if left != 0.0 else 1.0, true)


## Get between the most dangerous nearby opponent and the thing being protected.
func _block(pc: PlayController, protect: Vector3) -> void:
	player.is_blocking = true
	var best: Player = null
	var best_score: float = INF
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		var score: float = _flat_distance(opponent.position, player.position) + 0.35 * _flat_distance(opponent.position, protect)
		if score < best_score:
			best_score = score
			best = opponent
	if best == null:
		return
	var toward: Vector3 = protect - best.position
	toward.y = 0.0
	var spot: Vector3 = best.position
	if toward.length_squared() > 0.01:
		spot += toward.normalized() * 0.9
	_seek(spot)
	if pc.phase == PlayController.Phase.RUN:
		player.wants_turbo = _flat_distance(player.position, spot) > 4.0


# --- Defense -----------------------------------------------------------------

func _defense_pocket(pc: PlayController) -> void:
	if _sees_scramble(pc):
		_pursue(pc, pc.qb)
		return
	if pc.live_time < bite_time and pc.phase == PlayController.Phase.POCKET and pc.runner != null:
		# Sold on the faked handoff: he comes up to stop the run.
		_seek(pc.runner.position)
		return
	match def_assign.job:
		DefenseAssignment.Job.RUSH:
			# Rushers hold their turbo at first so the QB gets a moment to read.
			_pursue(pc, pc.qb, pc.live_time >= tuning.ai_rush_turbo_delay)
		DefenseAssignment.Job.MAN:
			if man_target == null:
				_cover_zone(pc)
			else:
				_cover_man(pc)
		DefenseAssignment.Job.ZONE:
			_cover_zone(pc)
		DefenseAssignment.Job.SPY:
			_spy(pc)
			return
	if pc.live_time < blown_time:
		# Blown coverage: caught flat-footed, looking into the backfield.
		player.move_input = Vector3.ZERO
		player.wants_turbo = false


## An underneath zone defender has his eyes on the backfield: he comes up as
## soon as the quarterback tucks the ball and heads for the line. Everyone else
## in coverage has his back turned until the quarterback crosses it.
func _sees_scramble(pc: PlayController) -> bool:
	if def_assign.job != DefenseAssignment.Job.ZONE or def_assign.deep or pc.phase != PlayController.Phase.POCKET:
		return false
	if pc.qb_tuck_time < tuning.ai_scramble_read_time or pc.qb.velocity.x * pc.off_dir < 1.0:
		return false
	return _flat_distance(player.position, pc.qb.position) <= tuning.ai_scramble_read_range


## Shadow the quarterback from just past the line; go and get him once he tucks
## the ball or comes up to the line.
func _spy(pc: PlayController) -> void:
	var passer: Player = pc.qb
	var depth: float = (pc.los_x - passer.position.x) * pc.off_dir
	if pc.qb_tuck_time >= tuning.ai_spy_react_time or depth < tuning.ai_spy_trigger_depth:
		_pursue(pc, passer)
		return
	var limit: float = tuning.half_width() - 2.0
	_seek(Vector3(pc.los_x + pc.off_dir * tuning.ai_spy_depth, 0.0, clampf(passer.position.z, -limit, limit)))


func _cover_man(pc: PlayController) -> void:
	var aim: Vector3 = _cover_spot(pc, man_target)
	# Stay on his deep side: a catch in front of the defender is a tackle, one
	# behind him is a touchdown.
	aim.x += pc.off_dir * tuning.ai_cover_cushion * (-1.0 if def_assign.underneath else 1.0)
	player.ai_speed_scale = tuning.ai_cover_speed_scale * _cut_scale(man_target)
	_seek(aim)
	# Beaten: he is past the defender or has pulled away. Burn turbo to recover.
	var behind: float = (man_target.position.x - player.position.x) * pc.off_dir
	var gap: float = _flat_distance(player.position, man_target.position)
	player.wants_turbo = _bust_timer <= 0.0 and (behind > tuning.ai_cover_beaten_depth or gap > tuning.ai_cover_beaten_gap)


func _cover_zone(pc: PlayController) -> void:
	var deep: bool = def_assign.deep
	var hot: Player = pc.hot_receiver()
	var threat: Player = null
	var best: float = -INF
	var nearest: Player = null
	var nearest_dist: float = INF
	for receiver: Player in pc.eligible:
		if receiver.is_down():
			continue
		# Judge him by where he is heading, not only where he is.
		var soon: Vector3 = receiver.position + receiver.velocity * tuning.ai_zone_anticipate
		var dist: float = minf(_flat_distance(soon, zone_center), _flat_distance(receiver.position, zone_center))
		var reach: float = zone_radius
		if receiver == hot:
			# The man who keeps getting the ball draws help from further away.
			reach *= tuning.ai_hot_zone_scale
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = receiver
		if dist > reach:
			continue
		# Deep zones take the deepest man; underneath zones take the closest.
		var score: float = (receiver.position.x - pc.los_x) * pc.off_dir if deep else -dist
		if receiver == hot:
			score += tuning.ai_hot_bonus
		if score > best:
			best = score
			threat = receiver

	var aim: Vector3 = zone_center
	if threat != null:
		var spot: Vector3 = _cover_spot(pc, threat)
		if deep:
			# Over the top of him, shaded toward the middle of the zone.
			aim = Vector3(spot.x + pc.off_dir * tuning.ai_deep_cushion, 0.0, lerpf(zone_center.z, spot.z, tuning.ai_zone_tightness))
		else:
			aim = zone_center.lerp(spot, tuning.ai_zone_tightness)
			aim.x += pc.off_dir * tuning.ai_cover_cushion
	elif nearest != null:
		# Nobody in the area yet: lean toward whoever is closest to coming in.
		var lean: Vector3 = nearest.position - zone_center
		lean.y = 0.0
		aim = zone_center + lean.limit_length(zone_radius * tuning.ai_zone_lean)
	if deep:
		# Never let a receiver on this side of the field get behind.
		for receiver: Player in pc.eligible:
			if receiver.is_down() or absf(receiver.position.z - zone_center.z) > zone_radius:
				continue
			var floor_x: float = receiver.position.x + pc.off_dir * tuning.ai_deep_cushion
			if (floor_x - aim.x) * pc.off_dir > 0.0:
				aim.x = floor_x
		# ...and do not get pulled up by short routes.
		var shallowest: float = zone_center.x - pc.off_dir * zone_radius * tuning.ai_deep_step_up
		if (shallowest - aim.x) * pc.off_dir > 0.0:
			aim.x = shallowest
	player.ai_speed_scale = tuning.ai_cover_speed_scale
	if threat != null:
		player.ai_speed_scale *= _cut_scale(threat)
	_seek(aim)
	if threat != null and _bust_timer <= 0.0:
		var behind: float = (threat.position.x - player.position.x) * pc.off_dir
		player.wants_turbo = behind > tuning.ai_cover_beaten_depth or (not deep and _flat_distance(player.position, threat.position) > tuning.ai_cover_beaten_gap)


## Speed factor while the defender is still catching up with a cut: the further
## his read is from what the receiver is really doing, the slower he moves.
func _cut_scale(target: Player) -> float:
	if _bust_timer > 0.0:
		return tuning.ai_cover_bust_speed
	var slow: float = minf(tuning.ai_cover_cut_slow * _cover_handicap(target), 1.0)
	return 1.0 - slow * clampf(_surprise(target) * 0.5, 0.0, 1.0)


## How far the defender's read is from what the receiver is really doing:
## 0 = spot on, 1 = off by a full run speed, 2 = he has turned right around.
func _surprise(target: Player) -> float:
	return (target.velocity - _read_velocity).length() / maxf(tuning.run_speed, 0.01)


## Multiplies how late and how slow this defender is on the receiver's cuts:
## his own coverage rating against the receiver's knack for getting open.
func _cover_handicap(target: Player) -> float:
	var handicap: float = PlayerRatings.blend(player.ratings.coverage, tuning.coverage_scale_low, tuning.coverage_scale_high) \
		* PlayerRatings.blend(target.ratings.get_open, tuning.get_open_scale_low, tuning.get_open_scale_high)
	var pc: PlayController = player.play
	if target == pc.read_target:
		# He has seen this route before.
		handicap *= lerpf(1.0, tuning.ai_scout_cover_scale, pc.read)
	return handicap


## Where this defender thinks he has to be to stay with `target`.
func _cover_spot(pc: PlayController, target: Player) -> Vector3:
	_bust_cooldown = maxf(_bust_cooldown - _delta, 0.0)
	if _bust_timer <= 0.0 and _bust_cooldown <= 0.0 and pc.live_time >= tuning.ai_cover_bust_min_time and _surprise(target) >= tuning.ai_cover_bust_surprise:
		# A sharp cut: one roll to see whether he bites on it.
		_bust_cooldown = tuning.ai_cover_bust_cooldown
		var chance: float = tuning.ai_cover_bust_chance
		chance *= PlayerRatings.blend(target.ratings.get_open, tuning.bust_get_open_scale_low, tuning.bust_get_open_scale_high)
		chance *= PlayerRatings.blend(player.ratings.coverage, tuning.bust_coverage_scale_low, tuning.bust_coverage_scale_high)
		if target == pc.read_target:
			chance *= 1.0 - pc.read
		if randf() < chance:
			_bust_timer = tuning.ai_cover_bust_time
			_bust_ghost = target.position
			pc.game.add_stat(&"coverage_busts")
	if _bust_timer > 0.0:
		# Fooled: he keeps chasing the receiver he thought he saw.
		_bust_timer -= _delta
		_bust_ghost += _read_velocity * _delta
		return _bust_ghost
	return target.position + _read(target) * tuning.ai_cover_lead


## The receiver's velocity as this defender has read it so far.
func _read(target: Player) -> Vector3:
	var lag: float = tuning.ai_cover_lag * _cover_handicap(target)
	var pc: PlayController = player.play
	if pc.phase == PlayController.Phase.AIR and pc.ball.intended == target:
		# With the ball in the air he watches the man it is going to: a receiver
		# who pulls up for it is read sooner than one making a cut.
		lag *= 0.5
	if lag <= 0.0:
		_read_velocity = target.velocity
	else:
		_read_velocity = _read_velocity.lerp(target.velocity, minf(_delta / lag, 1.0))
	return _read_velocity


## Coverage defenders take a moment to see that it is a handoff, not a pass.
func _reading_run(pc: PlayController, carrier: Player) -> bool:
	if def_assign == null or def_assign.job == DefenseAssignment.Job.RUSH or def_assign.job == DefenseAssignment.Job.SPY:
		return false
	# A run the defense has seen again and again is read sooner.
	var read_time: float = tuning.ai_run_read_time * (1.0 - tuning.ai_scout_react_saving * pc.read)
	return carrier == pc.runner and pc.handoff_done and pc.live_time - pc.handoff_time < read_time


## Run to where the target will be, not where it is.
func _pursue(pc: PlayController, target: Player, allow_turbo: bool = true) -> void:
	var lead: float = Ball.intercept_time(player.position, target.position, target.velocity, player.max_speed())
	lead = minf(lead, tuning.ai_pursuit_max_lead)
	var aim: Vector3 = target.position + target.velocity * lead
	player.move_input = _direction_to(aim)
	var dist: float = _flat_distance(player.position, target.position)
	player.wants_turbo = allow_turbo and dist < tuning.ai_turbo_range
	if dist < tuning.ai_dive_range and _decision_timer <= 0.0:
		_decision_timer = 0.4
		if randf() < tuning.ai_dive_chance:
			pc.do_dive(player, _direction_to(target.position + target.velocity * 0.12))


# --- Ball in the air / dead ball ------------------------------------------------

func _think_air(pc: PlayController) -> void:
	var landing: Vector3 = pc.ball.target_point
	if is_offense:
		if pc.ball.intended == player:
			_seek(landing)
			player.wants_turbo = _flat_distance(player.position, landing) > 1.5
			_go_for_ball(pc)
		elif off_assign.job == OffenseAssignment.Job.BLOCK:
			_block(pc, pc.qb.position)
		elif off_assign.job != OffenseAssignment.Job.QB:
			_run_route(pc)
		return

	var react_time: float = tuning.ai_ball_react_time
	if pc.ball.intended == pc.read_target:
		# The throw the defense was waiting for.
		react_time *= 1.0 - tuning.ai_scout_react_saving * pc.read
	if pc.live_time - pc.throw_time < react_time:
		_defense_pocket(pc)
		return
	var time_left: float = maxf(pc.ball.flight_time - pc.ball.flight_elapsed, 0.0)
	var dist: float = _flat_distance(player.position, landing)
	if not pc.ball_breakers.has(player):
		# Too far to make a play on the ball: get in front of the catch instead.
		var depth: float = tuning.ai_ball_cut_off
		if pc.ball_coverer == player:
			# His man is pulling up for a short ball: he stays with the catch
			# instead of running on past it.
			depth = lerpf(depth, tuning.ai_cover_cushion, clampf(pc.pass_short / maxf(tuning.ai_ball_short_full, 0.01), 0.0, 1.0))
		var cut_off: Vector3 = landing + Vector3(pc.off_dir * depth, 0.0, 0.0)
		player.move_input = _direction_to(cut_off)
		player.wants_turbo = dist < tuning.ai_ball_react_radius
		return
	_seek(landing)
	player.wants_turbo = dist > 1.0
	# Close enough as the ball comes down: go up for it.
	if not _contest_decided and time_left <= tuning.ai_contest_time and dist <= tuning.ai_contest_range:
		_contest_decided = true
		if randf() < tuning.ai_contest_chance:
			pc.do_jump(player)
	_go_for_ball(pc)


## The ball is coming down out of his reach: sometimes he leaves his feet for
## it, with a jump if that gets him there and a dive if it takes more. Most of
## the time he just keeps running. Decided once per pass.
func _go_for_ball(pc: PlayController) -> void:
	var time_left: float = pc.ball.flight_time - pc.ball.flight_elapsed
	if _contest_decided or time_left > tuning.ai_catch_effort_time:
		return
	var landing: Vector3 = pc.ball.target_point
	var reach: float = pc.catch_reach(player, landing)
	# How far off he will be if he stays on his feet.
	var short: float = _flat_distance(player.position + player.velocity * time_left, landing)
	if short <= reach:
		return
	_contest_decided = true
	var effort: float = tuning.ai_catch_effort_chance * PlayerRatings.blend(player.ratings.catching, tuning.catch_scale_low, tuning.catch_scale_high)
	if pc.human.team == player.team:
		effort *= tuning.ai_catch_effort_human_scale
	if randf() >= effort:
		return
	if short <= reach * tuning.jump_catch_radius_scale:
		pc.game.add_stat(&"catch_efforts")
		pc.do_jump(player)
	elif _flat_distance(player.position, landing) <= tuning.dive_ball_range:
		pc.game.add_stat(&"catch_efforts")
		pc.do_dive(player, _direction_to(landing))


func _think_dead(pc: PlayController, delta: float) -> void:
	player.look_dir = Vector3.ZERO
	if pc.result == PlayController.Result.TOUCHDOWN and pc.scorer != null:
		if pc.is_celebrating(player):
			_celebrate(pc)
		else:
			_sulk(pc)
		return
	if _late_hit_used or randf() > tuning.ai_late_hit_chance * delta:
		return
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		if _flat_distance(opponent.position, player.position) < tuning.shove_radius * 1.4:
			_late_hit_used = true
			pc.do_shove(player, _direction_to(opponent.position))
			return


## His team has scored. The scorer stays where he is and dances, facing back up
## the field; everyone else runs to his place round him and joins in.
func _celebrate(pc: PlayController) -> void:
	var scorer: Player = pc.scorer
	if player == scorer:
		player.look_dir = Vector3(-float(player.team.attack_dir), 0.0, 0.0)
		return
	var slot: Vector3 = pc.celebration_slot(player)
	var gap: float = _flat_distance(player.position, slot)
	# Once he is there he only moves again if the party has drifted well away.
	if gap <= 0.5:
		_at_party = true
	elif gap > 1.5:
		_at_party = false
	if _at_party:
		player.look_dir = _direction_to(scorer.position)
		return
	player.move_input = _direction_to(slot)
	player.wants_turbo = gap > 8.0
	player.ai_speed_scale = clampf(gap / 3.0, 0.3, 1.0)


## The other team has scored. Mostly he stands and takes it badly; one kind
## wanders off with his head down, and the one who has had enough runs at
## somebody celebrating and dives into him.
func _sulk(pc: PlayController) -> void:
	if cheap_shot_delay >= 0.0 and not _late_hit_used and pc.dead_time >= cheap_shot_delay:
		var victim: Player = _cheap_shot_victim(pc)
		if victim != null:
			var dir: Vector3 = _direction_to(victim.position)
			if _flat_distance(player.position, victim.position) <= tuning.cheap_shot_dive_range:
				_late_hit_used = true
				pc.do_dive(player, dir)
			else:
				player.move_input = dir
				player.wants_turbo = true
			return
	# Nobody stands and sulks in the middle of the other team's party.
	if _flat_distance(player.position, pc.scorer.position) < tuning.celebration_ring_radius + 2.0:
		player.move_input = -_direction_to(pc.scorer.position)
		player.ai_speed_scale = 0.35
		return
	if pc.celebration_variant(player, PlayerAnimator.SULKS) == PlayerAnimator.SULK_TRUDGE and pc.dead_time > 1.0:
		var away: Vector3 = Vector3(-float(pc.scorer.team.attack_dir), 0.0, signf(player.position.z - pc.scorer.position.z) * 0.4)
		player.move_input = away.normalized()
		player.ai_speed_scale = 0.22


func _cheap_shot_victim(pc: PlayController) -> Player:
	if cheap_shot_scorer and not pc.scorer.is_down():
		return pc.scorer
	var victim: Player = null
	var best: float = INF
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		var dist: float = _flat_distance(opponent.position, player.position)
		if dist < best:
			best = dist
			victim = opponent
	return victim


# --- Helpers -----------------------------------------------------------------

func _reset() -> void:
	route = PackedVector3Array()
	route_index = 0
	route_exit_dir = Vector3.ZERO
	man_target = null
	blown_time = 0.0
	bite_time = 0.0
	_decision_timer = 0.0
	_move_lead = -1.0
	_move_late = 0.0
	_keeper_rolled = false
	_keeper_time = -1.0
	_late_hit_used = false
	cheap_shot_delay = -1.0
	cheap_shot_scorer = true
	_at_party = false
	_read_velocity = Vector3.ZERO
	_contest_decided = false
	_scrambling = false
	_rollout = 0.0
	_keep_ball = false
	_bust_timer = 0.0
	_bust_cooldown = 0.0
	_wait_time = 0.0
	_open_timer = 0.0
	_open_delay = -1.0
	_calling = false
	sees_ball = false
	_notice_time = 0.0
	_loose_decided = false


## Move toward a point, easing off when close so the player settles on it.
func _seek(point: Vector3) -> void:
	var to: Vector3 = point - player.position
	to.y = 0.0
	var dist: float = to.length()
	if dist < 0.15:
		player.move_input = Vector3.ZERO
		return
	player.move_input = to / dist * clampf(dist / 1.2, 0.25, 1.0)


func _direction_to(point: Vector3) -> Vector3:
	var to: Vector3 = point - player.position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return player.facing
	return to.normalized()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
