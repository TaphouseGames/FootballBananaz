extends GameState
## How a half opens: the ball in the middle of the field, each team's mascot on
## its own side of it and nobody else out there. After a moment it goes straight
## up, the two run in, and the one who comes up with it runs it back for its
## team (played out in the Live state).


func enter() -> void:
	game.scramble_due = false
	game.start_scramble()
	pc.line_up_scramble()
	game.snap_camera()
	game.hud.show_banner("MASCOT SCRAMBLE!", "Whoever gets it, has it")
	game.hud.set_hint("" if game.human.is_active() else "AUTOPLAY")


func exit() -> void:
	game.hud.hide_banner()


func physics_update(_delta: float) -> void:
	if time_in_state >= game.tuning.scramble_delay:
		pc.start_scramble()
		machine.transition(&"Live")
