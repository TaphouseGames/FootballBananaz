class_name HUD
extends CanvasLayer
## Scoreboard, down and distance, clock, turbo meter, banners and the
## play-select panel. Reads everything it shows from Game each frame.

const GRID_COLUMNS: int = 3
## Plays on one page of the play-select grid.
const PAGE_SIZE: int = 9
const CARD_COLOR: Color = Color(0.09, 0.16, 0.13, 0.96)
const CARD_SELECTED_COLOR: Color = Color(0.14, 0.27, 0.2, 1.0)
const CARD_BORDER: Color = Color(0.32, 0.38, 0.35)
const CARD_SELECTED_BORDER: Color = Color(1.0, 1.0, 1.0)
const NAME_COLOR: Color = Color(0.82, 0.84, 0.82)
const NAME_SELECTED_COLOR: Color = Color(1.0, 0.9, 0.2)

var game: Game

var _cards: Array[PanelContainer] = []
var _card_names: Array[Label] = []
var _diagrams: Array[PlayDiagram] = []
var _card_style: StyleBoxFlat
var _card_selected_style: StyleBoxFlat

var _intro_card: IntroCard

@onready var top_bar: Control = $TopBar
@onready var score_label: Label = $TopBar/Row/ScoreLabel
@onready var down_label: Label = $TopBar/Row/DownLabel
@onready var clock_label: Label = $TopBar/Row/ClockLabel
@onready var banner: Label = $Banner
@onready var sub_banner: Label = $SubBanner
@onready var hint: Label = $Hint
@onready var turbo_box: Control = $TurboBox
@onready var turbo_bar: ProgressBar = $TurboBox/TurboBar
@onready var play_select: Control = $PlaySelect
@onready var play_title: Label = $PlaySelect/Margin/Column/Title
@onready var play_grid: GridContainer = $PlaySelect/Margin/Column/PlayGrid
@onready var pause_menu: PauseMenu = $PauseMenu


func setup(p_game: Game) -> void:
	game = p_game
	pause_menu.setup(p_game)
	hide_banner()
	hide_play_select()
	set_hint("")


func _process(_delta: float) -> void:
	if game == null or game.offense == null:
		return
	var home_marker: String = "> " if game.offense == game.home else ""
	var away_marker: String = " <" if game.offense == game.away else ""
	score_label.text = "%s%s  %d  -  %d  %s%s" % [home_marker, game.home.short_name, game.home.score, game.away.score, game.away.short_name, away_marker]
	# A kickoff has no spot yet.
	if game.play_controller.kickoff:
		down_label.text = game.down_text()
	else:
		down_label.text = "%s   |   %s" % [game.down_text(), game.ball_on_text()]
	clock_label.text = game.clock_text()

	var controlled: Player = game.human.controlled
	turbo_box.visible = controlled != null and not play_select.visible and _intro_card == null
	if controlled != null:
		turbo_bar.value = controlled.turbo
		turbo_bar.modulate = Color(1.0, 0.4, 0.3) if controlled.turbo_locked else Color.WHITE


func show_banner(text: String, sub_text: String = "") -> void:
	banner.text = text
	banner.visible = text != ""
	sub_banner.text = sub_text
	sub_banner.visible = sub_text != ""


## The television graphics of the pregame intro, in place of the scoreboard.
func show_intro() -> void:
	hide_intro()
	top_bar.visible = false
	_intro_card = IntroCard.new()
	add_child(_intro_card)
	# Under the pause menu.
	move_child(_intro_card, pause_menu.get_index())
	_intro_card.setup(game)


func hide_intro() -> void:
	top_bar.visible = true
	if _intro_card != null:
		_intro_card.finish()
		_intro_card = null


func hide_banner() -> void:
	banner.visible = false
	sub_banner.visible = false


func set_hint(text: String) -> void:
	hint.text = text
	hint.visible = text != ""


## `plays` holds OffensePlay or DefensePlay resources, shown as a grid of cards
## in playbook order.
func show_play_select(title: String, plays: Array[Resource]) -> void:
	for card: PanelContainer in _cards:
		# Out of the grid at once, so a page change never shows both pages.
		play_grid.remove_child(card)
		card.queue_free()
	_cards.clear()
	_card_names.clear()
	_diagrams.clear()
	if _card_style == null:
		_card_style = _make_card_style(CARD_COLOR, CARD_BORDER, 2)
		_card_selected_style = _make_card_style(CARD_SELECTED_COLOR, CARD_SELECTED_BORDER, 4)
	play_title.text = title
	for i: int in plays.size():
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override(&"separation", 2)
		card.add_child(column)

		var name_label: Label = Label.new()
		name_label.add_theme_font_size_override(&"font_size", 21)
		name_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override(&"outline_size", 6)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(name_label)

		var diagram: PlayDiagram = PlayDiagram.new()
		diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(diagram)

		var offense_play: OffensePlay = plays[i] as OffensePlay
		var defense_play: DefensePlay = plays[i] as DefensePlay
		if offense_play != null:
			name_label.text = offense_play.play_name.to_upper()
			diagram.show_offense(offense_play)
		elif defense_play != null:
			name_label.text = defense_play.play_name.to_upper()
			diagram.show_defense(defense_play)

		play_grid.add_child(card)
		_cards.append(card)
		_card_names.append(name_label)
		_diagrams.append(diagram)
	play_select.visible = true
	set_play_cursor(0)


## Draws every offensive play mirrored left to right, or as designed.
func set_play_flipped(flipped: bool) -> void:
	for diagram: PlayDiagram in _diagrams:
		diagram.set_flipped(flipped)


func set_play_cursor(index: int) -> void:
	for i: int in _cards.size():
		var selected: bool = i == index
		_cards[i].add_theme_stylebox_override(&"panel", _card_selected_style if selected else _card_style)
		_card_names[i].add_theme_color_override(&"font_color", NAME_SELECTED_COLOR if selected else NAME_COLOR)


func _make_card_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	# Thinner borders get more padding, so every card's contents line up.
	style.set_content_margin_all(float(10 - border_width))
	return style


func hide_play_select() -> void:
	play_select.visible = false
