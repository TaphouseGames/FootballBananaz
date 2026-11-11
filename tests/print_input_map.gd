extends SceneTree
## Prints every gameplay action and its bindings, to confirm project.godot parsed.
##
## Run:  godot --headless --path . --script res://tests/print_input_map.gd


func _initialize() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		var parts: PackedStringArray = PackedStringArray()
		for event: InputEvent in InputMap.action_get_events(action):
			parts.append(event.as_text())
		print("%-12s %s" % [action, ", ".join(parts)])
	quit(0)
