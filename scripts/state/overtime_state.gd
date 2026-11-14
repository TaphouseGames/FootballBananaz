extends GameState
## The second half's clock has run out with the score level. Nobody ties: the
## game goes to sudden death, which opens with a scramble for the ball as each
## half did, and whoever scores first (a touchdown or a safety) has won.


func enter() -> void:
	var home: Team = game.home
	game.start_overtime()
	game.hud.show_banner("OVERTIME!", "%s %d  -  %d %s      Sudden death: first score wins" % [home.short_name, home.score, game.away.score, game.away.short_name])
	game.hud.set_hint("")


func exit() -> void:
	game.hud.hide_banner()


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	if time_in_state >= game.tuning.overtime_banner_time:
		machine.transition(&"Scramble")


func hold_update(delta: float) -> void:
	pc.simulate_dead(delta)
