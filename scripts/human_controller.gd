class_name HumanController
extends Node
## Turns Input Map actions into inputs for the one player a person controls.
## There is one of these for each person playing (Game.humans): one against the
## CPU, two against each other. `team` is null in autoplay, which disables
## everything here.

const PASS_ACTIONS: Array[StringName] = [&"pass_1", &"pass_2", &"pass_3", &"pass_4"]
const PAD_LABELS: Array[String] = ["A", "X", "B", "Y"]
const PAD_COLORS: Array[Color] = [Color(0.3, 0.85, 0.35), Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.25), Color(1.0, 0.82, 0.2)]

var game: Game
var pc: PlayController
var tuning: Tuning
## The team this person plays. The team knows it too (Team.human).
var team: Team:
	set(value):
		if team != null and team.human == self:
			team.human = null
		team = value
		if team != null:
			team.human = self
var controlled: Player
## This person's buttons: every pad's with one person playing, their own pad's
## with two (see Controllers).
var pad: PadInput = PadInput.new()
## 0 for player one, 1 for player two.
var seat: int = 0
## True on ticks where the controlled player should run on AI instead
## (a targeted receiver with the stick at rest runs to the ball by himself).
var assist: bool = false
## Pass button being held while the QB winds up (-1 = none), and when it went down.
var _pass_slot: int = -1
var _pass_press_time: float = 0.0
## The right bumper went down by itself while he could throw (and when): let go
## quickly, with no pass button pressed meanwhile, it is a pump fake.
var _fake_armed: bool = false
var _fake_press_time: float = 0.0


## `p_team` is the team this person plays (null: nobody does), `p_pad` their
## buttons and `p_seat` which of the people playing they are.
func setup(p_game: Game, p_team: Team, p_pad: PadInput, p_seat: int = 0) -> void:
	game = p_game
	pc = game.play_controller
	tuning = game.tuning
	pad = p_pad
	seat = p_seat
	team = p_team


func is_active() -> bool:
	return team != null


func set_controlled(player: Player) -> void:
	if controlled == player:
		return
	if controlled != null:
		controlled.set_controlled(false)
		controlled.human = null
	controlled = player
	if controlled != null:
		# Never two people's: the other one lets go of him.
		if controlled.human != null and controlled.human != self:
			controlled.human.set_controlled(null)
		controlled.human = self
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
	var stick: Vector2 = pad.vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var rig: Basis = game.camera_rig.basis
	var move: Vector3 = rig.x * stick.x + rig.z * stick.y
	return Vector3(move.x, 0.0, move.z)


# --- Events from PlayController --------------------------------------------------

## The receiver whose pass button the person is holding right now (the
## quarterback is winding up to throw to him), or null; and the power the
## throw would have if it left now.
func winding_up() -> Player:
	if _pass_slot < 0 or _pass_slot >= pc.eligible.size():
		return null
	return pc.eligible[_pass_slot]


func wind_up_power() -> float:
	return pc.pass_power(pc.live_time - _pass_press_time)


func on_line_up() -> void:
	_pass_slot = -1
	_fake_armed = false
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
	if pad.just_pressed(&"switch_player"):
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
	player.wants_turbo = pad.pressed(&"turbo")

	# Play action: he stays with the back until the fake is over.
	if player == pc.qb and player.has_ball and pc.faking():
		player.move_input = Vector3.ZERO
		player.wants_turbo = false
		return
	# A run play until the ball is handed over, and a flea flicker while the
	# back has it: the quarterback does what the play draws for him (stays put,
	# or drops on a draw), so the exchange happens where it is meant to. Walked
	# away from the back, the handoff would turn into a slower toss.
	if player == pc.qb and pc.phase == PlayController.Phase.POCKET and _in_exchange():
		player.move_input = Vector3.ZERO
		player.wants_turbo = false
		assist = true
		return

	if pc.phase == PlayController.Phase.AIR and pc.ball.intended == player and not moving:
		assist = true

	# A back behind the line on a run at a hole, stick pushed upfield: he is
	# eased toward the middle of the lane his blockers have opened. Leaning the
	# stick to a side is the person's own cut, and wins.
	if player == pc.runner and player.has_ball and pc.run_hole_live():
		var ahead: float = move.x * pc.off_dir
		if ahead > 0.5 and absf(move.z) < tuning.hole_magnet_release:
			var lane: Vector2 = pc.hole_lane()
			if lane.y >= tuning.hole_burst_min_width and absf(lane.x - player.position.z) <= tuning.hole_pull_range:
				var pulled: Vector3 = move + Vector3(0.0, 0.0, clampf(lane.x - player.position.z, -1.0, 1.0) * tuning.hole_magnet * ahead)
				player.move_input = pulled.normalized() * move.length()

	var carrier: Player = pc.ball.carrier
	var is_passer: bool = pc.can_pass() and player == pc.qb
	# Pressed with the ball in his hands: he secures it for a moment, also with
	# a tackler on his back. While the quarterback can throw the same button is
	# a pass button.
	# Wrapped up in the pocket they are pass buttons still: he gets rid of it as
	# he goes down, for what that throw is worth.
	var in_grasp: bool = player == pc.qb and pc.in_the_grasp()
	if in_grasp:
		for slot: int in mini(PASS_ACTIONS.size(), pc.eligible.size()):
			if pad.just_pressed(PASS_ACTIONS[slot]):
				pc.throw_ball(pc.eligible[slot], tuning.hit_throw_power, _pass_placement(), true)
				return
	elif player.has_ball and not is_passer and pad.just_pressed(&"secure_ball"):
		pc.do_secure(player)

	# A lateral to the nearest teammate level with him or behind him: for any
	# carrier, also with a tackler on his back. A quarterback who can still
	# throw has to tuck the ball first (turbo): untucked, the same trigger
	# throws it away.
	if player.has_ball and not is_passer and pad.just_pressed(&"lateral"):
		if pc.do_lateral(player):
			_pass_slot = -1
			_fake_armed = false
			return

	# In the pocket the pass buttons win: they share A, X, B and (with four men
	# out) Y with other actions.
	# The pass leaves on release: the longer the hold, the harder and flatter the
	# throw. A tap is a lob; a full charge fires a bullet by itself.
	if is_passer:
		# Getting rid of it: into the stands on the side the stick leans to, or else
		# the nearer sideline. It beats a pass being wound up.
		if pad.just_pressed(&"throw_away"):
			_pass_slot = -1
			var side: float = signf(move.z) if absf(move.z) > 0.3 else signf(player.position.z)
			pc.throw_away(side if side != 0.0 else 1.0)
			return
		# The right bumper tapped by itself is a pump fake. Held as a pass leaves
		# it underthrows, so a pass button pressed meanwhile calls the fake off.
		if pad.just_pressed(&"pass_under"):
			_fake_armed = _pass_slot < 0
			_fake_press_time = pc.live_time
		if _pass_slot >= 0:
			_fake_armed = false
		elif _fake_armed and not pad.pressed(&"pass_under"):
			_fake_armed = false
			if pc.live_time - _fake_press_time <= tuning.pump_tap_time:
				pc.pump_fake()
				return
		if _pass_slot < 0 or _pass_slot >= pc.eligible.size():
			_pass_slot = -1
			for slot: int in mini(PASS_ACTIONS.size(), pc.eligible.size()):
				if pad.just_pressed(PASS_ACTIONS[slot]):
					_pass_slot = slot
					_pass_press_time = pc.live_time
					return
		else:
			var held: float = pc.live_time - _pass_press_time
			if not pad.pressed(PASS_ACTIONS[_pass_slot]) or held >= tuning.pass_charge_time:
				var target: Player = pc.eligible[_pass_slot]
				_pass_slot = -1
				pc.throw_ball(target, pc.pass_power(held), _pass_placement())
				return
	else:
		_pass_slot = -1
		_fake_armed = false
		# A tucked quarterback is a runner: the pass buttons do nothing until turbo
		# is released, and the jump and action buttons below work for him.
		if not player.has_ball and pad.just_pressed(&"switch_player"):
			if carrier == null or carrier.team != team:
				_switch_to_nearest()
			return

	# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
#	# In the air from a jump the action is a jump dive. Not for a quarterback who
#	# can still throw: his action button is a pass button up there too.
#	if player.state == Player.State.JUMPING and not is_passer and pad.just_pressed(&"action"):
#		pc.do_jump_dive(player, _jump_dive_aim(player, move, moving, carrier))
#		return
	if not player.can_act():
		return
	# With four men out the jump button is the fourth pass button for as long
	# as the quarterback can throw.
	var jump_is_pass: bool = is_passer and pc.eligible.size() >= PASS_ACTIONS.size()
	if pad.just_pressed(&"jump") and not jump_is_pass:
		pc.do_jump(player)
		return
	if is_passer:
		return
	# The second jump button is a pass button while the quarterback can throw,
	# and secures the ball for anyone carrying it.
	if not player.has_ball and pad.just_pressed(&"jump_alt"):
		pc.do_jump(player)
		return
	if player.has_ball:
		_carrier_moves(player, move, moving)
		return
	if not pad.just_pressed(&"action"):
		return
	# A dive always goes where the stick points. The aiming below (at the pass,
	# the loose ball, the carrier) is only for a stick left alone.
	var in_air: bool = pc.phase == PlayController.Phase.AIR or pc.phase == PlayController.Phase.TIPPED
	if moving and (in_air or pc.phase == PlayController.Phase.LOOSE or is_defending()):
		pc.do_dive(player, move.normalized())
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
	elif in_air:
		# A pass in the air that comes down too far off to aim at (or right where
		# he stands): still a dive. A shove here would stop a receiver in the
		# middle of his run at the ball.
		pc.do_dive(player, player.facing)
	elif is_defending():
		# On defense (from the snap or after a turnover) the action is always a
		# dive, aimed at the carrier when he is close.
		var target: Player = carrier if carrier != null and carrier.team != team else null
		pc.do_dive(player, _dive_direction(player, move, moving, target))
	else:
		pc.do_shove(player, move.normalized() if moving else player.facing)


## The quarterback still has the ball to hand over on a run play, or is waiting
## for the pitch back on a flea flicker.
func _in_exchange() -> bool:
	if pc.off_play == null or pc.runner == null or pc.runner == pc.qb:
		return false
	if pc.off_play.is_run:
		return not pc.handoff_done and pc.ball.carrier == pc.qb
	return pc.flicking()


## Running with the ball: spin, a stiff arm to either side, or a dive that
## gives himself up for the last few yards. (Securing the ball is read in
## update_live: it also works with a tackler on his back.)
func _carrier_moves(player: Player, move: Vector3, moving: bool) -> void:
	if pad.just_pressed(&"stiff_arm_left"):
		pc.do_stiff_arm(player, 1.0)
	elif pad.just_pressed(&"stiff_arm_right"):
		pc.do_stiff_arm(player, -1.0)
	elif pad.just_pressed(&"spin"):
		# Stick leaned across his running line: spin and sidestep that way.
		# Otherwise a plain spin, turning away from the nearest defender.
		var line: Vector3 = player.velocity.normalized() if player.velocity.length_squared() > 0.6 else player.facing
		var left: Vector3 = Vector3.UP.cross(line)
		var lean: float = move.dot(left)
		if absf(lean) > 0.3:
			pc.do_spin(player, signf(lean), true)
		else:
			pc.do_spin(player, 1.0 if _spin_direction(player).dot(left) >= 0.0 else -1.0)
	elif pad.just_pressed(&"action"):
		pc.do_dive(player, move.normalized() if moving else player.facing)


# TODO(jump-dive): shelved 2026-11-19. Re-enable or delete once we decide whether to keep it.
### Where a jump dive goes: along the stick if it is held, otherwise the same
### choices as a dive off the ground (the pass, the loose ball, the carrier),
### each from a little further off.
#func _jump_dive_aim(player: Player, move: Vector3, moving: bool, carrier: Player) -> Vector3:
#	var free: Vector3 = move.normalized() if moving else player.facing
#	if player.has_ball or moving:
#		return free
#	var at_ball: Vector3 = pc.ball_dive_direction(player, pc.jump_dive_ball_range())
#	if at_ball != Vector3.ZERO:
#		return at_ball
#	if pc.phase == PlayController.Phase.LOOSE:
#		var at_loose: Vector3 = pc.loose_dive_direction(player)
#		return at_loose if at_loose != Vector3.ZERO else free
#	if is_defending() and carrier != null and carrier.team != team:
#		return _dive_direction(player, move, moving, carrier, tuning.jump_dive_speed_scale)
#	return free


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
	player.wants_turbo = pad.pressed(&"turbo")
	# He has scored and holds the ball up, or has made a first down or a long
	# gain: the face buttons pick his dance, and do nothing else while they can.
	if pc.celebration_pick_open and player == pc.celebrant:
		if pc.can_pick_celebration(player):
			for slot: int in PASS_ACTIONS.size():
				if pad.just_pressed(PASS_ACTIONS[slot]):
					pc.pick_celebration(slot)
					break
		return
	if not pad.just_pressed(&"action") or not player.can_act():
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
	# A dive while his team celebrates brings the rest of them down on him.
	pc.start_pile_on(player)


# --- Helpers -----------------------------------------------------------------

## A bumper held as the pass leaves: left leads the receiver, right underthrows
## him. Both together cancel out.
func _pass_placement() -> PlayController.Placement:
	var lead: bool = pad.pressed(&"pass_lead")
	var under: bool = pad.pressed(&"pass_under")
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


## Where a defender's dive goes: along the stick if it is held. With the stick
## left alone, at `target` (led a little) if he is within the auto-aim range
## (times `range_scale`), otherwise straight ahead.
func _dive_direction(player: Player, move: Vector3, moving: bool, target: Player, range_scale: float = 1.0) -> Vector3:
	if moving:
		return move.normalized()
	if target != null and _flat_distance(player.position, target.position) <= tuning.dive_trigger_range * range_scale:
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
