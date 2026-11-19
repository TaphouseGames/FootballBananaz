extends GameState
## Teams are set. The person snaps on offense, with the play clock running,
## (B) for more shouting from the quarterback and (Y) to send a receiver in
## motion when the play has one; the CPU snaps on its own timer.
##
## On either side of the ball the person can have a play drawn on the field
## (PlayArt): left trigger held and the stick pushed up shows the play that was
## called, any other way a fake from the same formation (or, on defense, the
## same tab). The trigger by itself shows nothing, so whoever is watching the
## screen cannot tell the real one from a fake.

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
## The hint under the banner is the jet motion's snap cue right now.
var _cue_shown: bool = false


func enter() -> void:
	_human_snaps = game.human.is_active() and game.human.team == game.offense
	_cpu_delay = randf_range(game.tuning.cpu_snap_delay_min, game.tuning.cpu_snap_delay_max)
	_last_call = 0.0
	_cpu_motion_at = -1.0
	_cue_shown = false
	_pick_fakes()
	# A CPU quarterback gets a silly line out before he snaps.
	var silly: float = game.audio.qb_open()
	_cpu_delay = maxf(_cpu_delay, minf(silly, game.tuning.cpu_silly_hold_max))
	if not _human_snaps and pc.motion.available() and randf() < game.tuning.ai_motion_chance:
		_cpu_motion_at = game.tuning.ai_motion_time
		if pc.motion.is_jet():
			# A jet is snapped while he runs: he is sent late enough for that.
			_cpu_motion_at = maxf(_cpu_motion_at, _cpu_delay - 0.6)
	if _human_snaps:
		_show_offense_banner()
		game.hud.set_hint("")
	elif game.human.is_active():
		var flipped: String = " (flipped)" if pc.def_flipped else ""
		game.hud.show_banner("", "%s%s  -  get ready   (LT) show play" % [pc.def_play.play_name, flipped])
		game.hud.set_hint("")
	else:
		game.hud.set_hint("AUTOPLAY")


func exit() -> void:
	game.hud.hide_banner()
	game.hud.hide_countdown()
	game.play_art.clear()
	if _cue_shown:
		game.hud.set_hint("")


## The person's play and buttons. (Y) is offered for as long as there is a
## motion to call.
func _show_offense_banner() -> void:
	var flipped: String = " (flipped)" if pc.off_flipped else ""
	var motion: String = "   (Y) motion" if pc.motion.available() else ""
	game.hud.show_banner("", "%s%s  -  (A) snap   (B) shout%s   (LT) show play" % [pc.off_play.play_name, flipped, motion])


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
	game.human.update_pre_snap()
	_update_reveal()
	pc.motion.tick(delta)
	var snap_now: bool = false
	if _human_snaps:
		var tuning: Tuning = game.tuning
		if Input.is_action_just_pressed(&"qb_call") and time_in_state - _last_call >= tuning.qb_call_gap:
			_last_call = time_in_state
			game.audio.qb_call()
		if Input.is_action_just_pressed(&"motion") and pc.motion.call_motion():
			_show_offense_banner()
		# A jet man close to the quarterback: now is the time.
		var cue: bool = pc.motion.jet_in_window()
		if cue != _cue_shown:
			_cue_shown = cue
			game.hud.set_hint("(A) SNAP IT!" if cue else "")
		snap_now = time_in_state >= tuning.pre_snap_delay and Input.is_action_just_pressed(&"confirm")
		# Out of time: the ball is snapped for them.
		if count_down(tuning.play_clock, delta):
			snap_now = true
	else:
		if _cpu_motion_at >= 0.0 and time_in_state >= _cpu_motion_at:
			_cpu_motion_at = -1.0
			pc.motion.call_motion()
		snap_now = _cpu_snaps()
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
