class_name NetView
extends Node
## The picture of an online match on a person's machine. Every tick it puts the
## next state from the server on the match here (NetState), does what happened
## once in that tick (NetEvents), and has every player and the ball draw
## themselves from it.
##
## States come in unevenly, so a couple wait here before they are shown: one a
## tick, in order. With none to show the last one stands; with too many waiting
## the oldest are stepped over.

## States that wait before the first is shown.
const START_WITH: int = 2
## More than this waiting and the picture is that far behind for good.
const MAX_WAITING: int = 5
## A node that moved further than this in a tick was put there: it is drawn
## there at once, not slid over.
const JUMP: float = 4.0

var game: Game
var seat: int = -1
## The tick of the state on show, -1 before the first.
var shown_tick: int = -1
## States shown, ticks that passed with no new one, and states stepped over.
var shown: int = 0
var held: int = 0
var skipped: int = 0
## States that came in, and those of them that were not what a state should be.
var received: int = 0
var refused: int = 0
## Things that happened once, done here.
var replayed: int = 0

var _waiting: Dictionary[int, Array] = {}
var _next: int = -1
## What happened once, by the tick it happened on, oldest first.
var _events: Array[Array] = []
var _last_places: PackedVector3Array = PackedVector3Array()


func setup(p_game: Game, p_seat: int) -> void:
	game = p_game
	seat = p_seat
	# Before any node's own tick, and when the tree is paused too: the server
	# does not wait for a menu here.
	get_tree().physics_frame.connect(_before_tick)


func add_state(tick: int, state: Variant) -> void:
	received += 1
	if not NetState.fits(game, state):
		refused += 1
	elif tick > shown_tick and not _waiting.has(tick):
		_waiting[tick] = state


func add_events(tick: int, notes: Array) -> void:
	_events.append([tick, notes])


func _before_tick() -> void:
	if game == null or game.play_controller == null or game.play_controller.players.is_empty():
		return
	var state: Array = _take()
	if not state.is_empty():
		NetState.unpack(game, state, seat)
		shown += 1
		if shown == 1:
			game.snap_camera()
	elif shown > 0:
		held += 1
	if shown == 0:
		return
	while not _events.is_empty() and int(_events[0][0]) <= shown_tick:
		var notes: Array = _events.pop_front()[1]
		for note: Variant in notes:
			NetEvents.replay(game, note)
			replayed += 1
	_draw()


## The next state to show, or nothing.
func _take() -> Array:
	if _waiting.is_empty() or (_next < 0 and _waiting.size() < START_WITH):
		return []
	var oldest: int = _waiting.keys().min()
	var newest: int = _waiting.keys().max()
	# One that never came, with later ones here: it will not come now.
	_next = maxi(_next, oldest)
	if newest - _next >= MAX_WAITING:
		var to: int = newest - START_WITH + 1
		for tick: int in _waiting.keys():
			if tick < to:
				_waiting.erase(tick)
				skipped += 1
		_next = _waiting.keys().min()
	var state: Array = _waiting[_next]
	_waiting.erase(_next)
	shown_tick = _next
	_next += 1
	return state


## Everybody draws themselves as the state has them.
func _draw() -> void:
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	var nodes: Array[Node3D] = [game.ball]
	for player: Player in game.play_controller.players:
		player._update_visual(delta, false)
		nodes.append(player)
	game.ball._update_visual(delta)
	if _last_places.size() != nodes.size():
		_last_places.resize(nodes.size())
		for i: int in nodes.size():
			_last_places[i] = nodes[i].position
	for i: int in nodes.size():
		if nodes[i].position.distance_to(_last_places[i]) > JUMP:
			nodes[i].reset_physics_interpolation()
		_last_places[i] = nodes[i].position
