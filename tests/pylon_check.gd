extends SceneTree
## Headless check of the end zone pylons: one on each corner of both end zones,
## knocked over by a player or the ball, standing again after the next line-up,
## and a carried ball touching the pylon on the goal line its team is going for
## scores (the one on its own goal line does not).
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/pylon_check.gd

## Ticks given to a knocked pylon to fall over.
const FALL_TICKS: int = 60

enum Step { START, PLAYER_KNOCK, BALL_KNOCK, DONE }

var _game: Game
var _pc: PlayController
var _field: Field
var _step: Step = Step.START
var _wait: int = 0
var _target: Pylon
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _wait > 0:
		_wait -= 1
		return
	match _step:
		Step.START:
			_pc = _game.play_controller
			_field = _game.field
			# Nothing else moves while this runs; the physics server still steps the pylons.
			_pc.set_physics_process(false)
			_check_layout()
			# A player running into a pylon at full speed.
			_target = _field.pylons[0]
			var runner: Player = _game.home.players[0]
			var at: Vector3 = Vector3(_target.position.x, 0.0, _target.position.z)
			runner.position = at - Vector3(0.0, 0.0, signf(at.z)) * 0.5
			runner.velocity = Vector3(0.0, 0.0, signf(at.z)) * 7.0
			_field.touch_pylons(_pc.players)
			runner.velocity = Vector3.ZERO
			runner.position = Vector3(50.0, 0.0, 0.0)
			_step = Step.PLAYER_KNOCK
			_wait = FALL_TICKS
		Step.PLAYER_KNOCK:
			_expect(_target.basis.y.y < 0.5, "a player ran into a pylon and it is still up (up.y %.2f)" % _target.basis.y.y)
			print("player knock: pylon up.y %.2f, %.2f yd from home" % [_target.basis.y.y, _target.position.distance_to(_home_of(_target))])
			# A loose ball flying into another one.
			_target = _field.pylons[5]
			var hit: Pylon = _field.touch_pylons_with_ball(_target.position + Vector3(0.0, 0.4, 0.0), Vector3(6.0, -2.0, 0.0))
			_expect(hit == _target, "a ball inside a pylon did not touch it")
			_step = Step.BALL_KNOCK
			_wait = FALL_TICKS
		Step.BALL_KNOCK:
			_expect(_target.basis.y.y < 0.5, "the ball hit a pylon and it is still up (up.y %.2f)" % _target.basis.y.y)
			print("ball knock: pylon up.y %.2f" % _target.basis.y.y)
			_pc._reset_play()
			_wait = 2
			_step = Step.DONE
		Step.DONE:
			for pylon: Pylon in _field.pylons:
				_expect(pylon.is_standing() and not pylon.is_disturbed(), "a pylon is not back home after the next line-up")
			for team: Team in [_game.home, _game.away]:
				_check_score(team, true)
				_check_score(team, false)
			_finish()


func _check_layout() -> void:
	var tuning: Tuning = _game.tuning
	_expect(_field.pylons.size() == 8, "%d pylons, not 8" % _field.pylons.size())
	var front: int = 0
	for pylon: Pylon in _field.pylons:
		front += 1 if pylon.front else 0
		_expect(pylon.is_standing(), "a pylon is not standing at the start")
		var on_line: bool = false
		for x: float in [0.0, tuning.field_length, -tuning.end_zone_depth, tuning.field_length + tuning.end_zone_depth]:
			on_line = on_line or absf(pylon.position.x - x) <= pylon.size
		_expect(on_line, "pylon at x %.2f is not on a goal or end line" % pylon.position.x)
		_expect(absf(absf(pylon.position.z) - tuning.half_width()) <= pylon.size, "pylon at z %.2f is not on a sideline" % pylon.position.z)
	_expect(front == 4, "%d pylons on the goal lines, not 4" % front)


## A carrier in bounds, short of the goal line, gets the ball onto the pylon on
## the goal line he is going for (`attacking`) or on his own.
func _check_score(team: Team, attacking: bool) -> void:
	var tuning: Tuning = _game.tuning
	var dir: float = float(team.attack_dir)
	var line: float = tuning.goal_x(team.attack_dir) if attacking else tuning.own_goal_x(team.attack_dir)
	_game.conversion = false
	_game.start_drive(team, tuning.yard_to_x(team.attack_dir, 30.0))
	var play: OffensePlay = _game.offense_playbook.plays[0]
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.is_run:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	var carrier: Player = _pc.runner
	# Short of the line on the field side, whichever way he is going.
	var toward: float = dir if attacking else -dir
	carrier.position = Vector3(line - toward * 0.6, 0.0, tuning.half_width() - 0.3)
	_pc.handoff_done = true
	_pc.phase = PlayController.Phase.RUN
	_pc.ball.give_to(carrier)
	var before: int = _game.stats.get(&"pylon_touchdowns", 0)
	var ball_at: Vector3 = Vector3(line - toward * 0.05, 0.5, tuning.half_width() + 0.06)
	var hit: Pylon = _field.touch_pylons_with_ball(ball_at, Vector3(toward * 6.0, 0.0, 1.0))
	_expect(hit != null and hit.front and is_equal_approx(hit.line_x, line), "%s: the ball did not touch the goal-line pylon" % team.team_name)
	_pc._check_carrier(hit)
	var scored: bool = _pc.ball_dead and _pc.result == PlayController.Result.TOUCHDOWN
	var label: String = "attacking" if attacking else "own goal"
	print("%-6s %-8s pylon: %s, spot %.2f" % [team.team_name, label, _pc.result_text() if _pc.ball_dead else "still live", _pc.dead_spot_x])
	if attacking:
		_expect(scored, "%s: ball on the pylon it is going for is not a touchdown" % team.team_name)
		_expect(is_equal_approx(_pc.dead_spot_x, line), "%s: spotted at %.2f, not the goal line" % [team.team_name, _pc.dead_spot_x])
		_expect(_game.stats.get(&"pylon_touchdowns", 0) == before + 1, "%s: pylon_touchdowns not counted" % team.team_name)
	else:
		_expect(not scored, "%s: ball on its own goal-line pylon scored" % team.team_name)
	_pc._reset_play()


func _home_of(pylon: Pylon) -> Vector3:
	return pylon.get("_home").origin


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("PYLON CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("PYLON CHECK FAILED: %s" % failure)
		quit(1)
