extends SceneTree
## Headless rumble check. The presets have to be sane, every one named in the
## scripts has to exist (and the other way round), the mixer has to rise and
## fall on time, and a game played with random buttons has to trigger the ones
## any game has. (No gamepad is needed: this checks the levels asked for, not
## the feel in the hand.)
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/rumble_check.gd

const SPEED: float = 8.0
const STUCK_FRAMES: int = 600
const SCRIPT_DIRS: Array[String] = ["res://scripts", "res://scripts/state"]
## Rumbles a whole game cannot go without.
const EXPECTED: Array[StringName] = [&"kick", &"snap", &"tackle", &"land", &"buzzer"]
const MONKEY_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"turbo", &"jump", &"confirm", &"action", &"switch_player", &"pass_1", &"pass_2", &"pass_3", &"pass_4",
	&"jump_alt", &"spin", &"stiff_arm_left", &"stiff_arm_right",
	&"pass_lead", &"pass_under", &"flip_play", &"qb_call", &"throw_away", &"lateral", &"motion", &"audible", &"hot_route",
	&"quick_left", &"quick_right", &"quick_up", &"quick_down",
]

var _game: Game
var _state: StringName = &""
var _state_frames: int = 0
var _mixer_checked: bool = false
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	Game.human_side = 0
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null:
		return true
	# The game is not in the tree yet when it is made, so this waits.
	if _game.play_controller == null or _game.rumble.game == null:
		return false
	if not _mixer_checked:
		_mixer_checked = true
		_check_presets()
		_check_names()
		_check_mixer()
	var now: StringName = _game.play_controller.state_machine.current_name()
	if now != _state:
		_state = now
		_state_frames = 0
	_state_frames += 1
	_mash_buttons()
	if _state_frames > STUCK_FRAMES:
		_failures.append("stuck in state '%s'" % _state)
		return _report()
	if _state == &"GameOver":
		return _report()
	return false


## Random presses and releases on every gameplay action, as the human player.
func _mash_buttons() -> void:
	for action: StringName in MONKEY_ACTIONS:
		if randf() < 0.12:
			if Input.is_action_pressed(action):
				Input.action_release(action)
			else:
				Input.action_press(action)


func _check_presets() -> void:
	for preset: StringName in Rumble.PRESETS:
		var steps: Array = Rumble.PRESETS[preset]
		if steps.is_empty():
			_failures.append("'%s' has no steps" % preset)
		for step: Array in steps:
			if step.size() != 4:
				_failures.append("'%s' has a step of %d numbers, not 4" % [preset, step.size()])
				continue
			var weak: float = step[0]
			var strong: float = step[1]
			var seconds: float = step[2]
			var delay: float = step[3]
			if weak < 0.0 or weak > 1.0 or strong < 0.0 or strong > 1.0 or weak + strong <= 0.0:
				_failures.append("'%s' has motor levels %.2f / %.2f" % [preset, weak, strong])
			if seconds <= 0.0 or seconds > 1.0 or delay < 0.0 or delay + seconds > 1.5:
				_failures.append("'%s' lasts %.2f s after %.2f s" % [preset, seconds, delay])


## Every preset named in the scripts exists, and every preset is used.
func _check_names() -> void:
	var any_name: RegEx = RegEx.new()
	any_name.compile("&\"(\\w+)\"")
	var own_play: RegEx = RegEx.new()
	own_play.compile("\\bplay\\(&\"(\\w+)\"")
	var used: Dictionary[StringName, bool] = {}
	for dir: String in SCRIPT_DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if file.get_extension() != "gd":
				continue
			var own: bool = file == "rumble.gd"
			for line: String in FileAccess.get_file_as_string(dir.path_join(file)).split("\n"):
				if own:
					for hit: RegExMatch in own_play.search_all(line):
						used[StringName(hit.get_string(1))] = true
				elif line.contains("rumble.play"):
					for hit: RegExMatch in any_name.search_all(line):
						used[StringName(hit.get_string(1))] = true
	for preset: StringName in used:
		if not Rumble.PRESETS.has(preset):
			_failures.append("the scripts ask for '%s', which is no preset" % preset)
	for preset: StringName in Rumble.PRESETS:
		if not used.has(preset):
			_failures.append("preset '%s' is never played" % preset)


func _check_mixer() -> void:
	var rumble: Rumble = _game.rumble
	var human: HumanController = _game.human
	var tuning: Tuning = _game.tuning
	var was_controlled: Player = human.controlled
	var mine: Player = _game.home.players[0]
	var other: Player = _game.away.players[0]
	human.controlled = mine
	rumble.stop()

	# One pulse: there at once, gone when its time is up.
	rumble.play(&"tackle")
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2(0.5, 0.8), "a tackle at the start")
	rumble.advance(0.2)
	_expect(rumble.level(), Vector2(0.5, 0.8), "a tackle after 0.2 s")
	rumble.advance(0.1)
	_expect(rumble.level(), Vector2.ZERO, "a tackle after 0.3 s")

	# Two at once: the stronger of each motor, not the sum and not the later one.
	rumble.play(&"tackle")
	rumble.play(&"shove")
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2(0.5, 0.8), "a tackle with a shove on top")
	rumble.stop()

	# Steps that start later.
	rumble.play(&"touchdown")
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2(0.7, 0.7), "a touchdown at the start")
	rumble.advance(0.45)
	_expect(rumble.level(), Vector2.ZERO, "a touchdown between its beats")
	rumble.advance(0.1)
	_expect(rumble.level(), Vector2(0.5, 0.4), "a touchdown's second beat")
	rumble.advance(1.0)
	_expect(rumble.level(), Vector2.ZERO, "a touchdown once it is over")

	# Whose hit it was.
	rumble.play_mine(&"knockdown", other)
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2.ZERO, "somebody else's knockdown")
	rumble.play_mine(&"knockdown", other, mine)
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2(0.4, 0.65), "the person's own knockdown")
	rumble.stop()
	rumble.play_for(&"tackle", other)
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2(0.5, 0.8) * tuning.rumble_others, "somebody else's tackle")
	rumble.stop()
	rumble.play_team(&"catch", _game.away)
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2.ZERO, "the other team's catch")
	rumble.play(&"wall", 5.0)
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2(1.0, 1.0), "a rumble scaled past full")
	rumble.stop()

	# A drag holds for as long as it is asked for.
	rumble.hold_drag(mine, other)
	rumble.advance(0.05)
	_expect(rumble.level(), Rumble.DRAG_HOLD, "a drag being held")
	rumble.advance(0.3)
	_expect(rumble.level(), Vector2.ZERO, "a drag let go")
	rumble.hold_drag(other, null)
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2.ZERO, "somebody else's drag")

	# The pause menu stops it.
	rumble.play(&"tackle")
	rumble.advance(0.0)
	paused = true
	_expect(rumble.level(), Vector2.ZERO, "a tackle with the game paused")
	paused = false
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2.ZERO, "a tackle after the pause")

	# Switched off, and with nobody playing.
	var count: int = rumble.play_counts.get(&"tackle", 0)
	tuning.rumble_enabled = false
	rumble.play(&"tackle")
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2.ZERO, "a tackle with rumble off")
	tuning.rumble_enabled = true
	var team: Team = human.team
	human.team = null
	rumble.play(&"tackle")
	rumble.play_for(&"tackle", mine)
	rumble.advance(0.0)
	_expect(rumble.level(), Vector2.ZERO, "a tackle in autoplay")
	human.team = team
	if rumble.play_counts.get(&"tackle", 0) != count:
		_failures.append("a rumble was counted while it was off")
	if team == null:
		_failures.append("the game has no human team to test with")

	rumble.stop()
	rumble.play_counts.clear()
	human.controlled = was_controlled


func _expect(got: Vector2, wanted: Vector2, what: String) -> void:
	if not got.is_equal_approx(wanted):
		_failures.append("%s: motors at %.2f / %.2f, not %.2f / %.2f" % [what, got.x, got.y, wanted.x, wanted.y])


func _report() -> bool:
	var rumble: Rumble = _game.rumble
	for preset: StringName in rumble.unknown:
		_failures.append("asked for '%s', which is no preset" % preset)
	for preset: StringName in EXPECTED:
		if rumble.play_counts.get(preset, 0) == 0:
			_failures.append("'%s' never played" % preset)

	var names: Array[StringName] = rumble.play_counts.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	print("Rumbles this game:")
	for preset: StringName in names:
		print("  %-20s %d" % [preset, rumble.play_counts[preset]])
	var quiet: PackedStringArray = PackedStringArray()
	for preset: StringName in Rumble.PRESETS:
		if not rumble.play_counts.has(preset):
			quiet.append(String(preset))
	print("Not felt this game: %s" % (", ".join(quiet) if not quiet.is_empty() else "none"))
	if _failures.is_empty():
		print("RUMBLE CHECK PASSED")
	else:
		for failure: String in _failures:
			print("FAIL: %s" % failure)
		print("RUMBLE CHECK FAILED")
	for action: StringName in MONKEY_ACTIONS:
		Input.action_release(action)
	Game.human_side = -1
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true
