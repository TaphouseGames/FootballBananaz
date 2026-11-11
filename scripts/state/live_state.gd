extends GameState
## The ball is live. Ends at the whistle.


func enter() -> void:
	if not game.human.is_active():
		return
	if game.human.team == game.offense:
		if pc.off_play.is_run:
			game.hud.set_hint("Move      Shift / RT: turbo      E / (X): juke")
		else:
			game.hud.set_hint("Space / (A): pass (hold a direction to pick)      E / (X): next receiver, juke after the catch      Shift / RT: turbo")
	else:
		game.hud.set_hint("Space / (A): switch to nearest defender      E / (X): dive or shove      Shift / RT: turbo")


func physics_update(delta: float) -> void:
	pc.simulate(delta)
	if not pc.ball_dead:
		return
	if pc.result == PlayController.Result.TOUCHDOWN:
		machine.transition(&"Scored")
	else:
		machine.transition(&"Dead")
