extends SceneTree
## Prints the playbooks as Markdown for PLAY_AUDIT.md: every play with its
## line-up, the formation groups, the plays that are (mirrors of) each other,
## and where every defender of every defensive play stands against six
## offensive formations.
##
## Run:  godot --headless --path . --script res://tests/play_audit_dump.gd [-- lineups]
##   lineups   also the table of defender spots per formation (long)

const Probe: GDScript = preload("res://tests/playbook_probe.gd")
const JOBS: PackedStringArray = ["rush", "man", "zone", "spy"]

var _game: Game
var _lineups: bool = false


func _initialize() -> void:
	_lineups = OS.get_cmdline_user_args().has("lineups")
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready() or _game.play_controller == null or _game.offense == null:
		return false
	var offense: Array[OffensePlay] = _game.offense_playbook.plays
	var defense: Array[DefensePlay] = _game.defense_playbook.plays
	_offense_table(offense)
	_formation_groups(offense)
	_offense_twins(offense)
	_defense_table(defense)
	_defense_twins(defense)
	_alignment(defense)
	quit(0)
	return true


func _offense_table(plays: Array[OffensePlay]) -> void:
	print("\n### Offense: %d plays\n" % plays.size())
	print("| Play | File | Tab | Type | Skill players (x past the line, y right of the ball) | What it does |")
	print("|---|---|---|---|---|---|")
	for play: OffensePlay in plays:
		print("| %s | %s | %s | %s | %s | %s |" % [play.play_name, play.resource_path.get_file().get_basename(), OffensePlay.GROUP_NAMES[play.group], Probe.play_type(play), Probe.skill_spots(play), play.description])


func _formation_groups(plays: Array[OffensePlay]) -> void:
	var groups: Dictionary[String, Array] = {}
	for play: OffensePlay in plays:
		var key: String = Probe.formation_key(play)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(play)
	var small: int = 0
	for key: String in groups:
		if groups[key].size() < 4:
			small += groups[key].size()
	print("\n### Formation groups: %d line-ups for %d plays, %d plays in a group of fewer than 4\n" % [groups.size(), plays.size(), small])
	print("| Plays | Runs | Passes | Skill players | Plays in it |")
	print("|---|---|---|---|---|")
	for key: String in groups:
		var names: PackedStringArray = PackedStringArray()
		var runs: int = 0
		for play: OffensePlay in groups[key]:
			names.append(play.play_name)
			if play.is_run:
				runs += 1
		print("| %d | %d | %d | %s | %s |" % [names.size(), runs, names.size() - runs, Probe.skill_spots(groups[key][0]), ", ".join(names)])


func _offense_twins(plays: Array[OffensePlay]) -> void:
	print("\n### Offensive plays within %.1f yards of each other\n" % Probe.SAME_PLAY)
	var found: int = 0
	for i: int in plays.size():
		for j: int in range(i + 1, plays.size()):
			for mirror: bool in [false, true]:
				var gap: float = Probe.offense_distance(plays[i], plays[j], mirror)
				if gap <= Probe.SAME_PLAY:
					found += 1
					print("- %s / %s: %s, %.1f yd apart" % [plays[i].play_name, plays[j].play_name, "mirror" if mirror else "same side", gap])
	if found == 0:
		print("None.")


func _defense_table(plays: Array[DefensePlay]) -> void:
	print("\n### Defense: %d plays\n" % plays.size())
	print("| Play | File | Tab | Rush | Man | Zone (deep) | Spy | CPU fit run/short/deep | What it does |")
	print("|---|---|---|---|---|---|---|---|---|")
	for play: DefensePlay in plays:
		var counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
		var deep: int = 0
		for assignment: DefenseAssignment in play.assignments:
			counts[assignment.job] += 1
			if assignment.job == DefenseAssignment.Job.ZONE and assignment.deep:
				deep += 1
		print("| %s | %s | %s | %d | %d | %d (%d) | %d | %.2f / %.2f / %.2f | %s |" % [play.play_name, play.resource_path.get_file().get_basename(), DefensePlay.GROUP_NAMES[play.group], counts[0], counts[1], counts[2], deep, counts[3], play.run_fit, play.short_fit, play.deep_fit, play.description])


func _defense_twins(plays: Array[DefensePlay]) -> void:
	print("\n### Defensive plays within %.1f yards of each other\n" % Probe.SAME_PLAY)
	var found: int = 0
	for i: int in plays.size():
		for j: int in range(i + 1, plays.size()):
			for mirror: bool in [false, true]:
				var gap: float = Probe.defense_distance(plays[i], plays[j], mirror)
				if gap <= Probe.SAME_PLAY:
					found += 1
					print("- %s / %s: %s, %.1f yd apart" % [plays[i].play_name, plays[j].play_name, "mirror" if mirror else "same side", gap])
	if found == 0:
		print("None.")


## Per defensive play: how many of its coverage men move at all between the
## formations, and how many split receivers are left with nobody near them.
func _alignment(plays: Array[DefensePlay]) -> void:
	var pc: PlayController = _game.play_controller
	var formations: Dictionary[String, OffensePlay] = Probe.formations()
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 40.0))
	print("\n### Defensive line-ups against %d formations\n" % formations.size())
	print("Per formation: split receivers with no coverage defender within 5 yards across / split receivers. \"Fixed\": coverage defenders (not in man) who stand on the same spot against all six.\n")
	var header: String = "| Play | Fixed |"
	var rule: String = "|---|---|"
	for formation: String in formations:
		header += " %s |" % formation
		rule += "---|"
	print(header)
	print(rule)
	var detail: PackedStringArray = PackedStringArray()
	for play: DefensePlay in plays:
		var line: String = "| %s |" % play.play_name
		var spots: Array[Array] = []
		var cells: String = ""
		for formation: String in formations:
			pc.line_up(formations[formation], play)
			var rows: Array[Dictionary] = Probe.lineup(pc)
			var here: Array[Vector2] = []
			var text: PackedStringArray = PackedStringArray()
			for row: Dictionary in rows:
				var at: Vector2 = row["at"]
				here.append(at)
				text.append("%s %s (%.1f, %.1f)" % [row["label"], JOBS[int(row["job"])], at.x, at.y])
			spots.append(here)
			detail.append("| %s | %s | %s |" % [play.play_name, formation, ", ".join(text)])
			var open: int = 0
			var split: int = 0
			for receiver: Vector2 in Probe.skill(pc):
				if absf(receiver.y) < Probe.DETACHED or receiver.x < -2.5:
					continue
				split += 1
				var near: bool = false
				for row: Dictionary in rows:
					var at: Vector2 = row["at"]
					if int(row["job"]) != DefenseAssignment.Job.RUSH and absf(at.y - receiver.y) <= 5.0:
						near = true
				if not near:
					open += 1
			cells += " %d / %d |" % [open, split]
		var fixed: int = 0
		var movable: int = 0
		for i: int in play.assignments.size():
			var job: DefenseAssignment.Job = play.assignments[i].job
			if job == DefenseAssignment.Job.MAN or (job == DefenseAssignment.Job.RUSH and play.assignments[i].start.x <= 1.25):
				continue
			movable += 1
			var same: bool = true
			for here: Array in spots:
				if not (here[i] as Vector2).is_equal_approx(spots[0][i]):
					same = false
			if same:
				fixed += 1
		print(line + " %d of %d |" % [fixed, movable] + cells)
	if _lineups:
		print("\n### Every defender's spot\n")
		print("| Play | Against | Defenders (x past the line, y to the offense's right) |")
		print("|---|---|---|")
		for line: String in detail:
			print(line)
