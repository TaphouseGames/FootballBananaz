class_name GameState
extends Node
## Base class for the states under PlayController/StateMachine.
## The node's name is the state's name.

var machine: StateMachine
var pc: PlayController
var game: Game
## Seconds since enter(), in game time.
var time_in_state: float = 0.0


func enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


## Shows what is left of `limit` seconds in this state on the HUD, with a tick
## for each of the last few. True once the time is up; a limit of 0 never is.
func count_down(limit: float, delta: float) -> bool:
	if limit <= 0.0:
		return false
	var left: float = maxf(limit - time_in_state, 0.0)
	var warn: bool = left <= game.tuning.clock_warning
	game.hud.set_countdown(left, warn)
	if warn and left > 0.0 and ceili(left) != ceili(left + delta):
		game.audio.play(&"ui_tick")
	return left <= 0.0


## In place of physics_update while the screen dips to black on the way to the
## next state, which has already been asked for.
func hold_update(_delta: float) -> void:
	pass
