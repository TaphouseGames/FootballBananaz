class_name NetEvents
extends RefCounted
## Things that happen once and that the picture needs to hear of: a knock-down,
## a jolt, a spike. On the server the places that start them note them here;
## NetServer sends each tick's notes on, and NetView does the same thing to the
## same player on the person's machine. (What lasts, like where a player is and
## what he is doing, goes in the state instead: see NetState.)

## What of a player the call is made on.
enum Part { PLAYER, ANIMATOR, FALL }

## What may be called on each part when it comes in over the network.
const ALLOWED: Dictionary[int, Array] = {
	Part.PLAYER: [&"flash", &"net_reset"],
	Part.ANIMATOR: [&"jolt", &"plant", &"motion_kick", &"audible_call", &"route_juke", &"faked_out", &"spike", &"toss"],
	Part.FALL: [&"start", &"start_dive_landing", &"start_splat"],
}

## Only the server notes anything.
static var recording: bool = false
static var _notes: Array = []


## `method` was called with `args` on `part` of `player`.
static func note(player: Player, part: Part, method: StringName, args: Array) -> void:
	if not recording or player.play == null:
		return
	var who: int = player.play.players.find(player)
	if who >= 0:
		_notes.append([who, part, method, args])


## What was noted since the last time, oldest first.
static func take() -> Array:
	var notes: Array = _notes
	_notes = []
	return notes


## Does on this machine what a note says was done on the server.
static func replay(game: Game, entry: Variant) -> void:
	if typeof(entry) != TYPE_ARRAY:
		return
	var parts: Array = entry
	if parts.size() != 4 or typeof(parts[0]) != TYPE_INT or typeof(parts[1]) != TYPE_INT or typeof(parts[3]) != TYPE_ARRAY:
		return
	var players: Array[Player] = game.play_controller.players
	var who: int = parts[0]
	var part: int = parts[1]
	if who < 0 or who >= players.size() or not ALLOWED.has(part):
		return
	var method: StringName = StringName(str(parts[2]))
	if not ALLOWED[part].has(method):
		return
	var player: Player = players[who]
	var target: Object = player
	if part == Part.ANIMATOR:
		target = player.animator
	elif part == Part.FALL:
		target = player.fall
	if target != null:
		target.callv(method, parts[3])
