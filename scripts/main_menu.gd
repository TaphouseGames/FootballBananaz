class_name MainMenu
extends Node3D
## The title screen the game opens on: the field at dusk behind the title and
## three buttons. Start brings up the team select, where the person picks the
## two teams of the league and their own side, and which fades to the match and
## its intro; Exit quits, Options does nothing yet.
## The buttons take the D-pad or stick and (A), the arrow keys and Enter, or
## the mouse, all through Godot's own ui_* actions.

const GAME_SCENE: String = "res://scenes/main.tscn"
const MOVE_SOUND: AudioStream = preload("res://assets/audio/ui_move_1.wav")
const CONFIRM_SOUND: AudioStream = preload("res://assets/audio/ui_confirm_1.wav")
const BLUE: Color = Color(0.16, 0.42, 0.85)
const GOLD: Color = Color(0.93, 0.76, 0.3)
const OUTLINE: Color = Color(0.04, 0.08, 0.2)
const BUTTON_COLOR: Color = Color(0.13, 0.36, 0.72, 0.95)
const BUTTON_HOVER_COLOR: Color = Color(0.2, 0.5, 0.92, 1.0)
const BUTTON_BORDER: Color = Color(0.45, 0.85, 1.0)
const BUTTON_SIZE: Vector2 = Vector2(300.0, 60.0)
## Heavy fonts for the title and the buttons, the first one installed wins.
const FONT_NAMES: PackedStringArray = ["Impact", "Haettenschweiler", "Arial Black"]
## The camera stands on the field looking at the right end zone, whose word
## reads the right way up from here, and drifts from side to side.
const CAMERA_FROM: Vector3 = Vector3(62.0, 4.0, 0.0)
const CAMERA_AT: Vector3 = Vector3(112.0, 5.0, 0.0)
const CAMERA_SWAY: float = 6.0
const CAMERA_SWAY_SPEED: float = 0.12

@export var tuning: Tuning
## The teams the team select has to offer.
@export var league: League

var start_button: Button
var options_button: Button
var exit_button: Button
## Made the first time START GAME is pressed.
var team_select: TeamSelect

var _title: Control
var _buttons: Control
## Held so the match does not have to be loaded a second time.
var _game_scene: PackedScene
var _time: float = 0.0
var _starting: bool = false
## Off until the first button has its focus, so that does not make a sound.
var _sounds_on: bool = false
var _sound: AudioStreamPlayer
var _font: SystemFont

@onready var field: Field = $Field
@onready var camera: Camera3D = $Camera3D
@onready var ui: Control = $UI/Root


func _ready() -> void:
	# A match left paused or in a hit-stop must not carry over.
	get_tree().paused = false
	_build_field()
	# The camera moves every frame, not every physics tick.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_place_camera()

	_font = SystemFont.new()
	_font.font_names = FONT_NAMES
	AudioDirector.make_buses(tuning)
	_sound = AudioStreamPlayer.new()
	_sound.bus = AudioDirector.BUS_UI
	add_child(_sound)

	_build_title()
	_build_buttons()
	start_button.grab_focus()
	_sounds_on = true
	# Up out of black, at the start (on the way back from a match the change
	# of scene does it, and these do nothing).
	var fade: ScreenFade = ScreenFade.of(get_tree())
	fade.cover(0.0)
	fade.reveal()


func _process(delta: float) -> void:
	_time += delta
	_place_camera()


## Godot's ui_accept has no gamepad button on it, so (A) comes in through the
## game's own confirm action and presses whichever button has the focus.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"confirm") or event.is_action(&"ui_accept"):
		return
	if team_select != null and team_select.visible:
		return
	var focused: Button = get_viewport().gui_get_focus_owner() as Button
	if focused != null:
		get_viewport().set_input_as_handled()
		focused.pressed.emit()


func _place_camera() -> void:
	var sway: float = sin(_time * CAMERA_SWAY_SPEED) * CAMERA_SWAY
	camera.look_at_from_position(CAMERA_FROM + Vector3(0.0, 0.0, sway), CAMERA_AT + Vector3(0.0, 0.0, -sway * 0.3))


# --- Buttons -------------------------------------------------------------------------

## On to the team select, in place of the title and the buttons.
func _on_start() -> void:
	if _starting:
		return
	_play(CONFIRM_SOUND)
	if team_select == null:
		team_select = TeamSelect.new()
		# Loaded here, so the fade into the match does not have to wait for it.
		_game_scene = load(GAME_SCENE)
		team_select.setup(_font, league.teams)
		team_select.chosen.connect(_start_match)
		team_select.cancelled.connect(_on_select_cancelled)
		team_select.moved.connect(_play.bind(MOVE_SOUND))
		ui.add_child(team_select)
	ScreenFade.pop(_title, false)
	ScreenFade.pop(_buttons, false)
	team_select.open()
	ScreenFade.pop(team_select, true)


## Back to the title. START GAME taking the focus makes the sound.
func _on_select_cancelled() -> void:
	team_select.close()
	ScreenFade.pop(_title, true)
	ScreenFade.pop(_buttons, true)
	start_button.grab_focus()


## `team` is the side the person plays: 0 home (the left team), 1 away.
func _start_match(team: int) -> void:
	if _starting:
		return
	_starting = true
	_play(CONFIRM_SOUND)
	Game.human_side = team
	Game.team_picks = PackedInt32Array(team_select.picks)
	# The match opens with the broadcast's intro, which comes up out of black.
	Game.show_intro = true
	ScreenFade.of(get_tree()).change_scene(GAME_SCENE)


## Nothing to set yet.
func _on_options() -> void:
	_play(CONFIRM_SOUND)


func _on_exit() -> void:
	get_tree().quit()


func _play(stream: AudioStream) -> void:
	if not _sounds_on or not tuning.audio_enabled:
		return
	_sound.stream = stream
	_sound.play()


# --- Building blocks -----------------------------------------------------------------

## The field only asks its teams for a colour and a word for each end zone:
## between them they spell the title.
func _build_field() -> void:
	var left: Team = Team.new()
	left.short_name = "BLUE"
	left.team_color = BLUE
	left.attack_dir = 1
	var right: Team = Team.new()
	right.short_name = "42"
	right.team_color = GOLD
	right.attack_dir = -1
	field.setup(tuning, left, right)
	field.markers.visible = false
	left.free()
	right.free()


func _build_title() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_TOP_WIDE)
	column.offset_top = 36.0
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", -6)
	ui.add_child(column)
	_title = column

	var title: HBoxContainer = HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override(&"separation", 22)
	title.add_child(_title_label("BLUE", BLUE))
	title.add_child(_title_label("42", GOLD))
	column.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "EXTREMELY REALISTIC AMERICAN FOOTBALL SIMULATOR"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override(&"font", _font)
	subtitle.add_theme_font_size_override(&"font_size", 26)
	subtitle.add_theme_color_override(&"font_color", Color.WHITE)
	subtitle.add_theme_color_override(&"font_outline_color", OUTLINE)
	subtitle.add_theme_constant_override(&"outline_size", 8)
	column.add_child(subtitle)


func _title_label(text: String, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", 170)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", OUTLINE)
	label.add_theme_constant_override(&"outline_size", 22)
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
	label.add_theme_constant_override(&"shadow_offset_x", 5)
	label.add_theme_constant_override(&"shadow_offset_y", 7)
	label.add_theme_constant_override(&"shadow_outline_size", 22)
	return label


func _build_buttons() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	ui.add_child(column)
	_buttons = column
	start_button = _button("START GAME", _on_start)
	options_button = _button("OPTIONS", _on_options)
	exit_button = _button("EXIT", _on_exit)
	for button: Button in [start_button, options_button, exit_button]:
		column.add_child(button)
	# Up from the first one goes round to the last, and back.
	start_button.focus_neighbor_top = start_button.get_path_to(exit_button)
	exit_button.focus_neighbor_bottom = exit_button.get_path_to(start_button)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 56)


func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_override(&"font", _font)
	button.add_theme_font_size_override(&"font_size", 30)
	for color: StringName in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color", &"font_hover_pressed_color"]:
		button.add_theme_color_override(color, Color.WHITE)
	button.add_theme_color_override(&"font_outline_color", OUTLINE)
	button.add_theme_constant_override(&"outline_size", 6)
	button.add_theme_stylebox_override(&"normal", _button_style(BUTTON_COLOR, BUTTON_BORDER, true))
	button.add_theme_stylebox_override(&"hover", _button_style(BUTTON_HOVER_COLOR, BUTTON_BORDER, true))
	button.add_theme_stylebox_override(&"pressed", _button_style(BUTTON_COLOR.darkened(0.25), BUTTON_BORDER, true))
	# Drawn over the others on the button that has the focus.
	button.add_theme_stylebox_override(&"focus", _button_style(Color(1.0, 1.0, 1.0, 0.14), Color.WHITE, false))
	button.pressed.connect(action)
	button.focus_entered.connect(_play.bind(MOVE_SOUND))
	button.mouse_entered.connect(button.grab_focus)
	return button


func _button_style(fill: Color, border: Color, shadow: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	if shadow:
		style.shadow_color = Color(BUTTON_BORDER, 0.35)
		style.shadow_size = 6
	return style
