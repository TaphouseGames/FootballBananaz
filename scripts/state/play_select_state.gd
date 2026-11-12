extends GameState
## Both sides pick a play. The person picks from their side's playbook on a grid
## of cards; the CPU's PlayCaller picks for the other side.

const INPUT_LOCK: float = 0.25

## Every play of the person's side, the page of them on screen, and the cursor's
## place and the number of cards on that page.
var _plays: Array[Resource] = []
var _page: int = 0
var _cursor: int = 0
var _count: int = 0
var _human_on_offense: bool = false
## The person wants their offensive play mirrored left to right.
var _flipped: bool = false


func enter() -> void:
	# Show both teams at the new spot while the menu is up.
	pc.line_up(game.offense_playbook.plays[0], game.defense_playbook.plays[0])
	game.hud.hide_banner()
	if not game.human.is_active():
		return
	_human_on_offense = game.human.team == game.offense
	if _human_on_offense:
		_plays.assign(game.offense_playbook.plays)
	else:
		_plays.assign(game.defense_playbook.plays)
	_page = 0
	_flipped = false
	_show_page()
	var hint: String = "Stick / D-pad: choose      (A): confirm"
	if _human_on_offense:
		hint += "      (X): flip play"
	if _page_count() > 1:
		hint += "      (LB) / (RB): page"
	game.hud.set_hint(hint)


func exit() -> void:
	game.hud.hide_play_select()


func _page_count() -> int:
	@warning_ignore("integer_division")
	return maxi((_plays.size() + HUD.PAGE_SIZE - 1) / HUD.PAGE_SIZE, 1)


## Puts the current page's cards on screen with the cursor on the first one.
func _show_page() -> void:
	var first: int = _page * HUD.PAGE_SIZE
	var cards: Array[Resource] = _plays.slice(first, first + HUD.PAGE_SIZE)
	_count = cards.size()
	_cursor = 0
	var title: String = "%s  -  %s" % ["OFFENSE" if _human_on_offense else "DEFENSE", game.down_text()]
	if _page_count() > 1:
		title += "  -  PAGE %d/%d" % [_page + 1, _page_count()]
	game.hud.show_play_select(title, cards)
	game.hud.set_play_flipped(_flipped)


func physics_update(_delta: float) -> void:
	if not game.human.is_active():
		if time_in_state >= 0.3:
			_confirm(-1)
		return
	if time_in_state < INPUT_LOCK:
		return
	var turn: int = int(Input.is_action_just_pressed(&"page_next")) - int(Input.is_action_just_pressed(&"page_prev"))
	if turn != 0 and _page_count() > 1:
		_page = posmod(_page + turn, _page_count())
		_show_page()
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

	if _human_on_offense and Input.is_action_just_pressed(&"flip_play"):
		_flipped = not _flipped
		game.hud.set_play_flipped(_flipped)
		game.audio.play(&"ui_flip")
	if Input.is_action_just_pressed(&"confirm"):
		game.audio.play(&"ui_confirm")
		_confirm(_page * HUD.PAGE_SIZE + _cursor)


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


## `choice` is the person's pick, or -1 when the CPU picks for both sides.
func _confirm(choice: int) -> void:
	var off_plays: Array[OffensePlay] = game.offense_playbook.plays
	var def_plays: Array[DefensePlay] = game.defense_playbook.plays
	var off_play: OffensePlay = null
	var def_play: DefensePlay = null
	var flipped: bool = false
	if choice >= 0:
		if _human_on_offense:
			off_play = off_plays[choice]
			flipped = _flipped
		else:
			def_play = def_plays[choice]
	if off_play == null:
		off_play = game.play_caller.pick_offense(off_plays, game)
		# The CPU runs its plays to either side.
		flipped = randf() < 0.5
	if def_play == null:
		def_play = game.play_caller.pick_defense(def_plays, game)
	pc.line_up(off_play, def_play, flipped)
	machine.transition(&"PreSnap")
