extends SceneTree
## Headless check of the coach's tab on the play-select screen. First the lists
## themselves (PlayCaller.coach_offense and coach_defense) in a number of
## situations: nine different plays, goal line plays at the goal line only (and
## no deep pass there), the
## deepest throws on the last play, runs to kill the clock. Then the screen: it
## opens on the coach's nine, on offense and on defense, and (RB) goes on to the
## first tab of the book.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/ask_coach_check.gd

const NAMES: Array[String] = ["run", "short", "deep"]
## Ticks to wait for the play-select screen (it comes up behind a fade) and for
## a press to be taken.
const OPEN_TICKS: int = 240
const PRESS_TICKS: int = 12

var _game: Game
var _pc: PlayController
var _team: Team
var _failures: PackedStringArray = PackedStringArray()
## The sides still to open the screen on: true is the person on offense.
var _sides: Array[bool] = [true, false]
var _on_offense: bool = true
## 0 waiting for the screen, 1 (RB) held, 2 (RB) let go.
var _step: int = 0
var _ticks: int = 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready() or _game.play_controller == null or _game.offense == null:
		return
	if _pc == null:
		_pc = _game.play_controller
		_team = _game.human.team
		if _team == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_game.tuning.audio_enabled = false
		_check_lists()
		_open_next()
		return
	_ticks += 1
	var select: GameState = _pc.state_machine.current
	match _step:
		0:
			if _pc.state_machine.current_name() == &"PlaySelect" and select.time_in_state > 0.4:
				_check_screen(select)
				Input.action_press(&"page_next")
				_step = 1
				_ticks = 0
			elif _ticks > OPEN_TICKS:
				_failures.append("%s: the play-select screen did not come up" % _side())
				_open_next()
		1:
			if _ticks >= PRESS_TICKS:
				Input.action_release(&"page_next")
				_step = 2
				_ticks = 0
		2:
			if _ticks >= PRESS_TICKS:
				var plays: Array = select.get(&"_plays")
				_expect(int(select.get(&"_group")) == 1, "%s: (RB) went from the coach to tab %d" % [_side(), select.get(&"_group")])
				_expect(not plays.is_empty() and int(plays[0].get(&"group")) == 0, "%s: the tab after the coach's is not the first of the book" % _side())
				_expect(plays.size() == HUD.PAGE_SIZE, "%s: %d plays on the first tab of the book" % [_side(), plays.size()])
				_open_next()


# --- The lists ---------------------------------------------------------------

func _check_lists() -> void:
	_put(true, 2, 150.0, 0, 0, 50.0, 1, 30.0)
	var neutral: Array[OffensePlay] = _offense("tied, 2:30 left, midfield, 1st & 30")
	var neutral_defense: Array[DefensePlay] = _defense()
	var kinds: PackedInt32Array = _kinds(neutral)
	_expect(kinds[0] > 0 and kinds[1] > 0 and kinds[2] > 0, "neutral: a kind of play is missing (%s)" % [kinds])
	_expect(_goal_line(neutral) == 0, "neutral: %d goal line plays on offense" % _goal_line(neutral))
	_expect(_goal_line(neutral_defense) == 0, "neutral: %d goal line plays on defense" % _goal_line(neutral_defense))
	for play: OffensePlay in neutral:
		_expect(not play.heave_only, "neutral: the coach advises %s" % play.play_name)
	# Drawn afresh: the same down does not always get the same nine.
	var differs: bool = false
	for i: int in 20:
		var again: Array[OffensePlay] = _game.play_caller.coach_offense(_game.offense_playbook.plays, _game)
		for play: OffensePlay in again:
			differs = differs or not neutral.has(play)
	_expect(differs, "neutral: 20 more lists for the same down had the same nine plays")

	_put(true, 2, 150.0, 0, 0, 96.0, 1, 0.0)
	var near: Array[OffensePlay] = _offense("tied, 2:30 left, opp 4")
	var near_defense: Array[DefensePlay] = _defense()
	_expect(_goal_line(near) >= 5, "at the 4: only %d goal line plays on offense" % _goal_line(near))
	_expect(_kinds(near)[2] == 0, "at the 4: %d deep passes on the list" % _kinds(near)[2])
	_expect(_goal_line(near_defense) >= 5, "at the 4: only %d goal line plays on defense" % _goal_line(near_defense))

	_put(true, 2, 5.0, 0, 6, 20.0, 1, 30.0)
	_expect(_game.play_caller.situation(_game).heave, "down 6, 0:05 left, own 20: not a heave")
	var last: Array[OffensePlay] = _offense("down 6, 0:05 left, own 20")
	var last_defense: Array[DefensePlay] = _defense()
	kinds = _kinds(last)
	_expect(kinds[2] == last.size(), "last play: %d runs and %d short passes" % [kinds[0], kinds[1]])
	var heave_only: int = 0
	for i: int in last.size():
		if last[i].heave_only:
			heave_only += 1
		if i > 0:
			_expect(_heave_depth(last[i]) <= _heave_depth(last[i - 1]) + 0.001, "last play: %s comes before the deeper %s" % [last[i - 1].play_name, last[i].play_name])
	_expect(heave_only == 1, "last play: %d heave-only plays on the list" % heave_only)
	_expect(_mean_fit(last_defense, 2) > _mean_fit(neutral_defense, 2), "last play: the defense's list is no better against the deep ball")

	_put(true, 2, 40.0, 0, 6, 20.0, 1, 30.0)
	var hurry: Array[OffensePlay] = _offense("down 6, 0:40 left, own 20")
	_defense()
	kinds = _kinds(hurry)
	_expect(kinds[0] <= 2 and kinds[2] >= 4, "trailing with 0:40 left: %d runs, %d deep passes" % [kinds[0], kinds[2]])

	_put(true, 2, 10.0, 10, 6, 40.0, 1, 30.0)
	var kill: Array[OffensePlay] = _offense("up 4, 0:10 left, own 40")
	var kill_defense: Array[DefensePlay] = _defense()
	kinds = _kinds(kill)
	_expect(kinds[0] >= 5, "leading with 0:10 left: only %d runs" % kinds[0])
	_expect(_mean_fit(kill_defense, 0) > _mean_fit(neutral_defense, 0), "leading with 0:10 left: the defense's list is no better against the run")

	# A play called twice running is not advised a third time.
	_put(true, 2, 150.0, 0, 0, 50.0, 1, 30.0)
	var worn: OffensePlay = neutral[0]
	_game.play_caller.record(_team, worn, 3.0)
	_game.play_caller.record(_team, worn, 3.0)
	var advised: int = 0
	for i: int in 40:
		if _game.play_caller.coach_offense(_game.offense_playbook.plays, _game).has(worn):
			advised += 1
	_expect(advised <= 10, "%s, called twice running, is on %d of 40 lists" % [worn.play_name, advised])


## The person's team has the ball (`on_offense`) or the other one, on its own
## `yard` line, `off_score` to `def_score`. `to_go` of 0 leaves the marker
## where the drive puts it.
func _put(on_offense: bool, half: int, clock: float, off_score: int, def_score: int, yard: float, down: int, to_go: float) -> void:
	var team: Team = _team if on_offense else _team.opponent
	_game.conversion = false
	_game.half = half
	_game.clock = clock
	_game.start_drive(team, _game.tuning.yard_to_x(team.attack_dir, yard))
	team.score = off_score
	team.opponent.score = def_score
	_game.down = down
	if to_go > 0.0:
		_game.goal_to_go = false
		_game.first_down_x = _game.los_x + float(team.attack_dir) * to_go


func _offense(label: String) -> Array[OffensePlay]:
	var plays: Array[OffensePlay] = _game.play_caller.coach_offense(_game.offense_playbook.plays, _game)
	var names: PackedStringArray = PackedStringArray()
	for play: OffensePlay in plays:
		names.append("%s (%s)" % [play.play_name, NAMES[play.category]])
		_expect(plays.count(play) == 1, "%s: %s is on the offense's list %d times" % [label, play.play_name, plays.count(play)])
	_expect(plays.size() == HUD.PAGE_SIZE, "%s: %d plays on the offense's list" % [label, plays.size()])
	print("%s\n    offense: %s" % [label, ", ".join(names)])
	return plays


func _defense() -> Array[DefensePlay]:
	var plays: Array[DefensePlay] = _game.play_caller.coach_defense(_game.defense_playbook.plays, _game)
	var names: PackedStringArray = PackedStringArray()
	for play: DefensePlay in plays:
		names.append(play.play_name)
		_expect(plays.count(play) == 1, "%s is on the defense's list %d times" % [play.play_name, plays.count(play)])
	_expect(plays.size() == HUD.PAGE_SIZE, "%d plays on the defense's list" % plays.size())
	print("    defense: %s" % ", ".join(names))
	return plays


## How many runs, short and deep passes are on the list.
func _kinds(plays: Array[OffensePlay]) -> PackedInt32Array:
	var kinds: PackedInt32Array = PackedInt32Array([0, 0, 0])
	for play: OffensePlay in plays:
		kinds[play.category] += 1
	return kinds


func _goal_line(plays: Array) -> int:
	var found: int = 0
	for play: Resource in plays:
		if play.get(&"goal_line"):
			found += 1
	return found


## How deep the play throws for a last-play heave: a fake costs half of it.
func _heave_depth(play: OffensePlay) -> float:
	return play.deepest_route() * (0.5 if play.play_action or play.flea_flicker else 1.0)


func _mean_fit(plays: Array[DefensePlay], category: int) -> float:
	var total: float = 0.0
	for play: DefensePlay in plays:
		total += play.fit(category as OffensePlay.Category)
	return total / maxf(float(plays.size()), 1.0)


# --- The screen --------------------------------------------------------------

func _open_next() -> void:
	Input.action_release(&"page_next")
	if _sides.is_empty():
		_finish()
		return
	_on_offense = _sides.pop_front()
	_step = 0
	_ticks = 0
	if not _pc.ball_dead:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
	_put(_on_offense, 1, _game.tuning.game_length * 0.4, 0, 0, 40.0, 1, 0.0)
	_pc.state_machine.transition(&"PlaySelect")


## The screen as it comes up: the coach's tab open, nine cards on it, the book's
## tabs after it.
func _check_screen(select: GameState) -> void:
	var names: PackedStringArray = select.get(&"_group_names")
	var book: PackedStringArray = OffensePlay.GROUP_NAMES if _on_offense else DefensePlay.GROUP_NAMES
	var plays: Array = select.get(&"_plays")
	_expect(names.size() == book.size() + 1 and names[0] == HUD.COACH_TAB, "%s: the tabs are %s" % [_side(), names])
	_expect(int(select.get(&"_group")) == 0, "%s: the screen opened on tab %d" % [_side(), select.get(&"_group")])
	_expect(plays.size() == HUD.PAGE_SIZE, "%s: %d plays on the coach's tab" % [_side(), plays.size()])
	for play: Resource in plays:
		_expect((play is OffensePlay) == _on_offense, "%s: %s is a play of the other side" % [_side(), play.get(&"play_name")])
	var tabs: int = _game.hud.play_tabs.get_child_count()
	var cards: int = 0
	for child: Node in _game.hud.play_grid.get_children():
		if child is PanelContainer and not child.is_queued_for_deletion():
			cards += 1
	_expect(_game.hud.play_select.visible, "%s: the play-select panel is not up" % _side())
	_expect(tabs == names.size(), "%s: %d tabs drawn for %d" % [_side(), tabs, names.size()])
	_expect(cards == HUD.PAGE_SIZE, "%s: %d cards drawn" % [_side(), cards])


func _side() -> String:
	return "offense" if _on_offense else "defense"


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("ask_coach_check PASSED")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("ask_coach_check FAILED")
	quit(0 if _failures.is_empty() else 1)
