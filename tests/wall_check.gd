extends SceneTree
## Headless check of the wall round the field as a solid thing. A player who
## runs into it stays on his feet and slides along it; one knocked into it fast
## from close by is flattened against it, sticks, and gets up again; a carrier's
## dive into it is down there, and not flattened when only his hands reach it;
## the ball comes back off it, a pass included,
## which stays live; and nothing is out of bounds any more, except a ball that
## goes over the wall into the stands.
##
## The play is lined up and snapped, then stopped, and each case moves the one
## player or the ball by hand, so that nobody else gets in the way.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/wall_check.gd

const DT: float = 1.0 / 60.0

var _game: Game
var _pc: PlayController
var _tuning: Tuning
var _done: bool = false
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _done or _game == null or not _game.is_node_ready() or _game.play_controller == null:
		return
	_done = true
	_pc = _game.play_controller
	_tuning = _game.tuning
	_check_shape()
	_check_running()
	_check_knocked()
	_check_dive()
	_check_loose_ball()
	_check_pass()
	_check_rules()
	_finish()


# --- The cases ---------------------------------------------------------------------

func _check_shape() -> void:
	var side: float = _tuning.half_width() + _tuning.wall_gap
	var end: float = _tuning.field_length + _tuning.end_zone_depth + _tuning.wall_gap
	_expect(is_equal_approx(Stadium.wall_distance(_tuning, 50.0, side), 0.0), "the side wall is not %.1f yd from the middle" % side)
	_expect(is_equal_approx(Stadium.wall_distance(_tuning, end, 0.0), 0.0), "the end wall is not at x %.1f" % end)
	_expect(Stadium.wall_distance(_tuning, 50.0, 0.0) < -10.0, "midfield is not well inside the wall")
	_expect(Stadium.wall_normal(_tuning, 50.0, side).is_equal_approx(Vector3(0.0, 0.0, -1.0)), "the +z wall does not face -z")
	_expect(Stadium.wall_normal(_tuning, 50.0, -side).is_equal_approx(Vector3(0.0, 0.0, 1.0)), "the -z wall does not face +z")
	_expect(Stadium.wall_normal(_tuning, end, 3.0).is_equal_approx(Vector3(-1.0, 0.0, 0.0)), "the right end wall does not face -x")
	var corner: Vector3 = Stadium.wall_normal(_tuning, end, side)
	_expect(corner.x < -0.5 and corner.z < -0.5, "the corner does not face the middle of the field")
	var player_height: float = 1.95
	_expect(Stadium.WALL_HEIGHT > player_height and Stadium.WALL_HEIGHT < player_height + 0.8, "the wall is %.1f high, a player %.2f" % [Stadium.WALL_HEIGHT, player_height])


## On his feet he is stopped, not knocked over, and can run along the wall.
func _check_running() -> void:
	var player: Player = _stage()
	var side: float = _tuning.half_width() + _tuning.wall_gap
	_put(player, Vector3(50.0, 0.0, side - 3.0))
	player.move_input = Vector3(0.0, 0.0, 1.0)
	var splats: int = 0
	for i: int in 90:
		player.integrate(DT)
		splats += int(player.wall_hit > 0.0)
	var gap: float = -Stadium.wall_distance(_tuning, player.position.x, player.position.z)
	print("running in:   %.2f yd from the wall, state %d" % [gap, player.state])
	_expect(gap > _tuning.wall_standoff - 0.02 and gap < 1.0, "a player run at the wall stands %.2f yd from it" % gap)
	_expect(_depth(player) <= 0.0, "he is %.2f yd into the wall" % _depth(player))
	_expect(player.state == Player.State.NORMAL and splats == 0, "a player who ran into the wall on his feet was flattened")
	_expect(absf(player.velocity.z) < 0.5, "he still has %.1f yd/s into the wall" % player.velocity.z)
	var from_x: float = player.position.x
	player.move_input = Vector3(1.0, 0.0, 1.0).normalized()
	for i: int in 60:
		player.integrate(DT)
	_expect(player.position.x > from_x + 2.0, "he cannot run along the wall: %.1f yd in a second" % (player.position.x - from_x))
	_expect(player.state == Player.State.NORMAL, "running along the wall knocked him over")
	# The end walls and the corners hold him as well.
	_put(player, Vector3(_tuning.field_length + _tuning.end_zone_depth - 2.0, 0.0, side - 2.0))
	player.move_input = Vector3(1.0, 0.0, 1.0).normalized()
	for i: int in 120:
		player.integrate(DT)
	gap = -Stadium.wall_distance(_tuning, player.position.x, player.position.z)
	_expect(gap > _tuning.wall_standoff - 0.02 and gap < 1.0, "in the corner he is %.2f yd from the wall" % gap)
	_expect(_depth(player) <= 0.0, "in the corner he is %.2f yd into the wall" % _depth(player))


## Knocked into it hard he is flattened and sticks; knocked into it gently not.
func _check_knocked() -> void:
	var player: Player = _stage()
	var side: float = _tuning.half_width() + _tuning.wall_gap
	_put(player, Vector3(40.0, 0.0, -(side - _tuning.wall_standoff - 1.2)))
	player.knock_down(Vector3(0.0, 0.0, -1.0) * _tuning.shove_knockdown_impulse, _tuning.knockdown_time)
	var hit_at: int = -1
	var hit_speed: float = 0.0
	var up_at: int = -1
	var stuck_ticks: int = 0
	var thinnest: float = 1.0
	var deepest: float = -100.0
	var nearest: float = 100.0
	player.heal()
	for i: int in 300:
		var before: float = -Stadium.wall_distance(_tuning, player.position.x, player.position.z)
		player.integrate(DT)
		deepest = maxf(deepest, _depth(player))
		if player.wall_hit > 0.0:
			# Only from close by: a tick's travel and wall_splat_range at most.
			_expect(before <= _tuning.wall_splat_range + player.wall_hit * DT + 0.01, "he was flattened from %.2f yd off the wall" % before)
			_expect(hit_at < 0, "he was flattened twice by one shove")
			hit_at = i
			hit_speed = player.wall_hit
			_expect(player.is_dazed() and not player.injured, "flattened against the wall he is not dazed")
		if hit_at >= 0 and player.fall.stick >= 1.0:
			stuck_ticks += 1
			nearest = minf(nearest, -Stadium.wall_distance(_tuning, player.position.x, player.position.z))
			_expect(player.is_down() and player.velocity.length() < 0.01, "he moved while stuck to the wall")
		thinnest = minf(thinnest, _thickness(player, Vector3(0.0, 0.0, 1.0)))
		if hit_at >= 0 and up_at < 0 and not player.is_down():
			up_at = i
	print("knocked in:   hit the wall at %.1f yd/s, stuck for %.2f s, squashed to %.2f, up after %.2f s" % [hit_speed, float(stuck_ticks) * DT, thinnest, float(up_at - hit_at) * DT])
	_expect(hit_at >= 0, "a player shoved at the wall from 1.2 yd was not flattened against it")
	_expect(nearest < 0.3, "flattened, he is %.2f yd from the wall" % nearest)
	_expect(deepest <= 0.0, "hitting the wall, sticking to it or coming off it he got %.2f yd into it" % deepest)
	_expect(player.fall.kind == PlayerFall.Kind.SPLAT, "his fall is not the one off the wall")
	_expect(absf(float(stuck_ticks) * DT - _tuning.wall_splat_stick_time) < 0.06, "he stuck for %.2f s" % (float(stuck_ticks) * DT))
	_expect(thinnest < 0.4, "his body was never pressed flat (%.2f at its thinnest)" % thinnest)
	_expect(up_at > hit_at, "he never got up again")
	_expect(absf(float(up_at - hit_at) * DT - _tuning.wall_splat_stick_time - _tuning.wall_splat_daze_time) < 0.1, "he was down for %.2f s after hitting the wall" % (float(up_at - hit_at) * DT))
	# Up from it he is injured: the rest of this play and the next one.
	_expect(player.injured and not player.is_dazed(), "up from the wall he is not injured")
	for plays: int in _tuning.injury_plays:
		player.next_play()
		_expect(player.injured, "he is not injured for play %d after the wall" % (plays + 1))
	player.next_play()
	_expect(not player.injured, "he is still injured %d plays after the wall" % (_tuning.injury_plays + 1))
	if up_at > hit_at:
		var gap: float = -Stadium.wall_distance(_tuning, player.position.x, player.position.z)
		_expect(gap >= _tuning.wall_standoff - 0.02, "back on his feet he is %.2f yd from the wall" % gap)
		_expect(absf(_thickness(player, Vector3(0.0, 0.0, 1.0)) - 1.0) < 0.02 and absf(player.body.basis.determinant() - 1.0) < 0.02, "his body did not come back to its shape")

	# From further off he has slowed down by the time he gets there.
	_put(player, Vector3(40.0, 0.0, -(side - _tuning.wall_standoff - 4.2)))
	player.knock_down(Vector3(0.0, 0.0, -1.0) * _tuning.shove_knockdown_impulse, _tuning.knockdown_time)
	var soft_hits: int = 0
	deepest = -100.0
	for i: int in 200:
		player.integrate(DT)
		soft_hits += int(player.wall_hit > 0.0)
		deepest = maxf(deepest, _depth(player))
	_expect(deepest <= 0.0, "lying by the wall he is %.2f yd into it" % deepest)
	_expect(soft_hits == 0, "a player who slid gently into the wall was flattened")
	_expect(not player.injured and not player.is_dazed(), "a player who slid gently into the wall was hurt")
	_expect(-Stadium.wall_distance(_tuning, player.position.x, player.position.z) >= _tuning.wall_standoff - 0.02, "he slid into the wall")


## A carrier who dives into the wall is down where he hits it.
## Stretched out he meets it with his hands, his middle about a yard off: he is
## flattened only if that is within wall_splat_range.
func _check_dive() -> void:
	var range_set: float = _tuning.wall_splat_range
	_tuning.wall_splat_range = 2.0
	_dive_at_wall(true)
	_tuning.wall_splat_range = 0.5
	_dive_at_wall(false)
	_tuning.wall_splat_range = range_set


func _dive_at_wall(near_enough: bool) -> void:
	var player: Player = _stage()
	var side: float = _tuning.half_width() + _tuning.wall_gap
	player.heal()
	_put(player, Vector3(45.0, 0.0, side - 2.0))
	_pc.ball.give_to(player)
	_pc.phase = PlayController.Phase.RUN
	player.start_dive(Vector3(0.0, 0.0, 1.0))
	var hit: bool = false
	var ticks: int = 0
	var deepest: float = -100.0
	while ticks < 120 and not _pc.ball_dead:
		ticks += 1
		player.integrate(DT)
		deepest = maxf(deepest, _depth(player))
		hit = hit or player.wall_hit > 0.0
		_pc.ball.integrate(DT)
		_pc._check_carrier()
	print("dive at it:   %s after %.2f s, %s" % [_pc.result_text(), float(ticks) * DT, "flattened" if hit else "not flattened"])
	if near_enough:
		_expect(hit, "a dive into the wall did not flatten him")
	else:
		_expect(not hit, "a diver who only reached the wall with his hands was flattened")
		_expect(player.fall.kind != PlayerFall.Kind.SPLAT and not player.is_dazed(), "a dive that only touched the wall left him dazed")
	_expect(deepest <= 0.0, "diving at the wall he got %.2f yd into it" % deepest)
	_expect(_pc.ball_dead and _pc.result == PlayController.Result.TACKLED and _pc.was_dive, "a carrier's dive into the wall is ruled %s" % _pc.result_text())
	_expect(_pc.ball.carrier == player, "he lost the ball on the wall")


## A loose ball comes back off the wall, keeps going along it, and stays in.
func _check_loose_ball() -> void:
	_stage()
	var ball: Ball = _pc.ball
	var side: float = _tuning.half_width() + _tuning.wall_gap
	# Straight at it.
	ball.position = Vector3(50.0, 0.6, side - 0.5)
	ball.tip(Vector3(0.0, 1.0, 9.0))
	var furthest: float = _run_ball(ball, 30)
	_expect(furthest <= 0.0, "a ball thrown at the wall got %.2f yd into it" % furthest)
	_expect(ball.loose_velocity().z < 0.0 or ball.position.z < side - 0.5, "it did not come back off the wall")
	# At a shallow angle.
	ball.position = Vector3(50.0, 0.6, side - 0.3)
	ball.tip(Vector3(9.0, 1.5, 3.0))
	furthest = maxf(furthest, _run_ball(ball, 10))
	var pace: Vector3 = ball.loose_velocity()
	print("loose ball:   off the wall at (%.1f, %.1f) from (9.0, 3.0)" % [pace.x, pace.z])
	_expect(pace.x > 4.0 and pace.z < 0.0, "a ball that met the wall at an angle did not carry on along it")
	# Into a corner.
	var end: float = _tuning.field_length + _tuning.end_zone_depth + _tuning.wall_gap
	ball.position = Vector3(end - 1.5, 0.6, side - 1.5)
	ball.tip(Vector3(7.0, 1.0, 7.0))
	furthest = maxf(furthest, _run_ball(ball, 120))
	_expect(furthest <= 0.0, "a ball got %.2f yd into the wall" % furthest)
	_expect(ball.position.x < end and ball.position.z < side, "a ball sent into the corner ended up at (%.1f, %.1f)" % [ball.position.x, ball.position.z])


## A pass that meets the wall comes back off it, and is live until it lands.
func _check_pass() -> void:
	_stage()
	var ball: Ball = _pc.ball
	var qb: Player = _pc.qb
	var side: float = _tuning.half_width() + _tuning.wall_gap
	var before: int = _game.get_stat(&"wall_passes")
	_expect(ball.carrier == qb and _pc.phase == PlayController.Phase.POCKET, "the quarterback does not have the ball after the snap")
	ball.throw_to(qb, _pc.eligible[0], Vector3(qb.position.x, 0.0, side + 3.0), 22.0, _tuning, 0.4)
	_pc.phase = PlayController.Phase.AIR
	_pc.passer = qb
	_pc.pass_intended = _pc.eligible[0]
	_pc.throw_time = _pc.live_time
	var off_wall: bool = false
	var furthest: float = -100.0
	var ticks: int = 0
	while ticks < 400 and not _pc.ball_dead and (ball.carrier == null or not off_wall):
		ticks += 1
		_pc.simulate(DT)
		furthest = maxf(furthest, Stadium.wall_distance(_tuning, ball.position.x, ball.position.z))
		if ball.hit_wall:
			off_wall = true
			_expect(_pc.phase == PlayController.Phase.TIPPED and not _pc.ball_dead, "a pass off the wall is not live")
			_expect(not _pc._tip_untouched, "nobody is allowed to catch a pass off the wall")
			_expect(ball.loose_velocity().z < 0.0, "the pass did not come back off the wall")
	var how: String = _pc.result_text() if _pc.ball_dead else "caught"
	print("pass at it:   %s, %s after %.2f s" % ["came back off the wall" if off_wall else "never met the wall", how, float(ticks) * DT])
	_expect(off_wall, "a pass thrown low at the wall did not hit it")
	_expect(furthest <= 0.0, "the pass got %.2f yd into the wall" % furthest)
	_expect(_game.get_stat(&"wall_passes") == before + 1, "the pass off the wall was not counted")
	_expect(_pc.ball_dead or ball.carrier != null, "the pass off the wall never came down")
	if _pc.ball_dead and ball.carrier == null:
		_expect(_pc.result == PlayController.Result.INCOMPLETE, "on the turf it is ruled %s" % _pc.result_text())


## No out of bounds: a carrier or a loose ball past the sideline is in play.
## Only a ball in the stands is dead.
func _check_rules() -> void:
	var player: Player = _stage()
	var past_line: float = _tuning.half_width() + 0.35
	_put(player, Vector3(45.0, 0.0, past_line))
	_pc.ball.give_to(player)
	_pc.phase = PlayController.Phase.RUN
	_pc.ball.integrate(DT)
	_pc._check_carrier()
	_expect(not _pc.ball_dead, "a carrier past the sideline is ruled %s" % _pc.result_text())

	_stage()
	_pc.ball.fumble(Vector3.ZERO)
	_pc.ball.position = Vector3(45.0, Ball.GROUND_HEIGHT, -past_line)
	_pc.phase = PlayController.Phase.LOOSE
	_pc.ball.integrate(DT)
	_pc._check_loose_ball(DT)
	_expect(not _pc.ball_dead, "a loose ball past the sideline is ruled %s" % _pc.result_text())

	if not _tuning.stadium_enabled:
		return
	_pc.ball.position = Vector3(45.0, 9.0, _tuning.half_width() + 5.0)
	var ticks: int = 0
	while ticks < 300 and not _pc.ball_dead:
		ticks += 1
		_pc.ball.integrate(DT)
		_pc._check_loose_ball(DT)
	print("in the stands: %s" % (_pc.result_text() if _pc.ball_dead else "still live"))
	_expect(_pc.ball_dead and _pc.result == PlayController.Result.OUT_OF_PLAY, "a ball in the stands is %s" % ("ruled " + _pc.result_text() if _pc.ball_dead else "still live"))


# --- Helpers -----------------------------------------------------------------------

## A play lined up, snapped and stopped. Returns a player to move by hand.
func _stage() -> Player:
	var team: Team = _game.home
	_pc.process_mode = Node.PROCESS_MODE_INHERIT
	_game.conversion = false
	_game.half = 1
	_game.clock = 100.0
	_game.start_drive(team, _tuning.yard_to_x(team.attack_dir, 40.0))
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if not candidate.is_run and not candidate.play_action and not candidate.flea_flicker:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_pc.process_mode = Node.PROCESS_MODE_DISABLED
	return _game.away.players[0]


func _put(player: Player, spot: Vector3) -> void:
	player.position = spot
	player.velocity = Vector3.ZERO
	player.move_input = Vector3.ZERO
	player.state = Player.State.NORMAL
	player.state_timer = 0.0
	player.frozen = false
	player.fall.reset()


## How thick his body is drawn along `normal` (a flat direction in the world),
## as a share of what it is: 1 unless he is pressed against the wall.
func _thickness(player: Player, normal: Vector3) -> float:
	return (player.body.basis.transposed() * normal.rotated(Vector3.UP, -player.rotation.y)).length()


## How far the deepest part of him is into the wall, in yards: every bone
## below the top of it. 0 or less when all of him is on the field side.
func _depth(player: Player) -> float:
	var skeleton: Skeleton3D = player.animator.skeleton
	var deepest: float = -100.0
	for i: int in skeleton.get_bone_count():
		var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
		if at.y < Stadium.WALL_HEIGHT:
			deepest = maxf(deepest, Stadium.wall_distance(_tuning, at.x, at.z))
	return deepest


## Moves the ball on by `ticks`; returns how far into the wall it got at most.
func _run_ball(ball: Ball, ticks: int) -> float:
	var furthest: float = -100.0
	for i: int in ticks:
		ball.integrate(DT)
		furthest = maxf(furthest, Stadium.wall_distance(_tuning, ball.position.x, ball.position.z))
	return furthest


func _expect(ok: bool, what: String) -> void:
	if not ok and not _failures.has(what):
		_failures.append(what)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("wall_check PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("FAIL: %s" % failure)
		print("wall_check FAILED")
		quit(1)
