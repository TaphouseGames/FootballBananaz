class_name NetCards
extends RefCounted
## The person's own play-select cards in an online match's picture. The server
## works the cards (PlaySelectState) and tells this machine what to show, which
## comes a trip there and back after the press. So the cursor, the flip and the
## pick are shown here at the press, from the same buttons as were sent, and the
## server's word of them is not shown again.
##
## The server's word still counts: an answer that does not come in time puts
## the cards back as it last had them. A change of tab waits for the server
## (the cards of the other tabs are not here).

## Ticks the cards are up before a press counts (PlaySelectState.INPUT_LOCK).
const LOCK_TICKS: int = 16
## Ticks the server has to answer what was shown here.
const ANSWER_TICKS: int = 45

var view: NetView
## Cursor moves, flips and picks shown here at the press.
var shown_ahead: int = 0

var _pad: PadInput
var _tick: int = -1
var _now: int = 0
## Cards on the open tab (0: none up), the cursor as shown here and as the
## server last had it, and the ticks the cards have been up.
var _count: int = 0
var _cursor: int = 0
var _server_cursor: int = 0
var _up: int = 0
var _flipped: bool = false
var _ready: bool = false
## For each cursor move shown here, the tick by which the server must have
## answered; and the same for a pick (-1: none waited for).
var _waits: Array[int] = []
var _ready_wait: int = -1


## Once a tick, after this tick's buttons were sent.
func tick(game: Game, client: NetClient) -> void:
	_now += 1
	if client == null or client.tick == _tick or not client.moves.has(client.tick):
		return
	_tick = client.tick
	if _pad == null:
		_pad = PadInput.new()
		_pad.remote = true
	var held: Dictionary[StringName, Vector2] = client.moves[_tick][1]
	_pad.push(held)
	var hud: HUD = game.hud
	if _count <= 0 or not hud.play_select.visible:
		return
	_up += 1
	if not _waits.is_empty() and _waits[0] < _now:
		_waits.clear()
		_cursor = _server_cursor
		hud.set_play_cursor(_cursor, 0)
	if _ready_wait >= 0 and _ready_wait < _now:
		_ready_wait = -1
		_ready = false
		hud.set_play_ready(false, 0)
	if _ready or _up < LOCK_TICKS:
		return
	if _pad.just_pressed(&"page_next") or _pad.just_pressed(&"page_prev"):
		return
	var to: int = _cursor
	if _pad.just_pressed(&"move_right"):
		to = _step(1, 0)
	elif _pad.just_pressed(&"move_left"):
		to = _step(-1, 0)
	elif _pad.just_pressed(&"move_down"):
		to = _step(0, 1)
	elif _pad.just_pressed(&"move_up"):
		to = _step(0, -1)
	if to != _cursor:
		_cursor = to
		hud.set_play_cursor(_cursor, 0)
		_sound(game, &"ui_move")
		_waits.append(_now + ANSWER_TICKS)
	if _pad.just_pressed(&"flip_play"):
		_flipped = not _flipped
		hud.set_play_flipped(_flipped, 0)
		_sound(game, &"ui_flip")
	if _pad.just_pressed(&"confirm"):
		_ready = true
		_ready_wait = _now + ANSWER_TICKS
		hud.set_play_ready(true, 0)
		_sound(game, &"ui_confirm")


## The server says `method` was called on the HUD with `args`. True when that
## is shown here already and is not to be done again.
func heard(game: Game, method: StringName, args: Array) -> bool:
	match method:
		&"show_play_select":
			var count: int = 0
			if args.size() > 3 and typeof(args[3]) == TYPE_ARRAY and (args[3] as Array).size() == 2 and typeof(args[3][1]) == TYPE_ARRAY:
				count = (args[3][1] as Array).size()
			if _count <= 0:
				_up = 0
			_count = count
			_cursor = 0
			_server_cursor = 0
			_waits.clear()
			_ready = false
			_ready_wait = -1
		&"hide_play_select":
			_count = 0
			_waits.clear()
			_ready_wait = -1
		&"set_play_cursor":
			if args.is_empty():
				return false
			_server_cursor = int(args[0])
			if not _waits.is_empty():
				_waits.pop_front()
				if _waits.is_empty() and _cursor != _server_cursor:
					_cursor = _server_cursor
					game.hud.set_play_cursor(_cursor, 0)
				return true
			_cursor = _server_cursor
		&"set_play_flipped":
			if not args.is_empty():
				_flipped = bool(args[0])
		&"set_play_ready":
			if not args.is_empty():
				_ready = bool(args[0])
				_ready_wait = -1
	return false


func _sound(game: Game, sound: StringName) -> void:
	shown_ahead += 1
	game.audio.play(sound)
	view.swallow(NetEvents.Part.AUDIO, &"net_start", sound)


## As PlaySelectState._step: one card across or down the grid, wrapping.
func _step(dx: int, dy: int) -> int:
	var columns: int = HUD.GRID_COLUMNS
	@warning_ignore("integer_division")
	var rows: int = (_count + columns - 1) / columns
	@warning_ignore("integer_division")
	var row: int = posmod(_cursor / columns + dy, rows)
	var column: int = posmod(_cursor % columns + dx, columns)
	var to: int = row * columns + column
	return to if to < _count else _cursor
