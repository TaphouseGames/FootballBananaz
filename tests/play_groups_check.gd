extends SceneTree
## Headless check of the play-select tabs: every tab of both playbooks has plays
## and no more than fit on the grid, the Hail Mary is an ordinary play on the
## deep pass tab, and the CPU never calls it on an ordinary down.
##
## Run:  godot --headless --path . --script res://tests/play_groups_check.gd

const CALLS: int = 3000

var _game: Game
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready():
		return false
	var offense: Array[OffensePlay] = _game.offense_playbook.plays
	var defense: Array[DefensePlay] = _game.defense_playbook.plays
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(OffensePlay.GROUP_NAMES.size())
	var heaves: Array[OffensePlay] = []
	for play: OffensePlay in offense:
		counts[play.group] += 1
		if play.heave_only:
			heaves.append(play)
		if play.goal_line != (play.group == OffensePlay.Group.GOAL_LINE):
			_failures.append("%s: goal line flag and tab disagree" % play.play_name)
	_check_counts("offense", OffensePlay.GROUP_NAMES, counts)
	_expect(OffensePlay.GROUP_NAMES.size() == OffensePlay.Group.size(), "offense: tab names and groups differ in number")

	counts = PackedInt32Array()
	counts.resize(DefensePlay.GROUP_NAMES.size())
	for play: DefensePlay in defense:
		counts[play.group] += 1
		if play.goal_line != (play.group == DefensePlay.Group.GOAL_LINE):
			_failures.append("%s: goal line flag and tab disagree" % play.play_name)
	_check_counts("defense", DefensePlay.GROUP_NAMES, counts)
	_expect(DefensePlay.GROUP_NAMES.size() == DefensePlay.Group.size(), "defense: tab names and groups differ in number")

	_expect(heaves.size() == 1, "%d heave-only plays in the offense playbook, wanted 1" % heaves.size())
	for play: OffensePlay in heaves:
		_expect(play.group == OffensePlay.Group.DEEP_PASS, "%s is not on the deep pass tab" % play.play_name)
		_expect(play.category == OffensePlay.Category.DEEP, "%s is not a deep play" % play.play_name)

	# An ordinary down at midfield early in the game, and one at the goal line.
	for to_goal: float in [50.0, 5.0]:
		_game.half = 1
		_game.clock = _game.tuning.game_length * 0.4
		_game.conversion = false
		_game.down = 1
		var dir: int = _game.offense.attack_dir
		_game.los_x = _game.tuning.goal_x(dir) - float(dir) * to_goal
		_expect(not _game.play_caller.situation(_game).heave, "%d yards out: the test situation is a heave" % int(to_goal))
		var called: int = 0
		for i: int in CALLS:
			if _game.play_caller.pick_offense(offense, _game).heave_only:
				called += 1
		_expect(called == 0, "%d yards out: the CPU called a heave-only play %d times in %d" % [int(to_goal), called, CALLS])

	if _failures.is_empty():
		print("play_groups_check PASSED")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("play_groups_check FAILED")
	quit(0 if _failures.is_empty() else 1)
	return true


func _check_counts(side: String, names: PackedStringArray, counts: PackedInt32Array) -> void:
	for i: int in names.size():
		_expect(counts[i] > 0, "%s: no plays on the %s tab" % [side, names[i]])
		_expect(counts[i] <= HUD.PAGE_SIZE, "%s: %d plays on the %s tab, room for %d" % [side, counts[i], names[i], HUD.PAGE_SIZE])
	print("%s tabs: %s %s" % [side, names, counts])


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
