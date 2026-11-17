extends GameState
## Teams are set. The person snaps on offense, with the play clock running,
## (B) for more shouting from the quarterback and (Y) to send a receiver in
## motion when the play has one; the CPU snaps on its own timer.

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
		game.hud.show_banner("", "%s%s  -  get ready" % [pc.def_play.play_name, flipped])
		game.hud.set_hint("")
	else:
		game.hud.set_hint("AUTOPLAY")


func exit() -> void:
	game.hud.hide_banner()
	game.hud.hide_countdown()
	if _cue_shown:
		game.hud.set_hint("")


## The person's play and buttons. (Y) is offered for as long as there is a
## motion to call.
func _show_offense_banner() -> void:
	var flipped: String = " (flipped)" if pc.off_flipped else ""
	var motion: String = "   (Y) motion" if pc.motion.available() else ""
	game.hud.show_banner("", "%s%s  -  (A) snap   (B) shout%s" % [pc.off_play.play_name, flipped, motion])


func physics_update(delta: float) -> void:
	game.human.update_pre_snap()
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
