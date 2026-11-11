extends GameState
## Teams are set. The person snaps on offense; the CPU snaps on its own timer.

var _human_snaps: bool = false
var _cpu_delay: float = 0.0


func enter() -> void:
	_human_snaps = game.human.is_active() and game.human.team == game.offense
	_cpu_delay = randf_range(game.tuning.cpu_snap_delay_min, game.tuning.cpu_snap_delay_max)
	if _human_snaps:
		game.hud.show_banner("", "%s  -  press Space / (A) to snap" % pc.off_play.play_name)
		game.hud.set_hint("")
	elif game.human.is_active():
		game.hud.show_banner("", "%s  -  get ready" % pc.def_play.play_name)
		game.hud.set_hint("Space / (A): pick another defender")
	else:
		game.hud.set_hint("AUTOPLAY")


func exit() -> void:
	game.hud.hide_banner()


func physics_update(_delta: float) -> void:
	game.human.update_pre_snap()
	var snap_now: bool = false
	if _human_snaps:
		snap_now = time_in_state >= game.tuning.pre_snap_delay and Input.is_action_just_pressed(&"pass_switch")
	else:
		snap_now = time_in_state >= _cpu_delay
	if snap_now:
		pc.snap()
		machine.transition(&"Live")
