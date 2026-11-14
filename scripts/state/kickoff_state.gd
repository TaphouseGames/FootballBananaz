extends GameState
## Both teams line up for a kickoff to Game.kickoff_to. After a moment the ball
## is kicked by itself and the return is played out in the Live state.


func enter() -> void:
	var receiving: Team = game.kickoff_to if game.kickoff_to != null else game.home
	game.kickoff_to = null
	game.start_kickoff(receiving)
	pc.line_up_kickoff()
	game.snap_camera()
	game.hud.show_banner("KICKOFF", "%s to receive" % receiving.team_name)
	game.hud.set_hint("" if game.human.is_active() else "AUTOPLAY")


func exit() -> void:
	game.hud.hide_banner()


func physics_update(_delta: float) -> void:
	if time_in_state >= game.tuning.kickoff_delay:
		pc.kick_off()
		machine.transition(&"Live")
