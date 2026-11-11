class_name StateMachine
extends Node
## Minimal state machine: every GameState child is a state, keyed by node name.

signal state_changed(from: StringName, to: StringName)

var current: GameState
var states: Dictionary[StringName, GameState] = {}


func setup(pc: PlayController) -> void:
	for child: Node in get_children():
		var state: GameState = child as GameState
		if state != null:
			state.machine = self
			state.pc = pc
			state.game = pc.game
			states[StringName(state.name)] = state


func current_name() -> StringName:
	return StringName(current.name) if current != null else &""


func transition(to: StringName) -> void:
	if not states.has(to):
		push_error("Unknown game state: %s" % to)
		return
	var from: StringName = current_name()
	if current != null:
		current.exit()
	current = states[to]
	current.time_in_state = 0.0
	current.enter()
	state_changed.emit(from, to)


func physics_update(delta: float) -> void:
	if current == null:
		return
	current.time_in_state += delta
	current.physics_update(delta)
