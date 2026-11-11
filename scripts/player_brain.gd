class_name PlayerBrain
extends RefCounted
## CPU decision-making for one player. think() only sets the player's inputs
## (move_input, wants_turbo) and asks PlayController for actions; it never moves
## the player itself.

var player: Player
var tuning: Tuning

var off_assign: OffenseAssignment
var def_assign: DefenseAssignment
var is_offense: bool = false

var route: PackedVector3Array = PackedVector3Array()
var route_index: int = 0
var route_exit_dir: Vector3 = Vector3.ZERO
var start_point: Vector3 = Vector3.ZERO

var man_target: Player
var zone_center: Vector3 = Vector3.ZERO
var zone_radius: float = 0.0

var _decision_timer: float = 0.0
var _late_hit_used: bool = false
var _delta: float = 0.0
## What a coverage defender believes his receiver is doing. It follows the real
## velocity with a short delay, so a sharp cut buys the receiver a step.
var _read_velocity: Vector3 = Vector3.ZERO
## Decided once per pass: whether this defender goes up for the ball.
var _contest_decided: bool = false
## The CPU quarterback has given up on the pass and is running with it.
var _scrambling: bool = false
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
	player.ai_speed_scale = 1.0
	_delta = delta
	_decision_timer = maxf(_decision_timer - delta, 0.0)
	# A stiff arm is done on the run, so the brain keeps steering through it.
	if not player.can_act() and player.state != Player.State.STIFF_ARM:
		return
	if pc.ball_dead:
		_think_dead(pc, delta)
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
		player.wants_turbo = true
		return
	var drop_point: Vector3 = route[route.size() - 1] if route.size() > 0 else start_point
	_seek(drop_point)
	if pc.off_play.is_run:
		return
	if pc.live_time < tuning.ai_qb_min_time or _decision_timer > 0.0:
		return
	_decision_timer = 0.15

	var pressured: bool = pc.nearest_opponent_distance(player) < tuning.ai_qb_pressure_radius
	var out_of_time: bool = pc.live_time >= tuning.ai_qb_max_time
	var checkdowns: bool = pressured or pc.live_time >= tuning.ai_qb_checkdown_time
	var best: Player = null
	var best_open: float = -1.0
	var best_score: float = -INF
	for receiver: Player in pc.eligible:
		if receiver.is_down():
			continue
		if not checkdowns and (receiver.position.x - pc.los_x) * pc.off_dir < tuning.ai_qb_min_depth:
			continue
		# No point throwing further than his arm reaches.
		if _flat_distance(receiver.position, player.position) > pc.pass_range():
			continue
		# Open now, and still open where the ball would come down.
		var open: float = minf(minf(pc.nearest_opponent_distance(receiver), _open_at_catch(pc, receiver)), 10.0)
		var downfield: float = (receiver.position.x - pc.los_x) * pc.off_dir
		var score: float = open + downfield * 0.08
		if score > best_score:
			best_score = score
			best_open = open
			best = receiver

	if best == null or (out_of_time and not pressured and best_open < tuning.ai_qb_scramble_open):
		if out_of_time or pressured:
			# Nobody to throw to: tuck it and run.
			_scrambling = true
		return
	if best_open >= tuning.ai_qb_open_distance or pressured or out_of_time:
		pc.throw_ball(best, choose_pass(pc, best, best_open, pressured))


## Distance from the nearest defender to the spot a regular pass to `receiver`
## would be thrown at.
func _open_at_catch(pc: PlayController, receiver: Player) -> float:
	var speed: float = lerpf(tuning.pass_lob_speed, tuning.pass_bullet_speed, tuning.ai_qb_normal_power)
	var lead: float = minf(Ball.intercept_time(player.position, receiver.position, receiver.velocity, speed), tuning.pass_max_lead_time)
	var spot: Vector3 = receiver.position + receiver.velocity * lead
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


func _run_route(pc: PlayController) -> void:
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
	if off_assign.job == OffenseAssignment.Job.ROUTE and not pc.off_play.is_run:
		_work_open(pc)


## Nowhere left to run: after a moment he goes looking for open grass. A better
## get-open rating looks again sooner, judges the space better and moves faster.
func _work_open(pc: PlayController) -> void:
	_wait_time += _delta
	if _wait_time < tuning.ai_get_open_delay:
		return
	var skill: int = player.ratings.get_open
	_open_timer -= _delta
	if _open_timer <= 0.0:
		_open_timer = PlayerRatings.blend(skill, tuning.get_open_rethink_low, tuning.get_open_rethink_high)
		_open_spot = _find_open_spot(pc)
	player.ai_speed_scale = PlayerRatings.blend(skill, tuning.get_open_speed_scale_low, tuning.get_open_speed_scale_high)
	_seek(_open_spot)


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
	if nearest < 2.6 and _decision_timer <= 0.0:
		_decision_timer = 0.5
		_carrier_move(pc, nearest_opponent)


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
			pc.do_stiff_arm(player, signf(left))
		return

	# Elusive carriers spin more.
	if randf() < tuning.ai_spin_chance * float(player.ratings.juke) / 50.0:
		pc.do_spin(player, -signf(left) if left != 0.0 else 1.0)


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


func _cover_man(pc: PlayController) -> void:
	var aim: Vector3 = _cover_spot(pc, man_target)
	# Stay on his deep side: a catch in front of the defender is a tackle, one
	# behind him is a touchdown.
	aim.x += pc.off_dir * tuning.ai_cover_cushion
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
	return PlayerRatings.blend(player.ratings.coverage, tuning.coverage_scale_low, tuning.coverage_scale_high) \
		* PlayerRatings.blend(target.ratings.get_open, tuning.get_open_scale_low, tuning.get_open_scale_high)


## Where this defender thinks he has to be to stay with `target`.
func _cover_spot(pc: PlayController, target: Player) -> Vector3:
	_bust_cooldown = maxf(_bust_cooldown - _delta, 0.0)
	if _bust_timer <= 0.0 and _bust_cooldown <= 0.0 and pc.live_time >= tuning.ai_cover_bust_min_time and _surprise(target) >= tuning.ai_cover_bust_surprise:
		# A sharp cut: one roll to see whether he bites on it.
		_bust_cooldown = tuning.ai_cover_bust_cooldown
		var chance: float = tuning.ai_cover_bust_chance
		chance *= PlayerRatings.blend(target.ratings.get_open, tuning.bust_get_open_scale_low, tuning.bust_get_open_scale_high)
		chance *= PlayerRatings.blend(player.ratings.coverage, tuning.bust_coverage_scale_low, tuning.bust_coverage_scale_high)
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
	if lag <= 0.0:
		_read_velocity = target.velocity
	else:
		_read_velocity = _read_velocity.lerp(target.velocity, minf(_delta / lag, 1.0))
	return _read_velocity


## Coverage defenders take a moment to see that it is a handoff, not a pass.
func _reading_run(pc: PlayController, carrier: Player) -> bool:
	if def_assign == null or def_assign.job == DefenseAssignment.Job.RUSH:
		return false
	return carrier == pc.runner and pc.handoff_done and pc.live_time - pc.handoff_time < tuning.ai_run_read_time


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
		elif off_assign.job == OffenseAssignment.Job.BLOCK:
			_block(pc, pc.qb.position)
		elif off_assign.job != OffenseAssignment.Job.QB:
			_run_route(pc)
		return

	if pc.live_time - pc.throw_time < tuning.ai_ball_react_time:
		_defense_pocket(pc)
		return
	var time_left: float = maxf(pc.ball.flight_time - pc.ball.flight_elapsed, 0.0)
	var dist: float = _flat_distance(player.position, landing)
	if not pc.ball_breakers.has(player):
		# Too far to make a play on the ball: get in front of the catch instead.
		var cut_off: Vector3 = landing + Vector3(pc.off_dir * tuning.ai_ball_cut_off, 0.0, 0.0)
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


func _think_dead(pc: PlayController, delta: float) -> void:
	if _late_hit_used or randf() > tuning.ai_late_hit_chance * delta:
		return
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		if _flat_distance(opponent.position, player.position) < tuning.shove_radius * 1.4:
			_late_hit_used = true
			pc.do_shove(player, _direction_to(opponent.position))
			return


# --- Helpers -----------------------------------------------------------------

func _reset() -> void:
	route = PackedVector3Array()
	route_index = 0
	route_exit_dir = Vector3.ZERO
	man_target = null
	_decision_timer = 0.0
	_late_hit_used = false
	_read_velocity = Vector3.ZERO
	_contest_decided = false
	_scrambling = false
	_bust_timer = 0.0
	_bust_cooldown = 0.0
	_wait_time = 0.0
	_open_timer = 0.0


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
