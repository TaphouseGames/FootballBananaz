class_name OnlineLobby
extends Control
## The screen between ONLINE and an online match. First the person's team: up
## and down go through the league's teams, (A) starts the search and (B) goes
## back. Then the search for an opponent, with the time it has taken so far;
## (B) calls it off, back to the team. When the matchmaker has a match, `ready_to_play` says
## where it is and the main menu goes there. When it has none to offer, the
## screen says why, and any button goes back to the team.
##
## Both people pick their team before they are put together, so they can come
## with the same one: the server then gives the away side its other kit.

## A match is found: its server, what lets this person in there, and their team.
signal ready_to_play(address: String, port: int, match_pass: String, team: int)
signal cancelled
## The team changed (the click).
signal moved
## A search was started or called off (the confirm sound).
signal picked

enum Stage { TEAM, SEARCHING, FOUND, FAILED }

const PANEL_SIZE: Vector2 = Vector2(420.0, 250.0)
const RATING_COUNT: int = 4
const DIM: Color = Color(0.86, 0.9, 1.0)

var stage: Stage = Stage.TEAM
## The person's team, as a place in the league's teams.
var pick: int = 0
## Seconds the search has taken.
var waited: float = 0.0
var matchmaker: Matchmaker

var _font: SystemFont
var _teams: Array[TeamData] = []
var _header: Label
var _panel_style: StyleBoxFlat
var _fill: StyleBoxFlat
var _short_label: Label
var _name_label: Label
var _bar_fill: StyleBoxFlat
var _bars: Array[ProgressBar] = []
var _rating_names: Array[Label] = []
var _rating_numbers: Array[Label] = []
var _status: Label
var _clock: Label
var _hint: Label
## The sticks held over right now, by gamepad and way.
var _held: Dictionary[String, bool] = {}


## `teams` is every team there is to pick; `finder` whoever finds the matches
## (null: this machine is not set up for any, and the screen says so).
func setup(font: SystemFont, teams: Array[TeamData], finder: Matchmaker) -> void:
	_font = font
	_teams = teams
	matchmaker = finder
	if matchmaker != null:
		add_child(matchmaker)
		matchmaker.found.connect(_on_found)
		matchmaker.failed.connect(_on_failed)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var scrim: ColorRect = ColorRect.new()
	scrim.color = TeamSelect.SCRIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 22)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	_header = _label("ONLINE  -  QUICK MATCH", 58, Color.WHITE, 12)
	column.add_child(_header)
	var holder: CenterContainer = CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_build_panel())
	column.add_child(holder)
	_status = _label("", 34, MainMenu.GOLD, 10)
	_status.custom_minimum_size = Vector2(900.0, 96.0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_clock = _label("", 44, Color.WHITE, 10)
	_clock.custom_minimum_size.y = 52.0
	column.add_child(_clock)
	_hint = _label("", 22, Color.WHITE, 6)
	column.add_child(_hint)


## Shows the screen at the choice of team.
func open() -> void:
	_held.clear()
	visible = true
	_show(Stage.TEAM)


## Fades the screen out; a search that is on is called off.
func close() -> void:
	if stage == Stage.SEARCHING:
		matchmaker.cancel()
	stage = Stage.FOUND
	ScreenFade.pop(self, false)


func _process(delta: float) -> void:
	if not visible or stage != Stage.SEARCHING:
		return
	waited += delta
	@warning_ignore("integer_division")
	_clock.text = "%d:%02d" % [int(waited) / 60, int(waited) % 60]


func _unhandled_input(event: InputEvent) -> void:
	if not visible or stage == Stage.FOUND:
		return
	var confirm: bool = event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept")
	var back: bool = event.is_action_pressed(&"back") or event.is_action_pressed(&"ui_cancel")
	if stage == Stage.TEAM and _pressed(event, &"ui_up"):
		_cycle(-1)
	elif stage == Stage.TEAM and _pressed(event, &"ui_down"):
		_cycle(1)
	elif stage == Stage.TEAM and confirm:
		_search()
	elif stage == Stage.TEAM and back:
		cancelled.emit()
	elif stage == Stage.SEARCHING and back:
		matchmaker.cancel()
		picked.emit()
		_show(Stage.TEAM)
	elif stage == Stage.FAILED and (confirm or back):
		picked.emit()
		_show(Stage.TEAM)
	else:
		return
	get_viewport().set_input_as_handled()


## A stick held over sends one event after another: only the first one of each
## gamepad counts.
func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event is InputEventJoypadMotion:
		return event.is_action_pressed(action)
	if not event.is_action(action):
		return false
	var key: String = "%d/%s" % [event.device, action]
	var down: bool = event.is_action_pressed(action)
	var was: bool = _held.get(key, false)
	_held[key] = down
	return down and not was


func _cycle(by: int) -> void:
	if _teams.size() < 2:
		return
	pick = posmod(pick + by, _teams.size())
	_show_team()
	moved.emit()


func _search() -> void:
	picked.emit()
	if matchmaker == null:
		_on_failed("Online play is not set up on this machine.")
		return
	waited = 0.0
	_clock.text = "0:00"
	_show(Stage.SEARCHING)
	matchmaker.search()


func _on_found(address: String, port: int, match_pass: String) -> void:
	if stage != Stage.SEARCHING:
		return
	_show(Stage.FOUND)
	ready_to_play.emit(address, port, match_pass, pick)


func _on_failed(reason: String) -> void:
	_show(Stage.FAILED)
	_status.text = reason


func _show(to: Stage) -> void:
	stage = to
	_show_team()
	# Empty, not hidden: nothing on the screen moves when it comes up.
	if to != Stage.SEARCHING and to != Stage.FOUND:
		_clock.text = ""
	match to:
		Stage.TEAM:
			_status.text = "CHOOSE YOUR TEAM"
			_hint.text = "UP / DOWN  CHANGE TEAM          (A)  FIND A MATCH          (B)  BACK"
		Stage.SEARCHING:
			_status.text = "LOOKING FOR AN OPPONENT"
			_hint.text = "(B)  CANCEL"
		Stage.FOUND:
			_status.text = "OPPONENT FOUND!"
			_hint.text = ""
		Stage.FAILED:
			_hint.text = "(A)  OK"


func _show_team() -> void:
	var team: TeamData = _teams[pick]
	_fill.bg_color = team.team_color
	_panel_style.border_color = Color.WHITE if stage == Stage.TEAM else team.team_color
	_short_label.text = team.short_name
	_name_label.text = team.team_name.to_upper()
	# A dark team colour would not show against the panel.
	_bar_fill.bg_color = Team.marker_of(team.team_color)
	var ratings: Array[Array] = team.roster.team_ratings() if team.roster != null else []
	for row: int in RATING_COUNT:
		var value: int = ratings[row][1] if row < ratings.size() else 0
		_bars[row].value = value
		_rating_names[row].text = ratings[row][0] if row < ratings.size() else ""
		_rating_numbers[row].text = str(value)


# --- Building blocks -----------------------------------------------------------------

func _build_panel() -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = TeamSelect.PANEL_COLOR
	_panel_style.set_border_width_all(5)
	_panel_style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override(&"panel", _panel_style)

	var block: Panel = Panel.new()
	_fill = StyleBoxFlat.new()
	_fill.set_corner_radius_all(8)
	block.add_theme_stylebox_override(&"panel", _fill)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.position = Vector2(14.0, 14.0)
	block.size = Vector2(PANEL_SIZE.x - 28.0, 100.0)
	panel.add_child(block)
	_short_label = _label("", 62, Color.WHITE, 12)
	_short_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	block.add_child(_short_label)
	_name_label = _label("", 24, DIM, 0)
	_name_label.position = Vector2(0.0, 115.0)
	_name_label.size = Vector2(PANEL_SIZE.x, 30.0)
	panel.add_child(_name_label)

	_bar_fill = StyleBoxFlat.new()
	_bar_fill.set_corner_radius_all(3)
	var bar_back: StyleBoxFlat = StyleBoxFlat.new()
	bar_back.bg_color = TeamSelect.BAR_BACK
	bar_back.set_corner_radius_all(3)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.position = Vector2(22.0, 152.0)
	rows.size = Vector2(PANEL_SIZE.x - 44.0, 20.0 * float(RATING_COUNT))
	panel.add_child(rows)
	for row: int in RATING_COUNT:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 10)
		line.custom_minimum_size.y = 20.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(line)
		var name_label: Label = _label("", 15, DIM, 0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.custom_minimum_size.x = 84.0
		line.add_child(name_label)
		var bar: ProgressBar = ProgressBar.new()
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override(&"background", bar_back)
		bar.add_theme_stylebox_override(&"fill", _bar_fill)
		line.add_child(bar)
		var number_label: Label = _label("", 16, Color.WHITE, 0)
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number_label.custom_minimum_size.x = 28.0
		line.add_child(number_label)
		_bars.append(bar)
		_rating_names.append(name_label)
		_rating_numbers.append(number_label)
	return panel


func _label(text: String, font_size: int, color: Color, outline: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	if outline > 0:
		label.add_theme_color_override(&"font_outline_color", MainMenu.OUTLINE)
		label.add_theme_constant_override(&"outline_size", outline)
	return label
