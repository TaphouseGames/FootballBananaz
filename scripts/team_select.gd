class_name TeamSelect
extends Control
## The screen between START GAME and the match: a team on the left, a team on
## the right and the controllers between them. Left and right slide player
## one's controller under a team, up and down go through the league's teams on
## that side, (A) starts the match as that team and (B) goes back. The second
## controller only sits there: the CPU plays the other team.

## The person starts as this team: 0 the left one (home), 1 the right one (away).
signal chosen(team: int)
signal cancelled
## The controller went from one place to another, or a side got another team.
signal moved
## The controller went to another side, and the team on its side changed.
signal side_changed
signal team_changed

const SCRIM_COLOR: Color = Color(0.02, 0.04, 0.1, 0.72)
const PANEL_COLOR: Color = Color(0.04, 0.08, 0.2, 0.94)
const SLOT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.07)
const CPU_COLOR: Color = Color(0.5, 0.54, 0.62)
const BAR_BACK: Color = Color(1.0, 1.0, 1.0, 0.12)
const BOARD_SIZE: Vector2 = Vector2(1000.0, 400.0)
const PANEL_SIZE: Vector2 = Vector2(360.0, 400.0)
## The team's ratings under its name: where the first row is, how far in from
## the panel's sides, and the height of a row.
const RATINGS_TOP: float = 152.0
const RATINGS_INSET: float = 22.0
const RATING_ROW: float = 20.0
const RATING_COUNT: int = 4
const ICON_SIZE: Vector2 = Vector2(104.0, 60.0)
## Middle of the left panel, of the board and of the right panel.
const SLOT_X: Array[float] = [180.0, 500.0, 820.0]
## Player one's row and player two's.
const ROW_Y: Array[float] = [275.0, 352.0]
const SLIDE_TIME: float = 0.14

## Where player one's controller is: -1 the left team, 0 the middle, 1 the right team.
var side: int = 0
## The team on the left and the one on the right, as places in the league's
## teams. Never the same one twice.
var picks: Array[int] = [0, 1]
## Per panel: the bars of its team's ratings (see Roster.team_ratings()).
var rating_bars: Array[Array] = []

var _font: SystemFont
var _teams: Array[TeamData] = []
var _panels: Array[Panel] = []
var _styles: Array[StyleBoxFlat] = []
## Per panel: the block in the team's colour and what is written on and under it.
var _fills: Array[StyleBoxFlat] = []
var _short_labels: Array[Label] = []
var _name_labels: Array[Label] = []
## Per panel: the name and the number beside each rating bar, and what the
## bars are filled with.
var _rating_names: Array[Array] = []
var _rating_numbers: Array[Array] = []
var _bar_fills: Array[StyleBoxFlat] = []
var _icon: ControllerIcon
var _choose_hint: Label
var _start_hint: Label
var _slide: Tween
var _nudge: Tween
## A team is chosen and the match is on its way: nothing more to press.
var _done: bool = false


## `teams` is every team there is to pick. The first two start on the left
## and on the right.
func setup(font: SystemFont, teams: Array[TeamData]) -> void:
	_font = font
	_teams = teams
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var scrim: ColorRect = ColorRect.new()
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 26)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var header: Label = _label("CHOOSE YOUR TEAM", 58, Color.WHITE, 12)
	column.add_child(header)
	column.add_child(_build_board())
	column.add_child(_build_hints())


## Shows the screen with the controller back in the middle.
func open() -> void:
	_done = false
	side = 0
	visible = true
	_refresh(false)


## Fades the screen out; it takes no more input meanwhile.
func close() -> void:
	_done = true
	ScreenFade.pop(self, false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _done:
		return
	if _pressed(event, &"ui_left"):
		_step(-1)
	elif _pressed(event, &"ui_right"):
		_step(1)
	elif _pressed(event, &"ui_up"):
		_cycle(-1)
	elif _pressed(event, &"ui_down"):
		_cycle(1)
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		_confirm()
	elif event.is_action_pressed(&"back") or event.is_action_pressed(&"ui_cancel"):
		cancelled.emit()
	else:
		return
	get_viewport().set_input_as_handled()


## A stick held over sends one event after another: only the first one counts.
func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action):
		return false
	return not event is InputEventJoypadMotion or Input.is_action_just_pressed(action)


func _step(by: int) -> void:
	_move_to(clampi(side + by, -1, 1))


func _move_to(to: int) -> void:
	if to == side:
		return
	side = to
	_refresh(true)
	moved.emit()
	side_changed.emit()


## The next team (`by` +1) or the one before (-1) on the side the controller
## is under, passing over the one the other side has.
func _cycle(by: int) -> void:
	if side == 0:
		_flash_choose_hint()
		return
	if _teams.size() < 3:
		return
	var index: int = 0 if side < 0 else 1
	var to: int = posmod(picks[index] + by, _teams.size())
	if to == picks[1 - index]:
		to = posmod(to + by, _teams.size())
	picks[index] = to
	_refresh(false)
	moved.emit()
	team_changed.emit()


## Nothing to start or to change in the middle: the hint to pick a side flashes.
func _flash_choose_hint() -> void:
	if _nudge != null:
		_nudge.kill()
	_choose_hint.modulate = MainMenu.GOLD
	_nudge = create_tween()
	_nudge.tween_property(_choose_hint, ^"modulate", Color.WHITE, 0.4)


func _confirm() -> void:
	if side == 0:
		_flash_choose_hint()
		return
	_done = true
	chosen.emit(0 if side < 0 else 1)


## The mouse: a click on a team moves the controller there, a second one
## starts, and the wheel over the team the controller is under changes it.
func _on_panel_input(event: InputEvent, to: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or _done:
		return
	if click.button_index == MOUSE_BUTTON_WHEEL_UP or click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if side == to:
			_cycle(-1 if click.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	if side == to:
		_confirm()
	else:
		_move_to(to)


func _refresh(animated: bool) -> void:
	for i: int in _panels.size():
		var mine: bool = side == (-1 if i == 0 else 1)
		var team: TeamData = _teams[picks[i]]
		var color: Color = team.team_color
		_fills[i].bg_color = color
		_short_labels[i].text = team.short_name
		_name_labels[i].text = team.team_name.to_upper()
		# A dark team colour would not show against the panel.
		_bar_fills[i].bg_color = color.lightened(0.4) if color.get_luminance() < 0.3 else color
		var ratings: Array[Array] = team.roster.team_ratings() if team.roster != null else []
		for row: int in RATING_COUNT:
			var value: int = ratings[row][1] if row < ratings.size() else 0
			var bar: ProgressBar = rating_bars[i][row]
			var name_label: Label = _rating_names[i][row]
			var number_label: Label = _rating_numbers[i][row]
			bar.value = value
			name_label.text = ratings[row][0] if row < ratings.size() else ""
			number_label.text = str(value)
		_styles[i].border_color = Color.WHITE if mine else color
		_styles[i].set_border_width_all(5 if mine else 3)
		_panels[i].modulate = Color.WHITE if mine or side == 0 else Color(0.5, 0.5, 0.5)
	_start_hint.modulate.a = 0.35 if side == 0 else 1.0

	var x: float = SLOT_X[side + 1] - ICON_SIZE.x * 0.5
	if _slide != null:
		_slide.kill()
	if animated:
		_slide = create_tween()
		_slide.tween_property(_icon, ^"position:x", x, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_icon.position.x = x


# --- Building blocks -----------------------------------------------------------------

func _build_board() -> Control:
	var board: Control = Control.new()
	board.custom_minimum_size = BOARD_SIZE
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in 2:
		var panel: Panel = _team_panel(i)
		panel.position = Vector2(0.0 if i == 0 else BOARD_SIZE.x - PANEL_SIZE.x, 0.0)
		board.add_child(panel)

	var versus: Label = _label("VS", 72, MainMenu.GOLD, 12)
	versus.position = Vector2(PANEL_SIZE.x, 30.0)
	versus.size = Vector2(BOARD_SIZE.x - PANEL_SIZE.x * 2.0, 100.0)
	board.add_child(versus)

	# A place for each controller under each team and in the middle.
	for x: float in SLOT_X:
		for y: float in ROW_Y:
			var slot: Panel = Panel.new()
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = SLOT_COLOR
			style.set_corner_radius_all(14)
			slot.add_theme_stylebox_override(&"panel", style)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.size = ICON_SIZE + Vector2(20.0, 10.0)
			slot.position = Vector2(x, y) - slot.size * 0.5
			board.add_child(slot)

	_icon = _controller("P1", MainMenu.BUTTON_BORDER, 0)
	board.add_child(_icon)
	# Player two stays in the middle for now: the CPU plays the other team.
	board.add_child(_controller("CPU", CPU_COLOR, 1))
	return board


## The panel of one side. _refresh() fills in whichever team that side has.
func _team_panel(index: int) -> Panel:
	var panel: Panel = Panel.new()
	panel.size = PANEL_SIZE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.gui_input.connect(_on_panel_input.bind(-1 if index == 0 else 1))
	_panels.append(panel)
	_styles.append(style)

	var block: Panel = Panel.new()
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.set_corner_radius_all(8)
	block.add_theme_stylebox_override(&"panel", fill)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.position = Vector2(14.0, 14.0)
	block.size = Vector2(PANEL_SIZE.x - 28.0, 100.0)
	panel.add_child(block)
	var short_label: Label = _label("", 62, Color.WHITE, 12)
	short_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	block.add_child(short_label)

	var name_label: Label = _label("", 24, Color(0.86, 0.9, 1.0), 0)
	name_label.position = Vector2(0.0, 115.0)
	name_label.size = Vector2(PANEL_SIZE.x, 30.0)
	panel.add_child(name_label)
	_fills.append(fill)
	_short_labels.append(short_label)
	_name_labels.append(name_label)
	_build_ratings(panel)
	return panel


## A row for each of the team's ratings: what it is, a bar and the number.
func _build_ratings(panel: Panel) -> void:
	var bar_fill: StyleBoxFlat = StyleBoxFlat.new()
	bar_fill.set_corner_radius_all(3)
	var bar_back: StyleBoxFlat = StyleBoxFlat.new()
	bar_back.bg_color = BAR_BACK
	bar_back.set_corner_radius_all(3)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.position = Vector2(RATINGS_INSET, RATINGS_TOP)
	rows.size = Vector2(PANEL_SIZE.x - RATINGS_INSET * 2.0, RATING_ROW * float(RATING_COUNT))
	panel.add_child(rows)
	var bars: Array[ProgressBar] = []
	var names: Array[Label] = []
	var numbers: Array[Label] = []
	for row: int in RATING_COUNT:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 10)
		line.custom_minimum_size.y = RATING_ROW
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(line)
		var name_label: Label = _label("", 15, Color(0.86, 0.9, 1.0), 0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.custom_minimum_size.x = 84.0
		line.add_child(name_label)
		var bar: ProgressBar = ProgressBar.new()
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override(&"background", bar_back)
		bar.add_theme_stylebox_override(&"fill", bar_fill)
		line.add_child(bar)
		var number_label: Label = _label("", 16, Color.WHITE, 0)
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number_label.custom_minimum_size.x = 28.0
		line.add_child(number_label)
		bars.append(bar)
		names.append(name_label)
		numbers.append(number_label)
	rating_bars.append(bars)
	_rating_names.append(names)
	_rating_numbers.append(numbers)
	_bar_fills.append(bar_fill)


func _controller(tag: String, tint: Color, row: int) -> ControllerIcon:
	var icon: ControllerIcon = ControllerIcon.new()
	icon.tag = tag
	icon.tint = tint
	icon.font = _font
	icon.size = ICON_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(SLOT_X[1], ROW_Y[row]) - ICON_SIZE * 0.5
	return icon


func _build_hints() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 44)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choose_hint = _label("LEFT / RIGHT  CHOOSE SIDE", 22, Color.WHITE, 6)
	_start_hint = _label("(A)  START", 22, Color.WHITE, 6)
	row.add_child(_choose_hint)
	row.add_child(_label("UP / DOWN  CHANGE TEAM", 22, Color.WHITE, 6))
	row.add_child(_start_hint)
	row.add_child(_label("(B)  BACK", 22, Color.WHITE, 6))
	return row


func _label(text: String, font_size: int, color: Color, outline: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	if outline > 0:
		label.add_theme_color_override(&"font_outline_color", MainMenu.OUTLINE)
		label.add_theme_constant_override(&"outline_size", outline)
	return label


## A gamepad drawn from a few shapes, with whose it is written across it.
class ControllerIcon:
	extends Control

	var tag: String = ""
	var tint: Color = Color.WHITE
	var font: Font

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var dark: Color = MainMenu.OUTLINE
		# The outline first, a little bigger, then the pad itself over it.
		for pass_index: int in 2:
			var grow: float = 3.0 if pass_index == 0 else 0.0
			var color: Color = dark if pass_index == 0 else tint
			var body: StyleBoxFlat = StyleBoxFlat.new()
			body.bg_color = color
			body.set_corner_radius_all(int(h * 0.3 + grow))
			draw_style_box(body, Rect2(0.0, 0.0, w, h * 0.72).grow(grow))
			for grip_x: float in [w * 0.17, w * 0.83]:
				draw_circle(Vector2(grip_x, h * 0.66), h * 0.33 + grow, color)
		# The cross on the left and the four buttons on the right.
		var cross: Vector2 = Vector2(w * 0.17, h * 0.36)
		var arm: float = h * 0.17
		draw_rect(Rect2(cross.x - arm, cross.y - arm * 0.33, arm * 2.0, arm * 0.66), dark)
		draw_rect(Rect2(cross.x - arm * 0.33, cross.y - arm, arm * 0.66, arm * 2.0), dark)
		var buttons: Vector2 = Vector2(w * 0.83, h * 0.36)
		for offset: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_circle(buttons + offset * h * 0.13, h * 0.065, dark)
		const TAG_SIZE: int = 24
		draw_string(font, Vector2(0.0, h * 0.36 + TAG_SIZE * 0.36), tag, HORIZONTAL_ALIGNMENT_CENTER, w, TAG_SIZE, dark)
