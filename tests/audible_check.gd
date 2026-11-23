extends SceneTree
## Headless check of changing the play at the line, with the person on offense
## and then on defense:
##   menu      (X) opens it, (A) on the called play closes it without a snap,
##             another play of the formation is called with nobody moving
##   family    (LB) and (RB) only reach the formations of the called one's
##             family; a play of another one is walked to, the snap waits for
##             it, and everybody ends on the new spots
##   quick     the right stick: down a run, left a short pass, up a deep one,
##             right the called play mirrored
##   hot       (Y), a receiver's button and the stick give him a new route; the
##             back and a blocker cannot be given one; who can be thrown to
##             stays as it was
##   motion    the bumpers send the motion man, (Y) does not; after that, and
##             after the snap, the play cannot be changed
##   defense   the menu and the quick audible on defense; the defender the
##             person had picked stays theirs; no hot routes
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/audible_check.gd

const ACTIONS: Array[StringName] = [
	&"audible", &"hot_route", &"motion", &"page_prev", &"page_next", &"confirm", &"back", &"flip_play", &"reveal_play",
	&"move_up", &"move_left", &"move_right", &"move_down",
	&"quick_up", &"quick_left", &"quick_right", &"quick_down",
	&"pass_1", &"pass_2", &"pass_3", &"pass_4",
]
## Ticks a walk to a new formation is given.
const WALK: int = 480
const LINE: int = 0
const MENU: int = 1
const HOT: int = 2

var _game: Game
var _pc: PlayController
var _team: Team
var _state: Node
var _failures: PackedStringArray = PackedStringArray()
var _sync_done: bool = false
## Each step is a wait in ticks and then a call.
var _steps: Array[Array] = []
var _wait: int = 0
## What a step leaves for a later one.
var _kept: Dictionary[String, Variant] = {}


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
		_state = _pc.state_machine.get_node(^"PreSnap")
		if _team == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_game.tuning.audio_enabled = false
		# Nobody snaps the ball or sends a man while the test is at the line.
		_game.tuning.play_clock = 0.0
		_game.tuning.cpu_snap_delay_min = 600.0
		_game.tuning.cpu_snap_delay_max = 600.0
		_game.tuning.ai_motion_chance = 0.0
		_check_rules()
		_plan_offense()
		_plan_defense()
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


# --- The rules, without the field -------------------------------------------------

func _check_rules() -> void:
	var g: Dictionary = OffensePlay.Group
	_expect(OffensePlay.audible_groups(g.I_FORM) == [g.I_FORM, g.SINGLEBACK, g.HEAVY, g.GOAL_LINE], "family: I-Form reaches %s" % [OffensePlay.audible_groups(g.I_FORM)])
	_expect(OffensePlay.audible_groups(g.SINGLEBACK) == [g.SINGLEBACK, g.I_FORM, g.HEAVY], "family: Singleback reaches %s" % [OffensePlay.audible_groups(g.SINGLEBACK)])
	_expect(OffensePlay.audible_groups(g.GUN_SPREAD) == [g.GUN_SPREAD, g.GUN_TRIPS], "family: Gun Spread reaches %s" % [OffensePlay.audible_groups(g.GUN_SPREAD)])
	_expect(OffensePlay.audible_groups(g.GOAL_LINE) == [g.GOAL_LINE, g.I_FORM, g.HEAVY], "family: Goal Line reaches %s" % [OffensePlay.audible_groups(g.GOAL_LINE)])
	_expect(_buttons(&"motion") == [9, 10], "motion: it is on buttons %s, not the bumpers" % [_buttons(&"motion")])
	_expect(_buttons(&"hot_route") == [3], "hot: it is on buttons %s, not (Y)" % [_buttons(&"hot_route")])
	_expect(_buttons(&"audible") == [2], "menu: it is on buttons %s, not (X)" % [_buttons(&"audible")])


func _buttons(action: StringName) -> Array[int]:
	var found: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			found.append((event as InputEventJoypadButton).button_index)
	found.sort()
	return found


# --- Offense ---------------------------------------------------------------------

func _plan_offense() -> void:
	_steps.append([45, _pre_snap.bind(true, OffensePlay.Group.I_FORM)])

	# The menu, and a play of the same formation.
	_tap(&"audible")
	_steps.append([0, func() -> void:
		_expect(_mode() == MENU and _game.hud.audible_shown(), "menu: (X) did not open it")
		_expect(_state.get("_menu_groups") == OffensePlay.audible_groups(_pc.off_play.group), "family: the menu goes to %s" % [_state.get("_menu_groups")])])
	_tap(&"confirm")
	_steps.append([0, func() -> void:
		_expect(_in_pre_snap(), "menu: (A) in the menu snapped the ball")
		_expect(_mode() == LINE and not _game.hud.audible_shown(), "menu: (A) on the called play did not close it")
		_kept["play"] = _pc.off_play
		_kept["spots"] = _spots(_game.offense)
		_kept["eligible"] = _pc.eligible.duplicate()])
	_tap(&"audible")
	_tap(&"move_down")
	_tap(&"confirm")
	_steps.append([0, func() -> void:
		var was: OffensePlay = _kept["play"]
		_expect(_in_pre_snap(), "menu: calling a play snapped the ball")
		_expect(_pc.off_play != was, "menu: the play was not changed")
		_expect(_pc.off_play.group == was.group, "menu: one step down left the formation")
		_expect(not _pc.shift.active(), "menu: a play of the same formation has somebody walking")
		_expect(_spots(_game.offense) == _kept["spots"], "menu: a play of the same formation moved somebody")
		_expect(not _game.hud.audible_shown(), "menu: still open after the call")
		_expect(_game.stats.get(&"audibles", 0) == 1, "menu: %d audibles counted, not 1" % _game.stats.get(&"audibles", 0))])

	# Left and right go between the columns of plays, not to another formation.
	_tap(&"audible")
	_steps.append([0, func() -> void:
		_kept["cursor"] = _state.get("_menu_cursor")
		_kept["group"] = _state.get("_menu_group")])
	_tap(&"move_right")
	_steps.append([0, func() -> void:
		var was: int = _kept["cursor"]
		var count: int = (_state.get("_menu_plays") as Array).size()
		var rows: int = AudibleMenu.COLUMN_ROWS
		@warning_ignore("integer_division")
		var want: int = mini(was + rows, count - 1) if was / rows < (count - 1) / rows else was
		_expect(_state.get("_menu_cursor") == want, "menu: right moved the cursor from %d to %d of %d, not to %d" % [was, _state.get("_menu_cursor"), count, want])
		_expect(_state.get("_menu_group") == _kept["group"], "menu: right changed the formation")
		_kept["cursor"] = want])
	_tap(&"move_left")
	_steps.append([0, func() -> void:
		# The same row of the column to the left, when there is one.
		var was: int = _kept["cursor"]
		var rows: int = AudibleMenu.COLUMN_ROWS
		var want: int = was - rows if was >= rows else was
		_expect(_state.get("_menu_cursor") == want, "menu: left moved the cursor from %d to %d, not to %d" % [was, _state.get("_menu_cursor"), want])])
	_tap(&"back")
	# Another formation of the family.
	_tap(&"audible")
	_tap(&"page_next")
	_tap(&"confirm")
	_steps.append([0, func() -> void:
		_expect(_pc.off_play.group == OffensePlay.audible_groups(OffensePlay.Group.I_FORM)[1], "family: (RB) did not go to the next formation of the family")
		_expect(_pc.shift.active(_game.offense), "family: nobody walks to the new formation")])
	_tap(&"confirm")
	_steps.append([0, func() -> void: _expect(_in_pre_snap(), "family: the ball was snapped while they walked")])
	_tap(&"audible")
	_steps.append([WALK, func() -> void: _expect(_mode() == LINE, "family: the menu opened while they walked")])
	_steps.append([0, func() -> void:
		_expect(not _pc.shift.active(), "family: still walking after %d ticks" % WALK)
		_expect(_on_spots(), "family: somebody is not on his new spot")])

	# Quick audibles.
	for way: Array in [[&"quick_down", OffensePlay.Category.RUN], [&"quick_left", OffensePlay.Category.SHORT], [&"quick_up", OffensePlay.Category.DEEP]]:
		_steps.append([0, func() -> void: _kept["play"] = _pc.off_play])
		_tap(way[0])
		_steps.append([0, func() -> void:
			var was: OffensePlay = _kept["play"]
			if OffensePlay.quick_pick(_game.offense_playbook.plays, was, way[1]) == null:
				_expect(_pc.off_play == was, "quick: %s changed the play with nothing to call" % way[0])
				return
			_expect(_pc.off_play != was and _pc.off_play.group == was.group, "quick: %s did not call another play of the formation" % way[0])
			_expect(_pc.off_play.category == way[1], "quick: %s called a play of kind %d" % [way[0], _pc.off_play.category])
			_expect(not _pc.shift.active(), "quick: %s has somebody walking" % way[0])])
	_steps.append([0, func() -> void:
		_kept["play"] = _pc.off_play
		_kept["flipped"] = _pc.off_flipped])
	_tap(&"quick_right")
	_steps.append([WALK, func() -> void:
		_expect(_pc.off_play == _kept["play"], "quick: right changed the play")
		_expect(_pc.off_flipped != _kept["flipped"], "quick: right did not mirror the play")])
	_steps.append([0, func() -> void: _expect(not _pc.shift.active() and _on_spots(), "quick: not set after the play was mirrored")])

	# Hot routes, on a pass play with a back.
	_steps.append([45, _pre_snap.bind(true, OffensePlay.Group.GUN_SPREAD)])
	_steps.append([0, func() -> void:
		_kept["eligible"] = _pc.eligible.duplicate()
		_kept["man"] = null
		_kept["back"] = null
		for slot: int in mini(_pc.eligible.size(), HumanController.PASS_ACTIONS.size()):
			var man: Player = _pc.eligible[slot]
			if man.brain.off_assign.job == OffenseAssignment.Job.ROUTE and _kept["man"] == null and man != _pc.motion.man:
				_kept["man"] = slot
			elif man.brain.off_assign.job == OffenseAssignment.Job.RUNNER:
				_kept["back"] = slot
		_expect(_kept["man"] != null, "hot: the test play has no receiver on a button")])
	_tap(&"hot_route")
	_steps.append([0, func() -> void:
		_expect(_mode() == HOT and _pc.hot_picking, "hot: (Y) did not open it")
		_expect(_pc.motion.state != PreSnapMotion.State.MOVING, "motion: (Y) sent a man")
		_expect(_game.play_art.shown == _pc.off_play, "hot: the play is not drawn on the field")])
	_steps.append([2, func() -> void:
		if _kept["back"] != null:
			Input.action_press(HumanController.PASS_ACTIONS[_kept["back"]])])
	_steps.append([2, func() -> void:
		_release()
		_expect(_state.get("_hot_man") == null, "hot: the back was picked")
		Input.action_press(HumanController.PASS_ACTIONS[_kept["man"]])])
	_steps.append([2, func() -> void:
		_release()
		_expect(_in_pre_snap(), "hot: a receiver's button snapped the ball")
		_expect(_state.get("_hot_man") == _pc.eligible[_kept["man"]], "hot: the receiver was not picked")])
	_tap(&"move_up")
	_steps.append([0, func() -> void:
		var man: Player = _pc.eligible[_kept["man"]]
		_expect(_pc.hot_routes.has(man), "hot: stick up gave him no route")
		_expect(man.brain.route.size() == 1, "hot: a streak of %d legs" % man.brain.route.size())
		if man.brain.route.size() == 1:
			var to: Vector3 = man.brain.route[0] - man.brain.start_point
			_expect(absf(to.x * _pc.off_dir - 20.0) < 0.1 and absf(to.z) < 0.1, "hot: the streak goes to %s" % to)
		_expect(_pc.eligible == _kept["eligible"], "hot: who can be thrown to changed")
		_expect(_mode() == LINE and not _pc.hot_picking, "hot: still open after the route")
		_expect(_game.play_art.shown == null, "hot: the play is still drawn")
		# Not for a man who blocks.
		for player: Player in _game.offense.players:
			if player.brain.off_assign.job == OffenseAssignment.Job.BLOCK:
				_expect(not _pc.hot_route(player, OffenseAssignment.Hot.STREAK, 0.0), "hot: a blocker was given a route")
				break])
	# A slant to the right of the screen ends to the right of where it starts.
	_tap(&"hot_route")
	_steps.append([2, func() -> void: Input.action_press(HumanController.PASS_ACTIONS[_kept["man"]])])
	_steps.append([2, _release])
	_tap(&"move_right")
	_steps.append([0, func() -> void:
		var man: Player = _pc.eligible[_kept["man"]]
		var across: float = (man.brain.route[man.brain.route.size() - 1] - man.brain.start_point).dot(_game.camera_rig.basis.x)
		_expect(man.brain.route.size() == 2 and across > 1.0, "hot: a slant to the right goes %.1f yd to the right" % across)])
	# The right stick has routes of its own: up is a post, deeper than the streak.
	_tap(&"hot_route")
	_steps.append([0, func() -> void: _expect(_game.hud.get("_hot_routes") != null and (_game.hud.get("_hot_routes") as Control).visible, "hot: the panel is not up")])
	_steps.append([2, func() -> void: Input.action_press(HumanController.PASS_ACTIONS[_kept["man"]])])
	_steps.append([2, _release])
	_tap(&"quick_up")
	_steps.append([0, func() -> void:
		var man: Player = _pc.eligible[_kept["man"]]
		var deep: float = (man.brain.route[man.brain.route.size() - 1].x - man.brain.start_point.x) * _pc.off_dir
		_expect(man.brain.route.size() == 2 and deep > 20.5, "hot: right stick up gave a route %.1f yd deep, not a post" % deep)
		_expect(_mode() == LINE and not (_game.hud.get("_hot_routes") as Control).visible, "hot: the panel stays up after the route")])
	# And left with the trigger.
	_tap(&"hot_route")
	_tap(&"reveal_play")
	_steps.append([0, func() -> void: _expect(_mode() == LINE, "hot: the left trigger did not leave it")])
	# With the trigger held the stick shows a route on the field and does not
	# call it; letting go of the trigger calls the one that is shown.
	_tap(&"hot_route")
	_steps.append([2, func() -> void: Input.action_press(HumanController.PASS_ACTIONS[_kept["man"]])])
	_steps.append([2, func() -> void:
		_release()
		_kept["hots"] = _game.stats.get(&"hot_routes", 0)
		_kept["route"] = _pc.eligible[_kept["man"]].brain.route.duplicate()
		_kept["triangles"] = _game.play_art.triangles
		Input.action_press(&"reveal_play")])
	_steps.append([2, func() -> void: Input.action_press(&"move_right")])
	_steps.append([2, func() -> void:
		var man: Player = _pc.eligible[_kept["man"]]
		var art: PlayArt = _game.play_art
		_expect(_mode() == HOT, "show: the stick left the hot routes with the trigger held")
		_expect(_game.stats.get(&"hot_routes", 0) == _kept["hots"] and man.brain.route == _kept["route"], "show: the route was called with the trigger held")
		_expect(art.hot_preview_man == man and art.hot_preview != null, "show: no route is shown for him")
		if art.hot_preview != null:
			var legs: PackedVector2Array = art.hot_preview.route
			_expect(legs.size() == 2 and absf(absf(legs[1].y) - 7.0) < 0.1 and not art.hot_preview.settle, "show: stick right shows %s, not a slant" % legs)
		_expect(art.triangles > _kept["triangles"], "show: the route is not drawn (%d triangles, %d before)" % [art.triangles, _kept["triangles"]])
		Input.action_release(&"move_right")
		Input.action_press(&"move_down")])
	_steps.append([2, func() -> void:
		var art: PlayArt = _game.play_art
		_expect(_mode() == HOT and art.hot_preview != null and art.hot_preview.settle, "show: stick down does not show the curl")
		Input.action_release(&"reveal_play")])
	_steps.append([2, func() -> void:
		_release()
		var man: Player = _pc.eligible[_kept["man"]]
		var deep: float = (man.brain.route[man.brain.route.size() - 1].x - man.brain.start_point.x) * _pc.off_dir
		_expect(_mode() == LINE, "show: still open after the trigger was let go")
		_expect(_game.stats.get(&"hot_routes", 0) == _kept["hots"] + 1, "show: letting go of the trigger did not call the route")
		_expect(absf(deep - 6.5) < 0.1, "show: the route called ends %.1f yd deep, not the curl that was shown" % deep)
		_expect(_game.play_art.hot_preview == null, "show: the route is still shown after it was called")])
	# The stick let go first: nothing is called.
	_tap(&"hot_route")
	_steps.append([2, func() -> void: Input.action_press(HumanController.PASS_ACTIONS[_kept["man"]])])
	_steps.append([2, func() -> void:
		_release()
		_kept["hots"] = _game.stats.get(&"hot_routes", 0)
		Input.action_press(&"reveal_play")
		Input.action_press(&"move_up")])
	_steps.append([2, func() -> void:
		_expect(_game.play_art.hot_preview != null, "show: the streak is not shown")
		Input.action_release(&"move_up")])
	_steps.append([2, func() -> void:
		_expect(_mode() == HOT and _game.play_art.hot_preview == null, "show: the route stays on the field with the stick at rest")
		Input.action_release(&"reveal_play")])
	_steps.append([2, func() -> void:
		_expect(_mode() == LINE, "show: the trigger let go with the stick at rest did not leave")
		_expect(_game.stats.get(&"hot_routes", 0) == _kept["hots"], "show: a route was called with the stick at rest")])
	# A trigger held since before (Y) is not the one that leaves.
	_steps.append([2, func() -> void: Input.action_press(&"reveal_play")])
	_tap(&"hot_route")
	_steps.append([2, func() -> void: Input.action_release(&"reveal_play")])
	_steps.append([0, func() -> void: _expect(_mode() == HOT, "show: a trigger held from before left the hot routes")])
	_tap(&"reveal_play")
	_steps.append([0, func() -> void: _expect(_mode() == LINE, "show: the left trigger did not leave it afterwards")])

	# Motion on the bumper, and no audible after it.
	_steps.append([45, func() -> void:
		for play: OffensePlay in _game.offense_playbook.plays:
			if MotionRules.has_motion(play) and play.motion != OffensePlay.Motion.JET:
				_pre_snap(true, play.group, play)
				return
		_failures.append("motion: no play with a motion to test with")])
	_tap(&"motion")
	_steps.append([0, func() -> void:
		_expect(_pc.motion.called(), "motion: the bumper did not send him")
		_kept["play"] = _pc.off_play])
	_tap(&"audible")
	_steps.append([0, func() -> void: _expect(_mode() == LINE, "motion: the menu opened with a man in motion")])
	_tap(&"quick_down")
	_tap(&"hot_route")
	_steps.append([0, func() -> void:
		_expect(_pc.off_play == _kept["play"], "motion: a quick audible with a man in motion")
		_expect(_mode() == LINE, "motion: a hot route with a man in motion")
		_pc.snap()
		_pc.state_machine.transition(&"Live")])
	_steps.append([3, func() -> void:
		_expect(not _pc.audible(_pc.off_play, _pc.def_play, not _pc.off_flipped, _pc.def_flipped), "snap: an audible after the snap")
		print("offense: checked")])


# --- Defense ---------------------------------------------------------------------

func _plan_defense() -> void:
	_steps.append([45, _pre_snap.bind(false, OffensePlay.Group.I_FORM)])
	_steps.append([0, func() -> void:
		# A defender the person picked themselves.
		var mine: Player = _team.players[_team.players.size() - 1]
		if mine == _game.human.controlled:
			mine = _team.players[0]
		_game.human.set_controlled(mine)
		_kept["mine"] = mine
		_kept["play"] = _pc.def_play
		_kept["audibles"] = _game.stats.get(&"audibles", 0)])
	_tap(&"hot_route")
	_steps.append([0, func() -> void: _expect(_mode() == LINE, "defense: (Y) opened the hot routes")])
	_tap(&"audible")
	_steps.append([0, func() -> void:
		var groups: Array = _state.get("_menu_groups")
		_expect(_mode() == MENU, "defense: (X) did not open the menu")
		_expect(not groups.is_empty() and groups[0] == _pc.def_play.group, "defense: the menu does not open on the called tab")])
	_tap(&"move_down")
	_tap(&"confirm")
	_steps.append([WALK, func() -> void:
		var was: DefensePlay = _kept["play"]
		_expect(_in_pre_snap(), "defense: calling a play snapped the ball")
		_expect(_pc.def_play != was and _pc.def_play.group == was.group, "defense: the menu did not call another play of the tab")
		_expect(_game.human.controlled == _kept["mine"], "defense: the person's defender was taken away")
		_expect(_game.stats.get(&"audibles", 0) == _kept["audibles"] + 1, "defense: the audible was not counted once")])
	_steps.append([0, func() -> void:
		_expect(not _pc.shift.active() and _on_spots(), "defense: not set after the audible")
		_kept["play"] = _pc.def_play])
	_tap(&"quick_down")
	_steps.append([WALK, func() -> void:
		var was: DefensePlay = _kept["play"]
		var want: DefensePlay = DefensePlay.quick_pick(_game.defense_playbook.plays, was, OffensePlay.Category.RUN)
		_expect(want != null and _pc.def_play == want, "defense: stick down did not call the tab's best play against the run")])
	# Another tab.
	_tap(&"audible")
	_tap(&"page_next")
	_tap(&"confirm")
	_steps.append([WALK, func() -> void:
		_expect(_pc.def_play.group != (_kept["play"] as DefensePlay).group, "defense: (RB) did not go to another tab")])
	_steps.append([0, func() -> void:
		_expect(not _pc.shift.active() and _on_spots(), "defense: not set after the change of tab")
		print("defense: checked")])


# --- Helpers ---------------------------------------------------------------------

## A button pressed for two ticks and let go.
func _tap(action: StringName) -> void:
	_steps.append([2, func() -> void: Input.action_press(action)])
	_steps.append([2, func() -> void: Input.action_release(action)])


func _pre_snap(on_offense: bool, group: OffensePlay.Group, play: OffensePlay = null) -> void:
	_release()
	if not _pc.ball_dead:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
	var with_ball: Team = _team if on_offense else _team.opponent
	_game.start_drive(with_ball, _game.tuning.yard_to_x(with_ball.attack_dir, 30.0))
	if play == null:
		for candidate: OffensePlay in _game.offense_playbook.plays:
			# A pass with a back in it, where there is one: both are needed.
			if candidate.group == group and (play == null or (play.is_run and not candidate.is_run)):
				play = candidate
	_pc.line_up(play, _defense("man cover 1"))
	_pc.state_machine.transition(&"PreSnap")


func _defense(play_name: String) -> DefensePlay:
	for play: DefensePlay in _game.defense_playbook.plays:
		if play.play_name.to_lower() == play_name:
			return play
	_failures.append("no defensive play called %s" % play_name)
	return _game.defense_playbook.plays[0]


func _mode() -> int:
	return int(_state.get("_mode"))


func _in_pre_snap() -> bool:
	return _pc.state_machine.current_name() == &"PreSnap"


func _spots(team: Team) -> PackedVector3Array:
	var spots: PackedVector3Array = PackedVector3Array()
	for player: Player in team.players:
		spots.append(player.position)
	return spots


## Everybody stands where his play puts him.
func _on_spots() -> bool:
	for team: Team in [_game.offense, _game.defense]:
		for player: Player in team.players:
			var off: Vector3 = player.position - player.brain.start_point
			if Vector2(off.x, off.z).length() > 0.2 or not player.frozen:
				return false
	return true


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
	print("audible_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
