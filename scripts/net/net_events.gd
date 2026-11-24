class_name NetEvents
extends RefCounted
## Things that happen once and that a person's machine needs to hear of: a
## knock-down, a jolt, a sound starting, a banner going up, a shake of the
## gamepad. On the server the functions that do them note the call here;
## NetServer sends each tick's notes on, and NetView makes the same call on the
## person's machine. (What lasts, like where a player is and what he is doing,
## goes in the state instead: see NetState.)
##
## A function tells of itself in its first lines:
##     if NetEvents.recording:
##         NetEvents.tell(NetEvents.Part.HUD, &"show_banner", [text, sub_text])
## and its name goes in ALLOWED. Players and teams among the arguments travel
## as their number and are the same player and team on the other side.

## What the call is made on: a player or something of his (note()), or one of
## the match's own parts (tell()).
enum Part { PLAYER, ANIMATOR, FALL, AUDIO, HUD, RUMBLE, GAME, CAMERA, FX, FIELD, STADIUM }

## What may be called on each part when it comes in over the network.
const ALLOWED: Dictionary[int, Array] = {
	Part.PLAYER: [&"flash", &"net_reset", &"set_pass_icon", &"set_dance_prompt"],
	Part.ANIMATOR: [&"jolt", &"plant", &"motion_kick", &"audible_call", &"route_juke", &"faked_out", &"spike", &"toss"],
	Part.FALL: [&"start", &"start_dive_landing", &"start_splat"],
	Part.AUDIO: [&"net_start", &"net_hush"],
	Part.HUD: [&"show_banner", &"hide_banner", &"set_hint", &"set_countdown", &"hide_countdown"],
	Part.RUMBLE: [&"play", &"play_mine", &"play_for", &"play_team", &"hold_drag"],
	Part.GAME: [&"impact"],
	Part.CAMERA: [&"shot", &"end_shot", &"snap_to", &"punch"],
	Part.FX: [&"blood_burst", &"daze_impact", &"dust_puff"],
	Part.FIELD: [&"set_markers"],
	Part.STADIUM: [&"react"],
}
## How a player and a team among the arguments are marked on the way.
const PLAYER_MARK: String = "@p"
const TEAM_MARK: String = "@t"

## Only the server notes anything.
static var recording: bool = false
## The server's match: where a player's and a team's number come from.
static var game: Game
static var _notes: Array = []
## The last call noted of each group, so the same one is not sent tick after tick.
static var _last: Dictionary[StringName, Array] = {}


## `method` was called with `args` on `part` of `player`.
static func note(player: Player, part: Part, method: StringName, args: Array) -> void:
	if not recording or player.play == null:
		return
	var who: int = player.play.players.find(player)
	if who >= 0:
		_notes.append([who, part, method, _marked(args)])


## `method` was called with `args` on `part` of the match. With a `group`, a
## call that is the same as the last one of its group is not noted again
## (a countdown set to the same second every tick).
static func tell(part: Part, method: StringName, args: Array, group: StringName = &"") -> void:
	if not recording:
		return
	var marked: Array = _marked(args)
	if group != &"":
		var call: Array = [method, marked]
		if _last.get(group, []) == call:
			return
		_last[group] = call
	_notes.append([-1, part, method, marked])


## What was noted since the last time, oldest first.
static func take() -> Array:
	var notes: Array = _notes
	_notes = []
	return notes


## Forgets everything: a new match.
static func clear() -> void:
	_notes = []
	_last.clear()


## Makes on this machine the call a note says was made on the server.
static func replay(here: Game, entry: Variant) -> void:
	if typeof(entry) != TYPE_ARRAY:
		return
	var parts: Array = entry
	if parts.size() != 4 or typeof(parts[0]) != TYPE_INT or typeof(parts[1]) != TYPE_INT or typeof(parts[3]) != TYPE_ARRAY:
		return
	var players: Array[Player] = here.play_controller.players
	var who: int = parts[0]
	var part: int = parts[1]
	if not ALLOWED.has(part) or who >= players.size():
		return
	var method: StringName = StringName(str(parts[2]))
	if not ALLOWED[part].has(method):
		return
	var target: Object = null
	match part:
		Part.PLAYER:
			target = players[who] if who >= 0 else null
		Part.ANIMATOR:
			target = players[who].animator if who >= 0 else null
		Part.FALL:
			target = players[who].fall if who >= 0 else null
		Part.AUDIO:
			target = here.audio
		Part.HUD:
			target = here.hud
		Part.RUMBLE:
			target = here.rumble
		Part.GAME:
			target = here
		Part.CAMERA:
			target = here.camera_rig
		Part.FX:
			target = here.field.fx
		Part.FIELD:
			target = here.field
		Part.STADIUM:
			target = here.field.stadium
	if target != null:
		target.callv(method, _unmarked(parts[3], here))


## `args` with every player and team in it as a mark and a number.
static func _marked(args: Array) -> Array:
	var marked: Array = []
	for value: Variant in args:
		if value is Player:
			var player: Player = value
			marked.append([PLAYER_MARK, player.play.players.find(player) if player.play != null else -1])
		elif value is Team:
			marked.append([TEAM_MARK, 0 if game != null and value == game.home else 1])
		else:
			marked.append(value)
	return marked


static func _unmarked(args: Array, here: Game) -> Array:
	var plain: Array = []
	var players: Array[Player] = here.play_controller.players
	for value: Variant in args:
		if typeof(value) == TYPE_ARRAY and (value as Array).size() == 2 and typeof(value[0]) == TYPE_STRING and typeof(value[1]) == TYPE_INT:
			var number: int = value[1]
			if value[0] == PLAYER_MARK:
				plain.append(players[number] if number >= 0 and number < players.size() else null)
				continue
			if value[0] == TEAM_MARK:
				plain.append(here.home if number == 0 else here.away)
				continue
		plain.append(value)
	return plain
