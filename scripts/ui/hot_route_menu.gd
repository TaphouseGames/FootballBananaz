class_name HotRouteMenu
extends PanelContainer
## The hot-route panel at the line of scrimmage, in the corner the audible
## menu uses and drawn the same way: a title bar, the two sticks each with the
## route every direction gives, and the button that leaves. Until a receiver is
## picked the sticks are dim and the line under the title asks for one.
## PreSnapState drives it.

const WHEEL_CELL: Vector2 = Vector2(74.0, 26.0)
const STICK_SIZE: float = 46.0
## The routes on each stick: its name, then up, left, right and down.
const WHEELS: Array[Array] = [
	["LS", "Streak", "Slant", "Slant", "Curl"],
	["RS", "Post", "Out", "Out", "Drag"],
]

var _title: Label
var _prompt: Label
var _buttons: HBoxContainer
var _wheels: HBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_top = 1.0
	anchor_bottom = 1.0
	var frame: StyleBoxFlat = AudibleMenu.box(AudibleMenu.BACK_COLOR, 4)
	frame.border_color = AudibleMenu.EDGE_COLOR
	frame.set_border_width_all(1)
	frame.set_content_margin_all(1.0)
	add_theme_stylebox_override(&"panel", frame)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 0)
	add_child(stack)

	var bar: PanelContainer = PanelContainer.new()
	var bar_style: StyleBoxFlat = AudibleMenu.box(AudibleMenu.TITLE_COLOR, 0)
	bar_style.border_color = AudibleMenu.EDGE_COLOR
	bar_style.border_width_bottom = 1
	bar_style.content_margin_left = 10.0
	bar_style.content_margin_right = 10.0
	bar_style.content_margin_top = 3.0
	bar_style.content_margin_bottom = 4.0
	bar.add_theme_stylebox_override(&"panel", bar_style)
	stack.add_child(bar)
	_title = AudibleMenu.text_label(18, Color.WHITE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_title)

	var margin: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	stack.add_child(margin)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 6)
	margin.add_child(body)

	# What to do next, with the receivers' buttons while one is still to be picked.
	var ask: HBoxContainer = HBoxContainer.new()
	ask.alignment = BoxContainer.ALIGNMENT_CENTER
	ask.add_theme_constant_override(&"separation", 8)
	body.add_child(ask)
	_prompt = AudibleMenu.text_label(15, AudibleMenu.LIT_COLOR)
	ask.add_child(_prompt)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 4)
	for slot: int in HumanController.PAD_LABELS.size():
		_buttons.add_child(AudibleMenu.badge(HumanController.PAD_LABELS[slot], HumanController.PAD_COLORS[slot]))
	ask.add_child(_buttons)

	_wheels = HBoxContainer.new()
	_wheels.add_theme_constant_override(&"separation", 8)
	body.add_child(_wheels)
	for wheel: Array in WHEELS:
		_wheels.add_child(_wheel(wheel))

	var foot: PanelContainer = PanelContainer.new()
	var foot_style: StyleBoxFlat = AudibleMenu.box(AudibleMenu.ROW_ALT_COLOR, 3)
	foot_style.content_margin_left = 6.0
	foot_style.content_margin_right = 6.0
	foot_style.content_margin_top = 2.0
	foot_style.content_margin_bottom = 2.0
	foot.add_theme_stylebox_override(&"panel", foot_style)
	var foot_row: HBoxContainer = HBoxContainer.new()
	foot_row.add_theme_constant_override(&"separation", 8)
	foot.add_child(foot_row)
	foot_row.add_child(_key("LT"))
	var what: Label = AudibleMenu.text_label(15, AudibleMenu.TEXT_COLOR)
	what.text = "Cancel"
	foot_row.add_child(what)
	body.add_child(foot)


## `receiver`: the picked man's button and position ("(X) WR"), or nothing
## while one is still to be picked.
func show_for(receiver: String) -> void:
	var picked: bool = receiver != ""
	_title.text = ("%s HOT ROUTES" % receiver) if picked else "HOT ROUTES"
	_prompt.text = "Push a stick for his route" if picked else "Pick a receiver"
	_buttons.visible = not picked
	_wheels.modulate.a = 1.0 if picked else 0.4
	var needed: Vector2 = get_combined_minimum_size()
	offset_left = AudibleMenu.CORNER.x
	offset_right = AudibleMenu.CORNER.x + needed.x
	offset_bottom = -AudibleMenu.CORNER.y
	offset_top = -AudibleMenu.CORNER.y - needed.y


## One stick in a frame, the route of each direction on that side of it.
func _wheel(names: Array) -> Control:
	var frame: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = AudibleMenu.box(AudibleMenu.ROW_COLOR, 4)
	style.set_content_margin_all(6.0)
	frame.add_theme_stylebox_override(&"panel", style)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 2)
	frame.add_child(grid)
	# Up, left, the stick, right, down: the cells of a cross.
	var cells: Array =["", names[1], "", names[2], "*", names[3], "", names[4], ""]
	for i: int in cells.size():
		if cells[i] == "*":
			grid.add_child(_stick(names[0]))
			continue
		var label: Label = AudibleMenu.text_label(15, AudibleMenu.TEXT_COLOR)
		label.text = cells[i]
		label.custom_minimum_size = WHEEL_CELL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Each name sits against the stick.
		label.horizontal_alignment = [HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_LEFT][i % 3]
		grid.add_child(label)
	return frame


## The stick itself: a disc with its name on it.
func _stick(text: String) -> Control:
	var holder: CenterContainer = CenterContainer.new()
	var disc: PanelContainer = PanelContainer.new()
	disc.custom_minimum_size = Vector2(STICK_SIZE, STICK_SIZE)
	var style: StyleBoxFlat = AudibleMenu.box(Color(0.2, 0.23, 0.27), int(STICK_SIZE * 0.5))
	style.border_color = AudibleMenu.EDGE_COLOR
	style.set_border_width_all(2)
	disc.add_theme_stylebox_override(&"panel", style)
	var label: Label = AudibleMenu.text_label(17, Color.WHITE)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(label)
	holder.add_child(disc)
	return holder


## A trigger: its name on a grey key.
func _key(text: String) -> Control:
	var key: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = AudibleMenu.box(Color(0.3, 0.33, 0.38), 4)
	style.border_color = AudibleMenu.EDGE_COLOR
	style.set_border_width_all(1)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	key.add_theme_stylebox_override(&"panel", style)
	var label: Label = AudibleMenu.text_label(13, Color.WHITE)
	label.text = text
	key.add_child(label)
	return key
