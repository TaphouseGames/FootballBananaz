class_name NetView
extends Node
## The picture of an online match on a person's machine. Every tick it puts the
## next state from the server on the match here (NetState), does what happened
## once in that tick (NetEvents), and has every player and the ball draw
## themselves from it.
##
## States come in unevenly, so a couple wait here before they are shown: one a
## tick, in order. With none to show the last one stands. With more waiting
## than there should be (after a hit-stop held this machine up, say) two are
## shown a tick until it has caught up; far too many, and the oldest are
## stepped over.
##
## The person's own player does not wait for the server. A state says which
## tick of their buttons it was played with; from where the server has him in
## it, he is run on through the ticks sent since (Player.net_predict), so the
## stick moves him at once. Only while his running is the stick's alone
## (Player.net_free): held still for a handoff, tackled, diving or run by the
## AI, he is where the server says. Where the two disagree he is eased across,
## not jumped.

## States that wait before the first is shown.
const START_WITH: int = 2
## More than this waiting and two are shown a tick.
const CATCH_UP_FROM: int = 3
## More than this waiting and the oldest are stepped over.
const MAX_WAITING: int = 30
## A node that moved further than this in a tick was put there: it is drawn
## there at once, not slid over.
const JUMP: float = 4.0
## The person's own player: how much of the gap between where he was drawn and
## where he should be is left after a tick, and the gap above which he is put
## there at once.
const EASE: float = 0.85
const SNAP: float = 3.0
## What of a player is put back to the server's word before he is run on.
const OWN_FIELDS: Array[StringName] = [
	&"position", &"velocity", &"facing", &"move_input", &"wants_turbo", &"turbo", &"turbo_locked",
	&"turbo_active", &"feet_set", &"_feet_set_time", &"dive_get_up_timer",
]

var game: Game
var seat: int = -1
## This machine's end of the line: the moves it has sent. Without one, nobody
## is run ahead of the server.
var client: NetClient
## Off, the person's own player is drawn where the server has him, like
## everybody else (to tell what running him ahead is worth).
var predict: bool = true
## The tick of the state on show, -1 before the first.
var shown_tick: int = -1
## States shown, ticks that passed with no new one, and states stepped over.
var shown: int = 0
var held: int = 0
var skipped: int = 0
## Ticks on which two states were shown to catch up.
var caught_up: int = 0
## States that came in, and those of them that were not what a state should be.
var received: int = 0
var refused: int = 0
## Things that happened once, done here.
var replayed: int = 0
## And how many of them on each part (NetEvents.Part).
var replayed_on: Dictionary[int, int] = {}
## The person's own player: ticks he was run ahead of the server; how far
## ahead of it he was, added up; and how far the server's word moved him from
## where he was run to the tick before, added up, and at the most.
var predicted: int = 0
var lead_sum: float = 0.0
var correction_sum: float = 0.0
var correction_max: float = 0.0

var _waiting: Dictionary[int, Array] = {}
var _next: int = -1
## What happened once, by the tick it happened on, oldest first.
var _events: Array[Array] = []
var _last_places: PackedVector3Array = PackedVector3Array()
## The person's own player, as the state on show has him; where he was drawn
## last (INF: nowhere yet); and where he was run to last tick with the speed he
## had (INF: he was not).
var _own: Player
var _own_base: Dictionary[StringName, Variant] = {}
var _drawn_at: Vector3 = Vector3.INF
var _ran_to: Vector3 = Vector3.INF
var _ran_velocity: Vector3 = Vector3.ZERO


func setup(p_game: Game, p_seat: int, p_client: NetClient = null) -> void:
	game = p_game
	seat = p_seat
	client = p_client
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
	if not _show_next():
		if shown > 0:
			held += 1
	elif _waiting.size() > CATCH_UP_FROM:
		_show_next()
		caught_up += 1
	if shown > 0:
		_run_own()
		_draw()


## Puts the next state on the match here, and does what happened once up to
## it. False with none to show.
func _show_next() -> bool:
	var state: Array = _take()
	if state.is_empty():
		return false
	NetState.unpack(game, state, seat)
	shown += 1
	# The person's own player as the server has him: where he is run on from.
	var own: Player = game.human.controlled if game.human.is_active() else null
	if own != _own:
		_own = own
		_drawn_at = Vector3.INF
		_ran_to = Vector3.INF
	_own_base.clear()
	if _own != null:
		for field: StringName in OWN_FIELDS:
			_own_base[field] = _own.get(field)
	if client != null and seat >= 0 and seat < game.net_acks.size():
		client.forget_moves(game.net_acks[seat])
	if shown == 1:
		game.snap_camera()
	while not _events.is_empty() and int(_events[0][0]) <= shown_tick:
		var notes: Array = _events.pop_front()[1]
		for note: Variant in notes:
			NetEvents.replay(game, note)
			replayed += 1
			if typeof(note) == TYPE_ARRAY and (note as Array).size() == 4 and typeof(note[1]) == TYPE_INT:
				replayed_on[note[1]] = replayed_on.get(note[1], 0) + 1
	return true


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


## The person's own player: from where the server has him, on through the
## moves it has not played yet, and eased to there from where he was drawn.
func _run_own() -> void:
	if _own == null or _own_base.is_empty():
		return
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	for field: StringName in _own_base:
		_own.set(field, _own_base[field])
	var server_place: Vector3 = _own.position
	var running: bool = predict and client != null and client.playing and _own.net_free and _own.can_act() \
			and seat >= 0 and seat < game.net_acks.size()
	if running:
		var ticks: Array = client.moves.keys()
		ticks.sort()
		for sent: int in ticks:
			if sent > game.net_acks[seat]:
				var move: Array = client.moves[sent]
				_own.net_predict(move[0], move[1], delta)
		predicted += 1
		lead_sum += _own.position.distance_to(server_place)
		if _ran_to != Vector3.INF:
			# Where one more tick of running would have had him, against where
			# the server's word and the same running have him.
			var correction: float = _own.position.distance_to(_ran_to + _ran_velocity * delta)
			correction_sum += correction
			correction_max = maxf(correction_max, correction)
		_ran_to = _own.position
		_ran_velocity = _own.velocity
	else:
		_ran_to = Vector3.INF
	# Eased from where he was drawn: where the two disagree he does not jump.
	if _drawn_at != Vector3.INF:
		var gap: Vector3 = _drawn_at + _own.velocity * delta - _own.position
		gap.y = 0.0
		if gap.length() <= SNAP:
			_own.position += gap * EASE
	_drawn_at = _own.position


## Everybody draws themselves as the state has them.
func _draw() -> void:
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	var nodes: Array[Node3D] = [game.ball]
	for player: Player in game.play_controller.players:
		player._update_visual(delta, false)
		nodes.append(player)
	# The ball in the person's own player's hands goes where he is drawn.
	if _own != null and game.ball.state == Ball.State.HELD and game.ball.carrier == _own:
		game.ball._follow_carrier()
	game.ball._update_visual(delta)
	if _last_places.size() != nodes.size():
		_last_places.resize(nodes.size())
		for i: int in nodes.size():
			_last_places[i] = nodes[i].position
	for i: int in nodes.size():
		if nodes[i].position.distance_to(_last_places[i]) > JUMP:
			nodes[i].reset_physics_interpolation()
		_last_places[i] = nodes[i].position
