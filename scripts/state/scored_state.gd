extends GameState
## Touchdown. Points go up, the celebration (and late hits) play out, then the
## other team gets the ball.

var _scorer: Team


func enter() -> void:
	_scorer = pc.final_team
	game.award_touchdown(_scorer)
	game.impact(game.tuning.tackle_shake, 1.0)
	game.hud.show_banner("TOUCHDOWN!", _scorer.team_name)
	game.hud.set_hint("")


func exit() -> void:
	game.hud.hide_banner()


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	if time_in_state >= game.tuning.scored_banner_time:
		game.start_drive_after_score(_scorer)
		machine.transition(game.next_play_state())
