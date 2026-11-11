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
	_decision_timer = maxf(_decision_timer - delta, 0.0)
	if not player.can_act():
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
			_run_route()


func _quarterback(pc: PlayController) -> void:
	var drop_point: Vector3 = route[route.size() - 1] if route.size() > 0 else start_point
	_seek(drop_point)
	if pc.off_play.is_run:
		return
	if pc.live_time < tuning.ai_qb_min_time or _decision_timer > 0.0:
		return
	_decision_timer = 0.15

	var best: Player = null
	var best_open: float = -1.0
	var best_score: float = -INF
	for receiver: Player in pc.eligible:
		if receiver.is_down():
			continue
		var open: float = minf(pc.nearest_opponent_distance(receiver), 10.0)
		var downfield: float = (receiver.position.x - pc.los_x) * pc.off_dir
		var score: float = open + downfield * 0.08
		if score > best_score:
			best_score = score
			best_open = open
			best = receiver

	var pressured: bool = pc.nearest_opponent_distance(player) < tuning.ai_qb_pressure_radius
	var out_of_time: bool = pc.live_time >= tuning.ai_qb_max_time
	if best == null:
		if out_of_time or pressured:
			# Nobody to throw to: tuck it and run.
			player.move_input = Vector3(pc.off_dir, 0.0, 0.0)
			player.wants_turbo = true
		return
	if best_open >= tuning.ai_qb_open_distance or pressured or out_of_time:
		pc.throw_ball(best)


func _run_route() -> void:
	if route_index < route.size():
		var target: Vector3 = route[route_index]
		if _flat_distance(player.position, target) < 0.9:
			route_index += 1
		player.move_input = _direction_to(target)
		return
	if route_exit_dir == Vector3.ZERO:
		return
	# Route finished: keep going the same way until the field runs out.
	var ahead: Vector3 = player.position + route_exit_dir * 3.0
	var inside_z: bool = absf(ahead.z) < tuning.half_width() - 1.0
	var inside_x: bool = ahead.x > -tuning.end_zone_depth + 1.5 and ahead.x < tuning.field_length + tuning.end_zone_depth - 1.5
	if inside_z and inside_x:
		player.move_input = route_exit_dir


func _carry(pc: PlayController) -> void:
	var forward: Vector3 = Vector3(float(player.team.attack_dir), 0.0, 0.0)
	var steer: Vector3 = forward
	var nearest: float = INF
	var nearest_side: float = 0.0
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		var to: Vector3 = opponent.position - player.position
		var dist: float = to.length()
		if dist < nearest:
			nearest = dist
			nearest_side = signf(to.z)
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

	if nearest < 2.6 and _decision_timer <= 0.0:
		_decision_timer = 0.5
		if randf() < tuning.ai_juke_chance:
			var lateral: float = -nearest_side if nearest_side != 0.0 else 1.0
			pc.do_juke(player, Vector3(0.0, 0.0, lateral))


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
	# Trail the receiver's position from a moment ago, shaded to the deep side.
	var aim: Vector3 = man_target.position - man_target.velocity * tuning.ai_cover_lag
	aim.x += pc.off_dir * tuning.ai_cover_cushion
	player.ai_speed_scale = tuning.ai_cover_speed_scale
	_seek(aim)


func _cover_zone(pc: PlayController) -> void:
	var aim: Vector3 = zone_center
	var closest: float = zone_radius
	for receiver: Player in pc.eligible:
		var dist: float = _flat_distance(receiver.position, zone_center)
		if dist < closest:
			closest = dist
			aim = zone_center.lerp(receiver.position, 0.75)
			aim.x += pc.off_dir * tuning.ai_cover_cushion
	player.ai_speed_scale = tuning.ai_cover_speed_scale
	_seek(aim)


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
			_run_route()
		return

	if pc.live_time - pc.throw_time < tuning.ai_ball_react_time:
		_defense_pocket(pc)
		return
	_seek(landing)
	player.wants_turbo = _flat_distance(player.position, landing) < tuning.ai_ball_react_radius


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
