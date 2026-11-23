class_name HUD
extends CanvasLayer
## The scoreboard (see Scoreboard), turbo meter, banners and the
## play-select panel. Reads everything it shows from Game each frame.

const GRID_COLUMNS: int = 3
## The grid always has at least this many rows, so a tab with few plays has
## cards of the same size as a full one.
const GRID_ROWS: int = 2
## The most plays one tab of the play-select grid has room for.
const PAGE_SIZE: int = 9
const CARD_COLOR: Color = Color(0.09, 0.16, 0.13, 0.96)
const CARD_SELECTED_COLOR: Color = Color(0.14, 0.27, 0.2, 1.0)
const CARD_BORDER: Color = Color(0.32, 0.38, 0.35)
const CARD_SELECTED_BORDER: Color = Color(1.0, 1.0, 1.0)
const NAME_COLOR: Color = Color(0.82, 0.84, 0.82)
const NAME_SELECTED_COLOR: Color = Color(1.0, 0.9, 0.2)
const NOTE_COLOR: Color = Color(0.6, 0.66, 0.62)
## The tab of the plays the coach advises. Its title stands out from the tabs
## of the book.
const COACH_TAB: String = "ASK COACH"
const COACH_TAB_COLOR: Color = Color(1.0, 0.85, 0.1)
const COUNTDOWN_WARN_COLOR: Color = Color(1.0, 0.3, 0.25)

var game: Game

var _cards: Array[PanelContainer] = []
var _card_names: Array[Label] = []
var _diagrams: Array[PlayDiagram] = []
## Empty cells that fill the grid up to GRID_ROWS rows.
var _fillers: Array[Control] = []
var _card_style: StyleBoxFlat
var _card_selected_style: StyleBoxFlat
var _tab_style: StyleBoxFlat
var _tab_selected_style: StyleBoxFlat

var _intro_card: IntroCard
var _halftime_card: HalftimeCard
var _audible: AudibleMenu
var _hot_routes: HotRouteMenu

@onready var scoreboard: Scoreboard = $Scoreboard
## The play clock and the play-select timer: the number in the scoreboard's box.
@onready var countdown: Label = scoreboard.play_clock
@onready var banner: Label = $Banner
@onready var sub_banner: Label = $SubBanner
@onready var hint: Label = $Hint
@onready var turbo_box: Control = $TurboBox
@onready var turbo_bar: ProgressBar = $TurboBox/TurboBar
@onready var play_select: Control = $PlaySelect
@onready var play_title: Label = $PlaySelect/Margin/Column/Title
@onready var play_tabs: HBoxContainer = $PlaySelect/Margin/Column/Tabs
@onready var play_grid: GridContainer = $PlaySelect/Margin/Column/PlayGrid
@onready var pause_menu: PauseMenu = $PauseMenu


func setup(p_game: Game) -> void:
	game = p_game
	scoreboard.setup(p_game)
	pause_menu.setup(p_game)
	hide_banner()
	hide_play_select()
	hide_countdown()
	set_hint("")


func _process(_delta: float) -> void:
	if game == null or game.offense == null:
		return
	scoreboard.refresh()

	var controlled: Player = game.human.controlled
	turbo_box.visible = controlled != null and not play_select.visible and _intro_card == null and _halftime_card == null
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
	scoreboard.visible = false
	_intro_card = IntroCard.new()
	add_child(_intro_card)
	# Under the pause menu.
	move_child(_intro_card, pause_menu.get_index())
	_intro_card.setup(game)


func hide_intro() -> void:
	scoreboard.visible = true
	if _intro_card != null:
		_intro_card.finish()
		_intro_card = null


## The halftime report, in place of the scoreboard.
func show_halftime() -> HalftimeCard:
	hide_halftime()
	scoreboard.visible = false
	_halftime_card = HalftimeCard.new()
	add_child(_halftime_card)
	# Under the pause menu.
	move_child(_halftime_card, pause_menu.get_index())
	_halftime_card.setup(game)
	return _halftime_card


func hide_halftime() -> void:
	if _halftime_card != null:
		scoreboard.visible = true
		_halftime_card.finish()
		_halftime_card = null


func hide_banner() -> void:
	banner.visible = false
	sub_banner.visible = false


func set_hint(text: String) -> void:
	hint.text = text
	hint.visible = text != ""


## `plays` holds the OffensePlay or DefensePlay resources of one tab, shown as a
## grid of cards in that order. `tabs` names every tab; `tab` is the open one.
## `notes`, when given, has a line for each card to show small under its name.
func show_play_select(title: String, tabs: PackedStringArray, tab: int, plays: Array[Resource], notes: PackedStringArray = PackedStringArray()) -> void:
	_show_tabs(tabs, tab)
	for card: PanelContainer in _cards:
		# Out of the grid at once, so a page change never shows both pages.
		play_grid.remove_child(card)
		card.queue_free()
	for filler: Control in _fillers:
		play_grid.remove_child(filler)
		filler.queue_free()
	_fillers.clear()
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

		if i < notes.size():
			var note: Label = Label.new()
			note.text = notes[i]
			note.add_theme_font_size_override(&"font_size", 13)
			note.add_theme_color_override(&"font_color", NOTE_COLOR)
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(note)

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
	for i: int in range(plays.size(), GRID_COLUMNS * GRID_ROWS):
		var filler: Control = Control.new()
		filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		play_grid.add_child(filler)
		_fillers.append(filler)
	# Fades in when it comes up; a tab change shows at once.
	ScreenFade.pop(play_select, true, ScreenFade.FADE_IN)
	set_play_cursor(0)


## The strip of tab names over the cards, the open one lit.
func _show_tabs(tabs: PackedStringArray, tab: int) -> void:
	if _tab_style == null:
		_tab_style = _make_card_style(CARD_COLOR, CARD_BORDER, 2)
		_tab_selected_style = _make_card_style(CARD_SELECTED_COLOR, CARD_SELECTED_BORDER, 2)
	for child: Node in play_tabs.get_children():
		play_tabs.remove_child(child)
		child.queue_free()
	for i: int in tabs.size():
		var selected: bool = i == tab
		var label: Label = Label.new()
		label.text = tabs[i]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 20)
		var color: Color = COACH_TAB_COLOR if tabs[i] == COACH_TAB else NAME_COLOR
		label.add_theme_color_override(&"font_color", NAME_SELECTED_COLOR if selected else color)
		label.add_theme_stylebox_override(&"normal", _tab_selected_style if selected else _tab_style)
		play_tabs.add_child(label)


## Draws every play mirrored left to right, or as designed.
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


## The play clock and the play-select timer: whole seconds left, red when
## `warn`.
func set_countdown(seconds_left: float, warn: bool) -> void:
	countdown.text = str(ceili(seconds_left))
	countdown.add_theme_color_override(&"font_color", COUNTDOWN_WARN_COLOR if warn else Color.WHITE)
	countdown.visible = true


func hide_countdown() -> void:
	countdown.visible = false


## The audible menu at the line (see AudibleMenu), made the first time it is
## asked for: `plays` on up, left, right and down of the stick, drawn mirrored
## or not, and the play that is `called` now.
func show_audible(plays: Array[Resource], flipped: bool, called: Resource) -> void:
	if _audible == null:
		_audible = AudibleMenu.new()
		add_child(_audible)
		# Under the pause menu.
		move_child(_audible, pause_menu.get_index())
	_audible.visible = true
	_audible.show_plays(plays, flipped, called)


func hide_audible() -> void:
	if _audible != null:
		_audible.visible = false


## The hot-route panel (see HotRouteMenu), made the first time it is asked
## for. `receiver` names the picked man, or is empty while one is being picked.
func show_hot_routes(receiver: String) -> void:
	if _hot_routes == null:
		_hot_routes = HotRouteMenu.new()
		add_child(_hot_routes)
		# Under the pause menu.
		move_child(_hot_routes, pause_menu.get_index())
	_hot_routes.visible = true
	_hot_routes.show_for(receiver)


func hide_hot_routes() -> void:
	if _hot_routes != null:
		_hot_routes.visible = false


func audible_shown() -> bool:
	return _audible != null and _audible.visible


func hide_play_select() -> void:
	ScreenFade.pop(play_select, false, 0.0)
