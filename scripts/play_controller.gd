class_name PlayController
extends Node
## Runs a single play: lineup, snap, handoff, passes, catches, blocks, tackles
## and the whistle. Owns the GameState machine, which decides when simulate()
## and simulate_dead() are called.

## POCKET: QB holds the ball behind the line. AIR: pass in flight.
## RUN: someone is carrying the ball in the open field (any team).
## LOOSE: fumbled, on the turf, anybody's.
## TIPPED: a pass off somebody's hands (or past everybody), still in the air.
enum Phase { POCKET, AIR, RUN, LOOSE, TIPPED }
## OUT_OF_PLAY: the ball went over the wall into the stands, or a kick returner
## took a knee at the back of his own end zone. The wall is solid, so there is
## no stepping out of bounds.
enum Result { NONE, TACKLED, OUT_OF_PLAY, INCOMPLETE, TOUCHDOWN }
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
## The defensive play is being run mirrored left to right.
var def_flipped: bool = false
## +1 or -1: the offense's direction along X.
var off_dir: float = 1.0
var los_x: float = 0.0
## A run play aimed inside has a hole: the spot on the line of scrimmage the
## back's path goes through. The blockers move their men away from it and a
## CPU back runs at it. See _find_run_hole and _drive_block.
var has_run_hole: bool = false
var run_hole: Vector3 = Vector3.ZERO
## The back has crossed the line on this play (see _check_hole_burst).
var _hole_crossed: bool = false

var phase: Phase = Phase.POCKET
var ball_dead: bool = true
var result: Result = Result.NONE
var dead_spot_x: float = 0.0
## Team holding the ball at the whistle.
var final_team: Team
var was_sack: bool = false
## The last change of possession in this play was a recovered fumble.
var was_fumble: bool = false
## For the box score (StatBook): who threw the pass and to whom, who came down
## with it, who made the tackle that ended the play, and who knocked the ball
## out, where, and who got it back.
var passer: Player
var pass_intended: Player
## The pass in the air was thrown into the stands on purpose: nobody can get to it.
var thrown_away: bool = false
var catcher: Player
## How far the nearest defender on his feet was from the catcher as he caught
## it (yards; -1 without a catch), and that defender.
var catch_open: float = -1.0
var catch_nearest: Player
## What the defense gambled on this snap: &"blown", &"takeout", &"bracket",
## &"spy", &"bite" (play action), &"bust" (a defender fooled by a cut).
var gambles: Array[StringName] = []
var interceptor: Player
var tackled_by: Player
var fumble_forcer: Player
var fumble_recoverer: Player
var fumble_x: float = 0.0
## Where the returner fielded the kickoff.
var return_from_x: float = 0.0
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
## One of the celebrating team has dived and the rest pile on him: who, when
## (in dead_time), and how many times it has happened since the whistle.
var pile_target: Player
var pile_time: float = 0.0
var pile_count: int = 0
var live_time: float = 0.0
var throw_time: float = 0.0
var handoff_done: bool = false
var handoff_time: float = 0.0
## Teammates of the carrier who follow him to take a lateral, nearest first.
var pitch_men: Array[Player] = []
## Nobody can lateral before this (live_time): the last pitch is on its way.
var _lateral_ready: float = 0.0
## Flea flicker: 0 = the quarterback still has to give it to the back, 1 = the
## back has it, 2 = over (pitched back, kept by the back, or never given). And
## when (live_time) the pitch back is in the quarterback's hands.
var _flick_stage: int = 0
var _flick_ready: float = 0.0

## This play is a kickoff: `offense` is the receiving team, `returner` the man
## the kick goes to, and there is no quarterback or play call.
var kickoff: bool = false
## The scoring team's mascot while it is on the field for the party round the
## scorer (see _invite_mascot); null the rest of the time, when it is away.
var _mascot_guest: Mascot
## Yards beyond the edge of the picture the mascot comes on at, and the furthest
## from the scorer that is looked for.
const MASCOT_ENTRY_MARGIN: float = 2.0
const MASCOT_ENTRY_MAX: float = 45.0
var returner: Player
## The returner gave himself up in his own end zone, or ran out of the back of it.
var was_touchback: bool = false

var qb: Player
var runner: Player
## Receivers in play order: the person throws to them with pass_1 to pass_4.
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
## A pass was caught by the offense on this play.
var _completed: bool = false
## The tipped pass in the air has not been touched by anyone (nobody can catch
## it), and which teams have already had their one try at coming down with it.
var _tip_untouched: bool = false
var _tip_tried: Array[Team] = []
## When (live_time) it was last tipped, and whether no receiver ever got to it.
var _tip_at: float = 0.0
var _tip_bad_throw: bool = false
## Pump fakes: when (live_time) the quarterback can pump again, and how many he
## has thrown this play (each one fools fewer).
var _pump_ready: float = 0.0
var _pump_count: int = 0
## The pass in the air came out badly because the passer was hit as he threw.
var hit_throw: bool = false
## The tackler whose hit a throw is being got away from (see _throws_as_hit).
var _hitter: Player
## Defenders who have had their one go at tipping this pass on its way up.
var _line_tip_tried: Array[Player] = []
## For a CPU quarterback: how much the clock pushes him to look downfield
## (0..1), and whether this is a last-play heave. See GameSituation.
var qb_urgency: float = 0.0
var heave: bool = false
## What Tony, the color commentator, makes of the last touchdown, or nothing.
var touchdown_quip: StringName = &""
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
## Motion before the snap: who may be sent, and what the defense does about it.
var motion: PreSnapMotion
## An audible: the walk from the old line-up to the new one.
var shift: PreSnapShift
## Receivers given another route at the line (see hot_route), and their new job.
var hot_routes: Dictionary[Player, OffenseAssignment] = {}
## The person is picking a receiver for a hot route: every man who can be
## thrown to shows his pass button, on a run play too.
var hot_picking: bool = false
## The offense as the defense lined up on it: the men who can be covered, and
## the order man coverage hands them out in (see DefenseAligner.man_order).
var _seen_players: Array[Player] = []
var _cover_order: PackedInt32Array = PackedInt32Array()

@onready var state_machine: StateMachine = $StateMachine


func setup(p_game: Game) -> void:
	game = p_game
	tuning = game.tuning
	ball = game.ball
	human = game.human
	motion = PreSnapMotion.new(self)
	shift = PreSnapShift.new(self)
	_gather_players()
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


## `p_flipped` runs the offensive play mirrored left to right, `p_def_flipped`
## the defensive one.
func line_up(p_off: OffensePlay, p_def: DefensePlay, p_flipped: bool = false, p_def_flipped: bool = false) -> void:
	_reset_play()
	off_play = p_off
	def_play = p_def
	off_flipped = p_flipped
	def_flipped = p_def_flipped
	var flip: float = -1.0 if p_flipped else 1.0
	var def_flip: float = -1.0 if p_def_flipped else 1.0
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
				# Not the man who leads the carrier through the hole: he has to
				# stay in front of him.
				if assignment.route.is_empty():
					player.speed_scale = tuning.line_speed_scale
			OffenseAssignment.Job.RUNNER:
				if runner == null:
					runner = player
	if qb == null:
		qb = offense.players[0]

	_find_run_hole()

	_list_eligible()

	# The defense lines up on what it sees: where the offense stands, not what
	# its play is going to be. See DefenseAligner.
	var seen: Array[Vector2] = []
	_seen_players.clear()
	for player: Player in offense.players:
		if player == qb:
			continue
		var spot: Vector2 = Vector2((player.position.x - los_x) * off_dir, player.position.z * off_dir)
		seen.append(spot)
		if absf(spot.y) >= DefenseAligner.LINE_WIDTH or spot.x <= DefenseAligner.LINE_DEPTH:
			_seen_players.append(player)
	_cover_order = DefenseAligner.read(seen).man_order()
	var spots: PackedVector2Array = defense_spots(seen)
	var room: float = _def_room()
	var deepest: float = _def_deepest()

	for i: int in defense.players.size():
		var player: Player = defense.players[i]
		var slot: int = mini(i, p_def.assignments.size() - 1)
		var assignment: DefenseAssignment = p_def.assignments[slot]
		var start: Vector3 = to_world(spots[slot])
		var target: Player = man_target_of(assignment, def_flip)
		player.reset_for_play(start, -face_off)
		# Rushers with a hand in the dirt are linemen; a blitzer from further back
		# comes at full speed.
		if assignment.job == DefenseAssignment.Job.RUSH and assignment.start.x <= tuning.line_depth:
			player.speed_scale = tuning.line_speed_scale
		player.brain.assign_defense(assignment, start, target, to_world(_def_point(assignment.zone_center, deepest, room), def_flip))
	_scout_defense()
	_assign_peel()
	_roll_blown_coverage()
	_roll_technique(p_def)
	_roll_takeout()
	_roll_play_action()
	var now: GameSituation = game.play_caller.situation(game)
	qb_urgency = now.urgency
	heave = now.heave and not p_off.is_run

	ball.place_on_ground(Vector3(los_x, 0.0, 0.0))
	game.field.set_markers(los_x, game.first_down_x, not game.goal_to_go)
	motion.prepare()
	human.on_line_up()
	_update_markers()


## An audible: the play is changed at the line. Both teams are lined up for
## the new one and walk to it from where they stand (see PreSnapShift). Not
## once a man is in motion or the ball is live. `by` is the team that called
## it (null: the person's).
func audible(p_off: OffensePlay, p_def: DefensePlay, p_flipped: bool, p_def_flipped: bool, by: Team = null) -> bool:
	if not ball_dead or kickoff or motion.called():
		return false
	if by == null:
		by = human.team
	var from: Dictionary[Player, Vector3] = {}
	for team: Team in [offense, defense]:
		for player: Player in team.players:
			from[player] = player.position
	var mine: Player = human.controlled
	# The defense changing its play does not take the offense's hot routes away.
	var hot: Dictionary[Player, OffenseAssignment] = {}
	if p_off == off_play and p_flipped == off_flipped:
		hot = hot_routes.duplicate()
	line_up(p_off, p_def, p_flipped, p_def_flipped)
	for player: Player in hot:
		_give_hot(player, hot[player])
	# The defender the person had picked is still theirs.
	if mine != null and mine.team == defense:
		human.set_controlled(mine)
	shift.start(from)
	if by == offense:
		_qb_signals(0.0)
	game.add_stat(&"audibles")
	game.rumble.play_team(&"audible", by)
	_update_markers()
	return true


## A hot route: `player` runs `kind` in place of the route the play draws for
## him (`side`: the way a slant breaks, in the play's frame). Only for a man who
## was going out on a route anyway, so who can be thrown to and on which button
## stays as it was. If he is the man who could have been sent in motion, there
## is no motion on this play any more.
func hot_route(player: Player, kind: OffenseAssignment.Hot, side: float) -> bool:
	if not ball_dead or kickoff or player == null or player.team != offense or motion.called():
		return false
	var drawn: OffenseAssignment = player.brain.off_assign
	if drawn == null or drawn.job != OffenseAssignment.Job.ROUTE:
		return false
	_give_hot(player, OffenseAssignment.hot_route(drawn, kind, side))
	# The quarterback points at him: his right is toward +z going toward +x.
	if qb != null:
		_qb_signals(1.0 if (player.position.z - qb.position.z) * off_dir >= 0.0 else -1.0)
	game.add_stat(&"hot_routes")
	game.rumble.play_team(&"audible", offense)
	return true


## `player` runs `hot` in place of the route the play draws for him.
func _give_hot(player: Player, hot: OffenseAssignment) -> void:
	var flip: float = -1.0 if off_flipped else 1.0
	var route: PackedVector3Array = PackedVector3Array()
	for waypoint: Vector2 in hot.route:
		route.append(to_world(hot.start + waypoint, flip))
	player.brain.assign_offense(hot, player.brain.start_point, route)
	hot_routes[player] = hot
	if player == motion.man:
		motion.cancel()


## The quarterback makes his signals for an audible (`side` 0) or for a hot
## route to a man on his right (+1) or his left (-1). See
## PlayerAnimator.audible_call.
func _qb_signals(side: float) -> void:
	if qb == null or qb.animator == null:
		return
	qb.animator.audible_call(side)
	# A little longer than the signals, so he is back in his stance at the end.
	motion.animate_qb(PlayerAnimator.AUDIBLE_CALL_TIME + 0.3)


## The person starts or stops picking a receiver for a hot route.
func set_hot_picking(on: bool) -> void:
	hot_picking = on
	_update_markers()


## The men who can be thrown to, in play order: the order of the pass buttons.
func _list_eligible() -> void:
	eligible.clear()
	for player: Player in offense.players:
		if player != qb and player.brain.off_assign.job != OffenseAssignment.Job.BLOCK:
			eligible.append(player)


## Where the defensive play lines up against an offense standing on `seen`
## (every offensive player but the quarterback, in the offense's frame as it
## is on the field): one point per assignment. See DefenseAligner.
func defense_spots(seen: Array[Vector2]) -> PackedVector2Array:
	var room: float = _def_room()
	var deepest: float = _def_deepest()
	var depths: PackedFloat32Array = PackedFloat32Array()
	for assignment: DefenseAssignment in def_play.assignments:
		depths.append(_def_point(assignment.start, deepest, room).x)
	return DefenseAligner.read(seen).starts(def_play, -1.0 if def_flipped else 1.0, depths)


## The man a MAN assignment covers in the formation the offense lined up in
## (null for any other job). `flip` of -1 is a play run mirrored.
func man_target_of(assignment: DefenseAssignment, flip: float) -> Player:
	if assignment.job != DefenseAssignment.Job.MAN or _cover_order.is_empty():
		return null
	return _seen_players[_cover_order[mini(DefenseAligner.man_index(assignment, flip), _cover_order.size() - 1)]]


## Where on the field the zone of `assignment` is, as a part of `play`.
func zone_world(play: DefensePlay, assignment: DefenseAssignment, flip: float) -> Vector3:
	return to_world(_def_point(assignment.zone_center, _def_deepest(play), _def_room()), flip)


## Close to the goal line the play as drawn would put its deep men and zones
## past the back of the end zone, and is squeezed up to fit (_def_point): the
## yards there are for it, and how deep it is drawn.
func _def_room() -> float:
	return (tuning.goal_x(offense.attack_dir) - los_x) * off_dir + tuning.end_zone_depth - tuning.def_back_margin


## How deep `play` is drawn (the play that was called when it is left out).
func _def_deepest(play: DefensePlay = null) -> float:
	if play == null:
		play = def_play
	var deepest: float = 0.0
	for assignment: DefenseAssignment in play.assignments:
		deepest = maxf(deepest, assignment.start.x)
		if assignment.job == DefenseAssignment.Job.ZONE:
			deepest = maxf(deepest, assignment.zone_center.x)
	return deepest


## Where a run play is aimed: the point at which the back's path as drawn
## crosses the line of scrimmage. Only a path that crosses near the ball makes
## a hole; a toss or a sweep goes round the end.
func _find_run_hole() -> void:
	has_run_hole = false
	_hole_crossed = false
	if not off_play.is_run or runner == null or runner == qb:
		return
	var from: Vector3 = runner.position
	for point: Vector3 in runner.brain.route:
		var before: float = (from.x - los_x) * off_dir
		var after: float = (point.x - los_x) * off_dir
		if before < 0.0 and after >= 0.0:
			var z: float = lerpf(from.z, point.z, -before / (after - before))
			if absf(z) <= tuning.hole_max_width:
				has_run_hole = true
				run_hole = Vector3(los_x, 0.0, z)
			return
		from = point


## The hole still matters: the ball has not gone through the line yet.
func run_hole_live() -> bool:
	if not has_run_hole or ball_dead or runner == null:
		return false
	if ball.carrier != runner and ball.carrier != qb:
		return false
	return (runner.position.x - los_x) * off_dir < 1.0


## A run at a hole is blocked for it. With both teams on their spots:
## - the hole moves to the nearest gap between two linemen (or just outside the
##   last one), since a path drawn straight at a lineman has no way through,
##   and the back's path and his lead blocker's move with it;
## - every lineman belongs to one side of the hole, and so does every defender
##   on the line; a defender standing right in the gap goes to the side that
##   has a lineman free for him;
## - each defender on the line, nearest the hole first, is given the nearest
##   lineman of his side who has nobody yet. A defender too many is nobody's;
## - a lineman too many (a tight end with nobody over him) is given the
##   nearest man behind the line on his side.
## See PlayerBrain._block_hole and _drive_block.
func _assign_run_blocks() -> void:
	if not has_run_hole:
		return
	var line: Array[Player] = []
	for player: Player in offense.players:
		var job: OffenseAssignment = player.brain.off_assign
		if job.job != OffenseAssignment.Job.BLOCK or not job.route.is_empty():
			continue
		var depth: float = (player.position.x - los_x) * off_dir
		if depth >= -(tuning.line_depth + 0.5) and absf(player.position.z) <= tuning.hole_max_width:
			line.append(player)
	if line.is_empty():
		return
	line.sort_custom(func(a: Player, b: Player) -> bool: return a.position.z < b.position.z)
	var front: Array[Player] = []
	for player: Player in defense.players:
		var depth: float = (player.position.x - los_x) * off_dir
		if depth >= 0.0 and depth <= tuning.line_depth + 1.0 and absf(player.position.z - run_hole.z) <= tuning.hole_range + 2.0:
			front.append(player)

	var body: float = tuning.player_radius * 2.0
	var gaps: PackedFloat32Array = PackedFloat32Array([line[0].position.z - body - 0.2])
	for i: int in range(1, line.size()):
		gaps.append((line[i - 1].position.z + line[i].position.z) * 0.5)
	gaps.append(line[line.size() - 1].position.z + body + 0.2)
	var drawn: float = run_hole.z
	var best: float = INF
	for gap: float in gaps:
		# A path drawn well outside the line (a counter, off tackle) stays where
		# it is: the whole line blocks away from it.
		if absf(gap - drawn) > tuning.hole_snap_range:
			continue
		# A defender lined up in the gap itself makes it the worse choice of two.
		var cost: float = absf(gap - drawn)
		for defender: Player in front:
			if absf(defender.position.z - gap) < 0.6:
				cost += 0.4
		if cost < best:
			best = cost
			run_hole.z = gap
	var shift: float = run_hole.z - drawn
	for player: Player in offense.players:
		var job: OffenseAssignment = player.brain.off_assign
		if player != runner and (job.job != OffenseAssignment.Job.BLOCK or job.route.is_empty()):
			continue
		for i: int in player.brain.route.size():
			var point: Vector3 = player.brain.route[i]
			if (point.x - los_x) * off_dir >= -3.5:
				point.z += shift
				player.brain.route[i] = point

	for player: Player in line:
		player.hole_side = 1.0 if player.position.z > run_hole.z else -1.0
	front.sort_custom(func(a: Player, b: Player) -> bool: return absf(a.position.z - run_hole.z) < absf(b.position.z - run_hole.z))
	var taken: PackedInt32Array = PackedInt32Array([0, 0])
	for defender: Player in front:
		var across: float = defender.position.z - run_hole.z
		var side: float = 0.0 if absf(across) < 0.3 else signf(across)
		var taker: Player = null
		var nearest: float = INF
		for player: Player in line:
			if player.block_target != null or (side != 0.0 and player.hole_side != side):
				continue
			var dist: float = absf(player.position.z - defender.position.z)
			if dist < nearest:
				nearest = dist
				taker = player
		if taker != null:
			taker.block_target = defender
			defender.hole_side = taker.hole_side
		else:
			defender.hole_side = side if side != 0.0 else 1.0
		# Each man further out on a side is taken a body further, to make room
		# for the one inside him.
		var slot: int = 0 if defender.hole_side < 0.0 else 1
		defender.hole_clear = tuning.hole_clear_width + float(taken[slot]) * (body + 0.1)
		taken[slot] += 1
	# A lineman with nobody over him goes up to the nearest man behind the
	# line on his side of the hole: the linebacker who would fill it.
	for player: Player in line:
		if player.block_target != null:
			continue
		var pick: Player = null
		var nearest: float = INF
		for defender: Player in defense.players:
			if front.has(defender) or defender.hole_side != 0.0:
				continue
			var depth: float = (defender.position.x - los_x) * off_dir
			var across: float = defender.position.z - run_hole.z
			if depth > tuning.hole_climb_depth or across * player.hole_side < -0.5 or absf(across) > tuning.hole_range:
				continue
			var dist: float = absf(across) + depth * 0.3
			if dist < nearest:
				nearest = dist
				pick = defender
		if pick != null:
			player.block_target = pick
			pick.hole_side = player.hole_side


## The lane at the hole as it is right now: x is the z of its middle and y its
## width clear of bodies, in yards. It is the room between the nearest man of
## either team on his feet at the line on one side of the hole and the nearest
## on the other (the back himself and a blocker running a path in front of him
## do not count), looked for no further than a little past where the blockers
## take their men. A linebacker waiting two yards past the line is not in it:
## he is the next thing the back has to beat.
func hole_lane() -> Vector2:
	var reach: float = tuning.hole_clear_width + 0.5
	var left: float = reach
	var right: float = reach
	for player: Player in players:
		if player == runner or player.is_down():
			continue
		if player.team == offense and (player == qb or not player.brain.route.is_empty()):
			continue
		var depth: float = (player.position.x - los_x) * off_dir
		if depth < -1.5 or depth > 1.2:
			continue
		var across: float = player.position.z - run_hole.z
		if across < 0.0:
			left = minf(left, -across)
		else:
			right = minf(right, across)
	return Vector2(run_hole.z + (right - left) * 0.5, maxf(left + right - tuning.player_radius * 2.0, 0.0))


## The back goes through the line: inside an open lane and in time, he gets his
## burst. Looked at once, on the tick he crosses.
func _check_hole_burst() -> void:
	if _hole_crossed or not has_run_hole or runner == null or ball.carrier != runner:
		return
	if (runner.position.x - los_x) * off_dir < 0.0:
		return
	_hole_crossed = true
	if live_time > tuning.hole_close_time:
		return
	var lane: Vector2 = hole_lane()
	if lane.y < tuning.hole_burst_min_width or absf(runner.position.z - lane.x) > lane.y * 0.5 + 0.2:
		return
	runner.burst_timer = tuning.hole_burst_time
	game.add_stat(&"hole_bursts")
	if runner == human.controlled:
		game.audio.play(&"spin", 0.5, 1.4)
		game.impact(tuning.shove_shake * 0.5, 0.0)
		game.rumble.play(&"hole")


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
	# Injuries last by the play. Only a play that was played counts one off: the
	# teams line up more than once before a snap (play select does it twice).
	if live_time > 0.0:
		for team: Team in [game.home, game.away]:
			for player: Player in team.players:
				player.next_play()
	_dismiss_mascot()
	offense = game.offense
	defense = game.defense
	off_dir = float(offense.attack_dir)
	off_flipped = false
	def_flipped = false
	kickoff = false
	returner = null
	was_touchback = false
	phase = Phase.POCKET
	ball_dead = true
	result = Result.NONE
	was_sack = false
	was_fumble = false
	fumbler = null
	passer = null
	pass_intended = null
	thrown_away = false
	catcher = null
	interceptor = null
	tackled_by = null
	fumble_forcer = null
	fumble_recoverer = null
	fumble_x = 0.0
	return_from_x = 0.0
	loose_time = 0.0
	_loose_untouched = 0.0
	was_dive = false
	scorer = null
	dead_time = 0.0
	pile_target = null
	pile_time = 0.0
	pile_count = 0
	_party_angles.clear()
	live_time = 0.0
	handoff_done = false
	pitch_men.clear()
	_lateral_ready = 0.0
	_flick_stage = 0
	_flick_ready = 0.0
	qb_tuck_time = 0.0
	read = 0.0
	read_target = null
	_pass_target = -1
	_qb_ran = false
	_completed = false
	catch_open = -1.0
	catch_nearest = null
	gambles.clear()
	_tip_untouched = false
	_tip_tried.clear()
	_pump_ready = 0.0
	_pump_count = 0
	hit_throw = false
	_hitter = null
	_line_tip_tried.clear()
	qb_urgency = 0.0
	heave = false
	qb = null
	runner = null
	if motion != null:
		motion.reset()
	if shift != null:
		shift.reset()
	hot_routes.clear()
	hot_picking = false
	eligible.clear()
	ball_breakers.clear()
	ball_coverer = null
	pass_placement = Placement.NORMAL
	pass_short = 0.0


# --- Kickoff ---------------------------------------------------------------------

## The team's two best return men by speed + juke, best first. Level on that,
## the faster one goes first, then the one earlier in the roster.
func kick_returners(team: Team) -> Array[Player]:
	var order: Array[Player] = team.players.duplicate()
	order.sort_custom(func(a: Player, b: Player) -> bool:
		var a_sum: int = a.ratings.speed + a.ratings.juke
		var b_sum: int = b.ratings.speed + b.ratings.juke
		if a_sum != b_sum:
			return a_sum > b_sum
		if a.ratings.speed != b.ratings.speed:
			return a.ratings.speed > b.ratings.speed
		return team.players.find(a) < team.players.find(b))
	return order.slice(0, 2)


## Lines both teams up for a kickoff to game.offense: the kicking team across
## its kick line, the returner deep, his teammates in two rows in front of him.
func line_up_kickoff() -> void:
	_reset_play()
	kickoff = true
	handoff_done = true
	var kick_dir: int = defense.attack_dir
	los_x = tuning.yard_to_x(kick_dir, tuning.kickoff_yard)
	# One of the two best return men, a coin toss from kick to kick.
	returner = kick_returners(offense).pick_random()
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
	# The better blockers go in the row nearest the returner, the rest up
	# front, and who gets which side changes from kick to kick: no side of the
	# field is the strong one every time.
	var blockers: Array[Player] = []
	for player: Player in offense.players:
		if player != returner:
			blockers.append(player)
	blockers.sort_custom(func(a: Player, b: Player) -> bool: return a.ratings.blocking > b.ratings.blocking)
	var lanes: Array[Player] = []
	for from: int in range(0, blockers.size(), 3):
		var line: Array[Player] = blockers.slice(from, from + 3)
		line.shuffle()
		lanes.append_array(line)
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
			var row: int = lanes.find(player)
			@warning_ignore("integer_division")
			var depth: float = tuning.kickoff_land_max + 12.0 + 12.0 * float(row / 3)
			spot = Vector3(own_goal + off_dir * depth, 0.0, (float(row % 3) - 1.0) * tuning.field_width * 0.3)
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
	game.rumble.play(&"kick")
	game.audio.excite(0.45)
	_update_markers()


## Everybody on the field: each team's eight. A mascot is only out there for a
## touchdown party (see _invite_mascot).
func _gather_players() -> void:
	players.clear()
	for team: Team in [game.home, game.away]:
		players.append_array(team.squad)
	for player: Player in players:
		player.play = self


## A defense that has seen this before adjusts. A play it recognises: tighter on
## the favourite receiver, sometimes with a second man in front of him. A
## quarterback who keeps running: sometimes a spy. Both take a defender away
## from something else: a blitz, a zone underneath, a double team. Never the
## only man on a receiver.
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
	var men_on: Dictionary[Player, int] = {}
	for defender: Player in defense.players:
		var man: Player = defender.brain.man_target
		if defender.brain.def_assign.job == DefenseAssignment.Job.MAN and man != null:
			men_on[man] = men_on.get(man, 0) + 1
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
				# Whoever already has the favourite receiver stays on him, and so
				# does the only man another receiver has.
				var man: Player = defender.brain.man_target
				if man != null and man != read_target and men_on.get(man, 0) > 1:
					underneath.append(defender)
	underneath.shuffle()

	if read_target != null and not underneath.is_empty() and randf() < read * tuning.ai_scout_bracket_chance:
		_reassign(underneath.pop_back(), DefenseAssignment.Job.MAN, read_target, true)
		game.add_stat(&"scout_brackets")
		gambles.append(&"bracket")
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
			gambles.append(&"spy")


## Gives `defender` a new job for this play. He stays where he lined up.
func _reassign(defender: Player, job: DefenseAssignment.Job, target: Player, underneath: bool) -> void:
	var old: DefenseAssignment = defender.brain.def_assign
	var assignment: DefenseAssignment = DefenseAssignment.new()
	assignment.label = old.label
	assignment.start = old.start
	assignment.job = job
	assignment.underneath = underneath
	defender.brain.assign_defense(assignment, defender.brain.start_point, target, Vector3.ZERO)


## A back nobody covers man to man would walk out of the backfield free on a
## side that has no flat defender either. The rusher coming from off the line
## nearest him peels: he leaves the rush for the back if the back comes out on
## such a side (PlayerBrain._peels). With a rusher like that on either side of
## the back each one has his own side. The back is read from where the offense
## stands, as the rest of the line-up is.
func _assign_peel() -> void:
	var back: Player = seen_back()
	if back == null:
		return
	# Index 0: the side of negative world z; 1: the other.
	var nearest: Array[Player] = [null, null]
	var open_sides: Array[int] = [0, 1]
	for defender: Player in defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		match assignment.job:
			DefenseAssignment.Job.MAN:
				if defender.brain.man_target == back:
					return
			DefenseAssignment.Job.ZONE:
				if assignment.flat:
					open_sides.erase(0 if defender.brain.zone_center.z < 0.0 else 1)
			DefenseAssignment.Job.RUSH:
				if assignment.start.x > tuning.line_depth:
					var side: int = 0 if defender.position.z < back.position.z else 1
					if nearest[side] == null or _flat_distance(defender.position, back.position) < _flat_distance(nearest[side].position, back.position):
						nearest[side] = defender
	for side: int in open_sides:
		# His own side's rusher, or else the one from across.
		var both: bool = nearest[side] != null and nearest[1 - side] != null
		var peeler: Player = nearest[side] if nearest[side] != null else nearest[1 - side]
		if peeler != null:
			peeler.brain.peel_target = back
			# One side only, unless he is the only one there is for two open sides.
			peeler.brain.peel_side = 0.0 if open_sides.size() == 2 and not both else float(side * 2 - 1)


## The back, as the defense saw the offense line up: the man DefenseAssignment
## .man_target 2 stands for, if he is in the backfield. Null without one.
func seen_back() -> Player:
	if _cover_order.size() < 3:
		return null
	var back: Player = _seen_players[_cover_order[2]]
	if (back.position.x - los_x) * off_dir >= DefenseAligner.BACKFIELD:
		return null
	return back


## A deep zone defender is behind the coverage in this play.
func deep_help() -> bool:
	for defender: Player in defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		if assignment.job == DefenseAssignment.Job.ZONE and assignment.deep:
			return true
	return false


## Every so often a coverage defender gets it wrong from the snap and is late
## to his man. One defender a play at most, and only with a deep zone behind
## him: a mistake costs a completion, not the game.
func _roll_blown_coverage() -> void:
	if not deep_help():
		return
	for defender: Player in defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		var covers: bool = assignment.job == DefenseAssignment.Job.MAN or (assignment.job == DefenseAssignment.Job.ZONE and not assignment.deep)
		var chance: float = tuning.ai_blown_coverage_chance * PlayerRatings.blend(defender.ratings.coverage, tuning.bust_coverage_scale_low, tuning.bust_coverage_scale_high)
		chance *= lerpf(1.0, tuning.ai_edge_blown_scale, team_edge(defense))
		if covers and randf() < chance:
			defender.brain.blown_time = randf_range(tuning.ai_blown_coverage_time_min, tuning.ai_blown_coverage_time_max)
			game.add_stat(&"blown_coverages")
			gambles.append(&"blown")
			return


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


## Man defenders do not all play their man the same way. Most stay tight on his
## deep side. Some play off him and give up what is short, and with a deep
## defender behind them some trail him on the quarterback's side and give up
## what is lofted over them. Each also shades him to one side or the other. A
## man the play draws up at the line is pressing and stays tight.
func _roll_technique(play: DefensePlay) -> void:
	var deep_help: bool = false
	for assignment: DefenseAssignment in play.assignments:
		if assignment.job == DefenseAssignment.Job.ZONE and assignment.deep:
			deep_help = true
	for defender: Player in defense.players:
		var brain: PlayerBrain = defender.brain
		var assignment: DefenseAssignment = brain.def_assign
		if assignment.job != DefenseAssignment.Job.MAN or brain.man_target == null or assignment.underneath:
			continue
		brain.leverage = randf_range(-tuning.ai_cover_leverage, tuning.ai_cover_leverage)
		if assignment.start.x <= tuning.ai_cover_press_depth:
			continue
		var roll: float = randf()
		if roll < tuning.ai_cover_off_chance:
			brain.technique = PlayerBrain.Technique.OFF
			game.add_stat(&"technique_off")
		elif deep_help and roll < tuning.ai_cover_off_chance + tuning.ai_cover_trail_chance:
			brain.technique = PlayerBrain.Technique.TRAIL
			game.add_stat(&"technique_trail")


## Now and then a coverage defender (sometimes two) means to take his man out
## of the play before the ball is thrown: a dive that puts a receiver or the
## back on the turf. The man the offense keeps going to comes first, then the
## back. A dive that misses leaves the defender on the ground and his man free,
## so it is only tried with a deep zone behind the coverage, and not in a play
## that already has a defender late to his man.
func _roll_takeout() -> void:
	if gambles.has(&"blown") or not deep_help():
		return
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
		gambles.append(&"takeout")


## The quarterback cannot throw yet: on play action the handoff is still being
## faked, on a flea flicker the ball has not come back to him.
func faking() -> bool:
	if off_play == null:
		return false
	return (off_play.play_action and live_time < off_play.handoff_delay) or flicking()


## Flea flicker: the ball is still to go to the back and come back from him.
func flicking() -> bool:
	return off_play != null and off_play.flea_flicker and runner != null and runner != qb 			and (_flick_stage < 2 or live_time < _flick_ready)


## Flea flicker: the pitch back is on its way into the quarterback's hands.
func flick_returning() -> bool:
	return flicking() and _flick_stage >= 2


## Seconds after the snap that the fake of this play is over.
func fake_end() -> float:
	if off_play.flea_flicker:
		return off_play.handoff_delay + off_play.flick_delay
	return off_play.handoff_delay


## Play action: the back is still running as if he had been given the ball.
func selling_run() -> bool:
	return off_play != null and off_play.play_action and runner != null and not ball_dead \
			and phase == Phase.POCKET and live_time < off_play.handoff_delay + tuning.play_action_sell_time


## Play action: decides at the line-up which coverage defenders will come up
## for the faked handoff. An offense that has been running sells it better; a
## play the defense recognises sells it worse.
func _roll_play_action() -> void:
	if not (off_play.play_action or off_play.flea_flicker) or runner == null:
		return
	var sold: float = lerpf(tuning.ai_play_action_run_scale_low, tuning.ai_play_action_run_scale_high, game.play_caller.run_share(offense))
	for defender: Player in defense.players:
		var assignment: DefenseAssignment = defender.brain.def_assign
		var chance: float = tuning.ai_play_action_bite_chance * sold * (1.0 - read)
		if off_play.flea_flicker:
			# The back really has the ball: more of them come up for it.
			chance *= tuning.ai_flea_flicker_bite_scale
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
			defender.brain.bite_time = fake_end() + randf_range(tuning.ai_play_action_bite_time_min, tuning.ai_play_action_bite_time_max)
			game.add_stat(&"play_action_bites")
			gambles.append(&"bite")


func snap() -> void:
	shift.finish()
	hot_picking = false
	if not kickoff:
		# A man sent in motion gets the job that goes with where he is by now.
		if motion.settle():
			_list_eligible()
			_find_run_hole()
		# The run is blocked for where everybody stands at the snap.
		_assign_run_blocks()
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
	game.rumble.play_team(&"snap", offense)
	touchdown_quip = &""
	if not kickoff and not game.conversion:
		if heave:
			game.audio.quip(&"color_bold", AudioDirector.QUIP_BOLD)
		elif game.down == 4 and not game.goal_to_go and not game.audio.blaze_down():
			# Nobody punts or kicks here, so going for it is no choice to
			# admire: it is the last chance at the first down. Fourth and
			# twenty has a joke of its own, asked for in the huddle.
			game.audio.quip(&"color_fourth", AudioDirector.QUIP_FOURTH)
	_update_markers()


# --- Simulation ------------------------------------------------------------------

## One tick of live play.
func simulate(delta: float) -> void:
	live_time += delta
	# On a kickoff the clock starts at the catch.
	if not (kickoff and phase == Phase.AIR):
		game.tick_clock(delta)
		if not game.conversion:
			game.stat_book.add_possession(offense, delta)
	_try_handoff()
	_try_flea_flicker()
	human.update_live()
	_pick_pitch_men()
	_think_and_move(delta)
	_check_hole_burst()
	if phase == Phase.POCKET and ball.carrier == qb and qb.is_tucked():
		qb_tuck_time += delta
	else:
		qb_tuck_time = 0.0
	_resolve_contacts(delta)
	_update_drag()
	_guide_pass()
	var arrived: bool = ball.integrate(delta)
	if not ball_dead:
		if ball.hit_wall and phase == Phase.AIR:
			_pass_off_wall()
		if arrived:
			_resolve_pass_arrival()
		else:
			_check_line_tip()
			_check_tipped_ball()
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
	_invite_mascot()
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


## The scoring team's mascot, which is not on the field during a play, turns up
## out of the camera's sight and runs in to join the party round the scorer: it
## is one of the team until the next line-up (_dismiss_mascot).
func _invite_mascot() -> void:
	if _mascot_guest != null or not tuning.mascot_joins_party:
		return
	var team: Team = scorer.team
	var guest: Mascot = team.mascot
	if guest == null or team.players.has(guest):
		return
	var spot: Vector3 = _mascot_entry_spot()
	var toward: Vector3 = scorer.position - spot
	toward.y = 0.0
	guest.reset_for_play(spot, toward.normalized() if toward.length_squared() > 0.01 else Vector3(off_dir, 0.0, 0.0))
	guest.frozen = false
	guest.play = self
	guest.visible = true
	guest.reset_physics_interpolation()
	team.players.append(guest)
	players.append(guest)
	_mascot_guest = guest
	game.add_stat(&"mascot_parties")


## Where the mascot comes onto the field for the party: from the scorer toward
## the camera, MASCOT_ENTRY_MARGIN yards past the first spot where none of it is
## in the picture, so it runs in from the bottom of the screen.
func _mascot_entry_spot() -> Vector3:
	var camera: Camera3D = game.camera_rig.camera
	var from: Vector3 = Vector3(scorer.position.x, 0.0, scorer.position.z)
	var back: Vector3 = camera.global_position - from
	back.y = 0.0
	if back.length_squared() < 1.0:
		back = Vector3(-float(scorer.team.attack_dir), 0.0, 0.0)
	back = back.normalized()
	var head: Vector3 = Vector3(0.0, Stadium.MASCOT_HEIGHT + 0.5, 0.0)
	var away: float = MASCOT_ENTRY_MAX
	for step: int in range(2, int(MASCOT_ENTRY_MAX)):
		var at: Vector3 = from + back * float(step)
		if not camera.is_position_in_frustum(at) and not camera.is_position_in_frustum(at + head):
			away = float(step) + MASCOT_ENTRY_MARGIN
			break
	var spot: Vector3 = Stadium.keep_inside(tuning, from + back * away, tuning.wall_standoff + tuning.mascot_extra_radius)
	spot.y = 0.0
	return spot


## The mascot that joined a celebration leaves the field again.
func _dismiss_mascot() -> void:
	if _mascot_guest == null:
		return
	_mascot_guest.team.players.erase(_mascot_guest)
	players.erase(_mascot_guest)
	_mascot_guest.visible = false
	if human.controlled == _mascot_guest:
		human.set_controlled(null)
	_mascot_guest = null


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
	spot.z = clampf(spot.z, -tuning.side_limit(), tuning.side_limit())
	return spot


## Which of `count` ways of taking it this player has, the same all the way
## through one celebration and different the next time.
func celebration_variant(player: Player, count: int) -> int:
	return posmod(player.index + celebration_seed, count)


## `player` has dived in the middle of his own team's celebration: everybody
## else on the team comes and dives on top of him. Each new dive calls them in
## again.
func start_pile_on(player: Player) -> void:
	if not is_celebrating(player) or player.state != Player.State.DIVING:
		return
	pile_target = player
	pile_time = dead_time
	pile_count += 1
	game.add_stat(&"pile_ons")


## Where the player being piled on ends up: the rest of his dive, and the slide
## after it.
func pile_spot() -> Vector3:
	if pile_target == null:
		return Vector3.ZERO
	var spot: Vector3 = pile_target.position
	var flat: Vector3 = Vector3(pile_target.velocity.x, 0.0, pile_target.velocity.z)
	if pile_target.state == Player.State.DIVING:
		spot += flat * maxf(pile_target.state_timer, 0.0)
	if pile_target.state == Player.State.DIVING or pile_target.is_down():
		spot += flat.normalized() * flat.length_squared() / (2.0 * tuning.knockdown_friction)
	# The wall stops his slide (see Player.keep_on_field).
	spot = Stadium.keep_inside(tuning, spot, tuning.wall_standoff)
	spot.y = 0.0
	return spot


## The speed to leave his feet at for a dive, slide and all, to end `dist` away.
func pile_dive_speed(dist: float) -> float:
	var rub: float = tuning.knockdown_friction
	var air: float = tuning.dive_time
	var speed: float = rub * (sqrt(air * air + 2.0 * dist / rub) - air)
	return clampf(speed, tuning.dive_speed * 0.35, tuning.dive_speed)


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
		var was_dazed: bool = player.is_dazed()
		var injury_count: int = player.injuries
		player.integrate(delta)
		if player.injuries != injury_count:
			# Up from the daze, and not the player they were.
			game.add_stat(&"injuries")
			game.audio.woozy()
		if player.is_dazed() and not was_dazed:
			# A jump dive has just come down, or somebody has hit the wall.
			game.add_stat(&"dazes")
			game.audio.dazed(player)
			game.rumble.play_mine(&"daze", player)
			game.field.fx.daze_impact(player.position, player.facing, player.velocity.length())
		if player.wall_hit > 0.0:
			_splat_on_wall(player)
	game.field.fx.track(players)


## `player` has just been flattened against the wall: the noise, the dust, the
## shake and the crowd, bigger the faster he went in and when it is the
## person's own player.
func _splat_on_wall(player: Player) -> void:
	var mine: bool = player == human.controlled
	var hard: float = clampf(player.wall_hit / 12.0, 0.4, 1.0)
	game.add_stat(&"wall_splats")
	game.audio.play(&"big_hit", hard if mine or player.has_ball else hard * 0.6, 0.7)
	game.audio.play(&"body_fall", hard * 0.8, 0.8)
	var out: Vector3 = Stadium.wall_normal(tuning, player.position.x, player.position.z)
	game.field.fx.daze_impact(player.position - out * 0.6, out, player.wall_hit * 0.5)
	game.impact(tuning.shove_shake * (1.0 if mine else 0.4), 0.5 if mine else 0.0)
	game.rumble.play_mine(&"wall", player, null, hard)
	# Everybody enjoys it but his own fans.
	game.audio.crowd_react(player.team.opponent, 0.35 + 0.25 * hard)
	game.audio.remark(&"announcer_hit", AudioDirector.REMARK_HIT)


## The quarterback looks downfield while he holds the ball in the pocket, even
## when dropping back, and at his target while the pass is in the air.
func _aim_quarterback() -> void:
	# After the whistle where he looks is up to him, like everybody else.
	if qb == null or ball_dead:
		return
	qb.look_dir = Vector3.ZERO
	if phase == Phase.POCKET and ball.carrier == qb:
		# Tucked and running, he faces the way he runs like any other carrier.
		if faking() and runner != null and runner != qb:
			# He turns to the back to put the ball in his belly.
			var to_back: Vector3 = runner.position - qb.position
			to_back.y = 0.0
			qb.look_dir = to_back
		elif not qb.is_tucked():
			qb.look_dir = Vector3(off_dir, 0.0, 0.0)
	elif phase == Phase.AIR and ball.thrower == qb:
		var to_target: Vector3 = ball.target_point - qb.position
		to_target.y = 0.0
		qb.look_dir = to_target
	elif phase == Phase.POCKET and flicking() and ball.carrier == runner:
		# Flea flicker: he drops with his eyes on the back, ready for the pitch.
		var to_ball: Vector3 = runner.position - qb.position
		to_ball.y = 0.0
		qb.look_dir = to_ball


func _try_handoff() -> void:
	if not off_play.is_run or handoff_done or runner == null:
		return
	# A jet sweep is handed over as the man goes by, not on the play's count.
	var passing: bool = motion.jet_sweep and live_time >= 0.1 and _flat_distance(qb.position, runner.position) <= tuning.handoff_reach
	if live_time < off_play.handoff_delay and not passing:
		return
	handoff_done = true
	if ball.carrier != qb or qb.is_down() or runner.is_down() or qb.state == Player.State.DRAGGING:
		return
	_hand_over(qb, runner)
	if motion.jet_sweep:
		runner.burst_timer = tuning.jet_sweep_burst_time
	phase = Phase.RUN
	handoff_time = live_time
	game.add_stat(&"handoffs")
	human.on_carrier_changed(runner)


## `from` gives the ball to his teammate `to`: handed over when they are close
## enough, tossed otherwise. Returns the seconds until it is in his hands.
func _hand_over(from: Player, to: Player) -> float:
	var gap: float = _flat_distance(from.position, to.position)
	to.flash(Color.WHITE, tuning.possession_flash)
	if gap <= tuning.handoff_reach:
		ball.give_to(to, tuning.handoff_time)
		to.catch_timer = tuning.handoff_time
		return tuning.handoff_time
	# Too far apart to hand it over: he turns and tosses it.
	var time: float = clampf(gap / tuning.toss_speed, 0.15, 0.6)
	ball.toss_to(to, time, gap * tuning.toss_height)
	to.catch_timer = time
	var to_him: Vector3 = to.position - from.position
	to_him.y = 0.0
	from.facing = to_him.normalized()
	if from.animator != null:
		from.animator.toss()
	game.add_stat(&"tosses")
	game.audio.play(&"throw", 0.3, 0.85)
	return time


# --- Laterals --------------------------------------------------------------------

## Who `carrier` would pitch the ball to: his nearest teammate on his feet and
## free of a block who is level with him or behind him, or null. Never forward.
func lateral_target(carrier: Player) -> Player:
	var dir: float = float(carrier.team.attack_dir)
	var best: Player = null
	var best_dist: float = tuning.lateral_range
	for mate: Player in carrier.team.players:
		if mate == carrier or not mate.can_act() or mate.block_partner != null:
			continue
		if (mate.position.x - carrier.position.x) * dir > tuning.lateral_forward_slack:
			continue
		var dist: float = _flat_distance(mate.position, carrier.position)
		if dist <= best_dist:
			best_dist = dist
			best = mate
	return best


## `carrier` has the ball in his hands and is in a state to pitch it: on his
## feet, also with a tackler hanging on him.
func can_lateral(carrier: Player) -> bool:
	if ball_dead or carrier == null or ball.carrier != carrier or carrier.catch_timer > 0.0:
		return false
	if live_time < _lateral_ready or (carrier == qb and faking()):
		return false
	return carrier.can_act() or carrier.state == Player.State.DRAGGING


## Chance that a pitch from `carrier` to `target` is a fumble instead (see
## Tuning.lateral_fumble_chance).
func lateral_risk(carrier: Player, target: Player) -> float:
	var chance: float = tuning.lateral_fumble_chance
	if carrier.state == Player.State.DRAGGING:
		chance += tuning.lateral_grasp_fumble_add
	var gap: float = _flat_distance(carrier.position, target.position)
	if gap > tuning.lateral_safe_range:
		chance += tuning.lateral_long_fumble_add * clampf(inverse_lerp(tuning.lateral_safe_range, tuning.lateral_range, gap), 0.0, 1.0)
	# The tacklers on the carrier himself are why he pitches it: only the ones
	# further along the ball's way, or at the man it is going to, count.
	var from: Vector2 = Vector2(carrier.position.x, carrier.position.z)
	var to: Vector2 = Vector2(target.position.x, target.position.z)
	from = from.lerp(to, 0.35)
	for opponent: Player in carrier.team.opponent.players:
		if opponent.is_down() or opponent == carrier.drag_partner:
			continue
		var at: Vector2 = Vector2(opponent.position.x, opponent.position.z)
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, from, to)) < tuning.lateral_pressure_radius:
			chance += tuning.lateral_pressure_fumble_add
	return clampf(chance * RubberBand.bad(carrier.team, game), 0.0, 1.0)


## `carrier` pitches the ball to lateral_target(). False if he cannot, or has
## nobody to pitch it to. It can go wrong (lateral_risk): then it is a fumble.
## From behind the line the play is a run from here on.
func do_lateral(carrier: Player) -> bool:
	if not can_lateral(carrier):
		return false
	var target: Player = lateral_target(carrier)
	if target == null:
		return false
	if _thinking:
		_queued_actions.append(do_lateral.bind(carrier))
		return true
	var risk: float = lateral_risk(carrier, target)
	game.add_stat(&"laterals")
	if game.last_gasp(carrier.team):
		game.add_stat(&"last_gasp_laterals")
	# For the tests: a pitch must never go forward.
	if (target.position.x - carrier.position.x) * float(carrier.team.attack_dir) > tuning.lateral_forward_slack:
		game.add_stat(&"forward_laterals")
	carrier.release_drag()
	if phase == Phase.POCKET:
		phase = Phase.RUN
		handoff_done = true
		handoff_time = live_time
		_flick_stage = 2
	if randf() < risk:
		# Behind him, over his head or at his feet: it is on the turf.
		var out: Vector3 = target.position - carrier.position
		out.y = 0.0
		out = out.normalized().rotated(Vector3.UP, randf_range(-0.5, 0.5)) * tuning.toss_speed * randf_range(0.5, 0.9)
		out += Vector3(carrier.velocity.x, 0.0, carrier.velocity.z) * tuning.fumble_carry_share
		out.y = randf_range(2.0, 4.0)
		if carrier.animator != null:
			carrier.animator.toss()
		game.audio.play(&"throw", 0.3, 0.85)
		ball.fumble(out)
		game.add_stat(&"lateral_fumbles")
		_ball_out(carrier, null)
		carrier.ball_grab_cooldown = tuning.fumble_retry_time
		return true
	_lateral_ready = live_time + _hand_over(carrier, target) + tuning.lateral_cooldown
	game.rumble.play_mine(&"lateral", carrier, target)
	human.on_carrier_changed(target)
	return true


## Picks the carrier's pitch men: the nearest teammates behind him who are not
## in a block. One of them, or three with the clock run out and points needed.
## For a quarterback still behind the line only once he has tucked the ball
## and run, and only a back: his receivers stay on their routes.
func _pick_pitch_men() -> void:
	var before: Array[Player] = pitch_men.duplicate()
	pitch_men.clear()
	var carrier: Player = ball.carrier
	if ball_dead or carrier == null:
		return
	var backs_only: bool = false
	if phase == Phase.POCKET:
		if carrier != qb or off_play == null or off_play.is_run or faking() or qb_tuck_time < tuning.lateral_trail_tuck_time:
			return
		backs_only = true
	elif phase != Phase.RUN:
		return
	var dir: float = float(carrier.team.attack_dir)
	var found: Array[Player] = []
	var scores: Dictionary[Player, float] = {}
	for mate: Player in carrier.team.players:
		if mate == carrier or not mate.can_act() or mate.block_partner != null:
			continue
		if backs_only and mate.ratings.position != "RB":
			continue
		if (mate.position.x - carrier.position.x) * dir > 1.0:
			continue
		var dist: float = _flat_distance(mate.position, carrier.position)
		if dist > tuning.lateral_range:
			continue
		# The men already following him keep the job over one a step nearer.
		scores[mate] = dist - (3.0 if before.has(mate) else 0.0)
		found.append(mate)
	found.sort_custom(func(a: Player, b: Player) -> bool: return scores[a] < scores[b])
	var count: int = 3 if game.last_gasp(carrier.team) else 1
	for i: int in mini(count, found.size()):
		pitch_men.append(found[i])


## Flea flicker: the quarterback gives the ball to the back, who holds it for a
## moment and pitches it back. A quarterback who cannot take it by then leaves
## the back with the ball, and the play is a run.
func _try_flea_flicker() -> void:
	if not off_play.flea_flicker or _flick_stage >= 2 or runner == null or runner == qb:
		return
	if _flick_stage == 0:
		if live_time < off_play.handoff_delay:
			return
		if ball.carrier != qb or qb.is_down() or runner.is_down() or qb.state == Player.State.DRAGGING:
			# No exchange: an ordinary pass play from here, if he still has it.
			_flick_stage = 2
			return
		_flick_stage = 1
		_hand_over(qb, runner)
		game.add_stat(&"flea_flickers")
		return
	# Tackled with it, lost it, or over the line with it: nothing to pitch back.
	if ball.carrier != runner or phase != Phase.POCKET:
		_flick_stage = 2
		return
	if live_time < off_play.handoff_delay + off_play.flick_delay or runner.state == Player.State.DRAGGING:
		return
	_flick_stage = 2
	if qb.can_act() and runner.can_act():
		_flick_ready = live_time + _hand_over(runner, qb)
		return
	phase = Phase.RUN
	handoff_done = true
	handoff_time = live_time
	game.add_stat(&"flea_flicker_kept")
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
		_score_touchdown(carrier, spot_x)
		return
	var from_own_goal: float = (x - tuning.own_goal_x(dir)) * float(dir)
	was_touchback = kickoff and carrier.team == offense and from_own_goal <= 0.0
	# Nobody goes out at the side: the wall is in the way (Player.keep_on_field).
	# A returner at the back of his own end zone has taken the touchback.
	if was_touchback and from_own_goal <= 1.0 - tuning.end_zone_depth:
		end_play(Result.OUT_OF_PLAY, x)
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
			game.audio.quip(&"color_qb_run", AudioDirector.QUIP_QB_RUN)


func _score_touchdown(carrier: Player, spot_x: float) -> void:
	if not game.conversion:
		game.add_stat(&"touchdowns")
	if kickoff:
		game.add_stat(&"kick_return_touchdowns")
	touchdown_quip = _pick_touchdown_quip(carrier, spot_x)
	end_play(Result.TOUCHDOWN, spot_x)


## The color commentator's line for `scorer` crossing the goal line at `spot_x`:
## a walk-in with no defender near him, a long one, or just a score. Only an
## untouched stroll is worth a word when it was not the offense that scored.
## A pass was caught by the offense on this play.
func pass_completed() -> bool:
	return _completed


func _pick_touchdown_quip(scorer: Player, spot_x: float) -> StringName:
	if game.conversion:
		return &""
	var nearest: float = INF
	for opponent: Player in scorer.team.opponent.players:
		if not opponent.is_down():
			nearest = minf(nearest, _flat_distance(opponent.position, scorer.position))
	if nearest >= tuning.audio_walk_in_yards:
		return &"color_td_walk"
	if kickoff or scorer.team != offense:
		return &""
	if (spot_x - los_x) * off_dir >= tuning.audio_long_score_yards:
		return &"color_td_long"
	return &"color_td"


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
		if _completed and result != Result.TOUCHDOWN and gain >= tuning.audio_hot_pass_yards:
			game.audio.quip(&"color_hot", AudioDirector.QUIP_HOT)
		# For the tests: what a CPU quarterback's runs come to, by why he ran.
		if qb != null and ball.carrier == qb and qb.brain.run_kind != &"":
			var kind: String = qb.brain.run_kind
			game.add_stat(StringName(kind + "_runs"))
			game.add_stat(StringName(kind + "_run_feet"), roundi(gain * 3.0))
			if was_sack:
				game.add_stat(StringName(kind + "_sacks"))
	if ball.carrier != null:
		ball.carrier.release_drag()
	game.stat_book.record_play(game)
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
		Result.OUT_OF_PLAY:
			return "OUT OF PLAY"
		Result.INCOMPLETE:
			return "INCOMPLETE"
		Result.TOUCHDOWN:
			return "TOUCHDOWN!"
	return ""


# --- Passing ---------------------------------------------------------------------

## The quarterback has to let go of turbo (untuck the ball) before he can throw.
func can_pass() -> bool:
	return not ball_dead and phase == Phase.POCKET and ball.carrier == qb and not off_play.is_run and not faking() and (qb.can_act() or qb.is_airborne()) and not qb.is_tucked()


## Wrapped up in the pocket with the ball still in his hands: he cannot throw
## properly any more, but he can still try to get rid of it (see throw_ball).
func in_the_grasp() -> bool:
	return not ball_dead and phase == Phase.POCKET and qb != null and ball.carrier == qb and qb.state == Player.State.DRAGGING \
			and off_play != null and not off_play.is_run and not faking()


## Whether `player` stamps into his stance as his feet come set: the
## quarterback, for as long as he has the ball to throw.
func plants_feet(player: Player) -> bool:
	return player == qb and not ball_dead and phase == Phase.POCKET and ball.carrier == qb and off_play != null \
			and not off_play.is_run and not faking() and (player.state == Player.State.NORMAL or player.state == Player.State.JUMPING)


## The quarterback's feet have just come set (see Player.feet_planted).
func on_feet_planted(player: Player) -> void:
	game.field.fx.dust_puff(player.position, Vector3.ZERO, 1.0)


## A body knocked down has just hit the turf, `impact` hard (0..1; see
## PlayerFall.impact).
func on_body_landed(player: Player, impact: float) -> void:
	game.rumble.play_mine(&"land", player, null, impact)


## Pump fake: the arm goes as if he were throwing to the receiver he is looking
## at, and the ball stays in his hand. Some of the coverage stop and break on
## the throw that never comes; a rusher close enough to bat it may jump at it.
## Better coverage men bite less, and every further fake on a play fools fewer.
func pump_fake() -> void:
	if _thinking:
		_queued_actions.append(pump_fake)
		return
	if not can_pass() or qb.is_airborne() or live_time < _pump_ready or eligible.is_empty():
		return
	_pump_ready = live_time + tuning.pump_cooldown
	qb.pump_timer = tuning.pump_time
	game.add_stat(&"pump_fakes")
	game.audio.play(&"throw", 0.3, 0.8)
	var target: Player = eligible[0]
	var best: float = -INF
	for receiver: Player in eligible:
		var to: Vector3 = receiver.position - qb.position
		to.y = 0.0
		var facing: float = to.normalized().dot(qb.facing)
		if not receiver.is_down() and facing > best:
			best = facing
			target = receiver
	var spot: Vector3 = pass_spot(target, pass_speed(0.5))
	var worth: float = pow(tuning.pump_repeat_scale, float(_pump_count))
	_pump_count += 1
	for defender: Player in defense.players:
		if defender == human.controlled or not defender.can_act():
			continue
		var assignment: DefenseAssignment = defender.brain.def_assign
		if assignment == null:
			continue
		var near: bool = _flat_distance(defender.position, qb.position) <= tuning.line_tip_jump_range
		var chance: float = tuning.pump_bite_chance * worth
		match assignment.job:
			DefenseAssignment.Job.MAN:
				pass
			DefenseAssignment.Job.ZONE:
				if assignment.deep:
					chance *= tuning.pump_deep_scale
			_:
				# A rusher or a spy only goes for it from close enough to bat it.
				if not near:
					continue
		chance *= PlayerRatings.blend(defender.ratings.coverage, tuning.bust_coverage_scale_low, tuning.bust_coverage_scale_high)
		chance *= lerpf(1.0, tuning.ai_edge_bust_scale, cpu_edge(defender))
		if randf() >= chance:
			continue
		game.add_stat(&"pump_fake_bites")
		if near:
			# Up he goes, hands in the air, and the quarterback steps round him.
			do_jump(defender)
		else:
			defender.brain.bite_on_pump(live_time, live_time + randf_range(tuning.pump_bite_time_min, tuning.pump_bite_time_max), spot)


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
## An underthrown one ignores the route and his run alike: it comes down short
## of where he is as it is thrown, on the line back to the quarterback, and he
## has to come back for it.
func pass_spot(target: Player, speed: float, placement: Placement = Placement.NORMAL) -> Vector3:
	var aim: PackedVector3Array = pass_aim(target, speed, placement)
	return aim[0] + aim[1]


## The two parts of pass_spot(): the spot the placement starts from, and how far
## the placement moves it. Also sets `aim_cuts` and `aim_dir`.
func pass_aim(target: Player, speed: float, placement: Placement) -> PackedVector3Array:
	if placement == Placement.UNDER:
		aim_cuts = false
		aim_dir = Vector3(target.velocity.x, 0.0, target.velocity.z).normalized()
		var here: Vector3 = target.position
		var home: Vector3 = qb.position - here
		home.y = 0.0
		var dist: float = home.length()
		if dist < 0.01:
			return PackedVector3Array([here, Vector3.ZERO])
		var back: float = target.max_speed() * (dist / speed) * tuning.pass_under_share
		back = minf(clampf(back, tuning.pass_under_min, tuning.pass_under_max), dist * 0.5)
		return PackedVector3Array([here, home / dist * back])
	var on_route: Vector3 = _route_spot(target, speed)
	if aim_cuts and placement == Placement.NORMAL:
		return PackedVector3Array([on_route, Vector3.ZERO])
	var base: Vector3 = on_route if placement == Placement.NORMAL else _run_spot(target, speed)
	return PackedVector3Array([base, placement_shift(target, base, speed, placement)])


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


## How far a lead pass is moved from `point`, the regular spot: along the
## receiver's run, by an amount that depends on how fast and how steadily he is
## running, how long the ball is in the air and where the nearest defender is.
## (An underthrown pass is placed by pass_aim() and does not come through here.)
func placement_shift(target: Player, point: Vector3, speed: float, placement: Placement) -> Vector3:
	if placement != Placement.LEAD:
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
	var headroom: float = maxf(target.max_speed() * tuning.turbo_speed_multiplier - pace, 0.0) * flight
	var ahead: float = (headroom * tuning.pass_lead_share + tuning.pass_lead_base) * moving * steady
	ahead *= 1.0 - tuning.pass_place_cover_scale * cover
	return dir * minf(ahead, tuning.pass_lead_max)


## `power` runs from 0 (slow, high lob) to 1 (fast, flat bullet). `placement`
## leads the receiver or underthrows him on purpose.
##
## `hit` is a throw got away as he is tackled: the only kind he can make once
## he is wrapped up. Now and then it comes out clean (more often from a strong
## quarterback); mostly it floats, comes up well short and goes nowhere near
## where he aimed. Either way he goes down as it leaves, and it is no sack.
func throw_ball(target: Player, power: float = 0.5, placement: Placement = Placement.NORMAL, hit: bool = false) -> void:
	if _thinking:
		_queued_actions.append(throw_ball.bind(target, power, placement, hit))
		return
	if target == null or not (can_pass() or (hit and in_the_grasp())):
		_hitter = null
		return
	var arm: PlayerRatings = qb.ratings
	var bad: bool = false
	if hit:
		game.add_stat(&"hit_throws")
		bad = randf() >= PlayerRatings.blend(arm.strength, tuning.hit_throw_clean_chance_low, tuning.hit_throw_clean_chance_high)
		if bad:
			power = minf(power, tuning.hit_throw_power)
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
	# Every pass sprays a little, more the further it has to travel. Whether his
	# feet are set makes no difference to it.
	var error: float = PlayerRatings.blend(arm.accuracy, tuning.accuracy_error_low, tuning.accuracy_error_high)
	if bad:
		# The arm was hit, or he never got his body into it.
		var intended: Vector3 = point - qb.position
		intended.y = 0.0
		point = qb.position + intended * randf_range(tuning.hit_throw_short_min, tuning.hit_throw_short_max)
		point.y = 0.0
		error += tuning.hit_throw_error
		game.add_stat(&"bad_hit_throws")
	if error > 0.0:
		var miss: float = _flat_distance(qb.position, point) * error
		point += Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU) * miss * sqrt(randf())
	var limit_z: float = tuning.half_width() - 0.5
	var back: float = tuning.end_zone_depth - 1.0
	point.x = clampf(point.x, -back, tuning.field_length + back)
	point.z = clampf(point.z, -limit_z, limit_z)
	# On the run it is thrown with a flourish, and the game takes a breath for
	# the person's own quarterback. (In the air he is busy enough already.) For
	# show only: the pass itself is the same one.
	if qb.feet_set < 1.0 and not hit and qb.state == Player.State.NORMAL:
		var wild: float = 1.0 - qb.feet_set
		qb.start_flair(point - qb.position, wild)
		game.add_stat(&"flair_throws")
		game.field.fx.dust_puff(qb.position, -(point - qb.position), 1.0 + wild)
		if qb == human.controlled:
			game.impact(0.15 * wild, tuning.flair_stop_scale * wild)
			game.camera_rig.punch(tuning.flair_camera_punch * wild)
			game.audio.play(&"spin", 0.7, 1.2)
			game.rumble.play(&"flair", wild)
	ball.throw_to(qb, target, point, speed, tuning)
	ball.wobbly = bad
	hit_throw = bad
	_line_tip_tried.clear()
	# How far short of his run the ball comes down, whatever the reason.
	pass_short = 0.0
	if placement == Placement.UNDER:
		# Short of him whichever way he is going, or standing still.
		pass_short = _flat_distance(target.position + run * ball.flight_time, ball.target_point)
	elif run.length() > 0.5:
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
	passer = qb
	pass_intended = target
	game.add_stat(&"passes")
	game.audio.play(&"throw", 0.45, lerpf(0.9, 1.15, power))
	# A lob is a flick of the wrist, a bullet the whole arm.
	game.rumble.play_mine(&"throw", qb, null, lerpf(0.4, 1.0, power))
	if hit:
		_flatten_passer()
	human.on_throw(target)


## The quarterback has got the ball away with a tackler on him: he goes down
## all the same, after it has left his hand.
func _flatten_passer() -> void:
	var hitter: Player = _hitter if _hitter != null else qb.drag_partner
	_hitter = null
	var dir: Vector3 = -qb.facing
	if hitter != null:
		dir = qb.position - hitter.position
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 0.0001 else -qb.facing
	var kind: PlayerFall.Kind = PlayerFall.Kind.LOW if hitter != null and hitter.state == Player.State.DIVING else PlayerFall.Kind.WRAP
	qb.knock_down(dir * tuning.tackle_knockdown_impulse, tuning.knockdown_time, kind)
	if hitter != null:
		game.audio.hit(hitter, qb, false)
	game.impact(tuning.tackle_shake * 0.7, 0.6)
	game.rumble.play_mine(&"qb_hit", qb, hitter)
	game.audio.play(&"crowd_gasp", 0.6)
	game.field.fx.blood_burst(qb.position, dir, tuning.blood_drops_knockdown, false)


## A pass can be got to while it is still on its way up out of the passer's
## hand: by a defender right by its path whose hands reach as high as it is,
## standing or in the air. He gets one go at it. Tipped, it keeps some of its
## pace, goes up and off line, and is anybody's until it lands.
func _check_line_tip() -> void:
	if phase != Phase.AIR or kickoff or thrown_away or ball.state != Ball.State.FLIGHT:
		return
	var pace: Vector3 = ball.flight_velocity_now()
	if pace.y <= 0.0:
		return
	var spot: Vector3 = ball.flat_position()
	for defender: Player in defense.players:
		if defender.is_down() or defender.state == Player.State.DIVING or _line_tip_tried.has(defender):
			continue
		var up: bool = defender.is_airborne()
		var reach: float = tuning.line_tip_radius * (tuning.jump_catch_radius_scale if up else 1.0)
		if ball.position.y > (tuning.line_tip_jump_height if up else tuning.line_tip_height):
			continue
		if _flat_distance(defender.position, spot) > reach:
			continue
		_line_tip_tried.append(defender)
		if randf() >= (tuning.line_tip_jump_chance if up else tuning.line_tip_chance):
			continue
		var off: Vector3 = Vector3(pace.x, 0.0, pace.z).rotated(Vector3.UP, randf_range(-tuning.line_tip_turn, tuning.line_tip_turn))
		off *= randf_range(tuning.line_tip_speed_share_min, tuning.line_tip_speed_share_max)
		off.y = randf_range(tuning.line_tip_up_min, tuning.line_tip_up_max)
		_tip_tried.clear()
		_tip_bad_throw = false
		game.add_stat(&"line_tips")
		game.audio.play(&"crowd_gasp", 0.7)
		game.audio.crowd_react(defense, 0.4)
		_tip_pass(defender, off)
		return


## The quarterback gets rid of it: over the wall into the stands on `side`
## (+1 or -1 along z), a little downfield. Nobody can catch it; it is incomplete
## when it lands.
func throw_away(side: float) -> void:
	if _thinking:
		_queued_actions.append(throw_away.bind(side))
		return
	if not can_pass():
		return
	var back: float = tuning.end_zone_depth - 1.0
	var point: Vector3 = Vector3(qb.position.x + off_dir * tuning.throwaway_downfield, 0.0, 0.0)
	point.x = clampf(point.x, -back, tuning.field_length + back)
	point.z = (1.0 if side >= 0.0 else -1.0) * (tuning.half_width() + tuning.throwaway_past_sideline)
	# High enough to come down on the seats, clear of the wall on the way.
	var seats: float = game.field.stadium.surface_height(point.x, point.z)
	ball.throw_to(qb, null, point, tuning.throwaway_speed, tuning, maxf(seats, Stadium.WALL_HEIGHT) + 1.0)
	thrown_away = true
	pass_placement = Placement.NORMAL
	pass_short = 0.0
	ball_coverer = null
	ball_breakers.clear()
	phase = Phase.AIR
	throw_time = live_time
	passer = qb
	pass_intended = null
	game.add_stat(&"passes")
	game.add_stat(&"throwaways")
	game.audio.play(&"throw", 0.45)


func _resolve_pass_arrival() -> void:
	if kickoff:
		# The returner always fields it.
		_take_pass(returner)
		return_from_x = returner.position.x
		phase = Phase.RUN
		game.add_stat(&"kick_returns")
		game.audio.play(&"catch")
		game.rumble.play_team(&"catch", returner.team)
		human.on_carrier_changed(returner)
		return
	if thrown_away:
		# Out of everybody's reach: it goes on until it lands.
		_tip_tried.clear()
		_tip_bad_throw = false
		_tip_pass(null, ball.flight_velocity_now())
		return
	var point: Vector3 = ball.target_point
	if pass_short >= 1.0 and ball_coverer != null and ball.intended != null:
		# For the tests: how close the man covering a short ball's receiver ends up.
		game.add_stat(&"short_passes")
		game.add_stat(&"short_pass_cover_feet", roundi(_flat_distance(ball_coverer.position, ball.intended.position) * 3.0))
	_count_arrival(point)
	var receiver: Player = _best_catcher(offense.players, point, ball.thrower)
	var defender: Player = _best_catcher(defense.players, point, null)

	if receiver != null:
		if defender != null:
			# A defender who has got between the receiver and the ball has first go.
			var front: float = in_front(receiver, defender)
			if front > 0.0:
				game.add_stat(&"undercuts")
			if randf() < tuning.interception_chance_front * front * _catch_scale(defender) * RubberBand.bad(offense, game):
				game.add_stat(&"undercut_interceptions")
				_intercept(defender)
				return
		if randf() < catch_chance(receiver, point):
			if receiver.is_airborne():
				game.add_stat(&"jump_catches")
			elif receiver.dive_reach_timer > 0.0:
				game.add_stat(&"dive_catches")
			_complete_pass(receiver)
			return
		if defender != null and randf() < tuning.interception_chance * _catch_scale(defender) * RubberBand.bad(offense, game):
			_intercept(defender)
			return
	elif defender != null and randf() < tuning.interception_chance_open * _catch_scale(defender) * RubberBand.bad(offense, game):
		_intercept(defender)
		return

	# Nobody held on to it. It is not incomplete until it lands: off somebody's
	# hands it is up for grabs on the way down.
	_tip_tried.clear()
	_tip_bad_throw = receiver == null
	var pace: Vector3 = ball.flight_velocity_now()
	pace.y = 0.0
	if defender != null:
		# Batted: up, and anywhere.
		var away: Vector3 = _away_from(defender).rotated(Vector3.UP, randf_range(-1.5, 1.5))
		var bat: Vector3 = away * randf_range(tuning.tip_bat_speed_min, tuning.tip_bat_speed_max)
		bat.y = randf_range(tuning.tip_bat_up_min, tuning.tip_bat_up_max)
		game.add_stat(&"batted_passes")
		_tip_pass(defender, bat)
	elif receiver != null:
		# Dropped: through his hands and on, more or less the way it was going.
		var drop: Vector3 = pace.rotated(Vector3.UP, randf_range(-0.6, 0.6)) * tuning.tip_drop_speed_share
		drop.y = randf_range(tuning.tip_drop_up_min, tuning.tip_drop_up_max)
		game.add_stat(&"drops")
		game.audio.quip(&"color_drop", AudioDirector.QUIP_DROP)
		_tip_pass(receiver, drop)
	else:
		_tip_pass(null, ball.flight_velocity_now())


## Chance that `receiver` holds on to the pass coming down at `point`. Every
## defender crowding him makes the catch harder, and a diving catch much more
## so: stretched out he cannot shield the ball, and a second man close by
## makes it a long shot.
func catch_chance(receiver: Player, point: Vector3) -> float:
	var chance: float = tuning.catch_base_chance
	var diving: bool = receiver.dive_reach_timer > 0.0 and not receiver.is_airborne()
	var incoming: Vector3 = receiver.position - ball.thrower.position
	incoming.y = 0.0
	incoming = incoming.normalized()
	# 1 when he waits for the ball or comes back to it, 0 running away from it.
	var facing_ball: float = clampf(1.0 - receiver.velocity.dot(incoming) / tuning.run_speed, 0.0, 1.0)
	var crowd: int = 0
	for opponent: Player in defense.players:
		if opponent.is_down():
			continue
		var offset: Vector3 = opponent.position - receiver.position
		offset.y = 0.0
		var dist: float = offset.length()
		if diving:
			# The dive took him away from his man: one at the ball counts as well.
			dist = minf(dist, _flat_distance(opponent.position, point))
			if dist < tuning.dive_cover_radius:
				chance -= (1.0 - dist / tuning.dive_cover_radius) * tuning.dive_cover_penalty
			if dist < tuning.dive_crowd_radius:
				crowd += 1
		elif dist < tuning.cover_radius:
			var penalty: float = pow(1.0 - dist / tuning.cover_radius, tuning.cover_penalty_curve) * tuning.cover_penalty
			# A defender on the far side of the receiver has to play through him.
			var behind: float = maxf(offset.normalized().dot(incoming), 0.0) if dist > 0.01 else 0.0
			penalty *= 1.0 - tuning.cover_shield * behind * facing_ball
			# One who has got round in front of him is in the way of it.
			penalty *= 1.0 + tuning.cover_front * in_front(receiver, opponent)
			chance -= penalty
	chance -= maxi(crowd - 1, 0) * tuning.dive_crowd_penalty
	# So does one who went up for the ball.
	for opponent: Player in defense.players:
		if (opponent.is_airborne() or opponent.dive_reach_timer > 0.0) and _flat_distance(opponent.position, point) <= catch_reach(opponent, point):
			chance -= tuning.contest_penalty
	chance *= _catch_scale(receiver)
	chance *= RubberBand.good(receiver.team, game)
	return clampf(chance, tuning.catch_min_chance, 1.0)


## An offensive player has caught the pass, at its spot or off a tip.
func _complete_pass(receiver: Player) -> void:
	_take_pass(receiver)
	receiver.jolt(receiver.position - ball.thrower.position, 0.5)
	phase = Phase.RUN
	_completed = true
	catcher = receiver
	catch_open = INF
	for defender: Player in defense.players:
		var gap: float = _flat_distance(defender.position, receiver.position)
		if not defender.is_down() and gap < catch_open:
			catch_open = gap
			catch_nearest = defender
	game.add_stat(&"completions")
	if receiver.is_airborne() or receiver.dive_reach_timer > 0.0:
		game.audio.remark(&"announcer_catch", AudioDirector.REMARK_CATCH)
		game.audio.quip(&"color_catch", AudioDirector.QUIP_CATCH)
	elif (ball.target_point.x - los_x) * off_dir >= tuning.audio_deep_throw_yards:
		game.audio.remark(&"announcer_throw", AudioDirector.REMARK_THROW)
	game.audio.play(&"catch")
	game.rumble.play_team(&"catch", receiver.team)
	game.audio.crowd_react(receiver.team, 0.35)
	_add_placement_stat("completions")
	human.on_carrier_changed(receiver)


## Flat direction from `player` to the ball, or the way he faces when he is under it.
func _away_from(player: Player) -> Vector3:
	var away: Vector3 = ball.flat_position() - player.position
	away.y = 0.0
	return away.normalized() if away.length_squared() > 0.01 else player.facing


## The pass goes on through the air at `velocity`: off `toucher`'s hands, or
## (null) having got to its spot with nobody there.
func _tip_pass(toucher: Player, velocity: Vector3) -> void:
	ball.tip(velocity)
	phase = Phase.TIPPED
	_tip_untouched = toucher == null
	_tip_at = live_time
	if toucher == null:
		return
	toucher.jolt(-_away_from(toucher), 0.3)
	game.audio.play(&"ball_bounce", 0.8)
	game.rumble.play_mine(&"tip", toucher)
	for player: Player in players:
		player.brain.on_tip()


## The pass in flight has come back off the wall (the ball has turned itself
## into a tipped one): it is live until it lands, and either team can come
## down with it. A kick off the wall is the returner's, as when it lands.
func _pass_off_wall() -> void:
	game.add_stat(&"wall_passes")
	game.audio.play(&"ball_bounce", 0.9, 0.8)
	if kickoff:
		_resolve_pass_arrival()
		return
	_tip_tried.clear()
	_tip_bad_throw = false
	phase = Phase.TIPPED
	_tip_untouched = false
	_tip_at = live_time
	for player: Player in players:
		player.brain.on_tip()


## Whether `player` can get a hand on the tipped ball where it is now.
func reaches_tip(player: Player) -> bool:
	if player.is_down() and player.dive_reach_timer <= 0.0:
		return false
	var spot: Vector3 = ball.flat_position()
	var height: float = tuning.tip_catch_height
	if player.is_airborne():
		height *= tuning.jump_catch_radius_scale
	return ball.position.y <= height and _flat_distance(player.position, spot) <= catch_reach(player, spot)


## A tipped pass is incomplete the moment it touches the turf. Until then
## each team has one try at coming down with it: whoever of its men gets a hand
## to it first.
func _check_tipped_ball() -> void:
	if phase != Phase.TIPPED:
		return
	if ball.grounded:
		game.add_stat(&"incompletions")
		game.audio.play(&"incomplete")
		if _tip_bad_throw:
			# Nobody on his own team could get a hand on it.
			game.audio.quip(&"color_bad_throw", AudioDirector.QUIP_BAD_THROW)
		game.audio.crowd_react(defense, 0.5)
		end_play(Result.INCOMPLETE, los_x)
		return
	if _tip_untouched or live_time - _tip_at < tuning.tip_retry_time:
		return
	var spot: Vector3 = ball.flat_position()
	var near: Array[Player] = []
	for candidate: Player in players:
		if candidate == ball.thrower or _tip_tried.has(candidate.team):
			continue
		if reaches_tip(candidate):
			near.append(candidate)
	if near.is_empty():
		return
	# Shuffled first so that neither team wins a dead heat by being listed first.
	near.shuffle()
	near.sort_custom(func(a: Player, b: Player) -> bool: return _flat_distance(a.position, spot) < _flat_distance(b.position, spot))
	var player: Player = near[0]
	_tip_tried.append(player.team)
	var chance: float = (tuning.tip_catch_chance if player.team == offense else tuning.tip_intercept_chance) * _catch_scale(player)
	# Comeback assist, on the offense's side either way: its catch, or a pick it throws.
	chance *= RubberBand.good(offense, game) if player.team == offense else RubberBand.bad(offense, game)
	if randf() < clampf(chance, 0.0, 0.95):
		if player.team == offense:
			game.add_stat(&"tip_catches")
			_complete_pass(player)
		else:
			game.add_stat(&"tip_interceptions")
			_intercept(player)
		return
	# Off his hands too, and on it goes.
	var knock: Vector3 = _away_from(player).rotated(Vector3.UP, randf_range(-1.5, 1.5)) * randf_range(0.5, 1.0) * tuning.tip_bat_speed_min
	knock += Vector3(player.velocity.x, 0.0, player.velocity.z) * tuning.fumble_carry_share
	knock.y = randf_range(tuning.tip_drop_up_min, tuning.tip_drop_up_max)
	game.add_stat(&"tip_bobbles")
	_tip_pass(player, knock)


## How squarely `defender` stands between `receiver` and the pass (0..1): 1 on
## the line back to the thrower from a receiver who waits for the ball or comes
## back to it, 0 beside him or behind him. A receiver running away from the
## throw has nobody in front of him in this sense: a man on that side of him is
## trailing.
func in_front(receiver: Player, defender: Player) -> float:
	if ball.thrower == null:
		return 0.0
	var incoming: Vector3 = receiver.position - ball.thrower.position
	incoming.y = 0.0
	var offset: Vector3 = defender.position - receiver.position
	offset.y = 0.0
	if incoming.length_squared() < 0.01 or offset.length_squared() < 0.0001:
		return 0.0
	incoming = incoming.normalized()
	var facing_ball: float = clampf(1.0 - receiver.velocity.dot(incoming) / tuning.run_speed, 0.0, 1.0)
	return maxf(-offset.normalized().dot(incoming), 0.0) * facing_ball


## For the tests: how near the nearest defender is to the man the pass is meant
## for as it arrives, what kind of coverage that defender is in, and whether a
## defender has got in front of him. `point` is where it comes down.
func _count_arrival(point: Vector3) -> void:
	var target: Player = ball.intended
	if target == null or target.is_down():
		return
	var near: Player = null
	var gap: float = INF
	for defender: Player in defense.players:
		if defender.is_down():
			continue
		var dist: float = _flat_distance(defender.position, target.position)
		if dist < gap:
			gap = dist
			near = defender
	if near == null:
		return
	var feet: int = roundi(minf(gap, 15.0) * 3.0)
	game.add_stat(&"arrivals")
	game.add_stat(&"arrival_feet", feet)
	game.add_stat(&"arrival_tight" if gap < 1.0 else (&"arrival_step" if gap <= 3.0 else &"arrival_open"))
	if gap <= tuning.cover_radius:
		# Covered: whether any of the men on him has got round in front.
		game.add_stat(&"arrival_covered")
		for defender: Player in defense.players:
			if not defender.is_down() and _flat_distance(defender.position, target.position) <= tuning.cover_radius and in_front(target, defender) >= 0.6:
				game.add_stat(&"arrival_front")
				break
	var deep_ball: bool = (point.x - los_x) * off_dir >= 15.0
	var assign: DefenseAssignment = near.brain.def_assign
	var kind: String = "other"
	if assign != null and assign.job == DefenseAssignment.Job.MAN:
		kind = "man"
	elif assign != null and assign.job == DefenseAssignment.Job.ZONE:
		kind = "deep_zone" if assign.deep else "zone"
	var key: String = "arrival_%s_%s" % ["long" if deep_ball else "short", kind]
	game.add_stat(StringName(key))
	game.add_stat(StringName(key + "_feet"), feet)


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
		if candidate.brain.hit_man:
			# He dived at the receiver, not at the ball.
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
	if ball_dead or thrown_away or ball.state != Ball.State.FLIGHT:
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
	interceptor = defender
	phase = Phase.RUN
	game.add_stat(&"interceptions")
	game.audio.play(&"catch")
	game.audio.play(&"crowd_gasp", 0.8)
	# Felt on both sides: taken away or given away.
	game.rumble.play(&"interception")
	game.audio.shout(&"announcer_interception")
	game.audio.quip(&"color_interception", AudioDirector.QUIP_INTERCEPTION)
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

## `speed` below 0 means the usual one: full, or what gets him to a pass.
func do_dive(player: Player, dir: Vector3, speed: float = -1.0) -> void:
	if _thinking:
		_queued_actions.append(do_dive.bind(player, dir, speed))
		return
	if not player.can_act():
		return
	# After the whistle (the party, a pile-on) a dive costs no stamina.
	player.start_dive(dir, speed if speed >= 0.0 else _ball_dive_speed(player, dir), ball_dead or is_celebrating(player))
	# A dive into the party is not one for the book.
	if not is_celebrating(player):
		game.stat_book.add_dive(player.team)
	game.audio.action(player, &"dive")


# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
### A dive out of a jump: only for a player who is in the air.
#func do_jump_dive(player: Player, dir: Vector3) -> void:
#	if _thinking:
#		_queued_actions.append(do_jump_dive.bind(player, dir))
#		return
#	if player.state != Player.State.JUMPING:
#		return
#	var top: float = tuning.dive_speed * tuning.jump_dive_speed_scale
#	if not player.start_jump_dive(dir, _ball_dive_speed(player, dir, jump_dive_ball_range(), player.jump_dive_time(), top)):
#		return
#	game.stat_book.add_dive(player.team)
#	game.add_stat(&"jump_dives")
#	game.audio.action(player, &"jump_dive")


### How far off a pass may come down for a jump dive to be aimed at it.
#func jump_dive_ball_range() -> float:
#	return tuning.dive_ball_range * tuning.jump_dive_speed_scale


func do_jump(player: Player) -> void:
	if _thinking:
		_queued_actions.append(do_jump.bind(player))
		return
	if not player.start_jump():
		return
	game.audio.action(player, &"jump")
	# Going up for a pass that comes down nearby: the jump carries him to it.
	var gap: Vector3 = _gap_to_pass(player)
	var left: float = ball.air_time_left()
	if gap != Vector3.INF and gap.length() <= tuning.jump_ball_range and left <= tuning.jump_time + 0.15:
		var top: float = player.max_speed() * tuning.turbo_speed_multiplier
		player.velocity = (gap / maxf(left, 0.15)).limit_length(top)
		if gap.length_squared() > 0.04:
			player.facing = gap.normalized()


## From `player` to where the pass in the air comes down, flat. Vector3.INF when
## there is no pass for him to go for.
func _gap_to_pass(player: Player) -> Vector3:
	if ball_dead or thrown_away or player.has_ball:
		return Vector3.INF
	var in_flight: bool = phase == Phase.AIR and ball.state == Ball.State.FLIGHT
	if not in_flight and (phase != Phase.TIPPED or _tip_untouched):
		return Vector3.INF
	var gap: Vector3 = ball.target_point - player.position
	gap.y = 0.0
	return gap


## Direction for a dive at the pass in the air, or Vector3.ZERO when there is
## none within reach of a dive.
func ball_dive_direction(player: Player, ball_range: float = -1.0) -> Vector3:
	var gap: Vector3 = _gap_to_pass(player)
	if ball_range < 0.0:
		ball_range = tuning.dive_ball_range
	if gap == Vector3.INF or gap.length() > ball_range or gap.length_squared() < 0.01:
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
## that is close would sail past it. Returns -1 for an ordinary dive. The last
## three are the reach, air time and top speed of the dive, a ground dive's
## when left out.
func _ball_dive_speed(player: Player, dir: Vector3, ball_range: float = -1.0, air_time: float = -1.0, top_speed: float = -1.0) -> float:
	if ball_range < 0.0:
		ball_range = tuning.dive_ball_range
		air_time = tuning.dive_time
		top_speed = tuning.dive_speed
	var gap: Vector3 = _gap_to_pass(player)
	if gap == Vector3.INF or gap.length() > ball_range:
		return -1.0
	if gap.length_squared() > 0.01 and gap.normalized().dot(dir) < 0.7:
		return -1.0
	var left: float = ball.air_time_left()
	return clampf(gap.length() / clampf(left, 0.1, air_time), tuning.dive_ball_min_speed, top_speed)


## `side` is +1 for the player's own left, -1 for his right. With `juke` the
## spin also sidesteps to that side.
func do_spin(player: Player, side: float, juke: bool = false) -> void:
	if _thinking:
		_queued_actions.append(do_spin.bind(player, side, juke))
		return
	if player.start_spin(side, juke):
		game.audio.action(player, &"spin")


func do_secure(player: Player) -> void:
	if _thinking:
		_queued_actions.append(do_secure.bind(player))
		return
	if player.start_secure():
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
	game.rumble.play_mine(&"shove", player)
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
	var reach: float = maxf(maxf(tuning.dive_tackle_radius, tuning.tackle_radius), tuning.player_radius * 2.0) + tuning.mascot_extra_radius
	# Pushes are summed from one snapshot of positions and applied afterwards, so
	# the result does not depend on the order players are listed in. (Applying
	# them pair by pair measurably favoured whichever team came first.)
	_pushes.resize(players.size())
	_pushes.fill(Vector3.ZERO)
	# Defenders being driven off the hole (see _drive_block) are moved first, so
	# that whoever they are walked into is pushed clear of them below.
	for player: Player in players:
		player.position += player.drive_push
		player.drive_push = Vector3.ZERO
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
	# Nobody is pushed through the wall.
	for player: Player in players:
		player.keep_on_field()


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
	var extra: float = a.extra_radius + b.extra_radius
	if a.team == b.team or a.is_blocking or b.is_blocking:
		return tuning.player_radius * 2.0 + extra
	return tuning.body_radius * 2.0 + extra


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
			# A carrier in the air hurdles the dive if he is high enough when it
			# gets to him: a matter of timing, and of how high he jumps (juke rating).
			if victim.is_airborne() and attacker.tackle_cooldown <= 0.0:
				if victim.air_height() >= tuning.hurdle_clear_height:
					attacker.tackle_cooldown = tuning.tackle_retry_time
					game.add_stat(&"hurdles")
					game.audio.remark(&"announcer_hurdle", AudioDirector.REMARK_HURDLE)
					game.audio.quip(&"color_hurdle", AudioDirector.QUIP_HURDLE)
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
				game.add_stat(&"air_hits" if attacker.brain.hit_man else &"takeouts")
			var dir: Vector3 = offset.normalized() if dist > 0.01 else attacker.facing
			if ball_dead:
				# A late hit goes through as many as are in its way.
				_knock_over(attacker, victim, dir)
			else:
				_dive_into(attacker, victim, dir)
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

	if _try_truck(tackler, carrier, dir):
		return

	var skills: PlayerRatings = carrier.ratings
	var chance: float = tuning.tackle_base_chance
	if big_hit:
		chance += tuning.dive_tackle_bonus
	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	if tackler.state == Player.State.DIVING and tackler.jump_dive:
#		chance += tuning.jump_dive_tackle_bonus
	chance *= PlayerRatings.blend(skills.strength, tuning.strength_tackle_scale_low, tuning.strength_tackle_scale_high)
	chance *= PlayerRatings.blend(tackler.ratings.tackling, tuning.tackling_scale_low, tuning.tackling_scale_high)
	if tackler.block_slow_timer > 0.0:
		chance *= tuning.hole_blocked_tackle_scale if tackler.hole_block else tuning.blocked_tackle_scale
	var spinning: bool = carrier.spin_evade_timer > 0.0
	if spinning:
		chance *= lerpf(1.0, PlayerRatings.blend(skills.juke, tuning.spin_tackle_scale_low, tuning.spin_tackle_scale_high), carrier.spin_strength)
	# A stiff arm only helps against a tackler on the side the arm is out.
	var stiff_armed: bool = carrier.stiff_arm_covers(tackler)
	if stiff_armed:
		chance *= lerpf(1.0, PlayerRatings.blend(skills.strength, tuning.stiff_arm_tackle_scale_low, tuning.stiff_arm_tackle_scale_high), carrier.stiff_arm_strength)
	chance *= RubberBand.bad(carrier.team, game)

	if randf() >= chance:
		var move: StringName = &""
		if stiff_armed:
			move = &"stiff_arm"
			game.add_stat(&"stiff_arms")
			game.audio.play(&"stiff_arm")
		elif spinning:
			move = &"spin"
			game.add_stat(&"spins")
		_break_tackle(tackler, carrier, dir, move)
		return
	if _throws_as_hit(tackler, carrier, big_hit):
		return
	# Wrapped up. A strong carrier stays on his feet and drags the tackler along.
	var drag_time: float = PlayerRatings.blend(skills.strength, tuning.drag_time_low, tuning.drag_time_high)
	if big_hit:
		drag_time *= tuning.drag_big_hit_scale
	drag_time *= lerpf(1.0, tuning.secure_drag_time_scale, carrier.secure_power())
	var can_drag: bool = carrier.state == Player.State.NORMAL and tackler.state == Player.State.NORMAL
	if can_drag and drag_time >= tuning.drag_min_time:
		carrier.start_drag(tackler, drag_time)
		carrier.jolt(dir, 0.8)
		game.add_stat(&"drags")
		game.audio.play(&"tackle", 0.7)
		game.impact(tuning.shove_shake * 0.6, 0.4)
		game.rumble.play_for(&"drag", carrier, tackler)
	else:
		_finish_tackle(carrier, dir, kind, tackler, big_hit)


## The tackle is made on a quarterback who was in the middle of throwing: the
## person with a pass button held, a CPU one with a man to throw to. Some of
## the time the ball still gets away (see throw_ball with `hit`), less often
## against a dive or a big hit. True if it did: there is no tackle then.
func _throws_as_hit(tackler: Player, carrier: Player, big_hit: bool) -> bool:
	if carrier != qb or not can_pass():
		return false
	var target: Player = null
	var power: float = 0.5
	var chance: float = tuning.ai_qb_hit_throw_chance
	if carrier == human.controlled and not human.assist:
		target = human.winding_up()
		power = human.wind_up_power()
		chance = tuning.hit_throw_chance
	else:
		target = carrier.brain.hit_throw_target(self)
	if target == null:
		return false
	if big_hit or tackler.state == Player.State.DIVING:
		chance *= tuning.hit_throw_dive_scale
	if randf() >= chance:
		return false
	_hitter = tackler
	throw_ball(target, power, Placement.NORMAL, true)
	_hitter = null
	return phase == Phase.AIR


## A carrier securing the ball runs over a weaker tackler who is on his feet in
## front of him: the bigger the gap in strength, the likelier. A dive at his
## legs is harder to run through, and a tackler at his side or his back cannot
## be run over at all. `dir` points from the tackler to him.
func _try_truck(tackler: Player, carrier: Player, dir: Vector3) -> bool:
	if not carrier.is_securing() or carrier.state != Player.State.NORMAL:
		return false
	var gap: float = float(carrier.ratings.strength - tackler.ratings.strength)
	if gap <= 0.0 or (-dir).dot(carrier.facing) < tuning.secure_truck_front_dot:
		return false
	var flat_speed: float = Vector2(carrier.velocity.x, carrier.velocity.z).length()
	if flat_speed < tuning.secure_truck_min_speed:
		return false
	var chance: float = minf(gap * tuning.secure_truck_chance_per_point, tuning.secure_truck_chance_max)
	chance *= carrier.secure_power()
	if tackler.state == Player.State.DIVING:
		chance *= tuning.secure_truck_dive_scale
	chance *= RubberBand.good(carrier.team, game)
	if randf() >= chance:
		return false
	game.add_stat(&"trucks")
	_break_tackle(tackler, carrier, dir, &"truck")
	carrier.velocity *= tuning.secure_truck_speed_keep
	return true


## The carrier goes down and the play is over.
func _finish_tackle(carrier: Player, dir: Vector3, kind: PlayerFall.Kind, tackler: Player = null, big: bool = false) -> void:
	var carried: Vector3 = carrier.velocity
	# Asked before he goes down: on the turf he is securing nothing.
	var secured: float = carrier.secure_power()
	# A drag that ends with him going down is the tackle of the man hanging on.
	tackled_by = tackler if tackler != null else carrier.drag_partner
	carrier.knock_down(dir * tuning.tackle_knockdown_impulse, tuning.knockdown_time, kind)
	game.add_stat(&"tackles")
	game.audio.hit(tackler, carrier, big)
	if big:
		game.audio.remark(&"announcer_hit", AudioDirector.REMARK_HIT)
		game.audio.quip(&"color_lawn_chair", AudioDirector.QUIP_LAWN_CHAIR)
	elif not (phase == Phase.POCKET and carrier == qb):
		# An ordinary tackle now and then gets a word; a sack has its own call.
		game.audio.remark(&"announcer_tackle", AudioDirector.REMARK_TACKLE)
		game.audio.quip(&"color_tackle", AudioDirector.QUIP_TACKLE)
	game.impact(tuning.tackle_shake, 1.0)
	# A sack is felt a little more than a tackle.
	var sacked: bool = phase == Phase.POCKET and carrier == qb
	game.rumble.play_for(&"big_hit" if big else &"tackle", carrier, tackled_by, 1.15 if sacked else 1.0)
	game.field.fx.blood_burst(carrier.position, dir, tuning.blood_drops_tackle, true)
	if _try_fumble(carrier, dir, kind, carried, secured):
		return
	was_sack = phase == Phase.POCKET and carrier == qb
	if was_sack:
		game.add_stat(&"sacks")
		game.audio.shout(&"announcer_sack")
		game.audio.quip(&"color_sack", AudioDirector.QUIP_SACK)
		game.audio.crowd_react(carrier.team.opponent, 0.7)
	end_play(Result.TACKLED, _carrier_spot_x(carrier))


## The hit may knock the ball out. It leaves the way he was hit (`dir`), more or
## less, and the play goes on with the ball on the turf until somebody has it.
## `carried` is how fast the carrier was moving when he was hit, `secured`
## how well he had the ball in both arms (Player.secure_power: 0 not at all).
func _try_fumble(carrier: Player, dir: Vector3, kind: PlayerFall.Kind, carried: Vector3, secured: float = 0.0) -> bool:
	var chance: float = PlayerRatings.blend(carrier.ratings.security, tuning.fumble_chance_low, tuning.fumble_chance_high)
	if kind != PlayerFall.Kind.WRAP:
		chance *= tuning.fumble_big_hit_scale
	if secured > 0.0:
		chance *= lerpf(1.0, tuning.secure_fumble_scale, secured)
		game.add_stat(&"secured_tackles")
	chance *= RubberBand.bad(carrier.team, game)
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
	_ball_out(carrier, tackled_by)
	return true


## The ball has just left `carrier`'s hands for the turf (Ball.fumble): the
## noise, the banner and everybody finding out. `forcer` knocked it out of
## him, or null when he lost it by himself.
func _ball_out(carrier: Player, forcer: Player) -> void:
	carrier.flash(Color(1.0, 0.1, 0.1), tuning.fumble_flash)
	game.audio.shout(&"announcer_fumble")
	game.audio.quip(&"color_fumble", AudioDirector.QUIP_FUMBLE)
	game.audio.quip(&"color_confused", AudioDirector.QUIP_CONFUSED)
	fumbler = carrier
	fumble_forcer = forcer
	fumble_recoverer = null
	fumble_x = carrier.position.x
	tackled_by = null
	phase = Phase.LOOSE
	loose_time = 0.0
	_loose_untouched = 0.0
	game.add_stat(&"fumbles")
	game.stat_book.add_fumble(carrier.team)
	# For the tests: which team lost it.
	game.add_stat(StringName("fumbles_lost_" + carrier.team.short_name.to_lower()))
	game.audio.play(&"crowd_gasp")
	game.rumble.play(&"fumble", 1.0 if game.rumble.involves(carrier, fumble_forcer) else 0.5)
	game.hud.show_banner("FUMBLE!")
	for player: Player in players:
		# Anyone in the middle of a dive or a shove (the tackler, mostly) has his
		# hands full for a moment: the ball gets away from the pile first.
		player.ball_grab_cooldown = 0.0 if player.can_act() else tuning.fumble_retry_time * 1.5
		player.brain.on_fumble(self)
	human.on_fumble()


## Whether `player` knows the ball is out. The person's own player always does.
func sees_loose_ball(player: Player) -> bool:
	return player == human.controlled or player.brain.sees_ball


## The ball is on the loose: it can go over the wall, and anyone who has seen it
## and gets to it tries to pick it up or fall on it.
func _check_loose_ball(delta: float) -> void:
	if phase != Phase.LOOSE or ball.carrier != null:
		return
	loose_time += delta
	_loose_untouched += delta
	var spot: Vector3 = ball.flat_position()
	# It bounces off the wall; only one that goes over it into the stands is gone.
	if Stadium.wall_distance(tuning, spot.x, spot.z) > 0.0:
		game.add_stat(&"fumbles_out_of_play")
		end_play(Result.OUT_OF_PLAY, clampf(spot.x, -tuning.end_zone_depth, tuning.field_length + tuning.end_zone_depth))
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
	fumble_recoverer = player
	phase = Phase.RUN
	game.hud.hide_banner()
	game.add_stat(&"fumble_recoveries")
	game.audio.play(&"catch")
	game.rumble.play_team(&"catch", player.team)
	game.audio.crowd_react(player.team, 0.85 if player.team != fumbler.team else 0.5)
	if diving:
		game.add_stat(&"fumbles_fallen_on")
	if player.team != fumbler.team:
		was_fumble = true
		game.add_stat(&"fumbles_lost")
	human.on_carrier_changed(player)


## Broken tackle: the defender bounces off and eats turf.
func _break_tackle(tackler: Player, carrier: Player, dir: Vector3, move: StringName = &"") -> void:
	tackler.knock_down(-dir * 3.0, tuning.broken_tackle_stun, PlayerFall.Kind.BOUNCE_OFF)
	carrier.jolt(dir, 0.8)
	game.add_stat(&"broken_tackles")
	game.audio.broke_tackle(move)
	game.audio.play(&"broken_tackle")
	game.audio.play(&"body_fall", 0.6)
	game.audio.crowd_react(carrier.team, 0.3)
	game.impact(tuning.shove_shake * 0.6, 0.4)
	# Running a man over is the hardest of them.
	var trucked: bool = move == &"truck"
	game.rumble.play_for(&"broken_tackle", carrier, tackler, 1.4 if trucked else 1.0)
	@warning_ignore("integer_division")
	game.field.fx.blood_burst(tackler.position, -dir, tuning.blood_drops_knockdown / 2, false)


## A drag ends when its time is up: the carrier either shakes the tackler off
## and keeps running, or finally goes down.
func _update_drag() -> void:
	var carrier: Player = ball.carrier
	if ball_dead or carrier == null or carrier.state != Player.State.DRAGGING:
		return
	if carrier.state_timer > 0.0:
		game.rumble.hold_drag(carrier, carrier.drag_partner)
		return
	var tackler: Player = carrier.drag_partner
	var dir: Vector3 = carrier.facing
	var escape: float = PlayerRatings.blend(carrier.ratings.strength, tuning.shake_off_chance_low, tuning.shake_off_chance_high)
	if carrier.is_securing():
		escape += tuning.secure_shake_off_bonus * carrier.secure_strength
		game.add_stat(&"secured_drags")
	if tackler != null and randf() < escape:
		game.add_stat(&"shake_offs")
		_break_tackle(tackler, carrier, dir)
	else:
		_finish_tackle(carrier, dir, PlayerFall.Kind.WRAP)


## A dive during the play has reached a man who is not the carrier. It takes
## out one man and no more, and a man who is blocking mostly holds: the diver's
## strength against his blocking rating, and the diver bounces off if he loses.
func _dive_into(attacker: Player, victim: Player, dir: Vector3) -> void:
	if attacker.dive_spent:
		return
	if victim.is_blocking and victim.state == Player.State.NORMAL:
		var chance: float = tuning.dive_blocker_chance
		chance *= PlayerRatings.blend(attacker.ratings.strength, tuning.dive_blocker_strength_scale_low, tuning.dive_blocker_strength_scale_high)
		chance *= PlayerRatings.blend(victim.ratings.blocking, tuning.dive_blocker_blocking_scale_low, tuning.dive_blocker_blocking_scale_high)
		if randf() >= chance:
			_stuff_dive(attacker, victim, dir)
			return
	_knock_over(attacker, victim, dir)
	attacker.dive_spent = true
	attacker.velocity *= tuning.dive_hit_speed_keep


## The blocker held: the diver bounces off him and eats turf, and the blocker
## goes on blocking.
func _stuff_dive(diver: Player, blocker: Player, dir: Vector3) -> void:
	diver.knock_down(-dir * 3.0, tuning.dive_stuffed_time, PlayerFall.Kind.BOUNCE_OFF)
	diver.dive_get_up_timer = tuning.dive_get_up_time
	blocker.jolt(dir, 0.8)
	game.add_stat(&"dive_stuffs")
	game.audio.play(&"pads_clash", 0.6)
	game.audio.play(&"body_fall", 0.6)
	if diver == human.controlled or blocker == human.controlled:
		game.impact(tuning.shove_shake * 0.6, 0.4)
	game.rumble.play_mine(&"stuffed", diver, blocker)


func _knock_over(attacker: Player, victim: Player, dir: Vector3) -> void:
	var kind: PlayerFall.Kind = PlayerFall.Kind.LOW if attacker.state == Player.State.DIVING else PlayerFall.Kind.HIGH
	victim.knock_down(dir * tuning.shove_knockdown_impulse, tuning.knockdown_time, kind)
	attacker.jolt(-dir, 0.5)
	game.add_stat(&"knockdowns")
	if ball_dead and attacker.team != victim.team:
		game.stat_book.add_late_hit(attacker.team)
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
		game.rumble.play(&"knockdown")
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
		_roll_drive(blocker, rusher)
		if rusher.hole_block and rusher.block_drive >= tuning.hole_drive_min:
			# A block won at the hole holds until the back has had his chance.
			rusher.block_shed_time = maxf(rusher.block_shed_time, tuning.hole_hold_time - live_time)
		if off_play.is_run:
			var pancake: float = tuning.block_pancake_chance
			pancake *= PlayerRatings.blend(blocker.ratings.blocking, tuning.pancake_blocking_scale_low, tuning.pancake_blocking_scale_high)
			pancake *= PlayerRatings.blend(rusher.ratings.strength, tuning.pancake_strength_scale_low, tuning.pancake_strength_scale_high)
			if randf() < pancake:
				rusher.block_pancake_time = randf_range(tuning.block_pancake_time_min, tuning.block_pancake_time_max)
	rusher.block_engaged_time += delta
	rusher.block_slow_timer = 0.12
	_drive_block(blocker, rusher, delta)
	# A man with two on him stays with the first until that one lets go.
	if rusher.block_partner == null or rusher.block_partner == blocker:
		rusher.block_partner = blocker
		rusher.block_partner_timer = 0.2
	if blocker.block_partner == null or blocker.block_partner == rusher:
		blocker.block_partner = rusher
		blocker.block_partner_timer = 0.2
	if rusher.block_pancake_time >= 0.0 and rusher.block_engaged_time >= rusher.block_pancake_time:
		# At the hole he is thrown out of it, not back into the lane.
		var fall: Vector3 = Vector3(0.0, 0.0, rusher.block_drive_side) if rusher.hole_block else push_dir
		rusher.knock_down(fall * 4.0, tuning.block_pancake_down_time, PlayerFall.Kind.PANCAKE)
		rusher.block_slow_timer = 0.0
		rusher.block_engaged_time = 0.0
		rusher.block_pancake_time = -1.0
		game.add_stat(&"pancakes")
		game.audio.remark(&"announcer_pancake", AudioDirector.REMARK_PANCAKE)
		game.audio.quip(&"color_lawn_chair", AudioDirector.QUIP_LAWN_CHAIR * 0.5)
		game.audio.play(&"big_hit", 0.6)
		game.audio.play(&"body_fall", 0.6)
		game.rumble.play_mine(&"pancake", blocker, rusher)
		return
	if rusher.block_engaged_time >= rusher.block_shed_time:
		blocker.knock_down(-push_dir * 4.0, tuning.block_beaten_time, PlayerFall.Kind.PANCAKE)
		rusher.block_immune_timer = tuning.block_immune_time
		rusher.block_slow_timer = 0.0
		rusher.block_engaged_time = 0.0


## Run blocking at the hole, rolled when a block is made: how fast (yards a
## second) this blocker moves this defender out of it, and to which side. His
## blocking against the defender's strength decides most of it and luck the
## rest, so a good line opens the hole against a weak one nearly every time
## and a weak one only half opens it. The same two locking up again keep the
## roll they had.
func _roll_drive(blocker: Player, rusher: Player) -> void:
	if not run_hole_live() or blocker.team != offense or _flat_distance(rusher.position, run_hole) > tuning.hole_range:
		rusher.hole_block = false
		rusher.block_drive = 0.0
		rusher.block_drive_by = null
		return
	rusher.hole_block = true
	if rusher.block_drive_by == blocker:
		return
	rusher.block_drive_by = blocker
	# The side he was given at the line-up; a man who was not on the line goes
	# to the side of the hole he is on, or away from his blocker.
	var side: float = rusher.hole_side
	if side == 0.0:
		side = rusher.position.z - run_hole.z
		if absf(side) < 0.3:
			side = rusher.position.z - blocker.position.z
	rusher.block_drive_side = 1.0 if side >= 0.0 else -1.0
	var edge: float = float(blocker.ratings.blocking - rusher.ratings.strength) / 100.0 + tuning.hole_drive_base
	edge += randf_range(-tuning.hole_drive_luck, tuning.hole_drive_luck)
	if not blocker.brain.route.is_empty():
		edge += tuning.hole_lead_bonus
	var won: float = clampf(edge / maxf(tuning.hole_drive_full, 0.01), 0.0, 1.0)
	game.add_stat(&"hole_blocks")
	if won > 0.0:
		game.add_stat(&"hole_blocks_won")
		rusher.block_drive = lerpf(tuning.hole_drive_min, tuning.hole_drive_speed, won)
	else:
		rusher.block_drive = tuning.hole_drive_lost
	if rusher == human.controlled:
		rusher.block_drive *= tuning.hole_drive_human_scale


## The defender is taken out of the hole while the block holds, the ball has
## not gone through and the hole has not closed: sideways to his side until he
## is `hole_clear_width` from the middle of it, and a little downfield. The
## blocker stays on his man by himself: the man he is blocking is slowed, he
## is not.
func _drive_block(_blocker: Player, rusher: Player, delta: float) -> void:
	if not rusher.hole_block or rusher.block_drive <= 0.0 or live_time > tuning.hole_close_time or not run_hole_live():
		return
	var depth: float = (rusher.position.x - los_x) * off_dir
	if absf(depth) > tuning.hole_drive_depth:
		return
	var push: Vector3 = Vector3.ZERO
	var clear: float = rusher.hole_clear if rusher.hole_clear > 0.0 else tuning.hole_clear_width
	if (rusher.position.z - run_hole.z) * rusher.block_drive_side < clear:
		push.z = rusher.block_drive_side * rusher.block_drive
	if depth < tuning.hole_drive_depth - 1.0:
		push.x = off_dir * tuning.hole_drive_forward * rusher.block_drive / maxf(tuning.hole_drive_speed, 0.01)
	rusher.drive_push += push * delta


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


## The last man between `carrier` and the goal line he is running at: the
## deepest opponent on his feet who is still ahead of him. Null with nobody
## ahead of him.
func last_defender(carrier: Player) -> Player:
	var dir: float = float(carrier.team.attack_dir)
	var best: Player = null
	var best_ahead: float = 1.0
	for defender: Player in carrier.team.opponent.players:
		var ahead: float = (defender.position.x - carrier.position.x) * dir
		if not defender.is_down() and ahead > best_ahead:
			best_ahead = ahead
			best = defender
	return best


## An opponent other than `but` is on his feet close enough to `carrier` to make
## the tackle with him.
func tackle_help(carrier: Player, but: Player) -> bool:
	for defender: Player in carrier.team.opponent.players:
		if defender != but and not defender.is_down() and _flat_distance(defender.position, carrier.position) <= tuning.ai_last_man_help:
			return true
	return false


## The man with the contain on `carrier`: of the opponents ahead of him, the one
## furthest toward the sideline the carrier is nearer to. Null in the middle of
## the field, or with nobody out there who can still get outside him.
func contain_defender(carrier: Player) -> Player:
	if absf(carrier.position.z) < tuning.ai_contain_min_width:
		return null
	var dir: float = float(carrier.team.attack_dir)
	var side: float = signf(carrier.position.z)
	var best: Player = null
	var best_out: float = -tuning.ai_contain_reach
	for defender: Player in carrier.team.opponent.players:
		var ahead: float = (defender.position.x - carrier.position.x) * dir
		var out: float = (defender.position.z - carrier.position.z) * side
		if not defender.is_down() and ahead > 0.0 and out > best_out:
			best_out = out
			best = defender
	return best


func nearest_opponent_distance(player: Player) -> float:
	var best: float = INF
	for opponent: Player in player.team.opponent.players:
		if opponent.is_down():
			continue
		best = minf(best, _flat_distance(opponent.position, player.position))
	return best


func _update_markers() -> void:
	var show: bool = human.is_active() and human.controlled == qb and qb != null and (not off_play.is_run or hot_picking)
	show = show and (ball_dead and result == Result.NONE or can_pass())
	for player: Player in players:
		var slot: int = eligible.find(player) if show else -1
		if slot >= 0 and slot < HumanController.PASS_ACTIONS.size():
			player.set_pass_icon(human.pass_label(slot), human.pass_color(slot))
		else:
			player.set_pass_icon("", Color.WHITE)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
