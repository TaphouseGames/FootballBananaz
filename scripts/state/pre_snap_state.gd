extends GameState
## Teams are set. The person snaps on offense, with the play clock running,
## (B) for more shouting from the quarterback and a bumper to send a receiver
## in motion when the play has one; the CPU snaps on its own timer.
##
## On either side of the ball the person can have a play drawn on the field
## (PlayArt): left trigger held and the stick pushed up shows the play that was
## called, any other way a fake from the same formation (or, on defense, the
## same tab). The trigger by itself shows nothing, so whoever is watching the
## screen cannot tell the real one from a fake.
##
## And the play can be changed at the line, for as long as nobody is in motion:
##  - (X) opens the audible menu: the plays of the called formation, and with
##    (LB) and (RB) the formations of its family (OffensePlay.audible_groups;
##    on defense, the other tabs). (A) calls one, (X) mirrors it, (B) closes.
##  - the right stick is a quick audible to another play of the same formation:
##    down a run, left a short pass, up a deep one (on defense: the play that
##    fits that best), right the called play mirrored.
##  - (Y), on offense: a hot route. A pass button picks the receiver, the stick
##    his route: on the left stick up a streak, down a curl, left or right a
##    slant that way; on the right stick up a post, down a drag, left or right
##    an out. With the left trigger held the stick only draws that route on the
##    field, and letting go of the trigger calls it; let go with the sticks at
##    rest, the trigger leaves (HotRouteMenu shows all of it).
## A new formation is walked to (PreSnapShift), and the offense cannot snap or
## send a man in motion until it is set again. The play clock runs all the while.

## LINE: at the line. MENU: the audible menu is open. HOT: a hot route is
## being given.
enum Mode { LINE, MENU, HOT }

## The stick is pushed a way from this far out.
const REVEAL_STICK: float = 0.5

## Other plays of the called play's formation, in the order left, right, down.
var _fakes: Array[Resource] = []
var _human_snaps: bool = false
var _cpu_delay: float = 0.0
## When the person's quarterback last shouted, in time_in_state.
var _last_call: float = 0.0
## When a CPU offense sends its man in motion, in time_in_state (negative = it
## does not, or it has).
var _cpu_motion_at: float = -1.0
## The hint under the banner right now (the jet motion's snap cue, the shift,
## the hot route's buttons), or nothing.
var _hint: String = ""
## The state of the motion the banner was last written for.
var _banner_motion: PreSnapMotion.State = PreSnapMotion.State.NONE
var _mode: Mode = Mode.LINE
## The audible menu: the formations (or tabs) it can go to with the called one
## first, the open one, its plays, the cursor and whether the play is mirrored.
var _menu_groups: Array[int] = []
var _menu_group: int = 0
var _menu_plays: Array[Resource] = []
var _menu_cursor: int = 0
var _menu_flipped: bool = false
## The receiver a hot route is being given to, once he is picked.
var _hot_man: Player
## The left trigger was pressed while a hot route is being given: until it is
## let go the sticks show a route and do not call it.
var _hot_lt: bool = false
## The route drawn on the field for him right now (see _hot_held), or -1.
var _hot_shown: int = -1


func enter() -> void:
	_human_snaps = game.human.is_active() and game.human.team == game.offense
	_cpu_delay = randf_range(game.tuning.cpu_snap_delay_min, game.tuning.cpu_snap_delay_max)
	_last_call = 0.0
	_cpu_motion_at = -1.0
	_hint = ""
	_mode = Mode.LINE
	_hot_man = null
	_pick_fakes()
	# A CPU quarterback gets a silly line out before he snaps.
	var silly: float = game.audio.qb_open()
	_cpu_delay = maxf(_cpu_delay, minf(silly, game.tuning.cpu_silly_hold_max))
	if not _human_snaps and pc.motion.available() and randf() < game.tuning.ai_motion_chance:
		_cpu_motion_at = game.tuning.ai_motion_time
		if pc.motion.is_jet():
			# A jet is snapped while he runs: he is sent late enough for that.
			_cpu_motion_at = maxf(_cpu_motion_at, _cpu_delay - 0.6)
	if game.human.is_active():
		_show_banner()
		game.hud.set_hint("")
	else:
		game.hud.set_hint("AUTOPLAY")


func exit() -> void:
	_close()
	game.hud.hide_banner()
	game.hud.hide_countdown()
	game.play_art.clear()
	if _hint != "":
		game.hud.set_hint("")


## The person's play and buttons. The motion is offered for as long as there is
## one to call.
func _show_banner() -> void:
	if _human_snaps:
		var flipped: String = " (flipped)" if pc.off_flipped else ""
		var motion: String = ""
		if pc.motion.available():
			motion = "  (LB) motion"
		elif pc.motion.can_send_back():
			motion = "  (LB) call back"
		_banner_motion = pc.motion.state
		game.hud.show_banner("", "%s%s  -  (A) snap  (B) shout  (X) audible  (Y) hot route%s  (LT) show" % [pc.off_play.play_name, flipped, motion])
	else:
		var flipped: String = " (flipped)" if pc.def_flipped else ""
		game.hud.show_banner("", "%s%s  -  get ready   (X) audible   (LT) show play" % [pc.def_play.play_name, flipped])


## The plays a fake can be: the others of the formation the person's play is in.
func _pick_fakes() -> void:
	_fakes.clear()
	if not game.human.is_active():
		return
	if _human_snaps:
		for play: OffensePlay in game.offense_playbook.plays:
			if play != pc.off_play and play.group == pc.off_play.group:
				_fakes.append(play)
	else:
		for play: DefensePlay in game.defense_playbook.plays:
			if play != pc.def_play and play.group == pc.def_play.group:
				_fakes.append(play)
	_fakes.shuffle()


## Left trigger and the stick: the play on the field, or a fake.
func _update_reveal() -> void:
	if not game.human.is_active():
		return
	var stick: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if not Input.is_action_pressed(&"reveal_play") or stick.length() < REVEAL_STICK:
		game.play_art.clear()
		return
	# Up is the real one. With no other play in the formation every way is.
	var slot: int = -1
	if absf(stick.x) > absf(stick.y):
		slot = 0 if stick.x < 0.0 else 1
	elif stick.y > 0.0:
		slot = 2
	var fake: Resource = _fakes[slot % _fakes.size()] if slot >= 0 and not _fakes.is_empty() else null
	if _human_snaps:
		game.play_art.show_offense(fake as OffensePlay if fake != null else pc.off_play, pc.off_flipped)
	else:
		game.play_art.show_defense(fake as DefensePlay if fake != null else pc.def_play, pc.def_flipped)


func physics_update(delta: float) -> void:
	var person: bool = game.human.is_active()
	# What a button does goes by the mode this tick began in: the (B) that
	# closes the menu is not a shout as well.
	var at_line: bool = _mode == Mode.LINE
	if at_line:
		game.human.update_pre_snap()
		_update_reveal()
	pc.motion.tick(delta)
	pc.shift.tick(delta)
	if person:
		match _mode:
			Mode.LINE:
				_update_line()
			Mode.MENU:
				_update_menu()
			Mode.HOT:
				_update_hot()
	at_line = at_line and _mode == Mode.LINE
	var snap_now: bool = false
	var hint: String = ""
	if _human_snaps:
		var tuning: Tuning = game.tuning
		# An offense on its way to a new formation is not set: no snap, no motion.
		var shifting: bool = pc.shift.active(game.offense)
		if at_line and not shifting:
			if Input.is_action_just_pressed(&"qb_call") and time_in_state - _last_call >= tuning.qb_call_gap:
				_last_call = time_in_state
				game.audio.qb_call()
			# (LB) sends him, and (LB) again calls him back to where he stood.
			if Input.is_action_just_pressed(&"motion") and not pc.motion.call_motion():
				pc.motion.send_back()
			if pc.motion.state != _banner_motion:
				_show_banner()
			snap_now = time_in_state >= tuning.pre_snap_delay and Input.is_action_just_pressed(&"confirm")
		if shifting:
			hint = "SHIFTING..."
		elif pc.motion.jet_in_window():
			# A jet man close to the quarterback: now is the time.
			hint = "(A) SNAP IT!"
		# Out of time: the ball is snapped for them, as soon as they are set.
		if count_down(tuning.play_clock, delta):
			_close()
			snap_now = not shifting
	else:
		if person and pc.shift.active(game.defense):
			hint = "SHIFTING..."
		if _cpu_motion_at >= 0.0 and time_in_state >= _cpu_motion_at and not pc.shift.active(game.offense):
			_cpu_motion_at = -1.0
			pc.motion.call_motion()
		snap_now = _cpu_snaps()
	if person:
		if hint != _hint:
			_hint = hint
			game.hud.set_hint(hint)
	if snap_now:
		pc.snap()
		machine.transition(&"Live")


## A CPU offense snaps on its timer. With a man in motion it waits until he is
## set, and a jet man it snaps to as he gets to the quarterback.
func _cpu_snaps() -> bool:
	if _cpu_motion_at >= 0.0:
		return false
	var motion: PreSnapMotion = pc.motion
	match motion.state:
		PreSnapMotion.State.MOVING:
			return motion.is_jet() and motion.jet_in_window()
		PreSnapMotion.State.SET:
			return time_in_state >= _cpu_delay and motion.time - motion.set_time >= game.tuning.ai_motion_set_time
	return time_in_state >= _cpu_delay


# --- Audibles ------------------------------------------------------------------

## The play can be changed right now: the teams have been set for a moment,
## nobody is walking to a new formation and nobody has been sent in motion.
func _can_change() -> bool:
	return time_in_state >= game.tuning.pre_snap_delay and not pc.shift.active() and not pc.motion.called()


## At the line: (X) opens the menu, (Y) the hot routes, and the right stick
## calls a quick audible.
func _update_line() -> void:
	if not _can_change():
		return
	if Input.is_action_just_pressed(&"audible"):
		_open_menu()
	elif _human_snaps and Input.is_action_just_pressed(&"hot_route"):
		_open_hot()
	elif Input.is_action_just_pressed(&"quick_right"):
		_call(_called(), not _called_flipped())
	elif Input.is_action_just_pressed(&"quick_down"):
		_call_quick(OffensePlay.Category.RUN)
	elif Input.is_action_just_pressed(&"quick_left"):
		_call_quick(OffensePlay.Category.SHORT)
	elif Input.is_action_just_pressed(&"quick_up"):
		_call_quick(OffensePlay.Category.DEEP)


## The play of the person's side as it is called now, and whether it is mirrored.
func _called() -> Resource:
	return pc.off_play if _human_snaps else pc.def_play


func _called_flipped() -> bool:
	return pc.off_flipped if _human_snaps else pc.def_flipped


func _call_quick(kind: OffensePlay.Category) -> void:
	var pick: Resource = null
	if _human_snaps:
		pick = OffensePlay.quick_pick(game.offense_playbook.plays, pc.off_play, kind)
	else:
		pick = DefensePlay.quick_pick(game.defense_playbook.plays, pc.def_play, kind)
	if pick != null:
		_call(pick, _called_flipped())


## The audible itself: `play` of the person's side, mirrored or not.
func _call(play: Resource, flipped: bool) -> void:
	var done: bool = false
	if _human_snaps:
		var off_play: OffensePlay = play as OffensePlay
		# A CPU defense drawn for one side of the formation goes to that side of
		# the new one.
		var def_flipped: bool = pc.def_flipped
		if pc.def_play.strength_side != 0:
			def_flipped = DefenseAligner.cpu_flip(pc.def_play, off_play, flipped)
		done = pc.audible(off_play, pc.def_play, flipped, def_flipped)
	else:
		done = pc.audible(pc.off_play, play as DefensePlay, pc.off_flipped, flipped)
	if not done:
		return
	_close()
	_pick_fakes()
	_show_banner()
	game.audio.play(&"ui_confirm")
	if _human_snaps:
		# The quarterback shouts it down the line.
		_last_call = time_in_state
		game.audio.qb_call()


## Back to the line: the menu shut, no receiver being picked.
func _close() -> void:
	if _mode == Mode.MENU:
		game.hud.hide_audible()
		_show_banner()
	elif _mode == Mode.HOT:
		pc.set_hot_picking(false)
		game.play_art.clear()
		game.hud.hide_hot_routes()
		_show_banner()
	_mode = Mode.LINE
	_hot_man = null
	_hot_lt = false
	_hot_shown = -1


# --- The audible menu ------------------------------------------------------------

func _open_menu() -> void:
	_menu_groups.clear()
	if _human_snaps:
		for group: int in OffensePlay.audible_groups(pc.off_play.group):
			if not _plays_of(group).is_empty():
				_menu_groups.append(group)
	else:
		# The called tab first, then the others in their order.
		_menu_groups.append(pc.def_play.group)
		for group: int in DefensePlay.GROUP_NAMES.size():
			if group != pc.def_play.group and not _plays_of(group).is_empty():
				_menu_groups.append(group)
	if _menu_groups.is_empty():
		return
	_mode = Mode.MENU
	_menu_group = 0
	_menu_flipped = _called_flipped()
	game.play_art.clear()
	# The banner's line of buttons would run under the menu.
	game.hud.hide_banner()
	_show_menu()
	game.audio.play(&"ui_page")


## The plays of formation (or tab) `group`, in playbook order.
func _plays_of(group: int) -> Array[Resource]:
	var plays: Array[Resource] = []
	if _human_snaps:
		for play: OffensePlay in game.offense_playbook.plays:
			if play.group == group:
				plays.append(play)
	else:
		for play: DefensePlay in game.defense_playbook.plays:
			if play.group == group:
				plays.append(play)
	return plays


## Puts the open formation's plays on screen, the cursor on the called play
## when it is one of them.
func _show_menu() -> void:
	var group: int = _menu_groups[_menu_group]
	_menu_plays = _plays_of(group)
	_menu_cursor = maxi(_menu_plays.find(_called()), 0)
	var names: PackedStringArray = OffensePlay.GROUP_NAMES if _human_snaps else DefensePlay.GROUP_NAMES
	game.hud.show_audible(names[group], _menu_groups.size() > 1, _menu_plays, _menu_cursor, _menu_flipped)


func _update_menu() -> void:
	# A CPU offense has sent its man in motion: too late.
	if not _can_change():
		_close()
		return
	if Input.is_action_just_pressed(&"back"):
		_close()
		game.audio.play(&"ui_move")
		return
	# The bumpers go to the next formation (or tab).
	var turn: int = int(Input.is_action_just_pressed(&"page_next")) - int(Input.is_action_just_pressed(&"page_prev"))
	if turn != 0 and _menu_groups.size() > 1:
		_menu_group = posmod(_menu_group + turn, _menu_groups.size())
		_show_menu()
		game.audio.play(&"ui_page")
	# The stick moves through the plays: up and down the list, left and right
	# to the same row of the column beside it (or that column's last play).
	var moved: int = _menu_cursor
	var step: int = int(Input.is_action_just_pressed(&"move_down")) - int(Input.is_action_just_pressed(&"move_up"))
	var across: int = int(Input.is_action_just_pressed(&"move_right")) - int(Input.is_action_just_pressed(&"move_left"))
	if step != 0:
		moved = posmod(_menu_cursor + step, _menu_plays.size())
	elif across != 0:
		var rows: int = AudibleMenu.COLUMN_ROWS
		@warning_ignore("integer_division")
		var column: int = _menu_cursor / rows + across
		@warning_ignore("integer_division")
		if column >= 0 and column <= (_menu_plays.size() - 1) / rows:
			moved = mini(column * rows + _menu_cursor % rows, _menu_plays.size() - 1)
	if moved != _menu_cursor:
		_menu_cursor = moved
		game.hud.set_audible_cursor(_menu_cursor)
		game.audio.play(&"ui_move")
	if Input.is_action_just_pressed(&"flip_play"):
		_menu_flipped = not _menu_flipped
		game.hud.set_audible_flipped(_menu_flipped)
		game.audio.play(&"ui_flip")
	if Input.is_action_just_pressed(&"confirm"):
		var pick: Resource = _menu_plays[_menu_cursor]
		if pick == _called() and _menu_flipped == _called_flipped():
			# The play that is on already: nothing to change.
			_close()
			game.audio.play(&"ui_move")
		else:
			_call(pick, _menu_flipped)


# --- Hot routes ------------------------------------------------------------------

func _open_hot() -> void:
	_mode = Mode.HOT
	_hot_man = null
	_hot_lt = false
	_hot_shown = -1
	pc.set_hot_picking(true)
	# The play on the field, so the new route is seen next to the others.
	game.play_art.show_offense(pc.off_play, pc.off_flipped)
	# The banner's line of buttons would run into the panel.
	game.hud.hide_banner()
	game.hud.show_hot_routes("")
	game.audio.play(&"ui_page")


## The four face buttons are the receivers' own here, so it is the left trigger
## that leaves: let go with no route on the field. Held, it turns the sticks
## from calling a route to showing it, and letting go calls the one shown.
func _update_hot() -> void:
	if not _can_change():
		_close()
		return
	# Only a trigger pulled in here: one still held from showing the play is not it.
	if Input.is_action_just_pressed(&"reveal_play"):
		_hot_lt = true
	for slot: int in mini(HumanController.PASS_ACTIONS.size(), pc.eligible.size()):
		if Input.is_action_just_pressed(HumanController.PASS_ACTIONS[slot]):
			var man: Player = pc.eligible[slot]
			# Only a man who was going out on a route: not the back the ball is
			# handed to.
			if man.brain.off_assign.job == OffenseAssignment.Job.ROUTE:
				_show_hot(-1)
				_hot_man = man
				game.hud.show_hot_routes("(%s) %s" % [game.human.pass_label(slot), man.brain.off_assign.label])
				game.audio.play(&"ui_move")
			else:
				game.audio.play(&"ui_tick")
			return
	if _hot_lt:
		var held: int = _hot_held() if _hot_man != null else -1
		if Input.is_action_pressed(&"reveal_play"):
			_show_hot(held)
		elif held < 0 or not _give_hot(held):
			_close()
		return
	if _hot_man != null:
		var pressed: int = _hot_pressed()
		if pressed >= 0:
			_give_hot(pressed)


## A route and the way it breaks on screen (-1 left, 0 neither, 1 right) as one
## number.
func _hot_key(kind: OffenseAssignment.Hot, way: int) -> int:
	return int(kind) * 3 + way + 1


## The route a stick pushed just now asks for (see _hot_key), or -1.
func _hot_pressed() -> int:
	if Input.is_action_just_pressed(&"move_up"):
		return _hot_key(OffenseAssignment.Hot.STREAK, 0)
	if Input.is_action_just_pressed(&"move_down"):
		return _hot_key(OffenseAssignment.Hot.CURL, 0)
	if Input.is_action_just_pressed(&"move_left"):
		return _hot_key(OffenseAssignment.Hot.SLANT, -1)
	if Input.is_action_just_pressed(&"move_right"):
		return _hot_key(OffenseAssignment.Hot.SLANT, 1)
	if Input.is_action_just_pressed(&"quick_up"):
		return _hot_key(OffenseAssignment.Hot.POST, 0)
	if Input.is_action_just_pressed(&"quick_down"):
		return _hot_key(OffenseAssignment.Hot.DRAG, 0)
	if Input.is_action_just_pressed(&"quick_left"):
		return _hot_key(OffenseAssignment.Hot.OUT, -1)
	if Input.is_action_just_pressed(&"quick_right"):
		return _hot_key(OffenseAssignment.Hot.OUT, 1)
	return -1


## The route the sticks are held on right now (see _hot_key): that of the one
## pushed further, or -1 with both at rest.
func _hot_held() -> int:
	var left: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var right: Vector2 = Input.get_vector(&"quick_left", &"quick_right", &"quick_up", &"quick_down")
	var on_right: bool = right.length() > left.length()
	var stick: Vector2 = right if on_right else left
	if stick.length() < REVEAL_STICK:
		return -1
	if absf(stick.x) > absf(stick.y):
		return _hot_key(OffenseAssignment.Hot.OUT if on_right else OffenseAssignment.Hot.SLANT, -1 if stick.x < 0.0 else 1)
	if stick.y < 0.0:
		return _hot_key(OffenseAssignment.Hot.POST if on_right else OffenseAssignment.Hot.STREAK, 0)
	return _hot_key(OffenseAssignment.Hot.DRAG if on_right else OffenseAssignment.Hot.CURL, 0)


@warning_ignore("integer_division")
func _hot_kind(key: int) -> OffenseAssignment.Hot:
	return (key / 3) as OffenseAssignment.Hot


## The way route `key` breaks, in the play's own frame. Left and right are as
## the person sees them: the camera's right, in the frame the play is drawn in
## (PlayController.to_world).
func _hot_side(key: int) -> float:
	var right: float = signf(game.camera_rig.basis.x.z)
	if right == 0.0:
		right = pc.off_dir
	var flip: float = -1.0 if pc.off_flipped else 1.0
	return float(key % 3 - 1) * right * pc.off_dir * flip


## Draws route `key` on the field for the picked man, in place of the one he
## has (-1: no route, his own again).
func _show_hot(key: int) -> void:
	if key == _hot_shown:
		return
	_hot_shown = key
	if key < 0:
		game.play_art.clear_hot_preview()
		return
	game.play_art.set_hot_preview(_hot_man, OffenseAssignment.hot_route(_hot_man.brain.off_assign, _hot_kind(key), _hot_side(key)))
	game.audio.play(&"ui_tick")


## The hot route itself: the picked man runs route `key`, and it is back to the line.
func _give_hot(key: int) -> bool:
	if not pc.hot_route(_hot_man, _hot_kind(key), _hot_side(key)):
		return false
	game.audio.play(&"ui_confirm")
	_close()
	return true
