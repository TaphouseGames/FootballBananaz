extends GameState
## Both sides pick a play. The person picks from their side's playbook on a grid
## of cards; the CPU's PlayCaller picks for the other side.

const INPUT_LOCK: float = 0.25
const QUICK_PICKS: Array[StringName] = [&"play_1", &"play_2", &"play_3", &"play_4", &"play_5", &"play_6", &"play_7", &"play_8", &"play_9"]

var _cursor: int = 0
var _count: int = 0
var _human_on_offense: bool = false


func enter() -> void:
	# Show both teams at the new spot while the menu is up.
	pc.line_up(game.offense_playbook.plays[0], game.defense_playbook.plays[0])
	game.hud.hide_banner()
	if not game.human.is_active():
		return
	_human_on_offense = game.human.team == game.offense
	var plays: Array[Resource] = []
	if _human_on_offense:
		plays.assign(game.offense_playbook.plays)
	else:
		plays.assign(game.defense_playbook.plays)
	_count = plays.size()
	_cursor = 0
	var side: String = "OFFENSE" if _human_on_offense else "DEFENSE"
	game.hud.show_play_select("%s  -  %s" % [side, game.down_text()], plays)
	game.hud.set_hint("Move: choose      Space / (A): confirm      1-9: quick pick")


func exit() -> void:
	game.hud.hide_play_select()


func physics_update(_delta: float) -> void:
	if not game.human.is_active():
		if time_in_state >= 0.3:
			_confirm(-1)
		return
	if time_in_state < INPUT_LOCK:
		return
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

	for i: int in mini(QUICK_PICKS.size(), _count):
		if Input.is_action_just_pressed(QUICK_PICKS[i]):
			_confirm(i)
			return
	if Input.is_action_just_pressed(&"confirm"):
		_confirm(_cursor)


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
	if choice >= 0:
		if _human_on_offense:
			off_play = off_plays[choice]
		else:
			def_play = def_plays[choice]
	if off_play == null:
		off_play = game.play_caller.pick_offense(off_plays, game)
	if def_play == null:
		def_play = game.play_caller.pick_defense(def_plays, game)
	pc.line_up(off_play, def_play)
	machine.transition(&"PreSnap")
