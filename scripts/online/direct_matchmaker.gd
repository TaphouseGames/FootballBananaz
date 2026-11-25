class_name DirectMatchmaker
extends Matchmaker
## No matchmaking at all: a server that is up already, at an address this
## machine was told. For trying things out at home; whoever else goes there is
## the opponent.

var address: String = "127.0.0.1"
var port: int = NetProtocol.DEFAULT_PORT

var _searching: bool = false


func search() -> void:
	_searching = true
	# Not within the call: whoever asked is still setting itself up.
	await get_tree().create_timer(0.6).timeout
	if _searching:
		_searching = false
		found.emit(address, port, "")


func cancel() -> void:
	_searching = false
