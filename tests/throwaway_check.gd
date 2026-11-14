extends SceneTree
## Headless check of the quarterback throwing the ball away (LT): it comes down
## past the sideline he picked, nobody standing there can catch it, the play is
## an incomplete pass that counts as an attempt, and it cannot be done on a run
## play or with the ball tucked.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/throwaway_check.gd

enum Case { CALL_RIGHT, CALL_LEFT_CROWDED, BUTTON, BUTTON_STICK, TUCKED, RUN_PLAY }

const CASE_NAMES: Array[String] = ["thrown to +z", "thrown to -z at two men", "LT, stick at rest", "LT, stick across", "LT while tucked", "run play"]
## Physics ticks a case may take.
const STUCK_TICKS: int = 900

var _game: Game
var _pc: PlayController
var _team: Team
var _case: int = -1
var _ticks: int = 0
var _checked_air: bool = false
var _checked_dead: bool = false
var _att_before: int = 0
var _comp_before: int = 0
var _passes_before: int = 0
var _throwaways_before: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
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
		_next()
		return
	_ticks += 1
	if _ticks > STUCK_TICKS:
		_fail("the play never ended")
		_next()
		return
	var half: float = _game.tuning.half_width()

	if _ticks == 1:
		match _case:
			Case.CALL_RIGHT:
				_pc.throw_away(1.0)
			Case.CALL_LEFT_CROWDED, Case.RUN_PLAY:
				_pc.throw_away(-1.0)
			Case.BUTTON:
				Input.action_press(&"throw_away")
			Case.BUTTON_STICK:
				# Across the field, away from the sideline he is nearer to.
				_lean_to(1.0)
				Input.action_press(&"throw_away")
			Case.TUCKED:
				Input.action_press(&"turbo")
		return
	if _ticks == 3 and _case == Case.TUCKED:
		_expect(_pc.qb.is_tucked(), "turbo did not tuck the ball")
		Input.action_press(&"throw_away")
		return
	if _ticks < 6:
		return

	if _case == Case.TUCKED or _case == Case.RUN_PLAY:
		_expect(not _pc.thrown_away and _game.get_stat(&"throwaways") == _throwaways_before, "the ball was thrown away")
		_expect(_game.get_stat(&"passes") == _passes_before, "a pass was counted")
		_next()
		return

	if not _checked_air:
		_checked_air = true
		_release_buttons()
		var side: float = -1.0 if _case == Case.CALL_LEFT_CROWDED or _case == Case.BUTTON else 1.0
		var spot: Vector3 = _pc.ball.target_point
		print("%-24s aimed at x %.1f z %.1f, %.2f s in the air" % [CASE_NAMES[_case], spot.x, spot.z, _pc.ball.flight_time])
		_expect(_pc.thrown_away, "nothing was thrown away")
		_expect(_pc.phase == PlayController.Phase.AIR, "the ball is not in the air")
		_expect(spot.z * side > half + 1.0, "aimed at z %.1f, not past the %s sideline" % [spot.z, "+z" if side > 0.0 else "-z"])
		_expect(_pc.ball.intended == null and _pc.pass_intended == null, "the throw has a target")
		_expect(_game.human.controlled == _pc.qb, "the person is no longer the quarterback")
		if _case == Case.CALL_LEFT_CROWDED:
			# A receiver and a defender wait right where it comes down.
			for waiting: Player in [_pc.eligible[0], _pc.defense.players[0]]:
				waiting.position = spot
		return

	if not _pc.ball_dead:
		return
	if not _checked_dead:
		_checked_dead = true
		print("%-24s %s, ball at z %.1f after %.2f s" % [CASE_NAMES[_case], _pc.result_text(), _pc.ball.position.z, _pc.live_time])
		_expect(_pc.result == PlayController.Result.INCOMPLETE, "ruled %s" % _pc.result_text())
		_expect(_pc.catcher == null and _pc.interceptor == null, "somebody caught it")
		_expect(absf(_pc.ball.position.z) > half, "the ball came down in bounds")
		_expect(_game.get_stat(&"throwaways") == _throwaways_before + 1, "not counted as thrown away")
		return

	# Once the play has been booked.
	var state: StringName = _pc.state_machine.current_name()
	if state == &"Live" or state == &"Dead":
		return
	var line: PlayerLine = _game.stat_book.players[_pc.qb]
	_expect(_game.down == 2, "it is down %d" % _game.down)
	_expect(line.pass_att == _att_before + 1, "not a pass attempt in the box score")
	_expect(line.pass_comp == _comp_before, "a completion in the box score")
	_next()


func _next() -> void:
	_release_buttons()
	_case += 1
	if _case >= Case.size():
		_finish()
		return
	var tuning: Tuning = _game.tuning
	var dir: float = float(_team.attack_dir)
	_game.start_drive(_team, tuning.yard_to_x(_team.attack_dir, 30.0))
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.is_run == (_case == Case.RUN_PLAY) and not candidate.play_action:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")

	# The quarterback alone in the pocket, a little to the -z side of the middle.
	for player: Player in _pc.players:
		if player != _pc.qb:
			player.position = Vector3(tuning.field_length * 0.5 - dir * 35.0, 0.0, float(player.index) * 2.0 - 30.0)
			player.velocity = Vector3.ZERO
			player.frozen = true
	if _case != Case.RUN_PLAY:
		_pc.qb.position = Vector3(_pc.los_x - dir * 6.0, 0.0, -5.0)
		_pc.qb.velocity = Vector3.ZERO
	_ticks = 0
	_checked_air = false
	_checked_dead = false
	var line: PlayerLine = _game.stat_book.players[_pc.qb]
	_att_before = line.pass_att
	_comp_before = line.pass_comp
	_passes_before = _game.get_stat(&"passes")
	_throwaways_before = _game.get_stat(&"throwaways")


## Holds the stick toward the sideline at `side` (+1 or -1 along z), whichever
## way the camera is looking.
func _lean_to(side: float) -> void:
	var rig: Basis = _game.camera_rig.basis
	var want: Vector3 = Vector3(0.0, 0.0, side)
	var x: float = want.dot(Vector3(rig.x.x, 0.0, rig.x.z).normalized())
	var y: float = want.dot(Vector3(rig.z.x, 0.0, rig.z.z).normalized())
	if x > 0.3:
		Input.action_press(&"move_right", x)
	elif x < -0.3:
		Input.action_press(&"move_left", -x)
	if y > 0.3:
		Input.action_press(&"move_down", y)
	elif y < -0.3:
		Input.action_press(&"move_up", -y)


func _release_buttons() -> void:
	for action: StringName in [&"throw_away", &"turbo", &"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	_failures.append("%s: %s" % [CASE_NAMES[_case], what])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	_release_buttons()
	if _failures.is_empty():
		print("THROWAWAY CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("THROWAWAY CHECK FAILED: %s" % failure)
		quit(1)
