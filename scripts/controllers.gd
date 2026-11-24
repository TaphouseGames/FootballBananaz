class_name Controllers
extends CanvasLayer
## Keeps track of the gamepads: which one is player one's and which player
## two's, and what to do when one of them goes away.
##
## The first pad to press a button is player one's. A second one joins on the
## team select (claim()). Each seat has its own copy of every action of the
## Input Map ("p1_confirm", "p2_confirm", ...), bound to that seat's pad alone;
## PadInput reads them. With one person playing nobody uses the copies: the
## plain actions listen to every pad, so whichever is picked up plays.
##
## A pad pulled out in the middle of a match stops the game with a notice until
## a pad is back on that seat (the same one, another one plugged in, or one
## nobody had that presses a button) and its (A) is pressed. With one person
## playing that only happens when no pad at all is left. In the menus it is a
## line at the top of the screen for a moment.
##
## Not an autoload (the tests run with --script): Controllers.of() makes it the
## first time it is asked for and hangs it on the root, as ScreenFade does.

## A pad went away from this seat, and one is back on it.
signal pad_lost(seat: int)
signal pad_back(seat: int)

## OK: nothing wrong. LOST: its pad is gone and the match waits. BACK: a pad is
## on it again and the match waits for its (A).
enum Pad { OK, LOST, BACK }

const SEATS: int = 2
const PREFIXES: PackedStringArray = ["p1_", "p2_"]
## The device a seat's actions are bound to while it has no pad: none there is.
## (-1 would be every pad.)
const NO_PAD: int = 99
const TOAST_TIME: float = 2.5
## Milliseconds after the start in which no pad is announced: the ones that
## were plugged in all along report in then.
const QUIET_START: int = 3000
const PANEL_COLOR: Color = Color(0.05, 0.06, 0.09, 0.96)
const TEXT_COLOR: Color = Color(0.86, 0.88, 0.86)

static var _instance: Controllers

## The pad of each seat, -1 for none.
var devices: PackedInt32Array = PackedInt32Array([-1, -1])
## Every pad's buttons: what one person playing uses.
var any: PadInput = PadInput.new()

var _inputs: Array[PadInput] = []
var _states: Array[Pad] = [Pad.OK, Pad.OK]
## The pads that are plugged in. A device that only ever sent made-up events
## (the tests) is not among them, and cannot be lost.
var _real: Dictionary[int, bool] = {}
## The match being played, or null in the menus.
var _game: Game
## The notice is gone and the match starts again once (A) is let go.
var _resuming: bool = false
var _toast_left: float = 0.0
var _built_at: int = 0

var _panel: PanelContainer
var _style: StyleBoxFlat
var _title: Label
var _line: Label
var _toast: Label


static func of(tree: SceneTree) -> Controllers:
	if not is_instance_valid(_instance):
		_instance = Controllers.new()
		_instance.name = &"Controllers"
		tree.root.add_child.call_deferred(_instance)
		# Ready at once, though it only goes into the tree at the end of the frame.
		_instance._build()
	return _instance


# --- Seats ---------------------------------------------------------------------------

## The buttons of the pad on `seat` (0 player one, 1 player two).
func input_for(seat: int) -> PadInput:
	return _inputs[seat]


## The seat `device` is on, or -1.
func seat_of(device: int) -> int:
	return devices.find(device) if device >= 0 else -1


func device_of(seat: int) -> int:
	return devices[seat]


func has_pad(seat: int) -> bool:
	return devices[seat] >= 0


## Puts `device` on the first seat without a pad and returns that seat (the one
## it has already, if any; -1 with both taken).
func claim(device: int) -> int:
	var seat: int = seat_of(device)
	if seat >= 0 or device < 0:
		return seat
	seat = devices.find(-1)
	if seat >= 0:
		_assign(seat, device)
	return seat


## Takes the pad off `seat`: player two leaving the team select.
func release(seat: int) -> void:
	if devices[seat] < 0:
		return
	devices[seat] = -1
	_states[seat] = Pad.OK
	_bind(seat)
	_refresh()


## A match is on: from here on a pad that goes away stops it.
func enter_match(game: Game) -> void:
	_game = game
	_clear()


func leave_match(game: Game) -> void:
	if _game == game:
		_game = null
		_clear()


## The match is waiting for a pad.
func blocked() -> bool:
	return _states.has(Pad.LOST) or _states.has(Pad.BACK)


## What the notice says right now (for the tests), or nothing.
func notice() -> String:
	return _title.text if _panel.visible else ""


# --- Pads coming and going -----------------------------------------------------------

## Called by Input when a pad is plugged in or pulled out.
func joy_changed(device: int, connected: bool) -> void:
	if connected:
		_real[device] = true
		var waiting: int = _states.find(Pad.LOST)
		if waiting >= 0 and seat_of(device) < 0:
			_assign(waiting, device)
		else:
			_show_toast("CONTROLLER CONNECTED")
		return
	if not _real.erase(device):
		return
	var two: bool = _in_match() and Game.two_players
	var seat: int = seat_of(device)
	if seat >= 0:
		devices[seat] = -1
		_bind(seat)
		if two:
			_states[seat] = Pad.LOST
		pad_lost.emit(seat)
	# One person plays with whichever pad there is: it takes the last one going.
	if _in_match() and not two and _real.is_empty():
		_states[0] = Pad.LOST
	if blocked():
		_refresh()
	else:
		_show_toast("CONTROLLER DISCONNECTED")


func _input(event: InputEvent) -> void:
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button == null or not button.pressed:
		return
	var seat: int = seat_of(button.device)
	if seat < 0:
		# A pad nobody has: it takes the seat that is waiting for one, or is
		# player one's when nobody is that yet.
		seat = _states.find(Pad.LOST)
		if seat < 0 and devices[0] < 0:
			seat = 0
		if seat >= 0:
			_assign(seat, button.device)
		return
	if _states[seat] == Pad.BACK and button.button_index == JOY_BUTTON_A:
		_states[seat] = Pad.OK
		_refresh()


func _assign(seat: int, device: int) -> void:
	devices[seat] = device
	_bind(seat)
	if _states[seat] == Pad.LOST:
		_states[seat] = Pad.BACK if _in_match() else Pad.OK
		pad_back.emit(seat)
	_refresh()


## Binds the seat's copy of every action to its pad. The keyboard's keys are
## copied as they are.
func _bind(seat: int) -> void:
	var prefix: String = PREFIXES[seat]
	var device: int = devices[seat] if devices[seat] >= 0 else NO_PAD
	for plain: StringName in InputMap.get_actions():
		var text: String = plain
		if text.begins_with("ui_") or text.begins_with(PREFIXES[0]) or text.begins_with(PREFIXES[1]):
			continue
		var mine: StringName = StringName(prefix + text)
		if InputMap.has_action(mine):
			InputMap.action_erase_events(mine)
		else:
			InputMap.add_action(mine, InputMap.action_get_deadzone(plain))
		for event: InputEvent in InputMap.action_get_events(plain):
			var copy: InputEvent = event.duplicate()
			if copy is InputEventJoypadButton or copy is InputEventJoypadMotion:
				copy.device = device
			InputMap.action_add_event(mine, copy)


func _in_match() -> bool:
	return is_instance_valid(_game) and not _game.autoplay


func _clear() -> void:
	for seat: int in SEATS:
		_states[seat] = Pad.OK
	_resuming = false
	_panel.visible = false


# --- The notice ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0 and not _panel.visible
	if not _resuming:
		return
	# The (A) that said "play on" is not a snap or a pass as well.
	if Input.is_action_pressed(&"confirm"):
		return
	_resuming = false
	# An open pause menu holds the game itself, and lets go of it when it closes.
	if _in_match() and not _game.hud.pause_menu.holds_pause():
		get_tree().paused = false


## Puts the notice up for the first seat that is waiting, or takes it down.
func _refresh() -> void:
	if not _in_match() or not blocked():
		if _panel.visible:
			_panel.visible = false
			_resuming = _in_match()
		return
	var seat: int = _states.find(Pad.LOST)
	var lost: bool = seat >= 0
	if not lost:
		seat = _states.find(Pad.BACK)
	var who: String = ""
	var color: Color = Color.WHITE
	if Game.two_players and seat < _game.humans.size():
		var team: Team = _game.humans[seat].team
		who = "PLAYER %d  (%s)  -  " % [seat + 1, team.short_name]
		color = team.marker_color()
	_title.text = who + ("CONTROLLER DISCONNECTED" if lost else "CONTROLLER CONNECTED")
	_title.add_theme_color_override(&"font_color", color)
	_style.border_color = color
	if lost:
		_line.text = "Plug it back in, or press a button on another controller.      Start: pause menu"
	else:
		_line.text = "Press (A) on it to play on"
	_panel.visible = true
	_resuming = false
	if is_inside_tree():
		get_tree().paused = true


func _show_toast(text: String) -> void:
	if Time.get_ticks_msec() - _built_at < QUIET_START:
		return
	_toast.text = text
	_toast_left = TOAST_TIME
	_toast.visible = not _panel.visible


func _build() -> void:
	layer = 90
	_built_at = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for seat: int in SEATS:
		_inputs.append(PadInput.new(PREFIXES[seat]))
		_bind(seat)
	for device: int in Input.get_connected_joypads():
		_real[device] = true
	Input.joy_connection_changed.connect(joy_changed)

	# Across the top, clear of the pause menu, which can be opened under it.
	_panel = PanelContainer.new()
	_style = StyleBoxFlat.new()
	_style.bg_color = PANEL_COLOR
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(8)
	_style.set_content_margin_all(12.0)
	_style.content_margin_left = 28.0
	_style.content_margin_right = 28.0
	_panel.add_theme_stylebox_override(&"panel", _style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 2)
	_panel.add_child(column)
	_title = _label(26, Color.WHITE)
	column.add_child(_title)
	_line = _label(16, TEXT_COLOR)
	column.add_child(_line)

	_toast = _label(20, Color.WHITE)
	_toast.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override(&"outline_size", 6)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.visible = false
	add_child(_toast)


func _label(font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label
