extends GameState
## The ball is live. Ends at the whistle.

## What the buttons do is on the pause menu's controls screen (see PauseMenu).


func physics_update(delta: float) -> void:
	pc.simulate(delta)
	if not pc.ball_dead:
		return
	# A try that gets in is settled with the other results, in Game.resolve_play().
	if pc.result == PlayController.Result.TOUCHDOWN and not game.conversion:
		machine.transition(&"Scored")
	else:
		machine.transition(&"Dead")
