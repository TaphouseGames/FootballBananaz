extends GameState
## The ball is live. Ends at the whistle.

const DEFENSE_HINT: String = "(B): switch defender      (X): dive      (Y)(A): jump      RT: turbo"
const RUN_HINT: String = "Stick: move      (B): spin, with the stick: juke      (LB)(RB): stiff arm      (X): dive, down where you land      (Y)(A): jump      RT: turbo"
const RETURN_HINT: String = "Stick: move      (B): spin, with the stick: juke      (LB)(RB): stiff arm      (X): dive (in your own end zone: touchback)      (Y)(A): jump      RT: turbo"
const PASS_HINT: String = "(A)(X)(B): tap to lob, hold longer to throw harder      Hold (LB): lead him   (RB): underthrow      Hold RT: tuck and run, let go to throw      Running with the ball  -  (B): spin   (LB)(RB): stiff arm   (X): dive   (Y)(A): jump"

## Which side's prompts are showing. A turnover swaps them mid-play.
var _defending: bool = false


func enter() -> void:
	if not game.human.is_active():
		return
	_defending = game.human.is_defending()
	_show_hint()


func physics_update(delta: float) -> void:
	pc.simulate(delta)
	if not pc.ball_dead:
		if game.human.is_active() and game.human.is_defending() != _defending:
			_defending = not _defending
			_show_hint()
		return
	# A try that gets in is settled with the other results, in Game.resolve_play().
	if pc.result == PlayController.Result.TOUCHDOWN and not game.conversion:
		machine.transition(&"Scored")
	else:
		machine.transition(&"Dead")


func _show_hint() -> void:
	if _defending:
		game.hud.set_hint(DEFENSE_HINT)
	elif pc.kickoff:
		game.hud.set_hint(RETURN_HINT)
	elif game.human.team == pc.offense and not pc.off_play.is_run:
		game.hud.set_hint(PASS_HINT)
	else:
		game.hud.set_hint(RUN_HINT)
