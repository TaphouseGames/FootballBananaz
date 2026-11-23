extends SceneTree
## Headless check of the CPU changing its play at the line:
##   rules     an offense only leaves a play for a defense that stops it best,
##             and for a play of the coach's that does better against it; a
##             defense only for one that fits the formation better
##   offense   a CPU offense with a run called against a zone audibles to a
##             pass, its quarterback signals, and it snaps only once set
##   hot       against a blitz one deep receiver is given a quick route
##   defense   a CPU defense in the wrong play for the person's formation
##             changes it, and the person's hot route is still on afterwards
##   never     with the chances at 0 nothing is changed
##   person    the person's own audible has the quarterback signal too
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/cpu_audible_check.gd

## Ticks a case is given to play out.
const LOOK: int = 150
const SNAP: int = 480

var _game: Game
var _pc: PlayController
var _team: Team
var _state: Node
var _failures: PackedStringArray = PackedStringArray()
var _started: bool = false
## Each step is a wait in ticks and then a call.
var _steps: Array[Array] = []
var _wait: int = 0
var _due: Callable = Callable()
var _kept: Dictionary[String, Variant] = {}
## The most the quarterback's signal timer was seen at since the last line-up.
var _signalled: float = 0.0
## The tick of the line-up, and the tick the ball was snapped on since (-1: not).
var _tick_count: int = 0
var _lined_up_at: int = 0
var _snapped_at: int = -1
var _walking_at_snap: bool = false


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready() or _game.play_controller == null or _game.offense == null:
		return
	if not _started:
		_started = true
		_pc = _game.play_controller
		_team = _game.human.team
		_state = _pc.state_machine.get_node(^"PreSnap")
		if _team == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_game.tuning.audio_enabled = false
		_game.tuning.play_clock = 0.0
		_game.tuning.ai_motion_chance = 0.0
		_check_rules()
		_plan()
		return
	_tick_count += 1
	if _pc.qb != null and _pc.qb.animator != null:
		_signalled = maxf(_signalled, float(_pc.qb.animator.get(&"_call_timer")))
	if _snapped_at < 0 and _pc.state_machine.current_name() == &"Live":
		_snapped_at = _tick_count
	if _wait > 0:
		_wait -= 1
		return
	if _due.is_valid():
		var due: Callable = _due
		_due = Callable()
		due.call()
		return
	if _steps.is_empty():
		_finish()
		return
	var step: Array = _steps.pop_front()
	_wait = int(step[0])
	_due = step[1]


# --- The rules, without the field ----------------------------------------------

func _check_rules() -> void:
	var caller: PlayCaller = _game.play_caller
	var offenses: Array[OffensePlay] = _game.offense_playbook.plays
	var defenses: Array[DefensePlay] = _game.defense_playbook.plays
	var margin: float = _game.tuning.ai_audible_margin
	_put(false, 40.0)
	var changes: int = 0
	for look: DefensePlay in defenses:
		var fit: PackedFloat32Array = PlayCaller.look_fit(defenses, look.group)
		var best: float = maxf(fit[0], maxf(fit[1], fit[2]))
		for called: OffensePlay in offenses:
			var pick: OffensePlay = caller.cpu_audible_offense(offenses, defenses, _game, called, look)
			if pick == null:
				continue
			changes += 1
			_expect(fit[called.category] >= best - 0.002, "rules: %s left against %s, which is not what that stops best" % [called.play_name, look.play_name])
			_expect(pick != called and fit[pick.category] <= fit[called.category] - margin + 0.002, "rules: %s to %s against %s is no better" % [called.play_name, pick.play_name, look.play_name])
			_expect(not pick.goal_line and not pick.heave_only, "rules: an audible to %s at the 40" % pick.play_name)
	_expect(changes > 0, "rules: no offense in the book ever has a reason to audible")
	print("rules: an offense has a reason to change in %d of %d line-ups" % [changes, offenses.size() * defenses.size()])

	changes = 0
	for group: int in OffensePlay.GROUP_NAMES.size():
		var mix: PackedFloat32Array = PlayCaller.formation_mix(offenses, group as OffensePlay.Group)
		_expect(absf(mix[0] + mix[1] + mix[2] - 1.0) < 0.001, "rules: the shares of %s do not add up" % OffensePlay.GROUP_NAMES[group])
		for called: DefensePlay in defenses:
			var pick: DefensePlay = caller.cpu_audible_defense(defenses, offenses, _game, called, group as OffensePlay.Group)
			if pick == null:
				continue
			changes += 1
			_expect(_mix_fit(pick, mix) >= _mix_fit(called, mix) + _game.tuning.ai_audible_defense_margin - 0.002, "rules: %s to %s against %s is no better" % [called.play_name, pick.play_name, OffensePlay.GROUP_NAMES[group]])
			_expect(not pick.goal_line, "rules: the defense goes to %s at the 40" % pick.play_name)
	_expect(changes > 0, "rules: no defense in the book ever has a reason to audible")
	print("rules: a defense has a reason to change in %d of %d line-ups" % [changes, OffensePlay.GROUP_NAMES.size() * defenses.size()])


func _mix_fit(play: DefensePlay, mix: PackedFloat32Array) -> float:
	return mix[0] * play.run_fit + mix[1] * play.short_fit + mix[2] * play.deep_fit


# --- At the line ---------------------------------------------------------------

func _plan() -> void:
	var tuning: Tuning = _game.tuning

	# A deep pass against a blitz: a hot route, and no audible on top of it.
	_steps.append([0, func() -> void:
		tuning.ai_audible_chance = 0.0
		tuning.ai_hot_route_chance = 1.0
		tuning.cpu_snap_delay_min = 600.0
		tuning.cpu_snap_delay_max = 600.0
		_line_up(false, _offense_of(OffensePlay.Category.DEEP, true), _defense_of(DefensePlay.Group.BLITZ))
		_kept["play"] = _pc.off_play
		_kept["hot"] = _game.stats.get(&"cpu_hot_routes", 0)])
	_steps.append([LOOK, func() -> void:
		_expect(_pc.off_play == _kept["play"], "hot: the play was changed as well")
		_expect(_pc.hot_routes.size() == 1, "hot: %d receivers were given a hot route" % _pc.hot_routes.size())
		_expect(_game.stats.get(&"cpu_hot_routes", 0) == int(_kept["hot"]) + 1, "hot: the hot route was not counted once")
		_expect(_signalled > 0.0, "hot: the quarterback made no signals")
		for man: Player in _pc.hot_routes:
			var hot: OffenseAssignment = _pc.hot_routes[man]
			var depth: float = 0.0
			for waypoint: Vector2 in hot.route:
				depth = maxf(depth, waypoint.x)
			_expect(man.brain.off_assign == hot, "hot: the receiver does not run it")
			_expect(depth < tuning.ai_hot_route_depth, "hot: the route he was given is %.0f yd deep" % depth)
			_expect(_pc.eligible.has(man), "hot: he cannot be thrown to")
			print("hot: %s against %s, %s runs a %.0f yd route instead" % [_pc.off_play.play_name, _pc.def_play.play_name, hot.label, depth])])

	# The person's formation, and a CPU defense that is in the wrong play for it.
	_steps.append([0, func() -> void:
		tuning.ai_audible_chance = 1.0
		tuning.ai_hot_route_chance = 0.0
		var offense: OffensePlay = _offense_of(OffensePlay.Category.SHORT, true)
		var worst: DefensePlay = _worst_against(offense.group)
		_line_up(true, offense, worst)
		_kept["defense"] = worst
		_kept["audibles"] = _game.stats.get(&"cpu_audibles", 0)
		# A hot route of the person's own, before the defense has looked.
		var man: Player = null
		for player: Player in _pc.eligible:
			if player.brain.off_assign.job == OffenseAssignment.Job.ROUTE:
				man = player
		_expect(man != null and _pc.hot_route(man, OffenseAssignment.Hot.STREAK, 1.0), "defense: the person's hot route was refused")
		_kept["man"] = man
		_kept["route"] = man.brain.off_assign if man != null else null])
	_steps.append([LOOK, func() -> void:
		var was: DefensePlay = _kept["defense"]
		var mix: PackedFloat32Array = PlayCaller.formation_mix(_game.offense_playbook.plays, _pc.off_play.group)
		var man: Player = _kept["man"]
		_expect(_pc.def_play != was, "defense: it stayed in %s" % was.play_name)
		_expect(_mix_fit(_pc.def_play, mix) > _mix_fit(was, mix), "defense: %s is no better against the formation than %s" % [_pc.def_play.play_name, was.play_name])
		_expect(_game.stats.get(&"cpu_audibles", 0) == int(_kept["audibles"]) + 1, "defense: the CPU audible was not counted once")
		_expect(_pc.state_machine.current_name() == &"PreSnap", "defense: the ball was snapped")
		_expect(man != null and _pc.hot_routes.has(man) and man.brain.off_assign == _kept["route"], "defense: its audible took the person's hot route away")
		print("defense: %s to %s against %s" % [was.play_name, _pc.def_play.play_name, OffensePlay.GROUP_NAMES[_pc.off_play.group]])])

	# With the chances at 0 nobody changes anything.
	for on_offense: bool in [true, false]:
		_steps.append([0, func() -> void:
			tuning.ai_audible_chance = 0.0
			tuning.ai_hot_route_chance = 0.0
			var offense: OffensePlay = _offense_of(OffensePlay.Category.DEEP, true)
			_line_up(on_offense, offense, _defense_of(DefensePlay.Group.BLITZ) if not on_offense else _worst_against(offense.group))
			_kept["play"] = _pc.off_play
			_kept["defense"] = _pc.def_play
			_kept["audibles"] = _game.stats.get(&"audibles", 0)])
		_steps.append([LOOK, func() -> void:
			_expect(_pc.off_play == _kept["play"] and _pc.def_play == _kept["defense"], "never: a play was changed with the chances at 0")
			_expect(_pc.hot_routes.is_empty(), "never: a hot route was given with the chances at 0")
			_expect(_game.stats.get(&"audibles", 0) == _kept["audibles"], "never: an audible was counted with the chances at 0")])

	# The person's own audible and hot route: the quarterback signals those too.
	_steps.append([0, func() -> void:
		_expect(_signalled == 0.0, "person: the quarterback signals with nothing called")
		var other: OffensePlay = _offense_of(OffensePlay.Category.RUN, false)
		_expect(_pc.audible(other, _pc.def_play, _pc.off_flipped, _pc.def_flipped, _game.offense), "person: the audible was refused")])
	_steps.append([20, func() -> void:
		_expect(_signalled > 0.0, "person: the quarterback made no signals for an audible")
		_signalled = 0.0])
	_steps.append([90, func() -> void:
		_expect(float(_pc.qb.animator.get(&"_call_timer")) == 0.0, "person: the quarterback is still signalling 110 ticks on")
		_signalled = 0.0
		_expect(_pc.audible(_pc.off_play, _defense_of(DefensePlay.Group.MAN), _pc.off_flipped, _pc.def_flipped, _game.defense), "person: the defense's audible was refused")])
	_steps.append([20, func() -> void:
		_expect(_signalled == 0.0, "person: the quarterback signals for the defense's audible")])


	# A CPU offense with a run called against a zone. Last: the ball is snapped.
	_steps.append([0, func() -> void:
		tuning.ai_audible_chance = 1.0
		tuning.ai_hot_route_chance = 0.0
		tuning.cpu_snap_delay_min = 0.8
		tuning.cpu_snap_delay_max = 0.8
		_line_up(false, _offense_of(OffensePlay.Category.RUN, false), _defense_of(DefensePlay.Group.ZONE))
		_kept["play"] = _pc.off_play
		_kept["audibles"] = _game.stats.get(&"cpu_audibles", 0)])
	_steps.append([LOOK, func() -> void:
		_expect(_pc.off_play != _kept["play"], "offense: it stayed with a run against a zone")
		_expect(_pc.off_play.category != OffensePlay.Category.RUN, "offense: it went from a run to the run %s" % _pc.off_play.play_name)
		_expect(_game.stats.get(&"cpu_audibles", 0) == int(_kept["audibles"]) + 1, "offense: the CPU audible was not counted once")
		_expect(_signalled > 0.0, "offense: the quarterback made no signals")
		_kept["to"] = _pc.off_play.play_name])
	_steps.append([SNAP, func() -> void:
		var set_ticks: float = (tuning.pre_snap_delay + tuning.ai_audible_time + tuning.ai_audible_set_time) * 60.0
		_expect(_snapped_at >= 0, "offense: the ball was not snapped in %d ticks" % (LOOK + SNAP))
		_expect(_snapped_at - _lined_up_at >= set_ticks - 2.0, "offense: snapped %d ticks after the line-up, before its signals were done" % (_snapped_at - _lined_up_at))
		print("offense: %s to %s, snapped after %d ticks" % [(_kept["play"] as OffensePlay).play_name, _kept["to"], _snapped_at - _lined_up_at])])


## Home has the ball (`on_offense`: the person's team) at its own `yard` line,
## early in a level game: nothing but the look across the ball asks for a play.
func _put(on_offense: bool, yard: float) -> void:
	var with_ball: Team = _team if on_offense else _team.opponent
	_game.conversion = false
	_game.half = 1
	_game.clock = _game.tuning.game_length * 0.4
	with_ball.score = 0
	with_ball.opponent.score = 0
	_game.start_drive(with_ball, _game.tuning.yard_to_x(with_ball.attack_dir, yard))


func _line_up(on_offense: bool, offense: OffensePlay, defense: DefensePlay) -> void:
	if not _pc.ball_dead:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
	_put(on_offense, 40.0)
	_game.coach_plays.clear()
	_pc.line_up(offense, defense)
	_pc.state_machine.transition(&"PreSnap")
	_signalled = 0.0
	_snapped_at = -1
	_lined_up_at = _tick_count


## A play of kind `category` that is no goal line play: with a route drawn deep
## enough for a hot route (`deep_route`), or the first there is.
func _offense_of(category: OffensePlay.Category, deep_route: bool) -> OffensePlay:
	for play: OffensePlay in _game.offense_playbook.plays:
		if play.category != category or play.goal_line or play.heave_only or play.flea_flicker:
			continue
		if not deep_route or play.deepest_route() >= _game.tuning.ai_hot_route_depth + 3.0:
			return play
	_failures.append("no play of kind %d to test with" % category)
	return _game.offense_playbook.plays[0]


func _defense_of(group: DefensePlay.Group) -> DefensePlay:
	for play: DefensePlay in _game.defense_playbook.plays:
		if play.group == group:
			return play
	_failures.append("no defense on tab %d to test with" % group)
	return _game.defense_playbook.plays[0]


## The defense that holds up worst against what comes out of formation `group`.
func _worst_against(group: OffensePlay.Group) -> DefensePlay:
	var mix: PackedFloat32Array = PlayCaller.formation_mix(_game.offense_playbook.plays, group)
	var worst: DefensePlay = null
	for play: DefensePlay in _game.defense_playbook.plays:
		if not play.goal_line and (worst == null or _mix_fit(play, mix) < _mix_fit(worst, mix)):
			worst = play
	return worst


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	for failure: String in _failures:
		print("FAIL: " + failure)
	print("cpu_audible_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
