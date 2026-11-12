class_name PlayController
extends Node
## Runs a single play: lineup, snap, handoff, passes, catches, blocks, tackles
## and the whistle. Owns the GameState machine, which decides when simulate()
## and simulate_dead() are called.

## POCKET: QB holds the ball behind the line. AIR: pass in flight.
## RUN: someone is carrying the ball in the open field (any team).
## LOOSE: fumbled, on the turf, anybody's.
enum Phase { POCKET, AIR, RUN, LOOSE }
enum Result { NONE, TACKLED, OUT_OF_BOUNDS, INCOMPLETE, TOUCHDOWN }
## Where a pass is put: at the receiver, ahead of him to run on to, or short of
## him to come back for.
enum Placement { NORMAL, LEAD, UNDER }

var game: Game
var tuning: Tuning
var ball: Ball
var human: HumanController

## Teams as of the snap. An interception does not change these.
var offense: Team
var defense: Team
var off_play: OffensePlay
var def_play: DefensePlay
## The offensive play is being run mirrored left to right.
var off_flipped: bool = false
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
## Who last lost the ball in this play (null = nobody has), how long it has now
## been loose, and how long since anyone last touched it.
var fumbler: Player
var loose_time: float = 0.0
var _loose_untouched: float = 0.0
## The carrier ended the play himself by diving.
var was_dive: bool = false
## Who took it in, on a touchdown. His team celebrates around him.
var scorer: Player
## Seconds since the whistle.
var dead_time: float = 0.0
## Rolled per score: which dance the scorer does, and what shuffles the
## cheers and sulks round the rest.
var celebration_style: int = 0
var celebration_seed: int = 0
## Where on the ring round the scorer each of his teammates stands.
var _party_angles: Dictionary[Player, float] = {}
var live_time: float = 0.0
var throw_time: float = 0.0
var handoff_done: bool = false
var handoff_time: float = 0.0

## This play is a kickoff: `offense` is the receiving team, `returner` the man
## the kick goes to, and there is no quarterback or play call.
var kickoff: bool = false
var returner: Player
## The returner gave himself up in his own end zone, or ran out of the back of it.
var was_touchback: bool = false

var qb: Player
var runner: Player
## Receivers in play order: the person throws to them with pass_1, pass_2, pass_3.
var eligible: Array[Player] = []
var players: Array[Player] = []

## How well the defense recognises this play from having seen it before (0..1),
## and the receiver it expects the ball to go to (or null). See Scout.
var read: float = 0.0
var read_target: Player
## Seconds the quarterback has now had the ball tucked (turbo held) in the pocket.
var qb_tuck_time: float = 0.0
## For the scout: the first receiver thrown to (his place in `eligible`, -1 =
## no pass) and whether the quarterback ran a pass play over the line himself.
var _pass_target: int = -1
var _qb_ran: bool = false
## For a CPU quarterback: how much the clock pushes him to look downfield
## (0..1), and whether this is a last-play heave. See GameSituation.
var qb_urgency: float = 0.0
var heave: bool = false
## For the tests: only this team gets the CPU edge (null = the usual rule).
var edge_team: Team

## Defenders going for the pass in the air. Chosen at the throw.
var ball_breakers: Array[Player] = []
## The defender who had the intended receiver when the ball was thrown, or null.
var ball_coverer: Player
## How the pass in the air was placed, and how many yards short it comes down
## of where the receiver would have run to.
var pass_placement: Placement = Placement.NORMAL
var pass_short: float = 0.0
## Set by pass_aim(): whether the receiver's route cuts or stops before the ball
## would get there, and which way he is then heading (zero if stopped).
var aim_cuts: bool = false
var aim_dir: Vector3 = Vector3.ZERO
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
## `flip` of -1 mirrors the point left to right.
func to_world(point: Vector2, flip: float = 1.0) -> Vector3:
	var limit: float = tuning.half_width() - 1.0
	return Vector3(los_x + off_dir * point.x, 0.0, clampf(off_dir * flip * point.y, -limit, limit))


## `p_flipped` runs the offensive play mirrored left to right.
func line_up(p_off: OffensePlay, p_def: DefensePlay, p_flipped: bool = false) -> void:
	_reset_play()
	off_play = p_off
	def_play = p_def
	off_flipped = p_flipped
	var flip: float = -1.0 if p_flipped else 1.0
	los_x = game.los_x

	var face_off: Vector3 = Vector3(off_dir, 0.0, 0.0)
	for i: int in offense.players.size():
		var player: Player = offense.players[i]
		var assignment: OffenseAssignment = p_off.assignments[mini(i, p_off.assignments.size() - 1)]
		var start: Vector3 = to_world(assignment.start, flip)
		var world_route: PackedVector3Array = PackedVector3Array()
		for waypoint: Vector2 in assignment.route:
			world_route.append(to_world(assignment.start + waypoint, flip))
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

	# Close to the goal line the play as drawn would put its deep men and zones
	# past the back of the end zone: squeeze it up to fit.
	var room: float = (tuning.goal_x(offense.attack_dir) - los_x) * off_dir + tuning.end_zone_depth - tuning.def_back_margin
	var deepest: float = 0.0
	for assignment: DefenseAssignment in p_def.assignments:
		deepest = maxf(deepest, assignment.start.x)
		if assignment.job == DefenseAssignment.Job.ZONE:
			deepest = maxf(deepest, assignment.zone_center.x)

	for i: int in defense.players.size():
		var player: Player = defense.players[i]
		var assignment: DefenseAssignment = p_def.assignments[mini(i, p_def.assignments.size() - 1)]
		var start: Vector3 = to_world(_def_point(assignment.start, deepest, room))
		var target: Player = null
		if assignment.job == DefenseAssignment.Job.MAN and not cover_order.is_empty():
			target = cover_order[mini(assignment.man_target, cover_order.size() - 1)]
			start.z = target.position.z
		player.reset_for_play(start, -face_off)
		# Rushers with a hand in the dirt are linemen; a blitzer from further back
		# comes at full speed.
		if assignment.job == DefenseAssignment.Job.RUSH and assignment.start.x <= tuning.line_depth:
			player.speed_scale = tuning.line_speed_scale
		player.brain.assign_defense(assignment, start, target, to_world(_def_point(assignment.zone_center, deepest, room)))
	_scout_defense()
	_roll_blown_coverage()
	_roll_takeout()
	_roll_play_action()
	var now: GameSituation = game.play_caller.situation(game)
	qb_urgency = now.urgency
	heave = now.heave and not p_off.is_run

	ball.place_on_ground(Vector3(los_x, 0.0, 0.0))
	game.field.set_markers(los_x, game.first_down_x, not game.goal_to_go)
	human.on_line_up()
	_update_markers()


## A defensive play-frame point with its depth squeezed so that a play whose
## deepest point is `deepest` yards off the line fits into `room` yards. The men
## on the line stay where they are and the layers behind them keep their order.
func _def_point(point: Vector2, deepest: float, room: float) -> Vector2:
	var front: float = tuning.line_depth
	if deepest <= room or point.x <= front or deepest <= front:
		return point
	var squeezed: float = lerpf(front, maxf(room, front), (point.x - front) / (deepest - front))
	return Vector2(squeezed, point.y)


## Clears everything left over from the last play.
func _reset_play() -> void:
	offense = game.offense
	defense = game.defense
	off_dir = float(offense.attack_dir)
	off_flipped = false
	kickoff = false
	returner = null
	was_touchback = false
	phase = Phase.POCKET
	ball_dead = true
	result = Result.NONE
	was_sack = false
	was_fumble = false
	fumbler = null
	loose_time = 0.0
	_loose_untouched = 0.0
	was_dive = false
	scorer = null
	dead_time = 0.0
	_party_angles.clear()
	live_time = 0.0
	handoff_done = false
	qb_tuck_time = 0.0
	read = 0.0
	read_target = null
	_pass_target = -1
	_qb_ran = false
	qb_urgency = 0.0
	heave = false
	qb = null
	runner = null
	eligible.clear()
	ball_breakers.clear()
	ball_coverer = null
	pass_placement = Placement.NORMAL
	pass_short = 0.0


# --- Kickoff ---------------------------------------------------------------------

## Lines both teams up for a kickoff to game.offense: the kicking team across
## its kick line, the returner deep, his teammates in two rows in front of him.
func line_up_kickoff() -> void:
	_reset_play()
	kickoff = true
	handoff_done = true
	var kick_dir: int = defense.attack_dir
	los_x = tuning.yard_to_x(kick_dir, tuning.kickoff_yard)
	# Slots 4 and 5 are the receivers (see Roster): the faster one returns it.
	returner = offense.players[mini(4, offense.players.size() - 1)]
	if offense.players.size() > 5 and offense.players[5].ratings.speed > returner.ratings.speed:
		returner = offense.players[5]
	runner = returner
	qb = returner

	off_play = OffensePlay.new()
	off_play.play_name = "Kickoff return"
	off_play.category = OffensePlay.Category.RUN
	off_play.is_run = true
	def_play = DefensePlay.new()
	def_play.play_name = "Kickoff"

	var face_off: Vector3 = Vector3(off_dir, 0.0, 0.0)
	var own_goal: float = tuning.own_goal_x(offense.attack_dir)
	var deep_yard: float = maxf((tuning.kickoff_land_min + tuning.kickoff_land_max) * 0.5, 2.0)
	var lane: float = tuning.field_width / float(maxi(defense.players.size(), 1))
	var row: int = 0
	for player: Player in offense.players:
		var assignment: OffenseAssignment = OffenseAssignment.new()
		var spot: Vector3 = Vector3(own_goal + off_dir * deep_yard, 0.0, 0.0)
		if player == returner:
			assignment.label = "KR"
			assignment.job = OffenseAssignment.Job.RUNNER
		else:
			# Three up front, three behind them, spread across the field.
			assignment.label = "B"
			assignment.job = OffenseAssignment.Job.BLOCK
			@warning_ignore("integer_division")
			var depth: float = tuning.kickoff_land_max + 12.0 + 12.0 * float(row / 3)
			spot = Vector3(own_goal + off_dir * depth, 0.0, (float(row % 3) - 1.0) * tuning.field_width * 0.3)
			row += 1
		off_play.assignments.append(assignment)
		player.reset_for_play(spot, face_off)
		player.brain.assign_offense(assignment, spot, PackedVector3Array())
	for i: int in defense.players.size():
		var player: Player = defense.players[i]
		var assignment: DefenseAssignment = DefenseAssignment.new()
		assignment.label = "K"
		assignment.job = DefenseAssignment.Job.RUSH
		def_play.assignments.append(assignment)
		var spot: Vector3 = Vector3(los_x - float(kick_dir) * tuning.kickoff_run_up, 0.0, (float(i) + 0.5) * lane - tuning.half_width())
		@warning_ignore("integer_division")
		if i == defense.players.size() / 2:
			# The kicker stands over the ball.
			spot = Vector3(los_x - float(kick_dir) * 0.7, 0.0, 0.0)
		player.reset_for_play(spot, -face_off)
		player.brain.assign_defense(assignment, spot, null, spot)

	ball.place_on_ground(Vector3(los_x, 0.0, 0.0))
	game.field.set_markers(los_x, los_x, false)
	human.on_line_up()
	_update_markers()


## The kick: up and away to a random spot in front of (or in) the end zone of
## the receiving team.
func kick_off() -> void:
	ball_dead = false
	live_time = 0.0
	for player: Player in players:
		player.frozen = false
	var kicker: Player = defense.players[0]
	for candidate: Player in defense.players:
		if absf(candidate.position.z) < absf(kicker.position.z):
			kicker = candidate
	var yard: float = randf_range(tuning.kickoff_land_min, tuning.kickoff_land_max)
	var across: float = tuning.half_width() * tuning.kickoff_land_width
	var point: Vector3 = Vector3(tuning.own_goal_x(offense.attack_dir) + off_dir * yard, 0.0, randf_range(-across, across))
	var distance: float = _flat_distance(ball.position, point)
	ball.kick_to(kicker, returner, point, distance / maxf(tuning.kickoff_hang_time, 0.5), tuning)
	phase = Phase.AIR
	throw_time = 0.0
	game.add_stat(&"kickoffs")
	game.audio.play(&"kick")
	game.audio.excite(0.45)
	_update_markers()


## A defense that has seen this before adjusts. A play it recognises: tighter on
## the favourite receiver, sometimes with a second man in front of him. A
## quarterback who keeps running: sometimes a spy. Both take a defender away
## from something else, which is then open.
func _scout_defense() -> void:
	read = 0.0
	read_target = null
	var strength: float = tuning.ai_scout_strength
	# The person's own play call is run as called.
	if strength <= 0.0 or (human.is_active() and human.team == defense):
		return
	read = game.scout.recognition(offense, off_play) * strength
	if off_play.is_run:
		return
	var favourite: int = game.scout.favourite(offense, off_play)
	if read > 0.0 and favourite >= 0 and favourite < eligible.size():
		read_target = eligible[favourite]
	# Defenders who can be handed another job. Deep zones and the line stay.
	var blitzers: Array[Player] = []
	var underneath: Array[Player] = []
	var has_spy: bool = false
	for defender: Player in defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		match assignment.job:
			DefenseAssignment.Job.SPY:
				has_spy = true
			DefenseAssignment.Job.RUSH:
				if assignment.start.x > tuning.line_depth:
					blitzers.append(defender)
			DefenseAssignment.Job.ZONE:
				if not assignment.deep:
					underneath.append(defender)
			DefenseAssignment.Job.MAN:
				# Whoever already has the favourite receiver stays on him.
				if read_target == null or defender.brain.man_target != read_target:
					underneath.append(defender)
	underneath.shuffle()

	if read_target != null and not underneath.is_empty() and randf() < read * tuning.ai_scout_bracket_chance:
		_reassign(underneath.pop_back(), DefenseAssignment.Job.MAN, read_target, true)
		game.add_stat(&"scout_brackets")
	if not has_spy and randf() < game.scout.scramble_threat(offense) * strength:
		# A blitzer is the cheapest spy; otherwise somebody leaves the coverage.
		var spy: Player = null
		if not blitzers.is_empty():
			spy = blitzers.pop_back()
		elif not underneath.is_empty():
			spy = underneath.pop_back()
		if spy != null:
			_reassign(spy, DefenseAssignment.Job.SPY, null, false)
			game.add_stat(&"scout_spies")


## Gives `defender` a new job for this play. He stays where he lined up.
func _reassign(defender: Player, job: DefenseAssignment.Job, target: Player, underneath: bool) -> void:
	var old: DefenseAssignment = defender.brain.def_assign
	var assignment: DefenseAssignment = DefenseAssignment.new()
	assignment.label = old.label
	assignment.start = old.start
	assignment.job = job
	assignment.underneath = underneath
	defender.brain.assign_defense(assignment, defender.brain.start_point, target, Vector3.ZERO)


## Every so often a coverage defender gets it wrong from the snap, and somebody
## runs free.
func _roll_blown_coverage() -> void:
	for defender: Player in defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		var covers: bool = assignment.job == DefenseAssignment.Job.MAN or (assignment.job == DefenseAssignment.Job.ZONE and not assignment.deep)
		var chance: float = tuning.ai_blown_coverage_chance * PlayerRatings.blend(defender.ratings.coverage, tuning.bust_coverage_scale_low, tuning.bust_coverage_scale_high)
		chance *= lerpf(1.0, tuning.ai_edge_blown_scale, team_edge(defense))
		if covers and randf() < chance:
			defender.brain.blown_time = randf_range(tuning.ai_blown_coverage_time_min, tuning.ai_blown_coverage_time_max)
			game.add_stat(&"blown_coverages")


## How much sharper `team`'s CPU players are than the plain ones (0..1). The
## team playing against the person gets Tuning.cpu_skill and the person's own
## teammates get none; with nobody playing, both teams get it.
func team_edge(team: Team) -> float:
	if edge_team != null:
		return tuning.cpu_skill if team == edge_team else 0.0
	if human.is_active() and human.team == team:
		return 0.0
	return tuning.cpu_skill


func cpu_edge(player: Player) -> float:
	return team_edge(player.team)


## Now and then a coverage defender (sometimes two) means to take his man out
## of the play before the ball is thrown: a dive that puts a receiver or the
## back on the turf. The man the offense keeps going to comes first, then the
## back. A dive that misses leaves the defender on the ground and his man free.
func _roll_takeout() -> void:
	if randf() >= tuning.ai_takeout_chance * team_edge(defense):
		return
	var hot: Player = hot_receiver()
	var candidates: Array[Player] = []
	var first: Player = null
	for defender: Player in defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		if defender.brain.blown_time > 0.0:
			continue
		if assignment.job == DefenseAssignment.Job.MAN and defender.brain.man_target != null:
			candidates.append(defender)
			var target: Player = defender.brain.man_target
			if hot != null and target == hot:
				first = defender
			elif target == runner and first == null and randf() < 0.5:
				first = defender
		elif assignment.job == DefenseAssignment.Job.ZONE and not assignment.deep:
			candidates.append(defender)
	if candidates.is_empty():
		return
	candidates.shuffle()
	if first != null:
		candidates.erase(first)
		candidates.push_front(first)
	var hitters: int = 2 if randf() < tuning.ai_takeout_second_chance else 1
	for i: int in mini(hitters, candidates.size()):
		candidates[i].brain.takeout_time = randf_range(tuning.ai_takeout_time_min, tuning.ai_takeout_time_max)
		game.add_stat(&"takeout_plans")


## Play action: the handoff is still being faked.
func faking() -> bool:
	return off_play != null and off_play.play_action and live_time < off_play.handoff_delay


## Play action: decides at the line-up which coverage defenders will come up
## for the faked handoff. An offense that has been running sells it better; a
## play the defense recognises sells it worse.
func _roll_play_action() -> void:
	if not off_play.play_action or runner == null:
		return
	var sold: float = lerpf(tuning.ai_play_action_run_scale_low, tuning.ai_play_action_run_scale_high, game.play_caller.run_share(offense))
	for defender: Player in defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		var chance: float = tuning.ai_play_action_bite_chance * sold * (1.0 - read)
		match assignment.job:
			DefenseAssignment.Job.MAN:
				# The back's own man goes with him anyway.
				if defender.brain.man_target == runner:
					continue
			DefenseAssignment.Job.ZONE:
				if assignment.deep:
					chance *= tuning.ai_play_action_deep_scale
			_:
				continue
		chance *= PlayerRatings.blend(defender.ratings.coverage, tuning.bust_coverage_scale_low, tuning.bust_coverage_scale_high)
		if randf() < chance:
			defender.brain.bite_time = off_play.handoff_delay + randf_range(tuning.ai_play_action_bite_time_min, tuning.ai_play_action_bite_time_max)
			game.add_stat(&"play_action_bites")


func snap() -> void:
	ball_dead = false
	live_time = 0.0
	phase = Phase.POCKET
	for player: Player in players:
		player.frozen = false
	ball.give_to(qb)
	game.add_stat(&"snaps")
	game.audio.say(&"qb_hut")
	game.audio.play(&"snap")
	game.audio.play(&"pads_clash", 0.6)
	_update_markers()


# --- Simulation ------------------------------------------------------------------

## One tick of live play.
func simulate(delta: float) -> void:
	live_time += delta
	# On a kickoff the clock starts at the catch.
	if not (kickoff and phase == Phase.AIR):
		game.tick_clock(delta)
	_try_handoff()
	human.update_live()
	_think_and_move(delta)
	if phase == Phase.POCKET and ball.carrier == qb and qb.is_tucked():
		qb_tuck_time += delta
	else:
		qb_tuck_time = 0.0
	_resolve_contacts(delta)
	_update_drag()
	_guide_pass()
	var arrived: bool = ball.integrate(delta)
	if not ball_dead:
		if arrived:
			_resolve_pass_arrival()
		_check_loose_ball(delta)
		_check_carrier()
	_update_markers()


## One tick after the whistle: everyone can still move and hit.
func simulate_dead(delta: float) -> void:
	dead_time += delta
	human.update_dead()
	_think_and_move(delta)
	_resolve_contacts(delta)
	_spike_ball()
	ball.integrate(delta)


# --- Celebration -----------------------------------------------------------------

## A score: the dance is picked, the scorer's teammates get their places round
## him, and now and then one of the beaten team makes up his mind to spoil it.
func _start_celebration() -> void:
	scorer = ball.carrier
	celebration_style = randi()
	celebration_seed = randi()
	if scorer == null:
		return
	# Each teammate comes in on the side he is already on: places go round the
	# ring in the order the players stand round the scorer now.
	var mates: Array[Player] = []
	var bearings: Dictionary[Player, float] = {}
	for mate: Player in scorer.team.players:
		if mate == scorer:
			continue
		var to: Vector3 = mate.position - scorer.position
		bearings[mate] = atan2(to.z, to.x)
		mates.append(mate)
	mates.sort_custom(func(a: Player, b: Player) -> bool: return bearings[a] < bearings[b])
	var step: float = TAU / float(maxi(mates.size(), 1))
	var turn: Vector2 = Vector2.ZERO
	for i: int in mates.size():
		turn += Vector2.from_angle(bearings[mates[i]] - step * float(i))
	var first: float = turn.angle() if turn.length_squared() > 0.0001 else 0.0
	for i: int in mates.size():
		_party_angles[mates[i]] = first + step * float(i)
	_roll_cheap_shot()


func _roll_cheap_shot() -> void:
	if randf() >= tuning.cheap_shot_chance:
		return
	var sore: Array[Player] = []
	for loser: Player in scorer.team.opponent.players:
		if loser == human.controlled:
			continue
		if _flat_distance(loser.position, scorer.position) <= tuning.cheap_shot_range:
			sore.append(loser)
	if sore.is_empty():
		return
	var hothead: Player = sore.pick_random()
	var brain: PlayerBrain = hothead.brain
	brain.cheap_shot_delay = randf_range(tuning.cheap_shot_delay_min, tuning.cheap_shot_delay_max)
	brain.cheap_shot_scorer = randf() < 0.6


## True after a score for the team that scored.
func is_celebrating(player: Player) -> bool:
	return ball_dead and result == Result.TOUCHDOWN and final_team != null and player.team == final_team


## A teammate's place in the huddle round the scorer.
func celebration_slot(player: Player) -> Vector3:
	if scorer == null:
		return player.position
	var angle: float = _party_angles.get(player, 0.0)
	var spot: Vector3 = scorer.position + Vector3(cos(angle), 0.0, sin(angle)) * tuning.celebration_ring_radius
	var back: float = tuning.end_zone_depth - 1.0
	spot.x = clampf(spot.x, -back, tuning.field_length + back)
	spot.z = clampf(spot.z, -tuning.half_width() - 1.0, tuning.half_width() + 1.0)
	return spot


## Which of `count` ways of taking it this player has, the same all the way
## through one celebration and different the next time.
func celebration_variant(player: Player, count: int) -> int:
	return posmod(player.index + celebration_seed, count)


## The scorer holds the ball up for a moment, then slams it into the turf.
func _spike_ball() -> void:
	if scorer == null or ball.carrier != scorer or dead_time < tuning.celebration_spike_time:
		return
	if not scorer.can_act() or scorer.velocity.length() > 3.0:
		return
	ball.spike(scorer.facing * 2.5 + Vector3(0.0, -15.0, 0.0))
	if scorer.animator != null:
		scorer.animator.spike()
	game.audio.play(&"throw", 0.5, 0.8)
	game.add_stat(&"spikes")


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
	# After the whistle where he looks is up to him, like everybody else.
	if qb == null or ball_dead:
		return
	qb.look_dir = Vector3.ZERO
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
	var gap: float = _flat_distance(qb.position, runner.position)
	if gap <= tuning.handoff_reach:
		ball.give_to(runner, tuning.handoff_time)
		runner.catch_timer = tuning.handoff_time
		runner.flash(Color.WHITE, tuning.possession_flash)
	else:
		# Too far apart to hand it over: the quarterback turns and tosses it.
		var time: float = clampf(gap / tuning.toss_speed, 0.15, 0.6)
		ball.toss_to(runner, time, gap * tuning.toss_height)
		runner.catch_timer = time
		runner.flash(Color.WHITE, tuning.possession_flash)
		var to_runner: Vector3 = runner.position - qb.position
		to_runner.y = 0.0
		qb.facing = to_runner.normalized()
		if qb.animator != null:
			qb.animator.toss()
		game.add_stat(&"tosses")
		game.audio.play(&"throw", 0.3, 0.85)
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
	# The ball is what counts: a score the tick it reaches the goal line, in his
	# hands or with him in the air, and the spot wherever it is when he is down.
	var spot_x: float = _carrier_spot_x(carrier)
	if (dir > 0 and spot_x >= tuning.field_length) or (dir < 0 and spot_x <= 0.0):
		if not game.conversion:
			game.add_stat(&"touchdowns")
		if kickoff:
			game.add_stat(&"kick_return_touchdowns")
		end_play(Result.TOUCHDOWN, spot_x)
		return
	var from_own_goal: float = (x - tuning.own_goal_x(dir)) * float(dir)
	was_touchback = kickoff and carrier.team == offense and from_own_goal <= 0.0
	if absf(carrier.position.z) > tuning.half_width():
		end_play(Result.OUT_OF_BOUNDS, spot_x)
		return
	# Out of the back of his own end zone.
	if was_touchback and from_own_goal <= 1.0 - tuning.end_zone_depth:
		end_play(Result.OUT_OF_BOUNDS, x)
		return
	if carrier.is_grounded():
		# Only his own dive leaves a carrier on the turf with the ball still live,
		# and it stays live until he lands.
		was_dive = true
		was_sack = false
		game.add_stat(&"carrier_dives")
		end_play(Result.TACKLED, x if was_touchback else spot_x)
		return
	if phase == Phase.POCKET and (x - los_x) * off_dir > 0.0:
		# QB crossed the line: no more passing, everyone reacts to a runner.
		phase = Phase.RUN
		if not off_play.is_run:
			_qb_ran = true
			game.add_stat(&"scrambles")


## Where the ball is spotted with `carrier` holding it: the furthest downfield
## (his way) of the ball and himself. A toss still on its way to him is behind
## him, so it is his own position that counts until it arrives.
func _carrier_spot_x(carrier: Player) -> float:
	var x: float = carrier.position.x
	if ball.carrier == carrier and (ball.position.x - x) * float(carrier.team.attack_dir) > 0.0:
		return ball.position.x
	return x


func end_play(p_result: Result, spot_x: float) -> void:
	if ball_dead:
		return
	ball_dead = true
	result = p_result
	game.audio.play(&"whistle", 0.8)
	dead_spot_x = spot_x
	dead_time = 0.0
	for player: Player in players:
		player.look_dir = Vector3.ZERO
	if ball.carrier != null:
		final_team = ball.carrier.team
	else:
		# A fumble nobody recovered stays with the team that lost it.
		final_team = fumbler.team if fumbler != null else offense
	if phase == Phase.LOOSE:
		game.hud.hide_banner()
	if not kickoff:
		var gain: float = (spot_x - los_x) * off_dir if final_team == offense else 0.0
		game.play_caller.record(offense, off_play, gain, live_time)
		game.scout.record(offense, off_play, _pass_target, _qb_ran, gain)
		# For the tests: what a CPU quarterback's runs come to, by why he ran.
		if qb != null and ball.carrier == qb and qb.brain.run_kind != &"":
			var kind: String = qb.brain.run_kind
			game.add_stat(StringName(kind + "_runs"))
			game.add_stat(StringName(kind + "_run_feet"), roundi(gain * 3.0))
			if was_sack:
				game.add_stat(StringName(kind + "_sacks"))
	if ball.carrier != null:
		ball.carrier.release_drag()
	if result == Result.TOUCHDOWN:
		_start_celebration()
	_update_markers()


func result_text() -> String:
	if game.conversion:
		return "2 POINTS!" if result == Result.TOUCHDOWN else "NO GOOD"
	if was_touchback and result != Result.TOUCHDOWN:
		return "TOUCHBACK"
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
	return not ball_dead and phase == Phase.POCKET and ball.carrier == qb and not off_play.is_run and not faking() and (qb.can_act() or qb.is_airborne()) and not qb.is_tucked()


## Furthest the quarterback can throw, in yards.
func pass_range() -> float:
	return PlayerRatings.blend(qb.ratings.power, tuning.pass_range_low, tuning.pass_range_high)


## Pass power for a button held `held` seconds: 0 for a tap, rising to 1 at
## pass_charge_time.
func pass_power(held: float) -> float:
	return clampf(inverse_lerp(tuning.pass_tap_time, tuning.pass_charge_time, held), 0.0, 1.0)


## Flat speed of a pass thrown with `power` (0 = lob, 1 = bullet).
func pass_speed(power: float) -> float:
	var bullet_speed: float = tuning.pass_bullet_speed * PlayerRatings.blend(qb.ratings.power, tuning.pass_speed_scale_low, tuning.pass_speed_scale_high)
	return lerpf(tuning.pass_lob_speed, maxf(bullet_speed, tuning.pass_lob_speed), clampf(power, 0.0, 1.0))


## Where a pass at `speed` to `target` is aimed, before any error: where he will
## be when the ball gets there, moved by the placement. A slower pass is in the
## air longer, so it is thrown further ahead of him.
##
## A receiver still on his route is thrown to where the route has him by then,
## so a ball thrown before a curl comes down at the curl. A lead pass ignores
## the route: it goes on down the line he is running now, and he goes with it.
## An underthrown one comes down short of the cut, toward the quarterback.
func pass_spot(target: Player, speed: float, placement: Placement = Placement.NORMAL) -> Vector3:
	var aim: PackedVector3Array = pass_aim(target, speed, placement)
	return aim[0] + aim[1]


## The two parts of pass_spot(): the spot the placement starts from, and how far
## the placement moves it. Also sets `aim_cuts` and `aim_dir`.
func pass_aim(target: Player, speed: float, placement: Placement) -> PackedVector3Array:
	var on_route: Vector3 = _route_spot(target, speed)
	if not aim_cuts or placement == Placement.LEAD:
		var base: Vector3 = on_route if placement == Placement.NORMAL else _run_spot(target, speed)
		return PackedVector3Array([base, placement_shift(target, base, speed, placement)])
	if placement == Placement.NORMAL:
		return PackedVector3Array([on_route, Vector3.ZERO])
	var home: Vector3 = qb.position - on_route
	home.y = 0.0
	var dist: float = home.length()
	if dist < 0.01:
		return PackedVector3Array([on_route, Vector3.ZERO])
	var back: float = target.max_speed() * (dist / speed) * tuning.pass_under_share
	back = minf(clampf(back, tuning.pass_under_route_min, tuning.pass_under_max), dist * 0.5)
	return PackedVector3Array([on_route, home / dist * back])


## Where the receiver's run, kept up as it is now, meets a pass at `speed`.
func _run_spot(target: Player, speed: float) -> Vector3:
	var lead: float = Ball.intercept_time(qb.position, target.position, target.velocity, speed)
	lead = minf(lead, tuning.pass_max_lead_time)
	return target.position + target.velocity * lead


## Where the receiver's route meets a pass at `speed`. The same as _run_spot()
## for a man who is not on a route.
func _route_spot(target: Player, speed: float) -> Vector3:
	aim_cuts = false
	aim_dir = Vector3(target.velocity.x, 0.0, target.velocity.z).normalized()
	if not target.brain.on_route(self):
		return _run_spot(target, speed)
	var spot: Vector3 = target.position
	for i: int in 4:
		var time: float = minf(_flat_distance(qb.position, spot) / speed, tuning.pass_max_lead_time)
		spot = target.brain.route_ahead(self, time)
	aim_cuts = target.brain.route_ahead_cut
	aim_dir = target.brain.route_ahead_dir
	return spot


## How far a lead pass or an underthrown one is moved from `point`, the regular
## spot: along the receiver's run, by an amount that depends on how fast and how
## steadily he is running, how long the ball is in the air and where the
## nearest defender is.
func placement_shift(target: Player, point: Vector3, speed: float, placement: Placement) -> Vector3:
	if placement == Placement.NORMAL:
		return Vector3.ZERO
	var run: Vector3 = Vector3(target.velocity.x, 0.0, target.velocity.z)
	var pace: float = run.length()
	if pace < 0.5:
		return Vector3.ZERO
	var dir: Vector3 = run / pace
	var moving: float = clampf(pace / tuning.run_speed, 0.0, 1.0)
	# Cutting, stopping or turning round: where he is running now says little
	# about where he is going, so the placement fades out.
	var want: Vector3 = Vector3(target.move_input.x, 0.0, target.move_input.z)
	var steady: float = clampf(dir.dot(want.normalized()), 0.0, 1.0) if want.length_squared() > 0.01 else 0.0
	# Coming back to the quarterback: nothing to lead him into or hold him up from.
	var home: Vector3 = qb.position - target.position
	home.y = 0.0
	if home.length_squared() > 0.01:
		steady *= clampf(1.0 - dir.dot(home.normalized()) / 0.5, 0.0, 1.0)
	# The nearest defender: +1 ahead of him on his run, -1 trailing him.
	var cover: float = 0.0
	var nearest: float = tuning.pass_place_cover_range
	for opponent: Player in target.team.opponent.players:
		if opponent.is_down():
			continue
		var offset: Vector3 = opponent.position - target.position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist < nearest and dist > 0.01:
			nearest = dist
			cover = offset.dot(dir) / dist * (1.0 - dist / tuning.pass_place_cover_range)
	var flight: float = _flat_distance(qb.position, point) / speed
	if placement == Placement.LEAD:
		var headroom: float = maxf(target.max_speed() * tuning.turbo_speed_multiplier - pace, 0.0) * flight
		var ahead: float = (headroom * tuning.pass_lead_share + tuning.pass_lead_base) * moving * steady
		ahead *= 1.0 - tuning.pass_place_cover_scale * cover
		return dir * minf(ahead, tuning.pass_lead_max)
	var back: float = pace * flight * tuning.pass_under_share * moving * steady
	back *= 1.0 + tuning.pass_place_cover_scale * cover
	return -dir * minf(back, tuning.pass_under_max)


## `power` runs from 0 (slow, high lob) to 1 (fast, flat bullet). `placement`
## leads the receiver or underthrows him on purpose.
func throw_ball(target: Player, power: float = 0.5, placement: Placement = Placement.NORMAL) -> void:
	if _thinking:
		_queued_actions.append(throw_ball.bind(target, power, placement))
		return
	if target == null or not can_pass():
		return
	var arm: PlayerRatings = qb.ratings
	var speed: float = pass_speed(power)
	if power < 0.34:
		game.add_stat(&"lobs")
	elif power > 0.66:
		game.add_stat(&"bullets")
	var run: Vector3 = Vector3(target.velocity.x, 0.0, target.velocity.z)
	var aim: PackedVector3Array = pass_aim(target, speed, placement)
	var normal: Vector3 = aim[0]
	var shift: Vector3 = aim[1]
	var point: Vector3 = normal + shift
	# His run as the ball gets there: thrown to a cut in his route, that is the
	# way the route has him going by then (nowhere, if it stops him).
	var arriving: Vector3 = run
	if aim_cuts and placement != Placement.LEAD:
		arriving = aim_dir * target.max_speed()
	pass_placement = placement
	if placement == Placement.LEAD:
		game.add_stat(&"lead_passes")
	elif placement == Placement.UNDER:
		game.add_stat(&"under_passes")
	# Out of his range: the ball comes up short.
	var throw: Vector3 = point - qb.position
	throw.y = 0.0
	var reach: float = pass_range()
	if throw.length() > reach:
		point = qb.position + throw.normalized() * reach
		game.add_stat(&"underthrows")
	else:
		# Sometimes a receiver on the move is led too far: he has to leave his
		# feet to get there. Leading him on purpose makes that more likely.
		var overlead: float = tuning.pass_overlead_chance * PlayerRatings.blend(arm.accuracy, tuning.accuracy_overlead_scale_low, tuning.accuracy_overlead_scale_high)
		if placement == Placement.LEAD:
			overlead *= tuning.pass_lead_overlead_scale
		if placement != Placement.UNDER and arriving.length() > tuning.run_speed * 0.5 and randf() < overlead:
			# Measured from as far as he could get by sprinting flat out, so it
			# cannot simply be run down.
			var flight: float = _flat_distance(qb.position, normal) / speed
			var catch_up: float = maxf(target.max_speed() * tuning.turbo_speed_multiplier - arriving.length(), 0.0) * flight
			point = normal + arriving.normalized() * (catch_up + randf_range(tuning.pass_overlead_min, tuning.pass_overlead_max))
			game.add_stat(&"overthrows")
		elif placement == Placement.LEAD:
			# Judging how far ahead to put it is the hard part: more often long.
			point += shift * randf_range(-tuning.pass_lead_error, 2.0 * tuning.pass_lead_error)
		elif placement == Placement.UNDER:
			# Taking something off it can take off too much.
			point += shift * randf() * tuning.pass_under_error
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
	# How far short of his run the ball comes down, whatever the reason.
	pass_short = 0.0
	if run.length() > 0.5:
		pass_short = maxf((target.position + run * ball.flight_time - ball.target_point).dot(run.normalized()), 0.0)
	_pick_ball_coverer(target)
	_remember_target(target)
	if _pass_target < 0:
		_pass_target = eligible.find(target)
	if (target.position.x - los_x) * off_dir >= tuning.ai_qb_min_depth and target.brain.is_wide_open(self):
		game.add_stat(&"wide_open_throws")
	_pick_ball_breakers()
	phase = Phase.AIR
	throw_time = live_time
	game.add_stat(&"passes")
	game.audio.play(&"throw", 0.45, lerpf(0.9, 1.15, power))
	human.on_throw(target)


func _resolve_pass_arrival() -> void:
	if kickoff:
		# The returner always fields it.
		_take_pass(returner)
		phase = Phase.RUN
		game.add_stat(&"kick_returns")
		game.audio.play(&"catch")
		human.on_carrier_changed(returner)
		return
	var point: Vector3 = ball.target_point
	if pass_short >= 1.0 and ball_coverer != null and ball.intended != null:
		# For the tests: how close the man covering a short ball's receiver ends up.
		game.add_stat(&"short_passes")
		game.add_stat(&"short_pass_cover_feet", roundi(_flat_distance(ball_coverer.position, ball.intended.position) * 3.0))
	var receiver: Player = _best_catcher(offense.players, point, ball.thrower)
	var defender: Player = _best_catcher(defense.players, point, null)

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
			if (opponent.is_airborne() or opponent.dive_reach_timer > 0.0) and _flat_distance(opponent.position, point) <= catch_reach(opponent, point):
				chance -= tuning.contest_penalty
		chance *= _catch_scale(receiver)
		chance = clampf(chance, tuning.catch_min_chance, 1.0)
		if randf() < chance:
			if receiver.is_airborne():
				game.add_stat(&"jump_catches")
			elif receiver.dive_reach_timer > 0.0:
				game.add_stat(&"dive_catches")
			_take_pass(receiver)
			receiver.jolt(receiver.position - ball.thrower.position, 0.5)
			phase = Phase.RUN
			game.add_stat(&"completions")
			if receiver.is_airborne() or receiver.dive_reach_timer > 0.0:
				game.audio.remark(&"announcer_catch", AudioDirector.REMARK_CATCH)
			elif (ball.target_point.x - los_x) * off_dir >= tuning.audio_deep_throw_yards:
				game.audio.remark(&"announcer_throw", AudioDirector.REMARK_THROW)
			game.audio.play(&"catch")
			game.audio.crowd_react(receiver.team, 0.35)
			_add_placement_stat("completions")
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
	game.audio.play(&"incomplete")
	game.audio.crowd_react(defense, 0.5)
	end_play(Result.INCOMPLETE, los_x)


func _catch_scale(player: Player) -> float:
	return PlayerRatings.blend(player.ratings.catching, tuning.catch_scale_low, tuning.catch_scale_high)


## The ball stays where the hands met it and is brought in from there.
func _take_pass(catcher: Player) -> void:
	ball.give_to(catcher, tuning.catch_blend_time)
	catcher.catch_timer = tuning.catch_blend_time
	catcher.flash(Color.WHITE, tuning.possession_flash)


## How far from the spot a pass comes down at `player` can be and still get his
## hands on it: further in the air, further still stretched out in a dive.
func catch_reach(player: Player, point: Vector3) -> float:
	var reach: float = tuning.catch_radius if player.team == offense else tuning.defender_catch_radius
	if player.is_airborne():
		return reach * tuning.jump_catch_radius_scale
	if player.dive_reach_timer > 0.0:
		# A dive only reaches what is in front of him.
		var to: Vector3 = point - player.position
		to.y = 0.0
		if to.dot(player.facing) > -1.0:
			return reach * tuning.dive_catch_radius_scale
	return reach


## Whoever on one team is best placed to take the pass coming down at `point`,
## or null if nobody can reach it. `lookahead` judges them by where they will
## be that many seconds from now.
func _best_catcher(candidates: Array[Player], point: Vector3, exclude: Player, lookahead: float = 0.0) -> Player:
	var best: Player = null
	var best_share: float = 1.0
	for candidate: Player in candidates:
		if candidate == exclude or (candidate.is_down() and candidate.dive_reach_timer <= 0.0):
			continue
		var spot: Vector3 = candidate.position_in(lookahead) if lookahead > 0.0 else candidate.position
		var share: float = _flat_distance(spot, point) / catch_reach(candidate, point)
		if share <= best_share:
			best_share = share
			best = candidate
	return best


## Late in its flight the ball bends toward the hands of whoever is about to
## make a play on it, so a catch ends in the hands and not next to them. Only
## the path changes: the catch is still decided at the landing spot.
func _guide_pass() -> void:
	if ball_dead or ball.state != Ball.State.FLIGHT:
		return
	var left: float = ball.flight_time - ball.flight_elapsed
	if left > tuning.catch_guide_time:
		return
	var point: Vector3 = ball.target_point
	var catcher: Player = _best_catcher(offense.players, point, ball.thrower, left)
	if catcher == null:
		catcher = _best_catcher(defense.players, point, null, left)
	var end: Vector3 = ball.end_position()
	ball.guide_to(catcher.catch_point(end, left) if catcher != null else end, tuning.catch_guide_time)


func _intercept(defender: Player) -> void:
	was_fumble = false
	_take_pass(defender)
	phase = Phase.RUN
	game.add_stat(&"interceptions")
	game.audio.play(&"catch")
	game.audio.play(&"crowd_gasp", 0.8)
	game.audio.shout(&"announcer_interception")
	game.audio.crowd_react(defender.team, 0.9)
	_add_placement_stat("interceptions")
	human.on_carrier_changed(defender)


## Counts what became of a lead pass or an underthrown one, apart from the rest.
func _add_placement_stat(what: String) -> void:
	if pass_placement == Placement.LEAD:
		game.add_stat(StringName("lead_" + what))
	elif pass_placement == Placement.UNDER:
		game.add_stat(StringName("under_" + what))


# --- Actions ---------------------------------------------------------------------

func do_dive(player: Player, dir: Vector3) -> void:
	if _thinking:
		_queued_actions.append(do_dive.bind(player, dir))
		return
	if not player.can_act():
		return
	player.start_dive(dir, _ball_dive_speed(player, dir))
	game.audio.action(player, &"dive")


func do_jump(player: Player) -> void:
	if _thinking:
		_queued_actions.append(do_jump.bind(player))
		return
	if not player.start_jump():
		return
	game.audio.action(player, &"jump")
	# Going up for a pass that comes down nearby: the jump carries him to it.
	var gap: Vector3 = _gap_to_pass(player)
	var left: float = ball.flight_time - ball.flight_elapsed
	if gap != Vector3.INF and gap.length() <= tuning.jump_ball_range and left <= tuning.jump_time + 0.15:
		var top: float = player.max_speed() * tuning.turbo_speed_multiplier
		player.velocity = (gap / maxf(left, 0.15)).limit_length(top)
		if gap.length_squared() > 0.04:
			player.facing = gap.normalized()


## From `player` to where the pass in the air comes down, flat. Vector3.INF when
## there is no pass for him to go for.
func _gap_to_pass(player: Player) -> Vector3:
	if ball_dead or phase != Phase.AIR or ball.state != Ball.State.FLIGHT or player.has_ball:
		return Vector3.INF
	var gap: Vector3 = ball.target_point - player.position
	gap.y = 0.0
	return gap


## Direction for a dive at the pass in the air, or Vector3.ZERO when there is
## none within reach of a dive.
func ball_dive_direction(player: Player) -> Vector3:
	var gap: Vector3 = _gap_to_pass(player)
	if gap == Vector3.INF or gap.length() > tuning.dive_ball_range or gap.length_squared() < 0.01:
		return Vector3.ZERO
	return gap.normalized()


## Direction for a dive at the fumbled ball (where it will be in a moment), or
## Vector3.ZERO when there is none close enough to go for.
func loose_dive_direction(player: Player) -> Vector3:
	if ball_dead or phase != Phase.LOOSE:
		return Vector3.ZERO
	var roll: Vector3 = ball.loose_velocity()
	roll.y = 0.0
	var gap: Vector3 = ball.flat_position() + roll * 0.2 - player.position
	gap.y = 0.0
	if gap.length() > tuning.dive_trigger_range or gap.length_squared() < 0.01:
		return Vector3.ZERO
	return gap.normalized()


## A dive aimed at a pass is paced to end at the ball: a full-speed dive at one
## that is close would sail past it. Returns -1 for an ordinary dive.
func _ball_dive_speed(player: Player, dir: Vector3) -> float:
	var gap: Vector3 = _gap_to_pass(player)
	if gap == Vector3.INF or gap.length() > tuning.dive_ball_range:
		return -1.0
	if gap.length_squared() > 0.01 and gap.normalized().dot(dir) < 0.7:
		return -1.0
	var left: float = ball.flight_time - ball.flight_elapsed
	return clampf(gap.length() / clampf(left, 0.1, tuning.dive_time), tuning.dive_ball_min_speed, tuning.dive_speed)


## `side` is +1 for the player's own left, -1 for his right. With `juke` the
## spin also sidesteps to that side.
func do_spin(player: Player, side: float, juke: bool = false) -> void:
	if _thinking:
		_queued_actions.append(do_spin.bind(player, side, juke))
		return
	if player.start_spin(side, juke):
		game.audio.action(player, &"spin")


func do_stiff_arm(player: Player, side: float) -> void:
	if _thinking:
		_queued_actions.append(do_stiff_arm.bind(player, side))
		return
	if player.start_stiff_arm(side):
		game.audio.action(player, &"spin")


## A shove hits instantly: everyone in a cone in front goes down.
func do_shove(player: Player, dir: Vector3) -> void:
	if _thinking:
		_queued_actions.append(do_shove.bind(player, dir))
		return
	if not player.can_act():
		return
	player.start_shove(dir)
	game.audio.action(player, &"shove")
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
	var reach: float = maxf(maxf(tuning.dive_tackle_radius, tuning.tackle_radius), tuning.player_radius * 2.0)
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
			var min_dist: float = _body_distance(a, b)
			if dist >= min_dist:
				continue
			# Bodies cannot overlap: push both apart equally.
			var normal: Vector3 = offset / dist if dist > 0.001 else Vector3(0.0, 0.0, 1.0)
			var push: Vector3 = normal * (min_dist - dist) * 0.5
			_pushes[i] -= push
			_pushes[j] += push
			if not enemies:
				continue
			if a.is_blocking or b.is_blocking:
				_check_block(a, b, normal, delta)
				_check_block(b, a, -normal, delta)
			else:
				# Nobody is blocking, so nobody gets walled off: whatever speed
				# they run into each other with turns into sliding past.
				var relative: Vector3 = b.velocity - a.velocity
				var closing: float = -relative.dot(normal)
				if closing > 0.0:
					var tangent: Vector3 = Vector3(-normal.z, 0.0, normal.x)
					var side: float = 1.0 if relative.dot(tangent) >= 0.0 else -1.0
					var slip: Vector3 = tangent * side * closing * tuning.body_slip * delta * 0.5
					_pushes[i] -= slip
					_pushes[j] += slip
	for i: int in players.size():
		players[i].position += _pushes[i]
	_separate_bodies()
	if fumbler != null:
		# Half of both teams end up in one heap around a fumble: that takes more
		# than one pass to pull apart.
		_separate_bodies()
		_separate_bodies()


## Closest two players' centres may be, or 0 when they pass through each other:
## a player on the turf can be run over, a dive goes through, and a tackler
## hanging on to the carrier is placed by the drag.
func _body_distance(a: Player, b: Player) -> float:
	if a.is_down() or b.is_down() or a.state == Player.State.DIVING or b.state == Player.State.DIVING:
		return 0.0
	if a.drag_partner == b or b.drag_partner == a:
		return 0.0
	# Teammates and blocks stand off at full width. Other opponents keep less
	# room, so a defender can run at his receiver's shoulder.
	if a.team == b.team or a.is_blocking or b.is_blocking:
		return tuning.player_radius * 2.0
	return tuning.body_radius * 2.0


## A second pass over positions only. Pushing one pair apart can push either of
## them into a third player; this settles most of that within the same tick.
func _separate_bodies() -> void:
	_pushes.fill(Vector3.ZERO)
	for i: int in players.size():
		var a: Player = players[i]
		for j: int in range(i + 1, players.size()):
			var b: Player = players[j]
			var offset: Vector3 = b.position - a.position
			offset.y = 0.0
			var dist: float = offset.length()
			var min_dist: float = _body_distance(a, b)
			if dist >= min_dist:
				continue
			var normal: Vector3 = offset / dist if dist > 0.001 else Vector3(0.0, 0.0, 1.0)
			var push: Vector3 = normal * (min_dist - dist) * 0.5
			_pushes[i] -= push
			_pushes[j] += push
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
					game.audio.remark(&"announcer_hurdle", AudioDirector.REMARK_HURDLE)
					return
			_attempt_tackle(attacker, victim, true)
		elif attacker.has_ball:
			# A carrier's dive is for yards: it knocks nobody over.
			pass
		elif ball_dead or attacker == human.controlled or attacker.brain.takeout_target == victim:
			# Bystanders only get flattened by the person's dives, by late hits
			# and by a defender who set out to take his receiver out. Other CPU
			# dives during the play go for the ball carrier alone.
			if attacker.brain.takeout_target == victim:
				attacker.brain.takeout_target = null
				game.add_stat(&"takeouts")
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
		_finish_tackle(carrier, dir, kind, tackler, big_hit)
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
			game.audio.play(&"stiff_arm")
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
		game.audio.play(&"tackle", 0.7)
		game.impact(tuning.shove_shake * 0.6, 0.4)
	else:
		_finish_tackle(carrier, dir, kind, tackler, big_hit)


## The carrier goes down and the play is over.
func _finish_tackle(carrier: Player, dir: Vector3, kind: PlayerFall.Kind, tackler: Player = null, big: bool = false) -> void:
	var carried: Vector3 = carrier.velocity
	carrier.knock_down(dir * tuning.tackle_knockdown_impulse, tuning.knockdown_time, kind)
	game.add_stat(&"tackles")
	game.audio.hit(tackler, carrier, big)
	if big:
		game.audio.remark(&"announcer_hit", AudioDirector.REMARK_HIT)
	game.impact(tuning.tackle_shake, 1.0)
	game.field.fx.blood_burst(carrier.position, dir, tuning.blood_drops_tackle, true)
	if _try_fumble(carrier, dir, kind, carried):
		return
	was_sack = phase == Phase.POCKET and carrier == qb
	if was_sack:
		game.add_stat(&"sacks")
		game.audio.shout(&"announcer_sack")
		game.audio.crowd_react(carrier.team.opponent, 0.7)
	end_play(Result.TACKLED, _carrier_spot_x(carrier))


## The hit may knock the ball out. It leaves the way he was hit (`dir`), more or
## less, and the play goes on with the ball on the turf until somebody has it.
## `carried` is how fast the carrier was moving when he was hit.
func _try_fumble(carrier: Player, dir: Vector3, kind: PlayerFall.Kind, carried: Vector3) -> bool:
	var chance: float = PlayerRatings.blend(carrier.ratings.security, tuning.fumble_chance_low, tuning.fumble_chance_high)
	if kind != PlayerFall.Kind.WRAP:
		chance *= tuning.fumble_big_hit_scale
	if randf() >= chance:
		return false
	# A standing big hit pops it up, a dive at his legs squirts it out low and
	# fast, and wrestled down it just dribbles out, anywhere.
	var spread: float = tuning.fumble_spread_high
	var pace: float = 1.0
	var lift: float = 1.0
	match kind:
		PlayerFall.Kind.LOW:
			spread = tuning.fumble_spread_low
			pace = 1.2
			lift = 0.6
		PlayerFall.Kind.WRAP:
			spread = tuning.fumble_spread_wrap
			pace = 0.6
			lift = 0.8
	var out: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(randf_range(-spread, spread)))
	var pop: Vector3 = out * randf_range(tuning.fumble_pop_speed_min, tuning.fumble_pop_speed_max) * pace
	pop += Vector3(carried.x, 0.0, carried.z) * tuning.fumble_carry_share
	pop.y = randf_range(tuning.fumble_pop_up_min, tuning.fumble_pop_up_max) * lift
	ball.fumble(pop)
	carrier.flash(Color(1.0, 0.1, 0.1), tuning.fumble_flash)
	game.audio.shout(&"announcer_fumble")
	fumbler = carrier
	phase = Phase.LOOSE
	loose_time = 0.0
	_loose_untouched = 0.0
	game.add_stat(&"fumbles")
	# For the tests: which team lost it.
	game.add_stat(StringName("fumbles_lost_" + carrier.team.short_name.to_lower()))
	game.audio.play(&"crowd_gasp")
	game.hud.show_banner("FUMBLE!")
	for player: Player in players:
		# Anyone in the middle of a dive or a shove (the tackler, mostly) has his
		# hands full for a moment: the ball gets away from the pile first.
		player.ball_grab_cooldown = 0.0 if player.can_act() else tuning.fumble_retry_time * 1.5
		player.brain.on_fumble(self)
	human.on_fumble()
	return true


## Whether `player` knows the ball is out. The person's own player always does.
func sees_loose_ball(player: Player) -> bool:
	return player == human.controlled or player.brain.sees_ball


## The ball is on the loose: it can go out of bounds, and anyone who has seen it
## and gets to it tries to pick it up or fall on it.
func _check_loose_ball(delta: float) -> void:
	if phase != Phase.LOOSE or ball.carrier != null:
		return
	loose_time += delta
	_loose_untouched += delta
	var spot: Vector3 = ball.flat_position()
	if absf(spot.z) > tuning.half_width() or spot.x < -tuning.end_zone_depth or spot.x > tuning.field_length + tuning.end_zone_depth:
		game.add_stat(&"fumbles_out_of_bounds")
		end_play(Result.OUT_OF_BOUNDS, spot.x)
		return
	if loose_time >= tuning.fumble_dead_time:
		game.add_stat(&"fumbles_whistled_dead")
		end_play(Result.TACKLED, spot.x)
		return
	if _loose_untouched < tuning.fumble_pickup_delay or ball.position.y > tuning.fumble_pickup_height:
		return
	var near: Array[Player] = []
	for candidate: Player in players:
		if candidate.ball_grab_cooldown > 0.0 or not sees_loose_ball(candidate):
			continue
		var reach: float = tuning.fumble_scoop_radius
		if _is_diving(candidate):
			reach = tuning.fumble_dive_radius
		elif not candidate.can_act():
			continue
		if _flat_distance(candidate.position, spot) <= reach:
			near.append(candidate)
	# Shuffled first so that neither team wins a dead heat by being listed first.
	near.shuffle()
	near.sort_custom(func(a: Player, b: Player) -> bool: return _flat_distance(a.position, spot) < _flat_distance(b.position, spot))
	if not near.is_empty():
		_grab_loose_ball(near[0])


## Stretched out in a dive, or just landed from one.
func _is_diving(player: Player) -> bool:
	return player.dive_reach_timer > 0.0 and (player.state == Player.State.DIVING or player.is_down())


## `player` gets his hands on the fumbled ball: he has it, or he knocks it on.
func _grab_loose_ball(player: Player) -> void:
	var diving: bool = _is_diving(player)
	var chance: float = tuning.fumble_dive_chance
	if not diving:
		chance = tuning.fumble_scoop_chance - ball.loose_velocity().length() * tuning.fumble_scoop_speed_penalty
	chance = clampf(chance * _catch_scale(player), 0.05, 0.95)
	if randf() >= chance:
		# Off his hands: away from him, more or less, and on it goes.
		var away: Vector3 = ball.flat_position() - player.position
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.01 else player.facing
		away = away.rotated(Vector3.UP, randf_range(-1.2, 1.2))
		var knock: Vector3 = away * randf_range(0.4, 1.0) * tuning.fumble_bobble_speed
		knock += Vector3(player.velocity.x, 0.0, player.velocity.z) * tuning.fumble_carry_share
		knock.y = randf_range(1.5, 4.0)
		ball.fumble(knock)
		player.ball_grab_cooldown = tuning.fumble_retry_time
		player.jolt(away, 0.4)
		_loose_untouched = 0.0
		game.add_stat(&"fumble_bobbles")
		game.audio.play(&"ball_bounce", 0.8)
		return
	_take_pass(player)
	phase = Phase.RUN
	game.hud.hide_banner()
	game.add_stat(&"fumble_recoveries")
	game.audio.play(&"catch")
	game.audio.crowd_react(player.team, 0.85 if player.team != fumbler.team else 0.5)
	if diving:
		game.add_stat(&"fumbles_fallen_on")
	if player.team != fumbler.team:
		was_fumble = true
		game.add_stat(&"fumbles_lost")
	human.on_carrier_changed(player)


## Broken tackle: the defender bounces off and eats turf.
func _break_tackle(tackler: Player, carrier: Player, dir: Vector3) -> void:
	tackler.knock_down(-dir * 3.0, tuning.broken_tackle_stun, PlayerFall.Kind.BOUNCE_OFF)
	carrier.jolt(dir, 0.8)
	game.add_stat(&"broken_tackles")
	game.audio.remark(&"announcer_break", AudioDirector.REMARK_BREAK)
	game.audio.play(&"broken_tackle")
	game.audio.play(&"body_fall", 0.6)
	game.audio.crowd_react(carrier.team, 0.3)
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
	game.audio.hit(attacker, victim, attacker == human.controlled)
	var cheap_shot: bool = attacker.brain.cheap_shot_delay >= 0.0 and is_celebrating(victim)
	if cheap_shot:
		# Counted once, however many he takes out on the way through.
		attacker.brain.cheap_shot_delay = -1.0
		game.add_stat(&"cheap_shots")
		game.audio.crowd_react(attacker.team, 0.6)
	if cheap_shot or attacker == human.controlled or victim == human.controlled:
		game.audio.remark(&"announcer_hit", AudioDirector.REMARK_HIT)
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
		game.audio.play(&"pads_clash", 0.4)
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
		game.audio.remark(&"announcer_pancake", AudioDirector.REMARK_PANCAKE)
		game.audio.play(&"big_hit", 0.6)
		game.audio.play(&"body_fall", 0.6)
		return
	if rusher.block_engaged_time >= rusher.block_shed_time:
		blocker.knock_down(-push_dir * 4.0, tuning.block_beaten_time, PlayerFall.Kind.PANCAKE)
		rusher.block_immune_timer = tuning.block_immune_time
		rusher.block_slow_timer = 0.0
		rusher.block_engaged_time = 0.0


# --- Queries ---------------------------------------------------------------------

## The receiver the offense keeps throwing to, or null if it spreads the ball:
## zone defenders give him extra attention.
func hot_receiver() -> Player:
	# In a play the defense knows, the man that play goes to.
	if read_target != null:
		return read_target
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
	var breakers: int = roundi(lerpf(float(tuning.ai_ball_breakers), float(tuning.ai_edge_ball_breakers), team_edge(defense)))
	for i: int in mini(candidates.size(), breakers):
		ball_breakers.append(candidates[i])


## The defender who has the intended receiver: the one covering him man to man,
## or else the nearest one in coverage who is close enough to count.
func _pick_ball_coverer(target: Player) -> void:
	ball_coverer = null
	var best: float = tuning.ai_cover_beaten_gap
	for defender: Player in defense.players:
		var assign: DefenseAssignment = defender.brain.def_assign
		if defender.is_down() or assign == null or assign.job == DefenseAssignment.Job.RUSH:
			continue
		if assign.job == DefenseAssignment.Job.MAN and defender.brain.man_target == target:
			ball_coverer = defender
			return
		var dist: float = _flat_distance(defender.position, target.position)
		if dist < best:
			best = dist
			ball_coverer = defender


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
