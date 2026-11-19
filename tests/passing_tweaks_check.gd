extends SceneTree
## Headless check of the passing tweaks: the pump fake (RB tapped by itself),
## the throw got away as the quarterback is hit or wrapped up, a pass tipped on
## its way up out of his hand, when his feet are set, and the acrobatic throw
## on the run.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/passing_tweaks_check.gd

enum Case { PUMP_TAP, PUMP_WITH_PASS, PUMP_HELD_LONG, HIT_AS_THROWN, HIT_NO_LUCK, IN_THE_GRASP, TIP_BULLET, TIP_PAST_TOP, TIP_LOB_STANDING, TIP_LOB_JUMPING, FEET_AFTER_TURBO, FEET_ON_THE_MOVE, FLAIR_THROW }

const CASE_NAMES: Array[String] = ["RB tapped", "RB held with a pass", "RB held long", "hit as he throws", "hit, no luck", "wrapped up", "bullet past a rusher", "rusher past the top", "lob over a rusher", "lob at a jumping rusher", "feet after turbo", "feet on the move", "throw on the run"]
const STUCK_TICKS: int = 900
const TICK: float = 1.0 / 60.0
const BUTTONS: Array[StringName] = [&"pass_1", &"pass_under", &"pass_lead", &"turbo", &"move_left", &"move_right", &"move_up", &"move_down"]
## Everything random about a throw that is not being tested here is off, and
## what is being tested always happens unless a case says otherwise.
const SETTINGS: Dictionary[StringName, float] = {
	&"pass_overlead_chance": 0.0, &"accuracy_error_low": 0.0, &"accuracy_error_high": 0.0,
	&"pump_bite_chance": 1.0, &"bust_coverage_scale_low": 1.0, &"bust_coverage_scale_high": 1.0, &"ai_edge_bust_scale": 1.0,
	&"pump_bite_time_min": 1.0, &"pump_bite_time_max": 1.0, &"pump_deep_scale": 1.0,
	&"hit_throw_chance": 1.0, &"hit_throw_dive_scale": 1.0, &"hit_throw_clean_chance_low": 0.0, &"hit_throw_clean_chance_high": 0.0, &"hit_throw_error": 0.0,
	&"hit_throw_short_min": 0.6, &"hit_throw_short_max": 0.6,
	&"tackle_base_chance": 100.0, &"drag_min_time": 99.0, &"fumble_chance_low": 0.0, &"fumble_chance_high": 0.0,
	&"line_tip_chance": 1.0, &"line_tip_jump_chance": 1.0,
}

var _game: Game
var _pc: PlayController
var _team: Team
var _case: int = -1
var _ticks: int = 0
var _receiver: Player
var _defender: Player
var _dir: float = 1.0
var _before: Dictionary[StringName, int] = {}
var _att_before: int = 0
var _sacked_before: int = 0
var _mark: int = -1
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
		for key: StringName in SETTINGS:
			_game.tuning.set(key, SETTINGS[key])
		_next()
		return
	_ticks += 1
	if _ticks > STUCK_TICKS:
		_fail("the case never finished")
		_next()
		return
	var qb: Player = _pc.qb
	var tuning: Tuning = _game.tuning
	match _case:
		Case.PUMP_TAP:
			if _ticks == 1:
				Input.action_press(&"pass_under")
			elif _ticks == 4:
				Input.action_release(&"pass_under")
			elif _ticks == 7:
				_expect(_gained(&"pump_fakes") == 1, "%d pump fakes" % _gained(&"pump_fakes"))
				_expect(_gained(&"passes") == 0 and _pc.ball.carrier == qb, "the ball left his hand")
				_expect(qb.pump_timer > 0.0, "his arm is not pumping")
				_expect(_gained(&"pump_fake_bites") >= 1, "nobody bit with the chance at 1")
				# Again at once: he cannot yet.
				Input.action_press(&"pass_under")
			elif _ticks == 9:
				Input.action_release(&"pass_under")
			elif _ticks == 55:
				_expect(_gained(&"pump_fakes") == 1, "a second fake inside the cooldown")
				var bitten: int = 0
				for defender: Player in _pc.defense.players:
					if defender.brain.pump_bite_time > 0.0:
						bitten += 1
						_expect(_pc.live_time < defender.brain.pump_bite_time, "the bite was over after %.2f s" % _pc.live_time)
						_expect(defender.velocity.length() < 1.5, "a man who bit is still running at %.1f yd/s" % defender.velocity.length())
				print("%-26s %d of the coverage bit and stood still" % [CASE_NAMES[_case], bitten])
				_expect(bitten >= 1, "no coverage man is sold on it")
				_next()
		Case.PUMP_WITH_PASS:
			if _ticks == 1:
				Input.action_press(&"pass_under")
			elif _ticks == 2:
				Input.action_press(&"pass_1")
			elif _ticks == 5:
				Input.action_release(&"pass_1")
			elif _ticks == 8:
				Input.action_release(&"pass_under")
			elif _ticks == 11:
				_expect(_gained(&"passes") == 1 and _gained(&"under_passes") == 1, "no underthrown pass (%d passes, %d under)" % [_gained(&"passes"), _gained(&"under_passes")])
				_expect(_gained(&"pump_fakes") == 0, "it counted as a pump fake too")
				_next()
		Case.PUMP_HELD_LONG:
			if _ticks == 1:
				Input.action_press(&"pass_under")
			elif _ticks == 22:
				Input.action_release(&"pass_under")
			elif _ticks == 26:
				_expect(_gained(&"pump_fakes") == 0, "a long hold counted as a tap")
				_next()
		Case.HIT_AS_THROWN, Case.HIT_NO_LUCK:
			if _ticks == 1:
				Input.action_press(&"pass_1")
			elif _ticks == 4:
				_expect(_game.human.winding_up() == _receiver, "he is not winding up to throw")
				_defender.position = qb.position - Vector3(_dir * 0.8, 0.0, 0.0)
				_defender.tackle_cooldown = 0.0
				# Where a clean throw would have gone: along his route, not at his feet.
				var floated: float = _pc.pass_speed(minf(_game.human.wind_up_power(), tuning.hit_throw_power))
				var aimed: float = _flat(qb.position, _pc.pass_spot(_receiver, floated))
				_pc._attempt_tackle(_defender, qb, false)
				Input.action_release(&"pass_1")
				if _case == Case.HIT_NO_LUCK:
					_expect(_gained(&"passes") == 0 and _gained(&"hit_throws") == 0, "the ball got away with the chance at 0")
					_expect(_pc.ball_dead and _pc.was_sack, "not a sack")
					_next()
					return
				var thrown: float = _flat(qb.position, _pc.ball.target_point)
				print("%-26s aimed %.1f yd, thrown %.1f yd, %.2f s in the air" % [CASE_NAMES[_case], aimed, thrown, _pc.ball.flight_time])
				_expect(_pc.phase == PlayController.Phase.AIR and _gained(&"passes") == 1, "the ball is not in the air")
				_expect(_gained(&"hit_throws") == 1 and _gained(&"bad_hit_throws") == 1 and _pc.ball.wobbly, "not a bad throw")
				_expect(absf(thrown - aimed * tuning.hit_throw_short_max) <= 0.5, "thrown %.1f yd of %.1f, not %.0f%% of the way" % [thrown, aimed, tuning.hit_throw_short_max * 100.0])
				_expect(qb.is_down(), "he is still on his feet")
				_expect(_gained(&"sacks") == 0 and not _pc.was_sack, "it is a sack as well")
			elif _ticks > 4 and _case == Case.HIT_AS_THROWN:
				var state: StringName = _pc.state_machine.current_name()
				if state == &"Live" or state == &"Dead":
					return
				var line: PlayerLine = _game.stat_book.players[qb]
				_expect(line.pass_att == _att_before + 1, "not a pass attempt in the box score")
				_expect(line.sacked == _sacked_before, "a sack in the box score")
				_next()
		Case.IN_THE_GRASP:
			if _ticks == 1:
				_defender.position = qb.position - Vector3(_dir * 0.8, 0.0, 0.0)
				qb.start_drag(_defender, 2.0)
			elif _ticks == 3:
				_expect(_pc.in_the_grasp() and not _pc.can_pass(), "he is not wrapped up")
				Input.action_press(&"pass_1")
			elif _ticks == 6:
				Input.action_release(&"pass_1")
				_expect(_pc.phase == PlayController.Phase.AIR and _gained(&"hit_throws") == 1, "the pass button did not get the ball away")
				_expect(qb.secure_timer <= 0.0, "he secured the ball instead")
				_expect(qb.is_down() and _defender.state == Player.State.NORMAL and qb.drag_partner == null, "the drag did not end with him down")
				_next()
		Case.TIP_BULLET, Case.TIP_PAST_TOP, Case.TIP_LOB_STANDING, Case.TIP_LOB_JUMPING:
			if _ticks == 1:
				var lob: bool = _case == Case.TIP_LOB_STANDING or _case == Case.TIP_LOB_JUMPING
				var off: float = 1.0
				if _case == Case.TIP_PAST_TOP:
					off = 7.0
				elif lob:
					off = 2.6
				_defender.position = qb.position + Vector3(_dir * off, 0.0, 0.0)
				if _case == Case.TIP_LOB_JUMPING:
					_defender.state = Player.State.JUMPING
					_defender.state_timer = tuning.jump_time
				_pc.throw_ball(_receiver, 0.0 if lob else 1.0)
			elif _ticks == 2:
				_mark = -1
			elif _mark < 0 and (_pc.phase != PlayController.Phase.AIR or _flat(qb.position, _pc.ball.flat_position()) > 9.0):
				_mark = _ticks
				var tipped: bool = _case == Case.TIP_BULLET or _case == Case.TIP_LOB_JUMPING
				print("%-26s %s, ball %.1f yd out at %.1f yd up" % [CASE_NAMES[_case], "tipped" if _gained(&"line_tips") > 0 else "not touched", _flat(qb.position, _pc.ball.flat_position()), _pc.ball.position.y])
				if tipped:
					_expect(_gained(&"line_tips") == 1 and _pc.phase == PlayController.Phase.TIPPED, "it was not tipped")
				else:
					_expect(_gained(&"line_tips") == 0, "it was tipped")
				_next()
		Case.FEET_AFTER_TURBO:
			if _ticks == 1:
				_lean_to(1.0)
				Input.action_press(&"turbo")
			elif _ticks == 12:
				_expect(qb.feet_set <= 0.0, "sprinting, his feet are set")
				_release_buttons()
				_mark = _ticks
			elif _ticks > 12 and qb.feet_set >= 1.0:
				var took: float = float(_ticks - _mark) * TICK
				var want: float = tuning.pass_set_feet_time
				print("%-26s set after %.2f s" % [CASE_NAMES[_case], took])
				_expect(absf(took - want) <= 0.06, "set after %.2f s, not %.2f" % [took, want])
				_next()
		Case.FEET_ON_THE_MOVE:
			# Without turbo his feet stay set however long he moves about.
			if _ticks == 1:
				_lean_to(1.0)
			elif qb.feet_set < 1.0 and _mark < 0:
				_mark = _ticks
				_fail("%.2f s on the move without turbo and his feet are not set" % (float(_ticks) * TICK))
			elif _ticks == 150:
				_expect(qb.velocity.length() > 1.0, "he never moved")
				print("%-26s still set after %.1f s on the move" % [CASE_NAMES[_case], float(_ticks) * TICK])
				_next()
		Case.FLAIR_THROW:
			if _ticks == 1:
				_lean_to(1.0)
				Input.action_press(&"turbo")
			elif _ticks == 12:
				Input.action_release(&"turbo")
			elif _ticks == 14:
				_pc.throw_ball(_receiver, 0.5)
				_expect(_gained(&"passes") == 1, "he could not throw")
				_expect(_gained(&"flair_throws") == 1, "not a throw on the run")
				_expect(qb.flair != Player.Flair.NONE and qb.flair_timer > 0.0, "no acrobatics")
				print("%-26s %s" % [CASE_NAMES[_case], Player.Flair.keys()[qb.flair]])
			elif _ticks == 60:
				_expect(qb.flair_timer <= 0.0, "the move never ends")
				_next()


func _next() -> void:
	_release_buttons()
	_case += 1
	if _case >= Case.size():
		_finish()
		return
	var tuning: Tuning = _game.tuning
	tuning.hit_throw_chance = 0.0 if _case == Case.HIT_NO_LUCK else 1.0
	_dir = float(_team.attack_dir)
	_game.start_drive(_team, tuning.yard_to_x(_team.attack_dir, 30.0))
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if not candidate.is_run and not candidate.play_action and not candidate.flea_flicker:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")

	# The quarterback alone in the pocket, his first receiver 20 yards straight
	# downfield of him, everybody else out of the way and standing still. For
	# the pump fake the coverage is let loose (well away from him).
	var qb: Player = _pc.qb
	_receiver = _pc.eligible[0]
	_defender = null
	for player: Player in _pc.players:
		if player == qb:
			continue
		player.position = Vector3(tuning.field_length * 0.5 - _dir * 35.0, 0.0, float(player.index) * 2.0 - 30.0)
		player.velocity = Vector3.ZERO
		player.frozen = true
		if player.team != _team and not player.bystander and player.brain.def_assign != null:
			var job: DefenseAssignment.Job = player.brain.def_assign.job
			var covers: bool = job == DefenseAssignment.Job.MAN or job == DefenseAssignment.Job.ZONE
			if _case == Case.PUMP_TAP and covers:
				player.frozen = false
				player.position.x = _pc.los_x + _dir * 15.0
			elif _defender == null and not covers:
				_defender = player
	if _defender == null:
		_defender = _pc.defense.players[0]
	qb.position = Vector3(_pc.los_x - _dir * 6.0, 0.0, -5.0)
	qb.velocity = Vector3.ZERO
	_receiver.position = qb.position + Vector3(_dir * 20.0, 0.0, 0.0)
	_ticks = 0
	_mark = -1
	for key: StringName in [&"pump_fakes", &"pump_fake_bites", &"passes", &"under_passes", &"hit_throws", &"bad_hit_throws", &"sacks", &"line_tips", &"flair_throws"]:
		_before[key] = _game.get_stat(key)
	var line: PlayerLine = _game.stat_book.players[qb]
	_att_before = line.pass_att
	_sacked_before = line.sacked


func _gained(key: StringName) -> int:
	return _game.get_stat(key) - _before[key]


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
	for action: StringName in BUTTONS:
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
		print("PASSING TWEAKS CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("PASSING TWEAKS CHECK FAILED: %s" % failure)
		quit(1)
