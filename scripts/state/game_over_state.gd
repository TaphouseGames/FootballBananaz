extends GameState
## Clock hit zero and the last play is over.


func enter() -> void:
	var home: Team = game.home
	var away: Team = game.away
	var headline: String = "TIE GAME"
	if home.score != away.score:
		var winner: Team = home if home.score > away.score else away
		headline = "%s WIN!" % winner.short_name
	game.hud.show_banner(headline, "Final:  %s %d  -  %d %s" % [home.short_name, home.score, away.score, away.short_name])
	# Start opens the pause menu, which offers the rematch here (see PauseMenu).
	game.hud.set_hint("Start: play again, box score, team stats, roster")


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
