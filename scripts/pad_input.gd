class_name PadInput
extends RefCounted
## One person's buttons: the Input Map's actions as their own gamepad presses
## them. With no prefix it reads the plain actions, which listen to every pad
## (one person playing); with a seat's prefix ("p1_", "p2_") the copies that
## Controllers keeps bound to that seat's pad.

var prefix: String = ""
## The buttons as they were this many physics ticks ago, 0 for right now. Only
## NetFeel sets it, to try out what a delay on the wire does to the game; it
## then calls sample() once a tick.
var delay: int = 0:
	set(value):
		delay = maxi(value, 0)
		_history.clear()
## The seat's name of each action asked for so far.
var _names: Dictionary[StringName, StringName] = {}
## With a delay: what every action read on each of the last ticks, newest last.
## For each plain action its strength (x) and raw strength (y).
var _history: Array[Dictionary] = []
## The plain actions there are (not the built-in ones, not the seats' copies).
var _plain: Array[StringName] = []


func _init(p_prefix: String = "") -> void:
	prefix = p_prefix


## The action as this person's pad has it.
func action(plain: StringName) -> StringName:
	if prefix == "":
		return plain
	if not _names.has(plain):
		_names[plain] = StringName(prefix + plain)
	return _names[plain]


func just_pressed(plain: StringName) -> bool:
	if delay > 0:
		return _then(plain, 0).x > 0.0 and _then(plain, 1).x <= 0.0
	return Input.is_action_just_pressed(action(plain))


func pressed(plain: StringName) -> bool:
	if delay > 0:
		return _then(plain, 0).x > 0.0
	return Input.is_action_pressed(action(plain))


func vector(left: StringName, right: StringName, up: StringName, down: StringName) -> Vector2:
	if delay > 0:
		return _vector_then(left, right, up, down)
	return Input.get_vector(action(left), action(right), action(up), action(down))


func axis(negative: StringName, positive: StringName) -> float:
	if delay > 0:
		return _then(positive, 0).x - _then(negative, 0).x
	return Input.get_axis(action(negative), action(positive))


# --- Delayed buttons (NetFeel) ---------------------------------------------------------

## Notes what every action reads right now. Once a physics tick, before anybody
## asks, while there is a delay.
func sample() -> void:
	if delay <= 0:
		return
	if _plain.is_empty():
		for name: StringName in InputMap.get_actions():
			var text: String = name
			if not (text.begins_with("ui_") or text.begins_with("p1_") or text.begins_with("p2_")):
				_plain.append(name)
	var now: Dictionary[StringName, Vector2] = {}
	for plain: StringName in _plain:
		var mine: StringName = action(plain)
		if InputMap.has_action(mine):
			now[plain] = Vector2(Input.get_action_strength(mine), Input.get_action_raw_strength(mine))
	_history.append(now)
	while _history.size() > delay + 2:
		_history.pop_front()


## What `plain` read `delay` ticks ago, or `back` ticks before that: strength (x)
## and raw strength (y). Nothing pressed for as long as it does not go back that far.
func _then(plain: StringName, back: int) -> Vector2:
	var at: int = _history.size() - 1 - delay - back
	if at < 0:
		return Vector2.ZERO
	return _history[at].get(plain, Vector2.ZERO)


## Input.get_vector on the buttons of `delay` ticks ago: the same round dead zone.
func _vector_then(left: StringName, right: StringName, up: StringName, down: StringName) -> Vector2:
	var stick: Vector2 = Vector2(_then(right, 0).y - _then(left, 0).y, _then(down, 0).y - _then(up, 0).y)
	var dead: float = 0.0
	for plain: StringName in [left, right, up, down]:
		dead += 0.25 * InputMap.action_get_deadzone(action(plain))
	var length: float = stick.length()
	if length <= dead:
		return Vector2.ZERO
	if length > 1.0:
		return stick / length
	return stick * (inverse_lerp(dead, 1.0, length) / length)
