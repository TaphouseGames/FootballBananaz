extends SceneTree
## Headless check of the hurdle (a carrier in the air goes over a diving
## tackler): how high he jumps goes by his juke rating, and whether he clears
## the dive goes by how high his feet are when it gets to him. For a carrier
## rated 0, 50 and 100: the top of his jump, a dive at every tick of the jump,
## and a CPU carrier, who only jumps at a dive his jump would get him over.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/hurdle_check.gd

enum Kind { PEAK, SWEEP, CPU }

const JUKES: Array[int] = [0, 50, 100]
## Yards between carrier and tackler in the sweep: inside the reach of a dive,
## outside that of a tackler on his feet.
const SWEEP_GAP: float = 1.3
## Yards ahead of the running CPU carrier that the tackler dives from.
const CPU_GAPS: Array[float] = [3.0, 3.5, 4.0, 4.5, 5.0, 5.5]
## A dive that meets him within this much of the clear height may go either way.
const EDGE: float = 0.04
const STUCK_TICKS: int = 120

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
var _top: float = 0.0
var _dived: bool = false
var _hurdles_before: int = 0
var _jumps_before: int = 0
## Per juke rating: dives cleared and dives made in the sweep, then the same
## and the jumps tried for the CPU carrier.
var _swept: Dictionary[int, Vector2i] = {}
var _cpu_runs: Dictionary[int, Vector3i] = {}
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
		_tuning = _game.tuning
		_person = _game.human.team
		if _person == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_cpu = _person.opponent
		# The CPU carrier always tries the hurdle and nothing else.
		_tuning.ai_edge_hurdle_chance = 1.0
		_tuning.ai_spin_chance = 0.0
		_tuning.ai_stiff_arm_chance = 0.0
		_tuning.ai_edge_move_chance = 0.0
		_tuning.ai_jump_dive_chance = 0.0
		_tuning.ai_edge_jump_dive_chance = 0.0
		var jump_ticks: int = roundi(_tuning.jump_time * 60.0)
		for juke: int in JUKES:
			_swept[juke] = Vector2i.ZERO
			_cpu_runs[juke] = Vector3i.ZERO
			_trials.append({"kind": Kind.PEAK, "juke": juke})
			for tick: int in range(1, jump_ticks):
				_trials.append({"kind": Kind.SWEEP, "juke": juke, "tick": tick})
			for gap: float in CPU_GAPS:
				_trials.append({"kind": Kind.CPU, "juke": juke, "gap": gap})
		_next()
		return
	_ticks += 1
	if _ticks > STUCK_TICKS:
		_fail("never finished")
		_next()
		return
	var trial: Dictionary = _trials[_trial]
	match trial["kind"]:
		Kind.PEAK:
			_tick_peak(trial["juke"])
		Kind.SWEEP:
			_tick_sweep(trial["juke"], trial["tick"])
		Kind.CPU:
			_tick_cpu(trial["juke"])


func _tick_peak(juke: int) -> void:
	if _man.state == Player.State.JUMPING:
		_top = maxf(_top, _man.air_height())
		return
	var want: float = _tuning.jump_height * PlayerRatings.blend(juke, _tuning.jump_height_scale_low, _tuning.jump_height_scale_high)
	print("juke %3d  top of the jump %.2f yd (should be %.2f)" % [juke, _top, want])
	_expect(absf(_man.jump_height() - want) < 0.001, "jump_height() is %.2f, should be %.2f" % [_man.jump_height(), want])
	_expect(_top > want * 0.98 and _top <= want + 0.001, "got %.2f up, should be %.2f" % [_top, want])
	_expect(want > _tuning.hurdle_clear_height, "the top of his jump is under the clear height")
	_next()


func _tick_sweep(juke: int, tick: int) -> void:
	if _ticks < tick:
		return
	if _ticks == tick:
		_dive()
		return
	# The dive meets him on the physics step after the one it was asked for in.
	var jump_ticks: float = _tuning.jump_time * 60.0
	var t: float = float(tick + 1) / jump_ticks
	var height: float = 4.0 * _man.jump_height() * t * (1.0 - t)
	var cleared: bool = _gained(&"hurdles", _hurdles_before) == 1
	var count: Vector2i = _swept[juke]
	_swept[juke] = count + Vector2i(1 if cleared else 0, 1)
	if absf(height - _tuning.hurdle_clear_height) > EDGE:
		var high: bool = height > _tuning.hurdle_clear_height
		_expect(cleared == high, "%.2f up when the dive got there, cleared: %s" % [height, cleared])
	_next()


func _tick_cpu(juke: int) -> void:
	if _ticks == 1:
		_dive()
		return
	if not _pc.ball_dead and _ticks < 45:
		return
	var jumped: int = mini(_gained(&"hurdle_jumps", _jumps_before), 1)
	var cleared: int = mini(_gained(&"hurdles", _hurdles_before), 1)
	_cpu_runs[juke] = _cpu_runs[juke] + Vector3i(cleared, jumped, 1)
	# He only goes up for a dive he can get over.
	_expect(cleared == jumped, "he jumped and did not clear the dive")
	_next()


func _dive() -> void:
	var to: Vector3 = _man.position - _tackler.position
	to.y = 0.0
	_tackler.frozen = false
	_pc.do_dive(_tackler, to.normalized())
	_dived = true
	_expect(_tackler.state == Player.State.DIVING, "the tackler's dive did not start")


func _gained(stat: StringName, before: int) -> int:
	return _game.get_stat(stat) - before


func _next() -> void:
	_trial += 1
	if _trial >= _trials.size():
		_report()
		_finish()
		return
	var trial: Dictionary = _trials[_trial]
	var kind: Kind = trial["kind"]
	var offense: Team = _cpu
	_dir = float(offense.attack_dir)
	var middle: float = _tuning.field_length * 0.5
	_game.human.team = _person
	_game.start_drive(offense, _tuning.yard_to_x(offense.attack_dir, 30.0))
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.is_run and not candidate.play_action:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	# Nobody at the controls: every player thinks for himself.
	_game.human.set_controlled(null)
	_game.human.team = null

	# Everybody else well behind the play, standing still.
	for player: Player in _pc.players:
		player.heal()
		player.position = Vector3(middle - _dir * 30.0, 0.0, float(player.index) * 2.0 - 30.0)
		player.velocity = Vector3.ZERO
		player.frozen = true

	_man = _pc.runner
	_man.ratings = _man.ratings.duplicate() as PlayerRatings
	_man.ratings.juke = trial["juke"]
	_man.position = Vector3(middle, 0.0, 0.0)
	_man.facing = Vector3(_dir, 0.0, 0.0)
	_man.frozen = false
	_pc.handoff_done = true
	_pc.phase = PlayController.Phase.RUN
	_pc.ball.give_to(_man)

	# The tackler stands in front of him, frozen until he dives.
	var gap: float = trial["gap"] if kind == Kind.CPU else SWEEP_GAP
	_tackler = offense.opponent.players[0]
	_tackler.position = _man.position + Vector3(_dir * gap, 0.0, 0.0)
	_tackler.facing = Vector3(-_dir, 0.0, 0.0)

	_ticks = 0
	_top = 0.0
	_dived = false
	_hurdles_before = _game.get_stat(&"hurdles")
	_jumps_before = _game.get_stat(&"hurdle_jumps")

	if kind == Kind.CPU:
		_man.velocity = Vector3(_dir * 7.0, 0.0, 0.0)
	else:
		_pc.do_jump(_man)
		_expect(_man.state == Player.State.JUMPING, "the jump did not start")


func _report() -> void:
	var last_share: float = -1.0
	for juke: int in JUKES:
		var count: Vector2i = _swept[juke]
		var share: float = float(count.x) / maxf(float(count.y), 1.0)
		var top: float = _tuning.jump_height * PlayerRatings.blend(juke, _tuning.jump_height_scale_low, _tuning.jump_height_scale_high)
		var want: float = sqrt(maxf(1.0 - _tuning.hurdle_clear_height / top, 0.0))
		print("juke %3d  cleared %d of %d dives through the jump: %.0f%% (the curve says %.0f%%)" % [juke, count.x, count.y, share * 100.0, want * 100.0])
		if absf(share - want) > 0.1:
			_failures.append("juke %d: cleared %.0f%% of the jump, should be near %.0f%%" % [juke, share * 100.0, want * 100.0])
		if share <= last_share:
			_failures.append("juke %d clears no more of the jump than the rating below it" % juke)
		last_share = share
	var last_cleared: int = -1
	for juke: int in JUKES:
		var runs: Vector3i = _cpu_runs[juke]
		print("juke %3d  CPU carrier: jumped at %d of %d dives, cleared %d" % [juke, runs.y, runs.z, runs.x])
		if runs.x < last_cleared:
			_failures.append("juke %d: the CPU carrier cleared fewer dives than the rating below it" % juke)
		last_cleared = runs.x
	if _cpu_runs[JUKES[-1]].x == 0:
		_failures.append("the CPU carrier with the best juke rating never cleared a dive")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	var trial: Dictionary = _trials[_trial]
	_failures.append("%s, juke %d, %s: %s" % [Kind.keys()[trial["kind"]], trial["juke"], trial.get("tick", trial.get("gap", "")), what])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("HURDLE CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("HURDLE CHECK FAILED: %s" % failure)
		quit(1)
