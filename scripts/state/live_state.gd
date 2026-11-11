extends GameState
## The ball is live. Ends at the whistle.


func enter() -> void:
	if not game.human.is_active():
		return
	if game.human.team == game.offense:
		if pc.off_play.is_run:
			game.hud.set_hint("Move      L / (B): spin      U O / (LB)(RB): stiff arm      K / (X): dive, down where you land      Space J / (Y)(A): jump      Shift / RT: turbo")
		else:
			game.hud.set_hint("J K L / (A)(X)(B): tap to lob, hold longer to throw harder      Hold Shift / RT: tuck and run, let go to throw      Running with the ball  -  (B): spin   (LB)(RB): stiff arm   (X): dive   (Y)(A): jump")
	else:
		game.hud.set_hint("Q / (B): switch defender      E / (X): dive      Space J / (Y)(A): jump      Shift / RT: turbo")


func physics_update(delta: float) -> void:
	pc.simulate(delta)
	if not pc.ball_dead:
		return
	if pc.result == PlayController.Result.TOUCHDOWN:
		machine.transition(&"Scored")
	else:
		machine.transition(&"Dead")
