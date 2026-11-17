extends SceneTree
## Headless check of motion before the snap (Y):
##   pick      who may move: only a receiver off the line, the one nearest the
##             ball, nobody in a formation that has none
##   rules     every play's motion keeps to MotionRules, as drawn and flipped
##   move      the motion man ends where the play sends him, nobody else on the
##             offense moves, as many are on the line as before
##   man       a man defender who has him goes with him and ends across from
##             him; no two defenders run through each other
##   zone      nobody else goes with him; a zone defender moves a few yards at most
##   snap      his job after the motion starts where he stands, also when the
##             ball is snapped while he is on his way
##   jet       Gun Dive snapped while the jet man runs goes to him; snapped
##             after he has set it goes to the back
##   button    (Y) sends him once, does nothing on a play without a motion,
##             and the play clock snaps the ball with him on his way
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/presnap_motion_check.gd
## Optional user args after "--":
##   detail    one line per play

const Probe: GDScript = preload("res://tests/playbook_probe.gd")
const DT: float = 1.0 / 60.0
const MAX_TICKS: int = 720
## A follower ends within this many yards across of his man.
const ACROSS: float = 1.5
## Defenders closer than this have run through each other.
const CROWDED: float = 0.8
## The motion man of each test formation of the probe: its place among the four
## skill players, or -1.
const PROBE_PICKS: Dictionary[String, int] = {
	"2-wide": -1, "trips": 3, "4-wide": 3, "empty 3x1": 3, "bunch": 3, "heavy": -1,
}
## And of the playbook's own, by tab.
const BOOK_PICKS: Array[int] = [-1, 1, 1, 3, 3, -1]

var _game: Game
var _pc: PlayController
var _team: Team
var _detail: bool = false
var _failures: PackedStringArray = PackedStringArray()
var _sync_done: bool = false
## The (Y) part runs over real ticks: its steps, each a wait in ticks and then a call.
var _steps: Array[Array] = []
var _wait: int = 0
var _counts: Dictionary[String, int] = {}
## Who the two defenders were that came closest in the last motion run.
var _closest_note: String = ""


func _initialize() -> void:
	_detail = OS.get_cmdline_user_args().has("detail")
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready() or _game.play_controller == null or _game.offense == null:
		return
	if not _sync_done:
		_sync_done = true
		_pc = _game.play_controller
		_team = _game.human.team
		if _team == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_game.tuning.audio_enabled = false
		_check_pick()
		_check_rules()
		_check_reactions()
		_check_snaps()
		_check_jet()
		_plan_button()
		return
	if _wait > 0:
		_wait -= 1
		return
	if _steps.is_empty():
		_finish()
		return
	var step: Array = _steps.pop_front()
	_wait = int(step[0])
	(step[1] as Callable).call()


# --- pick, rules ---------------------------------------------------------------

func _check_pick() -> void:
	var formations: Dictionary[String, OffensePlay] = Probe.formations()
	for formation: String in formations:
		var pick: int = MotionRules.pick(formations[formation])
		var want: int = PROBE_PICKS[formation]
		_expect(pick == (want + 4 if want >= 0 else -1), "pick: %s gives player %d, wanted %d" % [formation, pick - 4, want])
	for play: OffensePlay in _game.offense_playbook.plays:
		var pick: int = MotionRules.pick(play)
		var want: int = BOOK_PICKS[play.group]
		_expect(pick == (want + 4 if want >= 0 else -1), "pick: %s gives player %d, wanted %d" % [play.play_name, pick - 4, want])
		if pick >= 0:
			var man: OffenseAssignment = play.assignments[pick]
			_expect(not MotionRules.on_line(man), "pick: %s moves a man on the line" % play.play_name)
			_expect(man.start.x >= DefenseAligner.BACKFIELD, "pick: %s moves a back" % play.play_name)
		else:
			_expect(play.motion == OffensePlay.Motion.NONE, "pick: %s has a motion and nobody to run it" % play.play_name)
	# Two slots as near the ball as each other: the one on the right.
	var even: OffensePlay = formations["4-wide"]
	_expect(even.assignments[MotionRules.pick(even)].start.y > 0.0, "pick: of two equal slots the left one moves")
	print("pick: %d formations and %d plays" % [formations.size(), _game.offense_playbook.plays.size()])


func _check_rules() -> void:
	var half: float = _game.tuning.half_width()
	var with_motion: int = 0
	for play: OffensePlay in _game.offense_playbook.plays:
		for problem: String in MotionRules.problems(play, half):
			_expect(false, "rules: %s: %s" % [play.play_name, problem])
		if not MotionRules.has_motion(play):
			continue
		with_motion += 1
		_expect(MotionRules.line_count(play, true) == MotionRules.line_count(play, false), "rules: %s changes the line" % play.play_name)
	# A broken play is found out.
	var bad: OffensePlay = _game.offense_playbook.plays[0].duplicate() as OffensePlay
	bad.motion = OffensePlay.Motion.ZIP
	_expect(not MotionRules.problems(bad, half).is_empty(), "rules: a motion in a formation with nobody to move passes")
	for play: OffensePlay in _game.offense_playbook.plays:
		if play.motion == OffensePlay.Motion.ZIP:
			bad = play.duplicate() as OffensePlay
			bad.motion_to = Vector2(-0.6, play.motion_to.y)
			_expect(not MotionRules.problems(bad, half).is_empty(), "rules: a motion that ends on the line passes")
			break
	print("rules: %d plays with a motion, %d without" % [with_motion, _game.offense_playbook.plays.size() - with_motion])


# --- move, man, zone -----------------------------------------------------------

func _check_reactions() -> void:
	var defenses: Array[DefensePlay] = _game.defense_playbook.plays
	var runs: int = 0
	var followed: int = 0
	var shifted: int = 0
	var closest: float = INF
	for play: OffensePlay in _game.offense_playbook.plays:
		if not MotionRules.has_motion(play):
			continue
		var play_followed: int = 0
		var play_shift: float = 0.0
		for defense: DefensePlay in defenses:
			for flipped: bool in [false, true]:
				var where: String = "%s%s against %s" % [play.play_name, " (flipped)" if flipped else "", defense.play_name]
				_line_up(play, defense, flipped)
				runs += 1
				var motion: PreSnapMotion = _pc.motion
				var man: Player = motion.man
				var before: Dictionary[Player, Vector3] = _positions()
				var on_line: int = _on_line()
				var order: Array[Player] = _pc.eligible.duplicate()
				_expect(motion.available(), "move: %s: no motion to call" % where)
				_expect(motion.call_motion(), "move: %s: the call was refused" % where)
				_expect(not motion.call_motion(), "move: %s: called twice" % where)
				var gap: float = _run_motion(where)
				closest = minf(closest, gap)
				_expect(gap >= CROWDED, "man: %s: two defenders %.2f yd apart on the way: %s" % [where, gap, _closest_note])
				_expect(motion.state == PreSnapMotion.State.SET, "move: %s: he never set" % where)
				var end: Vector3 = _pc.to_world(MotionRules.end_spot(play), -1.0 if flipped else 1.0)
				_expect(_flat(man.position, end) < 0.25, "move: %s: he ends %.1f yd from his spot" % [where, _flat(man.position, end)])
				_expect(_on_line() == on_line, "move: %s: %d on the line, %d before" % [where, _on_line(), on_line])
				for player: Player in _pc.offense.players:
					if player != man:
						_expect(_flat(player.position, before[player]) < 0.01, "move: %s: a second man moved" % where)
				var has_man: bool = false
				for defender: Player in _pc.defense.players:
					var assignment: DefenseAssignment = defender.brain.def_assign
					var moved: float = _flat(defender.position, before[defender])
					if assignment.job == DefenseAssignment.Job.MAN and defender.brain.man_target == man:
						has_man = true
						_expect(absf(defender.position.z - man.position.z) <= ACROSS, "man: %s: his man ends %.1f yd across from him" % [where, absf(defender.position.z - man.position.z)])
					elif assignment.job == DefenseAssignment.Job.ZONE:
						play_shift = maxf(play_shift, moved)
						_expect(moved <= _game.tuning.motion_zone_shift_max + 0.2, "zone: %s: a zone defender moved %.1f yd" % [where, moved])
						if play.motion == OffensePlay.Motion.RETURN:
							_expect(moved < 0.05, "zone: %s: a zone defender moved on a return motion" % where)
						if moved > 0.3:
							shifted += 1
					else:
						_expect(moved < 0.05, "zone: %s: a %s moved %.1f yd" % [where, ["rusher", "man defender", "", "spy"][assignment.job], moved])
				for i: int in _pc.defense.players.size():
					for j: int in i:
						var apart: float = _flat(_pc.defense.players[i].position, _pc.defense.players[j].position)
						_expect(apart >= CROWDED, "man: %s: two defenders end %.2f yd apart" % [where, apart])
				if has_man:
					followed += 1
					play_followed += 1
				# The snap: his job starts from where he stands now.
				_pc.snap()
				var after: OffenseAssignment = play.motion_assignment if play.motion != OffensePlay.Motion.RETURN else play.assignments[MotionRules.pick(play)]
				if play.motion == OffensePlay.Motion.JET:
					_expect(man.brain.off_assign.job == OffenseAssignment.Job.BLOCK, "snap: %s: a jet man who has set is not a blocker" % where)
					_expect(_pc.runner != man, "snap: %s: the ball goes to a jet man who has set" % where)
				else:
					_expect(man.brain.off_assign == after, "snap: %s: he has the wrong job" % where)
					if not after.route.is_empty():
						var first: Vector3 = _pc.to_world(MotionRules.end_spot(play) + after.route[0], -1.0 if flipped else 1.0)
						var off: float = _flat(man.brain.route[0], first)
						if after.job == OffenseAssignment.Job.BLOCK and _pc.has_run_hole:
							# A lead blocker's path moves across with the hole
							# (PlayController._assign_run_blocks).
							off = absf(man.brain.route[0].x - first.x)
						_expect(off < 0.3, "snap: %s: his route starts %.1f yd from where he stands" % [where, off])
				if not play.is_run:
					_expect(_pc.eligible == order, "snap: %s: the pass buttons changed" % where)
				for player: Player in _pc.players:
					if not player.bystander:
						_expect(not player.frozen, "snap: %s: somebody is still frozen" % where)
		if _detail:
			print("  %-20s %-7s followed in %2d of %d line-ups, biggest zone shift %.1f yd" % [play.play_name, OffensePlay.Motion.keys()[play.motion], play_followed, defenses.size() * 2, play_shift])
	_counts["followed"] = followed
	_expect(followed > 0, "man: nobody ever followed the motion man")
	_expect(shifted > 0, "zone: no zone defender ever shifted")
	print("move: %d line-ups, a man went with him in %d, %d zone shifts, closest two defenders came %.2f yd" % [runs, followed, shifted, closest])


# --- snap while he is on his way -------------------------------------------------

func _check_snaps() -> void:
	var defense: DefensePlay = _defense("man cover 1")
	var runs: int = 0
	for play: OffensePlay in _game.offense_playbook.plays:
		if not MotionRules.has_motion(play) or play.motion == OffensePlay.Motion.JET:
			continue
		for share: float in [0.25, 0.75]:
			var where: String = "%s snapped %d%% of the way" % [play.play_name, roundi(share * 100.0)]
			_line_up(play, defense, false)
			var motion: PreSnapMotion = _pc.motion
			var man: Player = motion.man
			motion.call_motion()
			for _i: int in MAX_TICKS:
				if motion.progress() >= share or motion.state != PreSnapMotion.State.MOVING:
					break
				motion.tick(DT)
			_expect(motion.state == PreSnapMotion.State.MOVING, "snap: %s: he had set already" % where)
			var moving: int = 0
			for player: Player in _pc.offense.players:
				if player.velocity.length() > 0.5:
					moving += 1
			_expect(moving == 1, "snap: %s: %d of the offense moving" % [where, moving])
			# Not toward the line.
			_expect(man.velocity.x * _pc.off_dir < 0.5, "snap: %s: he is moving toward the line" % where)
			var here: Vector3 = man.position
			_pc.snap()
			runs += 1
			var drawn: OffenseAssignment = play.assignments[MotionRules.pick(play)]
			var want: OffenseAssignment = drawn
			if play.motion != OffensePlay.Motion.RETURN and share >= 0.5:
				want = play.motion_assignment
			_expect(man.brain.off_assign == want, "snap: %s: he has the %s job" % [where, "drawn" if man.brain.off_assign == drawn else "new"])
			if not want.route.is_empty():
				var first: Vector3 = here + Vector3(want.route[0].x * _pc.off_dir, 0.0, want.route[0].y * _pc.off_dir)
				first.z = clampf(first.z, -_game.tuning.half_width() + 1.0, _game.tuning.half_width() - 1.0)
				var off: float = _flat(man.brain.route[0], first)
				if want.job == OffenseAssignment.Job.BLOCK and _pc.has_run_hole:
					# A lead blocker's path moves across with the hole.
					off = absf(man.brain.route[0].x - first.x)
				_expect(off < 0.05, "snap: %s: his route does not start where he stands" % where)
	print("snap: %d snaps with him on his way" % runs)


# --- jet -----------------------------------------------------------------------

func _check_jet() -> void:
	var defense: DefensePlay = _defense("zone cover 2")
	for play: OffensePlay in _game.offense_playbook.plays:
		if play.motion != OffensePlay.Motion.JET:
			continue
		for flipped: bool in [false, true]:
			var where: String = "%s%s" % [play.play_name, " (flipped)" if flipped else ""]
			# In the window.
			_line_up(play, defense, flipped)
			var motion: PreSnapMotion = _pc.motion
			var man: Player = motion.man
			var back: Player = _pc.runner
			motion.call_motion()
			_expect(not motion.jet_in_window(), "jet: %s: in the window before he has moved" % where)
			var opened: bool = false
			for _i: int in MAX_TICKS:
				motion.tick(DT)
				if motion.jet_in_window():
					opened = true
					break
			_expect(opened, "jet: %s: the window never opened" % where)
			_expect(man.velocity.length() > _game.tuning.run_speed * 0.9, "jet: %s: he is doing %.1f yd/s in the window" % [where, man.velocity.length()])
			_pc.snap()
			_expect(man.brain.off_assign == play.motion_assignment, "jet: %s: snapped on the run he has the wrong job" % where)
			if play.motion_handoff:
				_expect(_pc.runner == man and motion.jet_sweep, "jet: %s: the ball does not go to the jet man" % where)
				_pc.state_machine.transition(&"Live")
				var got_it: bool = false
				for _i: int in 180:
					_pc.simulate(DT)
					if _pc.ball.carrier == man:
						got_it = true
						break
					if _pc.ball_dead:
						break
				_expect(got_it, "jet: %s: the jet man never had the ball" % where)
				_expect(not _pc.has_run_hole, "jet: %s: a sweep blocked for a hole" % where)
				if got_it and _detail:
					print("  %s: the jet man has the ball %.2f s after the snap, %.1f yd from the quarterback" % [where, _pc.live_time, _flat(man.position, _pc.qb.position)])
			else:
				_expect(_pc.runner == back, "jet: %s: a fake changed who gets the ball" % where)
			# After he has set.
			_line_up(play, defense, flipped)
			motion = _pc.motion
			man = motion.man
			back = _pc.runner
			motion.call_motion()
			var was_open: bool = false
			for _i: int in MAX_TICKS:
				motion.tick(DT)
				was_open = was_open or motion.jet_in_window()
				if motion.state == PreSnapMotion.State.SET:
					break
			_expect(motion.state == PreSnapMotion.State.SET and not motion.jet_in_window(), "jet: %s: the window is still open with him set" % where)
			_pc.snap()
			_expect(_pc.runner == back and not motion.jet_sweep, "jet: %s: snapped late the ball still goes to him" % where)
	_line_up(_game.offense_playbook.plays[0], defense, false)
	print("jet: checked")


# --- (Y) -----------------------------------------------------------------------

func _plan_button() -> void:
	var with_motion: OffensePlay = _play("gun stick")
	var without: OffensePlay = _play("iso lead")
	var defense: DefensePlay = _defense("man cover 1")
	_game.tuning.play_clock = 0.0
	_steps.append([20, _pre_snap.bind(with_motion, defense)])
	_steps.append([2, func() -> void:
		_expect(_pc.state_machine.current_name() == &"PreSnap", "button: not in PreSnap")
		_expect(_pc.motion.available(), "button: no motion to call on Gun Stick")
		_counts["before"] = _game.stats.get(&"motions", 0)
		Input.action_press(&"motion")])
	_steps.append([2, func() -> void:
		Input.action_release(&"motion")
		_expect(_pc.motion.state == PreSnapMotion.State.MOVING, "button: (Y) did not send him")
		_expect(_game.stats.get(&"motions", 0) == _counts["before"] + 1, "button: (Y) was not counted once")])
	_steps.append([2, func() -> void: Input.action_press(&"motion")])
	_steps.append([2, func() -> void:
		Input.action_release(&"motion")
		_expect(_game.stats.get(&"motions", 0) == _counts["before"] + 1, "button: a second (Y) sent him again")])
	# A play without one.
	_steps.append([20, _pre_snap.bind(without, defense)])
	_steps.append([2, func() -> void:
		_expect(not _pc.motion.available(), "button: Iso Lead has a motion to call")
		Input.action_press(&"motion")])
	_steps.append([2, func() -> void:
		Input.action_release(&"motion")
		_expect(_pc.motion.state == PreSnapMotion.State.NONE, "button: (Y) did something on a play without a motion")])
	# The play clock runs out with him on his way.
	_steps.append([20, func() -> void:
		_game.tuning.play_clock = 0.6
		_pre_snap(with_motion, defense)])
	_steps.append([2, func() -> void: Input.action_press(&"motion")])
	_steps.append([50, func() -> void:
		Input.action_release(&"motion")
		_expect(_pc.motion.state == PreSnapMotion.State.MOVING, "button: he is not on his way")])
	_steps.append([1, func() -> void:
		_expect(_pc.state_machine.current_name() == &"Live" and not _pc.ball_dead, "button: the play clock did not snap the ball")
		_expect(_pc.motion.man.brain.off_assign != null and not _pc.motion.man.frozen, "button: the motion man is not in the play")
		_expect(_game.stats.get(&"motion_snaps", 0) > 0, "button: the snap with him on his way was not counted")
		print("button: checked")])


func _pre_snap(play: OffensePlay, defense: DefensePlay) -> void:
	if not _pc.ball_dead:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
	_game.start_drive(_team, _game.tuning.yard_to_x(_team.attack_dir, 30.0))
	_pc.line_up(play, defense)
	_pc.state_machine.transition(&"PreSnap")


# --- Helpers -------------------------------------------------------------------

func _line_up(play: OffensePlay, defense: DefensePlay, flipped: bool) -> void:
	_game.start_drive(_team, _game.tuning.yard_to_x(_team.attack_dir, 40.0))
	_pc.line_up(play, defense, flipped, false)


## Runs the motion to its end. Returns how close any two defenders came.
func _run_motion(where: String) -> float:
	var motion: PreSnapMotion = _pc.motion
	var closest: float = INF
	var still: int = 0
	var max_moving: int = 0
	for _i: int in MAX_TICKS:
		motion.tick(DT)
		var moving: int = 0
		for player: Player in _pc.offense.players:
			if player.velocity.length() > 0.2:
				moving += 1
		max_moving = maxi(max_moving, moving)
		var busy: bool = motion.state != PreSnapMotion.State.SET
		var defenders: Array[Player] = _pc.defense.players
		for i: int in defenders.size():
			if defenders[i].velocity.length() > 0.05:
				busy = true
			for j: int in i:
				var apart: float = _flat(defenders[i].position, defenders[j].position)
				if apart < closest:
					closest = apart
					_closest_note = "%s %s at %s and %s %s at %s, %.1f s in, he %s" % [
						defenders[i].brain.def_assign.label, _job(defenders[i], motion.man), _spot(defenders[i]),
						defenders[j].brain.def_assign.label, _job(defenders[j], motion.man), _spot(defenders[j]),
						motion.time, "has set" if motion.state == PreSnapMotion.State.SET else "is on his way"]
		still = 0 if busy else still + 1
		if still >= 3:
			break
	_expect(still >= 3, "move: %s: somebody is still moving after %d s" % [where, roundi(MAX_TICKS * DT)])
	_expect(max_moving <= 1, "move: %s: %d of the offense moving at once" % [where, max_moving])
	return closest


func _job(defender: Player, man: Player) -> String:
	var job: String = ["rush", "man", "zone", "spy"][defender.brain.def_assign.job]
	return job + (" (his)" if defender.brain.man_target == man and defender.brain.def_assign.job == DefenseAssignment.Job.MAN else "")


## Where a player is in the offense's frame, as text.
func _spot(player: Player) -> String:
	var at: Vector2 = Probe.frame(_pc, player.position)
	return "(%.1f, %.1f)" % [at.x, at.y]


func _positions() -> Dictionary[Player, Vector3]:
	var result: Dictionary[Player, Vector3] = {}
	for player: Player in _pc.offense.players + _pc.defense.players:
		result[player] = player.position
	return result


## How many of the offense stand on the line of scrimmage right now.
func _on_line() -> int:
	var count: int = 0
	for player: Player in _pc.offense.players:
		if player != _pc.qb and (player.position.x - _pc.los_x) * _pc.off_dir > MotionRules.ON_LINE:
			count += 1
	return count


func _play(play_name: String) -> OffensePlay:
	for play: OffensePlay in _game.offense_playbook.plays:
		if play.play_name.to_lower() == play_name:
			return play
	_failures.append("no offensive play called %s" % play_name)
	return _game.offense_playbook.plays[0]


func _defense(play_name: String) -> DefensePlay:
	for play: DefensePlay in _game.defense_playbook.plays:
		if play.play_name.to_lower() == play_name:
			return play
	_failures.append("no defensive play called %s" % play_name)
	return _game.defense_playbook.plays[0]


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _finish() -> void:
	physics_frame.disconnect(_tick)
	Input.action_release(&"motion")
	for failure: String in _failures:
		print("FAIL: " + failure)
	if _failures.size() > 40:
		print("(%d failures)" % _failures.size())
	print("presnap_motion_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message):
		_failures.append(message)
