class_name HotRouteMenu
extends PanelContainer
## The hot-route panel at the line of scrimmage, in the corner the audible
## menu uses and drawn the same way: a title bar, the two sticks each with the
## route every direction gives, and what the left trigger does (held, it shows
## a route before it is called; by itself it leaves). Every route is a small
## drawing with its name under it, on the side of the stick that calls it, and
## the ones that break toward the ball are drawn for the man who was picked.
## Until a receiver is picked the sticks are dim and the line under the title
## asks for one. PreSnapState drives it.

## One route's box and the drawing in it.
const CELL_WIDTH: float = 41.0
const ICON_HEIGHT: float = 34.0
const STICK_SIZE: float = 32.0
## Yards up the field a drawing shows: a deeper route is cut at the top.
const ICON_DEPTH: float = 15.0
## Room left round a route in its drawing, for the dot and the arrowhead.
const ICON_PAD: float = 5.0
## The routes on each stick: its name, then up, left, right and down, each a
## name, the route and the way it breaks on screen (0: toward the ball, or not
## at all).
const WHEELS: Array[Array] = [
	["LS",
		["Streak", OffenseAssignment.Hot.STREAK, 0],
		["Slant", OffenseAssignment.Hot.SLANT, -1],
		["Slant", OffenseAssignment.Hot.SLANT, 1],
		["Curl", OffenseAssignment.Hot.CURL, 0]],
	["RS",
		["Post", OffenseAssignment.Hot.POST, 0],
		["Out", OffenseAssignment.Hot.OUT, -1],
		["Out", OffenseAssignment.Hot.OUT, 1],
		["Drag", OffenseAssignment.Hot.DRAG, 0]],
]

var _title: Label
var _prompt: Label
var _buttons: HBoxContainer
var _wheels: HBoxContainer
var _icons: Array[RouteIcon] = []
## The frame of every route's box, by its route and the way it breaks (see _key).
var _frames: Dictionary[int, StyleBoxFlat] = {}


## A small drawing of one route: a dot where the man lines up, his path up the
## field, and an arrowhead (or a bar, where he stops).
class RouteIcon extends Control:
	var kind: OffenseAssignment.Hot = OffenseAssignment.Hot.STREAK
	## The way a slant or an out breaks on screen: -1 left, 1 right.
	var way: float = 0.0
	## The side of the screen the ball is on from the man, for the routes that
	## break toward it.
	var inside: float = 1.0

	func _init(p_kind: OffenseAssignment.Hot, p_way: float) -> void:
		kind = p_kind
		way = p_way
		custom_minimum_size = Vector2(0.0, HotRouteMenu.ICON_HEIGHT)
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# The route itself, for a man lined up on the far side of the ball from
		# `inside`, in a frame whose lateral axis is the screen's.
		var drawn: OffenseAssignment = OffenseAssignment.new()
		drawn.start = Vector2(0.0, -inside * 10.0)
		var hot: OffenseAssignment = OffenseAssignment.hot_route(drawn, kind, way)
		var yards: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
		var previous: Vector2 = Vector2.ZERO
		for waypoint: Vector2 in hot.route:
			var point: Vector2 = waypoint
			if point.x > HotRouteMenu.ICON_DEPTH and previous.x < HotRouteMenu.ICON_DEPTH:
				yards.append(previous.lerp(point, (HotRouteMenu.ICON_DEPTH - previous.x) / (point.x - previous.x)))
				break
			yards.append(point)
			previous = point
		# Every drawing to the same scale, and each centred on its own width.
		var pad: float = HotRouteMenu.ICON_PAD
		var scale_px: float = (size.y - pad * 2.0) / HotRouteMenu.ICON_DEPTH
		var low: float = 0.0
		var high: float = 0.0
		for point: Vector2 in yards:
			low = minf(low, point.y)
			high = maxf(high, point.y)
		var origin: Vector2 = Vector2(size.x * 0.5 - (low + high) * 0.5 * scale_px, size.y - pad)
		var points: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in yards:
			points.append(origin + Vector2(point.y, -point.x) * scale_px)
		var color: Color = PlayDiagram.ROUTE_COLOR
		draw_polyline(points, color, 2.0, true)
		draw_circle(points[0], 3.0, color, true, -1.0, true)
		var tip: Vector2 = points[points.size() - 1]
		var dir: Vector2 = (tip - points[points.size() - 2]).normalized()
		var across: Vector2 = dir.orthogonal()
		if hot.settle:
			draw_line(tip - across * 4.0, tip + across * 4.0, color, 2.0, true)
		else:
			draw_colored_polygon(PackedVector2Array([tip + dir * 3.0, tip - dir * 4.0 + across * 3.5, tip - dir * 4.0 - across * 3.5]), color)


## In the bottom right corner instead (see AudibleMenu.on_right).
var on_right: bool = false


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
	var bar_row: HBoxContainer = HBoxContainer.new()
	bar_row.add_theme_constant_override(&"separation", 6)
	bar.add_child(bar_row)
	_title = AudibleMenu.text_label(16, Color.WHITE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	bar_row.add_child(_title)
	# How to leave, in the bar as the audible menu has it.
	bar_row.add_child(_key("LT"))
	var close: Label = AudibleMenu.text_label(14, AudibleMenu.TEXT_COLOR)
	close.text = "Cancel"
	bar_row.add_child(close)

	var margin: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	stack.add_child(margin)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 5)
	margin.add_child(body)

	# What to do next, with the receivers' buttons while one is still to be picked.
	var ask: HBoxContainer = HBoxContainer.new()
	ask.alignment = BoxContainer.ALIGNMENT_CENTER
	ask.add_theme_constant_override(&"separation", 8)
	ask.custom_minimum_size = Vector2(0.0, 22.0)
	body.add_child(ask)
	_prompt = AudibleMenu.text_label(14, AudibleMenu.LIT_COLOR)
	ask.add_child(_prompt)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 4)
	for slot: int in HumanController.PAD_LABELS.size():
		_buttons.add_child(AudibleMenu.badge(HumanController.PAD_LABELS[slot], HumanController.PAD_COLORS[slot]))
	ask.add_child(_buttons)

	_wheels = HBoxContainer.new()
	_wheels.alignment = BoxContainer.ALIGNMENT_CENTER
	_wheels.add_theme_constant_override(&"separation", 6)
	body.add_child(_wheels)
	for wheel: Array in WHEELS:
		_wheels.add_child(_wheel(wheel))

	# What the trigger does held.
	var foot: HBoxContainer = HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override(&"separation", 6)
	body.add_child(foot)
	foot.add_child(_key("LT"))
	var what: Label = AudibleMenu.text_label(13, AudibleMenu.TEXT_COLOR)
	what.text = "Hold: preview, let go to call"
	foot.add_child(what)


## `receiver`: the picked man's button and position ("(X) WR"), or nothing
## while one is still to be picked. `inside`: the side of the screen the ball
## is on from him (-1 left, 1 right), the way his curl, post and drag turn.
func show_for(receiver: String, inside: float = 1.0) -> void:
	var picked: bool = receiver != ""
	_title.text = ("%s HOT ROUTE" % receiver) if picked else "HOT ROUTE"
	_prompt.text = "Push a stick for his route" if picked else "Pick a receiver"
	_buttons.visible = not picked
	_wheels.modulate.a = 1.0 if picked else 0.4
	for icon: RouteIcon in _icons:
		icon.inside = inside
		icon.queue_redraw()
	light(-1, 0)
	AudibleMenu.to_corner(self, on_right)


## Lights the box of the route being shown on the field: route `kind` (an
## OffenseAssignment.Hot) breaking `way` on screen (-1, 0 or 1). A `kind` of
## -1 lights none.
func light(kind: int, way: int) -> void:
	var lit: int = _key_of(kind, way) if kind >= 0 else -1
	for key: int in _frames:
		_frames[key].border_color = AudibleMenu.LIT_COLOR if key == lit else Color(0.0, 0.0, 0.0, 0.0)
		_frames[key].bg_color = AudibleMenu.ROW_COLOR.lightened(0.12) if key == lit else AudibleMenu.ROW_COLOR


static func _key_of(kind: int, way: int) -> int:
	return kind * 3 + way + 1


## One stick with the route of each direction on that side of it.
func _wheel(wheel: Array) -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 2)
	grid.add_theme_constant_override(&"v_separation", 2)
	# Up, left, the stick, right, down: the cells of a cross.
	var cells: Array = [null, wheel[1], null, wheel[2], wheel[0], wheel[3], null, wheel[4], null]
	for cell: Variant in cells:
		if cell == null:
			var gap: Control = Control.new()
			gap.custom_minimum_size = Vector2(CELL_WIDTH, 0.0)
			grid.add_child(gap)
		elif cell is String:
			grid.add_child(_stick(cell))
		else:
			grid.add_child(_route(cell[0], cell[1], cell[2]))
	return grid


## One route's box: its drawing over its name.
func _route(text: String, kind: OffenseAssignment.Hot, way: int) -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(CELL_WIDTH, 0.0)
	var style: StyleBoxFlat = AudibleMenu.box(AudibleMenu.ROW_COLOR, 4)
	style.set_border_width_all(1)
	style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_content_margin_all(2.0)
	frame.add_theme_stylebox_override(&"panel", style)
	_frames[_key_of(kind, way)] = style
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	frame.add_child(column)
	var screen: PanelContainer = PanelContainer.new()
	screen.add_theme_stylebox_override(&"panel", AudibleMenu.box(AudibleMenu.SCREEN_COLOR, 3))
	column.add_child(screen)
	var icon: RouteIcon = RouteIcon.new(kind, float(way))
	screen.add_child(icon)
	_icons.append(icon)
	var label: Label = AudibleMenu.text_label(11, AudibleMenu.TEXT_COLOR)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	column.add_child(label)
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
	var label: Label = AudibleMenu.text_label(14, Color.WHITE)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(label)
	holder.add_child(disc)
	return holder


## A trigger: its name on a grey key.
func _key(text: String) -> Control:
	var key: PanelContainer = PanelContainer.new()
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = AudibleMenu.box(AudibleMenu.KEY_COLOR, 4)
	style.border_color = AudibleMenu.EDGE_COLOR
	style.set_border_width_all(1)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	key.add_theme_stylebox_override(&"panel", style)
	var label: Label = AudibleMenu.text_label(13, Color.WHITE)
	label.text = text
	key.add_child(label)
	return key
