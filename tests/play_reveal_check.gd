extends SceneTree
## Headless check of the play drawn on the field before the snap (left trigger
## and the stick), once with the person on offense and once on defense:
##   alone     the trigger by itself draws nothing
##   up        trigger and stick up draws the play that was called
##   fakes     left, right and down each draw another play of the same
##             formation (tab), the same one when pushed again
##   release   letting go of the trigger takes the drawing away
##   snap      so does the snap
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/play_reveal_check.gd

const ACTIONS: Array[StringName] = [&"reveal_play", &"move_up", &"move_left", &"move_right", &"move_down"]
const WAYS: Array[StringName] = [&"move_left", &"move_right", &"move_down"]

var _game: Game
var _pc: PlayController
var _team: Team
var _failures: PackedStringArray = PackedStringArray()
var _sync_done: bool = false
## Each step is a wait in ticks and then a call.
var _steps: Array[Array] = []
var _wait: int = 0
## What each way of the stick drew the first time.
var _seen: Dictionary[StringName, Resource] = {}


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready() or _game.play_controller == null or _game.offense == null:
		return
	if not _sync_done:
		_sync_done = true
		_pc = _game.play_controller
		_team = _game.human.team
		if _team == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_game.tuning.audio_enabled = false
		# Nor does the CPU change its play at the line.
		_game.tuning.ai_audible_chance = 0.0
		_game.tuning.ai_hot_route_chance = 0.0
		# Nobody snaps the ball while the test looks at the drawing.
		_game.tuning.play_clock = 0.0
		_game.tuning.cpu_snap_delay_min = 60.0
		_game.tuning.cpu_snap_delay_max = 60.0
		_plan(true)
		_plan(false)
		return
	if _wait > 0:
		_wait -= 1
		return
	if _steps.is_empty():
		_finish()
		return
	var step: Array = _steps.pop_front()
	_wait = int(step[0])
	(step[1] as Callable).call()


func _plan(on_offense: bool) -> void:
	var side: String = "offense" if on_offense else "defense"
	var art: Callable = func() -> PlayArt: return _game.play_art
	_steps.append([20, _pre_snap.bind(on_offense)])
	_steps.append([3, func() -> void:
		_seen.clear()
		_expect(_pc.state_machine.current_name() == &"PreSnap", "%s: not in PreSnap" % side)
		_expect((art.call() as PlayArt).shown == null, "%s: a play is drawn with nothing held" % side)
		Input.action_press(&"reveal_play")])
	_steps.append([3, func() -> void:
		_expect((art.call() as PlayArt).shown == null, "%s: the trigger by itself draws a play" % side)
		Input.action_press(&"move_up")])
	_steps.append([3, func() -> void:
		var shown: Resource = (art.call() as PlayArt).shown
		_expect(shown != null and shown == _real(on_offense), "%s: stick up does not draw the called play" % side)
		_expect((art.call() as PlayArt).triangles > 0, "%s: the called play is drawn with nothing in it" % side)
		Input.action_release(&"move_up")])
	for way: StringName in WAYS:
		_steps.append([2, func() -> void: Input.action_press(way)])
		_steps.append([3, func() -> void:
			var shown: Resource = (art.call() as PlayArt).shown
			_expect(shown != null, "%s: %s draws nothing" % [side, way])
			if shown != null:
				_expect(shown != _real(on_offense), "%s: %s draws the called play" % [side, way])
				_expect(_group(shown) == _group(_real(on_offense)), "%s: %s draws a play of another formation" % [side, way])
				_expect((art.call() as PlayArt).triangles > 0, "%s: %s draws a play with nothing in it" % [side, way])
			_seen[way] = shown
			Input.action_release(way)])
	_steps.append([2, func() -> void:
		if _others(on_offense) >= WAYS.size():
			_expect(_seen[WAYS[0]] != _seen[WAYS[1]] and _seen[WAYS[1]] != _seen[WAYS[2]] and _seen[WAYS[0]] != _seen[WAYS[2]],
				"%s: two ways of the stick draw the same fake" % side)
		Input.action_press(WAYS[0])])
	_steps.append([3, func() -> void:
		_expect((art.call() as PlayArt).shown == _seen[WAYS[0]], "%s: the same way draws another fake the second time" % side)
		Input.action_release(&"reveal_play")])
	_steps.append([3, func() -> void:
		_expect((art.call() as PlayArt).shown == null, "%s: the drawing stays with the trigger let go" % side)
		Input.action_release(WAYS[0])
		Input.action_press(&"reveal_play")
		Input.action_press(&"move_up")])
	_steps.append([3, func() -> void:
		_expect((art.call() as PlayArt).shown == _real(on_offense), "%s: no drawing before the snap" % side)
		_pc.snap()
		_pc.state_machine.transition(&"Live")])
	_steps.append([3, func() -> void:
		_expect((art.call() as PlayArt).shown == null, "%s: the drawing is still there after the snap" % side)
		_release()
		print("%s: checked" % side)])


func _pre_snap(on_offense: bool) -> void:
	if not _pc.ball_dead:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
	var with_ball: Team = _team if on_offense else _team.opponent
	_game.start_drive(with_ball, _game.tuning.yard_to_x(with_ball.attack_dir, 30.0))
	_pc.line_up(_play("gun stick"), _defense("man cover 1"))
	_pc.state_machine.transition(&"PreSnap")


func _real(on_offense: bool) -> Resource:
	return _pc.off_play if on_offense else _pc.def_play


func _group(play: Resource) -> int:
	if play is OffensePlay:
		return (play as OffensePlay).group
	return (play as DefensePlay).group if play is DefensePlay else -1


## How many other plays the called play's formation has.
func _others(on_offense: bool) -> int:
	var count: int = 0
	if on_offense:
		for play: OffensePlay in _game.offense_playbook.plays:
			if play != _pc.off_play and play.group == _pc.off_play.group:
				count += 1
	else:
		for play: DefensePlay in _game.defense_playbook.plays:
			if play != _pc.def_play and play.group == _pc.def_play.group:
				count += 1
	return count


func _play(play_name: String) -> OffensePlay:
	for play: OffensePlay in _game.offense_playbook.plays:
		if play.play_name.to_lower() == play_name:
			return play
	_failures.append("no offensive play called %s" % play_name)
	return _game.offense_playbook.plays[0]


func _defense(play_name: String) -> DefensePlay:
	for play: DefensePlay in _game.defense_playbook.plays:
		if play.play_name.to_lower() == play_name:
			return play
	_failures.append("no defensive play called %s" % play_name)
	return _game.defense_playbook.plays[0]


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _release() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	_release()
	for failure: String in _failures:
		print("FAIL: " + failure)
	print("play_reveal_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
