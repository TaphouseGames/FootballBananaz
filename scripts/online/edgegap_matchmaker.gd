class_name EdgegapMatchmaker
extends Matchmaker
## Edgegap's matchmaker, over its web API:
##   POST   <url>/tickets        {"profile": ..., "attributes": {}}  -> {"id": ..., "status": ...}
##   GET    <url>/tickets/<id>   -> {"status": "SEARCHING" | "MATCH_FOUND" | "TEAM_FOUND" |
##                                   "HOST_ASSIGNED" | "CANCELLED", "assignment": null or
##                                   {"fqdn", "public_ip", "ports": {"<name>": {"external", "protocol", ...}}}}
##   DELETE <url>/tickets/<id>
## each with the header "Authorization: <token>". The ticket is asked after
## every POLL_SECONDS; with a host assigned, its address, the outside number of
## its UDP port and the ticket's id (the pass, see NetHost) are the match.
## A ticket runs out after some minutes (the matchmaker's configuration says
## how many): a new one is made, and the search goes on.

const POLL_SECONDS: float = 2.0
## A request that is not answered in this many seconds has failed.
const PATIENCE: float = 15.0
## Failed asks in a row before the search is given up.
const MAX_MISSES: int = 4

var url: String = ""
var token: String = ""
var profile: String = ""

var ticket: String = ""
var _searching: bool = false
## Goes up with every search and every cancel: an answer to an older one is
## not acted on.
var _round: int = 0
var _misses: int = 0


func search() -> void:
	_round += 1
	_searching = true
	_misses = 0
	ticket = ""
	_run(_round)


func cancel() -> void:
	_round += 1
	_searching = false
	if ticket != "":
		# Not waited for: the ticket runs out by itself if this does not get there.
		_ask(HTTPClient.METHOD_DELETE, "/tickets/%s" % ticket, "")
		ticket = ""


func _run(the_round: int) -> void:
	while _searching and the_round == _round:
		if ticket == "":
			var made: Array = await _ask(HTTPClient.METHOD_POST, "/tickets", JSON.stringify({"profile": profile, "attributes": {}}))
			if the_round != _round:
				# Cancelled meanwhile: the ticket that came of it is not wanted.
				if _is_ok(made) and typeof(made[1].get("id")) == TYPE_STRING:
					_ask(HTTPClient.METHOD_DELETE, "/tickets/%s" % made[1]["id"], "")
				return
			if not _is_ok(made) or typeof(made[1].get("id")) != TYPE_STRING:
				_give_up(_why(made))
				return
			ticket = made[1]["id"]
		await get_tree().create_timer(POLL_SECONDS).timeout
		if the_round != _round:
			return
		var answer: Array = await _ask(HTTPClient.METHOD_GET, "/tickets/%s" % ticket, "")
		if the_round != _round:
			return
		if answer[0] == 404:
			# Run out: another one.
			ticket = ""
			continue
		if not _is_ok(answer):
			_misses += 1
			if _misses >= MAX_MISSES:
				_give_up(_why(answer))
				return
			continue
		_misses = 0
		var status: String = str(answer[1].get("status", ""))
		if status == "CANCELLED":
			ticket = ""
			continue
		var place: Array = server_of(answer[1])
		if status == "HOST_ASSIGNED" and not place.is_empty():
			_searching = false
			var match_pass: String = ticket
			ticket = ""
			found.emit(place[0], place[1], match_pass)
			return


## [address, port] of the server in what the matchmaker says of a ticket, or
## nothing when it has none (yet).
static func server_of(body: Dictionary) -> Array:
	if typeof(body.get("assignment")) != TYPE_DICTIONARY:
		return []
	var assignment: Dictionary = body["assignment"]
	var address: String = str(assignment.get("public_ip", ""))
	if address == "":
		address = str(assignment.get("fqdn", ""))
	if address == "" or typeof(assignment.get("ports")) != TYPE_DICTIONARY:
		return []
	for entry: Variant in (assignment["ports"] as Dictionary).values():
		if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("protocol", "")).to_upper() == "UDP":
			var port: int = int((entry as Dictionary).get("external", 0))
			if port > 0:
				return [address, port]
	return []


func _give_up(reason: String) -> void:
	_searching = false
	ticket = ""
	failed.emit(reason)


func _is_ok(answer: Array) -> bool:
	return answer[0] >= 200 and answer[0] < 300 and typeof(answer[1]) == TYPE_DICTIONARY


## What to tell the person about an ask that failed.
func _why(answer: Array) -> String:
	if answer[0] == 0:
		return "Cannot reach the matchmaker. Check your internet connection."
	if answer[0] == 401 or answer[0] == 403:
		return "The matchmaker does not know this version of the game."
	return "The matchmaker is not answering (%d). Try again in a while." % answer[0]


## One ask of the matchmaker: [the answer's code (0: none came), its body as a
## Dictionary (or null)].
func _ask(method: HTTPClient.Method, path: String, body: String) -> Array:
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = PATIENCE
	add_child(request)
	var headers: PackedStringArray = ["Authorization: %s" % token, "Content-Type: application/json"]
	if request.request(url + path, headers, method, body) != OK:
		request.queue_free()
		return [0, null]
	var answer: Array = await request.request_completed
	request.queue_free()
	if answer[0] != HTTPRequest.RESULT_SUCCESS:
		return [0, null]
	var text: String = (answer[3] as PackedByteArray).get_string_from_utf8()
	return [answer[1], JSON.parse_string(text) if text != "" else null]
