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

## Ticks that may wait. More than this and the person would be playing that far
## behind for the rest of the match.
const MAX_WAITING: int = 4

## The ticks that have come in and not been handed out.
var _waiting: Dictionary[int, PackedFloat32Array] = {}
## The tick to hand out next.
var _next: int = 0
var _last: PackedFloat32Array = PackedFloat32Array()
## Ticks handed out twice for want of a new one, and ticks stepped over.
var held: int = 0
var skipped: int = 0


func add(tick: int, frame: PackedFloat32Array) -> void:
	if tick >= _next and not _waiting.has(tick):
		_waiting[tick] = frame


## The buttons for this server tick. Empty before the first have come in.
func take() -> PackedFloat32Array:
	if _waiting.is_empty():
		if not _last.is_empty():
			held += 1
		return _last
	var oldest: int = _waiting.keys().min()
	var newest: int = _waiting.keys().max()
	# A tick that never came, with later ones here: it will not come now.
	_next = maxi(_next, oldest)
	var frame: PackedFloat32Array = _take_next()
	while newest - _next >= MAX_WAITING:
		var over: PackedFloat32Array = frame
		_next = _first_waiting()
		frame = _take_next()
		skipped += 1
		# The buttons of the tick stepped over count as pressed in this one. The
		# stick and the camera at the end are this one's own.
		for at: int in frame.size() - NetProtocol.VIEW_FLOATS:
			frame[at] = maxf(frame[at], over[at])
	_last = frame
	return frame


func _take_next() -> PackedFloat32Array:
	var frame: PackedFloat32Array = _waiting[_next]
	_waiting.erase(_next)
	_next += 1
	return frame


func _first_waiting() -> int:
	return _waiting.keys().min()
