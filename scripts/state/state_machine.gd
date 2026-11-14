class_name StateMachine
extends Node
## Minimal state machine: every GameState child is a state, keyed by node name.

signal state_changed(from: StringName, to: StringName)

## States whose enter() moves the teams or cuts the camera: the screen dips to
## black on the way into them (see ScreenFade).
const FADE_INTO: Array[StringName] = [&"PlaySelect", &"PreSnap", &"Kickoff", &"Scramble"]
## Longest wait for the black, in case something else held the fade up.
const FADE_WAIT: float = 1.0

var current: GameState
var states: Dictionary[StringName, GameState] = {}
## The state waiting for the screen to go black, or empty, and how long it has.
var _pending: StringName = &""
var _pending_time: float = 0.0


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


## Into a FADE_INTO state the switch waits for the screen to go black.
func transition(to: StringName) -> void:
	if not states.has(to):
		push_error("Unknown game state: %s" % to)
		return
	if _pending != &"":
		return
	if current != null and to in FADE_INTO and ScreenFade.active():
		_pending = to
		_pending_time = 0.0
		ScreenFade.of(get_tree()).cover()
		return
	_switch(to)


func _switch(to: StringName) -> void:
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
	if _pending == &"":
		current.physics_update(delta)
		return
	# The state has already asked to go: it only keeps the picture moving.
	current.hold_update(delta)
	_pending_time += delta
	var fade: ScreenFade = ScreenFade.of(get_tree())
	if fade.is_covered() or _pending_time >= FADE_WAIT:
		var to: StringName = _pending
		_pending = &""
		_switch(to)
		fade.reveal()
