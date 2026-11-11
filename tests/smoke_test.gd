extends SceneTree
## Headless smoke test: the CPU plays both teams for a whole game at high speed.
## Fails if a state gets stuck or the basic football events never happen.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd
## Optional user args after "--":
##   games=<n>   play n games (default 1)
##   monkey      random button presses play the human team (exercises input code)

const SPEED: float = 8.0
## Frames a single state may last (at SPEED x 60 fps, 600 frames = 80 game seconds).
const STUCK_FRAMES: int = 600
const MONKEY_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"turbo", &"pass_switch", &"action", &"play_1", &"play_2", &"play_3",
]

var _game: Game
var _state: StringName = &""
var _state_frames: int = 0
var _games_left: int = 1
## The person's team is driven by random button presses instead of the CPU.
var _monkey: bool = false
var _failures: PackedStringArray = PackedStringArray()
var _totals: Dictionary[StringName, int] = {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("games="):
			_games_left = maxi(int(arg.trim_prefix("games=")), 1)
		elif arg == "monkey":
			_monkey = true
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	_start_game()


func _start_game() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = not _monkey
	root.add_child(_game)
	_state = &""
	_state_frames = 0


func _process(_delta: float) -> bool:
	if _game == null:
		return true
	var now: StringName = _game.play_controller.state_machine.current_name()
	if now != _state:
		_state = now
		_state_frames = 0
	_state_frames += 1
	if _monkey:
		_mash_buttons()

	if _state == &"GameOver":
		return _finish_game()
	if _state_frames > STUCK_FRAMES:
		_failures.append("stuck in state '%s' (down %d, los %.1f, clock %.1f)" % [_state, _game.down, _game.los_x, _game.clock])
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


func _finish_game() -> bool:
	print("game over: %s %d - %d %s   stats: %s" % [_game.home.short_name, _game.home.score, _game.away.score, _game.away.short_name, _game.stats])
	for key: StringName in _game.stats:
		var so_far: int = _totals.get(key, 0)
		_totals[key] = so_far + _game.stats[key]
	_games_left -= 1
	if _games_left > 0:
		_game.free()
		_start_game()
		return false
	return _report()


func _report() -> bool:
	for key: StringName in [&"snaps", &"passes", &"completions", &"tackles", &"handoffs", &"turnovers"]:
		var count: int = _totals.get(key, 0)
		if count <= 0 and _failures.is_empty():
			_failures.append("no '%s' happened in the whole run" % key)
	var drives: int = _totals.get(&"drives", 0)
	if drives < 2 and _failures.is_empty():
		_failures.append("possession never changed")

	print("totals: %s" % _totals)
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("SMOKE TEST FAILED: %s" % failure)
		quit(1)
	return true
