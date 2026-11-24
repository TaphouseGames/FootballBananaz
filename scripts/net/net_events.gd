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
## and its name goes in ALLOWED. Players, teams and plays among the arguments
## travel as their number and are the same ones on the other side.
##
## A note is for everyone unless it says a seat: by `seat` in the call, or
## because `audience` is set while one person's menus are being worked through
## (PlaySelectState, PreSnapState). What a person picks, calls and is shown at
## the line never goes to the other one.

## What the call is made on: a player or something of his (note()), or one of
## the match's own parts (tell()).
enum Part { PLAYER, ANIMATOR, FALL, AUDIO, HUD, RUMBLE, GAME, CAMERA, FX, FIELD, STADIUM, ART }

## What may be called on each part when it comes in over the network.
const ALLOWED: Dictionary[int, Array] = {
	Part.PLAYER: [&"flash", &"net_reset", &"set_pass_icon", &"set_dance_prompt"],
	Part.ANIMATOR: [&"jolt", &"plant", &"motion_kick", &"audible_call", &"route_juke", &"faked_out", &"spike", &"toss"],
	Part.FALL: [&"start", &"start_dive_landing", &"start_splat"],
	Part.AUDIO: [&"net_start", &"net_hush"],
	Part.HUD: [
		&"show_banner", &"hide_banner", &"set_hint", &"set_countdown", &"hide_countdown",
		&"show_play_select", &"set_play_flipped", &"set_play_cursor", &"set_play_hint", &"set_play_ready",
		&"hide_play_select", &"show_audible", &"hide_audible", &"show_hot_routes", &"light_hot_route",
		&"hide_hot_routes",
	],
	Part.RUMBLE: [&"play", &"play_mine", &"play_for", &"play_team", &"hold_drag"],
	Part.GAME: [&"impact"],
	Part.CAMERA: [&"shot", &"end_shot", &"snap_to", &"punch"],
	Part.FX: [&"blood_burst", &"daze_impact", &"dust_puff"],
	Part.FIELD: [&"set_markers"],
	Part.STADIUM: [&"react"],
	Part.ART: [&"net_draw"],
}
## For everyone; and in a call, "whoever `audience` says".
const EVERYONE: int = -1
const BY_AUDIENCE: int = -2
## How a player and a team among the arguments are marked on the way.
const PLAYER_MARK: String = "@p"
const TEAM_MARK: String = "@t"
const OFFENSE_PLAY_MARK: String = "@o"
const DEFENSE_PLAY_MARK: String = "@d"
## A list of plays: [mark, [each play's own mark and number]].
const PLAYS_MARK: String = "@plays"

## Only the server notes anything.
static var recording: bool = false
## The server's match: where a player's and a team's number come from.
static var game: Game
## The seat that what is noted now is for, or EVERYONE.
static var audience: int = EVERYONE
## Each note with the seat it is for: [seat, note].
static var _notes: Array = []
## The last call noted of each group, so the same one is not sent tick after tick.
static var _last: Dictionary[String, Array] = {}


## `method` was called with `args` on `part` of `player`.
static func note(player: Player, part: Part, method: StringName, args: Array, seat: int = BY_AUDIENCE) -> void:
	if not recording or player.play == null:
		return
	var who: int = player.play.players.find(player)
	if who >= 0:
		_notes.append([audience if seat == BY_AUDIENCE else seat, [who, part, method, _marked(args)]])


## `method` was called with `args` on `part` of the match. With a `group`, a
## call that is the same as the last one of its group is not noted again
## (a countdown set to the same second every tick).
static func tell(part: Part, method: StringName, args: Array, group: StringName = &"", seat: int = BY_AUDIENCE) -> void:
	if not recording:
		return
	var to: int = audience if seat == BY_AUDIENCE else seat
	var marked: Array = _marked(args)
	if group != &"":
		var call: Array = [method, marked]
		var key: String = "%s/%d" % [group, to]
		if _last.get(key, []) == call:
			return
		_last[key] = call
	_notes.append([to, [-1, part, method, marked]])


## What was noted since the last time for each of `seats` people, oldest first:
## what is for everyone and what is for that one.
static func take(seats: int) -> Array[Array]:
	var lists: Array[Array] = []
	for seat: int in seats:
		lists.append([])
	for entry: Array in _notes:
		for seat: int in seats:
			if entry[0] == EVERYONE or entry[0] == seat:
				lists[seat].append(entry[1])
	_notes = []
	return lists


## Forgets everything: a new match.
static func clear() -> void:
	_notes = []
	_last.clear()
	audience = EVERYONE


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
		Part.ART:
			target = here.play_art
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
		elif value is OffensePlay or value is DefensePlay:
			marked.append(_play_mark(value))
		elif typeof(value) == TYPE_ARRAY and not (value as Array).is_empty() and (value[0] is OffensePlay or value[0] is DefensePlay):
			var plays: Array = []
			for play: Variant in value as Array:
				plays.append(_play_mark(play))
			marked.append([PLAYS_MARK, plays])
		else:
			marked.append(value)
	return marked


static func _play_mark(play: Variant) -> Array:
	if game != null and play is OffensePlay:
		return [OFFENSE_PLAY_MARK, game.offense_playbook.plays.find(play)]
	if game != null and play is DefensePlay:
		return [DEFENSE_PLAY_MARK, game.defense_playbook.plays.find(play)]
	return [OFFENSE_PLAY_MARK, -1]


## The play a mark stands for on this machine, or null.
static func _play_of(mark: Variant, here: Game) -> Resource:
	if typeof(mark) != TYPE_ARRAY or (mark as Array).size() != 2 or typeof(mark[1]) != TYPE_INT:
		return null
	var number: int = mark[1]
	if mark[0] == OFFENSE_PLAY_MARK and number >= 0 and number < here.offense_playbook.plays.size():
		return here.offense_playbook.plays[number]
	if mark[0] == DEFENSE_PLAY_MARK and number >= 0 and number < here.defense_playbook.plays.size():
		return here.defense_playbook.plays[number]
	return null


static func _unmarked(args: Array, here: Game) -> Array:
	var plain: Array = []
	var players: Array[Player] = here.play_controller.players
	for value: Variant in args:
		if typeof(value) == TYPE_ARRAY and (value as Array).size() == 2 and typeof(value[0]) == TYPE_STRING:
			if value[0] == PLAYS_MARK and typeof(value[1]) == TYPE_ARRAY:
				var plays: Array[Resource] = []
				for mark: Variant in value[1] as Array:
					var play: Resource = _play_of(mark, here)
					if play != null:
						plays.append(play)
				plain.append(plays)
				continue
			if typeof(value[1]) == TYPE_INT:
				var number: int = value[1]
				if value[0] == PLAYER_MARK:
					plain.append(players[number] if number >= 0 and number < players.size() else null)
					continue
				if value[0] == TEAM_MARK:
					plain.append(here.home if number == 0 else here.away)
					continue
				if value[0] == OFFENSE_PLAY_MARK or value[0] == DEFENSE_PLAY_MARK:
					plain.append(_play_of(value, here))
					continue
		plain.append(value)
	return plain
