class_name AudibleMenu
extends PanelContainer
## The audible menu at the line of scrimmage: four plays, one on each way the
## left stick can be pushed, each in a small box with its name and its drawing
## beside the arrow that calls it: up on top, left and right side by side, down
## below. It sits in the bottom left corner of the screen, narrow enough to fit
## beside the scoreboard, so the players stay in view. PreSnapState drives it.

## How far in from the left edge of the screen and up from the bottom the
## panels at the line sit (this one and HotRouteMenu).
const MENU_CORNER: Vector2 = Vector2(10.0, 10.0)
## One play's box, and the drawing in it.
const BOX_WIDTH: float = 128.0
const DIAGRAM_HEIGHT: float = 54.0
const ARROW_SIZE: float = 10.0
## How much of a box is left to see when its play is the one that is on.
const CALLED_ALPHA: float = 0.4
const BACK_COLOR: Color = Color(0.04, 0.07, 0.11, 0.88)
const EDGE_COLOR: Color = Color(0.62, 0.7, 0.78, 0.9)
const TITLE_COLOR: Color = Color(0.1, 0.16, 0.24, 0.98)
const ROW_COLOR: Color = Color(0.13, 0.19, 0.27, 0.92)
const ROW_ALT_COLOR: Color = Color(0.1, 0.15, 0.22, 0.92)
const SCREEN_COLOR: Color = Color(0.05, 0.12, 0.09, 0.95)
const LIT_COLOR: Color = Color(0.96, 0.62, 0.1)
const TEXT_COLOR: Color = Color(0.9, 0.93, 0.96)
const KEY_COLOR: Color = Color(0.3, 0.33, 0.38)
## The ways of the stick in the order of the plays: up, left, right, down.
const WAYS: Array[Vector2] = [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]

var _boxes: Array[PanelContainer] = []
var _names: Array[Label] = []
var _diagrams: Array[PlayDiagram] = []


## A small arrowhead pointing the way the stick is pushed.
class Arrow extends Control:
	var way: Vector2 = Vector2.UP

	func _init(p_way: Vector2) -> void:
		way = p_way
		custom_minimum_size = Vector2(AudibleMenu.ARROW_SIZE, AudibleMenu.ARROW_SIZE)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var middle: Vector2 = size * 0.5
		var reach: float = minf(size.x, size.y) * 0.5
		var across: Vector2 = Vector2(-way.y, way.x)
		draw_colored_polygon(PackedVector2Array([
			middle + way * reach,
			middle - way * reach * 0.7 + across * reach,
			middle - way * reach * 0.7 - across * reach,
		]), AudibleMenu.LIT_COLOR)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_top = 1.0
	anchor_bottom = 1.0
	var frame: StyleBoxFlat = box(BACK_COLOR, 4)
	frame.border_color = EDGE_COLOR
	frame.set_border_width_all(1)
	frame.set_content_margin_all(1.0)
	add_theme_stylebox_override(&"panel", frame)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 0)
	add_child(stack)

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
	bar_row.add_theme_constant_override(&"separation", 6)
	# The stick the arrows are of.
	bar_row.add_child(badge("LS", KEY_COLOR))
	var title: Label = text_label(17, Color.WHITE)
	title.text = "AUDIBLE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(title)
	# How to leave, in the bar: under the plays it would cost a row of field.
	bar_row.add_child(badge("B", HumanController.PAD_COLORS[2]))
	var close: Label = text_label(14, TEXT_COLOR)
	close.text = "Close"
	bar_row.add_child(close)

	var margin: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	stack.add_child(margin)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	margin.add_child(rows)
	# Up by itself, left and right beside each other, down by itself.
	var top: CenterContainer = CenterContainer.new()
	top.add_child(_make_box(WAYS[0]))
	rows.add_child(top)
	var middle: HBoxContainer = HBoxContainer.new()
	middle.add_theme_constant_override(&"separation", 4)
	middle.add_child(_make_box(WAYS[1]))
	middle.add_child(_make_box(WAYS[2]))
	rows.add_child(middle)
	var bottom: CenterContainer = CenterContainer.new()
	bottom.add_child(_make_box(WAYS[3]))
	rows.add_child(bottom)


## One play's box: the arrow and the play's name over its drawing.
func _make_box(way: Vector2) -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(BOX_WIDTH, 0.0)
	var style: StyleBoxFlat = box(ROW_COLOR, 4)
	style.set_content_margin_all(3.0)
	frame.add_theme_stylebox_override(&"panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 1)
	frame.add_child(column)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 5)
	column.add_child(head)
	head.add_child(Arrow.new(way))
	var name_label: Label = text_label(13, TEXT_COLOR)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	head.add_child(name_label)
	var screen: PanelContainer = PanelContainer.new()
	var screen_style: StyleBoxFlat = box(SCREEN_COLOR, 3)
	screen_style.set_content_margin_all(2.0)
	screen.add_theme_stylebox_override(&"panel", screen_style)
	column.add_child(screen)
	var diagram: PlayDiagram = PlayDiagram.new()
	diagram.custom_minimum_size = Vector2(0.0, DIAGRAM_HEIGHT)
	screen.add_child(diagram)
	_boxes.append(frame)
	_names.append(name_label)
	_diagrams.append(diagram)
	return frame


## `plays`: the OffensePlay or DefensePlay resources on up, left, right and
## down. `flipped`: drawn mirrored, as the play they are called in place of is.
## `called` is that play: its own box, when it has one, is dimmed.
func show_plays(plays: Array[Resource], flipped: bool, called: Resource) -> void:
	for i: int in _boxes.size():
		var play: Resource = plays[i] if i < plays.size() else null
		_boxes[i].visible = play != null
		if play == null:
			continue
		_boxes[i].modulate.a = CALLED_ALPHA if play == called else 1.0
		if play is OffensePlay:
			_names[i].text = (play as OffensePlay).play_name
			_diagrams[i].show_offense(play as OffensePlay)
		else:
			_names[i].text = (play as DefensePlay).play_name
			_diagrams[i].show_defense(play as DefensePlay)
		_diagrams[i].set_flipped(flipped)
	var needed: Vector2 = get_combined_minimum_size()
	offset_left = MENU_CORNER.x
	offset_right = MENU_CORNER.x + needed.x
	offset_bottom = -MENU_CORNER.y
	offset_top = -MENU_CORNER.y - needed.y


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
