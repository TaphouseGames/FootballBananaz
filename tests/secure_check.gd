extends SceneTree
## Headless check of securing the ball (A pressed with the ball in his hands:
## a short burst, then a cooldown):
## - he is faster by Tuning.secure_speed_scale;
## - running a tackler over: only one in front of a moving carrier who is
##   stronger, likelier the bigger the gap in strength, and half as likely
##   against a dive;
## - he fumbles less when tackled;
## - he shakes off a tackler on his back more often;
## - the CPU carrier: the strong one lowers his shoulder and runs a weak
##   tackler over, the weak one only covers the ball;
## - the button: a press of A secures for a carrier (and does not jump him),
##   holding it adds nothing, a second press waits for the cooldown, and it
##   stays a pass button for a quarterback who can throw.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/secure_check.gd
## About 3 minutes. `-- quick` runs a third of the trials (wider tolerances).

enum Kind { TRUCK, FUMBLE, DRAG, CPU, BUTTON, PASSER }

const STUCK_TICKS: int = 300
const TRUCK_ROLLS: int = 300
## Chances the trials are run at, so that a few hundred of them tell the two
## cases apart.
const FUMBLE_CHANCE: float = 0.6
const SHAKE_BONUS: float = 0.3

var _game: Game
var _pc: PlayController
var _tuning: Tuning
var _person: Team
var _cpu: Team
var _trials: Array[Dictionary] = []
var _trial: int = -1
var _ticks: int = 0
var _man: Player
var _tackler: Player
var _dir: float = 1.0
var _before: Dictionary[StringName, int] = {}
## Per label: x = times it happened, y = trials that counted.
var _tally: Dictionary[String, Vector2i] = {}
var _discarded: int = 0
var _secure_speed_scale: float = 1.0
var _shake_bonus: float = 0.0
var _fumble_low: float = 0.0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _build_trials() -> void:
	var scale: float = 0.34 if OS.get_cmdline_user_args().has("quick") else 1.0
	# Straight rolls of the run-over, one tick each.
	for gap: int in [-20, 0, 20, 40, 60]:
		_trials.append({"kind": Kind.TRUCK, "label": "gap %+d" % gap, "gap": gap, "want": clampf(gap * _tuning.secure_truck_chance_per_point, 0.0, _tuning.secure_truck_chance_max)})
	_trials.append({"kind": Kind.TRUCK, "label": "not securing", "gap": 40, "secure": false, "want": 0.0})
	_trials.append({"kind": Kind.TRUCK, "label": "tackler behind", "gap": 40, "from": Vector3(-1.0, 0.0, 0.0), "want": 0.0})
	_trials.append({"kind": Kind.TRUCK, "label": "tackler at his side", "gap": 40, "from": Vector3(0.0, 0.0, 1.0), "want": 0.0})
	_trials.append({"kind": Kind.TRUCK, "label": "a dive", "gap": 40, "diving": true, "want": 40.0 * _tuning.secure_truck_chance_per_point * _tuning.secure_truck_dive_scale})
	_trials.append({"kind": Kind.TRUCK, "label": "standing still", "gap": 40, "speed": 1.0, "want": 0.0})
	for i: int in roundi(150 * scale):
		_trials.append({"kind": Kind.FUMBLE, "label": "fumble plain", "secure": false})
		_trials.append({"kind": Kind.FUMBLE, "label": "fumble secured", "secure": true})
	for i: int in roundi(80 * scale):
		_trials.append({"kind": Kind.DRAG, "label": "shake-off plain", "bonus": 0.0})
		_trials.append({"kind": Kind.DRAG, "label": "shake-off secured", "bonus": SHAKE_BONUS})
	for i: int in roundi(40 * scale):
		_trials.append({"kind": Kind.CPU, "label": "CPU strong", "strength": 90})
	for i: int in roundi(24 * scale):
		_trials.append({"kind": Kind.CPU, "label": "CPU weak", "strength": 20})
	_trials.append({"kind": Kind.BUTTON, "label": "button"})
	_trials.append({"kind": Kind.PASSER, "label": "passer"})


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
		_tuning = _game.tuning
		_person = _game.human.team
		if _person == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_cpu = _person.opponent
		_secure_speed_scale = _tuning.secure_speed_scale
		_shake_bonus = _tuning.secure_shake_off_bonus
		_fumble_low = _tuning.fumble_chance_low
		# A CPU carrier does nothing but run, and secure the ball when told to.
		for value: StringName in [&"ai_edge_hurdle_chance", &"ai_spin_chance", &"ai_stiff_arm_chance", &"ai_edge_move_chance", \
				&"ai_jump_dive_chance", &"ai_edge_jump_dive_chance", &"ai_move_mistime_chance", &"ai_edge_move_mistime_chance", \
				&"ai_dive_chance", &"ai_edge_dive_chance", &"ai_secure_dive_chance"]:
			_tuning.set(value, 0.0)
		# Every tackle that is not run over holds.
		_tuning.tackle_base_chance = 4.0
		_build_trials()
		_next()
		return
	_ticks += 1
	var trial: Dictionary = _trials[_trial]
	if _ticks > STUCK_TICKS:
		_fail("never finished")
		_next()
		return
	match trial["kind"]:
		Kind.TRUCK:
			_tick_truck(trial)
		Kind.FUMBLE:
			_tick_fumble(trial)
		Kind.DRAG:
			_tick_drag(trial)
		Kind.CPU:
			_tick_cpu(trial)
		Kind.BUTTON:
			_tick_button()
		Kind.PASSER:
			_tick_passer()


## Rolls the run-over many times over in one tick, putting both men back each time.
func _tick_truck(trial: Dictionary) -> void:
	var from: Vector3 = trial.get("from", Vector3(1.0, 0.0, 0.0))
	# `from` is where the tackler stands, with x along the carrier's running line.
	var offset: Vector3 = Vector3(from.x * _dir, 0.0, from.z)
	var spot: Vector3 = _man.position + offset
	var speed: float = trial.get("speed", 7.0)
	var secure: bool = trial.get("secure", true)
	var hits: int = 0
	for i: int in TRUCK_ROLLS:
		_tackler.reset_for_play(spot, -offset)
		if trial.get("diving", false):
			_tackler.state = Player.State.DIVING
		_man.velocity = Vector3(_dir * speed, 0.0, 0.0)
		_man.facing = Vector3(_dir, 0.0, 0.0)
		_man.secure_timer = 1.0 if secure else 0.0
		if _pc._try_truck(_tackler, _man, -offset.normalized()):
			hits += 1
			_expect(_tackler.is_down(), "run over but still on his feet")
	_tackler.reset_for_play(spot, -offset)
	var share: float = float(hits) / float(TRUCK_ROLLS)
	var want: float = trial["want"]
	print("run-over, %-20s %3d of %d: %.0f%% (should be %.0f%%)" % [trial["label"], hits, TRUCK_ROLLS, share * 100.0, want * 100.0])
	if want <= 0.0:
		_expect(hits == 0, "%d run-overs where there should be none" % hits)
	else:
		_expect(absf(share - want) <= 0.09, "%.0f%% run-overs, should be near %.0f%%" % [share * 100.0, want * 100.0])
	_expect(_gained(&"trucks") == hits, "the trucks counter says %d, there were %d" % [_gained(&"trucks"), hits])

	if trial["label"] == "gap +0":
		# While he is set up with the ball: how much faster securing makes him.
		_man.secure_timer = 0.0
		var plain: float = _man.max_speed()
		_man.secure_timer = 1.0
		var quick: float = _man.max_speed()
		print("top speed %.2f, securing %.2f: x%.2f (should be x%.2f)" % [plain, quick, quick / plain, _secure_speed_scale])
		_expect(absf(quick / plain - _secure_speed_scale) < 0.001, "securing makes him x%.3f as fast, should be x%.3f" % [quick / plain, _secure_speed_scale])
		_expect(_secure_speed_scale > 1.0, "securing does not speed him up")
		_man.state = Player.State.SPINNING
		_expect(not _man.is_securing(), "securing in the middle of a spin")
		_man.state = Player.State.NORMAL
	_man.secure_timer = 0.0
	_next()


func _tick_fumble(trial: Dictionary) -> void:
	var fumbled: bool = _gained(&"fumbles") > 0
	if not fumbled and not _pc.ball_dead:
		return
	if _gained(&"broken_tackles") > 0 or _gained(&"drags") > 0:
		_discarded += 1
		_next()
		return
	var secured: int = _gained(&"secured_tackles")
	_expect(secured == (1 if trial["secure"] else 0), "tackled with the ball secured %d times" % secured)
	_count(trial["label"], fumbled)
	_next()


func _tick_drag(trial: Dictionary) -> void:
	var shook: bool = _gained(&"shake_offs") > 0
	if not shook and not _pc.ball_dead and _gained(&"fumbles") == 0:
		return
	if _gained(&"drags") != 1 or _gained(&"trucks") > 0:
		_discarded += 1
		_next()
		return
	# A CPU carrier with a tackler on his back always secures the ball.
	_expect(_gained(&"secured_drags") == 1, "the drag ended without the ball secured")
	_count(trial["label"], shook)
	_next()


func _tick_cpu(trial: Dictionary) -> void:
	var trucked: bool = _gained(&"trucks") > 0
	var over: bool = _pc.ball_dead or _gained(&"drags") > 0 or _gained(&"fumbles") > 0 or _gained(&"broken_tackles") > 0
	if not trucked and not over:
		return
	var strong: bool = trial["strength"] > 50
	_expect(_gained(&"secures_power") == (1 if strong else 0), "set out to run him over %d times" % _gained(&"secures_power"))
	_expect(_gained(&"secures_cover") == (0 if strong else 1), "set out to cover the ball %d times" % _gained(&"secures_cover"))
	_count(trial["label"], trucked)
	_next()


## The person's carrier and A, which is both `secure_ball` and `jump_alt`:
## pressed and held past the end of the burst, then pressed again before the
## cooldown is over, and once more after it.
func _tick_button() -> void:
	var burst: int = ceili(_tuning.secure_time * 60.0)
	var cooldown: int = ceili(_tuning.secure_cooldown * 60.0)
	if _ticks == 1:
		_expect(not _man.is_securing(), "securing before the button is down")
		_press_a(true)
	elif _ticks == 5:
		_expect(_man.is_securing(), "A pressed and he is not securing the ball")
		_expect(_man.state != Player.State.JUMPING, "A still jumps a ball carrier")
	elif _ticks == burst + 6:
		_expect(not _man.is_securing(), "A still held and he secures the ball past the end of the burst")
		_press_a(false)
	elif _ticks == burst + 8:
		_expect(not _man.is_securing(), "securing again when A is let go")
		_press_a(true)
	elif _ticks == burst + 12:
		_expect(not _man.is_securing(), "a second press before the cooldown is over secures the ball")
		_press_a(false)
	elif _ticks == cooldown + 6:
		_expect(_man.secure_cooldown <= 0.0, "the cooldown is not over %d ticks after the press" % (_ticks - 1))
		_press_a(true)
	elif _ticks == cooldown + 10:
		_expect(_man.is_securing(), "a press after the cooldown does not secure the ball")
		_press_a(false)
		_next()


func _press_a(down: bool) -> void:
	for action: StringName in [&"secure_ball", &"jump_alt"]:
		if down:
			Input.action_press(action)
		else:
			Input.action_release(action)


func _tick_passer() -> void:
	if _ticks == 1:
		Input.action_press(&"secure_ball")
		return
	if _ticks < 5:
		return
	var qb: Player = _pc.qb
	_expect(qb.has_ball and _pc.can_pass(), "the quarterback cannot throw: nothing checked")
	_expect(_game.human.controlled == qb, "the person is not the quarterback")
	_expect(not qb.is_securing() and qb.secure_cooldown <= 0.0, "a quarterback who can throw secures the ball")
	Input.action_release(&"secure_ball")
	_next()


func _count(label: String, hit: bool) -> void:
	var count: Vector2i = _tally.get(label, Vector2i.ZERO)
	_tally[label] = count + Vector2i(1 if hit else 0, 1)


func _gained(stat: StringName) -> int:
	return _game.get_stat(stat) - _before.get(stat, 0)


func _next() -> void:
	_trial += 1
	if _trial >= _trials.size():
		_report()
		_finish()
		return
	var trial: Dictionary = _trials[_trial]
	var kind: Kind = trial["kind"]
	var by_hand: bool = kind == Kind.BUTTON or kind == Kind.PASSER
	var offense: Team = _person if by_hand else _cpu
	_dir = float(offense.attack_dir)
	var middle: float = _tuning.field_length * 0.5

	var secure: bool = trial.get("secure", true)
	_tuning.ai_secure_chance = 1.0 if secure else 0.0
	_tuning.ai_edge_secure_chance = _tuning.ai_secure_chance
	_tuning.fumble_chance_low = FUMBLE_CHANCE if kind == Kind.FUMBLE else _fumble_low
	_tuning.secure_shake_off_bonus = trial.get("bonus", _shake_bonus)

	_game.human.team = _person
	_game.start_drive(offense, _tuning.yard_to_x(offense.attack_dir, 30.0))
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.is_run == (kind != Kind.PASSER) and not candidate.play_action:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_ticks = 0
	for stat: StringName in [&"trucks", &"fumbles", &"broken_tackles", &"drags", &"shake_offs", &"secured_tackles", &"secured_drags", &"secures_power", &"secures_cover"]:
		_before[stat] = _game.get_stat(stat)

	# Everybody else well behind the play, standing still.
	for player: Player in _pc.players:
		player.heal()
		if kind == Kind.PASSER and player == _pc.qb:
			continue
		player.position = Vector3(middle - _dir * 30.0, 0.0, float(player.index) * 2.0 - 30.0)
		player.velocity = Vector3.ZERO
		player.frozen = true
	if kind == Kind.PASSER:
		return

	_man = _pc.runner
	_man.ratings = _man.ratings.duplicate() as PlayerRatings
	_man.position = Vector3(middle, 0.0, 0.0)
	_man.facing = Vector3(_dir, 0.0, 0.0)
	_pc.handoff_done = true
	_pc.phase = PlayController.Phase.RUN
	_pc.ball.give_to(_man)
	_tackler = offense.opponent.players[0]
	_tackler.ratings = _tackler.ratings.duplicate() as PlayerRatings
	_tackler.ratings.strength = 50
	_tackler.ratings.tackling = 100
	_tackler.position = _man.position + Vector3(_dir * 5.0, 0.0, 0.0)
	_tackler.facing = Vector3(-_dir, 0.0, 0.0)

	if by_hand:
		_man.frozen = false
		_game.human.set_controlled(_man)
		return
	# Nobody at the controls: every player thinks for himself.
	_game.human.set_controlled(null)
	_game.human.team = null
	match kind:
		Kind.TRUCK:
			# Rolled by hand, with nobody moving.
			_man.ratings.strength = 50 + int(trial["gap"])
			_tackler.ratings.strength = 50
			if _man.ratings.strength > 100:
				_man.ratings.strength = 100
				_tackler.ratings.strength = 100 - int(trial["gap"])
			_tackler.position = _man.position + Vector3(_dir * 12.0, 0.0, 0.0)
		Kind.FUMBLE:
			# Too weak to drag anyone, and no safe pair of hands.
			_man.ratings.strength = 0
			_man.ratings.security = 0
			_start_run()
		Kind.DRAG:
			# As strong as each other: no running him over, and a long drag. The
			# tackler has to be free to be dragged along.
			_man.ratings.strength = 100
			_man.ratings.security = 100
			_tackler.ratings.strength = 100
			_tackler.frozen = false
			_start_run()
		Kind.CPU:
			_man.ratings.strength = trial["strength"]
			_man.ratings.juke = 50
			_tackler.ratings.strength = 40
			_start_run()


func _start_run() -> void:
	_man.frozen = false
	_man.velocity = Vector3(_dir * 7.0, 0.0, 0.0)


func _share(label: String) -> float:
	var count: Vector2i = _tally.get(label, Vector2i.ZERO)
	return float(count.x) / maxf(float(count.y), 1.0)


func _trials_of(label: String) -> int:
	return _tally.get(label, Vector2i.ZERO).y


func _report() -> void:
	for label: String in _tally:
		var count: Vector2i = _tally[label]
		print("%-20s %3d of %3d: %.0f%%" % [label, count.x, count.y, _share(label) * 100.0])
	print("trials thrown out (the tackle was not what the trial is about): %d" % _discarded)
	# Fewer trials: more room for luck.
	var slack: float = 1.7 if OS.get_cmdline_user_args().has("quick") else 1.0

	var plain: float = _share("fumble plain")
	var secured: float = _share("fumble secured")
	if _trials_of("fumble plain") < 20 or _trials_of("fumble secured") < 20:
		_failures.append("too few tackles to measure fumbles")
	else:
		var ratio: float = secured / maxf(plain, 0.01)
		print("fumbles with the ball secured: x%.2f of plain (should be x%.2f)" % [ratio, _tuning.secure_fumble_scale])
		if absf(plain - FUMBLE_CHANCE) > 0.12 * slack:
			_failures.append("plain fumble rate %.0f%%, should be near %.0f%%" % [plain * 100.0, FUMBLE_CHANCE * 100.0])
		if absf(ratio - _tuning.secure_fumble_scale) > 0.22 * slack:
			_failures.append("securing gives x%.2f the fumbles, should be near x%.2f" % [ratio, _tuning.secure_fumble_scale])

	var base: float = PlayerRatings.blend(100, _tuning.shake_off_chance_low, _tuning.shake_off_chance_high)
	var loose: float = _share("shake-off plain")
	var held: float = _share("shake-off secured")
	if _trials_of("shake-off plain") < 15 or _trials_of("shake-off secured") < 15:
		_failures.append("too few drags to measure shake-offs")
	else:
		if absf(loose - base) > 0.16 * slack:
			_failures.append("shake-offs without the bonus %.0f%%, should be near %.0f%%" % [loose * 100.0, base * 100.0])
		if absf(held - (base + SHAKE_BONUS)) > 0.16 * slack:
			_failures.append("shake-offs with the bonus %.0f%%, should be near %.0f%%" % [held * 100.0, (base + SHAKE_BONUS) * 100.0])
		if held <= loose:
			_failures.append("the bonus for securing the ball shakes off no more tacklers")

	var want: float = clampf(50.0 * _tuning.secure_truck_chance_per_point, 0.0, _tuning.secure_truck_chance_max)
	if absf(_share("CPU strong") - want) > 0.22 * slack:
		_failures.append("the strong CPU carrier ran over %.0f%%, should be near %.0f%%" % [_share("CPU strong") * 100.0, want * 100.0])
	if _tally.get("CPU weak", Vector2i.ZERO).x > 0:
		_failures.append("the weak CPU carrier ran a stronger tackler over")
	if _discarded > _trials.size() / 10:
		_failures.append("%d trials thrown out: the setup is off" % _discarded)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	_failures.append("%s (trial %d): %s" % [_trials[_trial]["label"], _trial, what])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("SECURE CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("SECURE CHECK FAILED: %s" % failure)
		quit(1)
