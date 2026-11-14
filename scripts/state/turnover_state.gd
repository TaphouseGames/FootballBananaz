extends GameState
## Change of possession (downs, interception, safety). Game.resolve_play() has
## already swapped the teams; this state just announces it.


func enter() -> void:
	# A scramble nobody won goes up again: it is nobody's ball yet.
	game.hud.show_banner(game.banner_text, "" if game.scramble_due else "%s ball" % game.offense.team_name)
	game.hud.set_hint("")


func exit() -> void:
	game.hud.hide_banner()


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	if time_in_state >= game.tuning.turnover_banner_time:
		machine.transition(game.next_play_state())


func hold_update(delta: float) -> void:
	pc.simulate_dead(delta)
