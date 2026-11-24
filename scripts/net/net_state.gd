class_name NetState
extends RefCounted
## The match as the picture needs it, packed on the server every tick and put
## back on the person's machine: where every player and the ball are and what
## they are doing, how the play stands, the score and the clock.
##
## The players, the ball, the PlayController and the Game there are the same
## objects as offline. Nothing is decided on them; they are given what the
## tables below name, and then draw themselves as ever. When the picture needs
## something more of the game, it goes in a table.
##
## Each table row is a property and what it is: f a number, i a small whole
## number or an enum, b yes or no, v a Vector3, p a player (sent as his place in
## PlayController.players, -1 for nobody), t a team (0 home, 1 away, -1 none).
## All of them travel as floats. What does not fit a float goes beside them.

const PLAYER: Array[Array] = [
	[&"position", "v"], [&"velocity", "v"], [&"facing", "v"], [&"look_dir", "v"],
	[&"visible", "b"], [&"state", "i"], [&"state_timer", "f"], [&"frozen", "b"],
	[&"has_ball", "b"], [&"wants_turbo", "b"], [&"turbo", "f"], [&"turbo_active", "b"],
	[&"feet_set", "f"], [&"pump_timer", "f"],
	[&"flair", "i"], [&"flair_timer", "f"], [&"flair_side", "f"], [&"flair_power", "f"],
	[&"_flair_from", "f"], [&"_flair_sweep", "f"],
	[&"is_blocking", "b"], [&"calling_for_ball", "b"], [&"block_slow_timer", "f"], [&"block_partner", "p"],
	[&"secure_timer", "f"], [&"jump_strength", "f"], [&"dive_reach_timer", "f"], [&"dazed_timer", "f"],
	[&"catch_timer", "f"], [&"move_side", "f"], [&"drag_partner", "p"], [&"injured", "b"],
]
## After a player's own: the seat of the person playing him (-1 nobody), his job
## on offense (-1 none) and how long he blocks first, his job on defense (-1
## none), and whether he has seen a loose ball.
const PLAYER_EXTRA: int = 5

const BALL: Array[Array] = [
	[&"position", "v"], [&"visible", "b"], [&"state", "i"],
	[&"carrier", "p"], [&"thrower", "p"], [&"intended", "p"],
	[&"target_point", "v"], [&"flight_time", "f"], [&"flight_elapsed", "f"],
	[&"_flight_start", "v"], [&"_flight_velocity", "v"], [&"_flight_vy", "f"], [&"_gravity", "f"],
	[&"_guide_now", "v"], [&"_guide_window", "f"],
	[&"_loose_velocity", "v"], [&"grounded", "b"], [&"velocity", "v"],
	[&"_settle_local", "v"], [&"_settle_time", "f"], [&"_settle_left", "f"],
	[&"_tossed", "b"], [&"_toss_from", "v"], [&"_toss_height", "f"], [&"_kicked", "b"], [&"wobbly", "b"],
]
## After the ball's own: whether the mark where a pass comes down shows, and where.
const BALL_EXTRA: int = 4

const PLAY: Array[Array] = [
	[&"phase", "i"], [&"ball_dead", "b"], [&"result", "i"],
	[&"live_time", "f"], [&"dead_time", "f"], [&"los_x", "f"], [&"off_dir", "f"],
	[&"kickoff", "b"], [&"handoff_done", "b"], [&"_flick_stage", "i"], [&"_flick_ready", "f"],
	[&"gain_dance", "b"], [&"gain_dance_time", "f"], [&"celebration_pick_open", "b"],
	[&"offense", "t"], [&"defense", "t"], [&"final_team", "t"],
	[&"qb", "p"], [&"runner", "p"], [&"returner", "p"], [&"scorer", "p"], [&"celebrant", "p"], [&"passer", "p"],
]

const GAME: Array[Array] = [
	[&"down", "i"], [&"los_x", "f"], [&"first_down_x", "f"], [&"goal_to_go", "b"],
	[&"clock", "f"], [&"half", "i"], [&"conversion", "b"], [&"overtime", "b"],
	[&"hold_camera_side", "b"], [&"offense", "t"], [&"defense", "t"],
]


## The match right now: [players, ball, play, game, the rest].
static func pack(game: Game) -> Array:
	var pc: PlayController = game.play_controller
	var players: PackedFloat32Array = PackedFloat32Array()
	for player: Player in pc.players:
		_write(player, PLAYER, players, game)
		var brain: PlayerBrain = player.brain
		players.append(float(player.human.seat) if player.human != null else -1.0)
		players.append(float(brain.off_assign.job) if brain.off_assign != null else -1.0)
		players.append(brain.off_assign.block_time if brain.off_assign != null else 0.0)
		players.append(float(brain.def_assign.job) if brain.def_assign != null else -1.0)
		players.append(1.0 if brain.sees_ball else 0.0)
	var ball: PackedFloat32Array = PackedFloat32Array()
	_write(game.ball, BALL, ball, game)
	var mark: Node3D = game.ball.landing_marker
	ball.append(1.0 if mark.visible else 0.0)
	ball.append(mark.global_position.x)
	ball.append(mark.global_position.y)
	ball.append(mark.global_position.z)
	var play: PackedFloat32Array = PackedFloat32Array()
	_write(pc, PLAY, play, game)
	var match_now: PackedFloat32Array = PackedFloat32Array()
	_write(game, GAME, match_now, game)
	# The play the offense is running is nobody's business before the snap.
	var snapped: bool = not (pc.ball_dead and pc.result == PlayController.Result.NONE)
	var off_play: int = game.offense_playbook.plays.find(pc.off_play) if snapped and pc.off_play != null else -1
	var eligible: PackedInt32Array = PackedInt32Array()
	for receiver: Player in pc.eligible:
		eligible.append(pc.players.find(receiver))
	var rest: Array = [
		String(pc.state_machine.current_name()), off_play, eligible,
		pc.celebration_style, pc.celebration_seed, String(pc.touchdown_quip),
		game.home.score, game.away.score, game.banner_text,
		# What the levels of the crowd, the huddle, the music and the chant go by.
		[game.audio.excitement, game.audio._huddle_on, game.audio._music_stopping, game.audio._chant_fading],
	]
	return [players, ball, play, match_now, rest]


## Whether `state` can be what pack() made for a match like `game`.
static func fits(game: Game, state: Variant) -> bool:
	if typeof(state) != TYPE_ARRAY:
		return false
	var parts: Array = state
	if parts.size() != 5 or typeof(parts[4]) != TYPE_ARRAY or (parts[4] as Array).size() != 10:
		return false
	for at: int in 4:
		if typeof(parts[at]) != TYPE_PACKED_FLOAT32_ARRAY:
			return false
	var count: int = game.play_controller.players.size()
	return (parts[0] as PackedFloat32Array).size() == count * (_width(PLAYER) + PLAYER_EXTRA) \
			and (parts[1] as PackedFloat32Array).size() == _width(BALL) + BALL_EXTRA \
			and (parts[2] as PackedFloat32Array).size() == _width(PLAY) \
			and (parts[3] as PackedFloat32Array).size() == _width(GAME)


## Puts `state` on this machine's match. `seat` is the person here: the player
## they have is theirs here too.
static func unpack(game: Game, state: Array, seat: int) -> void:
	var pc: PlayController = game.play_controller
	var players: PackedFloat32Array = state[0]
	var at: int = 0
	var mine: Player = null
	for player: Player in pc.players:
		at = _read(player, PLAYER, players, at, game)
		if int(players[at]) == seat and seat >= 0:
			mine = player
		_give_job(player.brain, int(players[at + 1]), players[at + 2], int(players[at + 3]))
		player.brain.sees_ball = players[at + 4] > 0.5
		at += PLAYER_EXTRA
	if game.human.is_active() and game.human.controlled != mine:
		game.human.set_controlled(mine)
	var ball: PackedFloat32Array = state[1]
	at = _read(game.ball, BALL, ball, 0, game)
	var mark: Node3D = game.ball.landing_marker
	mark.visible = ball[at] > 0.5
	mark.global_position = Vector3(ball[at + 1], ball[at + 2], ball[at + 3])
	_read(pc, PLAY, state[2], 0, game)
	_read(game, GAME, state[3], 0, game)
	var rest: Array = state[4]
	var state_name: StringName = StringName(str(rest[0]))
	var was: StringName = pc.state_machine.shown
	pc.state_machine.shown = state_name
	var plays: Array[OffensePlay] = game.offense_playbook.plays
	var off_play: int = int(rest[1])
	pc.off_play = plays[off_play] if off_play >= 0 and off_play < plays.size() else null
	pc.eligible.clear()
	if typeof(rest[2]) == TYPE_PACKED_INT32_ARRAY:
		for who: int in rest[2] as PackedInt32Array:
			if who >= 0 and who < pc.players.size():
				pc.eligible.append(pc.players[who])
	pc.celebration_style = int(rest[3])
	pc.celebration_seed = int(rest[4])
	pc.touchdown_quip = StringName(str(rest[5]))
	game.home.score = int(rest[6])
	game.away.score = int(rest[7])
	game.banner_text = str(rest[8])
	if typeof(rest[9]) == TYPE_ARRAY and (rest[9] as Array).size() == 4:
		var sound: Array = rest[9]
		game.audio.excitement = clampf(float(sound[0]), 0.0, 1.0)
		game.audio._huddle_on = bool(sound[1])
		game.audio._music_stopping = bool(sound[2])
		game.audio._chant_fading = bool(sound[3])
	# Last, with everything else in place: whoever listens for a new state of
	# the match (the rumble, for one) hears of it here too.
	if state_name != was:
		pc.state_machine.state_changed.emit(was, state_name)


## Floats a table's rows take.
static func _width(table: Array[Array]) -> int:
	var width: int = 0
	for row: Array in table:
		width += 3 if row[1] == "v" else 1
	return width


static func _write(from: Object, table: Array[Array], floats: PackedFloat32Array, game: Game) -> void:
	for row: Array in table:
		var value: Variant = from.get(row[0])
		match row[1]:
			"v":
				var vector: Vector3 = value
				floats.append(vector.x)
				floats.append(vector.y)
				floats.append(vector.z)
			"b":
				floats.append(1.0 if value else 0.0)
			"p":
				floats.append(float(game.play_controller.players.find(value)) if value != null else -1.0)
			"t":
				floats.append(-1.0 if value == null else (0.0 if value == game.home else 1.0))
			_:
				floats.append(float(value))


## Returns where the next thing in `floats` starts.
static func _read(to: Object, table: Array[Array], floats: PackedFloat32Array, at: int, game: Game) -> int:
	var players: Array[Player] = game.play_controller.players
	for row: Array in table:
		match row[1]:
			"v":
				to.set(row[0], Vector3(floats[at], floats[at + 1], floats[at + 2]))
				at += 2
			"b":
				to.set(row[0], floats[at] > 0.5)
			"i":
				to.set(row[0], roundi(floats[at]))
			"p":
				var who: int = roundi(floats[at])
				to.set(row[0], players[who] if who >= 0 and who < players.size() else null)
			"t":
				var side: int = roundi(floats[at])
				to.set(row[0], null if side < 0 else (game.home if side == 0 else game.away))
			_:
				to.set(row[0], floats[at])
		at += 1
	return at


## A stand-in for the player's assignment, with what the picture reads of it:
## the stance he takes at the line.
static func _give_job(brain: PlayerBrain, off_job: int, block_time: float, def_job: int) -> void:
	if off_job < 0:
		brain.off_assign = null
	else:
		if brain.off_assign == null:
			brain.off_assign = OffenseAssignment.new()
		brain.off_assign.job = off_job as OffenseAssignment.Job
		brain.off_assign.block_time = block_time
	if def_job < 0:
		brain.def_assign = null
	else:
		if brain.def_assign == null:
			brain.def_assign = DefenseAssignment.new()
		brain.def_assign.job = def_job as DefenseAssignment.Job
