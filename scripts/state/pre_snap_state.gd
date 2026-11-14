extends GameState
## Teams are set. The person snaps on offense, with the play clock running and
## (B) for more shouting from the quarterback; the CPU snaps on its own timer.

var _human_snaps: bool = false
var _cpu_delay: float = 0.0
## When the person's quarterback last shouted, in time_in_state.
var _last_call: float = 0.0


func enter() -> void:
	_human_snaps = game.human.is_active() and game.human.team == game.offense
	_cpu_delay = randf_range(game.tuning.cpu_snap_delay_min, game.tuning.cpu_snap_delay_max)
	_last_call = 0.0
	# A CPU quarterback gets a silly line out before he snaps.
	var silly: float = game.audio.qb_open()
	_cpu_delay = maxf(_cpu_delay, minf(silly, game.tuning.cpu_silly_hold_max))
	if _human_snaps:
		var flipped: String = " (flipped)" if pc.off_flipped else ""
		game.hud.show_banner("", "%s%s  -  (A) snap   (B) shout" % [pc.off_play.play_name, flipped])
		game.hud.set_hint("")
	elif game.human.is_active():
		game.hud.show_banner("", "%s  -  get ready" % pc.def_play.play_name)
		game.hud.set_hint("")
	else:
		game.hud.set_hint("AUTOPLAY")


func exit() -> void:
	game.hud.hide_banner()
	game.hud.hide_countdown()


func physics_update(delta: float) -> void:
	game.human.update_pre_snap()
	var snap_now: bool = false
	if _human_snaps:
		var tuning: Tuning = game.tuning
		if Input.is_action_just_pressed(&"qb_call") and time_in_state - _last_call >= tuning.qb_call_gap:
			_last_call = time_in_state
			game.audio.qb_call()
		snap_now = time_in_state >= tuning.pre_snap_delay and Input.is_action_just_pressed(&"confirm")
		# Out of time: the ball is snapped for them.
		if count_down(tuning.play_clock, delta):
			snap_now = true
	else:
		snap_now = time_in_state >= _cpu_delay
	if snap_now:
		pc.snap()
		machine.transition(&"Live")
