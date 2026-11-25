class_name NetHost
extends Node
## What the hosting service (Edgegap) tells a server it starts for a match, and
## the way to tell it that the server is done.
##
## The host starts the container with these in its environment:
##   ARBITRIUM_REQUEST_ID      set at all: this server was started by the host
##   ARBITRIUM_PORTS_MAPPING   {"ports": {"<name>": {"internal": 24642, "external": 31504, ...}}}
##                             the port to listen on is the internal one
##   MM_TICKET_IDS             ["<ticket>", "<ticket>"]: the matchmaker's tickets
##                             of the people of this match. A person's ticket is
##                             their pass (NetProtocol's HELLO)
##   ARBITRIUM_DELETE_URL, ARBITRIUM_DELETE_TOKEN
##                             called when the match is over, and the host takes
##                             the server down (it would run on, and cost, else)

## Seconds a server waits for both people before it gives up.
const WAIT_SECONDS: float = 90.0
## Seconds to wait for the host's answer to "done" before quitting anyway.
const STOP_WAIT: float = 8.0

var passes: PackedStringArray = PackedStringArray()
## The port to listen on, 0 when the host did not say.
var port: int = 0

var _stop_url: String = ""
var _stop_token: String = ""


## Null on a machine that is not the host's.
static func from_environment() -> NetHost:
	if OS.get_environment("ARBITRIUM_REQUEST_ID") == "":
		return null
	var host: NetHost = NetHost.new()
	host.read(OS.get_environment("MM_TICKET_IDS"), OS.get_environment("ARBITRIUM_PORTS_MAPPING"))
	host._stop_url = OS.get_environment("ARBITRIUM_DELETE_URL")
	host._stop_token = OS.get_environment("ARBITRIUM_DELETE_TOKEN")
	return host


## Takes the tickets and the port out of what the host wrote (both JSON).
func read(tickets: String, ports: String) -> void:
	passes = PackedStringArray()
	var ids: Variant = JSON.parse_string(tickets) if tickets != "" else null
	if typeof(ids) == TYPE_ARRAY:
		for id: Variant in ids:
			if typeof(id) == TYPE_STRING and id != "":
				passes.append(id)
	port = 0
	var mapping: Variant = JSON.parse_string(ports) if ports != "" else null
	if typeof(mapping) == TYPE_DICTIONARY and typeof((mapping as Dictionary).get("ports")) == TYPE_DICTIONARY:
		for entry: Variant in ((mapping as Dictionary)["ports"] as Dictionary).values():
			if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("protocol", "")).to_upper() == "UDP":
				port = int((entry as Dictionary).get("internal", 0))
				break


## Tells the host this server is done. Comes back when it has answered, or
## after STOP_WAIT seconds.
func stop() -> void:
	if _stop_url == "":
		return
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = STOP_WAIT
	add_child(request)
	if request.request(_stop_url, PackedStringArray(["authorization: %s" % _stop_token]), HTTPClient.METHOD_DELETE) != OK:
		push_warning("NetHost: could not ask the host to stop this server")
		return
	var answer: Array = await request.request_completed
	print("NetHost: told the host this server is done (%s)" % answer[1])
