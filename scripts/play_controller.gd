class_name PlayController
extends Node
## Runs a single play: lineup, snap, handoff, passes, catches, blocks, tackles
## and the whistle. Owns the GameState machine, which decides when simulate()
## and simulate_dead() are called.

## POCKET: QB holds the ball behind the line. AIR: pass in flight.
## RUN: someone is carrying the ball in the open field (any team).
enum Phase { POCKET, AIR, RUN }
enum Result { NONE, TACKLED, OUT_OF_BOUNDS, INCOMPLETE, TOUCHDOWN }

var game: Game
var tuning: Tuning
var ball: Ball
var human: HumanController

## Teams as of the snap. An interception does not change these.
var offense: Team
var defense: Team
var off_play: OffensePlay
var def_play: DefensePlay
## +1 or -1: the offense's direction along X.
var off_dir: float = 1.0
var los_x: float = 0.0

var phase: Phase = Phase.POCKET
var ball_dead: bool = true
var result: Result = Result.NONE
var dead_spot_x: float = 0.0
## Team holding the ball at the whistle.
var final_team: Team
var was_sack: bool = false
var live_time: float = 0.0
var throw_time: float = 0.0
var handoff_done: bool = false

var qb: Player
var runner: Player
## Receiver a neutral-stick pass goes to.
var highlighted: Player
var eligible: Array[Player] = []
var players: Array[Player] = []

var _pushes: PackedVector3Array = PackedVector3Array()
## Actions requested by AI brains this tick. They run after every brain has
## thought, so no brain reacts to another's decision from the same tick.
## (Running them immediately gave the team that thinks second an edge.)
var _thinking: bool = false
var _queued_actions: Array[Callable] = []

@onready var state_machine: StateMachine = $StateMachine


func setup(p_game: Game) -> void:
	game = p_game
	tuning = game.tuning
	ball = game.ball
	human = game.human
	players.clear()
	players.append_array(game.home.players)
	players.append_array(game.away.players)
	state_machine.setup(self)


func _physics_process(delta: float) -> void:
	if game != null:
		state_machine.physics_update(delta)


# --- Lineup and snap -------------------------------------------------------------

## Play-frame (x downfield from the line, y lateral) to world space.
func to_world(point: Vector2) -> Vector3:
	var limit: float = tuning.half_width() - 1.0
	return Vector3(los_x + off_dir * point.x, 0.0, clampf(off_dir * point.y, -limit, limit))


func line_up(p_off: OffensePlay, p_def: DefensePlay) -> void:
	offense = game.offense
	defense = game.defense
	off_play = p_off
	def_play = p_def
	off_dir = float(offense.attack_dir)
	los_x = game.los_x
	phase = Phase.POCKET
	ball_dead = true
	result = Result.NONE
	was_sack = false
	live_time = 0.0
	handoff_done = false
	qb = null
	runner = null
	highlighted = null
	eligible.clear()

	var face_off: Vector3 = Vector3(off_dir, 0.0, 0.0)
	for i: int in offense.players.size():
		var player: Player = offense.players[i]
		var assignment: OffenseAssignment = p_off.assignments[mini(i, p_off.assignments.size() - 1)]
		var start: Vector3 = to_world(assignment.start)
		var world_route: PackedVector3Array = PackedVector3Array()
		for waypoint: Vector2 in assignment.route:
			world_route.append(to_world(assignment.start + waypoint))
		player.reset_for_play(start, face_off)
		player.set_label(assignment.label)
		player.brain.assign_offense(assignment, start, world_route)
		match assignment.job:
			OffenseAssignment.Job.QB:
				player.speed_scale = tuning.qb_speed_scale
				if qb == null:
					qb = player
			OffenseAssignment.Job.BLOCK:
				player.speed_scale = tuning.line_speed_scale
			OffenseAssignment.Job.RUNNER:
				if runner == null:
					runner = player
	if qb == null:
		qb = offense.players[0]

	# Receivers first (in play order), then blockers from widest to tightest:
	# this is the order man-coverage indices refer to.
	var blockers: Array[Player] = []
	for player: Player in offense.players:
		if player == qb:
			continue
		if player.brain.off_assign.job == OffenseAssignment.Job.BLOCK:
			blockers.append(player)
		else:
			eligible.append(player)
	blockers.sort_custom(func(a: Player, b: Player) -> bool: return absf(a.position.z) > absf(b.position.z))
	var cover_order: Array[Player] = []
	cover_order.append_array(eligible)
	cover_order.append_array(blockers)
	if not eligible.is_empty():
		highlighted = eligible[0]

	for i: int in defense.players.size():
		var player: Player = defense.players[i]
		var assignment: DefenseAssignment = p_def.assignments[mini(i, p_def.assignments.size() - 1)]
		var start: Vector3 = to_world(assignment.start)
		var target: Player = null
		if assignment.job == DefenseAssignment.Job.MAN and not cover_order.is_empty():
			target = cover_order[mini(assignment.man_target, cover_order.size() - 1)]
			start.z = target.position.z
		player.reset_for_play(start, -face_off)
		player.set_label(assignment.label)
		if assignment.job == DefenseAssignment.Job.RUSH:
			player.speed_scale = tuning.line_speed_scale
		player.brain.assign_defense(assignment, start, target, to_world(assignment.zone_center))

	ball.place_on_ground(Vector3(los_x, 0.0, 0.0))
	game.field.set_markers(los_x, game.first_down_x, not game.goal_to_go)
	human.on_line_up()
	_update_markers()


func snap() -> void:
	ball_dead = false
	live_time = 0.0
	phase = Phase.POCKET
	for player: Player in players:
		player.frozen = false
	ball.give_to(qb)
	game.add_stat(&"snaps")
	_update_markers()


# --- Simulation ------------------------------------------------------------------

## One tick of live play.
func simulate(delta: float) -> void:
	live_time += delta
	game.tick_clock(delta)
	_try_handoff()
	human.update_live()
	_think_and_move(delta)
	_resolve_contacts(delta)
	var arrived: bool = ball.integrate(delta)
	if not ball_dead:
		if arrived:
			_resolve_pass_arrival()
		_check_carrier()
	_update_markers()


## One tick after the whistle: everyone can still move and hit.
func simulate_dead(delta: float) -> void:
	human.update_dead()
	_think_and_move(delta)
	_resolve_contacts(delta)
	ball.integrate(delta)


func _think_and_move(delta: float) -> void:
	_thinking = true
	for player: Player in players:
		if player == human.controlled and not human.assist:
			continue
		player.brain.think(self, delta)
	_thinking = false
	for action: Callable in _queued_actions:
		action.call()
	_queued_actions.clear()
	for player: Player in players:
		player.integrate(delta)


func _try_handoff() -> void:
	if not off_play.is_run or handoff_done or runner == null or live_time < off_play.handoff_delay:
		return
	handoff_done = true
	if ball.carrier != qb or qb.is_down() or runner.is_down():
		return
	ball.give_to(runner)
	phase = Phase.RUN
	game.add_stat(&"handoffs")
	human.on_carrier_changed(runner)


func _check_carrier() -> void:
	var carrier: Player = ball.carrier
	if carrier == null:
		return
	var dir: int = carrier.team.attack_dir
	var x: float = carrier.position.x
	if (dir > 0 and x >= tuning.field_length) or (dir < 0 and x <= 0.0):
		game.add_stat(&"touchdowns")
		end_play(Result.TOUCHDOWN, x)
		return
	if absf(carrier.position.z) > tuning.half_width():
		end_play(Result.OUT_OF_BOUNDS, x)
		return
	if phase == Phase.POCKET and (x - los_x) * off_dir > 0.0:
		# QB crossed the line: no more passing, everyone reacts to a runner.
		phase = Phase.RUN


func end_play(p_result: Result, spot_x: float) -> void:
	if ball_dead:
		return
	ball_dead = true
	result = p_result
	dead_spot_x = spot_x
	final_team = ball.carrier.team if ball.carrier != null else offense
	_update_markers()


func result_text() -> String:
	match result:
		Result.TACKLED:
			return "SACKED!" if was_sack else "TACKLED!"
		Result.OUT_OF_BOUNDS:
			return "OUT OF BOUNDS"
		Result.INCOMPLETE:
			return "INCOMPLETE"
		Result.TOUCHDOWN:
			return "TOUCHDOWN!"
	return ""


# --- Passing ---------------------------------------------------------------------

func can_pass() -> bool:
	return not ball_dead and phase == Phase.POCKET and ball.carrier == qb and not off_play.is_run and qb.can_act()


func cycle_highlight() -> void:
	if eligible.is_empty():
		return
	highlighted = eligible[(eligible.find(highlighted) + 1) % eligible.size()]
	_update_markers()


func throw_ball(target: Player) -> void:
	if _thinking:
		_queued_actions.append(throw_ball.bind(target))
		return
	if target == null or not can_pass():
		return
	# Lead the receiver: aim where he will be when the ball gets there.
	var lead: float = Ball.intercept_time(qb.position, target.position, target.velocity, tuning.pass_speed)
	lead = minf(lead, tuning.pass_max_lead_time)
	var point: Vector3 = target.position + target.velocity * lead
	var limit_z: float = tuning.half_width() - 0.5
	var back: float = tuning.end_zone_depth - 1.0
	point.x = clampf(point.x, -back, tuning.field_length + back)
	point.z = clampf(point.z, -limit_z, limit_z)
	ball.throw_to(qb, target, point, tuning)
	phase = Phase.AIR
	throw_time = live_time
	game.add_stat(&"passes")
	human.on_throw(target)


func _resolve_pass_arrival() -> void:
	var point: Vector3 = ball.target_point
	var receiver: Player = _nearest_within(offense.players, point, tuning.catch_radius, ball.thrower)
	var defender: Player = _nearest_within(defense.players, point, tuning.defender_catch_radius, null)

	if receiver != null:
		# Every defender crowding the receiver makes the catch harder.
		var chance: float = tuning.catch_base_chance
		for opponent: Player in defense.players:
			if opponent.is_down():
				continue
			var dist: float = _flat_distance(opponent.position, receiver.position)
			if dist < tuning.cover_radius:
				chance -= (1.0 - dist / tuning.cover_radius) * tuning.cover_penalty
		chance = clampf(chance, tuning.catch_min_chance, 1.0)
		if randf() < chance:
			ball.give_to(receiver)
			phase = Phase.RUN
			game.add_stat(&"completions")
			human.on_carrier_changed(receiver)
			return
		if defender != null and randf() < tuning.interception_chance:
			_intercept(defender)
			return
	elif defender != null and randf() < tuning.interception_chance_open:
		_intercept(defender)
		return

	ball.drop()
	game.add_stat(&"incompletions")
	end_play(Result.INCOMPLETE, los_x)


func _intercept(defender: Player) -> void:
	ball.give_to(defender)
	phase = Phase.RUN
	game.add_stat(&"interceptions")
	human.on_carrier_changed(defender)


# --- Actions ---------------------------------------------------------------------

func do_dive(player: Player, dir: Vector3) -> void:
	if _thinking:
		_queued_actions.append(do_dive.bind(player, dir))
		return
	player.start_dive(dir)


func do_juke(player: Player, lateral: Vector3) -> void:
	if _thinking:
		_queued_actions.append(do_juke.bind(player, lateral))
		return
	player.start_juke(lateral, Vector3(float(player.team.attack_dir), 0.0, 0.0))


## A shove hits instantly: everyone in a cone in front goes down.
func do_shove(player: Player, dir: Vector3) -> void:
	if _thinking:
		_queued_actions.append(do_shove.bind(player, dir))
		return
	if not player.can_act():
		return
	player.start_shove(dir)
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		var to: Vector3 = opponent.position - player.position
		to.y = 0.0
		var dist: float = to.length()
		if dist > tuning.shove_radius:
			continue
		if dist > 0.01 and (to / dist).dot(dir) < tuning.shove_arc_dot:
			continue
		if not ball_dead and opponent == ball.carrier:
			player.tackle_cooldown = 0.0
			_attempt_tackle(player, opponent, true)
		else:
			_knock_over(player, opponent, dir)


# --- Contacts --------------------------------------------------------------------

func _resolve_contacts(delta: float) -> void:
	var min_dist: float = tuning.player_radius * 2.0
	var reach: float = maxf(maxf(tuning.dive_tackle_radius, tuning.tackle_radius), min_dist)
	# Pushes are summed from one snapshot of positions and applied afterwards, so
	# the result does not depend on the order players are listed in. (Applying
	# them pair by pair measurably favoured whichever team came first.)
	_pushes.resize(players.size())
	_pushes.fill(Vector3.ZERO)
	for i: int in players.size():
		var a: Player = players[i]
		for j: int in range(i + 1, players.size()):
			var b: Player = players[j]
			var offset: Vector3 = b.position - a.position
			offset.y = 0.0
			var dist: float = offset.length()
			if dist > reach:
				continue
			var enemies: bool = a.team != b.team
			if enemies:
				_check_hit(a, b, offset, dist)
				_check_hit(b, a, -offset, dist)
			if a.is_down() or b.is_down() or a.state == Player.State.DIVING or b.state == Player.State.DIVING:
				continue
			# Opponents only body up when one of them is blocking. Otherwise a
			# man defender would wall off his receiver just by standing there.
			if enemies and not a.is_blocking and not b.is_blocking:
				continue
			if dist < min_dist and dist > 0.001:
				# Bodies cannot overlap: push both apart equally.
				var push: Vector3 = offset / dist * (min_dist - dist) * 0.5
				_pushes[i] -= push
				_pushes[j] += push
				if enemies:
					_check_block(a, b, offset / dist, delta)
					_check_block(b, a, -offset / dist, delta)
	for i: int in players.size():
		players[i].position += _pushes[i]


func _check_hit(attacker: Player, victim: Player, offset: Vector3, dist: float) -> void:
	if attacker.is_down() or victim.is_down():
		return
	var is_carrier: bool = not ball_dead and victim == ball.carrier
	if attacker.state == Player.State.DIVING:
		if dist > tuning.dive_tackle_radius:
			return
		if is_carrier:
			_attempt_tackle(attacker, victim, true)
		elif ball_dead or attacker == human.controlled:
			# Bystanders only get flattened by the person's dives and by late
			# hits. CPU dives during the play go for the ball carrier alone.
			_knock_over(attacker, victim, offset.normalized() if dist > 0.01 else attacker.facing)
	elif is_carrier and attacker.state == Player.State.NORMAL and dist <= tuning.tackle_radius:
		_attempt_tackle(attacker, victim, false)


func _attempt_tackle(tackler: Player, carrier: Player, big_hit: bool) -> void:
	if tackler.tackle_cooldown > 0.0:
		return
	tackler.tackle_cooldown = tuning.tackle_retry_time
	var chance: float = tuning.tackle_base_chance
	if big_hit:
		chance += tuning.dive_tackle_bonus
	if carrier.juke_evade_timer > 0.0:
		chance *= tuning.juke_tackle_scale
	var dir: Vector3 = carrier.position - tackler.position
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else tackler.facing

	if randf() < chance:
		was_sack = phase == Phase.POCKET and carrier == qb
		carrier.knock_down(dir * tuning.tackle_knockdown_impulse, tuning.knockdown_time)
		game.add_stat(&"tackles")
		game.impact(tuning.tackle_shake, 1.0)
		end_play(Result.TACKLED, carrier.position.x)
	else:
		# Broken tackle: the defender bounces off and eats turf.
		tackler.knock_down(-dir * 3.0, tuning.broken_tackle_stun)
		game.add_stat(&"broken_tackles")
		game.impact(tuning.shove_shake * 0.6, 0.4)


func _knock_over(attacker: Player, victim: Player, dir: Vector3) -> void:
	victim.knock_down(dir * tuning.shove_knockdown_impulse, tuning.knockdown_time)
	game.add_stat(&"knockdowns")
	# Full shake and hit-stop only when the person's player is involved;
	# CPU-on-CPU scuffles just rattle the camera a little.
	if attacker == human.controlled or victim == human.controlled:
		game.impact(tuning.shove_shake, 0.5)
	else:
		game.impact(tuning.shove_shake * 0.3, 0.0)


## A blocker in contact with an opponent slows him down until he sheds the block.
func _check_block(blocker: Player, rusher: Player, push_dir: Vector3, delta: float) -> void:
	if not blocker.is_blocking or rusher.is_blocking or rusher.has_ball:
		return
	if rusher.block_immune_timer > 0.0 or blocker.state != Player.State.NORMAL:
		return
	if rusher.block_engaged_time <= 0.0:
		rusher.block_shed_time = randf_range(tuning.block_shed_time_min, tuning.block_shed_time_max)
	rusher.block_engaged_time += delta
	rusher.block_slow_timer = 0.12
	if rusher.block_engaged_time >= rusher.block_shed_time:
		blocker.knock_down(-push_dir * 4.0, tuning.block_beaten_time)
		rusher.block_immune_timer = tuning.block_immune_time
		rusher.block_slow_timer = 0.0
		rusher.block_engaged_time = 0.0


# --- Queries ---------------------------------------------------------------------

func nearest_opponent_distance(player: Player) -> float:
	var best: float = INF
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		best = minf(best, _flat_distance(opponent.position, player.position))
	return best


func _nearest_within(candidates: Array[Player], point: Vector3, radius: float, exclude: Player) -> Player:
	var best: Player = null
	var best_dist: float = radius
	for candidate: Player in candidates:
		if candidate == exclude or candidate.is_down():
			continue
		var dist: float = _flat_distance(candidate.position, point)
		if dist <= best_dist:
			best_dist = dist
			best = candidate
	return best


func _update_markers() -> void:
	var show: bool = human.is_active() and human.controlled == qb and qb != null and not off_play.is_run
	show = show and (ball_dead and result == Result.NONE or can_pass())
	for player: Player in players:
		player.set_targeted(show and player == highlighted)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
