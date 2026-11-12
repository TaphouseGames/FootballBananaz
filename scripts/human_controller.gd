class_name HumanController
extends Node
## Turns Input Map actions into inputs for the one player the person controls.
## `team` is null in autoplay, which disables everything here.

const PASS_ACTIONS: Array[StringName] = [&"pass_1", &"pass_2", &"pass_3"]
const PAD_LABELS: Array[String] = ["A", "X", "B"]
const PAD_COLORS: Array[Color] = [Color(0.3, 0.85, 0.35), Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.25)]

var game: Game
var pc: PlayController
var tuning: Tuning
var team: Team
var controlled: Player
## True on ticks where the controlled player should run on AI instead
## (a targeted receiver with the stick at rest runs to the ball by himself).
var assist: bool = false
## Pass button being held while the QB winds up (-1 = none), and when it went down.
var _pass_slot: int = -1
var _pass_press_time: float = 0.0


func setup(p_game: Game) -> void:
	game = p_game
	pc = game.play_controller
	tuning = game.tuning
	team = null
	if not game.autoplay:
		for candidate: Team in [game.home, game.away]:
			if candidate.is_human:
				team = candidate


func is_active() -> bool:
	return team != null


func set_controlled(player: Player) -> void:
	if controlled == player:
		return
	if controlled != null:
		controlled.set_controlled(false)
	controlled = player
	if controlled != null:
		controlled.set_controlled(true)


func pass_label(slot: int) -> String:
	return PAD_LABELS[slot]


func pass_color(slot: int) -> Color:
	return PAD_COLORS[slot]


## True when the other team has the ball right now (or had it at the whistle),
## whichever side the person started the play on.
func is_defending() -> bool:
	if pc.ball_dead and pc.result != PlayController.Result.NONE:
		return team != pc.final_team
	var carrier: Player = pc.ball.carrier
	return carrier.team != team if carrier != null else team != pc.offense


## Stick input turned into field directions for the behind-the-player camera:
## up runs away from the camera, right runs to screen right. It goes by where
## the camera is right now, so it holds while the camera swings round.
func read_move() -> Vector3:
	var stick: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var rig: Basis = game.camera_rig.basis
	var move: Vector3 = rig.x * stick.x + rig.z * stick.y
	return Vector3(move.x, 0.0, move.z)


# --- Events from PlayController --------------------------------------------------

func on_line_up() -> void:
	_pass_slot = -1
	if not is_active():
		return
	if team == pc.offense:
		set_controlled(pc.qb)
	else:
		set_controlled(_default_defender())


func on_throw(target: Player) -> void:
	if is_active() and target.team == team:
		set_controlled(target)


func on_carrier_changed(carrier: Player) -> void:
	if is_active() and carrier.team == team:
		set_controlled(carrier)


## The ball is out. If the person's player is on the turf or nowhere near it,
## they get the teammate closest to the ball instead.
func on_fumble() -> void:
	if not is_active():
		return
	if controlled == null or not controlled.can_act() or _flat_distance(controlled.position, pc.ball.flat_position()) > 8.0:
		_switch_to_nearest()


# --- Per-tick updates ------------------------------------------------------------

## Before the snap on defense: the switch button steps through the defenders.
func update_pre_snap() -> void:
	if not is_active() or team == pc.offense or controlled == null:
		return
	if Input.is_action_just_pressed(&"switch_player"):
		var next: int = (team.players.find(controlled) + 1) % team.players.size()
		set_controlled(team.players[next])


func update_live() -> void:
	assist = false
	if not is_active() or controlled == null:
		return
	# The receiving team gets under a kickoff by itself; the person takes over
	# at the catch.
	if pc.kickoff and pc.phase == PlayController.Phase.AIR and team == pc.offense:
		assist = true
		return
	var player: Player = controlled
	var move: Vector3 = read_move()
	var moving: bool = move.length_squared() > 0.04
	player.is_blocking = false
	player.calling_for_ball = false
	player.ai_speed_scale = 1.0
	player.move_input = move
	player.wants_turbo = Input.is_action_pressed(&"turbo")

	if pc.phase == PlayController.Phase.AIR and pc.ball.intended == player and not moving:
		assist = true

	var carrier: Player = pc.ball.carrier
	var is_passer: bool = pc.can_pass() and player == pc.qb

	# In the pocket the pass buttons win: they share A, X and B with other actions.
	# The pass leaves on release: the longer the hold, the harder and flatter the
	# throw. A tap is a lob; a full charge fires a bullet by itself.
	if is_passer:
		if _pass_slot < 0 or _pass_slot >= pc.eligible.size():
			_pass_slot = -1
			for slot: int in mini(PASS_ACTIONS.size(), pc.eligible.size()):
				if Input.is_action_just_pressed(PASS_ACTIONS[slot]):
					_pass_slot = slot
					_pass_press_time = pc.live_time
					return
		else:
			var held: float = pc.live_time - _pass_press_time
			if not Input.is_action_pressed(PASS_ACTIONS[_pass_slot]) or held >= tuning.pass_charge_time:
				var target: Player = pc.eligible[_pass_slot]
				_pass_slot = -1
				pc.throw_ball(target, pc.pass_power(held), _pass_placement())
				return
	else:
		_pass_slot = -1
		# A tucked quarterback is a runner: the pass buttons do nothing until turbo
		# is released, and the jump and action buttons below work for him.
		if not player.has_ball and Input.is_action_just_pressed(&"switch_player"):
			if carrier == null or carrier.team != team:
				_switch_to_nearest()
			return

	if not player.can_act():
		return
	if Input.is_action_just_pressed(&"jump"):
		pc.do_jump(player)
		return
	if is_passer:
		return
	# The second jump button is a pass button while the quarterback can throw.
	if Input.is_action_just_pressed(&"jump_alt"):
		pc.do_jump(player)
		return
	if player.has_ball:
		_carrier_moves(player, move, moving)
		return
	if not Input.is_action_just_pressed(&"action"):
		return
	# With a pass in the air the action is a dive at the ball, for either side.
	var at_ball: Vector3 = pc.ball_dive_direction(player)
	if at_ball != Vector3.ZERO:
		pc.do_dive(player, at_ball)
	elif pc.phase == PlayController.Phase.LOOSE:
		# A fumble: the action is a dive on the ball, whichever side he is on.
		var at_loose: Vector3 = pc.loose_dive_direction(player)
		if at_loose == Vector3.ZERO:
			at_loose = move.normalized() if moving else player.facing
		pc.do_dive(player, at_loose)
	elif is_defending():
		# On defense (from the snap or after a turnover) the action is always a
		# dive, aimed at the carrier when he is close.
		var target: Player = carrier if carrier != null and carrier.team != team else null
		pc.do_dive(player, _dive_direction(player, move, moving, target))
	else:
		pc.do_shove(player, move.normalized() if moving else player.facing)


## Running with the ball: spin, a stiff arm to either side, or a dive that
## gives himself up for the last few yards.
func _carrier_moves(player: Player, move: Vector3, moving: bool) -> void:
	if Input.is_action_just_pressed(&"stiff_arm_left"):
		pc.do_stiff_arm(player, 1.0)
	elif Input.is_action_just_pressed(&"stiff_arm_right"):
		pc.do_stiff_arm(player, -1.0)
	elif Input.is_action_just_pressed(&"spin"):
		# Stick leaned across his running line: spin and sidestep that way.
		# Otherwise a plain spin, turning away from the nearest defender.
		var line: Vector3 = player.velocity.normalized() if player.velocity.length_squared() > 0.6 else player.facing
		var left: Vector3 = Vector3.UP.cross(line)
		var lean: float = move.dot(left)
		if absf(lean) > 0.3:
			pc.do_spin(player, signf(lean), true)
		else:
			pc.do_spin(player, 1.0 if _spin_direction(player).dot(left) >= 0.0 else -1.0)
	elif Input.is_action_just_pressed(&"action"):
		pc.do_dive(player, move.normalized() if moving else player.facing)


## After the whistle: free movement and cheap shots.
func update_dead() -> void:
	assist = false
	if not is_active() or controlled == null:
		return
	var player: Player = controlled
	var move: Vector3 = read_move()
	var moving: bool = move.length_squared() > 0.04
	player.is_blocking = false
	player.calling_for_ball = false
	player.ai_speed_scale = 1.0
	player.move_input = move
	player.wants_turbo = Input.is_action_pressed(&"turbo")
	if not Input.is_action_just_pressed(&"action") or not player.can_act():
		return
	var on_defense: bool = is_defending()
	var victim: Player = null
	var best: float = tuning.dive_trigger_range if on_defense else tuning.shove_radius
	for opponent: Player in team.opponent.players:
		var dist: float = _flat_distance(opponent.position, player.position)
		if not opponent.is_down() and dist < best:
			best = dist
			victim = opponent
	if on_defense:
		# The defense never shoves: a late hit is a dive too.
		pc.do_dive(player, _dive_direction(player, move, moving, victim))
	elif victim != null:
		var to: Vector3 = victim.position - player.position
		to.y = 0.0
		pc.do_shove(player, to.normalized() if to.length_squared() > 0.01 else player.facing)
	else:
		pc.do_dive(player, move.normalized() if moving else player.facing)


# --- Helpers -----------------------------------------------------------------

## A bumper held as the pass leaves: left leads the receiver, right underthrows
## him. Both together cancel out.
func _pass_placement() -> PlayController.Placement:
	var lead: bool = Input.is_action_pressed(&"pass_lead")
	var under: bool = Input.is_action_pressed(&"pass_under")
	if lead and not under:
		return PlayController.Placement.LEAD
	if under and not lead:
		return PlayController.Placement.UNDER
	return PlayController.Placement.NORMAL


func _switch_to_nearest() -> void:
	var in_air: bool = pc.phase == PlayController.Phase.AIR or pc.phase == PlayController.Phase.TIPPED
	var point: Vector3 = pc.ball.target_point if in_air else pc.ball.flat_position()
	var best: Player = null
	var best_dist: float = INF
	for candidate: Player in team.players:
		if candidate.is_down():
			continue
		var dist: float = _flat_distance(candidate.position, point)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	if best != null:
		set_controlled(best)


func _default_defender() -> Player:
	var best: Player = team.players[0]
	var best_dist: float = INF
	for candidate: Player in team.players:
		if candidate.brain.def_assign != null and candidate.brain.def_assign.job == DefenseAssignment.Job.RUSH:
			continue
		var dist: float = _flat_distance(candidate.position, pc.ball.flat_position())
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


## Where a defender's dive goes: at `target` (led a little) if he is within the
## auto-aim range, otherwise along the stick, otherwise straight ahead.
func _dive_direction(player: Player, move: Vector3, moving: bool, target: Player) -> Vector3:
	if target != null and _flat_distance(player.position, target.position) <= tuning.dive_trigger_range:
		var aim: Vector3 = target.position + target.velocity * 0.15 - player.position
		aim.y = 0.0
		if aim.length_squared() > 0.01:
			return aim.normalized()
	return move.normalized() if moving else player.facing


## Away from the nearest defender, across the field.
func _spin_direction(player: Player) -> Vector3:
	var nearest: float = INF
	var side: float = 1.0
	for opponent: Player in team.opponent.players:
		var dist: float = _flat_distance(opponent.position, player.position)
		if not opponent.is_down() and dist < nearest:
			nearest = dist
			side = -signf(opponent.position.z - player.position.z)
	return Vector3(0.0, 0.0, side if side != 0.0 else 1.0)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
