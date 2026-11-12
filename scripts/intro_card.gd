class_name IntroCard
extends Control
## The television graphics over the pregame intro: black bars top and bottom,
## the show's badge, and a lower third with the matchup and a line of nonsense.
## The HUD puts it up and calls finish() to slide it away.

const SHOW_NAME: String = "BLUE 42 GAMEDAY"
## One of these goes under the matchup.
const TAGLINES: PackedStringArray = [
	"TWO TEAMS. ONE BALL. SEVERAL RULES.",
	"TONIGHT: POINTS, PROBABLY.",
	"EXPERTS AGREE: SOMEBODY COULD WIN THIS.",
	"LIVE FROM A FIELD.",
	"FOOTBALL: IT IS ON RIGHT NOW.",
	"THE ONLY GAME ON THIS CHANNEL.",
	"BROUGHT TO YOU BY GRASS.",
	"100 YARDS OF PURE RECTANGLE.",
	"WINNER GETS TO HAVE WON.",
	"KEYS TO THE GAME: HAVE THE BALL.",
	"EVERY POINT COUNTS. THAT IS HOW COUNTING WORKS.",
	"NO REFUNDS.",
]
const BAR_HEIGHT: float = 62.0
const MARGIN: float = 44.0
const PANEL_COLOR: Color = Color(0.04, 0.08, 0.2, 0.94)
const LIVE_COLOR: Color = Color(0.9, 0.12, 0.14)
const SLIDE: float = 900.0

static var _last_tagline: int = -1

var game: Game

var _font: SystemFont
var _black: ColorRect
var _top: ColorRect
var _bottom: ColorRect
## What slides in from the left.
var _left: Control
var _live_dot: Panel
var _tween: Tween
var _time: float = 0.0
var _finishing: bool = false


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = MainMenu.FONT_NAMES

	_top = _bar(Control.PRESET_TOP_WIDE)
	_bottom = _bar(Control.PRESET_BOTTOM_WIDE)
	_left = _layer()
	_build_badge()
	_build_lower_third()
	_build_skip()
	# Over everything: the picture comes up out of black.
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)

	_left.position.x = -SLIDE
	_tween = create_tween().set_parallel()
	_tween.tween_property(_black, ^"color:a", 0.0, 0.6)
	_tween.tween_property(_left, ^"position:x", 0.0, 0.55).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	_live_dot.modulate.a = 1.0 if fmod(_time, 1.0) < 0.6 else 0.25


## Slides everything off and removes the card.
func finish() -> void:
	if _finishing:
		return
	_finishing = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_property(_black, ^"color:a", 0.0, 0.15)
	_tween.tween_property(_left, ^"position:x", -SLIDE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_top, ^"position:y", -BAR_HEIGHT, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_bottom, ^"position:y", _bottom.position.y + BAR_HEIGHT, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(queue_free)


# --- Building blocks -----------------------------------------------------------------

func _bar(preset: Control.LayoutPreset) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	bar.set_anchors_preset(preset)
	var bottom: bool = preset == Control.PRESET_BOTTOM_WIDE
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = -BAR_HEIGHT if bottom else 0.0
	bar.offset_bottom = 0.0 if bottom else BAR_HEIGHT
	return bar


func _layer() -> Control:
	var layer: Control = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


## Top left, hanging just under the black bar: the show's name and LIVE.
func _build_badge() -> void:
	var badge: PanelContainer = PanelContainer.new()
	badge.add_theme_stylebox_override(&"panel", _flat(PANEL_COLOR, MainMenu.BUTTON_BORDER, 2))
	_left.add_child(badge)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	badge.add_child(row)
	row.add_child(_label("BLUE", 26, MainMenu.BUTTON_BORDER))
	row.add_child(_label("42", 26, MainMenu.GOLD))
	row.add_child(_label("GAMEDAY", 26, Color.WHITE))

	var live: PanelContainer = PanelContainer.new()
	live.add_theme_stylebox_override(&"panel", _flat(LIVE_COLOR, LIVE_COLOR, 0, 8.0, 0.0))
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(live)
	var live_row: HBoxContainer = HBoxContainer.new()
	live_row.add_theme_constant_override(&"separation", 6)
	live.add_child(live_row)
	_live_dot = Panel.new()
	_live_dot.custom_minimum_size = Vector2(10.0, 10.0)
	_live_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot: StyleBoxFlat = StyleBoxFlat.new()
	dot.bg_color = Color.WHITE
	dot.set_corner_radius_all(5)
	_live_dot.add_theme_stylebox_override(&"panel", dot)
	live_row.add_child(_live_dot)
	live_row.add_child(_label("LIVE", 18, Color.WHITE))
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	badge.position = Vector2(MARGIN, BAR_HEIGHT + 18.0)


## Bottom left: a gold strip, the two teams, and tonight's line of nonsense.
func _build_lower_third() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	_left.add_child(column)

	var strip: PanelContainer = PanelContainer.new()
	strip.add_theme_stylebox_override(&"panel", _flat(MainMenu.GOLD, MainMenu.GOLD, 0, 14.0, 2.0))
	strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	strip.add_child(_label("TONIGHT'S MATCHUP", 20, MainMenu.OUTLINE))
	column.add_child(strip)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _flat(PANEL_COLOR, MainMenu.BUTTON_BORDER, 3, 22.0, 12.0))
	column.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 2)
	panel.add_child(body)
	var matchup: HBoxContainer = HBoxContainer.new()
	matchup.add_theme_constant_override(&"separation", 16)
	body.add_child(matchup)
	matchup.add_child(_team(game.home))
	matchup.add_child(_label("VS", 26, MainMenu.BUTTON_BORDER))
	matchup.add_child(_team(game.away))

	var pick: int = randi() % TAGLINES.size()
	if pick == _last_tagline:
		pick = (pick + 1) % TAGLINES.size()
	_last_tagline = pick
	body.add_child(_label(TAGLINES[pick], 22, Color(0.86, 0.9, 1.0)))
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	column.position += Vector2(MARGIN, -(BAR_HEIGHT + 22.0))


## A block of the team's colour and its name.
func _team(team: Team) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var chip: Panel = Panel.new()
	chip.custom_minimum_size = Vector2(14.0, 40.0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = team.team_color
	style.set_corner_radius_all(3)
	chip.add_theme_stylebox_override(&"panel", style)
	row.add_child(chip)
	row.add_child(_label(team.team_name.to_upper(), 42, Color.WHITE))
	return row


## In the bottom bar, out of the way.
func _build_skip() -> void:
	var skip: Label = _label("(A)  SKIP", 18, Color(1.0, 1.0, 1.0, 0.55))
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bottom.add_child(skip)
	skip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skip.offset_right = -MARGIN


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
