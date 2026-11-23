class_name Rumble
extends Node
## Shakes the person's gamepad with what happens to their player: hits given and
## taken, the ball leaving and reaching his hands, scores. Nothing in autoplay.
##
## A gamepad has two motors: the weak one is small and buzzes (ticks, clicks),
## the strong one is big and thuds (bodies). Starting a vibration replaces the
## one that is running, so the pulses are mixed here and the pad is only told
## when the level changes.

## What each moment feels like: one or more steps of weak motor, strong motor
## (both 0..1), seconds it lasts and seconds before it starts.
const PRESETS: Dictionary[StringName, Array] = {
	# Hits.
	&"tackle": [[0.5, 0.8, 0.25, 0.0]],
	&"big_hit": [[0.7, 1.0, 0.35, 0.0]],
	&"drag": [[0.4, 0.45, 0.12, 0.0]],
	&"broken_tackle": [[0.6, 0.5, 0.18, 0.0]],
	&"knockdown": [[0.4, 0.65, 0.2, 0.0]],
	&"qb_hit": [[0.6, 0.85, 0.3, 0.0]],
	&"wall": [[0.6, 1.0, 0.3, 0.0]],
	&"land": [[0.2, 0.45, 0.12, 0.0]],
	&"daze": [[0.5, 0.3, 0.25, 0.0]],
	&"pancake": [[0.3, 0.5, 0.15, 0.0]],
	&"stuffed": [[0.5, 0.7, 0.22, 0.0]],
	&"shove": [[0.3, 0.0, 0.07, 0.0]],
	# The ball.
	&"snap": [[0.25, 0.0, 0.07, 0.0]],
	&"audible": [[0.25, 0.0, 0.06, 0.0]],
	&"kick": [[0.15, 0.35, 0.1, 0.0]],
	&"throw": [[0.5, 0.35, 0.08, 0.0]],
	&"flair": [[0.5, 0.3, 0.15, 0.0]],
	&"lateral": [[0.35, 0.2, 0.08, 0.0]],
	&"catch": [[0.4, 0.25, 0.1, 0.0]],
	&"tip": [[0.3, 0.0, 0.06, 0.0]],
	&"fake_out": [[0.3, 0.0, 0.07, 0.0]],
	&"interception": [[0.5, 0.6, 0.25, 0.0]],
	&"fumble": [[0.7, 0.7, 0.3, 0.0]],
	# The run.
	&"hole": [[0.35, 0.0, 0.1, 0.0]],
	&"spent": [[0.3, 0.0, 0.05, 0.0], [0.3, 0.0, 0.05, 0.1]],
	# The game.
	&"touchdown": [[0.7, 0.7, 0.4, 0.0], [0.5, 0.4, 0.12, 0.5], [0.5, 0.4, 0.12, 0.72]],
	&"touchdown_against": [[0.2, 0.45, 0.3, 0.0]],
	&"buzzer": [[0.3, 0.3, 0.4, 0.0]],
}
## The steady level of a drag: the weak and the strong motor.
const DRAG_HOLD: Vector2 = Vector2(0.15, 0.3)
## Seconds a held level lasts after it was last asked for. Longer than a physics
## tick takes in a hit-stop.
const HOLD_TIME: float = 0.15
## The pad is told to shake for this long at a time and reminded before it is
## up, so it stops by itself should this node ever stop running.
const SEND_TIME: float = 0.3
const RESEND_TIME: float = 0.15
## A stick has to be pushed this far for its gamepad to count as the one in use.
const STICK_IN_USE: float = 0.5

## How often each preset was asked for (for the tests), and names asked for that
## are not in PRESETS.
var play_counts: Dictionary[StringName, int] = {}
var unknown: Array[StringName] = []

var game: Game
var tuning: Tuning
var human: HumanController

## Pulses running or waiting: weak, strong, seconds left, seconds before it starts.
var _pulses: Array[Vector4] = []
var _hold: Vector2 = Vector2.ZERO
var _hold_left: float = 0.0
## What the motors are at now, weak and strong, and what the pad was last told.
var _level: Vector2 = Vector2.ZERO
var _sent: Vector2 = Vector2.ZERO
var _sent_age: float = 0.0
var _sent_pad: int = -1
## The gamepad last used, -1 before any was.
var _device: int = -1
var _last_tick: int = 0
## The player whose stamina is watched, and whether he was out of it.
var _watched: Player
var _was_spent: bool = false


func setup(p_game: Game) -> void:
	game = p_game
	tuning = game.tuning
	human = game.human
	_last_tick = Time.get_ticks_usec()
	game.play_controller.state_machine.state_changed.connect(_on_state_changed)


func _exit_tree() -> void:
	stop()


func _notification(what: int) -> void:
	# The pause menu is up: nothing is happening to anybody.
	if what == NOTIFICATION_PAUSED:
		stop()
	elif what == NOTIFICATION_UNPAUSED:
		_last_tick = Time.get_ticks_usec()


func _input(event: InputEvent) -> void:
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button != null and button.pressed:
		_device = button.device
		return
	var stick: InputEventJoypadMotion = event as InputEventJoypadMotion
	if stick != null and absf(stick.axis_value) >= STICK_IN_USE:
		_device = stick.device


func _process(_delta: float) -> void:
	# Real time: a hit-stop slows the game down, not the motors.
	var now: int = Time.get_ticks_usec()
	var delta: float = float(now - _last_tick) / 1000000.0
	_last_tick = now
	_watch_stamina()
	advance(delta)


## The person's player is part of it (either of the two may be null).
func involves(a: Player, b: Player = null) -> bool:
	if human == null or human.controlled == null:
		return false
	return human.controlled == a or human.controlled == b


## Plays a preset, at `scale` times its strength.
func play(preset: StringName, scale: float = 1.0) -> void:
	if not _on() or scale <= 0.0:
		return
	if not PRESETS.has(preset):
		if not unknown.has(preset):
			unknown.append(preset)
			push_warning("Rumble: no preset called '%s'" % preset)
		return
	play_counts[preset] = play_counts.get(preset, 0) + 1
	scale *= tuning.rumble_strength
	for step: Array in PRESETS[preset]:
		var weak: float = clampf(float(step[0]) * scale, 0.0, 1.0)
		var strong: float = clampf(float(step[1]) * scale, 0.0, 1.0)
		_pulses.append(Vector4(weak, strong, float(step[2]), float(step[3])))


## Plays it only when the person's player is `a` or `b`.
func play_mine(preset: StringName, a: Player, b: Player = null, scale: float = 1.0) -> void:
	if involves(a, b):
		play(preset, scale)


## Plays it in full when the person's player is `a` or `b`, and faintly
## (Tuning.rumble_others) when it happened to somebody else.
func play_for(preset: StringName, a: Player, b: Player = null, scale: float = 1.0) -> void:
	if _on():
		play(preset, scale if involves(a, b) else scale * tuning.rumble_others)


## Plays it when `team` is the person's.
func play_team(preset: StringName, team: Team, scale: float = 1.0) -> void:
	if human != null and team != null and team == human.team:
		play(preset, scale)


## A steady level for as long as this is called every tick: the person's player
## (`a` or `b`) is dragging somebody or being dragged.
func hold_drag(a: Player, b: Player) -> void:
	if not _on() or not involves(a, b):
		return
	_hold = DRAG_HOLD * tuning.rumble_strength
	_hold_left = HOLD_TIME


## Everything off, now.
func stop() -> void:
	_pulses.clear()
	_hold_left = 0.0
	_level = Vector2.ZERO
	_send()


## What the motors are at: x the weak one, y the strong one.
func level() -> Vector2:
	return _level


## Moves every pulse on by `delta` real seconds and sets the motors to the
## strongest of what is running.
func advance(delta: float) -> void:
	var weak: float = 0.0
	var strong: float = 0.0
	_hold_left -= delta
	if _hold_left > 0.0:
		weak = _hold.x
		strong = _hold.y
	var i: int = _pulses.size() - 1
	while i >= 0:
		var pulse: Vector4 = _pulses[i]
		# What is left of `delta` once the wait is over comes off its length.
		pulse.w -= delta
		if pulse.w < 0.0:
			pulse.z += pulse.w
			pulse.w = 0.0
		if pulse.z <= 0.0:
			_pulses.remove_at(i)
		else:
			_pulses[i] = pulse
			if pulse.w <= 0.0:
				weak = maxf(weak, pulse.x)
				strong = maxf(strong, pulse.y)
		i -= 1
	_level = Vector2(weak, strong) if _on() else Vector2.ZERO
	_sent_age += delta
	_send()


func _on() -> bool:
	return game != null and tuning.rumble_enabled and human.is_active()


## The gamepad to shake: the one last used, or the first there is. -1 for none.
func _pad() -> int:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.has(_device):
		return _device
	return pads[0] if not pads.is_empty() else -1


## Tells the pad, when there is something new to tell it.
func _send() -> void:
	var pad: int = _pad()
	if pad != _sent_pad:
		if _sent_pad >= 0 and _sent != Vector2.ZERO:
			Input.stop_joy_vibration(_sent_pad)
		_sent_pad = pad
		_sent = Vector2.ZERO
	if pad < 0:
		return
	if _level == Vector2.ZERO:
		if _sent != Vector2.ZERO:
			Input.stop_joy_vibration(pad)
			_sent = Vector2.ZERO
		return
	if _level.is_equal_approx(_sent) and _sent_age < RESEND_TIME:
		return
	Input.start_joy_vibration(pad, _level.x, _level.y, SEND_TIME)
	_sent = _level
	_sent_age = 0.0


## Two ticks when the person's player runs out of stamina.
func _watch_stamina() -> void:
	var player: Player = human.controlled if human != null else null
	var spent: bool = player != null and player.turbo_locked
	if player == _watched and spent and not _was_spent:
		play(&"spent")
	_watched = player
	_was_spent = spent


func _on_state_changed(_from: StringName, to: StringName) -> void:
	if to == &"Halftime" or to == &"Overtime" or to == &"GameOver":
		play(&"buzzer")
