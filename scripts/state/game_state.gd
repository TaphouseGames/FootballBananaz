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


## In place of physics_update while the screen dips to black on the way to the
## next state, which has already been asked for.
func hold_update(_delta: float) -> void:
	pass
