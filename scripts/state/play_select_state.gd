extends GameState
## Both sides pick a play. The person picks from their side's playbook on a grid
## of cards; the CPU's PlayCaller picks for the other side.

const INPUT_LOCK: float = 0.25

## The plays of the person's side by tab (OffensePlay.Group or
## DefensePlay.Group) and the tabs' titles, the open tab and its plays, and the
## cursor's place and the number of cards on that tab.
var _groups: Array[Array] = []
var _group_names: PackedStringArray = PackedStringArray()
var _group: int = 0
var _plays: Array[Resource] = []
var _cursor: int = 0
var _count: int = 0
var _human_on_offense: bool = false
## The person wants their play mirrored left to right.
var _flipped: bool = false


func enter() -> void:
	# Show both teams at the new spot while the menu is up.
	pc.line_up(game.offense_playbook.plays[0], game.defense_playbook.plays[0])
	game.hud.hide_banner()
	if not game.human.is_active():
		return
	_human_on_offense = game.human.team == game.offense
	_group_names = OffensePlay.GROUP_NAMES if _human_on_offense else DefensePlay.GROUP_NAMES
	_groups.clear()
	for i: int in _group_names.size():
		_groups.append([])
	if _human_on_offense:
		for play: OffensePlay in game.offense_playbook.plays:
			_groups[play.group].append(play)
	else:
		for play: DefensePlay in game.defense_playbook.plays:
			_groups[play.group].append(play)
	_group = 0
	_flipped = false
	_show_group()
	_show_hint()


func exit() -> void:
	game.hud.hide_play_select()
	game.hud.hide_countdown()
	game.hud.set_hint("")


## Under the cards: the buttons that pick a play and mirror it.
func _show_hint() -> void:
	var text: String = "(LB/RB) Category      (A) Pick play      (X) Flip play"
	if _flipped:
		text += "  -  FLIPPED"
	game.hud.set_hint(text)


## Puts the open tab's cards on screen with the cursor on the first one.
func _show_group() -> void:
	_plays.assign(_groups[_group])
	_count = _plays.size()
	_cursor = 0
	var title: String = "%s  -  %s" % ["OFFENSE" if _human_on_offense else "DEFENSE", game.down_text()]
	game.hud.show_play_select(title, _group_names, _group, _plays)
	game.hud.set_play_flipped(_flipped)


func physics_update(delta: float) -> void:
	if not game.human.is_active():
		if time_in_state >= 0.3:
			_confirm(null)
		return
	# Out of time: the highlighted play it is.
	if count_down(game.tuning.play_select_time, delta):
		game.audio.play(&"ui_confirm")
		_confirm(_plays[_cursor])
		return
	if time_in_state < INPUT_LOCK:
		return
	var turn: int = int(Input.is_action_just_pressed(&"page_next")) - int(Input.is_action_just_pressed(&"page_prev"))
	if turn != 0:
		# Past a tab with no plays on it.
		for i: int in _groups.size():
			_group = posmod(_group + turn, _groups.size())
			if not _groups[_group].is_empty():
				break
		_show_group()
		game.audio.play(&"ui_page")
	var moved: int = _cursor
	if Input.is_action_just_pressed(&"move_right"):
		moved = _step(_cursor, 1, 0)
	elif Input.is_action_just_pressed(&"move_left"):
		moved = _step(_cursor, -1, 0)
	elif Input.is_action_just_pressed(&"move_down"):
		moved = _step(_cursor, 0, 1)
	elif Input.is_action_just_pressed(&"move_up"):
		moved = _step(_cursor, 0, -1)
	if moved != _cursor:
		_cursor = moved
		game.hud.set_play_cursor(_cursor)
		game.audio.play(&"ui_move")

	if Input.is_action_just_pressed(&"flip_play"):
		_flipped = not _flipped
		game.hud.set_play_flipped(_flipped)
		_show_hint()
		game.audio.play(&"ui_flip")
	if Input.is_action_just_pressed(&"confirm"):
		game.audio.play(&"ui_confirm")
		_confirm(_plays[_cursor])


## Moves the cursor one card across or down the grid, wrapping at the edges.
func _step(from: int, dx: int, dy: int) -> int:
	var columns: int = HUD.GRID_COLUMNS
	@warning_ignore("integer_division")
	var rows: int = (_count + columns - 1) / columns
	@warning_ignore("integer_division")
	var row: int = posmod(from / columns + dy, rows)
	var column: int = posmod(from % columns + dx, columns)
	var to: int = row * columns + column
	return to if to < _count else from


## `choice` is the person's pick, or null when the CPU picks for both sides.
func _confirm(choice: Resource) -> void:
	var off_plays: Array[OffensePlay] = game.offense_playbook.plays
	var def_plays: Array[DefensePlay] = game.defense_playbook.plays
	var off_play: OffensePlay = choice as OffensePlay
	var def_play: DefensePlay = choice as DefensePlay
	# The person's flip is for their own play. The CPU runs its plays to either side.
	var off_flipped: bool = _flipped
	var def_flipped: bool = _flipped
	if off_play == null:
		off_play = game.play_caller.pick_offense(off_plays, game)
		off_flipped = randf() < 0.5
	if def_play == null:
		def_play = game.play_caller.pick_defense(def_plays, game)
		def_flipped = randf() < 0.5
	pc.line_up(off_play, def_play, off_flipped, def_flipped)
	machine.transition(&"PreSnap")
