extends GameState
## Both sides pick a play. The person picks from their side's playbook; the CPU
## picks at random.

const INPUT_LOCK: float = 0.25

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
	var names: PackedStringArray = PackedStringArray()
	var descriptions: PackedStringArray = PackedStringArray()
	if _human_on_offense:
		for play: OffensePlay in game.offense_playbook.plays:
			names.append(play.play_name)
			descriptions.append(play.description)
	else:
		for play: DefensePlay in game.defense_playbook.plays:
			names.append(play.play_name)
			descriptions.append(play.description)
	_count = names.size()
	_cursor = 0
	var side: String = "OFFENSE" if _human_on_offense else "DEFENSE"
	game.hud.show_play_select("%s  -  %s" % [side, game.down_text()], names, descriptions)
	game.hud.set_hint("Up / Down: choose      Space / (A): confirm      1-3: quick pick")


func exit() -> void:
	game.hud.hide_play_select()


func physics_update(_delta: float) -> void:
	if not game.human.is_active():
		if time_in_state >= 0.3:
			_confirm(-1)
		return
	if time_in_state < INPUT_LOCK:
		return
	if Input.is_action_just_pressed(&"move_down"):
		_cursor = (_cursor + 1) % _count
		game.hud.set_play_cursor(_cursor)
	elif Input.is_action_just_pressed(&"move_up"):
		_cursor = (_cursor + _count - 1) % _count
		game.hud.set_play_cursor(_cursor)

	var quick_picks: Array[StringName] = [&"play_1", &"play_2", &"play_3"]
	for i: int in mini(quick_picks.size(), _count):
		if Input.is_action_just_pressed(quick_picks[i]):
			_confirm(i)
			return
	if Input.is_action_just_pressed(&"pass_switch"):
		_confirm(_cursor)


## `choice` is the person's pick, or -1 when the CPU picks for both sides.
func _confirm(choice: int) -> void:
	var off_plays: Array[OffensePlay] = game.offense_playbook.plays
	var def_plays: Array[DefensePlay] = game.defense_playbook.plays
	var off_play: OffensePlay = off_plays[randi() % off_plays.size()]
	var def_play: DefensePlay = def_plays[randi() % def_plays.size()]
	if choice >= 0:
		if _human_on_offense:
			off_play = off_plays[choice]
		else:
			def_play = def_plays[choice]
	pc.line_up(off_play, def_play)
	machine.transition(&"PreSnap")
