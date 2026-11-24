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
##  - (X) opens the audible menu (AudibleMenu): four plays, one on each way of
##    the left stick, and pushing it that way calls the play. They are picked at
##    random from the plays the coach advised for the down (Game.coach_plays),
##    once for the line-up, and one or two of an offense's are runs
##    (PlayCaller.audible_offense). (B) or (X) again closes.
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
##
## A CPU side changes its play too, now and then, when what it sees across the
## ball asks for it (_cpu_offense_read, _cpu_defense_read). It sees what the
## person sees: the kind of defense, the offense's formation, not the play.

##
## With two people playing each has a line of their own (Line): their own
## gamepad, their own menu in their own corner, their own fakes. Both look at
## one screen, so nothing on it names the play either of them called: the
## banner is only their buttons, the audible menu does not mark the play that
## is on, and a hot route shows the one man's route, not the rest of the play.

## LINE: at the line. MENU: the audible menu is open. HOT: a hot route is
## being given.
enum Mode { LINE, MENU, HOT }

## The stick is pushed a way from this far out.
const REVEAL_STICK: float = 0.5
## The longest a CPU offense that is set waits past its snap time for the
## defense to get to its spots, in seconds.
const CPU_SET_WAIT: float = 2.5
## The ways of the left stick that call the plays of the audible menu, in the
## order of AudibleMenu.WAYS.
const MENU_ACTIONS: Array[StringName] = [&"move_up", &"move_left", &"move_right", &"move_down"]

## One person at the line: which side of the ball they are on, and what they
## have open.
class Line:
	var human: HumanController
	var pad: PadInput
	## Their half of the screen for the menus: 0, or with two playing 0 left
	## and 1 right.
	var slot: int = 0
	var on_offense: bool = false
	## Other plays of the called play's formation, in the order left, right, down.
	var fakes: Array[Resource] = []
	var mode: Mode = Mode.LINE
	## The mode this tick began in: what a button does goes by it, so the (B)
	## that closes the menu is not a shout as well.
	var was_at_line: bool = true
	## The plays of the audible menu, in the order of MENU_ACTIONS. Picked the
	## first time it is opened and kept for the line-up, so opening it again is
	## no way to be dealt other plays.
	var menu_plays: Array[Resource] = []
	## The receiver a hot route is being given to, once he is picked.
	var hot_man: Player
	## The left trigger was pressed while a hot route is being given: until it
	## is let go the sticks show a route and do not call it.
	var hot_lt: bool = false
	## The route drawn on the field for him right now (see _hot_held), or -1.
	var hot_shown: int = -1


## The people at the line, in the order of Game.humans, and the one whose team
## has the ball (null: the CPU snaps).
var _lines: Array[Line] = []
var _snapper: Line
var _human_snaps: bool = false
var _cpu_delay: float = 0.0
## When the person's quarterback last shouted, in time_in_state.
var _last_call: float = 0.0
## When a CPU offense sends its man in motion, in time_in_state (negative = it
## does not, or it has).
var _cpu_motion_at: float = -1.0
## When a CPU offense and a CPU defense look across the ball for a reason to
## change the play, in time_in_state (negative: they have, or a person runs
## that side).
var _cpu_offense_read_at: float = -1.0
var _cpu_defense_read_at: float = -1.0
## The hint under the banner right now (the jet motion's snap cue, the shift,
## the hot route's buttons), or nothing.
var _hint: String = ""
## The state of the motion the banner was last written for.
var _banner_motion: PreSnapMotion.State = PreSnapMotion.State.NONE

## The first person's mode, menu and picked receiver (the tests look at them).
var _mode: Mode:
	get:
		return _lines[0].mode if not _lines.is_empty() else Mode.LINE
var _menu_plays: Array[Resource]:
	get:
		return _lines[0].menu_plays if not _lines.is_empty() else ([] as Array[Resource])
var _hot_man: Player:
	get:
		return _lines[0].hot_man if not _lines.is_empty() else null


func enter() -> void:
	_lines.clear()
	_snapper = null
	var defender: Line = null
	for person: HumanController in game.humans:
		if not person.is_active():
			continue
		var line: Line = Line.new()
		line.human = person
		line.pad = person.pad
		line.slot = game.screen_slot(person)
		line.on_offense = person.team == game.offense
		_lines.append(line)
		if line.on_offense:
			_snapper = line
		else:
			defender = line
	_human_snaps = _snapper != null
	_cpu_delay = randf_range(game.tuning.cpu_snap_delay_min, game.tuning.cpu_snap_delay_max)
	_last_call = 0.0
	_cpu_motion_at = -1.0
	_hint = ""
	for line: Line in _lines:
		_pick_fakes(line)
	# A CPU quarterback gets a silly line out before he snaps.
	var silly: float = game.audio.qb_open()
	_cpu_delay = maxf(_cpu_delay, minf(silly, game.tuning.cpu_silly_hold_max))
	var read_at: float = game.tuning.pre_snap_delay + game.tuning.ai_audible_time
	_cpu_offense_read_at = -1.0 if _human_snaps else read_at
	_cpu_defense_read_at = -1.0 if defender != null else read_at
	if not _human_snaps and pc.motion.available() and randf() < game.tuning.ai_motion_chance:
		# After the look across the ball: a man in motion rules out an audible.
		_cpu_motion_at = maxf(game.tuning.ai_motion_time, read_at + 0.1)
		if pc.motion.is_jet():
			# A jet is snapped while he runs: he is sent late enough for that.
			_cpu_motion_at = maxf(_cpu_motion_at, _cpu_delay - 0.6)
	if not _lines.is_empty():
		for line: Line in _lines:
			_show_banner(line)
		game.hud.set_hint("")
	else:
		game.hud.set_hint("AUTOPLAY")


func exit() -> void:
	for line: Line in _lines:
		_close(line)
	game.hud.hide_banner()
	game.hud.hide_countdown()
	game.play_art.clear()
	if _hint != "":
		game.hud.set_hint("")


## Two people are at the line, looking at one screen.
## Not online: there each has a screen of their own, and is shown what one
## person alone is (and nothing of it goes to the other, see _only).
func _shared() -> bool:
	return _lines.size() > 1 and Game.net_mode != Game.NetMode.SERVER


## Online, what is shown and heard from here on is this person's alone, until
## _everyone().
func _only(line: Line) -> void:
	NetEvents.audience = line.human.seat


func _everyone() -> void:
	NetEvents.audience = NetEvents.EVERYONE


## A person's play and buttons. The motion is offered for as long as there is
## one to call. With two at the line only the buttons, each on their own half:
## the play's name would tell the other one.
func _show_banner(line: Line) -> void:
	var before: int = NetEvents.audience
	_only(line)
	var play: String = ""
	var buttons: String = ""
	if line.on_offense:
		var flipped: String = " (flipped)" if pc.off_flipped else ""
		var motion: String = ""
		if pc.motion.available():
			motion = "  (LB) motion"
		elif pc.motion.can_send_back():
			motion = "  (LB) call back"
		_banner_motion = pc.motion.state
		play = pc.off_play.play_name + flipped
		buttons = "(A) snap  (B) shout  (X) audible  (Y) hot route%s  (LT) show" % motion
	else:
		var flipped: String = " (flipped)" if pc.def_flipped else ""
		play = pc.def_play.play_name + flipped
		buttons = "get ready   (X) audible   (LT) show play"
	if _shared():
		game.hud.show_line_hint(line.slot, buttons)
	else:
		game.hud.show_banner("", "%s  -  %s" % [play, buttons])
	NetEvents.audience = before


## Takes a person's line of buttons away: a menu of theirs is going up there.
func _hide_banner(line: Line) -> void:
	if _shared():
		game.hud.show_line_hint(line.slot, "")
	else:
		game.hud.hide_banner()


## The plays a fake can be: the others of the formation the person's play is in.
func _pick_fakes(line: Line) -> void:
	line.fakes.clear()
	if line.on_offense:
		for play: OffensePlay in game.offense_playbook.plays:
			if play != pc.off_play and play.group == pc.off_play.group:
				line.fakes.append(play)
	else:
		for play: DefensePlay in game.defense_playbook.plays:
			if play != pc.def_play and play.group == pc.def_play.group:
				line.fakes.append(play)
	line.fakes.shuffle()


## Takes the drawing of a person's side of the ball off the field.
func _clear_art(line: Line) -> void:
	if line.on_offense:
		game.play_art.clear_offense()
	else:
		game.play_art.clear_defense()


## Left trigger and the stick: the play on the field, or a fake.
func _update_reveal(line: Line) -> void:
	var stick: Vector2 = line.pad.vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if not line.pad.pressed(&"reveal_play") or stick.length() < REVEAL_STICK:
		_clear_art(line)
		return
	# Up is the real one. With no other play in the formation every way is.
	var slot: int = -1
	if absf(stick.x) > absf(stick.y):
		slot = 0 if stick.x < 0.0 else 1
	elif stick.y > 0.0:
		slot = 2
	var fake: Resource = line.fakes[slot % line.fakes.size()] if slot >= 0 and not line.fakes.is_empty() else null
	if line.on_offense:
		game.play_art.show_offense(fake as OffensePlay if fake != null else pc.off_play, pc.off_flipped)
	else:
		game.play_art.show_defense(fake as DefensePlay if fake != null else pc.def_play, pc.def_flipped)


func physics_update(delta: float) -> void:
	var person: bool = not _lines.is_empty()
	# What a button does goes by the mode this tick began in: the (B) that
	# closes the menu is not a shout as well.
	for line: Line in _lines:
		_only(line)
		line.was_at_line = line.mode == Mode.LINE
		if line.was_at_line:
			line.human.update_pre_snap()
			_update_reveal(line)
	_everyone()
	pc.motion.tick(delta)
	pc.shift.tick(delta)
	for line: Line in _lines:
		_only(line)
		match line.mode:
			Mode.LINE:
				_update_line(line)
			Mode.MENU:
				_update_menu(line)
			Mode.HOT:
				_update_hot(line)
	_everyone()
	var snap_now: bool = false
	var hint: String = ""
	if _human_snaps:
		var tuning: Tuning = game.tuning
		var pad: PadInput = _snapper.pad
		var at_line: bool = _snapper.was_at_line and _snapper.mode == Mode.LINE
		# An offense on its way to a new formation is not set: no snap, no motion.
		var shifting: bool = pc.shift.active(game.offense)
		if at_line and not shifting:
			if pad.just_pressed(&"qb_call") and time_in_state - _last_call >= tuning.qb_call_gap:
				_last_call = time_in_state
				game.audio.qb_call()
			# (LB) sends him, and (LB) again calls him back to where he stood.
			if pad.just_pressed(&"motion") and not pc.motion.call_motion():
				pc.motion.send_back()
			if pc.motion.state != _banner_motion:
				_show_banner(_snapper)
			snap_now = time_in_state >= tuning.pre_snap_delay and pad.just_pressed(&"confirm")
		if shifting:
			hint = "SHIFTING..."
		elif pc.motion.jet_in_window():
			# A jet man close to the quarterback: now is the time.
			hint = "(A) SNAP IT!"
		# Out of time: the ball is snapped for them, as soon as they are set.
		if count_down(tuning.play_clock, delta):
			for line: Line in _lines:
				_close(line)
			snap_now = not shifting
	else:
		# The CPU has the same play clock. It snaps on its own timer long before
		# the clock is out; if it ever is, the ball is snapped as soon as they
		# are set, as it is for the person.
		var out_of_time: bool = count_down(game.tuning.play_clock, delta)
		_cpu_offense_read()
		if person and pc.shift.active(game.defense):
			hint = "SHIFTING..."
		# Not before the look across the ball, and not while a defender walks
		# to a new spot: the motion would stop him where he is.
		if _cpu_motion_at >= 0.0 and time_in_state >= _cpu_motion_at and _cpu_offense_read_at < 0.0 and not pc.shift.active():
			_cpu_motion_at = -1.0
			pc.motion.call_motion()
		snap_now = _cpu_snaps() or (out_of_time and not pc.shift.active(game.offense))
	_cpu_defense_read()
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
	# Not before it has looked the defense over, nor on its way to new spots.
	if _cpu_motion_at >= 0.0 or _cpu_offense_read_at >= 0.0 or pc.shift.active(game.offense):
		return false
	# An audible has the defense walking too: it gets a moment to be set.
	if pc.shift.active() and time_in_state < _cpu_delay + CPU_SET_WAIT:
		return false
	var motion: PreSnapMotion = pc.motion
	match motion.state:
		PreSnapMotion.State.MOVING:
			return motion.is_jet() and motion.jet_in_window()
		PreSnapMotion.State.SET:
			return time_in_state >= _cpu_delay and motion.time - motion.set_time >= game.tuning.ai_motion_set_time
	return time_in_state >= _cpu_delay


# --- The CPU at the line -------------------------------------------------------

## A CPU offense looks the defense over, once: an audible or a hot route when
## the look asks for one, and then only now and then.
func _cpu_offense_read() -> void:
	# Whoever is still walking to a spot: the snap waits for this look, so this
	# look waits for nobody.
	if _cpu_offense_read_at < 0.0 or time_in_state < _cpu_offense_read_at:
		return
	_cpu_offense_read_at = -1.0
	if pc.motion.called() or pc.off_play.heave_only:
		return
	var tuning: Tuning = game.tuning
	var changed: bool = false
	# A blitz is answered with a quick route first; anything else with a play.
	if pc.def_play.group == DefensePlay.Group.BLITZ:
		changed = _cpu_hot_route() or _cpu_audible()
	else:
		changed = _cpu_audible() or _cpu_hot_route()
	if not changed:
		return
	game.audio.qb_call()
	# Time for the signals to be seen and the men to be set. There is no
	# motion on top of it.
	_cpu_delay = maxf(_cpu_delay, time_in_state + tuning.ai_audible_set_time)
	_cpu_motion_at = -1.0


## The CPU offense's audible: a play of another kind when the defense is in the
## kind of defense that stops the called one best.
func _cpu_audible() -> bool:
	var pick: OffensePlay = game.play_caller.cpu_audible_offense(game.offense_playbook.plays, game.defense_playbook.plays, game, pc.off_play, pc.def_play)
	if pick == null or randf() >= game.tuning.ai_audible_chance:
		return false
	if not pc.audible(pick, pc.def_play, pc.off_flipped, pc.def_flipped, game.offense):
		return false
	game.add_stat(&"cpu_audibles")
	return true


## The CPU offense's hot route, on a pass play: against a blitz the receiver
## with the deepest route runs a slant or a drag instead, to be thrown to
## before the rush is home; against a zone, with not far to go, he sits down
## in it on a curl. Not the man who may be sent in motion.
func _cpu_hot_route() -> bool:
	var tuning: Tuning = game.tuning
	var play: OffensePlay = pc.off_play
	if play.is_run or play.flea_flicker:
		return false
	var kind: OffenseAssignment.Hot = OffenseAssignment.Hot.SLANT
	match pc.def_play.group:
		DefensePlay.Group.BLITZ:
			kind = OffenseAssignment.Hot.SLANT if randf() < 0.5 else OffenseAssignment.Hot.DRAG
		DefensePlay.Group.ZONE:
			if absf(game.first_down_x - game.los_x) > tuning.ai_hot_route_curl_to_go:
				return false
			kind = OffenseAssignment.Hot.CURL
		_:
			return false
	var man: Player = null
	var deepest: float = tuning.ai_hot_route_depth
	for player: Player in pc.eligible:
		var drawn: OffenseAssignment = player.brain.off_assign
		if drawn == null or drawn.job != OffenseAssignment.Job.ROUTE or drawn.block_time > 0.0 or player == pc.motion.man:
			continue
		var depth: float = 0.0
		for waypoint: Vector2 in drawn.route:
			depth = maxf(depth, waypoint.x)
		if depth >= deepest:
			deepest = depth
			man = player
	if man == null or randf() >= tuning.ai_hot_route_chance:
		return false
	# A slant breaks toward the ball.
	var inside: float = -signf(man.brain.off_assign.start.y) if absf(man.brain.off_assign.start.y) > 0.5 else 1.0
	if not pc.hot_route(man, kind, inside):
		return false
	game.add_stat(&"cpu_hot_routes")
	return true


## A CPU defense looks the offense's formation over: at the line, and again
## when the person changes the play. An audible when one of the coach's plays
## holds up better against what comes out of that formation, and then only now
## and then.
func _cpu_defense_read() -> void:
	if _cpu_defense_read_at < 0.0 or time_in_state < _cpu_defense_read_at:
		return
	_cpu_defense_read_at = -1.0
	if pc.motion.called():
		return
	var pick: DefensePlay = game.play_caller.cpu_audible_defense(game.defense_playbook.plays, game.offense_playbook.plays, game, pc.def_play, pc.off_play.group)
	if pick == null or randf() >= game.tuning.ai_audible_chance:
		return
	var flipped: bool = DefenseAligner.cpu_flip(pick, pc.off_play, pc.off_flipped)
	# The person's menu and hot routes stay open: the offense's play, its
	# receivers and their buttons are as they were.
	if pc.audible(pc.off_play, pick, pc.off_flipped, flipped, game.defense):
		game.add_stat(&"cpu_audibles")


# --- Audibles ------------------------------------------------------------------

## A person can change the play right now: the teams have been set for a
## moment, their own team is not walking to a new formation and nobody has been
## sent in motion. The other team walking to its audible is no reason to wait:
## that is when an answer to it is wanted.
func _can_change(line: Line) -> bool:
	return time_in_state >= game.tuning.pre_snap_delay and not pc.shift.active(line.human.team) and not pc.motion.called()


## At the line: (X) opens the menu, (Y) the hot routes, and the right stick
## calls a quick audible.
func _update_line(line: Line) -> void:
	if not _can_change(line):
		return
	var pad: PadInput = line.pad
	if pad.just_pressed(&"audible"):
		_open_menu(line)
	elif line.on_offense and pad.just_pressed(&"hot_route"):
		_open_hot(line)
	elif pad.just_pressed(&"quick_right"):
		_call(line, _called(line), not _called_flipped(line))
	elif pad.just_pressed(&"quick_down"):
		_call_quick(line, OffensePlay.Category.RUN)
	elif pad.just_pressed(&"quick_left"):
		_call_quick(line, OffensePlay.Category.SHORT)
	elif pad.just_pressed(&"quick_up"):
		_call_quick(line, OffensePlay.Category.DEEP)


## The play of a person's side as it is called now, and whether it is mirrored.
func _called(line: Line) -> Resource:
	return pc.off_play if line.on_offense else pc.def_play


func _called_flipped(line: Line) -> bool:
	return pc.off_flipped if line.on_offense else pc.def_flipped


func _call_quick(line: Line, kind: OffensePlay.Category) -> void:
	var pick: Resource = null
	if line.on_offense:
		pick = OffensePlay.quick_pick(game.offense_playbook.plays, pc.off_play, kind)
	else:
		pick = DefensePlay.quick_pick(game.defense_playbook.plays, pc.def_play, kind)
	if pick != null:
		_call(line, pick, _called_flipped(line))


## The audible itself: `play` of the person's side, mirrored or not.
func _call(line: Line, play: Resource, flipped: bool) -> void:
	var done: bool = false
	# The other side is the CPU's: it may answer. A person's play stays theirs.
	var cpu_defense: bool = game.defense.human == null
	if line.on_offense:
		var off_play: OffensePlay = play as OffensePlay
		# A CPU defense drawn for one side of the formation goes to that side of
		# the new one.
		var def_flipped: bool = pc.def_flipped
		if cpu_defense and pc.def_play.strength_side != 0:
			def_flipped = DefenseAligner.cpu_flip(pc.def_play, off_play, flipped)
		done = pc.audible(off_play, pc.def_play, flipped, def_flipped, game.offense)
	else:
		done = pc.audible(pc.off_play, play as DefensePlay, pc.off_flipped, flipped, game.defense)
	if not done:
		return
	_close(line)
	_pick_fakes(line)
	_show_banner(line)
	game.audio.play(&"ui_confirm")
	if line.on_offense:
		# The quarterback shouts it down the line: everybody hears that.
		_last_call = time_in_state
		var heard: int = NetEvents.audience
		_everyone()
		game.audio.qb_call()
		NetEvents.audience = heard
		# A CPU defense has a new formation to look at.
		if cpu_defense:
			_cpu_defense_read_at = time_in_state + game.tuning.ai_audible_time


## Back to the line: the menu shut, no receiver being picked.
func _close(line: Line) -> void:
	var before: int = NetEvents.audience
	_only(line)
	if line.mode == Mode.MENU:
		game.hud.hide_audible(line.slot)
		_show_banner(line)
	elif line.mode == Mode.HOT:
		pc.set_hot_picking(false)
		_clear_art(line)
		game.hud.hide_hot_routes()
		_show_banner(line)
	line.mode = Mode.LINE
	line.hot_man = null
	line.hot_lt = false
	line.hot_shown = -1
	NetEvents.audience = before


# --- The audible menu ------------------------------------------------------------

func _open_menu(line: Line) -> void:
	if line.menu_plays.is_empty():
		_pick_menu(line)
	if line.menu_plays.is_empty():
		return
	line.mode = Mode.MENU
	_clear_art(line)
	# The banner's line of buttons would run under the menu.
	_hide_banner(line)
	# The play that is on is not marked with somebody else looking on.
	game.hud.show_audible(line.menu_plays, _called_flipped(line), null if _shared() else _called(line), line.slot)
	game.audio.play(&"ui_page")


## The menu's plays for this line-up: from the plays the coach advised on the
## play-select screen, or, with none kept for this side, from his advice now.
func _pick_menu(line: Line) -> void:
	var caller: PlayCaller = game.play_caller
	if line.on_offense:
		var book: Array[OffensePlay] = game.offense_playbook.plays
		var advised: Array[OffensePlay] = []
		for play: Resource in game.coach_plays:
			if play is OffensePlay:
				advised.append(play as OffensePlay)
		if advised.is_empty():
			advised = caller.coach_offense(book, game)
		line.menu_plays.assign(caller.audible_offense(advised, book, game, pc.off_play))
	else:
		var advised: Array[DefensePlay] = []
		for play: Resource in game.coach_plays:
			if play is DefensePlay:
				advised.append(play as DefensePlay)
		if advised.is_empty():
			advised = caller.coach_defense(game.defense_playbook.plays, game)
		line.menu_plays.assign(caller.audible_defense(advised, pc.def_play))


func _update_menu(line: Line) -> void:
	# The offense has sent its man in motion: too late.
	if not _can_change(line):
		_close(line)
		return
	var pad: PadInput = line.pad
	if pad.just_pressed(&"back") or pad.just_pressed(&"audible"):
		_close(line)
		game.audio.play(&"ui_move")
		return
	for slot: int in mini(MENU_ACTIONS.size(), line.menu_plays.size()):
		if not pad.just_pressed(MENU_ACTIONS[slot]):
			continue
		if line.menu_plays[slot] == _called(line):
			# The play that is on already: nothing to change.
			_close(line)
			game.audio.play(&"ui_move")
		else:
			_call(line, line.menu_plays[slot], _called_flipped(line))
		return


# --- Hot routes ------------------------------------------------------------------

func _open_hot(line: Line) -> void:
	line.mode = Mode.HOT
	line.hot_man = null
	line.hot_lt = false
	line.hot_shown = -1
	pc.set_hot_picking(true)
	# The play on the field, so the new route is seen next to the others. With
	# somebody else looking on, only the route being shown.
	game.play_art.hot_preview_only = _shared()
	game.play_art.show_offense(pc.off_play, pc.off_flipped)
	# The banner's line of buttons would run into the panel.
	_hide_banner(line)
	game.hud.show_hot_routes("", 1.0, line.slot)
	game.audio.play(&"ui_page")


## The four face buttons are the receivers' own here, so it is the left trigger
## that leaves: let go with no route on the field. Held, it turns the sticks
## from calling a route to showing it, and letting go calls the one shown.
func _update_hot(line: Line) -> void:
	if not _can_change(line):
		_close(line)
		return
	var pad: PadInput = line.pad
	# Only a trigger pulled in here: one still held from showing the play is not it.
	if pad.just_pressed(&"reveal_play"):
		line.hot_lt = true
	for slot: int in mini(HumanController.PASS_ACTIONS.size(), pc.eligible.size()):
		if pad.just_pressed(HumanController.PASS_ACTIONS[slot]):
			var man: Player = pc.eligible[slot]
			# Only a man who was going out on a route: not the back the ball is
			# handed to.
			if man.brain.off_assign.job == OffenseAssignment.Job.ROUTE:
				_show_hot(line, -1)
				line.hot_man = man
				# The way to the ball on screen, as OffenseAssignment.hot_route has it.
				var start_y: float = man.brain.off_assign.start.y
				var inside: float = (-signf(start_y) if absf(start_y) > 0.5 else 1.0) * _hot_screen(line)
				game.hud.show_hot_routes("(%s) %s" % [line.human.pass_label(slot), man.brain.off_assign.label], inside, line.slot)
				game.audio.play(&"ui_move")
			else:
				game.audio.play(&"ui_tick")
			return
	if line.hot_lt:
		var held: int = _hot_held(line) if line.hot_man != null else -1
		if pad.pressed(&"reveal_play"):
			_show_hot(line, held)
		elif held < 0 or not _give_hot(line, held):
			_close(line)
		return
	if line.hot_man != null:
		var pressed: int = _hot_pressed(line)
		if pressed >= 0:
			_give_hot(line, pressed)


## A route and the way it breaks on screen (-1 left, 0 neither, 1 right) as one
## number.
func _hot_key(kind: OffenseAssignment.Hot, way: int) -> int:
	return int(kind) * 3 + way + 1


## The route a stick pushed just now asks for (see _hot_key), or -1.
func _hot_pressed(line: Line) -> int:
	var pad: PadInput = line.pad
	if pad.just_pressed(&"move_up"):
		return _hot_key(OffenseAssignment.Hot.STREAK, 0)
	if pad.just_pressed(&"move_down"):
		return _hot_key(OffenseAssignment.Hot.CURL, 0)
	if pad.just_pressed(&"move_left"):
		return _hot_key(OffenseAssignment.Hot.SLANT, -1)
	if pad.just_pressed(&"move_right"):
		return _hot_key(OffenseAssignment.Hot.SLANT, 1)
	if pad.just_pressed(&"quick_up"):
		return _hot_key(OffenseAssignment.Hot.POST, 0)
	if pad.just_pressed(&"quick_down"):
		return _hot_key(OffenseAssignment.Hot.DRAG, 0)
	if pad.just_pressed(&"quick_left"):
		return _hot_key(OffenseAssignment.Hot.OUT, -1)
	if pad.just_pressed(&"quick_right"):
		return _hot_key(OffenseAssignment.Hot.OUT, 1)
	return -1


## The route the sticks are held on right now (see _hot_key): that of the one
## pushed further, or -1 with both at rest.
func _hot_held(line: Line) -> int:
	var left: Vector2 = line.pad.vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var right: Vector2 = line.pad.vector(&"quick_left", &"quick_right", &"quick_up", &"quick_down")
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
## the person sees them.
func _hot_side(line: Line, key: int) -> float:
	return float(key % 3 - 1) * _hot_screen(line)


## Turns a side on screen (-1 left, 1 right) into one in the play's own frame,
## and back: the camera's right, in the frame the play is drawn in
## (PlayController.to_world).
func _hot_screen(line: Line) -> float:
	# Somebody on another machine has a camera of their own.
	var right: float = signf(line.pad.view_right.z if line.pad.has_view else game.camera_rig.basis.x.z)
	if right == 0.0:
		right = pc.off_dir
	var flip: float = -1.0 if pc.off_flipped else 1.0
	return right * pc.off_dir * flip


## Draws route `key` on the field for the picked man, in place of the one he
## has (-1: no route, his own again).
func _show_hot(line: Line, key: int) -> void:
	if key == line.hot_shown:
		return
	line.hot_shown = key
	if key < 0:
		game.play_art.clear_hot_preview()
		game.hud.light_hot_route(-1, 0)
		return
	game.hud.light_hot_route(int(_hot_kind(key)), key % 3 - 1)
	game.play_art.set_hot_preview(line.hot_man, OffenseAssignment.hot_route(line.hot_man.brain.off_assign, _hot_kind(key), _hot_side(line, key)))
	game.audio.play(&"ui_tick")


## The hot route itself: the picked man runs route `key`, and it is back to the line.
func _give_hot(line: Line, key: int) -> bool:
	if not pc.hot_route(line.hot_man, _hot_kind(key), _hot_side(line, key)):
		return false
	game.audio.play(&"ui_confirm")
	_close(line)
	return true
