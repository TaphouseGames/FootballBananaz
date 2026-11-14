extends SceneTree
## Headless check of the clocks and the quarterback's shouting before the snap.
## A person's team that barely touches the pad plays until it has lined up
## twice on offense and twice on defense:
## - play select takes the highlighted play by itself when its time is up;
## - the play clock snaps the ball by itself, and (A) still snaps it sooner;
## - (B) on offense makes the quarterback shout, not faster than the gap
##   allows, and never snaps the ball; on defense it shouts nothing and still
##   switches defender;
## - a CPU quarterback with a silly line holds the snap until it is out.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/play_clock_check.gd

const STUCK_FRAMES: int = 120000
const LINE_UPS: int = 2
## Slack on a clock for the frame it runs out in, and for the fade that
## follows a pick.
const SLACK: float = 0.1
const FADE_SLACK: float = 1.3
const HOLD_FRAMES: int = 3

var _game: Game
var _audio: AudioDirector
var _frames: int = 0
var _state: StringName = &""
var _state_time: float = 0.0
## What is left to do in the current state: [time_in_state, Callable] pairs.
var _steps: Array[Array] = []
## Buttons held down by _tap and the frames each still has to go.
var _held: Dictionary[StringName, int] = {}
var _offense_line_ups: int = 0
var _defense_line_ups: int = 0
var _picks_checked: int = 0
## The play under the cursor when play select ran out, to compare at the line-up.
var _expected_play: Resource
var _shouts_before: int = 0
var _snaps_before: int = 0
var _defender_before: Player
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready():
		return false
	_audio = _game.audio
	_frames += 1
	if _frames > STUCK_FRAMES:
		_failures.append("only %d line-ups on offense and %d on defense came up" % [_offense_line_ups, _defense_line_ups])
		return _finish()
	for action: StringName in _held.keys():
		_held[action] -= 1
		if _held[action] <= 0:
			Input.action_release(action)
			_held.erase(action)
	if not _game.human.is_active():
		_failures.append("nobody is playing: the scene has no person's team")
		return _finish()

	var machine: StateMachine = _game.play_controller.state_machine
	var now: StringName = machine.current_name()
	if now != _state:
		_left(_state, _state_time)
		_state = now
		_steps.clear()
		_entered(now)
		_steps.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_state_time = machine.current.time_in_state
	while not _steps.is_empty() and _state_time >= float(_steps[0][0]):
		var step: Array = _steps.pop_front()
		(step[1] as Callable).call()
	if _offense_line_ups >= LINE_UPS and _defense_line_ups >= LINE_UPS and now == &"Live":
		_expect(_picks_checked > 0, "no pick of a play was looked at")
		return _finish()
	return false


func _entered(state: StringName) -> void:
	var tuning: Tuning = _game.tuning
	var hud: HUD = _game.hud
	match state:
		&"PlaySelect":
			# The first time the cursor is moved, so the play taken is not
			# just the first one.
			if _picks_checked == 0:
				_steps.append([1.0, _tap.bind(&"move_right")])
			_steps.append([2.0, func() -> void:
				_expect(hud.countdown.visible and hud.countdown.text == "8", "play select: the clock read '%s' with 8 s left" % hud.countdown.text)])
			_steps.append([tuning.play_select_time - 0.5, _note_cursor])
		&"PreSnap":
			_snaps_before = _game.stats.get(&"snaps", 0)
			_check_pick()
			if _game.human.team == _game.offense:
				_offense_line_ups += 1
				_plan_offense(_offense_line_ups == 1)
			else:
				_defense_line_ups += 1
				_plan_defense()
		&"Live":
			_expect(not hud.countdown.visible, "the clock is still up after the snap")


func _left(state: StringName, time: float) -> void:
	var tuning: Tuning = _game.tuning
	match state:
		&"PlaySelect":
			_expect(time >= tuning.play_select_time - SLACK, "play select ended by itself after %.2f s" % time)
			_expect(time <= tuning.play_select_time + FADE_SLACK, "play select lasted %.2f s" % time)
		&"PreSnap":
			_expect(_game.stats.get(&"snaps", 0) == _snaps_before + 1, "leaving the line-up, %d snaps were counted" % (_game.stats.get(&"snaps", 0) - _snaps_before))


## Offense. The first time nothing is pressed and the play clock snaps the
## ball; after that the quarterback shouts and (A) snaps it early.
func _plan_offense(hands_off: bool) -> void:
	var tuning: Tuning = _game.tuning
	var hud: HUD = _game.hud
	_steps.append([1.5, func() -> void:
		_expect(hud.countdown.visible and hud.countdown.text == "7", "offense: the play clock read '%s' with 6.5 s left" % hud.countdown.text)])
	if hands_off:
		_steps.append([tuning.play_clock - 0.2, func() -> void:
			_expect(_state == &"PreSnap", "the ball was snapped before the play clock ran out")])
		_steps.append([tuning.play_clock + SLACK, func() -> void:
			_failures.append("the play clock ran out and the ball was not snapped")])
		return
	_steps.append([0.9, func() -> void: _shouts_before = _shouts()])
	# Three shouts, then two inside the gap: the second of those is not heard.
	for time: float in [1.0, 1.5, 2.0, 2.5]:
		_steps.append([time, _tap.bind(&"qb_call")])
	_steps.append([2.5 + tuning.qb_call_gap * 0.5, _tap.bind(&"qb_call")])
	_steps.append([3.2, func() -> void:
		_expect(_shouts() - _shouts_before == 4, "5 presses of (B), one too soon: %d shouts" % (_shouts() - _shouts_before))
		_expect(_state == &"PreSnap", "(B) snapped the ball")
		_tap(&"confirm")])
	_steps.append([3.4, func() -> void:
		_failures.append("(A) did not snap the ball")])


## Defense: (B) shouts nothing and still switches defender. The second time
## the CPU quarterback was made to open with a silly line.
func _plan_defense() -> void:
	var tuning: Tuning = _game.tuning
	var state: GameState = _game.play_controller.state_machine.current
	if _defense_line_ups >= LINE_UPS:
		var said: float = _audio._voice.stream.get_length() if _audio._voice.stream != null else 0.0
		var hold: float = minf(said, tuning.cpu_silly_hold_max)
		_expect(_audio.play_counts.get(AudioDirector.QB_SILLY, 0) > 0, "the CPU quarterback had no silly line")
		_expect(float(state.get(&"_cpu_delay")) >= hold - 0.001, "the CPU snaps after %.2f s, its silly line takes %.2f" % [state.get(&"_cpu_delay"), hold])
	# From here on every line-up opens with a silly line.
	tuning.qb_silly_open_chance = 1.0
	_steps.append([0.2, func() -> void:
		_expect(not _game.hud.countdown.visible, "defense: the play clock is up")
		_shouts_before = _shouts()
		_defender_before = _game.human.controlled
		_tap(&"qb_call")
		_tap(&"switch_player")])
	_steps.append([0.4, func() -> void:
		_expect(_shouts() == _shouts_before, "(B) on defense made the quarterback shout")
		_expect(_game.human.controlled != _defender_before, "(B) on defense did not switch defender")])


## The play lined up is the one the cursor was on when the time ran out.
func _check_pick() -> void:
	if _expected_play == null:
		return
	var pc: PlayController = _game.play_controller
	var lined_up: Resource = pc.off_play if _game.human.team == _game.offense else pc.def_play
	_expect(lined_up == _expected_play, "the play lined up is not the highlighted one")
	_expected_play = null
	_picks_checked += 1


func _note_cursor() -> void:
	var select: GameState = _game.play_controller.state_machine.current
	var plays: Array = select.get(&"_plays")
	var cursor: int = select.get(&"_cursor")
	if _picks_checked == 0:
		_expect(cursor == 1, "the cursor is on card %d after one step right" % cursor)
	_expected_play = plays[cursor]


func _shouts() -> int:
	return _audio.play_counts.get(AudioDirector.QB_CALL, 0) + _audio.play_counts.get(AudioDirector.QB_SILLY, 0)


## One press, held for a few frames so that a physics tick is sure to see it.
func _tap(action: StringName) -> void:
	Input.action_press(action)
	_held[action] = HOLD_FRAMES


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	for action: StringName in _held:
		Input.action_release(action)
	print("line-ups: %d on offense, %d on defense; %d picks checked" % [_offense_line_ups, _defense_line_ups, _picks_checked])
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("PLAY CLOCK CHECK PASSED" if _failures.is_empty() else "PLAY CLOCK CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true
