extends GameState
## The half's clock has gone under Tuning.warning_time and the play that took
## it there is over: a short stop, like the NFL's two-minute warning, then the
## next snap or kickoff. Once a half.


func enter() -> void:
	game.warning_half = game.half
	game.add_stat(&"warnings")
	var home: Team = game.home
	var away: Team = game.away
	var seconds: int = ceili(game.clock)
	game.hud.show_banner(
		"%d SECOND WARNING" % roundi(game.tuning.warning_time),
		"%s %d  -  %d %s      0:%02d LEFT" % [home.short_name, home.score, away.score, away.short_name, seconds])
	game.hud.set_hint("")


func exit() -> void:
	game.hud.hide_banner()


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	if time_in_state >= game.tuning.warning_banner_time:
		machine.transition(game.next_play_state())


func hold_update(delta: float) -> void:
	pc.simulate_dead(delta)
