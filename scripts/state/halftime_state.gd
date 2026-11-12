extends GameState
## The first half's clock has run out and its last play is over. Shows the
## score, then the second half starts with a kickoff.


func enter() -> void:
	var home: Team = game.home
	var away: Team = game.away
	game.add_stat(&"halftimes")
	game.hud.show_banner("HALFTIME", "%s %d  -  %d %s" % [home.short_name, home.score, away.score, away.short_name])
	game.hud.set_hint("")


func exit() -> void:
	game.hud.hide_banner()


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	if time_in_state >= game.tuning.halftime_banner_time:
		game.start_second_half()
		machine.transition(&"Kickoff")
