class_name Scoreboard
extends Control
## The score bug at the bottom of the screen, as on television: a block of each
## team's colour with its logo, its record (in a game of the season) and its
## score, either side of the down and distance, the half, the time left in it
## and the play clock. HUD refreshes it each frame.

const TEAM_WIDTH: float = 230.0
const MIDDLE_WIDTH: float = 250.0
const STRIP_HEIGHT: float = 30.0
const LOGO_WIDTH: float = 58.0
const CORNER: int = 6
const CLOCK_COLOR: Color = Color(0.03, 0.03, 0.04)
const PLAY_CLOCK_BORDER: Color = Color(0.9, 0.16, 0.14)
const DIM: Color = Color(0.8, 0.82, 0.85)
## A team colour brighter than this gets dark writing on it.
const LIGHT_COLOR: float = 0.55

var game: Game
## The number in the play clock's box. Hidden when no clock is running.
var play_clock: Label

var _font: SystemFont
## Home, then away.
var _block_styles: Array[StyleBoxFlat] = []
var _logos: Array[TextureRect] = []
var _records: Array[Label] = []
var _scores: Array[Label] = []
var _strip_style: StyleBoxFlat
var _down: Label
var _half: Label
var _divider: ColorRect
var _time: Label
var _dressed: bool = false
var _offense: Team


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = MainMenu.FONT_NAMES
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(_build_team(true))
	row.add_child(_build_middle())
	row.add_child(_build_team(false))


func setup(p_game: Game) -> void:
	game = p_game


## Called each frame once the teams are on the field.
func refresh() -> void:
	if not _dressed:
		_dress()
	_write(_scores[0], str(game.home.score))
	_write(_scores[1], str(game.away.score))
	_write(_down, game.down_text())
	if game.offense != _offense:
		_offense = game.offense
		_strip_style.bg_color = _offense.team_color.darkened(0.12)
		_down.add_theme_color_override(&"font_color", _ink(_strip_style.bg_color))
	_write(_half, game.half_text())
	var time: String = game.time_text()
	_write(_time, time)
	_time.visible = time != ""
	_divider.visible = time != ""


## The teams' colours, logos and records, which last the whole game.
func _dress() -> void:
	_dressed = true
	var teams: Array[Team] = [game.home, game.away]
	var season: Season = game.season()
	for i: int in teams.size():
		var team: Team = teams[i]
		_block_styles[i].bg_color = team.team_color
		var ink: Color = _ink(team.team_color)
		_scores[i].add_theme_color_override(&"font_color", ink)
		_records[i].add_theme_color_override(&"font_color", ink)
		_logos[i].texture = _logo(team)
		var place: int = season.team_of(team.short_name) if season != null else -1
		_records[i].visible = place >= 0
		if place >= 0:
			_records[i].text = season.record_text(place)


func _build_team(home: bool) -> Control:
	var block: PanelContainer = PanelContainer.new()
	block.custom_minimum_size = Vector2(TEAM_WIDTH, 0.0)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	if home:
		style.corner_radius_top_left = CORNER
		style.corner_radius_bottom_left = CORNER
	else:
		style.corner_radius_top_right = CORNER
		style.corner_radius_bottom_right = CORNER
	block.add_theme_stylebox_override(&"panel", style)
	_block_styles.append(style)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	block.add_child(row)

	var badge: VBoxContainer = VBoxContainer.new()
	badge.add_theme_constant_override(&"separation", -2)
	var logo: TextureRect = TextureRect.new()
	logo.custom_minimum_size = Vector2(LOGO_WIDTH, 0.0)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The pictures face right: the one on the right is turned to face the middle.
	logo.flip_h = not home
	badge.add_child(logo)
	_logos.append(logo)
	var record: Label = _label("", 14, Color.WHITE)
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record.visible = false
	badge.add_child(record)
	_records.append(record)

	var score: Label = _label("0", 42, Color.WHITE)
	score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scores.append(score)

	# The logos are at the outer ends, the scores next to the middle.
	if home:
		row.add_child(badge)
		row.add_child(score)
	else:
		row.add_child(score)
		row.add_child(badge)
	return block


## The down and distance on the colour of the team with the ball, over the
## half, the time left in it and the play clock on black.
func _build_middle() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(MIDDLE_WIDTH, 0.0)
	column.add_theme_constant_override(&"separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var strip: PanelContainer = PanelContainer.new()
	strip.custom_minimum_size = Vector2(0.0, STRIP_HEIGHT)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_style = StyleBoxFlat.new()
	_strip_style.bg_color = Color(0.15, 0.15, 0.15)
	strip.add_theme_stylebox_override(&"panel", _strip_style)
	_down = _label("", 22, Color.WHITE)
	_down.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	strip.add_child(_down)
	column.add_child(strip)

	var clock: PanelContainer = PanelContainer.new()
	clock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock_style: StyleBoxFlat = StyleBoxFlat.new()
	clock_style.bg_color = CLOCK_COLOR
	clock.add_theme_stylebox_override(&"panel", clock_style)
	column.add_child(clock)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	clock.add_child(row)

	_half = _label("", 22, DIM)
	_half.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_half)
	_divider = ColorRect.new()
	_divider.color = DIM
	_divider.custom_minimum_size = Vector2(2.0, 22.0)
	_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_divider)
	_time = _label("", 24, Color.WHITE)
	_time.custom_minimum_size = Vector2(54.0, 0.0)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_time)

	var box: PanelContainer = PanelContainer.new()
	box.custom_minimum_size = Vector2(38.0, 28.0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box_style: StyleBoxFlat = StyleBoxFlat.new()
	box_style.bg_color = CLOCK_COLOR
	box_style.border_color = PLAY_CLOCK_BORDER
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(3)
	box.add_theme_stylebox_override(&"panel", box_style)
	play_clock = _label("", 20, Color.WHITE)
	play_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	play_clock.visible = false
	box.add_child(play_clock)
	row.add_child(box)
	return column


## The team's mascot picture, without the empty space around it.
func _logo(team: Team) -> Texture2D:
	var texture: Texture2D = Field.mascot_decal(team)
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return texture
	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return texture
	var cropped: AtlasTexture = AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(used)
	return cropped


## White writing, or dark on a light colour.
func _ink(on: Color) -> Color:
	return MainMenu.OUTLINE if on.get_luminance() > LIGHT_COLOR else Color.WHITE


func _write(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label
