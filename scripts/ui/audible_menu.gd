class_name AudibleMenu
extends PanelContainer
## The audible menu at the line of scrimmage: a title bar with the formation
## (on defense, the tab) between the bumpers that change it, its plays as rows with the highlighted one lit, and
## beside them that play's drawing over the buttons. The field stays in view.
## PreSnapState drives it.

## Plays in a column before a second one is started.
const COLUMN_ROWS: int = 6
## How far in from the left edge of the screen and up from the bottom it sits.
const CORNER: Vector2 = Vector2(24.0, 124.0)
const ROW_SIZE: Vector2 = Vector2(196.0, 28.0)
const SIDE_WIDTH: float = 176.0
const DIAGRAM_HEIGHT: float = 118.0
const BACK_COLOR: Color = Color(0.04, 0.07, 0.11, 0.88)
const EDGE_COLOR: Color = Color(0.62, 0.7, 0.78, 0.9)
const TITLE_COLOR: Color = Color(0.1, 0.16, 0.24, 0.98)
const ROW_COLOR: Color = Color(0.13, 0.19, 0.27, 0.92)
const ROW_ALT_COLOR: Color = Color(0.1, 0.15, 0.22, 0.92)
const LIT_COLOR: Color = Color(0.96, 0.62, 0.1)
const LIT_TEXT: Color = Color(0.08, 0.06, 0.02)
const TEXT_COLOR: Color = Color(0.9, 0.93, 0.96)
const DIM_COLOR: Color = Color(0.62, 0.68, 0.74)
## The buttons under the drawing: label, colour (HumanController.PAD_COLORS
## order is A, X, B, Y) and what it does.
const ACTIONS: Array[Array] = [["A", 0, "Call play"], ["X", 1, "Flip play"], ["B", 2, "Close"]]

var _title: Label
var _arrows: Array[Label] = []
var _flip_tag: Label
var _columns: HBoxContainer
var _diagram: PlayDiagram
var _plays: Array[Resource] = []
var _rows: Array[PanelContainer] = []
var _row_names: Array[Label] = []
var _row_styles: Array[StyleBoxFlat] = []
var _lit_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_top = 1.0
	anchor_bottom = 1.0
	var frame: StyleBoxFlat = box(BACK_COLOR, 4)
	frame.border_color = EDGE_COLOR
	frame.set_border_width_all(1)
	frame.set_content_margin_all(1.0)
	add_theme_stylebox_override(&"panel", frame)
	_lit_style = box(LIT_COLOR, 3)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 0)
	add_child(stack)

	# The title bar: < FORMATION >, and whether the play is mirrored.
	var bar: PanelContainer = PanelContainer.new()
	var bar_style: StyleBoxFlat = box(TITLE_COLOR, 0)
	bar_style.border_color = EDGE_COLOR
	bar_style.border_width_bottom = 1
	bar_style.content_margin_left = 10.0
	bar_style.content_margin_right = 10.0
	bar_style.content_margin_top = 3.0
	bar_style.content_margin_bottom = 4.0
	bar.add_theme_stylebox_override(&"panel", bar_style)
	stack.add_child(bar)
	var bar_row: HBoxContainer = HBoxContainer.new()
	bar.add_child(bar_row)
	for arrow: String in ["LB", "RB"]:
		var label: Label = text_label(15, LIT_COLOR)
		label.text = arrow
		_arrows.append(label)
	bar_row.add_child(_arrows[0])
	_title = text_label(18, Color.WHITE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_row.add_child(_title)
	bar_row.add_child(_arrows[1])

	var margin: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	stack.add_child(margin)
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	margin.add_child(body)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override(&"separation", 4)
	body.add_child(_columns)

	# Beside the plays: the highlighted one drawn, and the buttons.
	var side_column: VBoxContainer = VBoxContainer.new()
	side_column.custom_minimum_size = Vector2(SIDE_WIDTH, 0.0)
	side_column.add_theme_constant_override(&"separation", 4)
	body.add_child(side_column)
	var screen: PanelContainer = PanelContainer.new()
	var screen_style: StyleBoxFlat = box(Color(0.05, 0.12, 0.09, 0.95), 3)
	screen_style.set_content_margin_all(3.0)
	screen.add_theme_stylebox_override(&"panel", screen_style)
	side_column.add_child(screen)
	_diagram = PlayDiagram.new()
	_diagram.custom_minimum_size = Vector2(0.0, DIAGRAM_HEIGHT)
	screen.add_child(_diagram)
	_flip_tag = text_label(13, LIT_COLOR)
	_flip_tag.text = "FLIPPED"
	_flip_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_flip_tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_flip_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_flip_tag)
	for action: Array in ACTIONS:
		var line: PanelContainer = PanelContainer.new()
		var line_style: StyleBoxFlat = box(ROW_ALT_COLOR, 3)
		line_style.content_margin_left = 6.0
		line_style.content_margin_right = 6.0
		line_style.content_margin_top = 2.0
		line_style.content_margin_bottom = 2.0
		line.add_theme_stylebox_override(&"panel", line_style)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		line.add_child(row)
		row.add_child(badge(action[0], HumanController.PAD_COLORS[action[1]]))
		var what: Label = text_label(15, TEXT_COLOR)
		what.text = action[2]
		row.add_child(what)
		side_column.add_child(line)


## `plays`: the OffensePlay or DefensePlay resources of the open formation.
## `title` names it; `more` says there are others to the left and right.
func show_plays(title: String, more: bool, plays: Array[Resource], cursor: int, flipped: bool) -> void:
	_title.text = title
	for arrow: Label in _arrows:
		# Kept in place when there is nowhere to go, so the title stays centred.
		arrow.modulate.a = 1.0 if more else 0.0
	_plays.assign(plays)
	for old: Node in _columns.get_children():
		_columns.remove_child(old)
		old.queue_free()
	_rows.clear()
	_row_names.clear()
	_row_styles.clear()
	var column: VBoxContainer = null
	for i: int in plays.size():
		if i % COLUMN_ROWS == 0:
			column = VBoxContainer.new()
			column.add_theme_constant_override(&"separation", 2)
			_columns.add_child(column)
		var row: PanelContainer = PanelContainer.new()
		row.custom_minimum_size = ROW_SIZE
		var style: StyleBoxFlat = box(ROW_COLOR if i % 2 == 0 else ROW_ALT_COLOR, 3)
		var name_label: Label = text_label(16, TEXT_COLOR)
		name_label.text = _name_of(plays[i])
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		var inset: MarginContainer = MarginContainer.new()
		inset.add_theme_constant_override(&"margin_left", 10)
		inset.add_theme_constant_override(&"margin_right", 6)
		inset.add_child(name_label)
		row.add_child(inset)
		column.add_child(row)
		_rows.append(row)
		_row_names.append(name_label)
		_row_styles.append(style)
	# In the bottom left corner, over the hint line, and as big as this
	# formation's plays need: not left as wide as the last one.
	var needed: Vector2 = get_combined_minimum_size()
	offset_left = CORNER.x
	offset_right = CORNER.x + needed.x
	offset_bottom = -CORNER.y
	offset_top = -CORNER.y - needed.y
	set_flipped(flipped)
	set_cursor(cursor)


func set_cursor(index: int) -> void:
	for i: int in _rows.size():
		var selected: bool = i == index
		_rows[i].add_theme_stylebox_override(&"panel", _lit_style if selected else _row_styles[i])
		_row_names[i].add_theme_color_override(&"font_color", LIT_TEXT if selected else TEXT_COLOR)
		_row_names[i].add_theme_constant_override(&"outline_size", 0 if selected else 4)
	if index < 0 or index >= _plays.size():
		return
	if _plays[index] is OffensePlay:
		_diagram.show_offense(_plays[index] as OffensePlay)
	else:
		_diagram.show_defense(_plays[index] as DefensePlay)


func set_flipped(flipped: bool) -> void:
	_diagram.set_flipped(flipped)
	_flip_tag.visible = flipped


func _name_of(play: Resource) -> String:
	if play is OffensePlay:
		return (play as OffensePlay).play_name
	return (play as DefensePlay).play_name


## A gamepad button: its letter on a disc of its colour.
static func badge(text: String, color: Color) -> Control:
	var disc: PanelContainer = PanelContainer.new()
	disc.custom_minimum_size = Vector2(22.0, 22.0)
	var style: StyleBoxFlat = box(color.darkened(0.25), 11)
	style.border_color = color.lightened(0.3)
	style.set_border_width_all(1)
	disc.add_theme_stylebox_override(&"panel", style)
	var letter: Label = text_label(13, Color.WHITE)
	letter.text = text
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(letter)
	return disc


static func box(fill: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	return style


static func text_label(font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	return label
