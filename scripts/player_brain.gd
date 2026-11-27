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
## How far the wall slides across towards the side the kick comes down on
## (0 = stays in the middle, 1 = centred on the landing spot).
const KICKOFF_WALL_SHIFT: float = 0.7
## A route has cut once its heading is further than this (as a dot product, about
## 25 degrees) from the leg the receiver is on.
const ROUTE_CUT_DOT: float = 0.9
## Yards short of a cut in his route at which a receiver starts to sell it.
const ROUTE_JUKE_LEAD: float = 2.2

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
## A rusher's peel: the back nobody covers, whom he leaves the rush for when the
## man comes out (see PlayController._assign_peel). `peel_side` of -1 or +1
## (world z) has him do it only for a man who comes out to that side.
var peel_target: Player
var peel_side: float = 0.0
var _peeling: bool = false
## Counted once a play: he was the last man in front of the carrier, he had the
## contain on him.
var _last_man_noted: bool = false
var _contain_noted: bool = false
var zone_center: Vector3 = Vector3.ZERO
var zone_radius: float = 0.0

## Set by PlayController at the line-up: until this long after the snap this
## coverage defender has lost the plot. 0 = he has not.
var blown_time: float = 0.0
## Set by PlayController at the line-up of a play-action play: until this long
## after the snap this coverage defender plays the faked run. 0 = he does not.
var bite_time: float = 0.0
## He has bitten on a pump fake (see bite_on_pump): from when until when
## (live_time), and where he thought the ball was going.
var pump_bite_from: float = 0.0
var pump_bite_time: float = 0.0
var pump_bite_spot: Vector3 = Vector3.ZERO
## A quarterback wrapped up in the pocket has decided whether to try to throw,
## and a defender by the passer whether to jump at the ball as it comes out.
var _grasp_decided: bool = false
var _line_jump_decided: bool = false
## Set by PlayController at the line-up: this long after the snap this coverage
## defender dives at his receiver to put him on the ground (negative = he does
## not). `takeout_target` is the man he has gone for, until the dive lands.
var takeout_time: float = -1.0
var takeout_target: Player
## How a man defender plays his man this play. Set by PlayController at the
## line-up (see _roll_technique): tight on his deep side, off him with a
## cushion that closes as he comes, or trailing on the quarterback's side.
enum Technique { TIGHT, OFF, TRAIL }
var technique: Technique = Technique.TIGHT
## Yards he shades to one side of his man (along z), rolled with it.
var leverage: float = 0.0
## Playing off: the cushion he is holding right now.
var _cushion: float = 0.0
## Decided once per pass: whether this defender tries to get in front of the
## receiver, and whether he has thought about diving at him instead.
var _undercut_decided: bool = false
var _undercut: bool = false
var _air_hit_decided: bool = false
## He dived at the receiver and not at the ball: that dive catches nothing.
var hit_man: bool = false

var _decision_timer: float = 0.0
## The sharper quarterback rolls once per play for getting away from a rusher,
## and once for running through an open lane.
var _escape_rolled: bool = false
var _bail_rolled: bool = false
## Seconds until he looks at the empty side again, and until a carrier next
## thinks about jumping a dive.
var _lane_timer: float = 0.0
var _hurdle_timer: float = 0.0
# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
### What he went up meaning to jump dive at: a man (`_leap_target`), the pass
### coming down, or straight ahead for the line.
#enum Leap { NONE, MAN, BALL, AHEAD }
#var _leap: Leap = Leap.NONE
#var _leap_target: Player
### He has made up his mind, once this play, about a jump dive at the carrier or
### for the line; and once this pass about one at the ball.
#var _leap_decided: bool = false
#var _ball_leap_decided: bool = false
## He is out of the pocket to get away from a rusher, still looking to throw.
var _escaping: bool = false
## Why the CPU quarterback took off, for the tests: keeper, escape, lane or
## bail (out of time with nobody open). Empty while he has not.
var run_kind: StringName = &""
## A carrier's next move against a tackler: how long before contact he starts
## it (negative = not rolled yet) and how long he then still hesitates.
var _move_lead: float = -1.0
var _move_late: float = 0.0
## Securing the ball is decided once per tackler: who it was decided for,
## whether he does, and whether it is to run that tackler over.
var _secure_target: Player
var _secure_on: bool = false
var _secure_power: bool = false
## The chaser the carrier last thought of pulling away from, and what he chose.
var _chase_target: Player
var _chase_on: bool = false
## The tackler he last decided about pitching the ball away from, and whether
## he has decided about it for the tackler hanging on him now.
var _lateral_tackler: Player
var _grasp_lateral_decided: bool = false
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
## How many of the celebration's pile-ons (PlayController.pile_count) he has
## dived into.
var _piles_answered: int = 0
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
## The point of his route whose cut this receiver has already juked at.
var _juke_index: int = -1
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
	# With a tackler on his back a carrier gets both arms round the ball if he
	# still can. (He does no other thinking then: see can_act below.)
	if player.state == Player.State.DRAGGING:
		if not _throws_from_grasp(pc) and not _laterals_from_grasp(pc):
			pc.do_secure(player)
	else:
		_grasp_lateral_decided = false
	player.is_blocking = false
	player.calling_for_ball = false
	player.ai_speed_scale = 1.0
	_delta = delta
	_decision_timer = maxf(_decision_timer - delta, 0.0)
	_lane_timer = maxf(_lane_timer - delta, 0.0)
	_hurdle_timer = maxf(_hurdle_timer - delta, 0.0)
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	if _leap != Leap.NONE:
#		_think_leap(pc)
	# A stiff arm is done on the run, so the brain keeps steering through it.
	if not player.can_act() and player.state != Player.State.STIFF_ARM:
		return
	if pc.ball_dead:
		_think_dead(pc, delta)
		return

	if pc.kickoff and pc.phase == PlayController.Phase.AIR:
		_think_kickoff(pc)
		return

	var pitch_slot: int = pc.pitch_men.find(player)
	if pitch_slot >= 0 and pc.ball.carrier != null and pc.ball.carrier != player:
		_trail(pc, pc.ball.carrier, pitch_slot)
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
				if not _sweep(pc):
					_carry(pc)
			elif carrier.team == player.team:
				_lead_block(pc, carrier.position)
			elif _reading_run(pc, carrier):
				_defense_pocket(pc)
			else:
				_pursue(pc, carrier)
		PlayController.Phase.LOOSE:
			_think_loose(pc)
		PlayController.Phase.TIPPED:
			_think_tipped(pc)


# --- Tipped pass ---------------------------------------------------------------

## The pass has come off somebody's hands: whether to leave his feet for it is
## decided afresh.
func on_tip() -> void:
	_contest_decided = false


# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
## --- Jump dive ---------------------------------------------------------------

### Goes up now and dives out of the jump once he is past the top of it. He
### lands dazed, so this is only for what nothing else will get.
#func _leap_at(pc: PlayController, kind: Leap, target: Player = null) -> void:
#	if not player.can_act() or player.jump_cooldown > 0.0:
#		return
#	_leap = kind
#	_leap_target = target
#	pc.game.add_stat([&"", &"leaps_at_carrier", &"leaps_at_ball", &"leaps_for_line"][kind])
#	pc.do_jump(player)


### In the air with a jump dive in mind: lets go at the right moment, aimed at
### where the man or the ball is by now.
#func _think_leap(pc: PlayController) -> void:
#	if player.state != Player.State.JUMPING:
#		# The jump never came off, or he was hit out of it.
#		_leap = Leap.NONE
#		_leap_target = null
#		return
#	if player.state_timer > tuning.jump_time * tuning.jump_dive_ai_release:
#		return
#	var kind: Leap = _leap
#	var target: Player = _leap_target
#	_leap = Leap.NONE
#	_leap_target = null
#	if pc.ball_dead:
#		return
#	match kind:
#		Leap.MAN:
#			# Somebody else got him, or he is no longer worth a daze.
#			if target == null or target.is_down() or pc.ball.carrier != target:
#				return
#			var speed: float = tuning.dive_speed * tuning.jump_dive_speed_scale
#			var lead: float = minf(_flat_distance(player.position, target.position) / speed, 0.45)
#			pc.do_jump_dive(player, _direction_to(target.position + target.velocity * lead))
#		Leap.BALL:
#			var at_ball: Vector3 = pc.ball_dive_direction(player, pc.jump_dive_ball_range())
#			if at_ball != Vector3.ZERO:
#				pc.do_jump_dive(player, at_ball)
#		Leap.AHEAD:
#			if player.has_ball:
#				pc.do_jump_dive(player, Vector3(float(player.team.attack_dir), 0.0, 0.0))


#func _jump_dive_roll() -> bool:
#	return randf() < _sharp(tuning.ai_jump_dive_chance, tuning.ai_edge_jump_dive_chance)


### Seconds from leaving the ground to landing a jump dive let go at the usual
### moment.
#func _leap_time() -> float:
#	return tuning.jump_time * (1.0 - tuning.jump_dive_ai_release) + tuning.dive_time + tuning.jump_dive_extra_time


### The pass comes down further off than he can run or dive to: he may go up and
### dive out of the jump for it. Decided once per pass, early enough for both.
#func _leap_for_ball(pc: PlayController) -> void:
#	if _ball_leap_decided or _contest_decided:
#		return
#	var time_left: float = pc.ball.air_time_left()
#	if time_left > _leap_time():
#		return
#	_ball_leap_decided = true
#	var landing: Vector3 = pc.ball.target_point
#	var dist: float = _flat_distance(player.position, landing)
#	if dist > pc.jump_dive_ball_range():
#		return
#	# How far off he would be on his feet, and what a plain dive adds to that.
#	var short: float = _flat_distance(player.position + player.velocity * time_left, landing)
#	var plain_dive: float = pc.catch_reach(player, landing) * tuning.dive_catch_radius_scale + tuning.dive_speed * tuning.dive_time * 0.5
#	if short <= plain_dive:
#		return
#	var effort: float = PlayerRatings.blend(player.ratings.catching, tuning.catch_scale_low, tuning.catch_scale_high)
#	if pc.human.team == player.team:
#		effort *= tuning.ai_catch_effort_human_scale
#	if randf() >= effort or not _jump_dive_roll():
#		return
#	_contest_decided = true
#	pc.game.add_stat(&"catch_efforts")
#	_leap_at(pc, Leap.BALL)


### The carrier is getting away from this defender, out of reach of a dive off
### the ground, and nobody on his side is left between the carrier and the goal
### line: a jump dive is the last thing that can stop him.
#func _leap_at_carrier(pc: PlayController, target: Player, dist: float) -> void:
#	if _leap_decided or dist < tuning.ai_dive_range or dist > tuning.ai_jump_dive_range:
#		return
#	if player.block_slow_timer > 0.0 or target.state != Player.State.NORMAL:
#		return
#	var to: Vector3 = _direction_to(target.position)
#	if (player.velocity - target.velocity).dot(to) > 0.5:
#		# Still gaining on him: he will get there on his feet.
#		return
#	var goal_dir: float = float(target.team.attack_dir)
#	for mate: Player in player.team.players:
#		if mate != player and mate.can_act() and (mate.position.x - target.position.x) * goal_dir > 0.0:
#			return
#	_leap_decided = true
#	if _jump_dive_roll():
#		_leap_at(pc, Leap.MAN, target)


### The goal line or the marker is further off than a dive reaches but not than
### a jump dive does, and a tackler is closing: the play ends where he lands
### anyway, so the daze costs him nothing.
#func _leap_for_the_line(pc: PlayController, nearest: float) -> bool:
#	if _leap_decided or nearest > tuning.ai_jump_dive_pressure:
#		return false
#	var dir: float = float(player.team.attack_dir)
#	var goal_x: float = tuning.field_length if dir > 0.0 else 0.0
#	var to_line: float = (goal_x - player.position.x) * dir
#	if player.team == pc.offense and not pc.game.goal_to_go:
#		var to_marker: float = (pc.game.first_down_x - player.position.x) * dir
#		if to_marker > 0.0:
#			to_line = minf(to_line, to_marker)
#	if to_line <= tuning.ai_dive_reach or to_line > tuning.ai_jump_dive_reach:
#		return false
#	_leap_decided = true
#	if not _jump_dive_roll():
#		return false
#	_leap_at(pc, Leap.AHEAD)
#	return true


## The ball is in the air off a tip. The few nearest where it comes down go and
## get under it, and leave their feet for it if that is what it takes; the rest
## come over and get in the way.
func _think_tipped(pc: PlayController) -> void:
	var landing: Vector3 = pc.ball.target_point
	var dist: float = _flat_distance(player.position, landing)
	if pc.ball.thrower == player:
		return
	var closer: int = 0
	for mate: Player in player.team.players:
		if mate != player and mate.can_act() and _flat_distance(mate.position, landing) < dist:
			closer += 1
	if closer >= tuning.ai_tip_chasers:
		# Enough of his side are under it: he comes over and keeps the others
		# off, with his body only (as round a fumble).
		_block(pc, landing)
		player.is_blocking = false
		player.wants_turbo = dist > 4.0
		return
	_seek(landing)
	player.wants_turbo = dist > 1.0
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	_leap_for_ball(pc)
	if _contest_decided:
		return
	var time_left: float = pc.ball.air_time_left()
	var reach: float = pc.catch_reach(player, landing)
	if dist <= reach:
		# Under it: go up and meet it once it is nearly down to where a jump gets.
		if time_left <= tuning.jump_time * 0.6 and not pc.reaches_tip(player):
			_contest_decided = true
			pc.do_jump(player)
		return
	# He will not get there on his feet: dive for it at the last moment.
	var short: float = _flat_distance(player.position + player.velocity * time_left, landing)
	if short > reach and time_left <= tuning.dive_time and dist <= tuning.dive_ball_range:
		_contest_decided = true
		pc.do_dive(player, _direction_to(landing))


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
			# The wall forms in front of where the kick comes down, not in the
			# middle of the field: a kick to one side pulls it over there.
			var edge: float = tuning.half_width() - 2.0
			var lane: float = clampf(landing.z * KICKOFF_WALL_SHIFT + start_point.z * 0.6, -edge, edge)
			_seek(Vector3(landing.x + upfield * KICKOFF_WALL_DEPTH, 0.0, lane))
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
			elif pc.flicking():
				# Flea flicker: he drops while the back has it.
				_seek(route[route.size() - 1] if route.size() > 0 else start_point)
		OffenseAssignment.Job.BLOCK:
			_lead_block(pc, pc.qb.position)
		_:
			if chipping(pc):
				_block(pc, pc.qb.position)
			else:
				_run_route(pc)


## The man a quarterback who is being tackled would try to get the ball to, or
## null: he is running with it, or there is nobody.
func hit_throw_target(pc: PlayController) -> Player:
	if _scrambling or _keep_ball or pc.heave or pc.off_play == null or pc.off_play.is_run:
		return null
	return _best_receiver(pc, true)


## Wrapped up in the pocket: once a tackle he may try to get rid of the ball
## instead of going down with it. True on the tick he does.
func _throws_from_grasp(pc: PlayController) -> bool:
	if _grasp_decided or player != pc.qb or not pc.in_the_grasp():
		return false
	_grasp_decided = true
	if randf() >= tuning.ai_qb_hit_throw_chance:
		return false
	var target: Player = hit_throw_target(pc)
	if target == null:
		return false
	pc.throw_ball(target, tuning.hit_throw_power, PlayController.Placement.NORMAL, true)
	return true


## Sold on a pump fake until `until` (live_time): he breaks on the throw he
## thought he saw, to `spot`, and is left standing when it does not come.
func bite_on_pump(from: float, until: float, spot: Vector3) -> void:
	pump_bite_from = from
	pump_bite_time = until
	pump_bite_spot = spot


func _quarterback(pc: PlayController) -> void:
	if _scrambling:
		_carry(pc)
		var behind_line: bool = (player.position.x - pc.los_x) * pc.off_dir < 0.0
		if _rollout != 0.0 and behind_line and absf(player.position.z - start_point.z) < _rollout_width:
			player.move_input = Vector3(pc.off_dir * _rollout_forward, 0.0, _rollout).normalized()
		player.wants_turbo = true
		if behind_line and not _keep_ball and not pc.off_play.is_run and _decision_timer <= 0.0:
			# Still behind the line: he throws as well on the run as from the
			# pocket, so any open man is worth pulling up for.
			_decision_timer = 0.15
			# One who left the pocket to get away from a rusher gets rid of it
			# with the rusher about to get him anyway.
			var caught: bool = _escaping and pc.nearest_opponent_distance(player) < tuning.ai_edge_escape_dump_range
			var open_man: Player = _best_receiver(pc, _escaping)
			if open_man != null and (caught or _open_for(pc, open_man) >= tuning.ai_qb_open_distance):
				player.wants_turbo = false
				pc.game.add_stat(&"qb_throws_on_the_run")
				var run_power: float = choose_pass(pc, open_man, _open_for(pc, open_man), false)
				pc.throw_ball(open_man, run_power, choose_placement(pc, open_man, run_power))
		return
	var drop_point: Vector3 = route[route.size() - 1] if route.size() > 0 else start_point
	if pc.faking() and not pc.flick_returning():
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

	if _takes_off(pc, pressured, best_open):
		return
	if best == null or (out_of_time and not pressured and best_open < tuning.ai_qb_scramble_open):
		if out_of_time or pressured:
			# Nobody to throw to: tuck it and run. The sharper one goes round
			# the emptier side instead of straight into the rush.
			if pc.cpu_edge(player) > 0.0:
				_break_out(_open_side(pc, 99))
			else:
				_scrambling = true
			run_kind = &"bail"
		return
	if not pressured and not out_of_time and best_open < tuning.ai_qb_open_distance and randf() < tuning.ai_qb_pump_chance:
		# Nobody open and time to spare: he pumps to move the coverage.
		pc.pump_fake()
		return
	if best_open >= tuning.ai_qb_open_distance or pressured or out_of_time:
		var power: float = choose_pass(pc, best, best_open, pressured)
		pc.throw_ball(best, power, choose_placement(pc, best, power))


## How much of a runner this quarterback is: 0 for a statue, 1 about average.
func _mobility() -> float:
	return maxf(PlayerRatings.blend(player.ratings.speed, tuning.qb_mobility_scale_low, tuning.qb_mobility_scale_high), 0.0)


## The sharper quarterback uses his legs. With nobody open and a free rusher
## coming he leaves the pocket before the man gets there, round the side away
## from him. With one side of the field empty he goes round it unless somebody
## is clearly open, and with nobody open for long enough he goes round the
## emptier side anyway. He can still pull up and throw to a man who comes
## free. A quarterback short of time has no use for a few yards on the ground.
func _takes_off(pc: PlayController, pressured: bool, best_open: float) -> bool:
	var edge: float = pc.cpu_edge(player)
	if edge <= 0.0:
		return false
	var covered: bool = best_open < tuning.ai_qb_open_distance
	var want: float = edge * clampf(_mobility(), tuning.ai_edge_mobility_floor, 1.5) * (1.0 - pc.qb_urgency)
	var rusher: Player = _free_rusher()
	if rusher != null:
		if not covered or _escape_rolled:
			return false
		_escape_rolled = true
		if randf() >= tuning.ai_edge_escape_chance * want:
			return false
		var across: float = rusher.position.z - player.position.z
		# Straight up the middle: whichever side has fewer people on it.
		var side: float = -signf(across) if absf(across) > 0.5 else _open_side(pc, 99)
		pc.game.add_stat(&"qb_escapes")
		_break_out(side)
		_escaping = true
		run_kind = &"escape"
		return true
	if pressured or pc.live_time < tuning.ai_edge_lane_time:
		return false
	var empty: float = _open_side(pc, 0)
	if empty != 0.0 and best_open < tuning.ai_edge_lane_open and _lane_timer <= 0.0:
		_lane_timer = tuning.ai_edge_lane_retry
		if randf() < tuning.ai_edge_lane_chance * want:
			pc.game.add_stat(&"qb_lane_runs")
			_break_out(empty)
			run_kind = &"lane"
			return true
	if covered and not _bail_rolled and pc.live_time >= tuning.ai_edge_bail_time:
		_bail_rolled = true
		if randf() < tuning.ai_edge_bail_chance * want:
			pc.game.add_stat(&"qb_bails")
			_break_out(_open_side(pc, 99))
			run_kind = &"bail"
			return true
	return false


## Out of the pocket and round the line on that side, as on a designed keeper.
func _break_out(side: float) -> void:
	start_scramble(side, false, tuning.ai_qb_keeper_width, tuning.ai_qb_keeper_forward)


## The nearest defender within ai_edge_escape_range whom nobody is blocking,
## or null.
func _free_rusher() -> Player:
	var rusher: Player = null
	var nearest: float = tuning.ai_edge_escape_range
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down() or opponent.block_slow_timer > 0.0:
			continue
		var dist: float = _flat_distance(opponent.position, player.position)
		if dist < nearest:
			nearest = dist
			rusher = opponent
	return rusher


## Which side to go round the line on: +1 or -1 for the one with fewer free
## defenders between him and the corner (up to ai_edge_lane_depth yards ahead
## and ai_edge_lane_width yards out), or 0 if even that one has more than
## `limit` of them.
func _open_side(pc: PlayController, limit: int) -> float:
	var low: int = 0
	var high: int = 0
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down() or opponent.block_slow_timer > 0.0:
			continue
		var ahead: float = (opponent.position.x - player.position.x) * pc.off_dir
		var across: float = opponent.position.z - player.position.z
		if ahead < -3.0 or ahead > tuning.ai_edge_lane_depth or absf(across) > tuning.ai_edge_lane_width:
			continue
		if across < 0.0:
			low += 1
		else:
			high += 1
	if mini(low, high) > limit:
		return 0.0
	if low != high:
		return -1.0 if low < high else 1.0
	# Nothing in it: the side with more field.
	if absf(player.position.z) > 1.0:
		return -signf(player.position.z)
	return 1.0 if randf() < 0.5 else -1.0


## This player's value for something the sharper CPU team does differently:
## `base` for the person's own teammates, `sharp` at full edge.
func _sharp(base: float, sharp: float) -> float:
	return lerpf(base, sharp, player.play.cpu_edge(player))


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
		if receiver.is_down() or receiver.brain.chipping(pc):
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
	# A team that throws short takes the man underneath unless time is short.
	var depth_bonus: float = lerpf(tuning.ai_qb_depth_bonus * player.team.call_bias[OffensePlay.Category.DEEP], tuning.ai_qb_urgent_depth_bonus, pc.qb_urgency)
	for receiver: Player in pc.eligible:
		# A man still in his block is not looking for the ball.
		if receiver.is_down() or receiver.brain.chipping(pc):
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
		if randf() < _sharp(tuning.ai_qb_keeper_chance, tuning.ai_edge_keeper_chance) * maxf(_mobility(), _sharp(0.0, tuning.ai_edge_mobility_floor)):
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
	run_kind = &"keeper"
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
	var noise: float = tuning.ai_qb_placement_noise * PlayerRatings.blend(player.ratings.accuracy, tuning.accuracy_overlead_scale_low, tuning.accuracy_overlead_scale_high)
	var under_gain: float = _underthrow_gain(pc, target, speed, noise)
	var under: PlayController.Placement = PlayController.Placement.UNDER if under_gain >= tuning.ai_qb_under_margin else PlayController.Placement.NORMAL
	var normal: Vector3 = pc.pass_spot(target, speed)
	# About to cut or stop: no leading him past it.
	if pc.aim_cuts:
		return under
	var flight: float = _flat_distance(player.position, normal) / speed
	var run: Vector3 = Vector3(target.velocity.x, 0.0, target.velocity.z)
	if run.length() < tuning.run_speed * 0.5:
		return under

	# Lead him only if he has the legs left to run on to it.
	var ahead: Vector3 = pc.pass_spot(target, speed, PlayController.Placement.LEAD)
	if _flat_distance(ahead, normal) >= 1.0 and not target.turbo_locked and target.turbo >= tuning.ai_qb_lead_min_turbo:
		var gain: float = _open_at_spot(target, ahead, flight) - _open_at_spot(target, normal, flight) + randf_range(-noise, noise)
		if gain >= tuning.ai_qb_lead_margin and gain >= under_gain:
			return PlayController.Placement.LEAD
	return under


## How many yards more open the spot of an underthrown pass to `target` looks
## than the regular one, or -INF when he does not think of throwing one: it has
## to be a throw of some length, with the nearest defender on the far side of
## the receiver (who then comes back to the ball with that man behind him) and
## nobody underneath to step in front of it.
func _underthrow_gain(pc: PlayController, target: Player, speed: float, noise: float) -> float:
	var home: Vector3 = player.position - target.position
	home.y = 0.0
	if home.length() < tuning.ai_qb_under_min_distance:
		return -INF
	if randf() >= _sharp(tuning.ai_qb_under_chance, tuning.ai_edge_under_chance):
		return -INF
	var short: Vector3 = pc.pass_spot(target, speed, PlayController.Placement.UNDER)
	var flight: float = _flat_distance(player.position, short) / speed
	var path: Vector3 = short - player.position
	path.y = 0.0
	var length: float = path.length()
	var nearest: Player = null
	var nearest_dist: float = INF
	for opponent: Player in target.team.opponent.players:
		if opponent.is_down():
			continue
		var dist: float = _flat_distance(opponent.position, target.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = opponent
		# Anyone near the last stretch of the ball's path can get a hand on it.
		var soon: Vector3 = opponent.position + opponent.velocity * minf(flight, 0.4) - player.position
		soon.y = 0.0
		var along: float = soon.dot(path) / maxf(length, 0.01)
		if along >= length * 0.5 and (soon - path / maxf(length, 0.01) * minf(along, length)).length() < tuning.ai_qb_under_lane:
			return -INF
	if nearest != null:
		var offset: Vector3 = nearest.position - target.position
		offset.y = 0.0
		if offset.dot(home) >= 0.0:
			return -INF
	var normal: Vector3 = pc.pass_spot(target, speed)
	return _open_at_spot(target, short, flight) - _open_at_spot(target, normal, flight) + randf_range(-noise, noise)


## Distance from `spot` to the nearest defender, each judged by where he will be
## a moment from now (they do not all keep running the same way for the whole
## flight).
func _open_at_spot(target: Player, spot: Vector3, flight: float) -> float:
	var best: float = 10.0
	for opponent: Player in target.team.opponent.players:
		if not opponent.is_down():
			best = minf(best, _flat_distance(opponent.position + opponent.velocity * minf(flight, 0.4), spot))
	return best


## A jet sweep (PreSnapMotion.jet_sweep): the man who took the ball on the run
## keeps to the path the play draws for him, flat out, until he is round the
## end and at the line. Left to _carry he would turn upfield where he got the
## ball, straight into his own linemen.
func _sweep(pc: PlayController) -> bool:
	if not pc.motion.jet_sweep or player != pc.runner or route_index >= route.size():
		return false
	if (player.position.x - pc.los_x) * pc.off_dir >= 0.0:
		return false
	var target: Vector3 = route[route_index]
	if _flat_distance(player.position, target) < 0.9:
		route_index += 1
	player.move_input = _direction_to(target)
	player.wants_turbo = true
	return true


func _run_route(pc: PlayController) -> void:
	_call_for_ball(pc)
	if player == pc.runner and pc.motion.jet_sweep:
		# A jet sweep: he comes past the quarterback at full speed.
		player.wants_turbo = true
	if player == pc.runner and pc.selling_run():
		# Play action: he hits the hole like a man with the ball.
		player.wants_turbo = true
	if player.has_ball and pc.flicking():
		# Flea flicker: he plants at the first point of his route and waits to
		# pitch it back.
		if route.size() > 0 and _flat_distance(player.position, route[0]) > 0.6:
			player.move_input = _direction_to(route[0])
		return
	if route_index < route.size():
		var target: Vector3 = route[route_index]
		_juke_at_cut(pc, target)
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


## Coming up to a point of his route where it turns, with a defender near
## enough to be fooled by it: he sells the cut (PlayerAnimator.route_juke). Once
## per cut, and only for show: whether the defender falls for it is his own
## roll (see _cover_spot).
func _juke_at_cut(pc: PlayController, target: Vector3) -> void:
	if _juke_index == route_index or player.animator == null or player.has_ball or not _is_receiver(pc):
		return
	if pc.phase != PlayController.Phase.POCKET or _flat_distance(player.position, target) > ROUTE_JUKE_LEAD:
		return
	var from: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if from.length() < tuning.run_speed * 0.5:
		return
	from = from.normalized()
	var to: Vector3 = route_exit_dir
	if route_index + 1 < route.size():
		to = route[route_index + 1] - target
		to.y = 0.0
		to = to.normalized()
	elif off_assign.settle:
		return
	if to == Vector3.ZERO or to.dot(from) >= ROUTE_CUT_DOT:
		return
	_juke_index = route_index
	if _open_at_spot(player, player.position, 0.0) > tuning.ai_route_juke_range:
		return
	# +1 when the cut takes him to his own right.
	player.animator.route_juke(-to.dot(Vector3.UP.cross(from)))


## The CPU is still running him through the waypoints of his route.
func on_route(pc: PlayController) -> bool:
	return is_offense and off_assign != null and pc.phase == PlayController.Phase.POCKET \
			and _is_receiver(pc) and route_index < route.size() \
			and player.human == null and not chipping(pc)


## A chip and release: he is still in his block and has not gone out on his
## route yet (see OffenseAssignment.block_time).
func chipping(pc: PlayController) -> bool:
	return is_offense and off_assign != null and off_assign.job == OffenseAssignment.Job.ROUTE \
			and off_assign.block_time > 0.0 and pc.phase == PlayController.Phase.POCKET \
			and pc.live_time < off_assign.block_time


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
			or (player == pc.runner and pc.selling_run()) \
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
	var at_hole: bool = tuning.ai_hole_read and player == pc.runner and pc.run_hole_live()
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
		if at_hole and opponent.hole_block and opponent.block_slow_timer > 0.0:
			# His blockers have this one: he runs past him, not away from him.
			continue
		if dist < tuning.ai_carrier_avoid_radius and to.dot(forward) > -1.0:
			var side: float = signf(to.z)
			if side == 0.0:
				side = signf(player.position.z)
			steer.z -= side * (1.0 - dist / tuning.ai_carrier_avoid_radius) * 1.3
	var edge: float = tuning.half_width() - 3.0
	if absf(player.position.z) > edge:
		steer.z -= signf(player.position.z) * 2.0
	if at_hole:
		# Behind the line on a run at a hole: when his blockers have opened a
		# lane he runs at the middle of it. With none open he runs as he
		# always does.
		# A hole still far off to one side (a counter) is run to as the play
		# draws it, not straight across the field.
		var lane: Vector2 = pc.hole_lane()
		if lane.y >= tuning.ai_hole_min_room and absf(lane.x - player.position.z) <= tuning.hole_pull_range:
			steer.z += clampf(lane.x - player.position.z, -1.0, 1.0) * tuning.ai_hole_pull
	player.move_input = steer.normalized()
	player.wants_turbo = nearest < tuning.ai_turbo_range

	if nearest_opponent == null or not player.can_act():
		return
	if _dive_for_the_line(pc, nearest):
		pc.do_dive(player, forward)
		return
	if _laterals(pc, nearest_opponent, nearest):
		return
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	if _leap_for_the_line(pc, nearest):
#		return
	if _hurdles(pc):
		return
	_bursts_away(pc, nearest_opponent, nearest)
	if _secures(pc, nearest_opponent, nearest):
		return
	if _decision_timer <= 0.0 and _move_due(pc, nearest_opponent, nearest):
		_decision_timer = 0.5
		_move_lead = -1.0
		_carrier_move(pc, nearest_opponent)


## True on the tick this carrier pitches the ball to a teammate instead of
## taking the tackle that is about to arrive. With the clock run out and points
## needed (Game.last_gasp) he does whenever the teammate has more room than he
## has. Otherwise only now and then: past the line or on a scramble, with a
## safe pitch to a man in the clear, decided once for each tackler; and never
## when a yard or two is what he needs, or when his team is ahead late.
func _laterals(pc: PlayController, opponent: Player, dist: float) -> bool:
	if not pc.can_lateral(player):
		return false
	var to: Vector3 = opponent.position - player.position
	to.y = 0.0
	to /= maxf(dist, 0.01)
	var closing: float = (player.velocity - opponent.velocity).dot(to)
	# Seconds until the tackler is within reach.
	var contact: float = (dist - tuning.tackle_radius) / maxf(closing, 0.5)
	if contact > tuning.ai_lateral_lead:
		return false
	var target: Player = pc.lateral_target(player)
	if target == null:
		return false
	var room: float = pc.nearest_opponent_distance(target)
	if pc.game.last_gasp(player.team):
		return room > dist and pc.do_lateral(player)
	if _lateral_tackler == opponent:
		return false
	_lateral_tackler = opponent
	var past_line: bool = player.team != pc.offense or pc.kickoff or _scrambling or (player.position.x - pc.los_x) * pc.off_dir > 0.0
	if not past_line or _short_yardage(pc) or _protects_lead(pc):
		return false
	if room < tuning.ai_lateral_open or _flat_distance(target.position, player.position) > tuning.lateral_safe_range:
		return false
	# Somebody near the ball's way to him: not worth it.
	if pc.lateral_risk(player, target) > tuning.lateral_fumble_chance * RubberBand.bad(player.team, pc.game) + 0.001:
		return false
	if randf() >= _sharp(tuning.ai_lateral_chance, tuning.ai_edge_lateral_chance):
		return false
	return pc.do_lateral(player)


## Wrapped up: with the clock run out and points needed he gets the ball away
## to anybody he can. Otherwise once a tackle, now and then, and not a
## quarterback in the pocket: the sack costs him less than the fumble would.
func _laterals_from_grasp(pc: PlayController) -> bool:
	if not player.has_ball or not pc.can_lateral(player):
		return false
	if not pc.game.last_gasp(player.team):
		if _grasp_lateral_decided:
			return false
		_grasp_lateral_decided = true
		if pc.phase != PlayController.Phase.RUN or _protects_lead(pc) or randf() >= tuning.ai_lateral_grasp_chance:
			return false
	return pc.do_lateral(player)


## His team is ahead in the second half: the ball is worth more than the yards.
func _protects_lead(pc: PlayController) -> bool:
	return pc.game.half >= 2 and player.team.score > player.team.opponent.score


## The carrier's pitch man (`slot` 0 is the nearest of them): he follows a few
## yards behind him and out to the side he is on already, where a lateral can
## find him.
func _trail(_pc: PlayController, carrier: Player, slot: int) -> void:
	var dir: float = float(player.team.attack_dir)
	var side: float = signf(player.position.z - carrier.position.z)
	if side == 0.0:
		side = -signf(carrier.position.z) if carrier.position.z != 0.0 else 1.0
	var back: float = tuning.lateral_trail_back * (1.0 + 0.6 * float(slot))
	var width: float = tuning.lateral_trail_side * (1.0 + 0.5 * float(slot))
	var spot: Vector3 = carrier.position + Vector3(carrier.velocity.x, 0.0, carrier.velocity.z) * 0.3
	spot += Vector3(-dir * back, 0.0, side * width)
	var edge: float = tuning.half_width() - 2.0
	spot.z = clampf(spot.z, -edge, edge)
	_seek(spot)
	player.wants_turbo = _flat_distance(player.position, spot) > 2.0


## A chaser at his back or his side who is gaining on him: the burst of speed
## that comes with securing the ball is spent on pulling away. Decided once
## for each chaser, with the same chance as securing it for a tackler.
func _bursts_away(pc: PlayController, opponent: Player, dist: float) -> void:
	if dist > tuning.ai_secure_chase_range or player.secure_cooldown > 0.0:
		return
	# Nothing left in the meter to pay for it with.
	if tuning.secure_turbo_cost > 0.0 and player.turbo <= 0.0:
		return
	var to: Vector3 = opponent.position - player.position
	to.y = 0.0
	to /= maxf(dist, 0.01)
	if to.dot(player.facing) > 0.0 or (player.velocity - opponent.velocity).dot(to) <= 0.0:
		return
	if _chase_target != opponent:
		_chase_target = opponent
		_chase_on = randf() < _sharp(tuning.ai_secure_chance, tuning.ai_edge_secure_chance)
	if _chase_on:
		pc.game.add_stat(&"secures_chase")
		pc.do_secure(player)


## Secures the ball as a tackler is about to arrive, and returns true when the
## carrier means to run `opponent` over, so that no spin or stiff arm gets in
## the way.
## - Short yardage: a back strong enough to drag a tackler always does.
## - Otherwise decided once for each tackler: the carrier a good deal
##   stronger than a tackler on his feet in front of him lowers his shoulder.
##   Anyone else covers the ball only if no spin or stiff arm came of it, so
##   the small quick carrier mostly just looks after the ball.
func _secures(pc: PlayController, opponent: Player, dist: float) -> bool:
	if dist > tuning.ai_move_range:
		return false
	var to: Vector3 = opponent.position - player.position
	to.y = 0.0
	to /= maxf(dist, 0.01)
	var closing: float = (player.velocity - opponent.velocity).dot(to)
	# Seconds until the tackler is within reach.
	var contact: float = (dist - tuning.tackle_radius) / maxf(closing, 0.5)
	if contact > tuning.ai_secure_lead:
		return false
	if _short_yardage(pc):
		var drag_time: float = PlayerRatings.blend(player.ratings.strength, tuning.drag_time_low, tuning.drag_time_high)
		if drag_time * tuning.secure_drag_time_scale >= tuning.drag_min_time:
			pc.do_secure(player)
	if _secure_target != opponent:
		_secure_target = opponent
		var stronger: float = float(player.ratings.strength - opponent.ratings.strength)
		var elusive: float = float(player.ratings.juke - player.ratings.strength)
		_secure_power = stronger >= tuning.ai_secure_strength_margin and elusive < tuning.ai_move_rating_margin \
				and to.dot(player.facing) >= tuning.secure_truck_front_dot
		_secure_on = randf() < _sharp(tuning.ai_secure_chance, tuning.ai_edge_secure_chance)
		if _secure_on:
			pc.game.add_stat(&"secures_power" if _secure_power else &"secures_cover")
	if not _secure_on:
		return false
	if _secure_power:
		pc.do_secure(player)
		return true
	# His move has been and gone, or he chose to make none.
	if _decision_timer > 0.0 or player.move_cooldown > 0.0:
		pc.do_secure(player)
	return false


## The runner with a yard or two to go for the first down or the goal line.
func _short_yardage(pc: PlayController) -> bool:
	if player != pc.runner or player.team != pc.offense:
		return false
	var dir: float = float(player.team.attack_dir)
	var goal_x: float = tuning.field_length if dir > 0.0 else 0.0
	var to_go: float = (goal_x - player.position.x) * dir
	if not pc.game.goal_to_go:
		to_go = minf(to_go, (pc.game.first_down_x - player.position.x) * dir)
	return to_go > 0.0 and to_go <= tuning.ai_secure_short_yards


## The sharper carrier goes over a tackler who dives at him. Only a dive: a
## man on his feet wraps up a carrier in the air like any other. And only a
## dive he would be high enough over when it gets to him: one that is too
## close for his jump he leaves to a spin or a stiff arm.
func _hurdles(pc: PlayController) -> bool:
	var edge: float = pc.cpu_edge(player)
	if edge <= 0.0 or _hurdle_timer > 0.0:
		return false
	for opponent: Player in player.team.opponent.players:
		if opponent.state != Player.State.DIVING:
			continue
		var to: Vector3 = player.position - opponent.position
		to.y = 0.0
		var dist: float = to.length()
		if dist > tuning.ai_edge_hurdle_range or dist < 0.01 or opponent.velocity.dot(to / dist) <= 0.0:
			continue
		if not _would_clear(opponent, to / dist, dist):
			continue
		_hurdle_timer = 0.5
		if randf() < tuning.ai_edge_hurdle_chance * edge:
			pc.game.add_stat(&"hurdle_jumps")
			pc.do_jump(player)
			return true
		return false
	return false


## Whether a jump started now would have his feet over the diving `opponent`
## when the dive gets to him. `toward` points from the diver to him.
func _would_clear(opponent: Player, toward: Vector3, dist: float) -> bool:
	var closing: float = (opponent.velocity - player.velocity).dot(toward)
	if closing <= 0.0:
		return false
	var contact: float = maxf(dist - tuning.dive_tackle_radius, 0.0) / closing
	var t: float = contact / maxf(tuning.jump_time, 0.01)
	if t >= 1.0:
		return false
	# As high as the stamina he has left would take him.
	var height: float = player.jump_height(player.move_strength(tuning.jump_stamina_cost, false))
	return 4.0 * height * t * (1.0 - t) >= tuning.hurdle_clear_height


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
		if randf() < _sharp(tuning.ai_move_mistime_chance, tuning.ai_edge_move_mistime_chance) * _mistime_scale():
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
	# With the clock run out the marker is worth nothing: only a score is.
	if player.team != pc.offense or pc.game.goal_to_go or pc.game.last_gasp(player.team):
		return false
	var to_marker: float = (pc.game.first_down_x - player.position.x) * dir
	return to_marker > 0.0 and to_marker <= tuning.ai_dive_reach and nearest < tuning.ai_dive_marker_pressure


## Picks the move that fits where the tackler is coming from: a stiff arm for one
## closing from the side, a spin for one straight ahead. A carrier who is much
## better at the other move uses that one where it can work: the strong one
## puts his arm out at a tackler in front of him, the elusive one spins off a
## tackler at his side.
func _carrier_move(pc: PlayController, opponent: Player) -> void:
	var to: Vector3 = opponent.position - player.position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	to = to.normalized()
	var ahead: float = to.dot(player.facing)
	var left: float = to.dot(Vector3.UP.cross(player.facing))

	var stiff_arm: bool = absf(left) > tuning.ai_stiff_arm_side_dot and ahead > -0.5
	var stronger: float = float(player.ratings.strength - player.ratings.juke)
	if stiff_arm and -stronger >= tuning.ai_move_rating_margin:
		stiff_arm = false
		pc.game.add_stat(&"spins_by_rating")
	elif not stiff_arm and ahead > 0.0 and left != 0.0 and stronger >= tuning.ai_move_rating_margin:
		stiff_arm = true
		pc.game.add_stat(&"stiff_arms_by_rating")

	if stiff_arm:
		# Strong carriers use the stiff arm more.
		if randf() < _sharp(tuning.ai_stiff_arm_chance, tuning.ai_edge_move_chance) * float(player.ratings.strength) / 50.0:
			var side: float = signf(left)
			if randf() < _sharp(tuning.ai_move_wrong_side_chance, tuning.ai_edge_move_wrong_side_chance) * _mistime_scale():
				# The wrong arm: it does nothing for him.
				side = -side
				pc.game.add_stat(&"mistimed_moves")
			pc.do_stiff_arm(player, side)
		return

	# Elusive carriers spin more. The spin sidesteps away from the tackler.
	if randf() < _sharp(tuning.ai_spin_chance, tuning.ai_edge_move_chance) * float(player.ratings.juke) / 50.0:
		pc.do_spin(player, -signf(left) if left != 0.0 else 1.0, true)


## A blocker with a path drawn for him on a run play (the fullback through the
## hole, a tight end round the edge) runs it in front of the carrier until a
## defender nobody is blocking yet is near enough to take on: the linebacker
## in the hole, not the lineman his own line already has. Everybody else
## blocks from the start, and so does he once his path is run or the carrier
## has gone past him.
func _lead_block(pc: PlayController, protect: Vector3) -> void:
	var leading: bool = is_offense and off_assign != null and off_assign.job == OffenseAssignment.Job.BLOCK \
			and pc.off_play.is_run and route_index < route.size()
	if leading:
		var carrier: Player = pc.ball.carrier
		if carrier != null and carrier != pc.qb and (carrier.position.x - player.position.x) * pc.off_dir > 1.0:
			leading = false
	if not leading:
		_block(pc, protect)
		return
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down() or opponent.block_slow_timer > 0.0:
			continue
		if _flat_distance(opponent.position, player.position) <= tuning.ai_lead_block_range:
			_block(pc, protect, true)
			return
	var target: Vector3 = route[route_index]
	if _flat_distance(player.position, target) < 0.9:
		route_index += 1
	player.move_input = _direction_to(target)
	# He has to get there before the man with the ball does.
	player.wants_turbo = true


## Get between the most dangerous nearby opponent and the thing being protected.
## `free_only` leaves the ones a teammate is already blocking to him.
func _block(pc: PlayController, protect: Vector3, free_only: bool = false) -> void:
	player.is_blocking = true
	if is_offense and (player.hole_side != 0.0 or free_only) and pc.run_hole_live():
		_block_hole(pc, free_only)
		return
	var best: Player = null
	var best_score: float = INF
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		if free_only and opponent.block_slow_timer > 0.0 and opponent.block_partner != player:
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


## Blocking for the hole on a run aimed inside, until the ball is through it.
## A lineman takes the man he was given at the line-up for as long as that man
## is on his feet and near, and after that whoever is nearest on his own side
## of the hole; a lead blocker takes the first free man he meets. He sets up
## inside and behind his man, never with his own body in the lane, so the man
## is walked out of the hole (PlayController._drive_block) and the blocker ends
## up as the edge of it.
func _block_hole(pc: PlayController, free_only: bool) -> void:
	var hole_z: float = pc.run_hole.z
	var target: Player = player.block_target
	if target != null and (target.is_down() or _flat_distance(target.position, player.position) > 8.0):
		target = null
	if target == null:
		var best_score: float = INF
		for opponent: Player in player.team.opponent.players:
			if opponent.is_down():
				continue
			if opponent.block_slow_timer > 0.0 and opponent.block_partner != player and (free_only or player.hole_side != 0.0):
				continue
			if player.hole_side != 0.0 and (opponent.position.z - hole_z) * player.hole_side < -0.3:
				continue
			var score: float = _flat_distance(opponent.position, player.position) + 0.35 * _flat_distance(opponent.position, pc.run_hole)
			if score < best_score:
				best_score = score
				target = opponent
	if target == null:
		return
	var side: float = player.hole_side
	if side == 0.0:
		side = target.block_drive_side if target.block_drive_by == player else target.position.z - hole_z
		if absf(side) < 0.3:
			side = target.position.z - player.position.z
		side = 1.0 if side >= 0.0 else -1.0
	var out: float = (target.position.z - hole_z) * side
	# Inside his man, but no nearer the middle of the lane than its edge; and
	# while the man is still nearer than that, straight behind him.
	var edge: float = tuning.hole_lane_half + tuning.player_radius
	var wide: float = maxf(out - 0.6, minf(edge, out))
	var spot: Vector3 = Vector3(target.position.x - pc.off_dir * 0.6, 0.0, hole_z + side * wide)
	_seek(spot)
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
	if pc.live_time < pump_bite_time and pc.phase == PlayController.Phase.POCKET:
		# Sold on the pump fake: he breaks on the ball that never left, then
		# stands there finding out.
		var into: float = (pc.live_time - pump_bite_from) / maxf(pump_bite_time - pump_bite_from, 0.01)
		if into < 0.35:
			_seek(pump_bite_spot)
		return
	if _takes_out(pc):
		return
	match def_assign.job:
		DefenseAssignment.Job.RUSH:
			if _peels(pc):
				_cover_man(pc)
			else:
				# Rushers hold their turbo at first so the QB gets a moment to read.
				_pursue(pc, pc.qb, pc.live_time >= _sharp(tuning.ai_rush_turbo_delay, tuning.ai_edge_rush_turbo_delay))
		DefenseAssignment.Job.MAN:
			if man_target == null:
				_cover_zone(pc)
			elif _green_dogs(pc):
				_pursue(pc, pc.qb)
			else:
				_cover_man(pc)
		DefenseAssignment.Job.ZONE:
			_cover_zone(pc)
		DefenseAssignment.Job.SPY:
			_spy(pc)
			return
	if pc.live_time < blown_time:
		# Blown coverage: slow off the mark, looking into the backfield.
		player.ai_speed_scale *= tuning.ai_blown_coverage_speed
		player.wants_turbo = false


## A rusher told to peel: the back nobody covers has come out of the backfield
## on his side instead of staying in to block, so he leaves the rush and takes
## him man to man.
func _peels(pc: PlayController) -> bool:
	if _peeling:
		return true
	var back: Player = peel_target
	if back == null or back.is_down() or back.is_blocking or back.has_ball:
		return false
	var job: OffenseAssignment = back.brain.off_assign
	if job == null or back.brain.chipping(pc):
		return false
	match job.job:
		OffenseAssignment.Job.ROUTE:
			pass
		OffenseAssignment.Job.RUNNER:
			# A faked handoff: he is a receiver once the fake is over.
			if pc.off_play.is_run or pc.live_time < pc.fake_end():
				return false
		_:
			return false
	if _flat_distance(back.position, back.brain.start_point) < tuning.ai_peel_release:
		return false
	if peel_side != 0.0 and (back.position.z - back.brain.start_point.z) * peel_side < 0.0:
		return false
	_peeling = true
	man_target = back
	pc.game.add_stat(&"peels")
	return true


## His man is staying in to block, so he comes for the quarterback: the extra
## blocker gets an extra rusher, as he would from a linebacker who sees it.
func _green_dogs(pc: PlayController) -> bool:
	if not def_assign.green_dog or pc.live_time < tuning.ai_green_dog_delay:
		return false
	var job: OffenseAssignment = man_target.brain.off_assign
	return job != null and job.job == OffenseAssignment.Job.BLOCK


## The defender picked to take a receiver or the back out goes for him once the
## man is near: his own man in man coverage, whoever is nearest in a zone. Only
## while the quarterback still has the ball, and he gives up on it after a while.
func _takes_out(pc: PlayController) -> bool:
	if takeout_time < 0.0 or pc.live_time < takeout_time or pc.phase != PlayController.Phase.POCKET:
		return false
	if pc.live_time > tuning.ai_takeout_give_up:
		takeout_time = -1.0
		return false
	var victim: Player = man_target if def_assign.job == DefenseAssignment.Job.MAN else null
	if victim == null:
		var nearest: float = INF
		for receiver: Player in pc.eligible:
			var gap: float = _flat_distance(receiver.position, player.position)
			if gap < nearest:
				nearest = gap
				victim = receiver
	if victim == null or victim.is_down() or victim.is_blocking or victim.has_ball:
		return false
	var gap: float = _flat_distance(victim.position, player.position)
	if gap > tuning.ai_takeout_close_range:
		return false
	if gap > tuning.ai_takeout_range:
		# Close enough to go and get him: he leaves his coverage and runs at him.
		player.move_input = _direction_to(victim.position + victim.velocity * 0.2)
		player.wants_turbo = true
		return true
	takeout_time = -1.0
	takeout_target = victim
	pc.do_dive(player, _direction_to(victim.position + victim.velocity * 0.12))
	return true


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
	aim.x += pc.off_dir * _man_cushion(pc)
	aim.z += leverage
	# A man still in the backfield is waited for past the line, not chased into
	# it through the blockers: the defender stays across from him.
	var hold: float = pc.los_x + pc.off_dir * tuning.ai_cover_back_depth
	var waiting: bool = (pc.los_x - man_target.position.x) * pc.off_dir > 2.0 and (hold - aim.x) * pc.off_dir > 0.0
	if waiting:
		# Across from where he is going, not where he is.
		aim = Vector3(hold, 0.0, man_target.position.z + _read_velocity.z * tuning.ai_cover_back_lead + leverage)
	player.ai_speed_scale = tuning.ai_cover_speed_scale * _cut_scale(man_target)
	_seek(aim)
	if waiting:
		player.wants_turbo = _bust_timer <= 0.0 and _flat_distance(player.position, aim) > tuning.ai_cover_back_slack
		return
	# Beaten: he is past the defender or has pulled away. Burn turbo to recover.
	var behind: float = (man_target.position.x - player.position.x) * pc.off_dir
	var gap: float = _flat_distance(player.position, man_target.position)
	player.wants_turbo = _bust_timer <= 0.0 and (behind > tuning.ai_cover_beaten_depth or gap > tuning.ai_cover_beaten_gap)


## Yards downfield of his man a man defender aims to be (negative = on the
## quarterback's side of him).
func _man_cushion(pc: PlayController) -> float:
	var tight: float = tuning.ai_cover_cushion
	if def_assign.underneath:
		return -tight
	match technique:
		Technique.TRAIL:
			return -tuning.ai_cover_trail_cushion
		Technique.OFF:
			# He gives ground as his man comes at him, and less of it the further
			# downfield they get. A man who pulls up short gets closed on.
			var depth: float = (man_target.position.x - pc.los_x) * pc.off_dir
			var want: float = tight
			var early: bool = pc.live_time < 0.3
			if early or man_target.velocity.x * pc.off_dir > tuning.run_speed * 0.5:
				want = lerpf(tuning.ai_cover_off_cushion, tight, clampf(depth / maxf(tuning.ai_cover_off_depth, 0.01), 0.0, 1.0))
			_cushion = want if early else move_toward(_cushion, want, tuning.ai_cover_off_close * _delta)
			return maxf(_cushion, tight)
	return tight


func _cover_zone(pc: PlayController) -> void:
	var deep: bool = def_assign.deep
	var hot: Player = pc.hot_receiver()
	# Underneath, with a deep zone behind him: a receiver who has gone on up the
	# field belongs to the deep man now, and he looks for the next one in.
	var passes_off: bool = not deep and pc.deep_help()
	# The curl-flat man: whoever comes out into the flat wider than the middle
	# of his zone is his, out to the sideline.
	var flat_side: float = signf(zone_center.z) if def_assign.flat and not deep else 0.0
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
		var past: float = (receiver.position.x - zone_center.x) * pc.off_dir
		if passes_off and past > tuning.ai_zone_pass_off_depth:
			continue
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = receiver
		var in_flat: bool = false
		var out: float = 0.0
		if flat_side != 0.0 and (receiver.position.x - pc.los_x) * pc.off_dir < tuning.ai_zone_flat_depth:
			# Short and wide of him, and on his way out there: a back, or a man
			# who has left his stance for the sideline. Not a wideout who is
			# simply standing out there.
			out = maxf(soon.z - zone_center.z, receiver.position.z - zone_center.z) * flat_side
			var start: Vector3 = receiver.brain.start_point
			var from_backfield: bool = (start.x - pc.los_x) * pc.off_dir < DefenseAligner.BACKFIELD
			in_flat = out > 0.0 and (from_backfield or (receiver.position.z - start.z) * flat_side >= 2.0)
		if dist > reach and not in_flat:
			continue
		# Deep zones take the deepest man; underneath zones take the closest.
		var score: float = (receiver.position.x - pc.los_x) * pc.off_dir if deep else -dist
		if in_flat:
			# Before anybody else, and the widest of them first.
			score = 100.0 + out
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
		chance *= _sharp(1.0, tuning.ai_edge_bust_scale)
		if randf() < chance:
			_bust_timer = tuning.ai_cover_bust_time
			_bust_ghost = target.position
			pc.game.add_stat(&"coverage_busts")
			pc.gambles.append(&"bust")
			_show_fake_out(pc, target)
	if _bust_timer > 0.0:
		# Fooled: he keeps chasing the receiver he thought he saw.
		_bust_timer -= _delta
		_bust_ghost += _read_velocity * _delta
		return _bust_ghost
	return target.position + _read(target) * tuning.ai_cover_lead


## He has bitten on `target`'s cut: he lunges the way he thought the man was
## going, and a person whose receiver it is feels his man go.
func _show_fake_out(pc: PlayController, target: Player) -> void:
	var wrong: Vector3 = _read_velocity - target.velocity
	wrong.y = 0.0
	pc.game.rumble.play_mine(&"fake_out", target)
	if player.animator == null:
		return
	var right: Vector3 = -Vector3.UP.cross(Vector3(player.facing.x, 0.0, player.facing.z))
	var side: float = wrong.dot(right)
	if absf(side) < 0.5:
		# The man stopped or took off straight ahead: either foot will do.
		side = 1.0 if randf() < 0.5 else -1.0
	player.animator.faked_out(side)
	if wrong.length_squared() > 0.01:
		player.jolt(wrong.normalized(), 0.35)


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
## A carrier who has broken into the open field is run down as a team: the men
## ahead of him take the angle that cuts him off, everybody sprints, the widest
## man ahead keeps him off the sideline, and the last man in front of him stays
## on his feet between him and the goal line until help is there.
func _pursue(pc: PlayController, target: Player, allow_turbo: bool = true) -> void:
	var dist: float = _flat_distance(player.position, target.position)
	var dir: float = float(target.team.attack_dir)
	var loose: bool = target.has_ball and pc.phase == PlayController.Phase.RUN \
			and (target.team != pc.offense or (target.position.x - pc.los_x) * dir >= tuning.ai_pursuit_open_yards)
	var ahead: bool = loose and (player.position.x - target.position.x) * dir > 0.0
	var lead: float = Ball.intercept_time(player.position, target.position, target.velocity, player.max_speed())
	lead = minf(lead, tuning.ai_pursuit_cutoff_lead if ahead else tuning.ai_pursuit_max_lead)
	var aim: Vector3 = target.position + target.velocity * lead
	var turbo: bool = allow_turbo and (loose or dist < tuning.ai_turbo_range)
	var dive_range: float = tuning.ai_dive_range
	if ahead:
		var limit: float = tuning.half_width() - 0.5
		aim.z = clampf(aim.z, -limit, limit)
		var to_goal: float = (tuning.goal_x(target.team.attack_dir) - target.position.x) * dir
		if pc.last_defender(target) == player and to_goal > tuning.ai_last_man_goal_yards and not pc.tackle_help(target, player):
			if not _last_man_noted:
				_last_man_noted = true
				pc.game.add_stat(&"last_man_stands")
			# Nobody behind him: he does not leave his feet for a tackle he might miss.
			dive_range = tuning.ai_last_man_dive_range
			if dist <= tuning.ai_last_man_range:
				# He breaks down: squares up in front of the carrier and lets him
				# come. A carrier who pulls up gets closed on.
				aim = Vector3(player.position.x, 0.0, clampf(target.position.z + target.velocity.z * tuning.ai_last_man_mirror, -limit, limit))
				if target.velocity.x * dir < tuning.run_speed * 0.3:
					aim.x = target.position.x
				turbo = allow_turbo and absf(aim.z - player.position.z) > 2.0
			elif (aim.x - target.position.x) * dir < tuning.ai_last_man_cushion:
				# Never level with him on the way there: always the goal side.
				aim.x = target.position.x + dir * tuning.ai_last_man_cushion
		elif pc.contain_defender(target) == player:
			if not _contain_noted:
				_contain_noted = true
				pc.game.add_stat(&"contains")
			# Outside shoulder: the sideline lane is shut and he is turned back in.
			aim.z = clampf(aim.z + signf(target.position.z) * tuning.ai_contain_width, -limit, limit)
	player.move_input = _direction_to(aim)
	player.wants_turbo = turbo
	if dist < dive_range and _decision_timer <= 0.0:
		_decision_timer = 0.4
		# The sharper defender nearly always leaves his feet: a dive is a big hit,
		# and big hits are what knock the ball loose.
		var dive_chance: float = _sharp(tuning.ai_dive_chance, tuning.ai_edge_dive_chance)
		# A stronger carrier with both arms round the ball runs over a man on his
		# feet: this one goes for his legs, which is harder to run through.
		if target.is_securing() and float(target.ratings.strength - player.ratings.strength) >= tuning.ai_secure_strength_margin:
			dive_chance = maxf(dive_chance, tuning.ai_secure_dive_chance)
		if randf() < dive_chance:
			pc.do_dive(player, _direction_to(target.position + target.velocity * 0.12))
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	elif target.has_ball:
#		_leap_at_carrier(pc, target, dist)


# --- Ball in the air / dead ball ------------------------------------------------

func _think_air(pc: PlayController) -> void:
	var landing: Vector3 = pc.ball.target_point
	if is_offense:
		if pc.ball.intended == player:
			_run_under(pc, landing)
			_go_for_ball(pc)
		elif off_assign.job == OffenseAssignment.Job.BLOCK:
			_block(pc, pc.qb.position)
		elif off_assign.job != OffenseAssignment.Job.QB:
			_run_route(pc)
		return

	if pc.thrown_away:
		# Nothing to go and get: he stays on his job.
		_defense_pocket(pc)
		return
	if not _line_jump_decided:
		# Right by the passer and in the way of it: hands up, and maybe a jump,
		# to get a finger on the ball as it comes out.
		_line_jump_decided = true
		if _in_throwing_lane(pc) and randf() < _sharp(tuning.ai_line_tip_jump_chance, tuning.ai_edge_line_tip_jump_chance):
			pc.game.add_stat(&"line_tip_jumps")
			pc.do_jump(player)
			return
	var react_time: float = _sharp(tuning.ai_ball_react_time, tuning.ai_edge_ball_react_time)
	if pc.ball.intended == pc.read_target:
		# The throw the defense was waiting for.
		react_time *= 1.0 - tuning.ai_scout_react_saving * pc.read
	if pc.live_time - pc.throw_time < react_time:
		_defense_pocket(pc)
		return
	var time_left: float = maxf(pc.ball.flight_time - pc.ball.flight_elapsed, 0.0)
	var dist: float = _flat_distance(player.position, landing)
	if _hits_receiver(pc, landing, time_left):
		return
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
	_seek(_undercut_spot(pc, landing, time_left))
	player.wants_turbo = dist > 1.0
	# Close enough as the ball comes down: go up for it.
	if not _contest_decided and time_left <= tuning.ai_contest_time and dist <= tuning.ai_contest_range:
		_contest_decided = true
		if randf() < _sharp(tuning.ai_contest_chance, tuning.ai_edge_contest_chance):
			pc.do_jump(player)
	_go_for_ball(pc)


## Close to the man who has just thrown, and ahead of him within a stride of
## the line the ball is leaving on.
func _in_throwing_lane(pc: PlayController) -> bool:
	var thrower: Player = pc.ball.thrower
	if thrower == null:
		return false
	var to: Vector3 = player.position - thrower.position
	to.y = 0.0
	if to.length() > tuning.line_tip_jump_range:
		return false
	var line: Vector3 = pc.ball.target_point - thrower.position
	line.y = 0.0
	if line.length_squared() < 0.01:
		return false
	line = line.normalized()
	var along: float = to.dot(line)
	return along > 0.0 and (to - line * along).length() <= 1.5


## Where a defender going for the ball runs to. Mostly where it comes down. But
## a receiver who waits for the ball or comes back to it has his body between
## it and a man behind him, so a defender with the time for it goes round to the
## quarterback's side of him. Decided once per pass; with the receiver running
## away from the throw the two spots are the same.
func _undercut_spot(pc: PlayController, landing: Vector3, time_left: float) -> Vector3:
	var target: Player = pc.ball.intended
	if target == null or target.is_down() or pc.ball.thrower == null:
		return landing
	var incoming: Vector3 = landing - pc.ball.thrower.position
	incoming.y = 0.0
	if incoming.length_squared() < 0.01:
		return landing
	incoming = incoming.normalized()
	var facing_ball: float = clampf(1.0 - target.velocity.dot(incoming) / tuning.run_speed, 0.0, 1.0)
	var spot: Vector3 = landing - incoming * tuning.ai_undercut_depth * facing_ball
	if not _undercut_decided:
		_undercut_decided = true
		var chance: float = _sharp(tuning.ai_undercut_chance, tuning.ai_edge_undercut_chance) \
			* PlayerRatings.blend(player.ratings.coverage, tuning.undercut_coverage_scale_low, tuning.undercut_coverage_scale_high)
		# A man who goes underneath and does not get there has let the catch go:
		# with nobody behind him he wants to be surer of it.
		var margin: float = tuning.ai_undercut_margin
		if def_assign.deep or not _has_help_behind(pc, landing):
			margin += tuning.ai_undercut_safe_margin
		var top: float = player.max_speed() * tuning.turbo_speed_multiplier
		_undercut = _flat_distance(player.position, spot) / maxf(top, 0.01) + margin <= time_left and randf() < chance
		if _undercut:
			pc.game.add_stat(&"undercut_tries")
	return spot if _undercut else landing


## A teammate on his feet deeper than where the pass comes down.
func _has_help_behind(pc: PlayController, landing: Vector3) -> bool:
	for mate: Player in player.team.players:
		if mate != player and not mate.is_down() and (mate.position.x - landing.x) * pc.off_dir > 1.0:
			return true
	return false


## No pass interference: a defender who will not get to the ball can put the
## receiver on the ground before it gets there. He dives at him from close in,
## late in the flight. If he misses he is on the turf and the catch is free.
func _hits_receiver(pc: PlayController, landing: Vector3, time_left: float) -> bool:
	var target: Player = pc.ball.intended
	if _air_hit_decided or target == null or target.is_down() or time_left > tuning.ai_air_hit_time:
		return false
	if _flat_distance(player.position, target.position) > tuning.ai_air_hit_range:
		return false
	# With a play on the ball he makes that instead.
	if _flat_distance(player.position + player.velocity * time_left, landing) <= pc.catch_reach(player, landing):
		return false
	_air_hit_decided = true
	if randf() >= _sharp(tuning.ai_air_hit_chance, tuning.ai_edge_air_hit_chance):
		return false
	takeout_target = target
	hit_man = true
	_contest_decided = true
	pc.game.add_stat(&"air_hit_tries")
	pc.do_dive(player, _direction_to(target.position + target.velocity * 0.12))
	return true


## The pass is his: he gets to where it comes down as it does, to catch it on
## the run. He sprints only if his own pace is not enough, and eases off a
## little for one he would be early for. One he would be very early for (thrown
## short of him, or behind him) he simply goes to and waits.
func _run_under(pc: PlayController, landing: Vector3) -> void:
	var dist: float = _flat_distance(player.position, landing)
	var time_left: float = maxf(pc.ball.flight_time - pc.ball.flight_elapsed, 0.05)
	var pace: float = dist / time_left / maxf(player.max_speed(), 0.01)
	if pace < tuning.ai_catch_pace_min:
		_seek(landing)
		return
	player.wants_turbo = pace > 1.0 and dist > 1.5 and not player.turbo_locked and player.turbo > 0.0
	if player.wants_turbo:
		# No faster on turbo than it takes, either.
		pace /= tuning.turbo_speed_multiplier
	player.move_input = _direction_to(landing) * minf(pace, 1.0)


## The ball is coming down out of his reach: sometimes he leaves his feet for
## it, with a jump if that gets him there and a dive if it takes more. Most of
## the time he just keeps running. Decided once per pass.
func _go_for_ball(pc: PlayController) -> void:
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	_leap_for_ball(pc)
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
	var effort: float = _sharp(tuning.ai_catch_effort_chance, tuning.ai_edge_catch_effort_chance) * PlayerRatings.blend(player.ratings.catching, tuning.catch_scale_low, tuning.catch_scale_high)
	if player.team.human != null:
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
	if _pile_on(pc):
		return
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


## One of his team has dived in the middle of the party: he runs over and dives
## on top of him, the scorer too. They go in one after another, not all at once.
## True while that is what he is doing.
func _pile_on(pc: PlayController) -> bool:
	if pc.pile_target == null or player == pc.pile_target or _piles_answered >= pc.pile_count:
		return false
	if pc.dead_time < pc.pile_time + tuning.pile_on_stagger * float(pc.celebration_variant(player, 4)):
		return true
	var spot: Vector3 = pc.pile_spot()
	var dir: Vector3 = _direction_to(spot)
	var dist: float = _flat_distance(player.position, spot)
	if dist > tuning.pile_on_dive_range:
		player.move_input = dir
		player.wants_turbo = true
		return true
	_piles_answered = pc.pile_count
	_at_party = false
	pc.do_dive(player, dir, pc.pile_dive_speed(dist))
	return true


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
	peel_target = null
	peel_side = 0.0
	_peeling = false
	_last_man_noted = false
	_contain_noted = false
	blown_time = 0.0
	bite_time = 0.0
	pump_bite_from = 0.0
	pump_bite_time = 0.0
	_grasp_decided = false
	_line_jump_decided = false
	takeout_time = -1.0
	takeout_target = null
	technique = Technique.TIGHT
	leverage = 0.0
	_cushion = 0.0
	_undercut_decided = false
	_undercut = false
	_air_hit_decided = false
	hit_man = false
	_escape_rolled = false
	_bail_rolled = false
	_lane_timer = 0.0
	_hurdle_timer = 0.0
	_escaping = false
	run_kind = &""
	_decision_timer = 0.0
	_move_lead = -1.0
	_move_late = 0.0
	_secure_target = null
	_secure_on = false
	_secure_power = false
	_chase_target = null
	_chase_on = false
	_lateral_tackler = null
	_grasp_lateral_decided = false
	_keeper_rolled = false
	_keeper_time = -1.0
	_late_hit_used = false
	cheap_shot_delay = -1.0
	cheap_shot_scorer = true
	_at_party = false
	_piles_answered = 0
	_read_velocity = Vector3.ZERO
	_contest_decided = false
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	_leap = Leap.NONE
#	_leap_target = null
#	_leap_decided = false
#	_ball_leap_decided = false
	_scrambling = false
	_rollout = 0.0
	_keep_ball = false
	_bust_timer = 0.0
	_bust_cooldown = 0.0
	_juke_index = -1
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
