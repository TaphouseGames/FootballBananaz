class_name PauseMenu
extends Control
## Start pauses the game and opens this: resume, the box score, the team stats,
## the rosters with a card for each player, and the way back to the main menu.
## It keeps running while the tree is paused; everything else stops.
## Once the game is over it comes up by itself (see GameOverState), without the
## resume, and stays: the main menu is the only way on.

enum Screen { MENU, BOX_SCORE, TEAM_STATS, ROSTER, CONTROLS }

const RESUME: String = "RESUME"
const MAIN_MENU: String = "MAIN MENU"
const MENU_ITEMS: Array[String] = [RESUME, "BOX SCORE", "TEAM STATS", "VIEW ROSTER", "CONTROLS", MAIN_MENU]
const MENU_SCENE: String = "res://scenes/main_menu.tscn"
## The controls screen: a heading, then a button and what it does on each line.
## The first half of the sections fills the left column, the rest the right.
const CONTROLS: Array[Array] = [
	["ANY TIME", [
		["Stick / D-pad", "Move"],
		["RT", "Turbo"],
		["Start", "Pause"],
	]],
	["PASSING", [
		["(A) (X) (B)", "Throw to that receiver: tap to lob, hold longer to throw harder"],
		["Hold (LB)", "Lead him"],
		["Hold (RB)", "Underthrow"],
		["Hold RT", "Tuck and run, let go to throw again"],
		["LT", "Throw it away, out of bounds"],
		["(Y)", "Jump"],
	]],
	["RUNNING WITH THE BALL", [
		["(B)", "Spin. With the stick across: juke"],
		["(LB) (RB)", "Stiff arm to the left, to the right"],
		["(X)", "Dive, down where you land. On a kick return in your own end zone: touchback"],
		["(Y) (A)", "Jump"],
	]],
	["DEFENSE", [
		["(B)", "Switch defender. Before the snap: pick another one"],
		["(X)", "Dive at the carrier, at a pass or on a loose ball"],
		["(Y) (A)", "Jump"],
	]],
	["OFFENSE WITHOUT THE BALL", [
		["(X)", "Shove. With a pass in the air: dive at it"],
		["(B)", "Switch to the teammate nearest the ball"],
		["(Y) (A)", "Jump"],
	]],
	["AFTER THE WHISTLE", [
		["(X)", "Late hit"],
	]],
	["PLAY SELECT", [
		["Stick / D-pad", "Choose"],
		["(A)", "Confirm, then (A) again to snap. Both are on a clock"],
		["(X)", "Flip the play"],
		["(LB) (RB)", "Other page"],
		["(B)", "Before the snap on offense: the quarterback shouts"],
	]],
]
const CONTROLS_LEFT: int = 3
const BUTTON_WIDTH: float = 120.0
const BOX_PAGES: Array[String] = ["OFFENSE", "DEFENSE"]
const PANEL_SIZE: Vector2 = Vector2(1080.0, 624.0)
const GOLD: Color = Color(1.0, 0.85, 0.1)
const TEXT: Color = Color(0.86, 0.88, 0.86)
const DIM_TEXT: Color = Color(0.6, 0.64, 0.62)
const ROW_COLOR: Color = Color(1.0, 1.0, 1.0, 0.05)
const HEAD_COLOR: Color = Color(1.0, 1.0, 1.0, 0.12)
const BAR_BACK: Color = Color(0.0, 0.0, 0.0, 0.5)
const BAR_COLOR: Color = Color(0.45, 0.62, 0.52)
## Width of a number column and of the name column in a box-score table.
const STAT_WIDTH: float = 56.0
const NAME_WIDTH: float = 150.0
const SCROLL_SPEED: float = 500.0
## Buttons that close or pick something: the game stays paused until all of
## them are let go, so the press cannot also snap the ball or throw a pass.
const HELD_ACTIONS: Array[StringName] = [&"pause", &"confirm", &"back"]

var game: Game
var screen: Screen = Screen.MENU

var _open: bool = false
## Closing, and waiting for the buttons to be released.
var _closing: bool = false
## Closing for good: on to the main menu.
var _to_menu: bool = false
## MAIN MENU was picked with a game still on, and has to be picked again.
var _confirm_quit: bool = false
var _cursor: int = 0
var _box_page: int = 0
var _roster_team: int = 0
var _roster_cursor: int = 0

var _title: Label
var _body: MarginContainer
var _scroll: ScrollContainer
var _hint: Label
var _sound: AudioStreamPlayer
var _item_style: StyleBoxFlat
var _item_selected_style: StyleBoxFlat


func setup(p_game: Game) -> void:
	game = p_game
	if _title == null:
		_build()
	visible = false


func is_open() -> bool:
	return _open


func _process(delta: float) -> void:
	if game == null:
		return
	if _closing:
		for action: StringName in HELD_ACTIONS:
			if Input.is_action_pressed(action):
				return
		_finish_close()
		return
	if not _open:
		# After the final whistle it opens by itself, once the booth is done.
		if Input.is_action_just_pressed(&"pause") and not _game_over():
			open()
		return
	if Input.is_action_just_pressed(&"pause"):
		if not _game_over():
			close()
		elif screen != Screen.MENU:
			_back()
		return
	match screen:
		Screen.MENU:
			_update_menu()
		Screen.ROSTER:
			_update_roster()
		_:
			_update_table(delta)


# --- Opening and closing -------------------------------------------------------------

func open() -> void:
	if _open or game == null:
		return
	_open = true
	_closing = false
	_to_menu = false
	_confirm_quit = false
	_cursor = 0
	get_tree().paused = true
	ScreenFade.pop(self, true, ScreenFade.MENU_FADE, true)
	# The game's own prompt would show through under the panel.
	game.hud.hint.modulate.a = 0.0
	show_screen(Screen.MENU)
	_play(&"ui_page")


## Hides the menu. The game starts again once the buttons are let go, or with
## `to_menu` gives way to the main menu.
func close(to_menu: bool = false) -> void:
	if not _open:
		return
	_open = false
	_closing = true
	_to_menu = to_menu
	ScreenFade.pop(self, false, ScreenFade.MENU_FADE, true)
	game.hud.hint.modulate.a = 1.0


func _finish_close() -> void:
	_closing = false
	get_tree().paused = false
	if _to_menu:
		ScreenFade.of(get_tree()).change_scene(MENU_SCENE)


func show_screen(to: Screen, page: int = 0) -> void:
	screen = to
	_confirm_quit = false
	if to == Screen.BOX_SCORE:
		_box_page = posmod(page, BOX_PAGES.size())
	elif to == Screen.ROSTER:
		_roster_team = posmod(page, 2)
		_roster_cursor = 0
	_refresh()
	# The new screen's contents come up out of nothing.
	_body.modulate.a = 0.0
	ScreenFade.pop(_body, true, ScreenFade.MENU_FADE, true)


## The game is over: nothing to resume, and the menu does not close.
func _game_over() -> bool:
	return game.play_controller.state_machine.current_name() == &"GameOver"


## The entries of the menu screen.
func _items() -> Array[String]:
	var items: Array[String] = []
	for item: String in MENU_ITEMS:
		if item != RESUME or not _game_over():
			items.append(item)
	return items


## The end of a screen's hint: what Start does from there.
func _start_hint() -> String:
	return "Start: menu" if _game_over() else "Start: resume"


# --- Input ---------------------------------------------------------------------------

func _update_menu() -> void:
	var step: int = int(Input.is_action_just_pressed(&"move_down")) - int(Input.is_action_just_pressed(&"move_up"))
	var items: Array[String] = _items()
	if step != 0:
		_cursor = posmod(_cursor + step, items.size())
		_confirm_quit = false
		_refresh()
		_play(&"ui_move")
	if Input.is_action_just_pressed(&"back"):
		if _confirm_quit:
			_confirm_quit = false
			_refresh()
		elif not _game_over():
			close()
	elif Input.is_action_just_pressed(&"confirm"):
		_play(&"ui_confirm")
		match items[_cursor]:
			RESUME:
				close()
			"BOX SCORE":
				show_screen(Screen.BOX_SCORE)
			"TEAM STATS":
				show_screen(Screen.TEAM_STATS)
			"VIEW ROSTER":
				show_screen(Screen.ROSTER)
			"CONTROLS":
				show_screen(Screen.CONTROLS)
			MAIN_MENU:
				# A game still on is not thrown away by one stray press.
				if _game_over() or _confirm_quit:
					close(true)
				else:
					_confirm_quit = true
					_refresh()


func _update_table(delta: float) -> void:
	if Input.is_action_just_pressed(&"back"):
		_back()
		return
	if screen == Screen.CONTROLS and Input.is_action_just_pressed(&"confirm"):
		_play(&"ui_confirm")
		show_screen(Screen.MENU)
		return
	_scroll.scroll_vertical += roundi(Input.get_axis(&"move_up", &"move_down") * SCROLL_SPEED * delta)
	if screen != Screen.BOX_SCORE:
		return
	var turn: int = int(Input.is_action_just_pressed(&"page_next")) - int(Input.is_action_just_pressed(&"page_prev"))
	if turn != 0:
		_box_page = posmod(_box_page + turn, BOX_PAGES.size())
		_refresh()
		_play(&"ui_page")


func _update_roster() -> void:
	if Input.is_action_just_pressed(&"back"):
		_back()
		return
	var turn: int = int(Input.is_action_just_pressed(&"page_next")) - int(Input.is_action_just_pressed(&"page_prev"))
	if turn != 0:
		_roster_team = posmod(_roster_team + turn, 2)
		_roster_cursor = 0
		_refresh()
		_play(&"ui_page")
		return
	var step: int = int(Input.is_action_just_pressed(&"move_down")) - int(Input.is_action_just_pressed(&"move_up"))
	if step != 0:
		_roster_cursor = posmod(_roster_cursor + step, _roster().squad.size())
		_refresh()
		_play(&"ui_move")


func _back() -> void:
	_play(&"ui_flip")
	show_screen(Screen.MENU)


func _play(sound: StringName) -> void:
	var stream: AudioStream = game.audio.stream_for(sound)
	if stream != null:
		_sound.stream = stream
		_sound.play()


# --- Screens -------------------------------------------------------------------------

func _refresh() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0
	match screen:
		Screen.MENU:
			_title.text = "GAME OVER" if _game_over() else "PAUSED"
			_hint.text = "Stick / D-pad: choose      (A): select"
			if _confirm_quit:
				_hint.text = "(A): leave this game for the main menu      (B): stay"
				if game.season() != null:
					_hint.text = "(A): leave this game, to be played again from the start      (B): stay"
			elif not _game_over():
				_hint.text += "      (B) / Start: resume"
			_body.add_child(_menu_view())
		Screen.BOX_SCORE:
			_title.text = "BOX SCORE  -  %s" % BOX_PAGES[_box_page]
			_hint.text = "(LB) / (RB): offense, defense      Stick: scroll      (B): back      " + _start_hint()
			_body.add_child(_box_score_view())
		Screen.TEAM_STATS:
			_title.text = "TEAM STATS"
			_hint.text = "Stick: scroll      (B): back      " + _start_hint()
			_body.add_child(_team_stats_view())
		Screen.ROSTER:
			_title.text = "ROSTER  -  %s" % _roster().team_name.to_upper()
			_hint.text = "Stick / D-pad: choose a player      (LB) / (RB): other team      (B): back      " + _start_hint()
			_body.add_child(_roster_view())
		Screen.CONTROLS:
			_title.text = "CONTROLS"
			_hint.text = "(A): accept      Stick: scroll      (B): back      " + _start_hint()
			_body.add_child(_controls_view())


## What every button does, in two columns of sections.
func _controls_view() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 28)
	var columns: Array[VBoxContainer] = []
	for i: int in 2:
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override(&"separation", 3)
		row.add_child(column)
		columns.append(column)
	for i: int in CONTROLS.size():
		var column: VBoxContainer = columns[0 if i < CONTROLS_LEFT else 1]
		var heading: String = CONTROLS[i][0]
		var lines: Array = CONTROLS[i][1]
		if column.get_child_count() > 0:
			column.add_child(_spacer(8.0))
		column.add_child(_label(heading, 17, GOLD))
		for j: int in lines.size():
			var button: String = lines[j][0]
			var what: String = lines[j][1]
			var panel: PanelContainer = PanelContainer.new()
			panel.add_theme_stylebox_override(&"panel", _flat(ROW_COLOR if j % 2 == 0 else Color(0.0, 0.0, 0.0, 0.0), 8.0, 2.0))
			var line: HBoxContainer = HBoxContainer.new()
			line.add_theme_constant_override(&"separation", 10)
			panel.add_child(line)
			var button_label: Label = _label(button, 15, HUD.NAME_SELECTED_COLOR)
			button_label.custom_minimum_size.x = BUTTON_WIDTH
			line.add_child(button_label)
			var what_label: Label = _label(what, 15, TEXT)
			what_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			what_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_child(what_label)
			column.add_child(panel)
	return row


func _score_line() -> String:
	return "%s  %d  -  %d  %s          %s" % [game.home.short_name, game.home.score, game.away.score, game.away.short_name, game.clock_text()]


func _menu_view() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 12)
	column.add_child(_label(_score_line(), 24, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_spacer(18.0))
	var items: Array[String] = _items()
	for i: int in items.size():
		var selected: bool = i == _cursor
		var item: PanelContainer = PanelContainer.new()
		item.custom_minimum_size = Vector2(380.0, 58.0)
		item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		item.add_theme_stylebox_override(&"panel", _item_selected_style if selected else _item_style)
		var text: String = "QUIT GAME?  (A) AGAIN" if selected and _confirm_quit else items[i]
		if text == MAIN_MENU and game.season() != null:
			text = "BACK TO SEASON"
		var label: Label = _label(text, 26, HUD.NAME_SELECTED_COLOR if selected else HUD.NAME_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item.add_child(label)
		column.add_child(item)
	return column


## Both teams side by side, a table for each part of the game.
func _box_score_view() -> Control:
	var book: StatBook = game.stat_book
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 28)
	for team: Team in [game.home, game.away]:
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override(&"separation", 3)
		if _box_page == 0:
			_add_table(column, team, "PASSING", StatBook.PASSING_HEAD, book.passing_rows(team))
			_add_table(column, team, "RUSHING", StatBook.RUSHING_HEAD, book.rushing_rows(team))
			_add_table(column, team, "RECEIVING", StatBook.RECEIVING_HEAD, book.receiving_rows(team))
		else:
			_add_table(column, team, "DEFENSE", StatBook.DEFENSE_HEAD, book.defense_rows(team))
		row.add_child(column)
	return row


func _add_table(column: VBoxContainer, team: Team, what: String, head: PackedStringArray, rows: Array[PackedStringArray]) -> void:
	if column.get_child_count() > 0:
		column.add_child(_spacer(8.0))
	column.add_child(_label("%s %s" % [team.short_name, what], 19, _team_tint(team)))
	column.add_child(_table_row(head, HEAD_COLOR, DIM_TEXT, 13))
	for i: int in rows.size():
		var team_row: bool = i == rows.size() - 1
		var fill: Color = ROW_COLOR if i % 2 == 1 else Color(0.0, 0.0, 0.0, 0.0)
		column.add_child(_table_row(rows[i], fill, Color.WHITE if team_row else TEXT, 15))


## One line of a table: the name on the left, the numbers in columns of the
## same width on the right.
func _table_row(cells: PackedStringArray, fill: Color, color: Color, font_size: int) -> Control:
	return StatTable.row(cells, fill, color, font_size, STAT_WIDTH, NAME_WIDTH)


func _team_stats_view() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	column.add_child(_stats_row("", game.home.short_name, game.away.short_name, false, HEAD_COLOR, _team_tint(game.home), _team_tint(game.away)))
	var rows: Array[Array] = game.stat_book.team_rows()
	for i: int in rows.size():
		var cells: Array = rows[i]
		var label: String = cells[0]
		var indented: bool = cells[3]
		var fill: Color = ROW_COLOR if i % 2 == 1 else Color(0.0, 0.0, 0.0, 0.0)
		column.add_child(_stats_row(label, cells[1], cells[2], indented, fill, TEXT, TEXT))
	var centered: CenterContainer = CenterContainer.new()
	column.custom_minimum_size.x = 640.0
	centered.add_child(column)
	centered.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return centered


func _stats_row(label: String, home: String, away: String, indented: bool, fill: Color, home_color: Color, away_color: Color) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _flat(fill, 10.0, 0.0))
	var row: HBoxContainer = HBoxContainer.new()
	panel.add_child(row)
	var name_label: Label = _label(("      " if indented else "") + label, 14, DIM_TEXT if indented else Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	for cell: Array in [[home, home_color], [away, away_color]]:
		var text: String = cell[0]
		var color: Color = cell[1]
		var value: Label = _label(text, 14, color, HORIZONTAL_ALIGNMENT_RIGHT)
		value.custom_minimum_size.x = 130.0
		row.add_child(value)
	return panel


func _roster() -> Team:
	return game.home if _roster_team == 0 else game.away


## The team's players down the left, the chosen one's card on the right.
func _roster_view() -> Control:
	var team: Team = _roster()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	var list: VBoxContainer = VBoxContainer.new()
	list.custom_minimum_size.x = 400.0
	list.add_theme_constant_override(&"separation", 6)
	row.add_child(list)
	for i: int in team.squad.size():
		var player: Player = team.squad[i]
		var selected: bool = i == _roster_cursor
		var item: PanelContainer = PanelContainer.new()
		item.add_theme_stylebox_override(&"panel", _item_selected_style if selected else _item_style)
		var line: HBoxContainer = HBoxContainer.new()
		item.add_child(line)
		var color: Color = HUD.NAME_SELECTED_COLOR if selected else HUD.NAME_COLOR
		var who: Label = _label(StatBook.label_of(player), 19, color)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.clip_text = true
		line.add_child(who)
		var role: Label = _label(player.ratings.position, 16, DIM_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		role.custom_minimum_size.x = 56.0
		line.add_child(role)
		var overall: Label = _label(str(player.ratings.overall()), 19, color, HORIZONTAL_ALIGNMENT_RIGHT)
		overall.custom_minimum_size.x = 44.0
		line.add_child(overall)
		list.add_child(item)
	row.add_child(_player_card(team.squad[_roster_cursor]))
	return row


func _player_card(player: Player) -> Control:
	var ratings: PlayerRatings = player.ratings
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = _flat(HUD.CARD_COLOR, 18.0, 12.0)
	style.border_color = _team_tint(player.team)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	card.add_theme_stylebox_override(&"panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 3)
	card.add_child(column)

	var head: HBoxContainer = HBoxContainer.new()
	column.add_child(head)
	var who: VBoxContainer = VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_constant_override(&"separation", -2)
	head.add_child(who)
	var display: String = ratings.display_name if ratings.display_name != "" else "%s %d" % [ratings.position, player.index + 1]
	who.add_child(_label(display.to_upper(), 28, Color.WHITE))
	var number: String = "#%d   " % ratings.number if ratings.number > 0 else ""
	who.add_child(_label("%s%s   %s" % [number, ratings.position, player.team.team_name], 16, _team_tint(player.team)))
	var overall: VBoxContainer = VBoxContainer.new()
	overall.add_theme_constant_override(&"separation", -6)
	head.add_child(overall)
	overall.add_child(_label(str(ratings.overall()), 38, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	overall.add_child(_label("OVERALL", 12, DIM_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_spacer(6.0))

	for rating: Array in ratings.card_ratings():
		var text: String = rating[0]
		var value: int = rating[1]
		var key: bool = rating[2]
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 12)
		var name_label: Label = _label(text, 15, Color.WHITE if key else DIM_TEXT)
		name_label.custom_minimum_size.x = 170.0
		line.add_child(name_label)
		var bar: ProgressBar = ProgressBar.new()
		bar.max_value = 100.0
		bar.value = value
		bar.show_percentage = false
		bar.custom_minimum_size.y = 12.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override(&"background", _flat(BAR_BACK, 0.0, 0.0))
		bar.add_theme_stylebox_override(&"fill", _flat(GOLD if key else BAR_COLOR, 0.0, 0.0))
		line.add_child(bar)
		var number_label: Label = _label(str(value), 16, Color.WHITE if key else TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		number_label.custom_minimum_size.x = 34.0
		line.add_child(number_label)
		column.add_child(line)

	column.add_child(_spacer(6.0))
	column.add_child(_label("THIS GAME", 13, DIM_TEXT))
	for line: String in game.stat_book.player_summary(player):
		column.add_child(_label(line, 15, TEXT))
	var season: Season = game.season()
	var season_team: int = season.team_of(player.team.short_name) if season != null else -1
	if season_team >= 0:
		column.add_child(_spacer(6.0))
		column.add_child(_label("THIS SEASON", 13, DIM_TEXT))
		for line: String in StatBook.summary_of(season.player_line(season_team, player.index)):
			column.add_child(_label(line, 15, TEXT))
	return card


# --- Building blocks -----------------------------------------------------------------

func _build() -> void:
	_item_style = _flat(HUD.CARD_COLOR, 14.0, 8.0)
	_item_style.border_color = HUD.CARD_BORDER
	_item_style.set_border_width_all(2)
	_item_style.set_corner_radius_all(6)
	_item_selected_style = _flat(HUD.CARD_SELECTED_COLOR, 14.0, 8.0)
	_item_selected_style.border_color = HUD.CARD_SELECTED_BORDER
	_item_selected_style.set_border_width_all(2)
	_item_selected_style.set_corner_radius_all(6)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = _flat(Color(0.05, 0.06, 0.09, 0.96), 22.0, 12.0)
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5 + 20.0
	panel.offset_bottom = PANEL_SIZE.y * 0.5 + 20.0
	add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	panel.add_child(column)
	_title = _label("PAUSED", 28, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = MarginContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"margin_right", 10)
	_scroll.add_child(_body)
	_hint = _label("", 15, DIM_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_hint)

	_sound = AudioStreamPlayer.new()
	_sound.bus = AudioDirector.BUS_UI
	add_child(_sound)


# The pieces of the tables are shared with the season's screen (StatTable).

func _label(text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return StatTable.label(text, font_size, color, align)


func _spacer(height: float) -> Control:
	return StatTable.spacer(height)


func _flat(fill: Color, margin_x: float, margin_y: float) -> StyleBoxFlat:
	return StatTable.flat(fill, margin_x, margin_y)


## The team's colour, lightened enough to read on the dark panel.
func _team_tint(team: Team) -> Color:
	return team.team_color.lerp(Color.WHITE, 0.45)
