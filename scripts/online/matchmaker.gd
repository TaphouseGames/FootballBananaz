class_name Matchmaker
extends Node
## Finds a person an opponent and a server for the two of them. This is all the
## game knows of whoever does that: the service behind it can change.
##
## search() starts looking; then one of `found` and `failed` comes, unless
## cancel() was called first.
##
## Which one is used, and where it is, is read by make() from the settings
## files res://online.cfg and, over that, user://online.cfg:
##   [matchmaker]
##   url = "https://....edgegap.net"    the matchmaker's API URL
##   token = "..."                      its auth token
##   profile = "quick-1v1"              the profile of its configuration
##   [direct]
##   address = "192.168.0.20"           no matchmaker: a server that is up already
##   port = 24642
## and from the command line, over both:  -- online=<address>[:<port>]

## The server of the match, and what lets this person in there.
signal found(address: String, port: int, match_pass: String)
## It did not work out: `reason` is for the person to read.
signal failed(reason: String)

const SETTINGS: PackedStringArray = ["res://online.cfg", "user://online.cfg"]


## The matchmaker this machine is set up for, or null when it is for none.
static func make() -> Matchmaker:
	var settings: ConfigFile = ConfigFile.new()
	for path: String in SETTINGS:
		var more: ConfigFile = ConfigFile.new()
		if more.load(path) == OK:
			for section: String in more.get_sections():
				for key: String in more.get_section_keys(section):
					settings.set_value(section, key, more.get_value(section, key))
	var address: String = str(settings.get_value("direct", "address", ""))
	var port: int = int(settings.get_value("direct", "port", NetProtocol.DEFAULT_PORT))
	var forced: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("online="):
			var parts: PackedStringArray = arg.trim_prefix("online=").split(":")
			address = parts[0]
			port = int(parts[1]) if parts.size() > 1 else NetProtocol.DEFAULT_PORT
			forced = true
	var url: String = str(settings.get_value("matchmaker", "url", "")).strip_edges().trim_suffix("/")
	if url != "" and not forced:
		var edgegap: EdgegapMatchmaker = EdgegapMatchmaker.new()
		edgegap.url = url
		edgegap.token = str(settings.get_value("matchmaker", "token", ""))
		edgegap.profile = str(settings.get_value("matchmaker", "profile", "quick-1v1"))
		return edgegap
	if address != "":
		var direct: DirectMatchmaker = DirectMatchmaker.new()
		direct.address = address
		direct.port = port
		return direct
	return null


## Starts looking for a match.
func search() -> void:
	pass


## Stops looking: nothing more comes of the search.
func cancel() -> void:
	pass
