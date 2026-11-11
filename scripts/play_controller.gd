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
## The last change of possession in this play was a recovered fumble.
var was_fumble: bool = false
## The carrier ended the play himself by diving.
var was_dive: bool = false
var live_time: float = 0.0
var throw_time: float = 0.0
var handoff_done: bool = false
var handoff_time: float = 0.0

var qb: Player
var runner: Player
## Receivers in play order: the person throws to them with pass_1, pass_2, pass_3.
var eligible: Array[Player] = []
var players: Array[Player] = []

## Defenders going for the pass in the air. Chosen at the throw.
var ball_breakers: Array[Player] = []
## Who each team has thrown to lately, newest last. Lasts the whole game.
var _recent_targets: Dictionary[Team, Array] = {}
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
	for player: Player in players:
		player.play = self
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
	was_fumble = false
	was_dive = false
	live_time = 0.0
	handoff_done = false
	qb = null
	runner = null
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
		player.brain.assign_offense(assignment, start, world_route)
		match assignment.job:
			OffenseAssignment.Job.QB:
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

	for i: int in defense.players.size():
		var player: Player = defense.players[i]
		var assignment: DefenseAssignment = p_def.assignments[mini(i, p_def.assignments.size() - 1)]
		var start: Vector3 = to_world(assignment.start)
		var target: Player = null
		if assignment.job == DefenseAssignment.Job.MAN and not cover_order.is_empty():
			target = cover_order[mini(assignment.man_target, cover_order.size() - 1)]
			start.z = target.position.z
		player.reset_for_play(start, -face_off)
		# Rushers with a hand in the dirt are linemen; a blitzer from further back
		# comes at full speed.
		if assignment.job == DefenseAssignment.Job.RUSH and assignment.start.x <= tuning.line_depth:
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
	_update_drag()
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
	_aim_quarterback()
	for player: Player in players:
		player.integrate(delta)
	game.field.fx.track(players)


## The quarterback looks downfield while he holds the ball in the pocket, even
## when dropping back, and at his target while the pass is in the air.
func _aim_quarterback() -> void:
	if qb == null:
		return
	qb.look_dir = Vector3.ZERO
	if ball_dead:
		return
	if phase == Phase.POCKET and ball.carrier == qb:
		# Tucked and running, he faces the way he runs like any other carrier.
		if not qb.is_tucked():
			qb.look_dir = Vector3(off_dir, 0.0, 0.0)
	elif phase == Phase.AIR and ball.thrower == qb:
		var to_target: Vector3 = ball.target_point - qb.position
		to_target.y = 0.0
		qb.look_dir = to_target


func _try_handoff() -> void:
	if not off_play.is_run or handoff_done or runner == null or live_time < off_play.handoff_delay:
		return
	handoff_done = true
	if ball.carrier != qb or qb.is_down() or runner.is_down() or qb.state == Player.State.DRAGGING:
		return
	ball.give_to(runner)
	phase = Phase.RUN
	handoff_time = live_time
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
	if carrier.is_down():
		# Only his own dive leaves a carrier on the turf with the ball still live.
		was_dive = true
		was_sack = false
		game.add_stat(&"carrier_dives")
		end_play(Result.TACKLED, x)
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
	var gain: float = (spot_x - los_x) * off_dir if final_team == offense else 0.0
	game.play_caller.record(offense, off_play, gain)
	if ball.carrier != null:
		ball.carrier.release_drag()
	_update_markers()


func result_text() -> String:
	match result:
		Result.TACKLED:
			if was_dive:
				return "DOWN!"
			return "SACKED!" if was_sack else "TACKLED!"
		Result.OUT_OF_BOUNDS:
			return "OUT OF BOUNDS"
		Result.INCOMPLETE:
			return "INCOMPLETE"
		Result.TOUCHDOWN:
			return "TOUCHDOWN!"
	return ""


# --- Passing ---------------------------------------------------------------------

## The quarterback has to let go of turbo (untuck the ball) before he can throw.
func can_pass() -> bool:
	return not ball_dead and phase == Phase.POCKET and ball.carrier == qb and not off_play.is_run and (qb.can_act() or qb.is_airborne()) and not qb.is_tucked()


## Furthest the quarterback can throw, in yards.
func pass_range() -> float:
	return PlayerRatings.blend(qb.ratings.power, tuning.pass_range_low, tuning.pass_range_high)


## Pass power for a button held `held` seconds: 0 for a tap, rising to 1 at
## pass_charge_time.
func pass_power(held: float) -> float:
	return clampf(inverse_lerp(tuning.pass_tap_time, tuning.pass_charge_time, held), 0.0, 1.0)


## `power` runs from 0 (slow, high lob) to 1 (fast, flat bullet).
func throw_ball(target: Player, power: float = 0.5) -> void:
	if _thinking:
		_queued_actions.append(throw_ball.bind(target, power))
		return
	if target == null or not can_pass():
		return
	var arm: PlayerRatings = qb.ratings
	var bullet_speed: float = tuning.pass_bullet_speed * PlayerRatings.blend(arm.power, tuning.pass_speed_scale_low, tuning.pass_speed_scale_high)
	var speed: float = lerpf(tuning.pass_lob_speed, maxf(bullet_speed, tuning.pass_lob_speed), clampf(power, 0.0, 1.0))
	if power < 0.34:
		game.add_stat(&"lobs")
	elif power > 0.66:
		game.add_stat(&"bullets")
	# Lead the receiver: aim where he will be when the ball gets there. A slower
	# pass is in the air longer, so it is thrown further ahead of him.
	var lead: float = Ball.intercept_time(qb.position, target.position, target.velocity, speed)
	lead = minf(lead, tuning.pass_max_lead_time)
	var point: Vector3 = target.position + target.velocity * lead
	# Out of his range: the ball comes up short.
	var throw: Vector3 = point - qb.position
	throw.y = 0.0
	var reach: float = pass_range()
	if throw.length() > reach:
		point = qb.position + throw.normalized() * reach
		game.add_stat(&"underthrows")
	# Every pass sprays a little, more the further it has to travel; a throw on
	# the run sprays a lot more.
	var error: float = PlayerRatings.blend(arm.accuracy, tuning.accuracy_error_low, tuning.accuracy_error_high)
	if qb.feet_set < 1.0:
		error += tuning.pass_scramble_error * PlayerRatings.blend(arm.agility, tuning.agility_scale_low, tuning.agility_scale_high) * (1.0 - qb.feet_set)
		game.add_stat(&"scramble_throws")
	if error > 0.0:
		var miss: float = _flat_distance(qb.position, point) * error
		point += Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU) * miss * sqrt(randf())
	var limit_z: float = tuning.half_width() - 0.5
	var back: float = tuning.end_zone_depth - 1.0
	point.x = clampf(point.x, -back, tuning.field_length + back)
	point.z = clampf(point.z, -limit_z, limit_z)
	ball.throw_to(qb, target, point, speed, tuning)
	_remember_target(target)
	_pick_ball_breakers()
	phase = Phase.AIR
	throw_time = live_time
	game.add_stat(&"passes")
	human.on_throw(target)


func _resolve_pass_arrival() -> void:
	var point: Vector3 = ball.target_point
	var receiver: Player = _nearest_within(offense.players, point, tuning.catch_radius, ball.thrower, true)
	var defender: Player = _nearest_within(defense.players, point, tuning.defender_catch_radius, null, true)

	if receiver != null:
		# Every defender crowding the receiver makes the catch harder.
		var chance: float = tuning.catch_base_chance
		var incoming: Vector3 = receiver.position - ball.thrower.position
		incoming.y = 0.0
		incoming = incoming.normalized()
		# 1 when he waits for the ball or comes back to it, 0 running away from it.
		var facing_ball: float = clampf(1.0 - receiver.velocity.dot(incoming) / tuning.run_speed, 0.0, 1.0)
		for opponent: Player in defense.players:
			if opponent.is_down():
				continue
			var offset: Vector3 = opponent.position - receiver.position
			offset.y = 0.0
			var dist: float = offset.length()
			if dist < tuning.cover_radius:
				var penalty: float = (1.0 - dist / tuning.cover_radius) * tuning.cover_penalty
				# A defender on the far side of the receiver has to play through him.
				var behind: float = maxf(offset.normalized().dot(incoming), 0.0) if dist > 0.01 else 0.0
				penalty *= 1.0 - tuning.cover_shield * behind * facing_ball
				chance -= penalty
		# So does one who went up for the ball.
		for opponent: Player in defense.players:
			if opponent.is_airborne() and _flat_distance(opponent.position, point) <= tuning.defender_catch_radius * tuning.jump_catch_radius_scale:
				chance -= tuning.contest_penalty
		chance *= _catch_scale(receiver)
		chance = clampf(chance, tuning.catch_min_chance, 1.0)
		if randf() < chance:
			ball.give_to(receiver)
			receiver.jolt(receiver.position - ball.thrower.position, 0.5)
			phase = Phase.RUN
			game.add_stat(&"completions")
			human.on_carrier_changed(receiver)
			return
		if defender != null and randf() < tuning.interception_chance * _catch_scale(defender):
			_intercept(defender)
			return
	elif defender != null and randf() < tuning.interception_chance_open * _catch_scale(defender):
		_intercept(defender)
		return

	ball.drop()
	game.add_stat(&"incompletions")
	end_play(Result.INCOMPLETE, los_x)


func _catch_scale(player: Player) -> float:
	return PlayerRatings.blend(player.ratings.catching, tuning.catch_scale_low, tuning.catch_scale_high)


func _intercept(defender: Player) -> void:
	was_fumble = false
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


func do_jump(player: Player) -> void:
	if _thinking:
		_queued_actions.append(do_jump.bind(player))
		return
	player.start_jump()


## `side` is +1 for the player's own left, -1 for his right.
func do_spin(player: Player, side: float) -> void:
	if _thinking:
		_queued_actions.append(do_spin.bind(player, side))
		return
	player.start_spin(side)


func do_stiff_arm(player: Player, side: float) -> void:
	if _thinking:
		_queued_actions.append(do_stiff_arm.bind(player, side))
		return
	player.start_stiff_arm(side)


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
			# A carrier in the air hurdles the dive, if he times it well enough.
			if victim.is_airborne() and attacker.tackle_cooldown <= 0.0:
				var clear: float = PlayerRatings.blend(victim.ratings.juke, tuning.hurdle_chance_low, tuning.hurdle_chance_high)
				if randf() < clear:
					attacker.tackle_cooldown = tuning.tackle_retry_time
					game.add_stat(&"hurdles")
					return
			_attempt_tackle(attacker, victim, true)
		elif attacker.has_ball:
			# A carrier's dive is for yards: it knocks nobody over.
			pass
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
	var dir: Vector3 = carrier.position - tackler.position
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else tackler.facing
	var kind: PlayerFall.Kind = PlayerFall.Kind.WRAP
	if tackler.state == Player.State.DIVING:
		kind = PlayerFall.Kind.LOW
	elif big_hit:
		kind = PlayerFall.Kind.HIGH

	# Already dragging one tackler: a second one finishes it.
	if carrier.state == Player.State.DRAGGING:
		_finish_tackle(carrier, dir, kind)
		return

	var skills: PlayerRatings = carrier.ratings
	var chance: float = tuning.tackle_base_chance
	if big_hit:
		chance += tuning.dive_tackle_bonus
	chance *= PlayerRatings.blend(skills.strength, tuning.strength_tackle_scale_low, tuning.strength_tackle_scale_high)
	chance *= PlayerRatings.blend(tackler.ratings.tackling, tuning.tackling_scale_low, tuning.tackling_scale_high)
	if tackler.block_slow_timer > 0.0:
		chance *= tuning.blocked_tackle_scale
	var spinning: bool = carrier.spin_evade_timer > 0.0
	if spinning:
		chance *= PlayerRatings.blend(skills.juke, tuning.spin_tackle_scale_low, tuning.spin_tackle_scale_high)
	# A stiff arm only helps against a tackler on the side the arm is out.
	var stiff_armed: bool = carrier.stiff_arm_covers(tackler)
	if stiff_armed:
		chance *= PlayerRatings.blend(skills.strength, tuning.stiff_arm_tackle_scale_low, tuning.stiff_arm_tackle_scale_high)

	if randf() >= chance:
		if stiff_armed:
			game.add_stat(&"stiff_arms")
		elif spinning:
			game.add_stat(&"spins")
		_break_tackle(tackler, carrier, dir)
		return
	# Wrapped up. A strong carrier stays on his feet and drags the tackler along.
	var drag_time: float = PlayerRatings.blend(skills.strength, tuning.drag_time_low, tuning.drag_time_high)
	if big_hit:
		drag_time *= tuning.drag_big_hit_scale
	var can_drag: bool = carrier.state == Player.State.NORMAL and tackler.state == Player.State.NORMAL
	if can_drag and drag_time >= tuning.drag_min_time:
		carrier.start_drag(tackler, drag_time)
		carrier.jolt(dir, 0.8)
		game.add_stat(&"drags")
		game.impact(tuning.shove_shake * 0.6, 0.4)
	else:
		_finish_tackle(carrier, dir, kind)


## The carrier goes down and the play is over.
func _finish_tackle(carrier: Player, dir: Vector3, kind: PlayerFall.Kind) -> void:
	carrier.knock_down(dir * tuning.tackle_knockdown_impulse, tuning.knockdown_time, kind)
	game.add_stat(&"tackles")
	game.impact(tuning.tackle_shake, 1.0)
	game.field.fx.blood_burst(carrier.position, dir, tuning.blood_drops_tackle, true)
	if _try_fumble(carrier, kind != PlayerFall.Kind.WRAP):
		return
	was_sack = phase == Phase.POCKET and carrier == qb
	end_play(Result.TACKLED, carrier.position.x)


## The hit may knock the ball out. Whoever is on his feet nearby picks it up and
## the play goes on: a teammate keeps the drive alive, a defender runs it back.
func _try_fumble(carrier: Player, big_hit: bool) -> bool:
	var chance: float = PlayerRatings.blend(carrier.ratings.security, tuning.fumble_chance_low, tuning.fumble_chance_high)
	if big_hit:
		chance *= tuning.fumble_big_hit_scale
	if randf() >= chance:
		return false
	var nearby: Array[Player] = []
	for candidate: Player in players:
		if candidate == carrier or not candidate.can_act():
			continue
		if _flat_distance(candidate.position, carrier.position) <= tuning.fumble_recover_radius:
			nearby.append(candidate)
	if nearby.is_empty():
		return false
	var recoverer: Player = nearby.pick_random()
	ball.give_to(recoverer)
	recoverer.jolt(recoverer.position - carrier.position, 0.5)
	phase = Phase.RUN
	game.add_stat(&"fumbles")
	if recoverer.team != carrier.team:
		was_fumble = true
		game.add_stat(&"fumbles_lost")
	human.on_carrier_changed(recoverer)
	return true


## Broken tackle: the defender bounces off and eats turf.
func _break_tackle(tackler: Player, carrier: Player, dir: Vector3) -> void:
	tackler.knock_down(-dir * 3.0, tuning.broken_tackle_stun, PlayerFall.Kind.BOUNCE_OFF)
	carrier.jolt(dir, 0.8)
	game.add_stat(&"broken_tackles")
	game.impact(tuning.shove_shake * 0.6, 0.4)
	@warning_ignore("integer_division")
	game.field.fx.blood_burst(tackler.position, -dir, tuning.blood_drops_knockdown / 2, false)


## A drag ends when its time is up: the carrier either shakes the tackler off
## and keeps running, or finally goes down.
func _update_drag() -> void:
	var carrier: Player = ball.carrier
	if ball_dead or carrier == null or carrier.state != Player.State.DRAGGING or carrier.state_timer > 0.0:
		return
	var tackler: Player = carrier.drag_partner
	var dir: Vector3 = carrier.facing
	var escape: float = PlayerRatings.blend(carrier.ratings.strength, tuning.shake_off_chance_low, tuning.shake_off_chance_high)
	if tackler != null and randf() < escape:
		game.add_stat(&"shake_offs")
		_break_tackle(tackler, carrier, dir)
	else:
		_finish_tackle(carrier, dir, PlayerFall.Kind.WRAP)


func _knock_over(attacker: Player, victim: Player, dir: Vector3) -> void:
	var kind: PlayerFall.Kind = PlayerFall.Kind.LOW if attacker.state == Player.State.DIVING else PlayerFall.Kind.HIGH
	victim.knock_down(dir * tuning.shove_knockdown_impulse, tuning.knockdown_time, kind)
	attacker.jolt(-dir, 0.5)
	game.add_stat(&"knockdowns")
	game.field.fx.blood_burst(victim.position, dir, tuning.blood_drops_knockdown, false)
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
		# A good blocker holds on longer; a strong rusher gets through sooner.
		rusher.block_shed_time = randf_range(tuning.block_shed_time_min, tuning.block_shed_time_max)
		rusher.block_shed_time *= PlayerRatings.blend(blocker.ratings.blocking, tuning.blocking_shed_scale_low, tuning.blocking_shed_scale_high)
		rusher.block_shed_time *= PlayerRatings.blend(rusher.ratings.strength, tuning.strength_shed_scale_low, tuning.strength_shed_scale_high)
		# On a run play the blocker sometimes wins outright and opens a hole.
		rusher.block_pancake_time = -1.0
		if off_play.is_run:
			var pancake: float = tuning.block_pancake_chance
			pancake *= PlayerRatings.blend(blocker.ratings.blocking, tuning.pancake_blocking_scale_low, tuning.pancake_blocking_scale_high)
			pancake *= PlayerRatings.blend(rusher.ratings.strength, tuning.pancake_strength_scale_low, tuning.pancake_strength_scale_high)
			if randf() < pancake:
				rusher.block_pancake_time = randf_range(tuning.block_pancake_time_min, tuning.block_pancake_time_max)
	rusher.block_engaged_time += delta
	rusher.block_slow_timer = 0.12
	if rusher.block_pancake_time >= 0.0 and rusher.block_engaged_time >= rusher.block_pancake_time:
		rusher.knock_down(push_dir * 4.0, tuning.block_pancake_down_time, PlayerFall.Kind.PANCAKE)
		rusher.block_slow_timer = 0.0
		rusher.block_engaged_time = 0.0
		rusher.block_pancake_time = -1.0
		game.add_stat(&"pancakes")
		return
	if rusher.block_engaged_time >= rusher.block_shed_time:
		blocker.knock_down(-push_dir * 4.0, tuning.block_beaten_time, PlayerFall.Kind.PANCAKE)
		rusher.block_immune_timer = tuning.block_immune_time
		rusher.block_slow_timer = 0.0
		rusher.block_engaged_time = 0.0


# --- Queries ---------------------------------------------------------------------

## The receiver the offense keeps throwing to, or null if it spreads the ball.
func hot_receiver() -> Player:
	var recent: Array = _recent_targets.get(offense, [])
	for candidate: Player in eligible:
		if recent.count(candidate) >= tuning.ai_hot_targets:
			return candidate
	return null


## The closest defenders who can get to the landing spot go for the ball.
func _pick_ball_breakers() -> void:
	ball_breakers.clear()
	var point: Vector3 = ball.target_point
	var candidates: Array[Player] = []
	for defender: Player in defense.players:
		if defender.is_down():
			continue
		var dist: float = _flat_distance(defender.position, point)
		var reach: float = defender.max_speed() * tuning.turbo_speed_multiplier * ball.flight_time + tuning.ai_ball_break_margin
		if dist <= tuning.ai_ball_break_radius and dist <= reach:
			candidates.append(defender)
	candidates.sort_custom(func(a: Player, b: Player) -> bool: return _flat_distance(a.position, point) < _flat_distance(b.position, point))
	for i: int in mini(candidates.size(), tuning.ai_ball_breakers):
		ball_breakers.append(candidates[i])


func _remember_target(target: Player) -> void:
	var recent: Array = _recent_targets.get(offense, [])
	recent.append(target)
	while recent.size() > tuning.ai_hot_memory:
		recent.pop_front()
	_recent_targets[offense] = recent


func nearest_opponent_distance(player: Player) -> float:
	var best: float = INF
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		best = minf(best, _flat_distance(opponent.position, player.position))
	return best


## With `jump_helps`, a player in the air reaches further (used for catches).
func _nearest_within(candidates: Array[Player], point: Vector3, radius: float, exclude: Player, jump_helps: bool = false) -> Player:
	var best: Player = null
	var best_dist: float = radius
	for candidate: Player in candidates:
		if candidate == exclude or candidate.is_down():
			continue
		var dist: float = _flat_distance(candidate.position, point)
		if jump_helps and candidate.is_airborne():
			dist /= tuning.jump_catch_radius_scale
		if dist <= best_dist:
			best_dist = dist
			best = candidate
	return best


func _update_markers() -> void:
	var show: bool = human.is_active() and human.controlled == qb and qb != null and not off_play.is_run
	show = show and (ball_dead and result == Result.NONE or can_pass())
	for player: Player in players:
		var slot: int = eligible.find(player) if show else -1
		if slot >= 0 and slot < HumanController.PASS_ACTIONS.size():
			player.set_pass_icon(human.pass_label(slot), human.pass_color(slot))
		else:
			player.set_pass_icon("", Color.WHITE)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
