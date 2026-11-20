extends SceneTree
## Headless check of the playbooks' rules, so a new play cannot bring the old
## problems back:
##  - every offensive formation (pixel-identical line-up) has at least
##    MIN_PLAYS plays, runs and passes among them, and is one tab;
##  - no play is another play again, or its mirror image (the flip button does
##    that), on offense or on defense;
##  - every defensive play lines up on the offense in front of it: its corners
##    and the men who can walk out move with the receivers, nobody able to cover
##    a split receiver leaves him alone, nobody stands in a teammate, every
##    defender has a job and no receiver gets two men while another gets none;
##  - every route stays on the field.
##
## Run:  godot --headless --path . --script res://tests/playbook_rules_check.gd

const Probe: GDScript = preload("res://tests/playbook_probe.gd")
const MIN_PLAYS: int = 4
## A coverage defender within this many yards across of a receiver is on him.
const REACH: float = 5.0
## Defenders closer together than this stand in each other.
const CROWDED: float = 1.0

var _game: Game
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready() or _game.play_controller == null or _game.offense == null:
		return false
	var offense: Array[OffensePlay] = _game.offense_playbook.plays
	var defense: Array[DefensePlay] = _game.defense_playbook.plays
	_check_formations(offense)
	_check_routes(offense)
	_check_motion(offense)
	_check_twins(offense, defense)
	_check_alignment(offense, defense)
	if _failures.is_empty():
		print("playbook_rules_check PASSED")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("playbook_rules_check FAILED")
	quit(0 if _failures.is_empty() else 1)
	return true


func _check_formations(plays: Array[OffensePlay]) -> void:
	var groups: Dictionary[String, Array] = {}
	for play: OffensePlay in plays:
		var key: String = Probe.formation_key(play)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(play)
	for key: String in groups:
		var names: PackedStringArray = PackedStringArray()
		var runs: int = 0
		var tabs: Array[int] = []
		for play: OffensePlay in groups[key]:
			names.append(play.play_name)
			if play.is_run:
				runs += 1
			if not tabs.has(play.group):
				tabs.append(play.group)
		var listed: String = ", ".join(names)
		_expect(names.size() >= MIN_PLAYS, "only %d plays line up like this, wanted %d: %s" % [names.size(), MIN_PLAYS, listed])
		_expect(runs > 0, "no run from this line-up: %s" % listed)
		_expect(runs < names.size(), "no pass from this line-up: %s" % listed)
		_expect(tabs.size() == 1, "one line-up on %d tabs: %s" % [tabs.size(), listed])
	_expect(groups.size() <= OffensePlay.GROUP_NAMES.size(), "%d line-ups for %d tabs" % [groups.size(), OffensePlay.GROUP_NAMES.size()])
	print("offense: %d plays in %d formations" % [plays.size(), groups.size()])


## No route leaves the field sideways, and nobody but the linemen starts inside
## another player.
func _check_routes(plays: Array[OffensePlay]) -> void:
	var limit: float = _game.tuning.half_width() - 1.0
	for play: OffensePlay in plays:
		for i: int in play.assignments.size():
			var assignment: OffenseAssignment = play.assignments[i]
			_expect(absf(assignment.start.y) <= limit, "%s: %s lines up off the field" % [play.play_name, assignment.label])
			for waypoint: Vector2 in assignment.route:
				_expect(absf(assignment.start.y + waypoint.y) <= limit, "%s: %s's route leaves the field" % [play.play_name, assignment.label])
			for j: int in i:
				_expect(assignment.start.distance_to(play.assignments[j].start) >= 1.0, "%s: %s and %s line up in each other" % [play.play_name, assignment.label, play.assignments[j].label])
			if assignment.job == OffenseAssignment.Job.ROUTE or assignment.job == OffenseAssignment.Job.RUNNER:
				_expect(not assignment.route.is_empty(), "%s: %s has nowhere to run" % [play.play_name, assignment.label])


## A play's motion (LB) or (RB) keeps to the rules of MotionRules: only a receiver off
## the line moves, he never moves toward it and ends off it, and what he does
## afterwards starts from where the motion puts him. Within a formation the
## same man moves in every play, and no kind of motion is only ever a run or
## only ever a pass, so the motion does not give the play away either.
func _check_motion(plays: Array[OffensePlay]) -> void:
	var half_width: float = _game.tuning.half_width()
	var with_motion: int = 0
	## Formation -> motion kind -> [runs, passes].
	var kinds: Dictionary[String, Dictionary] = {}
	for play: OffensePlay in plays:
		for problem: String in MotionRules.problems(play, half_width):
			_expect(false, "%s: %s" % [play.play_name, problem])
		if not MotionRules.has_motion(play):
			continue
		with_motion += 1
		var key: String = Probe.formation_key(play)
		if not kinds.has(key):
			kinds[key] = {}
		var counts: Array = kinds[key].get(play.motion, [0, 0])
		counts[0 if play.is_run else 1] += 1
		kinds[key][play.motion] = counts
	for key: String in kinds:
		var runs: int = 0
		var passes: int = 0
		for kind: int in kinds[key]:
			runs += kinds[key][kind][0]
			passes += kinds[key][kind][1]
		_expect(runs > 0 and passes > 0, "a formation whose motions are all %s" % ("runs" if passes == 0 else "passes"))
	print("offense: %d plays with a motion" % with_motion)


func _check_twins(offense: Array[OffensePlay], defense: Array[DefensePlay]) -> void:
	for i: int in offense.size():
		for j: int in range(i + 1, offense.size()):
			for mirror: bool in [false, true]:
				var gap: float = Probe.offense_distance(offense[i], offense[j], mirror)
				_expect(gap > Probe.SAME_PLAY, "%s and %s are %s (%.1f yd apart)" % [offense[i].play_name, offense[j].play_name, "mirror images" if mirror else "the same play", gap])
	for i: int in defense.size():
		for j: int in range(i + 1, defense.size()):
			for mirror: bool in [false, true]:
				var gap: float = Probe.defense_distance(defense[i], defense[j], mirror)
				_expect(gap > Probe.SAME_PLAY, "%s and %s are %s (%.1f yd apart)" % [defense[i].play_name, defense[j].play_name, "mirror images" if mirror else "the same play", gap])


func _check_alignment(offense: Array[OffensePlay], defense: Array[DefensePlay]) -> void:
	var pc: PlayController = _game.play_controller
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 40.0))
	# The six test formations, and the playbook's own.
	var formations: Dictionary[String, OffensePlay] = Probe.formations()
	var own: Array[int] = []
	for play: OffensePlay in offense:
		if not own.has(play.group):
			own.append(play.group)
			formations[OffensePlay.GROUP_NAMES[play.group]] = play
	var lineups: int = 0
	for play: DefensePlay in defense:
		var adapts: bool = false
		var spots: Array[Array] = []
		for formation: String in formations:
			for flipped: bool in [false, true]:
				pc.line_up(formations[formation], play, false, flipped)
				lineups += 1
				var rows: Array[Dictionary] = Probe.lineup(pc)
				if not flipped:
					var here: Array[Vector2] = []
					for row: Dictionary in rows:
						here.append(row["at"])
					spots.append(here)
				_check_lineup(play, "%s%s" % [formation, " (flipped)" if flipped else ""], rows, pc, -1.0 if flipped else 1.0)
		for i: int in play.assignments.size():
			var assignment: DefenseAssignment = play.assignments[i]
			var moves: bool = false
			for here: Array in spots:
				if not (here[i] as Vector2).is_equal_approx(spots[0][i]):
					moves = true
			if assignment.job == DefenseAssignment.Job.MAN or assignment.align != DefenseAssignment.Align.SPOT:
				adapts = true
				_expect(moves, "%s: %s (%s) stands on one spot against every formation" % [play.play_name, assignment.label, _job(assignment)])
			if assignment.job == DefenseAssignment.Job.ZONE:
				_expect(assignment.zone_radius > 0.0, "%s: %s has a zone of no size" % [play.play_name, assignment.label])
				# A zone defender who is not on the line has to be able to move.
				_expect(assignment.align != DefenseAssignment.Align.SPOT, "%s: %s plays a zone from a fixed spot" % [play.play_name, assignment.label])
		_expect(adapts, "%s: nobody lines up on the offense" % play.play_name)
	print("defense: %d plays, %d line-ups checked" % [defense.size(), lineups])


func _check_lineup(play: DefensePlay, against: String, rows: Array[Dictionary], pc: PlayController, flip: float) -> void:
	var where: String = "%s against %s" % [play.play_name, against]
	for i: int in rows.size():
		for j: int in i:
			var gap: float = (rows[i]["at"] as Vector2).distance_to(rows[j]["at"])
			_expect(gap >= CROWDED, "%s: two defenders %.1f yd apart" % [where, gap])
		if int(rows[i]["job"]) == DefenseAssignment.Job.MAN:
			_expect(rows[i]["man"] != null, "%s: a man defender with no man" % where)
			if rows[i]["man"] != null:
				_expect(absf((rows[i]["at"] as Vector2).y - (rows[i]["man"] as Vector2).y) < 0.1, "%s: a man defender not across from his man" % where)

	# Split receivers nobody is near, while somebody who could be is elsewhere.
	var split: Array[Vector2] = []
	for receiver: Vector2 in Probe.skill(pc):
		if absf(receiver.y) >= Probe.DETACHED and receiver.x >= -2.5:
			split.append(receiver)
	var limit: float = _game.tuning.half_width()
	for i: int in rows.size():
		var at: Vector2 = rows[i]["at"]
		_expect(absf(at.y) < limit, "%s: a defender lines up off the field" % where)
	for receiver: Vector2 in split:
		if _covered(receiver, rows, play):
			continue
		for i: int in rows.size():
			var assignment: DefenseAssignment = play.assignments[i]
			if assignment.job == DefenseAssignment.Job.MAN or assignment.job == DefenseAssignment.Job.RUSH:
				continue
			var at: Vector2 = rows[i]["at"]
			var idle: bool = true
			for other: Vector2 in split:
				if absf(at.y - other.y) <= REACH:
					idle = false
			# The side the play draws him on is the side his zone is on.
			var drawn: float = assignment.start.y * flip
			var same_side: bool = drawn * receiver.y > 0.0
			if idle and assignment.align == DefenseAssignment.Align.OUTSIDE and same_side:
				_expect(false, "%s: a corner stands over nobody with the receiver at %.0f uncovered" % [where, receiver.y])
			elif idle and assignment.align == DefenseAssignment.Align.SLOT and (same_side or absf(drawn) < DefenseAligner.MIDDLE):
				_expect(false, "%s: nobody walked out to the receiver at %.0f" % [where, receiver.y])

	# Two men on one receiver while another has nobody, with no zone behind it.
	var men: Dictionary[Vector2, int] = {}
	var zones: int = 0
	for row: Dictionary in rows:
		if int(row["job"]) == DefenseAssignment.Job.ZONE:
			zones += 1
		elif row["man"] != null:
			men[row["man"]] = men.get(row["man"], 0) + 1
	if zones == 0:
		var doubled: bool = false
		for man: Vector2 in men:
			if men[man] > 1:
				doubled = true
		var free: int = 0
		for receiver: Player in pc.eligible:
			if not men.has(Probe.frame(pc, receiver.position)):
				free += 1
		_expect(not (doubled and free > 0), "%s: a receiver is doubled while %d have nobody and there is no zone" % [where, free])


## A corner who blitzes from over the receiver counts: that is the play.
func _covered(receiver: Vector2, rows: Array[Dictionary], play: DefensePlay) -> bool:
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		var shows: bool = int(row["job"]) != DefenseAssignment.Job.RUSH or play.assignments[i].align == DefenseAssignment.Align.OUTSIDE
		if shows and absf((row["at"] as Vector2).y - receiver.y) <= REACH + (DefenseAligner.BLITZ_CHEAT if int(row["job"]) == DefenseAssignment.Job.RUSH else 0.0):
			return true
	return false


func _job(assignment: DefenseAssignment) -> String:
	return ["rush", "man", "zone", "spy"][assignment.job]


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message):
		_failures.append(message)
