extends SceneTree
## Headless check of deep passes and of who the person has after a throw.
##
## A receiver running straight up the field, nobody near him, is thrown a lob,
## a medium pass and a bullet at three depths, with no placement. For each it
## prints how long before the ball he was at the spot and how fast he was still
## going as it came down: a pass that takes a while to get there has to be caught
## on the run, not waited for.
##
## Then two throws for the person: they keep the quarterback after the throw,
## get the receiver with the switch button, and get him anyway at the catch.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/deep_pass_check.gd
## Optional user args after "--":
##   play=<text>   offensive play whose name contains the text (default "da bomb")
##   report        print only, judge nothing (for numbers to compare)

const POWERS: Array[float] = [0.0, 0.5, 1.0]
const POWER_NAMES: Array[String] = ["lob", "medium", "bullet"]
const DEPTHS: Array[float] = [10.0, 20.0, 30.0]
const STUCK_TICKS: int = 1200
## A pass in the air at least this long is a deep one: the ones judged.
const DEEP_FLIGHT: float = 1.2
## He may be at the spot this long before the ball, and has to be going at
## least this share of his own running speed as it comes down.
const MAX_EARLY: float = 0.3
const MIN_PACE: float = 0.7

var _game: Game
var _pc: PlayController
var _team: Team
var _play: OffensePlay
var _play_filter: String = "da bomb"
var _report_only: bool = false
var _case: int = -1
var _ticks: int = 0
var _receiver: Player
var _thrown: bool = false
var _thrown_tick: int = 0
var _early: float = -1.0
var _pace: float = 0.0
var _pace_share: float = 0.0
var _led: float = 0.0
var _short: bool = false
var _kept: bool = true
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("play="):
			_play_filter = arg.trim_prefix("play=").to_lower()
		elif arg == "report":
			_report_only = true
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
		_team = _game.human.team
		if _team == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		var tuning: Tuning = _game.tuning
		# Every throw goes exactly where it is aimed and is caught.
		tuning.accuracy_error_low = 0.0
		tuning.accuracy_error_high = 0.0
		tuning.pass_overlead_chance = 0.0
		tuning.catch_min_chance = 1.0
		tuning.ai_motion_chance = 0.0
		tuning.ai_audible_chance = 0.0
		tuning.ai_hot_route_chance = 0.0
		for play: OffensePlay in _game.offense_playbook.plays:
			if play.play_name.to_lower().contains(_play_filter):
				_play = play
		if _play == null:
			_failures.append("no play named like '%s'" % _play_filter)
			_finish()
			return
		_next()
		return
	if _receiver == null:
		return
	_ticks += 1
	if _ticks > STUCK_TICKS:
		_fail("the case never finished")
		_next()
		return
	var measured: int = POWERS.size() * DEPTHS.size()
	if not _thrown:
		var downfield: float = (_receiver.position.x - _pc.los_x) * _pc.off_dir
		@warning_ignore("integer_division")
		var depth: float = DEPTHS[_case / POWERS.size()] if _case < measured else 20.0
		if downfield >= depth and _pc.can_pass():
			var power: float = POWERS[_case % POWERS.size()] if _case < measured else 0.0
			var run: Vector3 = Vector3(_receiver.velocity.x, 0.0, _receiver.velocity.z)
			var underthrows: int = _game.get_stat(&"underthrows")
			_pc.throw_ball(_receiver, power)
			# Further than the quarterback can throw: it comes up short of him.
			_short = _game.get_stat(&"underthrows") > underthrows
			_thrown = true
			_thrown_tick = _ticks
			_early = -1.0
			# How far past where his pace alone would have him the ball comes down.
			_led = (_pc.ball.target_point - (_receiver.position + run * _pc.ball.flight_time)).dot(run.normalized()) if run.length() > 0.5 else 0.0
		elif _pc.ball_dead:
			_fail("the play ended before the throw")
			_next()
		return
	if _case < measured:
		_measure()
	elif _case == measured:
		_switch_by_button()
	else:
		_switch_at_catch()


## One of the nine throws: when he got there, and how fast he still was.
func _measure() -> void:
	var ball: Ball = _pc.ball
	if _pc.phase == PlayController.Phase.AIR and not _pc.ball_dead:
		var left: float = ball.flight_time - ball.flight_elapsed
		if _early < 0.0 and _flat(_receiver.position, ball.target_point) <= _game.tuning.catch_radius:
			_early = left
		_pace = Vector2(_receiver.velocity.x, _receiver.velocity.z).length()
		_pace_share = _pace / maxf(_receiver.max_speed(), 0.01)
		return
	var flight: float = ball.flight_time
	var caught: bool = ball.carrier == _receiver
	print("%-7s at %2.0f yd  %.2f s in the air, led %+.1f yd  there %.2f s early, %.1f yd/s (%.0f%% of his run) as it came down  %s" % [
			_case_name(), DEPTHS[_case / POWERS.size()], flight, _led, maxf(_early, 0.0), _pace, _pace_share * 100.0,
			("out of his range" if _short else "caught") if caught else "NOT CAUGHT"])
	if not _report_only:
		_expect(caught, "not caught")
		if flight >= DEEP_FLIGHT and not _short:
			_expect(_early <= MAX_EARLY, "he was at the spot %.2f s before the ball" % _early)
			_expect(_pace_share >= MIN_PACE, "he was down to %.0f%% of his run as it came down" % (_pace_share * 100.0))
	_next()


## The person keeps the quarterback after the throw; the switch button gives
## them the man it was thrown to.
func _switch_by_button() -> void:
	var since: int = _ticks - _thrown_tick
	if since == 2:
		_expect(_pc.phase == PlayController.Phase.AIR, "the ball is not in the air")
		_expect(_game.human.controlled == _pc.qb, "the person lost the quarterback at the throw")
		Input.action_press(&"switch_player")
	elif since == 5:
		Input.action_release(&"switch_player")
		_expect(_game.human.controlled == _receiver, "the switch button did not give them the receiver")
		print("%-18s quarterback kept at the throw, receiver on the button" % _case_name())
		_next()


## Left alone, they get him when he catches it.
func _switch_at_catch() -> void:
	if _pc.phase == PlayController.Phase.AIR and not _pc.ball_dead:
		_kept = _kept and _game.human.controlled == _pc.qb
		return
	_expect(_kept, "the person lost the quarterback with the ball in the air")
	_expect(_pc.ball.carrier == _receiver, "not caught")
	_expect(_game.human.controlled == _receiver, "the catch did not give them the receiver")
	print("%-18s receiver theirs at the catch" % _case_name())
	_next()


func _case_name() -> String:
	var measured: int = POWERS.size() * DEPTHS.size()
	if _case < measured:
		return POWER_NAMES[_case % POWERS.size()]
	return "switch by button" if _case == measured else "switch at catch"


func _next() -> void:
	Input.action_release(&"switch_player")
	_case += 1
	_receiver = null
	if _case >= POWERS.size() * DEPTHS.size() + 2:
		_finish()
		return
	var tuning: Tuning = _game.tuning
	_game.start_drive(_team, tuning.yard_to_x(_team.attack_dir, 15.0))
	_pc.line_up(_play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	# The defense stands well out of the way.
	for player: Player in _pc.defense.players:
		player.position = Vector3(_pc.los_x - _pc.off_dir * 12.0, 0.0, float(player.index) * 2.0 - 8.0)
		player.velocity = Vector3.ZERO
		player.frozen = true
	# The man whose route takes him furthest up the field without stopping.
	var best: float = -INF
	for player: Player in _pc.eligible:
		var brain: PlayerBrain = player.brain
		if brain.off_assign.settle or brain.route.is_empty():
			continue
		var deep: float = (brain.route[brain.route.size() - 1].x - _pc.los_x) * _pc.off_dir
		if brain.route_exit_dir.x * _pc.off_dir > 0.7 and deep > best:
			best = deep
			_receiver = player
	if _receiver == null:
		_failures.append("%s has no route straight up the field" % _play.play_name)
		_finish()
		return
	_thrown = false
	_kept = true
	_ticks = 0


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	var depth: String = ""
	if _case < POWERS.size() * DEPTHS.size():
		@warning_ignore("integer_division")
		depth = " at %.0f yd" % DEPTHS[_case / POWERS.size()]
	_failures.append("%s%s: %s" % [_case_name(), depth, what])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	Input.action_release(&"switch_player")
	if _failures.is_empty():
		print("DEEP PASS CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("DEEP PASS CHECK FAILED: %s" % failure)
		quit(1)
