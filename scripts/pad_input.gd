class_name PadInput
extends RefCounted
## One person's buttons: the Input Map's actions as their own gamepad presses
## them. With no prefix it reads the plain actions, which listen to every pad
## (one person playing); with a seat's prefix ("p1_", "p2_") the copies that
## Controllers keeps bound to that seat's pad.

var prefix: String = ""
## The seat's name of each action asked for so far.
var _names: Dictionary[StringName, StringName] = {}


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
	return Input.is_action_just_pressed(action(plain))


func pressed(plain: StringName) -> bool:
	return Input.is_action_pressed(action(plain))


func vector(left: StringName, right: StringName, up: StringName, down: StringName) -> Vector2:
	return Input.get_vector(action(left), action(right), action(up), action(down))


func axis(negative: StringName, positive: StringName) -> float:
	return Input.get_axis(action(negative), action(positive))
