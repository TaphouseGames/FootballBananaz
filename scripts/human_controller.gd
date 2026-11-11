class_name HumanController
extends Node
## Turns Input Map actions into inputs for the one player the person controls.
## `team` is null in autoplay, which disables everything here.

var game: Game
var pc: PlayController
var tuning: Tuning
var team: Team
var controlled: Player
## True on ticks where the controlled player should run on AI instead
## (a targeted receiver with the stick at rest runs to the ball by himself).
var assist: bool = false


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


func read_move() -> Vector3:
	var stick: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	return Vector3(stick.x, 0.0, stick.y)


# --- Events from PlayController --------------------------------------------------

func on_line_up() -> void:
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


# --- Per-tick updates ------------------------------------------------------------

## Before the snap on defense: the pass button steps through the defenders.
func update_pre_snap() -> void:
	if not is_active() or team == pc.offense or controlled == null:
		return
	if Input.is_action_just_pressed(&"pass_switch"):
		var next: int = (team.players.find(controlled) + 1) % team.players.size()
		set_controlled(team.players[next])


func update_live() -> void:
	assist = false
	if not is_active() or controlled == null:
		return
	var player: Player = controlled
	var move: Vector3 = read_move()
	var moving: bool = move.length_squared() > 0.04
	player.is_blocking = false
	player.ai_speed_scale = 1.0
	player.move_input = move
	player.wants_turbo = Input.is_action_pressed(&"turbo")

	if pc.phase == PlayController.Phase.AIR and pc.ball.intended == player and not moving:
		assist = true

	var carrier: Player = pc.ball.carrier
	var is_passer: bool = pc.can_pass() and player == pc.qb
	var pass_pressed: bool = Input.is_action_just_pressed(&"pass_switch")
	var action_pressed: bool = Input.is_action_just_pressed(&"action")

	if pass_pressed:
		if is_passer:
			pc.throw_ball(_pick_receiver(move, moving))
		elif not player.has_ball and (carrier == null or carrier.team != team):
			_switch_to_nearest()
		return

	if not action_pressed or not player.can_act():
		return
	if is_passer:
		pc.cycle_highlight()
	elif player.has_ball:
		pc.do_juke(player, _juke_direction(player, move))
	elif carrier != null and carrier.team != team and _flat_distance(player.position, carrier.position) <= tuning.dive_trigger_range:
		var aim: Vector3 = carrier.position + carrier.velocity * 0.15 - player.position
		aim.y = 0.0
		pc.do_dive(player, aim.normalized() if aim.length_squared() > 0.01 else player.facing)
	else:
		pc.do_shove(player, move.normalized() if moving else player.facing)


## After the whistle: free movement and cheap shots.
func update_dead() -> void:
	assist = false
	if not is_active() or controlled == null:
		return
	var player: Player = controlled
	var move: Vector3 = read_move()
	var moving: bool = move.length_squared() > 0.04
	player.is_blocking = false
	player.ai_speed_scale = 1.0
	player.move_input = move
	player.wants_turbo = Input.is_action_pressed(&"turbo")
	if not Input.is_action_just_pressed(&"action") or not player.can_act():
		return
	var victim: Player = null
	var best: float = tuning.shove_radius
	for opponent: Player in team.opponent.players:
		var dist: float = _flat_distance(opponent.position, player.position)
		if not opponent.is_down() and dist < best:
			best = dist
			victim = opponent
	if victim != null:
		var to: Vector3 = victim.position - player.position
		to.y = 0.0
		pc.do_shove(player, to.normalized() if to.length_squared() > 0.01 else player.facing)
	else:
		pc.do_dive(player, move.normalized() if moving else player.facing)


# --- Helpers -----------------------------------------------------------------

## Stick at rest: the highlighted receiver. Stick held: whoever is most in that direction.
func _pick_receiver(move: Vector3, moving: bool) -> Player:
	if not moving:
		return pc.highlighted
	var dir: Vector3 = move.normalized()
	var best: Player = pc.highlighted
	var best_dot: float = 0.3
	for receiver: Player in pc.eligible:
		var to: Vector3 = receiver.position - pc.qb.position
		to.y = 0.0
		if to.length_squared() < 0.01:
			continue
		var dot: float = to.normalized().dot(dir)
		if dot > best_dot:
			best_dot = dot
			best = receiver
	return best


func _switch_to_nearest() -> void:
	var point: Vector3 = pc.ball.target_point if pc.phase == PlayController.Phase.AIR else pc.ball.flat_position()
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


func _juke_direction(player: Player, move: Vector3) -> Vector3:
	if absf(move.z) > 0.3:
		return Vector3(0.0, 0.0, signf(move.z))
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
