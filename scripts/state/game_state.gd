class_name GameState
extends Node
## Base class for the states under PlayController/StateMachine.
## The node's name is the state's name.

var machine: StateMachine
var pc: PlayController
var game: Game
## Seconds since enter(), in game time.
var time_in_state: float = 0.0
## The seats that have asked to skip the scene this state shows (skip_asked).
var _skips: Dictionary[int, bool] = {}


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


## Nobody has asked to skip yet: for enter().
func skip_reset() -> void:
	_skips.clear()


## (A) was pressed to skip the scene this state shows. `open`: a press counts
## by now. In an online match each person has to have pressed it: the one who
## has is told they are waiting, the other that they are waited for. (The
## scene's own longest time ends it for both all the same.)
func skip_asked(open: bool) -> bool:
	if Game.net_mode != Game.NetMode.SERVER:
		return open and Input.is_action_just_pressed(&"confirm")
	var people: int = 0
	for person: HumanController in game.humans:
		if person.is_active():
			people += 1
	for person: HumanController in game.humans:
		if not person.is_active():
			continue
		if open and not _skips.has(person.seat) and person.pad.just_pressed(&"confirm"):
			_skips[person.seat] = true
			for other: HumanController in game.humans:
				if other.is_active() and _skips.size() < people:
					game.hud.set_skip_note("WAITING FOR THE OTHER PLAYER TO SKIP" if other == person else "THE OTHER PLAYER WANTS TO SKIP      (A)  SKIP", other.seat)
	return people > 0 and _skips.size() >= people


## In place of physics_update while the screen dips to black on the way to the
## next state, which has already been asked for.
func hold_update(_delta: float) -> void:
	pass
