extends GameState
## Whistle has blown. Late hits are legal until the window closes, then the
## result of the play is applied.


func enter() -> void:
	game.hud.show_banner(pc.result_text())


func exit() -> void:
	game.hud.hide_banner()


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	var wait: float = game.tuning.late_hit_window
	# After a try the game lingers before the kickoff. Not when the half is over:
	# then no kickoff follows.
	if game.conversion and not game.is_time_up():
		wait += game.tuning.conversion_linger
	# A dance picked after a first down or a long gain is seen out first.
	if time_in_state >= wait and not pc.gain_dance_running():
		machine.transition(game.resolve_play(pc.result, pc.dead_spot_x, pc.final_team))


func hold_update(delta: float) -> void:
	pc.simulate_dead(delta)
