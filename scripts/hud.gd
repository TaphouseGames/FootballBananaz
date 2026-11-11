class_name HUD
extends CanvasLayer
## Scoreboard, down and distance, clock, turbo meter, banners and the
## play-select panel. Reads everything it shows from Game each frame.

const SELECTED_COLOR: Color = Color(1.0, 0.9, 0.2)
const NORMAL_COLOR: Color = Color(0.85, 0.85, 0.85)

var game: Game

var _play_rows: Array[Label] = []
var _play_names: PackedStringArray = PackedStringArray()

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
@onready var play_list: VBoxContainer = $PlaySelect/Margin/Column/PlayList


func setup(p_game: Game) -> void:
	game = p_game
	hide_banner()
	hide_play_select()
	set_hint("")


func _process(_delta: float) -> void:
	if game == null or game.offense == null:
		return
	var home_marker: String = "> " if game.offense == game.home else ""
	var away_marker: String = " <" if game.offense == game.away else ""
	score_label.text = "%s%s  %d  -  %d  %s%s" % [home_marker, game.home.short_name, game.home.score, game.away.score, game.away.short_name, away_marker]
	down_label.text = "%s   |   %s" % [game.down_text(), game.ball_on_text()]
	clock_label.text = game.clock_text()

	var controlled: Player = game.human.controlled
	turbo_box.visible = controlled != null
	if controlled != null:
		turbo_bar.value = controlled.turbo
		turbo_bar.modulate = Color(1.0, 0.4, 0.3) if controlled.turbo_locked else Color.WHITE


func show_banner(text: String, sub_text: String = "") -> void:
	banner.text = text
	banner.visible = text != ""
	sub_banner.text = sub_text
	sub_banner.visible = sub_text != ""


func hide_banner() -> void:
	banner.visible = false
	sub_banner.visible = false


func set_hint(text: String) -> void:
	hint.text = text
	hint.visible = text != ""


func show_play_select(title: String, names: PackedStringArray, descriptions: PackedStringArray) -> void:
	for row: Label in _play_rows:
		row.queue_free()
	_play_rows.clear()
	_play_names = names
	play_title.text = title
	for i: int in names.size():
		var row: Label = Label.new()
		row.add_theme_font_size_override(&"font_size", 22)
		row.set_meta(&"description", descriptions[i])
		play_list.add_child(row)
		_play_rows.append(row)
	play_select.visible = true
	set_play_cursor(0)


func set_play_cursor(index: int) -> void:
	for i: int in _play_rows.size():
		var row: Label = _play_rows[i]
		var selected: bool = i == index
		var description: String = row.get_meta(&"description", "")
		row.text = "%s %d. %s\n      %s" % [">" if selected else "  ", i + 1, _play_names[i], description]
		row.modulate = SELECTED_COLOR if selected else NORMAL_COLOR


func hide_play_select() -> void:
	play_select.visible = false
