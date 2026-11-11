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
	game.hud.set_hint("Enter / Start: play again")


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	if time_in_state > 0.5 and Input.is_action_just_pressed(&"restart"):
		get_tree().reload_current_scene()
