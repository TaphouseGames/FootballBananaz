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

## The play-select panel of each person: one in the middle of the screen, or
## with two playing one on each half (see _split_play_select).
var _play_panels: Array[PlayPanel] = []
## The line of buttons of each person at the line of scrimmage, with two
## playing: one on each half, where the sub-banner is with one.
var _line_hints: Array[Label] = []
var _card_style: StyleBoxFlat
var _card_selected_style: StyleBoxFlat
var _tab_style: StyleBoxFlat
var _tab_selected_style: StyleBoxFlat

var _intro_card: IntroCard
var _halftime_card: HalftimeCard
## The audible menu of each person (the second one's in the right corner).
var _audibles: Array[AudibleMenu] = [null, null]
var _hot_routes: HotRouteMenu
## The stamina bar of each person playing, in the order of Game.humans.
var _turbo_boxes: Array[Control] = []
var _turbo_bars: Array[ProgressBar] = []

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


## One person's play-select panel: its parts, and the cards on it now.
class PlayPanel:
	var root: Control
	var title: Label
	var tabs: HBoxContainer
	var grid: GridContainer
	## The buttons under the cards, on a half-screen panel. Null on the one in
	## the middle, whose hint is the HUD's own.
	var hint: Label
	## Half a screen wide: everything on it is set smaller.
	var small: bool = false
	var cards: Array[PanelContainer] = []
	var card_names: Array[Label] = []
	var diagrams: Array[PlayDiagram] = []
	## Empty cells that keep a short page's cards the size of a full one's.
	var fillers: Array[Control] = []


func setup(p_game: Game) -> void:
	game = p_game
	scoreboard.setup(p_game)
	pause_menu.setup(p_game)
	# A stamina bar for each person: the second one's in the other top corner.
	_turbo_boxes = [turbo_box]
	_turbo_bars = [turbo_bar]
	if game.humans.size() > 1:
		var second: Control = turbo_box.duplicate() as Control
		add_child(second)
		move_child(second, turbo_box.get_index() + 1)
		var width: float = turbo_box.offset_right - turbo_box.offset_left
		second.anchor_left = 1.0
		second.anchor_right = 1.0
		second.offset_right = -turbo_box.offset_left
		second.offset_left = -turbo_box.offset_left - width
		_turbo_boxes.append(second)
		_turbo_bars.append(second.get_node(^"TurboBar") as ProgressBar)
		# Each in its team's colour, as the ring under their player is.
		var sides: Array[Team] = [game.home, game.away]
		for i: int in _turbo_bars.size():
			var fill: StyleBoxFlat = _turbo_bars[i].get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
			fill.bg_color = sides[i].marker_color()
			_turbo_bars[i].add_theme_stylebox_override(&"fill", fill)
	_play_panels = [_play_panel(play_select)]
	if game.humans.size() > 1:
		_split_play_select()
		_build_line_hints()
	hide_banner()
	hide_play_select()
	hide_countdown()
	set_hint("")


func _play_panel(root: Control) -> PlayPanel:
	var panel: PlayPanel = PlayPanel.new()
	panel.root = root
	panel.title = root.get_node(^"Margin/Column/Title") as Label
	panel.tabs = root.get_node(^"Margin/Column/Tabs") as HBoxContainer
	panel.grid = root.get_node(^"Margin/Column/PlayGrid") as GridContainer
	return panel


## Two people: a panel on each half of the screen, the home team's on the left,
## each with its team's colour round it and its own line of buttons.
func _split_play_select() -> void:
	var second: Control = play_select.duplicate() as Control
	add_child(second)
	move_child(second, play_select.get_index() + 1)
	_play_panels.append(_play_panel(second))
	var teams: Array[Team] = [game.home, game.away]
	for i: int in _play_panels.size():
		var panel: PlayPanel = _play_panels[i]
		panel.small = true
		var root: Control = panel.root
		root.set_anchor_and_offset(SIDE_LEFT, 0.5 * float(i), 12.0 if i == 0 else 6.0)
		root.set_anchor_and_offset(SIDE_RIGHT, 0.5 * float(i + 1), -6.0 if i == 0 else -12.0)
		var frame: StyleBoxFlat = root.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
		frame.border_color = teams[i].marker_color()
		root.add_theme_stylebox_override(&"panel", frame)
		var margin: Control = root.get_node(^"Margin") as Control
		margin.add_theme_constant_override(&"margin_left", 10)
		margin.add_theme_constant_override(&"margin_right", 10)
		panel.title.add_theme_font_size_override(&"font_size", 20)
		panel.title.add_theme_color_override(&"font_color", teams[i].marker_color())
		panel.grid.add_theme_constant_override(&"h_separation", 6)
		panel.hint = Label.new()
		panel.hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.hint.add_theme_font_size_override(&"font_size", 15)
		panel.title.get_parent().add_child(panel.hint)


## Two people: where the sub-banner is, a line for each on their half.
func _build_line_hints() -> void:
	var teams: Array[Team] = [game.home, game.away]
	for i: int in teams.size():
		var label: Label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override(&"font_size", 17)
		label.add_theme_color_override(&"font_color", teams[i].marker_color().lerp(Color.WHITE, 0.4))
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 6)
		label.visible = false
		add_child(label)
		move_child(label, sub_banner.get_index() + 1 + i)
		# Placed once it is in the tree: before that the anchors do not hold.
		label.anchor_left = 0.5 * float(i)
		label.anchor_right = 0.5 * float(i + 1)
		label.anchor_top = sub_banner.anchor_top
		label.anchor_bottom = sub_banner.anchor_bottom
		label.offset_left = 24.0
		label.offset_right = -24.0
		label.offset_top = sub_banner.offset_top
		label.offset_bottom = sub_banner.offset_bottom
		_line_hints.append(label)


## The buttons of the person on half `slot` of the screen at the line of
## scrimmage, with two playing. Empty text takes the line away.
func show_line_hint(slot: int, text: String) -> void:
	if slot < _line_hints.size():
		_line_hints[slot].text = text
		_line_hints[slot].visible = text != ""


func _process(_delta: float) -> void:
	if game == null or game.offense == null:
		return
	scoreboard.refresh()

	var clear: bool = not play_select.visible and _intro_card == null and _halftime_card == null
	for person: HumanController in game.humans:
		# The home team's person has the left one.
		var i: int = game.screen_slot(person)
		var controlled: Player = person.controlled
		_turbo_boxes[i].visible = controlled != null and clear
		if controlled != null:
			var bar: ProgressBar = _turbo_bars[i]
			bar.value = controlled.turbo
			bar.modulate = Color(1.0, 0.4, 0.3) if controlled.turbo_locked else Color.WHITE


func show_banner(text: String, sub_text: String = "") -> void:
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.HUD, &"show_banner", [text, sub_text])
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
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.HUD, &"hide_banner", [])
	banner.visible = false
	sub_banner.visible = false
	for label: Label in _line_hints:
		label.visible = false


func set_hint(text: String) -> void:
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.HUD, &"set_hint", [text], &"hint")
	hint.text = text
	hint.visible = text != ""


## `plays` holds the OffensePlay or DefensePlay resources of one tab, shown as a
## grid of cards in that order. `tabs` names every tab; `tab` is the open one.
## `notes`, when given, has a line for each card to show small under its name.
## `slot` is whose panel: 0, or with two playing 0 the left one and 1 the right.
func show_play_select(title: String, tabs: PackedStringArray, tab: int, plays: Array[Resource], notes: PackedStringArray = PackedStringArray(), slot: int = 0) -> void:
	var panel: PlayPanel = _play_panels[slot]
	_show_tabs(panel, tabs, tab)
	for card: PanelContainer in panel.cards:
		# Out of the grid at once, so a page change never shows both pages.
		panel.grid.remove_child(card)
		card.queue_free()
	for filler: Control in panel.fillers:
		panel.grid.remove_child(filler)
		filler.queue_free()
	panel.fillers.clear()
	panel.cards.clear()
	panel.card_names.clear()
	panel.diagrams.clear()
	if _card_style == null:
		_card_style = _make_card_style(CARD_COLOR, CARD_BORDER, 2)
		_card_selected_style = _make_card_style(CARD_SELECTED_COLOR, CARD_SELECTED_BORDER, 4)
	panel.title.text = title
	for i: int in plays.size():
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override(&"separation", 2)
		card.add_child(column)

		var name_label: Label = Label.new()
		name_label.add_theme_font_size_override(&"font_size", 14 if panel.small else 21)
		name_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override(&"outline_size", 6)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = panel.small
		column.add_child(name_label)

		if i < notes.size():
			var note: Label = Label.new()
			note.text = notes[i]
			note.add_theme_font_size_override(&"font_size", 11 if panel.small else 13)
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

		panel.grid.add_child(card)
		panel.cards.append(card)
		panel.card_names.append(name_label)
		panel.diagrams.append(diagram)
	for i: int in range(plays.size(), GRID_COLUMNS * GRID_ROWS):
		var filler: Control = Control.new()
		filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.grid.add_child(filler)
		panel.fillers.append(filler)
	# Fades in when it comes up; a tab change shows at once.
	ScreenFade.pop(panel.root, true, ScreenFade.FADE_IN)
	set_play_ready(false, slot)
	set_play_cursor(0, slot)


## The strip of tab names over the cards, the open one lit.
func _show_tabs(panel: PlayPanel, tabs: PackedStringArray, tab: int) -> void:
	if _tab_style == null:
		_tab_style = _make_card_style(CARD_COLOR, CARD_BORDER, 2)
		_tab_selected_style = _make_card_style(CARD_SELECTED_COLOR, CARD_SELECTED_BORDER, 2)
	panel.tabs.add_theme_constant_override(&"separation", 3 if panel.small else 8)
	for child: Node in panel.tabs.get_children():
		panel.tabs.remove_child(child)
		child.queue_free()
	for i: int in tabs.size():
		var selected: bool = i == tab
		var label: Label = Label.new()
		label.text = tabs[i]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = panel.small
		label.add_theme_font_size_override(&"font_size", 12 if panel.small else 20)
		var color: Color = COACH_TAB_COLOR if tabs[i] == COACH_TAB else NAME_COLOR
		label.add_theme_color_override(&"font_color", NAME_SELECTED_COLOR if selected else color)
		label.add_theme_stylebox_override(&"normal", _tab_selected_style if selected else _tab_style)
		panel.tabs.add_child(label)


## Draws every play of panel `slot` mirrored left to right, or as designed.
func set_play_flipped(flipped: bool, slot: int = 0) -> void:
	for diagram: PlayDiagram in _play_panels[slot].diagrams:
		diagram.set_flipped(flipped)


func set_play_cursor(index: int, slot: int = 0) -> void:
	var panel: PlayPanel = _play_panels[slot]
	for i: int in panel.cards.size():
		var selected: bool = i == index
		panel.cards[i].add_theme_stylebox_override(&"panel", _card_selected_style if selected else _card_style)
		panel.card_names[i].add_theme_color_override(&"font_color", NAME_SELECTED_COLOR if selected else NAME_COLOR)


## The buttons under the cards of panel `slot`: on the panel itself when it is
## half a screen, otherwise the HUD's hint.
func set_play_hint(text: String, slot: int = 0) -> void:
	var panel: PlayPanel = _play_panels[slot]
	if panel.hint == null:
		set_hint(text)
		return
	panel.hint.text = text
	panel.hint.add_theme_color_override(&"font_color", NAME_SELECTED_COLOR if text == "READY" else NAME_COLOR)


## The person of panel `slot` has picked and waits for the other: its cards dim.
func set_play_ready(ready: bool, slot: int = 0) -> void:
	_play_panels[slot].grid.modulate.a = 0.35 if ready else 1.0


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
	if NetEvents.recording:
		# Whole seconds are all that shows: told once a second, not every tick.
		NetEvents.tell(NetEvents.Part.HUD, &"set_countdown", [float(ceili(seconds_left)), warn], &"countdown")
	countdown.text = str(ceili(seconds_left))
	countdown.add_theme_color_override(&"font_color", COUNTDOWN_WARN_COLOR if warn else Color.WHITE)
	countdown.visible = true


func hide_countdown() -> void:
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.HUD, &"hide_countdown", [], &"countdown")
	countdown.visible = false


## The audible menu at the line (see AudibleMenu), made the first time it is
## asked for: `plays` on up, left, right and down of the stick, drawn mirrored
## or not, and the play that is `called` now. `slot` 1 is the second person's,
## in the right corner.
func show_audible(plays: Array[Resource], flipped: bool, called: Resource, slot: int = 0) -> void:
	if _audibles[slot] == null:
		_audibles[slot] = AudibleMenu.new()
		_audibles[slot].on_right = slot == 1
		add_child(_audibles[slot])
		# Under the pause menu.
		move_child(_audibles[slot], pause_menu.get_index())
	_audibles[slot].visible = true
	_audibles[slot].show_plays(plays, flipped, called)


func hide_audible(slot: int = 0) -> void:
	if _audibles[slot] != null:
		_audibles[slot].visible = false


## The hot-route panel (see HotRouteMenu), made the first time it is asked
## for. `receiver` names the picked man, or is empty while one is being picked.
## `inside`: the side of the screen the ball is on from him (-1 left, 1 right).
## `slot` 1 puts it in the right corner, the second person's.
func show_hot_routes(receiver: String, inside: float = 1.0, slot: int = 0) -> void:
	if _hot_routes == null:
		_hot_routes = HotRouteMenu.new()
		add_child(_hot_routes)
		# Under the pause menu.
		move_child(_hot_routes, pause_menu.get_index())
	_hot_routes.on_right = slot == 1
	_hot_routes.visible = true
	_hot_routes.show_for(receiver, inside)


## Lights the box of the route shown on the field (see HotRouteMenu.light).
func light_hot_route(kind: int, way: int) -> void:
	if _hot_routes != null:
		_hot_routes.light(kind, way)


func hide_hot_routes() -> void:
	if _hot_routes != null:
		_hot_routes.visible = false


## Somebody's audible menu is up.
func audible_shown() -> bool:
	for menu: AudibleMenu in _audibles:
		if menu != null and menu.visible:
			return true
	return false


func hide_play_select() -> void:
	for panel: PlayPanel in _play_panels:
		ScreenFade.pop(panel.root, false, 0.0)
