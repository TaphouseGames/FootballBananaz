extends GameState
## Whistle has blown. Late hits are legal until the window closes, then the
## result of the play is applied.


func enter() -> void:
	game.hud.show_banner(pc.result_text())


func exit() -> void:
	game.hud.hide_banner()


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	if time_in_state >= game.tuning.late_hit_window:
		machine.transition(game.resolve_play(pc.result, pc.dead_spot_x, pc.final_team))


func hold_update(delta: float) -> void:
	pc.simulate_dead(delta)
