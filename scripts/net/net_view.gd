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
## stepped over. Every state that waits is a tick the picture is late, so when
## there has been one to spare on every tick for a while, two are shown once:
## on a steady line none wait, and on an uneven one as many as it takes.
##
## The person's own player does not wait for the server. A state says which
## tick of their buttons it was played with; from how the server has him in
## it, he is run on through the ticks sent since, with the same code as the
## server runs him with (HumanController.net_predict, Player.net_predict). So
## the stick moves him at once, and a dive, a jump, a spin, a stiff arm or a
## shove starts at the press: its sound is played here then, and the server's
## word of it (which comes later) is not played again. What he does to anybody
## else, a throw, and what anybody does to him are the server's and come when
## it says. Only while his buttons are his alone (Player.net_free): held still
## for a handoff, wrapped up, knocked down or run by the AI, he is where the
## server says. Where the two disagree he is eased across, not jumped.
##
## Three more things are shown ahead of the server's word. A pass: his arm, its
## sound and the shake of the gamepad go when the person lets go, the ball when
## the server says. A touchdown with nobody near him: whistle, banner and shake
## as he crosses the line (the points are the server's, and with no word of it
## from there the banner comes down again). And the person's own play-select
## cards (NetCards).
##
## On a tick with no new state everybody else runs on as he was going, so a
## state that is late does not show as a stop and a jump.

## States that wait before the first is shown.
const START_WITH: int = 2
## More than this waiting and two are shown a tick.
const CATCH_UP_FROM: int = 3
## More than this waiting and the oldest are stepped over.
const MAX_WAITING: int = 30
## Ticks in a row with a state to spare before two are shown in one.
const SPARE_TICKS: int = 90
## A node that moved further than this in a tick was put there: it is drawn
## there at once, not slid over.
const JUMP: float = 4.0
## The person's own player: how much of the gap between where he was drawn and
## where he should be is left after a tick, and the gap above which he is put
## there at once.
const EASE: float = 0.85
const SNAP: float = 3.0
## What of the person's own player the server started and the picture shows
## the run of: not run ahead with the rest of him.
const SERVERS_OWN: Array[StringName] = [&"flair_timer", &"pump_timer", &"catch_timer", &"dazed_timer"]
## The states the person's own player is run ahead in. (On the turf only after
## a dive of his own that was run ahead here too.)
const OWN_STATES: Array[Player.State] = [
	Player.State.NORMAL, Player.State.DIVING, Player.State.SPINNING, Player.State.STIFF_ARM,
	Player.State.JUMPING, Player.State.SHOVING,
]
## The sound of a move he starts.
const MOVE_SOUNDS: Dictionary[Player.State, StringName] = {
	Player.State.DIVING: &"dive", Player.State.JUMPING: &"jump", Player.State.SPINNING: &"spin",
	Player.State.STIFF_ARM: &"spin", Player.State.SHOVING: &"shove",
}
## States shown for which the server's word of something done here already is
## waited for, and ticks before another landing can be one of its own.
const SWALLOW_TICKS: int = 90
const LANDING_GAP: int = 20
## Ticks in a row everybody runs on with no new state.
const COAST_TICKS: int = 6
## Ticks before another pass let go here can be one of its own.
const THROW_GAP: int = 30
## No opponent on his feet within this of the person's own carrier, where the
## server has him and where he is run to: his touchdown is called here.
const SCORE_CLEAR: float = 5.0
## States the server has to call a touchdown called here, and states before
## another can be.
const SCORE_WAIT: int = 45
const SCORE_GAP: int = 240

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
## How many of the person's ticks the server was behind on those ticks, added
## up; and the ticks on which that was not what it was the tick before.
var behind_sum: int = 0
var behind_changes: int = 0
var _behind: int = -1
var _ran_tick: int = -1

var _waiting: Dictionary[int, Array] = {}
## The fewest states that were left waiting on a tick lately, and for how many
## ticks that has been counted.
var _spare: int = MAX_WAITING
var _spare_ticks: int = 0
var _next: int = -1
## What happened once, by the tick it happened on, oldest first.
var _events: Array[Array] = []
var _last_places: PackedVector3Array = PackedVector3Array()
## The person's own player, as the state on show has him; where he was drawn
## last (INF: nowhere yet); and where he was run to last tick with the speed he
## had (INF: he was not).
var _own: Player
var _own_base: Dictionary[StringName, Variant] = {}
## The buttons he is run through, a tick at a time.
var _pad: PadInput
## The tick of the person's buttons up to which a move's start, and a dive's
## landing, have been done here; he is down after a dive that was run ahead
## here; and the state the server had him in on the tick before.
var _started_through: int = -1
var _landed_through: int = -1000
var _own_landing: bool = false
var _base_state: Player.State = Player.State.NORMAL
## What was done here ahead of the server and will come from it: [the last
## state shown it is waited for, part, method, what tells it apart].
var _swallows: Array[Array] = []
## Moves started here at the press, and landings done here.
var moves_started: int = 0
var landings: int = 0
var swallowed: int = 0
## Passes let go here, touchdowns called here (and those the server did not
## call), and ticks everybody ran on with no new state.
var throws_started: int = 0
var scores_called: int = 0
var scores_wrong: int = 0
var coasted: int = 0
var cards: NetCards = NetCards.new()
var _thrown_through: int = -1000
## What HumanController.net_pass_state() gave after each tick run here.
var _pass_after: Dictionary[int, Array] = {}
## The state by which the server must have called the touchdown called here
## (-1: none waited for), and the state before which no other is called.
var _score_wait: int = -1
var _score_gap: int = -1
var _coasting: int = 0
var _drawn_at: Vector3 = Vector3.INF
var _ran_to: Vector3 = Vector3.INF
var _ran_velocity: Vector3 = Vector3.ZERO


func setup(p_game: Game, p_seat: int, p_client: NetClient = null) -> void:
	game = p_game
	seat = p_seat
	client = p_client
	cards.view = self
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
	cards.tick(game, client)
	if not _show_next():
		if shown > 0:
			held += 1
			_coast()
		_spare = 0
	else:
		_coasting = 0
		_spare = mini(_spare, _waiting.size())
		_spare_ticks += 1
		var one_over: bool = false
		if _spare_ticks >= SPARE_TICKS:
			one_over = _spare >= 1
			_spare = MAX_WAITING
			_spare_ticks = 0
		if _waiting.size() > CATCH_UP_FROM or one_over:
			_show_next()
			caught_up += 1
	if shown > 0:
		_run_own()
		_draw()
	if _score_wait >= 0 and shown > _score_wait:
		# The server never called it: he did not get in after all.
		_score_wait = -1
		scores_wrong += 1
		game.hud.hide_banner()


## No new state this tick: everybody runs on as he was going, and the ball
## flies on. The next state puts them where they are.
func _coast() -> void:
	_coasting += 1
	if _coasting > COAST_TICKS:
		return
	coasted += 1
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	for player: Player in game.play_controller.players:
		if not player.frozen:
			player.position += Vector3(player.velocity.x, 0.0, player.velocity.z) * delta
	var ball: Ball = game.ball
	if ball.state == Ball.State.FLIGHT:
		ball.flight_elapsed += delta
		ball.position = ball._flight_position(ball.flight_elapsed)
	elif ball.state == Ball.State.HELD and ball.carrier != null:
		ball._follow_carrier()


## `method` on `part` is done here now, ahead of the server: its word of it,
## told apart by `key`, is not done again.
func swallow(part: NetEvents.Part, method: StringName, key: Variant) -> void:
	_swallows.append([shown + SWALLOW_TICKS, part, method, key])


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
		_own_landing = false
	_own_base.clear()
	if _own != null:
		for row: Array in NetState.PLAYER:
			_own_base[row[0]] = _own.get(row[0])
	if client != null and seat >= 0 and seat < game.net_acks.size():
		client.forget_moves(game.net_acks[seat])
	if shown == 1:
		game.snap_camera()
	while not _events.is_empty() and int(_events[0][0]) <= shown_tick:
		var notes: Array = _events.pop_front()[1]
		for note: Variant in notes:
			if _swallowed(note):
				swallowed += 1
				continue
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
	# Up from a dive of his own: the next time he is down, somebody put him there.
	if _base_state == Player.State.DOWN and _own.state != Player.State.DOWN:
		_own_landing = false
	_base_state = _own.state
	var running: bool = predict and client != null and client.playing and _own.net_free and not _own.frozen \
			and (OWN_STATES.has(_own.state) or (_own.state == Player.State.DOWN and _own_landing)) \
			and seat >= 0 and seat < game.net_acks.size()
	if running:
		var ack: int = game.net_acks[seat]
		var human: HumanController = game.human
		var dead: bool = game.play_controller.ball_dead
		if _pad == null:
			_pad = PadInput.new()
			_pad.remote = true
			_pad.has_view = true
		# What was held on the tick the server played last: a button down then
		# is not pressed again on the next.
		_pad.forget()
		var held: Dictionary[StringName, Vector2] = {}
		if client.moves.has(ack):
			held = client.moves[ack][1]
		_pad.push(held)
		human.net_rewind(_pass_after.get(ack, []))
		for sent: int in _pass_after.keys():
			if sent < ack:
				_pass_after.erase(sent)
		var pc: PlayController = game.play_controller
		# The play's clock runs on with him: how long a pass button is held goes by it.
		var live_time: float = pc.live_time
		var ticks: Array = client.moves.keys()
		ticks.sort()
		var behind: int = 0
		# Where he is with every move but this tick's own: where he was run to
		# the tick before, if the server's word since has changed nothing.
		var before_last: Vector3 = Vector3.INF
		for sent: int in ticks:
			if sent > ack:
				if sent == client.tick:
					before_last = _own.position
				var move: Array = client.moves[sent]
				_pad.push(move[1])
				_pad.world_move = move[0]
				_pad.view_right = move[2]
				var was: Player.State = _own.state
				var throws: int = pc.net_throws
				if not dead:
					pc.live_time += delta
				human.net_predict(_pad, dead)
				_pass_after[sent] = human.net_pass_state()
				if pc.net_throws != throws and sent > _thrown_through + THROW_GAP:
					_thrown_through = sent
					_start_throw(pc.net_throw_power)
				if _own.state != was and sent > _started_through:
					_started_through = sent
					_start_move()
				was = _own.state
				_own.net_predict(delta)
				_keep_off_bodies()
				if was == Player.State.DIVING and _own.state == Player.State.DOWN and sent > _landed_through + LANDING_GAP:
					_landed_through = sent
					_land()
				behind += 1
		pc.live_time = live_time
		for field: StringName in SERVERS_OWN:
			_own.set(field, _own_base[field])
		_call_score(server_place)
		predicted += 1
		lead_sum += _own.position.distance_to(server_place)
		behind_sum += behind
		if _behind >= 0 and behind != _behind:
			behind_changes += 1
		_behind = behind
		if _ran_to != Vector3.INF and before_last != Vector3.INF and _ran_tick == client.tick - 1:
			var correction: float = before_last.distance_to(_ran_to)
			correction_sum += correction
			correction_max = maxf(correction_max, correction)
		_ran_to = _own.position
		_ran_velocity = _own.velocity
		_ran_tick = client.tick
	else:
		_ran_to = Vector3.INF
		_behind = -1
	# Eased from where he was drawn: where the two disagree he does not jump.
	if _drawn_at != Vector3.INF:
		var gap: Vector3 = _drawn_at + _own.velocity * delta - _own.position
		gap.y = 0.0
		if gap.length() <= SNAP:
			_own.position += gap * EASE
	_drawn_at = _own.position


## The person's own player has started a move ahead of the server: its sound
## now, and not again when the server tells of it.
func _start_move() -> void:
	moves_started += 1
	var sound: StringName = MOVE_SOUNDS.get(_own.state, &"")
	if sound == &"":
		return
	game.audio.action(_own, sound)
	swallow(NetEvents.Part.AUDIO, &"net_start", sound)
	if _own.state == Player.State.SHOVING:
		game.rumble.play_mine(&"shove", _own)
		swallow(NetEvents.Part.RUMBLE, &"play_mine", &"shove")


## The person has let go of a pass: the arm, the sound and the gamepad now, as
## PlayController.throw_ball does them, and not again when the server tells of
## it. The ball leaves when the server says.
func _start_throw(power: float) -> void:
	throws_started += 1
	if _own.animator != null:
		_own.animator.net_throw()
	game.audio.play(&"throw", 0.45, lerpf(0.9, 1.15, power))
	swallow(NetEvents.Part.AUDIO, &"net_start", &"throw")
	game.rumble.play_mine(&"throw", _own, null, lerpf(0.4, 1.0, power))
	swallow(NetEvents.Part.RUMBLE, &"play_mine", &"throw")


## The server moves two bodies that overlap apart, half the way each a tick.
## He is run through everybody else as the last state has them, the same way.
func _keep_off_bodies() -> void:
	var pc: PlayController = game.play_controller
	for other: Player in pc.players:
		if other == _own or not other.visible:
			continue
		var least: float = pc._body_distance(_own, other)
		if least <= 0.0:
			continue
		var offset: Vector3 = _own.position - other.position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist >= least:
			continue
		var normal: Vector3 = offset / dist if dist > 0.001 else Vector3(0.0, 0.0, -1.0)
		_own.position += normal * (least - dist) * 0.5


## The person's own carrier is over the goal line here and nobody is near
## enough to have stopped him on the way: the touchdown is called now, as
## ScoredState does on the server, and not again when it tells of it. The
## points and what follows are the server's.
func _call_score(server_place: Vector3) -> void:
	var pc: PlayController = game.play_controller
	var ball: Ball = game.ball
	if shown < _score_gap or pc.ball_dead or game.conversion or pc.state_machine.shown != &"Live":
		return
	if ball.state != Ball.State.HELD or ball.carrier != _own or not _own.has_ball:
		return
	var dir: int = _own.team.attack_dir
	var x: float = _own.position.x
	if not ((dir > 0 and x >= game.tuning.field_length) or (dir < 0 and x <= 0.0)):
		return
	for opponent: Player in _own.team.opponent.players:
		if opponent.is_down() or not opponent.visible:
			continue
		var at: Vector3 = opponent.position
		if Vector2(at.x - x, at.z - _own.position.z).length() < SCORE_CLEAR \
				or Vector2(at.x - server_place.x, at.z - server_place.z).length() < SCORE_CLEAR:
			return
	scores_called += 1
	_score_gap = shown + SCORE_GAP
	_score_wait = shown + SCORE_WAIT
	game.audio.play(&"whistle", 0.8)
	swallow(NetEvents.Part.AUDIO, &"net_start", &"whistle")
	game.impact(game.tuning.tackle_shake, 1.0)
	swallow(NetEvents.Part.GAME, &"impact", null)
	game.rumble.play_team(&"touchdown", _own.team)
	swallow(NetEvents.Part.RUMBLE, &"play_team", &"touchdown")
	game.hud.show_banner("TOUCHDOWN!", _own.team.team_name)
	swallow(NetEvents.Part.HUD, &"show_banner", "TOUCHDOWN!")


## His dive has come down ahead of the server: he tumbles now, and not again
## when the server tells of it.
func _land() -> void:
	landings += 1
	_own_landing = true
	_own.fall.start_dive_landing(_own.state_timer)
	swallow(NetEvents.Part.FALL, &"start_dive_landing", null)


## Whether `note` tells of something that was done here already (and is not to
## be done again).
func _swallowed(note: Variant) -> bool:
	if typeof(note) != TYPE_ARRAY or (note as Array).size() != 4 or typeof(note[0]) != TYPE_INT \
			or typeof(note[1]) != TYPE_INT or typeof(note[3]) != TYPE_ARRAY:
		return false
	var who: int = note[0]
	var part: int = note[1]
	var method: StringName = StringName(str(note[2]))
	var args: Array = note[3]
	var mine: bool = _own != null and who == game.play_controller.players.find(_own)
	if part == NetEvents.Part.HUD and cards.heard(game, method, args):
		return true
	# Knocked down by somebody: this is not the landing of his own dive.
	if mine and part == NetEvents.Part.FALL and method != &"start_dive_landing":
		_own_landing = false
	for at: int in range(_swallows.size() - 1, -1, -1):
		if int(_swallows[at][0]) < shown:
			_swallows.remove_at(at)
	for at: int in _swallows.size():
		var wait: Array = _swallows[at]
		if part != wait[1] or method != wait[2]:
			continue
		match part:
			NetEvents.Part.FALL:
				if not mine:
					continue
			NetEvents.Part.AUDIO:
				if args.size() < 2 or not game.audio.is_take_of(wait[3], str(args[1])):
					continue
			NetEvents.Part.RUMBLE:
				if args.is_empty() or StringName(str(args[0])) != wait[3]:
					continue
			NetEvents.Part.HUD:
				if args.is_empty() or str(args[0]) != str(wait[3]):
					continue
				# The server has called the touchdown called here.
				_score_wait = -1
		_swallows.remove_at(at)
		return true
	return false


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
