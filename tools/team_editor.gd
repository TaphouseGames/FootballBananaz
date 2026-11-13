class_name TeamEditor
extends Control
## Developer tool, not part of the game: every team of the league on the left,
## and on the right the one picked there, to rename, recolour and re-rate.
## Run tools/team_editor.tscn by itself (F6). Edits stay in memory until Save
## (Ctrl+S), which writes them to the team's and its roster's .tres file.
##
## The team's players are shown one of two ways: "Ratings", everybody's
## numbers side by side, and "Player models", one player's model (see
## PlayerModel) with everything his PlayerLook sets next to it.
##
## Who plays where is fixed: every play lists its assignments by roster slot
## (see Roster), so positions are shown and not changed here.

const LEAGUE_PATH: String = "res://resources/league.tres"
const BACK_COLOR: Color = Color(0.09, 0.1, 0.13)
const HEAD_COLOR: Color = Color(0.62, 0.68, 0.8)
const KEY_COLOR: Color = Color(0.98, 0.82, 0.35)
const WARN_COLOR: Color = Color(1.0, 0.6, 0.3)
const BAR_BACK: Color = Color(1.0, 1.0, 1.0, 0.12)
const LIST_WIDTH: float = 190.0
const COLUMN_WIDTH: float = 112.0
const SWATCH_SIZE: int = 22
## How faint a rating is that the player's position has no use for.
const UNUSED_ALPHA: float = 0.4
const LOOK_PANEL_WIDTH: float = 340.0
const PREVIEW_BACK: Color = Color(0.16, 0.19, 0.24)
## The preview's camera: how far a drag of one pixel turns it, how far it may
## tip, and how near and far the wheel takes it, in metres.
const ORBIT_PER_PIXEL: float = 0.01
const PITCH_LIMIT: float = 1.2
const ZOOM_NEAR: float = 0.7
const ZOOM_FAR: float = 7.0

@export var league: League

## Everything of a PlayerLook there is to set, in the order shown: its
## property, what it is called, and what sets it. A slider gives its lowest
## and highest value and its step; a choice gives its names, which for the
## hair depend on the base model.
var look_fields: Array[Dictionary] = [
	{"property": &"base", "label": "Base model", "choices": PlayerLook.BASE_NAMES},
	{"property": &"height_in", "label": "Height", "slider": [PlayerLook.HEIGHT_MIN, PlayerLook.HEIGHT_MAX, 1]},
	{"property": &"weight_lb", "label": "Weight", "slider": [PlayerLook.WEIGHT_MIN, PlayerLook.WEIGHT_MAX, 5]},
	{"property": &"skin_color", "label": "Skin", "presets": PlayerLook.SKIN_PRESETS},
	{"property": &"forehead_size", "label": "Forehead", "slider": [0.0, 1.0, 0.01]},
	{"property": &"chin_size", "label": "Chin", "slider": [0.0, 1.0, 0.01]},
	{"property": &"hair_style", "label": "Hair", "choices": PackedStringArray()},
	{"property": &"hair_color", "label": "Hair colour", "presets": PlayerLook.HAIR_PRESETS},
	{"property": &"facial_hair", "label": "Facial hair", "choices": PlayerLook.FACIAL_HAIR_NAMES},
	{"property": &"eye_type", "label": "Eyes", "choices": PlayerLook.EYE_NAMES},
	{"property": &"glasses", "label": "Glasses", "choices": PlayerLook.GLASSES_NAMES},
	{"property": &"eyepatch_side", "label": "Eyepatch on", "choices": PlayerLook.SIDE_NAMES},
	{"property": &"nose_type", "label": "Nose", "choices": PlayerLook.NOSE_NAMES},
	{"property": &"nose_size", "label": "Nose size", "slider": [0.0, 1.0, 0.01]},
	{"property": &"mouth_type", "label": "Mouth", "choices": PlayerLook.MOUTH_NAMES},
	{"property": &"mouth_size", "label": "Mouth size", "slider": [0.0, 1.0, 0.01]},
]

## Tests: when set, Save writes copies into this folder and leaves the files
## in resources/ alone.
var save_dir: String = ""
## The place in the league's teams of the one being edited.
var selected: int = -1
## Per team: edited since it was last saved or reverted.
var dirty: Array[bool] = []

var team_list: ItemList
var name_edit: LineEdit
var short_edit: LineEdit
var color_button: ColorPickerButton
## The team's ratings (see Roster.team_ratings()).
var rating_bars: Array[ProgressBar] = []
## Per player of the team shown.
var player_name_edits: Array[LineEdit] = []
var number_spins: Array[SpinBox] = []
var overall_labels: Array[Label] = []
## Per player: rating name (StringName) -> its SpinBox.
var rating_spins: Array[Dictionary] = []
var status: Label

## The "Player models" view: which player of the team shown it shows, the
## list he is picked from, his model, and per property of his PlayerLook the
## control that sets it (an OptionButton, an HSlider or a ColorPickerButton).
var selected_player: int = 0
var player_list: ItemList
var model: PlayerModel
var look_controls: Dictionary[StringName, Control] = {}
var ratings_button: Button
var models_button: Button

var _ratings_view: Control
var _models_view: Control
var _look_values: Dictionary[StringName, Label] = {}
var _preview: SubViewport
var _camera: Camera3D
var _camera_yaw: float = 0.35
var _camera_pitch: float = 0.08
var _camera_distance: float = 4.2
## Whether the camera looks at the head or at the whole player.
var _camera_on_face: bool = false
## Set while the controls are being filled in, so that does not count as an edit.
var _filling: bool = false

var _rating_names: Array[Label] = []
var _rating_numbers: Array[Label] = []
var _bar_fill: StyleBoxFlat
var _grid: GridContainer
var _quit_dialog: ConfirmationDialog


func _ready() -> void:
	# Closing the window with edits not saved asks first.
	get_tree().auto_accept_quit = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if league == null:
		league = load(LEAGUE_PATH)
	dirty.resize(league.teams.size())
	dirty.fill(false)
	_build()
	for i: int in league.teams.size():
		team_list.add_item("")
		_refresh_list_item(i)
	if not league.teams.is_empty():
		select_team(0)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if dirty.has(true):
		_quit_dialog.popup_centered()
	else:
		get_tree().quit()


## Shows the team at `index` of the league's teams. Edits to the one shown
## before stay in memory, marked in the list.
func select_team(index: int) -> void:
	selected = index
	team_list.select(index)
	_show_team()
	_show_status(_problems(), true)


## Writes every edited team and its roster to their files. False if one of
## them could not be written.
func save_all() -> bool:
	var saved: int = 0
	for i: int in league.teams.size():
		if not dirty[i]:
			continue
		var team: TeamData = league.teams[i]
		var error: Error = OK
		if _has_own_file(team.roster):
			error = ResourceSaver.save(team.roster, _save_path(team.roster))
		if error == OK:
			error = ResourceSaver.save(team, _save_path(team))
		if error != OK:
			_show_status("Could not save %s: %s" % [team.short_name, error_string(error)], true)
			return false
		dirty[i] = false
		_refresh_list_item(i)
		saved += 1
	_refresh_derived()
	var problems: String = _problems()
	if problems != "":
		_show_status("Saved, but: %s" % problems, true)
	elif saved == 0:
		_show_status("Nothing to save", false)
	else:
		_show_status("Saved %d team%s" % [saved, "" if saved == 1 else "s"], false)
	return true


## Puts the team shown back to what its files say.
func revert_selected() -> void:
	if selected < 0:
		return
	var team: TeamData = _team()
	var fresh_team: TeamData = ResourceLoader.load(team.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as TeamData
	if fresh_team != null:
		team.team_name = fresh_team.team_name
		team.short_name = fresh_team.short_name
		team.team_color = fresh_team.team_color
	if _has_own_file(team.roster):
		var fresh: Roster = ResourceLoader.load(team.roster.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Roster
		if fresh != null:
			for i: int in mini(fresh.players.size(), team.roster.players.size()):
				_copy_values(fresh.players[i], team.roster.players[i])
	dirty[selected] = false
	_show_team()
	_show_status("Reverted %s" % team.short_name, false)


# --- Edits ---------------------------------------------------------------------------

func _on_team_name_changed(text: String) -> void:
	_team().team_name = text
	_touch()


## The scoreboard, the end zones and the stat names take the short name as it
## is written, so it is kept in capitals.
func _on_short_name_changed(text: String) -> void:
	var upper: String = text.to_upper()
	if upper != text:
		var caret: int = short_edit.caret_column
		short_edit.text = upper
		short_edit.caret_column = caret
	_team().short_name = upper
	_touch()


func _on_color_changed(color: Color) -> void:
	_team().team_color = color
	_touch()


func _on_player_name_changed(text: String, index: int) -> void:
	_team().roster.players[index].display_name = text
	_touch()


func _on_number_changed(value: float, index: int) -> void:
	_team().roster.players[index].number = roundi(value)
	_touch()


func _on_rating_changed(value: float, index: int, rating: StringName) -> void:
	_team().roster.players[index].set(rating, roundi(value))
	_touch()


## Shows the ratings of the team's players (false) or their models (true).
func show_models(models: bool) -> void:
	_ratings_view.visible = not models
	_models_view.visible = models
	ratings_button.set_pressed_no_signal(not models)
	models_button.set_pressed_no_signal(models)
	if models:
		_show_player()


## Shows the model of the player at `index` of the team's roster.
func select_player(index: int) -> void:
	selected_player = index
	player_list.select(index)
	_show_player()


## The look of the player whose model is shown. A player nobody has given one
## gets the one made up from his name, to start from.
func look() -> PlayerLook:
	var player: PlayerRatings = _player()
	if player == null:
		return null
	if player.look == null:
		player.look = player.look_or_default()
	return player.look


## A new look out of the hat for the player shown.
func randomize_look() -> void:
	var player: PlayerRatings = _player()
	if player == null:
		return
	player.look = PlayerLook.random(randi(), player.position)
	_show_player()
	_touch()


func _on_look_choice(index: int, property: StringName) -> void:
	_set_look(property, index)


func _on_look_slider(value: float, property: StringName) -> void:
	var slider: HSlider = look_controls[property] as HSlider
	_set_look(property, roundi(value) if slider.step >= 1.0 else value)


func _on_look_color(color: Color, property: StringName) -> void:
	_set_look(property, color)


func _set_look(property: StringName, value: Variant) -> void:
	if _filling or look() == null:
		return
	look().set(property, value)
	if property == &"base":
		# The other base has other hairstyles: the same place in its list.
		_fill_look_controls()
	_refresh_look_notes()
	_touch()


## Something of the team shown was edited.
func _touch() -> void:
	dirty[selected] = true
	_refresh_derived()
	_refresh_list_item(selected)
	_refresh_player_list()
	_refresh_model()
	var problems: String = _problems()
	if problems != "":
		_show_status(problems, true)
	else:
		_show_status("Unsaved changes  -  Ctrl+S saves", false)


## What is wrong with the team shown, or "". Nothing here stops a save.
func _problems() -> String:
	if selected < 0:
		return ""
	var team: TeamData = _team()
	if team.team_name.strip_edges() == "":
		return "The team has no name"
	if team.short_name.strip_edges() == "":
		return "The team has no short name"
	# League.find() and the stat names go by the short name.
	for i: int in league.teams.size():
		if i != selected and league.teams[i].short_name.to_lower() == team.short_name.to_lower():
			return "%s is also the short name of %s" % [team.short_name, league.teams[i].team_name]
	return ""


# --- Showing -------------------------------------------------------------------------

func _team() -> TeamData:
	return league.teams[selected]


func _show_team() -> void:
	var team: TeamData = _team()
	name_edit.text = team.team_name
	short_edit.text = team.short_name
	color_button.color = team.team_color
	_build_grid()
	_refresh_derived()
	_refresh_list_item(selected)
	player_list.clear()
	var count: int = team.roster.players.size() if team.roster != null else 0
	for i: int in count:
		player_list.add_item("")
	_refresh_player_list()
	selected_player = clampi(selected_player, 0, maxi(count - 1, 0))
	if count > 0:
		player_list.select(selected_player)
	if _models_view.visible:
		_show_player()


## The player whose model is shown, or null for a team without one.
func _player() -> PlayerRatings:
	var roster: Roster = _team().roster if selected >= 0 else null
	if roster == null or selected_player < 0 or selected_player >= roster.players.size():
		return null
	return roster.players[selected_player]


func _refresh_player_list() -> void:
	var roster: Roster = _team().roster
	if roster == null:
		return
	for i: int in mini(player_list.item_count, roster.players.size()):
		var player: PlayerRatings = roster.players[i]
		player_list.set_item_text(i, "%2d  %s  -  %s" % [player.number, player.display_name, player.position])


## The model and the controls, for the player picked.
func _show_player() -> void:
	_fill_look_controls()
	_refresh_look_notes()
	_refresh_model()
	_place_camera()


func _refresh_model() -> void:
	var player: PlayerRatings = _player()
	model.visible = player != null
	if player == null or not _models_view.visible:
		return
	model.show_look(look(), _team().team_color, player.number, player.display_name)


## Puts every control at what the look says, without that counting as an edit.
func _fill_look_controls() -> void:
	var shown: PlayerLook = look()
	if shown == null:
		return
	_filling = true
	for field: Dictionary in look_fields:
		var property: StringName = field["property"]
		var control: Control = look_controls[property]
		if control is OptionButton:
			var option: OptionButton = control as OptionButton
			if property == &"hair_style":
				option.clear()
				for style: String in PlayerLook.HAIR_NAMES[shown.base]:
					option.add_item(style)
			var index: int = shown.get(property)
			option.select(clampi(index, 0, option.item_count - 1))
		elif control is HSlider:
			var number: float = shown.get(property)
			(control as HSlider).value = number
		elif control is ColorPickerButton:
			var color: Color = shown.get(property)
			(control as ColorPickerButton).color = color
	_filling = false


## What is written next to the sliders, and which controls have no say for
## the look as it is.
func _refresh_look_notes() -> void:
	var shown: PlayerLook = look()
	if shown == null:
		return
	_look_values[&"height_in"].text = shown.height_text()
	_look_values[&"weight_lb"].text = "%d lb" % shown.weight_lb
	for property: StringName in [&"forehead_size", &"chin_size", &"nose_size", &"mouth_size"]:
		var size: float = shown.get(property)
		_look_values[property].text = "%d" % roundi(size * 100.0)
	var beard: OptionButton = look_controls[&"facial_hair"] as OptionButton
	beard.disabled = shown.base != PlayerLook.Base.MALE
	beard.tooltip_text = "Only the male base model grows it." if beard.disabled else ""
	var patch: OptionButton = look_controls[&"eyepatch_side"] as OptionButton
	patch.disabled = shown.glasses != PlayerLook.Glasses.EYEPATCH


## The preview's camera: round the player at the distance, turn and tip set by
## the mouse, looking at his head or at the middle of him.
func _place_camera() -> void:
	var shown: PlayerLook = look()
	var tall: float = shown.height_m() if shown != null else 1.8
	var target: Vector3 = Vector3(0.0, model.head_height() if _camera_on_face else tall * 0.52, 0.0)
	var offset: Vector3 = Vector3(sin(_camera_yaw) * cos(_camera_pitch), sin(_camera_pitch), cos(_camera_yaw) * cos(_camera_pitch))
	_camera.position = target + offset * _camera_distance
	_camera.look_at_from_position(_camera.position, target)


## One of the views the buttons under the preview give.
func _on_camera_preset(yaw: float, distance: float, on_face: bool) -> void:
	_camera_yaw = yaw
	_camera_pitch = 0.08
	_camera_distance = distance
	_camera_on_face = on_face
	_place_camera()


func _on_preview_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		_camera_yaw -= motion.relative.x * ORBIT_PER_PIXEL
		_camera_pitch = clampf(_camera_pitch + motion.relative.y * ORBIT_PER_PIXEL, -PITCH_LIMIT, PITCH_LIMIT)
		_place_camera()
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(_camera_distance * 0.9, ZOOM_NEAR)
			_place_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(_camera_distance / 0.9, ZOOM_FAR)
			_place_camera()


## Everything worked out from what was typed: the team's ratings and each
## player's overall.
func _refresh_derived() -> void:
	var team: TeamData = _team()
	var color: Color = team.team_color
	# A dark team colour would not show against the background.
	_bar_fill.bg_color = color.lightened(0.4) if color.get_luminance() < 0.3 else color
	var ratings: Array[Array] = team.roster.team_ratings() if team.roster != null else []
	for row: int in rating_bars.size():
		var value: int = ratings[row][1] if row < ratings.size() else 0
		rating_bars[row].value = value
		_rating_names[row].text = ratings[row][0] if row < ratings.size() else ""
		_rating_numbers[row].text = str(value)
	if team.roster == null:
		return
	for i: int in overall_labels.size():
		overall_labels[i].text = str(team.roster.players[i].overall())


func _refresh_list_item(index: int) -> void:
	var team: TeamData = league.teams[index]
	team_list.set_item_text(index, "%s%s" % [team.short_name, "  *" if dirty[index] else ""])
	team_list.set_item_tooltip(index, team.team_name)
	var image: Image = Image.create_empty(SWATCH_SIZE, SWATCH_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(team.team_color)
	team_list.set_item_icon(index, ImageTexture.create_from_image(image))


func _show_status(text: String, warning: bool) -> void:
	status.text = text
	status.add_theme_color_override(&"font_color", WARN_COLOR if warning else HEAD_COLOR)


# --- Files ---------------------------------------------------------------------------

## Whether `resource` is a file of its own and not a part of another one.
func _has_own_file(resource: Resource) -> bool:
	return resource != null and resource.resource_path != "" and not resource.resource_path.contains("::")


func _save_path(resource: Resource) -> String:
	if save_dir == "":
		return resource.resource_path
	return save_dir.path_join(resource.resource_path.trim_prefix("res://").replace("/", "_"))


## Every value of `from` that is kept in its file, taken over by `to`.
func _copy_values(from: Resource, to: Resource) -> void:
	if from == null or to == null:
		return
	const KEPT: int = PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_STORAGE
	for property: Dictionary in from.get_property_list():
		var usage: int = property["usage"]
		if usage & KEPT != KEPT:
			continue
		var key: String = property["name"]
		to.set(key, from.get(key))


# --- Building blocks -----------------------------------------------------------------

func _build() -> void:
	var back: ColorRect = ColorRect.new()
	back.color = BACK_COLOR
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 10)
	margin.add_child(page)

	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_team_list())
	body.add_child(_build_team_panel())
	page.add_child(_build_bottom_bar())

	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Unsaved changes"
	_quit_dialog.dialog_text = "Some teams have edits that are not saved."
	_quit_dialog.ok_button_text = "Save and quit"
	_quit_dialog.add_button("Quit without saving", true, "discard")
	_quit_dialog.confirmed.connect(_on_quit_save)
	_quit_dialog.custom_action.connect(_on_quit_discard)
	add_child(_quit_dialog)


func _on_quit_save() -> void:
	if save_all():
		get_tree().quit()


func _on_quit_discard(_action: StringName) -> void:
	get_tree().quit()


func _build_team_list() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size.x = LIST_WIDTH
	column.add_child(_label("TEAMS", 15, HEAD_COLOR))
	team_list = ItemList.new()
	team_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	team_list.fixed_icon_size = Vector2i(SWATCH_SIZE, SWATCH_SIZE)
	team_list.add_theme_font_size_override(&"font_size", 18)
	team_list.item_selected.connect(select_team)
	column.add_child(team_list)
	return column


func _build_team_panel() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fields: HBoxContainer = HBoxContainer.new()
	fields.add_theme_constant_override(&"separation", 10)
	column.add_child(fields)
	fields.add_child(_label("Name", 16, HEAD_COLOR))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size.x = 300.0
	name_edit.text_changed.connect(_on_team_name_changed)
	fields.add_child(name_edit)
	fields.add_child(_label("   Short", 16, HEAD_COLOR))
	short_edit = LineEdit.new()
	short_edit.custom_minimum_size.x = 150.0
	short_edit.tooltip_text = "What the scoreboard and the end zones say. One word, in capitals."
	short_edit.text_changed.connect(_on_short_name_changed)
	fields.add_child(short_edit)
	fields.add_child(_label("   Colour", 16, HEAD_COLOR))
	color_button = ColorPickerButton.new()
	color_button.custom_minimum_size = Vector2(110.0, 32.0)
	color_button.edit_alpha = false
	color_button.tooltip_text = "Home wears white with a band of it, away wears it all over."
	color_button.color_changed.connect(_on_color_changed)
	fields.add_child(color_button)

	column.add_child(_build_team_ratings())
	column.add_child(HSeparator.new())

	var views: HBoxContainer = HBoxContainer.new()
	views.add_theme_constant_override(&"separation", 6)
	column.add_child(views)
	var group: ButtonGroup = ButtonGroup.new()
	ratings_button = _view_button("Ratings", group, false)
	views.add_child(ratings_button)
	models_button = _view_button("Player models", group, true)
	views.add_child(models_button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_ratings_view = scroll
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override(&"h_separation", 6)
	_grid.add_theme_constant_override(&"v_separation", 2)
	scroll.add_child(_grid)
	_models_view = _build_models_view()
	_models_view.visible = false
	column.add_child(_models_view)
	ratings_button.set_pressed_no_signal(true)
	return column


func _view_button(text: String, group: ButtonGroup, models: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size.x = 150.0
	button.pressed.connect(show_models.bind(models))
	return button


## The players of the team in a list, the model of the one picked there, and
## what his look is made of.
func _build_models_view() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	player_list = ItemList.new()
	player_list.custom_minimum_size.x = 230.0
	player_list.add_theme_font_size_override(&"font_size", 16)
	player_list.item_selected.connect(select_player)
	row.add_child(player_list)

	var middle: VBoxContainer = VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(middle)
	var holder: SubViewportContainer = SubViewportContainer.new()
	holder.stretch = true
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.tooltip_text = "Drag to turn him, the wheel comes closer."
	holder.gui_input.connect(_on_preview_input)
	middle.add_child(holder)
	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.msaa_3d = Viewport.MSAA_4X
	holder.add_child(_preview)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = PREVIEW_BACK
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.55
	_preview.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	_preview.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_preview.add_child(_camera)
	model = PlayerModel.new()
	_preview.add_child(model)

	var shots: HBoxContainer = HBoxContainer.new()
	shots.add_theme_constant_override(&"separation", 6)
	shots.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_child(shots)
	for shot: Array in [["Body", 0.35, 4.2, false], ["Face", 0.0, 1.25, true], ["Side", PI / 2.0, 1.25, true], ["Back", PI, 4.2, false]]:
		var button: Button = Button.new()
		button.text = shot[0]
		button.custom_minimum_size.x = 80.0
		button.pressed.connect(_on_camera_preset.bind(shot[1], shot[2], shot[3]))
		shots.add_child(button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.x = LOOK_PANEL_WIDTH
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var fields: GridContainer = GridContainer.new()
	fields.columns = 3
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override(&"h_separation", 8)
	fields.add_theme_constant_override(&"v_separation", 5)
	scroll.add_child(fields)
	for field: Dictionary in look_fields:
		var property: StringName = field["property"]
		fields.add_child(_label(field["label"], 14, HEAD_COLOR))
		var control: Control
		if field.has("choices"):
			var option: OptionButton = OptionButton.new()
			for choice: String in field["choices"]:
				option.add_item(choice)
			option.item_selected.connect(_on_look_choice.bind(property))
			control = option
		elif field.has("slider"):
			var range_of: Array = field["slider"]
			var slider: HSlider = HSlider.new()
			slider.min_value = range_of[0]
			slider.max_value = range_of[1]
			slider.step = range_of[2]
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.value_changed.connect(_on_look_slider.bind(property))
			control = slider
		else:
			var picker: ColorPickerButton = ColorPickerButton.new()
			picker.edit_alpha = false
			picker.custom_minimum_size.y = 28.0
			for preset: Color in field["presets"]:
				picker.get_picker().add_preset(preset)
			picker.color_changed.connect(_on_look_color.bind(property))
			control = picker
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fields.add_child(control)
		look_controls[property] = control
		var value: Label = _label("", 14, Color.WHITE)
		value.custom_minimum_size.x = 52.0
		fields.add_child(value)
		_look_values[property] = value
	fields.add_child(Control.new())
	var random: Button = Button.new()
	random.text = "Random look"
	random.tooltip_text = "A new look out of the hat for this player."
	random.pressed.connect(randomize_look)
	fields.add_child(random)
	return row


## What the team select shows of the team, worked out again on every edit.
func _build_team_ratings() -> Control:
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.set_corner_radius_all(3)
	var bar_back: StyleBoxFlat = StyleBoxFlat.new()
	bar_back.bg_color = BAR_BACK
	bar_back.set_corner_radius_all(3)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	for i: int in 4:
		var name_label: Label = _label("", 14, HEAD_COLOR)
		row.add_child(name_label)
		var bar: ProgressBar = ProgressBar.new()
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(90.0, 10.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override(&"background", bar_back)
		bar.add_theme_stylebox_override(&"fill", _bar_fill)
		row.add_child(bar)
		var number_label: Label = _label("", 16, Color.WHITE)
		number_label.custom_minimum_size.x = 40.0
		row.add_child(number_label)
		rating_bars.append(bar)
		_rating_names.append(name_label)
		_rating_numbers.append(number_label)
	return row


## The players of the team shown, one to a column, a rating to a row.
func _build_grid() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	player_name_edits.clear()
	number_spins.clear()
	overall_labels.clear()
	rating_spins.clear()
	var roster: Roster = _team().roster
	if roster == null:
		_grid.columns = 1
		_grid.add_child(_label("This team has no roster.", 16, WARN_COLOR))
		return
	var players: Array[PlayerRatings] = roster.players
	_grid.columns = players.size() + 1

	_grid.add_child(_label("NAME", 14, HEAD_COLOR))
	for i: int in players.size():
		var edit: LineEdit = LineEdit.new()
		edit.text = players[i].display_name
		edit.custom_minimum_size.x = COLUMN_WIDTH
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(_on_player_name_changed.bind(i))
		_grid.add_child(edit)
		player_name_edits.append(edit)
		rating_spins.append({})

	_grid.add_child(_label("NUMBER", 14, HEAD_COLOR))
	for i: int in players.size():
		var spin: SpinBox = _spin(players[i].number, 99)
		spin.value_changed.connect(_on_number_changed.bind(i))
		_grid.add_child(spin)
		number_spins.append(spin)

	_grid.add_child(_label("POSITION", 14, HEAD_COLOR))
	for i: int in players.size():
		_grid.add_child(_cell_label(players[i].position, 16, Color.WHITE))

	var overall_head: Label = _label("OVERALL", 14, KEY_COLOR)
	overall_head.tooltip_text = "The mean of the position's key ratings, the ones in gold."
	overall_head.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.add_child(overall_head)
	for i: int in players.size():
		var overall: Label = _cell_label("", 20, KEY_COLOR)
		_grid.add_child(overall)
		overall_labels.append(overall)

	for rating: StringName in PlayerRatings.CARD_ORDER:
		_grid.add_child(_label(PlayerRatings.CARD_LABELS[rating], 14, HEAD_COLOR))
		for i: int in players.size():
			var player: PlayerRatings = players[i]
			var value: int = player.get(rating)
			var spin: SpinBox = _spin(value, 100)
			var keys: Array = PlayerRatings.KEY_RATINGS.get(player.position, [])
			if keys.has(rating):
				spin.get_line_edit().add_theme_color_override(&"font_color", KEY_COLOR)
			elif player.position != "QB" and PlayerRatings.QB_ONLY.has(rating):
				spin.modulate.a = UNUSED_ALPHA
				spin.tooltip_text = "Only a quarterback uses this."
			spin.value_changed.connect(_on_rating_changed.bind(i, rating))
			_grid.add_child(spin)
			rating_spins[i][rating] = spin


func _build_bottom_bar() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var save: Button = Button.new()
	save.text = "Save"
	save.custom_minimum_size.x = 120.0
	save.tooltip_text = "Writes every edited team to its files."
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_S
	key.ctrl_pressed = true
	var shortcut: Shortcut = Shortcut.new()
	shortcut.events = [key]
	save.shortcut = shortcut
	save.pressed.connect(save_all)
	row.add_child(save)
	var revert: Button = Button.new()
	revert.text = "Revert team"
	revert.tooltip_text = "Puts the team shown back to what its files say."
	revert.pressed.connect(revert_selected)
	row.add_child(revert)
	status = _label("", 15, HEAD_COLOR)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status)
	return row


func _spin(value: int, most: int) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = float(most)
	spin.rounded = true
	spin.value = float(value)
	spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.select_all_on_focus = true
	spin.custom_minimum_size.x = COLUMN_WIDTH
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.get_line_edit().add_theme_constant_override(&"minimum_character_width", 2)
	return spin


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label


## A label in the middle of a player's column.
func _cell_label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = _label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
