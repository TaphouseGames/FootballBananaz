class_name NetInputQueue
extends RefCounted
## One person's buttons as they come in over the network, handed to the game a
## tick at a time. The server has one for each seat.
##
## Packets come late, twice, out of order or not at all. Each carries the last
## few ticks, so one lost packet loses nothing. With no tick to hand out, the
## last one stands (what was held stays held, and nothing is pressed again);
## with too many waiting, the oldest are stepped over, and what was pressed in
## them is pressed in the next.
##
## Every tick that waits here is a tick the person's buttons are late. So when
## there has been one to spare on every tick for a while, one is stepped over:
## on a steady line none wait, and on an uneven one as many as it takes.

## Ticks that may wait. More than this and the person would be playing that far
## behind for the rest of the match.
const MAX_WAITING: int = 4
## Ticks in a row with one to spare before one is stepped over.
const SPARE_TICKS: int = 90
## A tick with none to hand out soon after that was done says the line is too
## uneven for it: the wait before the next time doubles, up to this, and comes
## down again once it has gone well.
const SPARE_TICKS_MAX: int = 1440

## The ticks that have come in and not been handed out.
var _waiting: Dictionary[int, PackedFloat32Array] = {}
## The tick to hand out next.
var _next: int = 0
var _last: PackedFloat32Array = PackedFloat32Array()
## Ticks handed out twice for want of a new one, and ticks stepped over.
var held: int = 0
var skipped: int = 0
## The tick of the buttons handed out last, -1 before the first.
var taken: int = -1
## The fewest that were left waiting on a tick lately, and for how many ticks
## that has been counted.
var _spare: int = MAX_WAITING
var _spare_ticks: int = 0
var _spare_window: int = SPARE_TICKS
var _since_spared: int = 1 << 30


func add(tick: int, frame: PackedFloat32Array) -> void:
	if tick >= _next and not _waiting.has(tick):
		_waiting[tick] = frame


## The buttons for this server tick. Empty before the first have come in.
func take() -> PackedFloat32Array:
	if _waiting.is_empty():
		if not _last.is_empty():
			held += 1
		_spare = 0
		if _since_spared < _spare_window:
			_spare_window = mini(_spare_window * 2, SPARE_TICKS_MAX)
			_since_spared = 1 << 30
		return _last
	var oldest: int = _waiting.keys().min()
	var newest: int = _waiting.keys().max()
	# A tick that never came, with later ones here: it will not come now.
	_next = maxi(_next, oldest)
	var frame: PackedFloat32Array = _take_next()
	_spare = mini(_spare, _waiting.size())
	_spare_ticks += 1
	var one_over: bool = false
	_since_spared = mini(_since_spared + 1, 1 << 30)
	if _spare_ticks >= _spare_window:
		one_over = _spare >= 1
		_spare = MAX_WAITING
		_spare_ticks = 0
		if one_over:
			if _since_spared < (1 << 30):
				_spare_window = maxi(_spare_window / 2, SPARE_TICKS)
			_since_spared = 0
	while not _waiting.is_empty() and (newest - _next >= MAX_WAITING or one_over):
		one_over = false
		var over: PackedFloat32Array = frame
		_next = _first_waiting()
		frame = _take_next()
		skipped += 1
		# The buttons of the tick stepped over count as pressed in this one. The
		# stick and the camera at the end are this one's own.
		for at: int in frame.size() - NetProtocol.VIEW_FLOATS:
			frame[at] = maxf(frame[at], over[at])
	_last = frame
	taken = _next - 1
	return frame


func _take_next() -> PackedFloat32Array:
	var frame: PackedFloat32Array = _waiting[_next]
	_waiting.erase(_next)
	_next += 1
	return frame


func _first_waiting() -> int:
	return _waiting.keys().min()
