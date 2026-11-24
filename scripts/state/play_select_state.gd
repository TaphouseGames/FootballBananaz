extends GameState
## Both sides pick a play. A person picks from their side's playbook on a grid
## of cards; the CPU's PlayCaller picks for a side nobody plays. The first tab
## is the coach's: the plays of the book that fit the situation best
## (PlayCaller.coach_offense and coach_defense).
##
## With two people playing each has their own half of the screen (the home
## team's on the left) and their own gamepad, and both pick at once. A side that
## has picked shows READY and waits for the other; the clock picks the
## highlighted card for whoever is not in when it runs out.

const INPUT_LOCK: float = 0.25
## The place of the coach's tab (HUD.COACH_TAB) among the tabs. The book's tabs
## follow it in Group order.
const COACH_GROUP: int = 0

## One person at the cards: the plays of their side by tab (the coach's, then
## one per OffensePlay.Group or DefensePlay.Group) and the tabs' titles, the
## open tab and its plays, and the cursor's place and the number of cards on
## that tab.
class Picker:
	var human: HumanController
	## Their panel on the HUD: 0, or with two playing 0 left and 1 right.
	var slot: int = 0
	var on_offense: bool = false
	var groups: Array[Array] = []
	var group_names: PackedStringArray = PackedStringArray()
	var group: int = 0
	var plays: Array[Resource] = []
	var cursor: int = 0
	var count: int = 0
	## They want their play mirrored left to right.
	var flipped: bool = false
	## The play they picked, once they have.
	var choice: Resource


## The people picking, in the order of Game.humans. Nobody in autoplay.
var _pickers: Array[Picker] = []

## The first person's tab, cards and cursor (the tests look at them).
var _group: int:
	get:
		return _pickers[0].group if not _pickers.is_empty() else 0
var _group_names: PackedStringArray:
	get:
		return _pickers[0].group_names if not _pickers.is_empty() else PackedStringArray()
var _plays: Array[Resource]:
	get:
		return _pickers[0].plays if not _pickers.is_empty() else ([] as Array[Resource])
var _cursor: int:
	get:
		return _pickers[0].cursor if not _pickers.is_empty() else 0


func enter() -> void:
	# Show both teams at the new spot while the menu is up.
	pc.line_up(game.offense_playbook.plays[0], game.defense_playbook.plays[0])
	game.hud.hide_banner()
	game.coach_plays.clear()
	_pickers.clear()
	for person: HumanController in game.humans:
		if person.is_active():
			_pickers.append(_seat(person))
	for picker: Picker in _pickers:
		_show_group(picker)
		_show_hint(picker)


## `person` at the cards of their side, on the coach's tab.
func _seat(person: HumanController) -> Picker:
	var picker: Picker = Picker.new()
	picker.human = person
	picker.slot = game.screen_slot(person)
	picker.on_offense = person.team == game.offense
	picker.group_names = PackedStringArray([HUD.COACH_TAB])
	picker.group_names.append_array(OffensePlay.GROUP_NAMES if picker.on_offense else DefensePlay.GROUP_NAMES)
	for i: int in picker.group_names.size():
		picker.groups.append([])
	if picker.on_offense:
		picker.groups[COACH_GROUP].assign(game.play_caller.coach_offense(game.offense_playbook.plays, game))
		for play: OffensePlay in game.offense_playbook.plays:
			picker.groups[_tab_of(play)].append(play)
	else:
		picker.groups[COACH_GROUP].assign(game.play_caller.coach_defense(game.defense_playbook.plays, game))
		for play: DefensePlay in game.defense_playbook.plays:
			picker.groups[_tab_of(play)].append(play)
	# Kept for the audible menu at the line, which takes its side's from them.
	game.coach_plays.append_array(picker.groups[COACH_GROUP])
	# The coach's tab, or the first of the book with nothing on that.
	picker.group = COACH_GROUP
	while picker.groups[picker.group].is_empty() and picker.group < picker.groups.size() - 1:
		picker.group += 1
	return picker


func exit() -> void:
	game.hud.hide_play_select()
	game.hud.hide_countdown()
	game.hud.set_hint("")


## Under the cards: the buttons that pick a play and mirror it.
func _show_hint(picker: Picker) -> void:
	var text: String = "(LB/RB) Category      (A) Pick play      (X) Flip play"
	if _split():
		text = "(LB/RB) Category   (A) Pick   (X) Flip"
	if picker.flipped:
		text += "  -  FLIPPED"
	if picker.choice != null:
		text = "READY"
	game.hud.set_play_hint(text, picker.slot)


## Puts the open tab's cards on screen with the cursor on the first one.
func _show_group(picker: Picker) -> void:
	picker.plays.assign(picker.groups[picker.group])
	picker.count = picker.plays.size()
	picker.cursor = 0
	var title: String = "%s  -  %s" % ["OFFENSE" if picker.on_offense else "DEFENSE", game.down_text()]
	if _split():
		title = "%s  %s" % [picker.human.team.short_name, title]
	# The coach's plays are from all over the book: each card says where from.
	var notes: PackedStringArray = PackedStringArray()
	if picker.group == COACH_GROUP:
		for play: Resource in picker.plays:
			notes.append(picker.group_names[_tab_of(play)])
	game.hud.show_play_select(title, picker.group_names, picker.group, picker.plays, notes, picker.slot)
	game.hud.set_play_flipped(picker.flipped, picker.slot)


func physics_update(delta: float) -> void:
	if _pickers.is_empty():
		if time_in_state >= 0.3:
			_confirm()
		return
	# Out of time: the highlighted play it is, for whoever has not picked.
	if count_down(game.tuning.play_select_time, delta):
		game.audio.play(&"ui_confirm")
		for picker: Picker in _pickers:
			if picker.choice == null:
				picker.choice = picker.plays[picker.cursor]
		_confirm()
		return
	if time_in_state < INPUT_LOCK:
		return
	var waiting: bool = false
	for picker: Picker in _pickers:
		if picker.choice == null:
			# The sounds of their own cards are theirs alone, online.
			NetEvents.audience = picker.human.seat
			_update(picker)
			NetEvents.audience = NetEvents.EVERYONE
		waiting = waiting or picker.choice == null
	if not waiting:
		_confirm()


## One person's buttons, until they have picked.
func _update(picker: Picker) -> void:
	var pad: PadInput = picker.human.pad
	var turn: int = int(pad.just_pressed(&"page_next")) - int(pad.just_pressed(&"page_prev"))
	if turn != 0:
		# Past a tab with no plays on it.
		for i: int in picker.groups.size():
			picker.group = posmod(picker.group + turn, picker.groups.size())
			if not picker.groups[picker.group].is_empty():
				break
		_show_group(picker)
		game.audio.play(&"ui_page")
	var moved: int = picker.cursor
	if pad.just_pressed(&"move_right"):
		moved = _step(picker, 1, 0)
	elif pad.just_pressed(&"move_left"):
		moved = _step(picker, -1, 0)
	elif pad.just_pressed(&"move_down"):
		moved = _step(picker, 0, 1)
	elif pad.just_pressed(&"move_up"):
		moved = _step(picker, 0, -1)
	if moved != picker.cursor:
		picker.cursor = moved
		game.hud.set_play_cursor(picker.cursor, picker.slot)
		game.audio.play(&"ui_move")

	if pad.just_pressed(&"flip_play"):
		picker.flipped = not picker.flipped
		game.hud.set_play_flipped(picker.flipped, picker.slot)
		_show_hint(picker)
		game.audio.play(&"ui_flip")
	if pad.just_pressed(&"confirm"):
		game.audio.play(&"ui_confirm")
		picker.choice = picker.plays[picker.cursor]
		# Their half says so while the other person is still choosing.
		game.hud.set_play_ready(true, picker.slot)
		_show_hint(picker)


## Two people have a half of one screen each. Not online: there each has a
## screen of their own, and it looks as it does for one person.
func _split() -> bool:
	return _pickers.size() > 1 and Game.net_mode != Game.NetMode.SERVER


## The tab of the book `play` is on.
func _tab_of(play: Resource) -> int:
	var group: int = (play as OffensePlay).group if play is OffensePlay else (play as DefensePlay).group
	return group + 1


## Moves the cursor one card across or down the grid, wrapping at the edges.
func _step(picker: Picker, dx: int, dy: int) -> int:
	var from: int = picker.cursor
	var columns: int = HUD.GRID_COLUMNS
	@warning_ignore("integer_division")
	var rows: int = (picker.count + columns - 1) / columns
	@warning_ignore("integer_division")
	var row: int = posmod(from / columns + dy, rows)
	var column: int = posmod(from % columns + dx, columns)
	var to: int = row * columns + column
	return to if to < picker.count else from


## Lines both teams up for the plays picked. The CPU picks for a side with no
## person on it.
func _confirm() -> void:
	var off_plays: Array[OffensePlay] = game.offense_playbook.plays
	var def_plays: Array[DefensePlay] = game.defense_playbook.plays
	var off_play: OffensePlay = null
	var def_play: DefensePlay = null
	# A person's flip is for their own play. The CPU runs its plays to either side.
	var off_flipped: bool = false
	var def_flipped: bool = false
	for picker: Picker in _pickers:
		if picker.on_offense:
			off_play = picker.choice as OffensePlay
			off_flipped = picker.flipped
		else:
			def_play = picker.choice as DefensePlay
			def_flipped = picker.flipped
	if off_play == null:
		off_play = game.play_caller.pick_offense(off_plays, game)
		off_flipped = randf() < 0.5
	if def_play == null:
		def_play = game.play_caller.pick_defense(def_plays, game)
		# A one-sided play goes to the side of the formation it is meant for.
		def_flipped = DefenseAligner.cpu_flip(def_play, off_play, off_flipped)
	pc.line_up(off_play, def_play, off_flipped, def_flipped)
	machine.transition(&"PreSnap")
