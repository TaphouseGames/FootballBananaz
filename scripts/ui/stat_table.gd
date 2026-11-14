class_name StatTable
extends RefCounted
## The pieces the tables of numbers are built from: the pause menu's box score
## and the season's standings and stats share them.

const GOLD: Color = Color(1.0, 0.85, 0.1)
const TEXT: Color = Color(0.86, 0.88, 0.86)
const DIM_TEXT: Color = Color(0.6, 0.64, 0.62)
const ROW_COLOR: Color = Color(1.0, 1.0, 1.0, 0.05)
const HEAD_COLOR: Color = Color(1.0, 1.0, 1.0, 0.12)
const CLEAR: Color = Color(0.0, 0.0, 0.0, 0.0)
## Width of a number column and of the name column.
const STAT_WIDTH: float = 56.0
const NAME_WIDTH: float = 150.0


static func label(text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var made: Label = Label.new()
	made.text = text
	made.horizontal_alignment = align
	made.add_theme_font_size_override(&"font_size", font_size)
	made.add_theme_color_override(&"font_color", color)
	return made


static func spacer(height: float) -> Control:
	var made: Control = Control.new()
	made.custom_minimum_size.y = height
	return made


static func flat(fill: Color, margin_x: float, margin_y: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	return style


## One line of a table: the name on the left, the numbers in columns of the
## same width on the right.
static func row(cells: PackedStringArray, fill: Color, color: Color, font_size: int, stat_width: float = STAT_WIDTH, name_width: float = NAME_WIDTH) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", flat(fill, 6.0, 1.0))
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 0)
	panel.add_child(line)
	for i: int in cells.size():
		var cell: Label = label(cells[i], font_size, color, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
		if i == 0:
			cell.custom_minimum_size.x = name_width
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.clip_text = true
		else:
			cell.custom_minimum_size.x = stat_width
		line.add_child(cell)
	return panel


## A whole table into `column`: its heading in `tint`, the names of the
## columns, then the rows turn about light and dark. `strong` rows (by their
## place) are written in white, `marked` ones in gold.
static func add(column: VBoxContainer, heading: String, tint: Color, head: PackedStringArray, rows: Array[PackedStringArray], strong: Array[int] = [], marked: Array[int] = [], stat_width: float = STAT_WIDTH, name_width: float = NAME_WIDTH) -> void:
	if column.get_child_count() > 0:
		column.add_child(spacer(8.0))
	if heading != "":
		column.add_child(label(heading, 19, tint))
	column.add_child(row(head, HEAD_COLOR, DIM_TEXT, 13, stat_width, name_width))
	for i: int in rows.size():
		var color: Color = GOLD if marked.has(i) else (Color.WHITE if strong.has(i) else TEXT)
		column.add_child(row(rows[i], ROW_COLOR if i % 2 == 1 else CLEAR, color, 15, stat_width, name_width))
