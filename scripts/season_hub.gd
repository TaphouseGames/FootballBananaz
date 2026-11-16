class_name SeasonHub
extends Control
## The season between its games, on the main menu behind SEASON: this week's
## game, the table, every team's numbers, the footballers' numbers and the
## schedule with the playoffs, a page each. With no season on it first asks
## which team the person wants.
##
## Left and right (or LB and RB) turn the pages, up and down scroll. (A) on THIS
## WEEK plays the person's game, or with none to play has the round played on
## paper; on PLAYER STATS it goes from the league's leaders through the teams.
## (Y) starts a new season, asked twice while one is still on. (B) goes back to
## the title.

## The person's game of this round is to be played now.
signal play_requested
signal closed
## The cursor or the page moved, and something was picked: for the sounds.
signal moved
signal picked
## Something the booth might have a word about: `sure` when it should not be
## left to chance.
signal remark(moment: StringName, sure: bool)

enum Mode { PICK, PAGES }
enum Page { WEEK, STANDINGS, TEAMS, PLAYERS, SCHEDULE }

const PAGE_NAMES: PackedStringArray = ["THIS WEEK", "STANDINGS", "TEAM STATS", "PLAYER STATS", "SCHEDULE"]
const SCRIM_COLOR: Color = Color(0.02, 0.04, 0.1, 0.72)
const PANEL_COLOR: Color = Color(0.04, 0.08, 0.2, 0.96)
const SOFT: Color = Color(0.86, 0.9, 1.0)
const PANEL_SIZE: Vector2 = Vector2(1120.0, 610.0)
const SCROLL_SPEED: float = 500.0
## Columns of the tables that are wider than the box score's.
const WIDE_STAT: float = 84.0
const WIDE_NAME: float = 250.0

var league: League
var mode: Mode = Mode.PAGES
var page: Page = Page.WEEK
## The team the cursor is on while one is being picked.
var pick_cursor: int = 0
## PLAYER STATS: -1 the league's leaders, otherwise the team whose footballers
## are shown.
var players_view: int = -1

var _font: SystemFont
var _title: Label
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _body: MarginContainer
var _hint: Label
## (Y) was pressed with a season on, and has to be pressed again.
var _confirm_new: bool = false
## The match is on its way: nothing more to press.
var _done: bool = false


func setup(font: SystemFont, p_league: League) -> void:
	_font = font
	league = p_league
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var scrim: ColorRect = ColorRect.new()
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StatTable.flat(PANEL_COLOR, 24.0, 14.0)
	style.border_color = MainMenu.BUTTON_BORDER
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	panel.add_child(column)
	_title = _heading("SEASON", 44, Color.WHITE)
	column.add_child(_title)
	_tabs = HBoxContainer.new()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override(&"separation", 34)
	column.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = MarginContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"margin_right", 10)
	_scroll.add_child(_body)
	_hint = _heading("", 20, Color.WHITE)
	column.add_child(_hint)


## Shows the screen: the season that is on, at THIS WEEK, or the choice of a
## team for a new one.
func open() -> void:
	_done = false
	_confirm_new = false
	visible = true
	page = Page.WEEK
	players_view = -1
	mode = Mode.PAGES if Season.current != null else Mode.PICK
	if mode == Mode.PICK:
		pick_cursor = 0
	refresh()


## Fades the screen out; it takes no more input meanwhile.
func close() -> void:
	_done = true
	ScreenFade.pop(self, false)


func _process(delta: float) -> void:
	if visible and not _done and mode == Mode.PAGES:
		_scroll.scroll_vertical += roundi(Input.get_axis(&"ui_up", &"ui_down") * SCROLL_SPEED * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _done:
		return
	var new_season: bool = event.is_action_pressed(&"jump") or (event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_N)
	if _pressed(event, &"ui_left") or event.is_action_pressed(&"page_prev"):
		_turn(-1)
	elif _pressed(event, &"ui_right") or event.is_action_pressed(&"page_next"):
		_turn(1)
	elif mode == Mode.PICK and _pressed(event, &"ui_up"):
		_move_pick(-1)
	elif mode == Mode.PICK and _pressed(event, &"ui_down"):
		_move_pick(1)
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		_confirm()
	elif event.is_action_pressed(&"back") or event.is_action_pressed(&"ui_cancel"):
		_back()
	elif new_season and mode == Mode.PAGES:
		_ask_new_season()
	else:
		return
	get_viewport().set_input_as_handled()


## A stick held over sends one event after another: only the first one counts.
func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action):
		return false
	return not event is InputEventJoypadMotion or Input.is_action_just_pressed(action)


func _turn(by: int) -> void:
	if mode != Mode.PAGES:
		return
	_confirm_new = false
	page = posmod(page + by, PAGE_NAMES.size()) as Page
	refresh()
	moved.emit()
	match page:
		Page.STANDINGS:
			remark.emit(&"standings", false)
		Page.TEAMS, Page.PLAYERS:
			remark.emit(&"stats", false)


func _move_pick(by: int) -> void:
	pick_cursor = posmod(pick_cursor + by, league.teams.size())
	refresh()
	moved.emit()
	remark.emit(&"team", false)


func _confirm() -> void:
	if mode == Mode.PICK:
		Season.start(league, pick_cursor)
		mode = Mode.PAGES
		page = Page.WEEK
		picked.emit()
		remark.emit(&"season_pick", true)
		refresh()
		return
	var season: Season = Season.current
	if _confirm_new:
		_confirm_new = false
		refresh()
		return
	if page == Page.PLAYERS:
		players_view = players_view + 1 if players_view + 1 < season.teams.size() else -1
		refresh()
		moved.emit()
		return
	if page != Page.WEEK or season.is_over():
		return
	picked.emit()
	if not season.fixture().is_empty():
		_done = true
		play_requested.emit()
		return
	# Nothing for the person to play: the round goes by on paper.
	var had_bye: bool = season.on_bye(season.user_team)
	season.finish_round()
	refresh()
	remark.emit(round_moment(season, had_bye), true)


## What the booth might say about where the season now stands for the person.
static func round_moment(season: Season, had_bye: bool = false) -> StringName:
	if season.is_over():
		return &"champion" if season.champion == season.user_team else &"season_over"
	if had_bye:
		return &"bye"
	if season.is_playoffs():
		return &"playoffs" if season.alive(season.user_team) else &"eliminated"
	return &"season_week"


func _back() -> void:
	if _confirm_new:
		_confirm_new = false
		refresh()
		return
	closed.emit()


## A new season in place of this one: at once when it is over, otherwise only
## on a second press.
func _ask_new_season() -> void:
	var season: Season = Season.current
	if season != null and not season.is_over() and not _confirm_new:
		_confirm_new = true
		refresh()
		moved.emit()
		return
	Season.clear()
	_confirm_new = false
	mode = Mode.PICK
	pick_cursor = 0
	picked.emit()
	refresh()


# --- Screens -------------------------------------------------------------------------

func refresh() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for child: Node in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0
	if mode == Mode.PICK:
		_title.text = "NEW SEASON"
		_tabs.add_child(_heading("CHOOSE YOUR TEAM FOR THE SEASON", 22, MainMenu.GOLD))
		_hint.text = "UP / DOWN  CHOOSE TEAM          (A)  START THE SEASON          (B)  BACK"
		_body.add_child(_pick_view())
		return
	var season: Season = Season.current
	_title.text = "SEASON  -  %s" % ("FINAL STANDINGS" if season.is_over() else season.round_name())
	for i: int in PAGE_NAMES.size():
		_tabs.add_child(_heading(PAGE_NAMES[i], 22, MainMenu.GOLD if i == page else Color(1.0, 1.0, 1.0, 0.45)))
	var action: String = ""
	match page:
		Page.WEEK:
			_body.add_child(_week_view(season))
			if not season.is_over():
				action = "(A)  PLAY          " if not season.fixture().is_empty() else "(A)  SIMULATE THE ROUND          "
		Page.STANDINGS:
			_body.add_child(_standings_view(season))
		Page.TEAMS:
			_body.add_child(_teams_view(season))
		Page.PLAYERS:
			_body.add_child(_players_view(season))
			action = "(A)  LEADERS / NEXT TEAM          "
		Page.SCHEDULE:
			_body.add_child(_schedule_view(season))
	_hint.text = "%s(LB) (RB)  PAGE          (Y)  NEW SEASON          (B)  BACK" % action
	if _confirm_new:
		_hint.text = "THROW THIS SEASON AWAY?          (Y)  YES, A NEW SEASON          (B)  NO"


## The league's teams and what each is good at, the cursor on one.
func _pick_view() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	for i: int in league.teams.size():
		var team: TeamData = league.teams[i]
		var selected: bool = i == pick_cursor
		var panel: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = StatTable.flat(Color(1.0, 1.0, 1.0, 0.14 if selected else 0.05), 16.0, 8.0)
		style.border_color = Color.WHITE if selected else StatTable.CLEAR
		style.set_border_width_all(3)
		style.set_corner_radius_all(10)
		panel.add_theme_stylebox_override(&"panel", style)
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 18)
		panel.add_child(line)
		line.add_child(_chip(team.team_color, Vector2(18.0, 44.0)))
		var name_label: Label = _heading(team.team_name.to_upper(), 34, Color.WHITE if selected else SOFT)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var ratings: Array[Array] = team.roster.team_ratings() if team.roster != null else []
		for rating: Array in ratings:
			var text: String = rating[0]
			var value: int = rating[1]
			var cell: Label = StatTable.label("%s  %d" % [text, value], 18, Color.WHITE if selected else StatTable.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
			cell.custom_minimum_size.x = 140.0
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(cell)
		column.add_child(panel)
	return column


## The person's game of the round, the round's other games and the last
## round's scores; once the season is over, who won the cup.
func _week_view(season: Season) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	var mine: int = season.user_team
	if season.is_over():
		column.add_child(_heading(Season.CUP_NAME, 30, MainMenu.GOLD))
		column.add_child(_heading("%s ARE THE CHAMPIONS" % season.team_data(season.champion).team_name.to_upper(), 54, _tint(season.champion)))
		var yours: String = "THAT IS YOUR TEAM. WELL PLAYED." if season.champion == mine else "YOUR %s FINISHED %s IN THE TABLE, %s." % [season.team_data(mine).team_name.to_upper(), _ordinal(season.place_of(mine)), season.record_text(mine)]
		column.add_child(_heading(yours, 24, Color.WHITE))
		column.add_child(StatTable.spacer(10.0))
	else:
		var fixture: Array = season.fixture()
		column.add_child(_heading(season.round_name(), 28, MainMenu.GOLD))
		if not fixture.is_empty():
			column.add_child(_matchup(season, fixture[0], fixture[1], 46))
			column.add_child(_heading("YOU ARE %s, %s" % [season.team_data(mine).team_name.to_upper(), "AT HOME" if fixture[0] == mine else "AWAY"], 20, SOFT))
		elif season.on_bye(mine):
			column.add_child(_heading("FIRST SEED: YOUR %s HAVE THE WEEK OFF" % season.team_data(mine).team_name.to_upper(), 36, _tint(mine)))
			column.add_child(_heading("THE WINNER OF THE SEMIFINAL COMES TO YOUR GROUND FOR %s" % Season.CUP_NAME, 20, SOFT))
		else:
			column.add_child(_heading("YOUR SEASON IS OVER", 36, Color.WHITE))
			column.add_child(_heading("%s FINISHED %s IN THE TABLE, %s" % [season.team_data(mine).team_name.to_upper(), _ordinal(season.place_of(mine)), season.record_text(mine)], 20, SOFT))
		column.add_child(StatTable.spacer(10.0))
		var others: Array[Array] = []
		for game: Array in season.round_games():
			if game != fixture:
				others.append(game)
		if not others.is_empty():
			column.add_child(_heading("ALSO IN THIS ROUND" if not fixture.is_empty() else "IN THIS ROUND", 20, MainMenu.BUTTON_BORDER))
			for game: Array in others:
				column.add_child(_matchup(season, game[0], game[1], 24))
			column.add_child(StatTable.spacer(10.0))
	var last: int = season.current_round() - 1 if not season.is_over() else Season.FINAL_ROUND
	var scores: Array[Dictionary] = season.results_of_round(last)
	if not scores.is_empty():
		column.add_child(_heading("%s: FINAL SCORES" % season.round_name(last), 20, MainMenu.BUTTON_BORDER))
		for result: Dictionary in scores:
			column.add_child(_score_line(season, result, 24))
	return column


## The table, a line under the last place that goes to the playoffs.
func _standings_view(season: Season) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	column.custom_minimum_size.x = 860.0
	var rows: Array[PackedStringArray] = SeasonTables.standings_rows(season)
	var table: Array[Dictionary] = season.standings()
	column.add_child(StatTable.row(SeasonTables.STANDINGS_HEAD, StatTable.HEAD_COLOR, StatTable.DIM_TEXT, 16, WIDE_STAT, WIDE_NAME))
	for i: int in rows.size():
		var color: Color = MainMenu.GOLD if table[i]["team"] == season.user_team else Color.WHITE
		column.add_child(StatTable.row(rows[i], StatTable.ROW_COLOR if i % 2 == 1 else StatTable.CLEAR, color, 24, WIDE_STAT, WIDE_NAME))
		if i == Season.PLAYOFF_TEAMS - 1:
			var cut: ColorRect = ColorRect.new()
			cut.color = MainMenu.BUTTON_BORDER
			cut.custom_minimum_size.y = 3.0
			column.add_child(cut)
	column.add_child(StatTable.spacer(14.0))
	var note: String = "THE TOP THREE GO TO THE PLAYOFFS. FIRST PLACE HAS THE FIRST WEEK OFF,\nSECOND HOSTS THIRD, AND THE WINNER PLAYS FIRST PLACE FOR %s." % Season.CUP_NAME
	if season.is_playoffs() or season.is_over():
		note = "THE REGULAR SEASON IS OVER. SEEDS: 1. %s   2. %s   3. %s" % [season.teams[season.seeds[0]], season.teams[season.seeds[1]], season.teams[season.seeds[2]]]
	column.add_child(_heading(note, 18, SOFT))
	return _centered(column)


func _teams_view(season: Season) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	column.custom_minimum_size.x = 1040.0
	var rows: Array[PackedStringArray] = SeasonTables.team_rows(season)
	var table: Array[Dictionary] = season.standings()
	column.add_child(StatTable.row(SeasonTables.TEAMS_HEAD, StatTable.HEAD_COLOR, StatTable.DIM_TEXT, 16, WIDE_STAT, WIDE_NAME))
	for i: int in rows.size():
		var color: Color = MainMenu.GOLD if table[i]["team"] == season.user_team else Color.WHITE
		column.add_child(StatTable.row(rows[i], StatTable.ROW_COLOR if i % 2 == 1 else StatTable.CLEAR, color, 22, WIDE_STAT, WIDE_NAME))
	column.add_child(StatTable.spacer(14.0))
	column.add_child(_heading("A GAME: POINTS, YARDS, PASSING, RUSHING, POINTS ALLOWED.\nALL SEASON: GIVEAWAYS, THIRD DOWNS MADE, TIMES SACKED. PLAYOFF GAMES COUNT.", 18, SOFT))
	return _centered(column)


## The league's leaders, or one team's footballers: passing and rushing on the
## left, receiving and defense on the right.
func _players_view(season: Season) -> Control:
	var whole: VBoxContainer = VBoxContainer.new()
	whole.add_theme_constant_override(&"separation", 8)
	var team: int = players_view
	var heading: String = "LEAGUE LEADERS" if team < 0 else season.team_data(team).team_name.to_upper()
	whole.add_child(_heading(heading, 26, Color.WHITE if team < 0 else _tint(team)))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 28)
	whole.add_child(row)
	var kinds: Array[Array] = [[SeasonTables.Leaders.PASSING, SeasonTables.Leaders.RUSHING], [SeasonTables.Leaders.RECEIVING, SeasonTables.Leaders.TACKLES]]
	for side: Array in kinds:
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override(&"separation", 3)
		row.add_child(column)
		for kind: SeasonTables.Leaders in side:
			var rows: Array[PackedStringArray] = SeasonTables.leader_rows(season, kind) if team < 0 else SeasonTables.roster_rows(season, team, kind)
			var strong: Array[int] = []
			var marked: Array[int] = []
			if team >= 0:
				strong.append(rows.size() - 1)
			else:
				# The person's own footballers stand out among the leaders.
				for i: int in rows.size():
					if rows[i][0].ends_with("  " + season.teams[season.user_team]):
						marked.append(i)
			StatTable.add(column, SeasonTables.title(kind), MainMenu.BUTTON_BORDER, SeasonTables.head(kind), rows, strong, marked, 50.0, 190.0)
			if rows.is_empty():
				column.add_child(StatTable.label("Nobody yet", 15, StatTable.DIM_TEXT))
	return whole


## The person's ten games, then the playoffs.
func _schedule_view(season: Season) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	column.custom_minimum_size.x = 760.0
	var mine: int = season.user_team
	column.add_child(_heading("%s  %s" % [season.team_data(mine).team_name.to_upper(), season.record_text(mine)], 26, _tint(mine)))
	for week: int in Season.WEEKS:
		for game: Array in season.schedule[week]:
			if game[0] != mine and game[1] != mine:
				continue
			var home: bool = game[0] == mine
			var other: int = game[1] if home else game[0]
			var result: Dictionary = season.result_of(week, game[0], game[1])
			var outcome: String = "NOW" if season.phase == Season.Phase.REGULAR and week == season.week else ""
			var color: Color = MainMenu.GOLD if outcome != "" else StatTable.TEXT
			if not result.is_empty():
				var own_score: int = result["home_score"] if home else result["away_score"]
				var their_score: int = result["away_score"] if home else result["home_score"]
				outcome = "%s  %d - %d%s" % ["W" if own_score > their_score else "L", own_score, their_score, "  OT" if result["overtime"] else ""]
				color = Color.WHITE
			var panel: PanelContainer = PanelContainer.new()
			panel.add_theme_stylebox_override(&"panel", StatTable.flat(StatTable.ROW_COLOR if week % 2 == 1 else StatTable.CLEAR, 6.0, 1.0))
			var line: HBoxContainer = HBoxContainer.new()
			panel.add_child(line)
			var when: Label = StatTable.label("WEEK %d" % (week + 1), 20, color)
			when.custom_minimum_size.x = 120.0
			line.add_child(when)
			var who: Label = StatTable.label("%s  %s" % ["VS" if home else "AT", season.team_data(other).team_name.to_upper()], 20, color)
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(who)
			line.add_child(StatTable.label(outcome, 20, color, HORIZONTAL_ALIGNMENT_RIGHT))
			column.add_child(panel)
	column.add_child(StatTable.spacer(14.0))
	column.add_child(_heading("PLAYOFFS", 26, MainMenu.GOLD))
	if season.seeds.size() < Season.PLAYOFF_TEAMS:
		column.add_child(_heading("SEMIFINAL: THIRD PLACE AT SECOND PLACE\n%s: THE WINNER AT FIRST PLACE" % Season.CUP_NAME, 20, SOFT))
		return _centered(column)
	var semifinal: Dictionary = season.result_of(Season.SEMIFINAL_ROUND, season.seeds[1], season.seeds[2])
	column.add_child(_heading("SEMIFINAL", 18, MainMenu.BUTTON_BORDER))
	column.add_child(_score_line(season, semifinal, 24) if not semifinal.is_empty() else _matchup(season, season.seeds[1], season.seeds[2], 24))
	column.add_child(_heading(Season.CUP_NAME, 18, MainMenu.BUTTON_BORDER))
	if season.semifinal_winner < 0:
		column.add_child(_heading("THE WINNER  AT  %s" % season.team_data(season.seeds[0]).team_name.to_upper(), 24, Color.WHITE))
	else:
		var final: Dictionary = season.result_of(Season.FINAL_ROUND, season.seeds[0], season.semifinal_winner)
		column.add_child(_score_line(season, final, 24) if not final.is_empty() else _matchup(season, season.seeds[0], season.semifinal_winner, 24))
	return _centered(column)


# --- Building blocks -----------------------------------------------------------------

## "COCONUTS (4-2)  AT  BANANAZ (5-1)", each in its colour.
func _matchup(season: Season, home: int, away: int, font_size: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", roundi(font_size * 0.5))
	row.add_child(_team_label(season, away, font_size))
	row.add_child(_heading("AT", roundi(font_size * 0.6), MainMenu.BUTTON_BORDER))
	row.add_child(_team_label(season, home, font_size))
	return row


func _team_label(season: Season, team: int, font_size: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", roundi(font_size * 0.3))
	row.add_child(_chip(season.team_data(team).team_color, Vector2(font_size * 0.3, font_size * 0.9)))
	row.add_child(_heading(season.team_data(team).team_name.to_upper(), font_size, MainMenu.GOLD if team == season.user_team else Color.WHITE))
	var seed: int = season.seeds.find(team)
	var record: String = season.record_text(team) if seed < 0 else "#%d, %s" % [seed + 1, season.record_text(team)]
	row.add_child(_heading("(%s)" % record, roundi(font_size * 0.6), SOFT))
	return row


## "COCONUTS 34  -  BANANAZ 42", the winner in white.
func _score_line(season: Season, result: Dictionary, font_size: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", roundi(font_size * 0.5))
	var winner: int = Season.winner_of(result)
	for side: String in ["away", "home"]:
		var team: int = result[side]
		var color: Color = MainMenu.GOLD if team == season.user_team else (Color.WHITE if team == winner else Color(1.0, 1.0, 1.0, 0.5))
		row.add_child(_chip(season.team_data(team).team_color, Vector2(font_size * 0.3, font_size * 0.9)))
		row.add_child(_heading("%s  %d" % [season.team_data(team).team_name.to_upper(), result[side + "_score"]], font_size, color))
		if side == "away":
			row.add_child(_heading("AT", roundi(font_size * 0.6), MainMenu.BUTTON_BORDER))
	if result["overtime"]:
		row.add_child(_heading("OT", roundi(font_size * 0.6), SOFT))
	return row


func _chip(color: Color, chip_size: Vector2) -> Control:
	var chip: Panel = Panel.new()
	chip.custom_minimum_size = chip_size
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	chip.add_theme_stylebox_override(&"panel", style)
	return chip


func _centered(inner: Control) -> Control:
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(inner)
	return center


## The team's colour, lightened enough to read on the dark panel.
func _tint(team: int) -> Color:
	return Season.current.team_data(team).team_color.lerp(Color.WHITE, 0.45)


func _ordinal(place: int) -> String:
	return ["FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH", "LAST"][clampi(place - 1, 0, 5)]


## A line in the menu's heavy font, centred.
func _heading(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label
