class_name HalftimeCard
extends Control
## The halftime report, over the whole picture: the two teams and the score,
## and their numbers side by side. Jim and Tony are heard, not captioned.
## The HUD puts it up and calls finish() to take it away.

const BACKDROP: Color = Color(0.02, 0.04, 0.1, 0.9)
const PANEL_COLOR: Color = Color(0.04, 0.08, 0.2, 0.94)
const ROW_COLOR: Color = Color(1.0, 1.0, 1.0, 0.05)
const LABEL_COLOR: Color = Color(0.86, 0.9, 1.0)
const WIDTH: float = 900.0
const VALUE_WIDTH: float = 150.0
const BADGE_SIZE: float = 60.0
const MARGIN: float = 44.0

var game: Game

var _font: SystemFont
var _tween: Tween
var _finishing: bool = false


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = MainMenu.FONT_NAMES

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override(&"separation", 14)
	center.add_child(column)

	var title: PanelContainer = PanelContainer.new()
	title.add_theme_stylebox_override(&"panel", _flat(MainMenu.GOLD, MainMenu.GOLD, 0, 18.0, 2.0))
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.add_child(_label("HALFTIME REPORT", 24, MainMenu.OUTLINE))
	column.add_child(title)
	column.add_child(_build_score())
	column.add_child(_build_stats())
	_build_skip()

	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", 1.0, 0.35)


## Fades the card out and removes it.
func finish() -> void:
	if _finishing:
		return
	_finishing = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", 0.0, 0.25)
	_tween.tween_callback(queue_free)


# --- Building blocks -----------------------------------------------------------------

## Badge, name and score of the home team, and the away team's the other way round.
func _build_score() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 16)
	var home: Team = game.home
	var away: Team = game.away
	row.add_child(_badge(home))
	row.add_child(_team_name(home, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_label(str(home.score), 64, Color.WHITE))
	row.add_child(_label("-", 40, MainMenu.BUTTON_BORDER))
	row.add_child(_label(str(away.score), 64, Color.WHITE))
	row.add_child(_team_name(away, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_badge(away))
	return row


func _team_name(team: Team, align: HorizontalAlignment) -> Label:
	var label: Label = _label(team.team_name.to_upper(), 30, _tint(team))
	label.horizontal_alignment = align
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## The team's colours stand in for a logo: a disc of its colour with its initial.
func _badge(team: Team) -> Control:
	var disc: PanelContainer = PanelContainer.new()
	disc.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = team.team_color
	style.border_color = Color.WHITE
	style.set_border_width_all(3)
	style.set_corner_radius_all(int(BADGE_SIZE * 0.5))
	disc.add_theme_stylebox_override(&"panel", style)
	var dark: bool = team.team_color.get_luminance() > 0.55
	var initial: Label = _label(team.short_name.left(1).to_upper(), 34, MainMenu.OUTLINE if dark else Color.WHITE)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(initial)
	return disc


## The first half's numbers: home on the left, away on the right.
func _build_stats() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _flat(PANEL_COLOR, MainMenu.BUTTON_BORDER, 3, 18.0, 10.0))
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 3)
	panel.add_child(rows)
	var home: TeamLine = game.stat_book.team_line(game.home)
	var away: TeamLine = game.stat_book.team_line(game.away)
	var lines: Array[Array] = [
		["TOTAL YARDS", str(home.total_yds()), str(away.total_yds())],
		["PASSING", str(home.net_pass_yds()), str(away.net_pass_yds())],
		["RUSHING", str(home.rush_yds), str(away.rush_yds)],
		["FIRST DOWNS", str(home.first_downs()), str(away.first_downs())],
		["TURNOVERS", str(home.turnovers()), str(away.turnovers())],
		["POSSESSION", _clock(home.possession), _clock(away.possession)],
	]
	for i: int in lines.size():
		var strip: PanelContainer = PanelContainer.new()
		var fill: StyleBoxFlat = _flat(ROW_COLOR if i % 2 == 0 else Color.TRANSPARENT, Color.TRANSPARENT, 0, 10.0, 1.0)
		fill.set_corner_radius_all(4)
		strip.add_theme_stylebox_override(&"panel", fill)
		var row: HBoxContainer = HBoxContainer.new()
		strip.add_child(row)
		row.add_child(_value(lines[i][1], _tint(game.home)))
		var what: Label = _label(lines[i][0], 20, LABEL_COLOR)
		what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(what)
		row.add_child(_value(lines[i][2], _tint(game.away)))
		rows.add_child(strip)
	return panel


func _value(text: String, color: Color) -> Label:
	var label: Label = _label(text, 26, color)
	label.custom_minimum_size.x = VALUE_WIDTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Bottom right, out of the way.
func _build_skip() -> void:
	var skip: Label = _label("(A)  SKIP", 18, Color(1.0, 1.0, 1.0, 0.55))
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	skip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skip)
	skip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skip.offset_right = -MARGIN
	skip.offset_bottom = -22.0


func _tint(team: Team) -> Color:
	return team.team_color.lerp(Color.WHITE, 0.45)


func _clock(seconds: float) -> String:
	var whole: int = roundi(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [whole / 60, whole % 60]


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _flat(fill: Color, border: Color, border_width: int, margin_x: float = 16.0, margin_y: float = 6.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	return style
