class_name TeamSelect
extends Control
## The screen between START GAME and the match: a team on the left, a team on
## the right and the controllers between them. Left and right slide a
## controller under a team, up and down go through the league's teams on that
## side, (A) starts the match as that team and (B) goes back.
##
## Player one's controller is the first gamepad that pressed anything (and the
## keyboard and the mouse). The second one reads CPU until another gamepad
## presses a button: that is player two, who takes the other team. Never the
## same one: a controller does not go under the team the other is under. With
## player two in, both have to be under a team before (A) starts, and player
## two's (B) takes them out again. Left in the middle as CPU, the CPU plays
## the other team. Which gamepad is whose is kept by Controllers.

## Player one starts as this team: 0 the left one (home), 1 the right one
## (away). With `versus` set player two has the other one.
signal chosen(team: int)
signal cancelled
## The controller went from one place to another, or a side got another team.
signal moved
## The controller went to another side, and the team on its side changed.
signal side_changed
signal team_changed

const SCRIM_COLOR: Color = Color(0.02, 0.04, 0.1, 0.72)
const PANEL_COLOR: Color = Color(0.04, 0.08, 0.2, 0.94)
const SLOT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.07)
const CPU_COLOR: Color = Color(0.5, 0.54, 0.62)
## Player two's controller in the middle, once somebody holds it.
const P2_COLOR: Color = Color(1.0, 0.72, 0.35)
const BAR_BACK: Color = Color(1.0, 1.0, 1.0, 0.12)
const BOARD_SIZE: Vector2 = Vector2(1000.0, 400.0)
const PANEL_SIZE: Vector2 = Vector2(360.0, 400.0)
## The team's ratings under its name: where the first row is, how far in from
## the panel's sides, and the height of a row.
const RATINGS_TOP: float = 152.0
const RATINGS_INSET: float = 22.0
const RATING_ROW: float = 20.0
const RATING_COUNT: int = 4
const ICON_SIZE: Vector2 = Vector2(104.0, 60.0)
## Middle of the left panel, of the board and of the right panel.
const SLOT_X: Array[float] = [180.0, 500.0, 820.0]
## Player one's row and player two's.
const ROW_Y: Array[float] = [275.0, 352.0]
const SLIDE_TIME: float = 0.14
## Each team stands on the top edge of its panel, the mascot at the outer end
## and its players beside it: the size of their picture, how far that hangs
## over the panel's outer side, how far their feet come down over the edge, and
## how many times finer than that it is drawn (the screen is scaled up on a big
## window).
const CAST_VIEW: Vector2 = Vector2(500.0, 190.0)
const CAST_OVERHANG: float = 140.0
const MASCOT_FEET: float = 9.0
const MASCOT_RENDER_SCALE: int = 2
## The title stands this much higher over the board, clear of the players' heads.
const HEADER_LIFT: float = 84.0
## How far out from the middle of the picture the mascot stands, and how far in
## the middle of the players is, in yards of their world.
const MASCOT_SPOT: float = 3.37
const CAST_SPOT: float = 1.42
## The players are in two rows, the taller half behind: yards from one to the
## next in a row, how far behind the back row is and how much higher it stands
## (as on a bench, so its faces show over the front row), and how many yards a
## metre of a player's model is (as in player.tscn).
const CAST_SPACING: float = 1.4
const CAST_ROW_DEPTH: float = 1.0
const CAST_RISER: float = 0.3
const CAST_SCALE: float = 1.25
## Yards of the mascot's world the picture is tall (the banana is 2.8, and
## leaves the ground when it cheers), and how far it is turned to the middle.
const MASCOT_FRAME: float = 3.6
const MASCOT_TURN: float = 0.38
## On the sideline a round mascot is kept small so as not to hide the front
## rows (Stadium.MASCOT_WIDTH). Here each is as big as fits: this tall, unless
## that makes it wider than this.
const MASCOT_TALL: float = 2.8
const MASCOT_WIDE: float = 2.7

## Where player one's controller is: -1 the left team, 0 the middle, 1 the right team.
var side: int = 0
## Where player two's is, and whether there is a player two.
var side2: int = 0
var joined: bool = false
## Two people start the match, one team each. Set as it starts.
var versus: bool = false
## The team on the left and the one on the right, as places in the league's
## teams. Never the same one twice.
var picks: Array[int] = [0, 1]
## Per panel: the bars of its team's ratings (see Roster.team_ratings()).
var rating_bars: Array[Array] = []
## Per panel: the short name of the team whose mascot stands on it, and the
## clip that one is in ("cheer" on the side the controller is under).
var mascot_names: PackedStringArray = PackedStringArray()
var mascot_clips: PackedStringArray = PackedStringArray()
## Per panel: the names of the players standing on it, from the left.
var cast_names: Array[PackedStringArray] = []

var _font: SystemFont
var _teams: Array[TeamData] = []
var _panels: Array[Panel] = []
var _styles: Array[StyleBoxFlat] = []
## Per panel: the block in the team's colour and what is written on and under it.
var _fills: Array[StyleBoxFlat] = []
var _short_labels: Array[Label] = []
var _name_labels: Array[Label] = []
## Per panel: the name and the number beside each rating bar, and what the
## bars are filled with.
var _rating_names: Array[Array] = []
var _rating_numbers: Array[Array] = []
var _bar_fills: Array[StyleBoxFlat] = []
## Per panel: the little world its mascot is drawn in, where the model goes in
## it, and the model's AnimationPlayer (null without one).
var _mascot_views: Array[SubViewport] = []
var _mascot_stands: Array[Node3D] = []
var _mascot_players: Array[AnimationPlayer] = []
## Per panel: where its team's players go, and whose they are.
var _cast_stands: Array[Node3D] = []
var _cast_teams: Array[TeamData] = []
## Player one's controller and player two's.
var _icons: Array[ControllerIcon] = []
var _choose_hint: Label
var _start_hint: Label
var _join_hint: Label
var _slides: Array[Tween] = [null, null]
var _nudge: Tween
## The sticks held over right now, by gamepad and way (see _pressed()).
var _held: Dictionary[String, bool] = {}
## A team is chosen and the match is on its way: nothing more to press.
var _done: bool = false


## `teams` is every team there is to pick. The first two start on the left
## and on the right.
func setup(font: SystemFont, teams: Array[TeamData]) -> void:
	_font = font
	_teams = teams
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var scrim: ColorRect = ColorRect.new()
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 26)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var header: Label = _label("CHOOSE YOUR TEAM", 58, Color.WHITE, 12)
	column.add_child(header)
	var lift: Control = Control.new()
	lift.custom_minimum_size.y = HEADER_LIFT - 26.0
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(lift)
	column.add_child(_build_board())
	column.add_child(_build_hints())
	# The mascots are only drawn while the screen is up.
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	Controllers.of(Engine.get_main_loop() as SceneTree).pad_lost.connect(_on_pad_lost)


## Shows the screen with the controllers back in the middle and no player two.
func open() -> void:
	_done = false
	side = 0
	side2 = 0
	joined = false
	versus = false
	_held.clear()
	visible = true
	_refresh(false)


## Puts the mascot and the players of side `index` (0 left, 1 right) in ahead
## of time, with the screen still hidden, so open() has nothing to load.
func warm_side(index: int) -> void:
	if index < _panels.size():
		var team: TeamData = _teams[picks[index]]
		_show_mascot(index, team.short_name, false)
		_show_cast(index, team)


## Fades the screen out; it takes no more input meanwhile.
func close() -> void:
	_done = true
	ScreenFade.pop(self, false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _done:
		return
	var seat: int = _seat_of(event)
	if seat < 0:
		return
	if _pressed(event, &"ui_left"):
		_step(seat, -1)
	elif _pressed(event, &"ui_right"):
		_step(seat, 1)
	elif _pressed(event, &"ui_up"):
		_cycle(seat, -1)
	elif _pressed(event, &"ui_down"):
		_cycle(seat, 1)
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		_confirm(seat)
	elif event.is_action_pressed(&"back") or event.is_action_pressed(&"ui_cancel"):
		if seat == 0:
			cancelled.emit()
		else:
			_leave()
	else:
		return
	get_viewport().set_input_as_handled()


## Whose press this is: 0 player one's, 1 player two's, -1 nobody's (it is not
## acted on). A gamepad that is neither's yet becomes player two's with its
## first button, and that press only brings player two in.
func _seat_of(event: InputEvent) -> int:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return 0
	var controllers: Controllers = Controllers.of(get_tree())
	var seat: int = controllers.seat_of(event.device)
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if seat < 0 and button != null and button.pressed:
		seat = controllers.claim(event.device)
	if seat != 1 or joined:
		return seat
	if button != null and button.pressed:
		_join()
		get_viewport().set_input_as_handled()
	return -1


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


## Where the controller of `seat` is.
func _place(seat: int) -> int:
	return side if seat == 0 else side2


## A second gamepad pressed a button: there is a player two.
func _join() -> void:
	joined = true
	side2 = 0
	_refresh(false)
	moved.emit()


## Player two is out again: the CPU plays the other team.
func _leave() -> void:
	if not joined:
		return
	joined = false
	side2 = 0
	Controllers.of(get_tree()).release(1)
	_refresh(true)
	moved.emit()


func _on_pad_lost(seat: int) -> void:
	if seat == 1 and visible and not _done:
		_leave()


func _step(seat: int, by: int) -> void:
	_move_to(seat, clampi(_place(seat) + by, -1, 1))


func _move_to(seat: int, to: int) -> void:
	if to == _place(seat):
		return
	# Not under the team the other one has: nobody plays together.
	if to != 0 and to == _place(1 - seat) and (seat == 1 or joined):
		return
	if seat == 0:
		side = to
	else:
		side2 = to
	_refresh(true)
	moved.emit()
	side_changed.emit()


## The next team (`by` +1) or the one before (-1) on the side the controller
## of `seat` is under, passing over the one the other side has.
func _cycle(seat: int, by: int) -> void:
	var place: int = _place(seat)
	if place == 0:
		_flash_choose_hint()
		return
	if _teams.size() < 3:
		return
	var index: int = 0 if place < 0 else 1
	var to: int = posmod(picks[index] + by, _teams.size())
	if to == picks[1 - index]:
		to = posmod(to + by, _teams.size())
	picks[index] = to
	_refresh(false)
	moved.emit()
	team_changed.emit()


## Nothing to start or to change in the middle: the hint to pick a side flashes.
func _flash_choose_hint() -> void:
	if _nudge != null:
		_nudge.kill()
	_choose_hint.modulate = MainMenu.GOLD
	_nudge = create_tween()
	_nudge.tween_property(_choose_hint, ^"modulate", Color.WHITE, 0.4)


## Everybody who is in is under a team.
func _ready_to_start() -> bool:
	return side != 0 and (not joined or side2 != 0)


func _confirm(_seat: int) -> void:
	if not _ready_to_start():
		_flash_choose_hint()
		return
	_done = true
	versus = joined
	chosen.emit(0 if side < 0 else 1)


## The mouse: a click on a team moves the controller there, a second one
## starts, and the wheel over the team the controller is under changes it.
func _on_panel_input(event: InputEvent, to: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or _done:
		return
	if click.button_index == MOUSE_BUTTON_WHEEL_UP or click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if side == to:
			_cycle(0, -1 if click.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	if side == to:
		_confirm(0)
	else:
		_move_to(0, to)


func _refresh(animated: bool) -> void:
	for i: int in _panels.size():
		var place: int = -1 if i == 0 else 1
		# Somebody's controller is under it.
		var mine: bool = side == place or (joined and side2 == place)
		var team: TeamData = _teams[picks[i]]
		var color: Color = team.team_color
		_fills[i].bg_color = color
		_short_labels[i].text = team.short_name
		_name_labels[i].text = team.team_name.to_upper()
		# A dark team colour would not show against the panel.
		_bar_fills[i].bg_color = Team.marker_of(color)
		var ratings: Array[Array] = team.roster.team_ratings() if team.roster != null else []
		for row: int in RATING_COUNT:
			var value: int = ratings[row][1] if row < ratings.size() else 0
			var bar: ProgressBar = rating_bars[i][row]
			var name_label: Label = _rating_names[i][row]
			var number_label: Label = _rating_numbers[i][row]
			bar.value = value
			name_label.text = ratings[row][0] if row < ratings.size() else ""
			number_label.text = str(value)
		_styles[i].border_color = Color.WHITE if mine else color
		_styles[i].set_border_width_all(5 if mine else 3)
		var anybody: bool = side != 0 or (joined and side2 != 0)
		_panels[i].modulate = Color.WHITE if mine or not anybody else Color(0.5, 0.5, 0.5)
		_show_mascot(i, team.short_name, mine)
		_show_cast(i, team)
		# The players cheer with their mascot on the side the controller is under.
		for model: PlayerModel in _cast_stands[i].get_children():
			ModelStage.motion_of(model).cheering = mine
	_start_hint.modulate.a = 1.0 if _ready_to_start() else 0.35
	_join_hint.text = "P2:  (B) LEAVE" if joined else "SECOND CONTROLLER:  PRESS ANY BUTTON TO JOIN"

	# Each controller under its team, in that team's colour.
	for seat: int in _icons.size():
		var icon: ControllerIcon = _icons[seat]
		var at: int = _place(seat)
		var tint: Color = MainMenu.BUTTON_BORDER if seat == 0 else (P2_COLOR if joined else CPU_COLOR)
		if at != 0:
			tint = Team.marker_of(_teams[picks[0 if at < 0 else 1]].team_color)
		var tag: String = "P1" if seat == 0 else ("P2" if joined else "CPU")
		if icon.tint != tint or icon.tag != tag:
			icon.tint = tint
			icon.tag = tag
			icon.queue_redraw()
		var x: float = SLOT_X[at + 1] - ICON_SIZE.x * 0.5
		if _slides[seat] != null:
			_slides[seat].kill()
		if animated:
			_slides[seat] = create_tween()
			_slides[seat].tween_property(icon, ^"position:x", x, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			icon.position.x = x


# --- Building blocks -----------------------------------------------------------------

func _build_board() -> Control:
	var board: Control = Control.new()
	board.custom_minimum_size = BOARD_SIZE
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in 2:
		var panel: Panel = _team_panel(i)
		panel.position = Vector2(0.0 if i == 0 else BOARD_SIZE.x - PANEL_SIZE.x, 0.0)
		board.add_child(panel)

	var versus: Label = _label("VS", 72, MainMenu.GOLD, 12)
	versus.position = Vector2(PANEL_SIZE.x, 30.0)
	versus.size = Vector2(BOARD_SIZE.x - PANEL_SIZE.x * 2.0, 100.0)
	board.add_child(versus)

	# A place for each controller under each team and in the middle.
	for x: float in SLOT_X:
		for y: float in ROW_Y:
			var slot: Panel = Panel.new()
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = SLOT_COLOR
			style.set_corner_radius_all(14)
			slot.add_theme_stylebox_override(&"panel", style)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.size = ICON_SIZE + Vector2(20.0, 10.0)
			slot.position = Vector2(x, y) - slot.size * 0.5
			board.add_child(slot)

	# Player two's is the CPU's until a second gamepad joins.
	_icons = [_controller("P1", MainMenu.BUTTON_BORDER, 0), _controller("CPU", CPU_COLOR, 1)]
	for icon: ControllerIcon in _icons:
		board.add_child(icon)
	return board


## The panel of one side. _refresh() fills in whichever team that side has.
func _team_panel(index: int) -> Panel:
	var panel: Panel = Panel.new()
	panel.size = PANEL_SIZE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.gui_input.connect(_on_panel_input.bind(-1 if index == 0 else 1))
	_panels.append(panel)
	_styles.append(style)

	var block: Panel = Panel.new()
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.set_corner_radius_all(8)
	block.add_theme_stylebox_override(&"panel", fill)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.position = Vector2(14.0, 14.0)
	block.size = Vector2(PANEL_SIZE.x - 28.0, 100.0)
	panel.add_child(block)
	var short_label: Label = _label("", 62, Color.WHITE, 12)
	short_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	block.add_child(short_label)

	var name_label: Label = _label("", 24, Color(0.86, 0.9, 1.0), 0)
	name_label.position = Vector2(0.0, 115.0)
	name_label.size = Vector2(PANEL_SIZE.x, 30.0)
	panel.add_child(name_label)
	_fills.append(fill)
	_short_labels.append(short_label)
	_name_labels.append(name_label)
	_build_ratings(panel)
	_build_mascot(panel, index)
	return panel


## The picture of the side's mascot and players, standing on the panel's top
## edge: a small world of its own (see ModelStage), drawn into a texture. The
## models are put in by _show_mascot() and _show_cast().
func _build_mascot(panel: Panel, index: int) -> void:
	var picture: TextureRect = TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.size = CAST_VIEW
	picture.position = Vector2(-CAST_OVERHANG if index == 0 else PANEL_SIZE.x - CAST_VIEW.x + CAST_OVERHANG, MASCOT_FEET - CAST_VIEW.y)
	panel.add_child(picture)

	var view: SubViewport = ModelStage.build(Vector2i(CAST_VIEW) * MASCOT_RENDER_SCALE, MASCOT_FRAME, 28.0 if index == 0 else -28.0)
	picture.add_child(view)
	picture.texture = view.get_texture()

	# Out is to the left on the left panel. Both the mascot and the players are
	# turned a little to the middle of the screen, where the other team stands.
	var out: float = -1.0 if index == 0 else 1.0
	var stand: Node3D = Node3D.new()
	stand.position.x = out * MASCOT_SPOT
	stand.rotation.y = -out * MASCOT_TURN
	view.add_child(stand)
	var cast: Node3D = Node3D.new()
	cast.position.x = -out * CAST_SPOT
	cast.rotation.y = -out * MASCOT_TURN
	view.add_child(cast)

	_mascot_views.append(view)
	_mascot_stands.append(stand)
	_mascot_players.append(null)
	mascot_names.append("")
	mascot_clips.append("")
	_cast_stands.append(cast)
	_cast_teams.append(null)
	cast_names.append(PackedStringArray())


## Stands `team`'s players on panel `index` in the kit they will wear: white
## for the team on the left, which is at home. The taller half is the back row.
func _show_cast(index: int, team: TeamData) -> void:
	if index >= _cast_stands.size() or _cast_teams[index] == team:
		return
	_cast_teams[index] = team
	var stand: Node3D = _cast_stands[index]
	for old: Node in stand.get_children():
		stand.remove_child(old)
		old.queue_free()
	var players: Array[PlayerRatings] = []
	if team.roster != null:
		for ratings: PlayerRatings in team.roster.players:
			if ratings != null:
				players.append(ratings)
	players.sort_custom(func(a: PlayerRatings, b: PlayerRatings) -> bool:
		return a.look_or_default().height_in > b.look_or_default().height_in)
	@warning_ignore("integer_division")
	var behind: int = players.size() / 2
	var spots: Array[Array] = []
	for i: int in players.size():
		var back: bool = i < behind
		var count: int = behind if back else players.size() - behind
		var place: int = i if back else i - behind
		# The back row stands in the gaps of the front one.
		var x: float = (float(place) - float(count - 1) * 0.5 + (0.25 if back else -0.25)) * CAST_SPACING
		var model: PlayerModel = ModelStage.player(players[i], team.team_color, index == 0, float(i) * 1.7)
		model.scale = Vector3.ONE * CAST_SCALE
		model.position = Vector3(x, CAST_RISER if back else 0.0, -CAST_ROW_DEPTH if back else 0.0)
		stand.add_child(model)
		spots.append([x, players[i].display_name])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var names: PackedStringArray = PackedStringArray()
	for spot: Array in spots:
		names.append(spot[1])
	cast_names[index] = names


## Stands `short_name`'s mascot on panel `index` (the model of the sidelines,
## see Stadium.mascot_model) and has it cheer on the side the controller is
## under, idle on the other.
func _show_mascot(index: int, short_name: String, mine: bool) -> void:
	if index >= _mascot_stands.size():
		return
	if mascot_names[index] != short_name:
		mascot_names[index] = short_name
		mascot_clips[index] = ""
		_mascot_players[index] = null
		var stand: Node3D = _mascot_stands[index]
		for old: Node in stand.get_children():
			stand.remove_child(old)
			old.queue_free()
		var model: Node3D = Stadium.mascot_model(short_name)
		if model != null:
			var size: Vector3 = model.get_meta(&"size", Vector3.ONE * MASCOT_TALL)
			model.scale = Vector3.ONE * minf(MASCOT_TALL / maxf(size.y, 0.01), MASCOT_WIDE / maxf(size.x, 0.01))
			stand.add_child(model)
			var found: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
			if not found.is_empty():
				var player: AnimationPlayer = found[0] as AnimationPlayer
				for clip: StringName in player.get_animation_list():
					player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				_mascot_players[index] = player
	var clip: String = "cheer" if mine else "idle"
	var clips: AnimationPlayer = _mascot_players[index]
	if clips == null or clip == mascot_clips[index] or not clips.has_animation(clip):
		return
	mascot_clips[index] = clip
	clips.play(clip, 0.2)


func _on_visibility_changed() -> void:
	var mode: SubViewport.UpdateMode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	for view: SubViewport in _mascot_views:
		view.render_target_update_mode = mode


## A row for each of the team's ratings: what it is, a bar and the number.
func _build_ratings(panel: Panel) -> void:
	var bar_fill: StyleBoxFlat = StyleBoxFlat.new()
	bar_fill.set_corner_radius_all(3)
	var bar_back: StyleBoxFlat = StyleBoxFlat.new()
	bar_back.bg_color = BAR_BACK
	bar_back.set_corner_radius_all(3)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.position = Vector2(RATINGS_INSET, RATINGS_TOP)
	rows.size = Vector2(PANEL_SIZE.x - RATINGS_INSET * 2.0, RATING_ROW * float(RATING_COUNT))
	panel.add_child(rows)
	var bars: Array[ProgressBar] = []
	var names: Array[Label] = []
	var numbers: Array[Label] = []
	for row: int in RATING_COUNT:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 10)
		line.custom_minimum_size.y = RATING_ROW
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(line)
		var name_label: Label = _label("", 15, Color(0.86, 0.9, 1.0), 0)
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
		bar.add_theme_stylebox_override(&"fill", bar_fill)
		line.add_child(bar)
		var number_label: Label = _label("", 16, Color.WHITE, 0)
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number_label.custom_minimum_size.x = 28.0
		line.add_child(number_label)
		bars.append(bar)
		names.append(name_label)
		numbers.append(number_label)
	rating_bars.append(bars)
	_rating_names.append(names)
	_rating_numbers.append(numbers)
	_bar_fills.append(bar_fill)


func _controller(tag: String, tint: Color, row: int) -> ControllerIcon:
	var icon: ControllerIcon = ControllerIcon.new()
	icon.tag = tag
	icon.tint = tint
	icon.font = _font
	icon.size = ICON_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(SLOT_X[1], ROW_Y[row]) - ICON_SIZE * 0.5
	return icon


func _build_hints() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 44)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choose_hint = _label("LEFT / RIGHT  CHOOSE SIDE", 22, Color.WHITE, 6)
	_start_hint = _label("(A)  START", 22, Color.WHITE, 6)
	row.add_child(_choose_hint)
	row.add_child(_label("UP / DOWN  CHANGE TEAM", 22, Color.WHITE, 6))
	row.add_child(_start_hint)
	row.add_child(_label("(B)  BACK", 22, Color.WHITE, 6))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_join_hint = _label("", 20, P2_COLOR, 6)
	column.add_child(_join_hint)
	return column


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


## A gamepad drawn from a few shapes, with whose it is written across it.
class ControllerIcon:
	extends Control

	var tag: String = ""
	var tint: Color = Color.WHITE
	var font: Font

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var dark: Color = MainMenu.OUTLINE
		# The outline first, a little bigger, then the pad itself over it.
		for pass_index: int in 2:
			var grow: float = 3.0 if pass_index == 0 else 0.0
			var color: Color = dark if pass_index == 0 else tint
			var body: StyleBoxFlat = StyleBoxFlat.new()
			body.bg_color = color
			body.set_corner_radius_all(int(h * 0.3 + grow))
			draw_style_box(body, Rect2(0.0, 0.0, w, h * 0.72).grow(grow))
			for grip_x: float in [w * 0.17, w * 0.83]:
				draw_circle(Vector2(grip_x, h * 0.66), h * 0.33 + grow, color)
		# The cross on the left and the four buttons on the right.
		var cross: Vector2 = Vector2(w * 0.17, h * 0.36)
		var arm: float = h * 0.17
		draw_rect(Rect2(cross.x - arm, cross.y - arm * 0.33, arm * 2.0, arm * 0.66), dark)
		draw_rect(Rect2(cross.x - arm * 0.33, cross.y - arm, arm * 0.66, arm * 2.0), dark)
		var buttons: Vector2 = Vector2(w * 0.83, h * 0.36)
		for offset: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_circle(buttons + offset * h * 0.13, h * 0.065, dark)
		const TAG_SIZE: int = 24
		draw_string(font, Vector2(0.0, h * 0.36 + TAG_SIZE * 0.36), tag, HORIZONTAL_ALIGNMENT_CENTER, w, TAG_SIZE, dark)
