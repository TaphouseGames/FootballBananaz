extends SceneTree
## Headless check of a ball carrier's dive, for both teams (so both directions):
## in the open field he is down when his body lands and not before, and at the
## goal line the score counts on the tick the ball gets there, on a touchdown
## and on a try alike.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/dive_check.gd

enum Case { OPEN_FIELD, GOAL_LINE, TRY }

const CASE_NAMES: Array[String] = ["open field", "goal line", "2-point try"]
## Yards short of the goal line the goal-line dives start from.
const GOAL_START: float = 2.0
## Body height (see PlayerFall) below which he is lying on the turf.
const TURF_HEIGHT: float = 0.45

var _game: Game
var _pc: PlayController
var _index: int = -1
var _case: Case = Case.OPEN_FIELD
var _team: Team
var _runner: Player
var _ticks: int = 0
var _down_tick: int = -1
var _down_x: float = 0.0
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
	if _pc == null:
		_pc = _game.play_controller
		_next()
		return
	_ticks += 1
	var dir: float = float(_team.attack_dir)
	var goal: float = _game.tuning.goal_x(_team.attack_dir)
	var front: float = _front_x()
	if _down_tick < 0 and _runner.is_down():
		_down_tick = _ticks
		_down_x = _runner.position.x
	if not _pc.ball_dead:
		if _case != Case.OPEN_FIELD and (front - goal) * dir >= 0.0:
			_fail("the ball is over the goal line and the play is still live")
			_next()
		elif _pc.live_time > 3.0:
			_fail("the play never ended")
			_next()
		return

	var label: String = "%-12s %-5s" % [CASE_NAMES[_case], _team.team_name]
	if _case == Case.OPEN_FIELD:
		var waited: int = _ticks - _down_tick if _down_tick >= 0 else -1
		var slid: float = (_runner.position.x - _down_x) * dir
		print("%s  whistle %d ticks after the leap ended, %.2f yd further on, body at %.2f, spot %.2f, ball %.2f, player %.2f" % [label, waited, slid, _runner.body.position.y, _pc.dead_spot_x, _pc.ball.position.x, _runner.position.x])
		_expect(_pc.result == PlayController.Result.TACKLED and _pc.was_dive, "not ruled down by his own dive")
		_expect(waited > 0, "whistle blew on the tick the leap ended, before he landed")
		_expect(_runner.is_grounded(), "whistle blew before the fall had landed")
		_expect(_runner.body.position.y <= TURF_HEIGHT, "whistle blew with the body %.2f up" % _runner.body.position.y)
		_expect(absf(_pc.dead_spot_x - front) < 0.05, "spotted at %.2f, the ball was at %.2f" % [_pc.dead_spot_x, front])
	else:
		var short: float = (goal - _runner.position.x) * dir
		print("%s  %s with the ball %.2f yd over the line, his centre %.2f yd short of it, state %s" % [label, _pc.result_text(), (front - goal) * dir, short, Player.State.keys()[_runner.state]])
		_expect(_pc.result == PlayController.Result.TOUCHDOWN, "no score")
		_expect(_runner.state == Player.State.DIVING, "did not score in the air")
		_expect(short > 0.0, "scored on his body, not on the ball")
		_expect(_pc.result_text() == ("2 POINTS!" if _case == Case.TRY else "TOUCHDOWN!"), "called %s" % _pc.result_text())
	_next()


## The furthest point downfield of the runner and the ball he carries.
func _front_x() -> float:
	var dir: float = float(_team.attack_dir)
	return _runner.position.x if (_runner.position.x - _pc.ball.position.x) * dir > 0.0 else _pc.ball.position.x


func _next() -> void:
	_game.conversion = false
	_index += 1
	if _index >= Case.size() * 2:
		_finish()
		return
	@warning_ignore("integer_division")
	_case = (_index / 2) as Case
	_team = _game.home if _index % 2 == 0 else _game.away
	var dir: float = float(_team.attack_dir)
	var goal: float = _game.tuning.goal_x(_team.attack_dir)
	_game.start_drive(_team, _game.tuning.yard_to_x(_team.attack_dir, 30.0))
	if _case == Case.TRY:
		_game.start_conversion(_team)
	var play: OffensePlay = _game.offense_playbook.plays[0]
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.is_run:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")

	# The runner has it, alone on the field, and dives straight ahead.
	_runner = _pc.runner
	for player: Player in _pc.players:
		if player != _runner:
			player.position = Vector3(_game.tuning.field_length * 0.5 - dir * 30.0, 0.0, float(player.index) * 2.0 - 30.0)
			player.frozen = true
	var start_x: float = _game.tuning.field_length * 0.5
	if _case != Case.OPEN_FIELD:
		start_x = goal - dir * GOAL_START
	_runner.position = Vector3(start_x, 0.0, 0.0)
	_runner.velocity = Vector3.ZERO
	_runner.facing = Vector3(dir, 0.0, 0.0)
	_pc.handoff_done = true
	_pc.phase = PlayController.Phase.RUN
	_pc.ball.give_to(_runner)
	_pc.do_dive(_runner, Vector3(dir, 0.0, 0.0))
	_ticks = 0
	_down_tick = -1
	_expect(_runner.state == Player.State.DIVING, "the dive did not start")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	_failures.append("%s, %s: %s" % [CASE_NAMES[_case], _team.team_name, what])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("DIVE CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("DIVE CHECK FAILED: %s" % failure)
		quit(1)
