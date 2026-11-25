extends SceneTree
## Measures what a state costs on the line, and what other ways of packing it
## would: a server and two ends with random buttons in this one program, and
## every tick's state packed each way.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/net_size_probe.gd [-- ticks=3000]

const PORT: int = 24745

var _server: NetServer
var _clients: Array[NetClient] = []
var _pads: Array[PadInput] = []
var _held: Array[Dictionary] = [{}, {}]
var _ticks: int = 3000
var _tick: int = 0
var _joined: bool = false
var _listening: bool = false
var _counted: int = 0
var _sums: Dictionary[String, int] = {}
var _before: Array = []
var _far: Array[Array] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("ticks="):
			_ticks = int(arg.trim_prefix("ticks="))
	_server = NetServer.new()
	_server.port = PORT
	_server.quit_when_done = false
	_server.intro = false
	root.add_child(_server)
	for i: int in 2:
		var client: NetClient = NetClient.new()
		var pad: PadInput = PadInput.new()
		pad.remote = true
		client.pad = pad
		root.add_child(client)
		_pads.append(pad)
		_clients.append(client)


func _process(_delta: float) -> bool:
	if not _listening:
		_listening = true
		physics_frame.connect(_on_tick)
	return false


func _on_tick() -> void:
	if not _joined:
		_joined = true
		for client: NetClient in _clients:
			client.join("127.0.0.1", PORT)
	for i: int in 2:
		for plain: StringName in PadInput.plain_actions():
			if randf() < 0.12:
				if _held[i].has(plain):
					_held[i].erase(plain)
				else:
					_held[i][plain] = true
		var frame: Dictionary[StringName, Vector2] = {}
		for plain: StringName in _held[i]:
			frame[plain] = Vector2.ONE
		_pads[i].push(frame)
	if _server.game == null:
		return
	_tick += 1
	var state: Array = NetState.pack(_server.game, PackedInt32Array([_tick, _tick]))
	_add("as now", _squeezed(state))
	# Against the state before, and against the one eight ticks back (what a
	# person's machine is sure to have): only what differs, as bits.
	if not _before.is_empty():
		_add("against the tick before", _squeezed(_against(state, _before)))
	_far.append(state)
	if _far.size() > 8:
		_add("against 8 ticks before", _squeezed(_against(state, _far.pop_front())))
	_before = state
	_counted += 1
	if _tick >= _ticks:
		for key: String in _sums:
			print("%-26s %5d bytes a state, %5.1f kB a second" % [key, _sums[key] / _counted, _sums[key] / float(_counted) * 60.0 / 1000.0])
		quit(0)


func _add(key: String, bytes: int) -> void:
	_sums[key] = _sums.get(key, 0) + bytes


func _squeezed(state: Array) -> int:
	return var_to_bytes(state).compress(FileAccess.COMPRESSION_ZSTD).size()


## `state` with each table of floats as its bytes, and of those only what is
## not the same as in `base`.
func _against(state: Array, base: Array) -> Array:
	var out: Array = []
	for at: int in 4:
		var now: PackedByteArray = (state[at] as PackedFloat32Array).to_byte_array()
		var was: PackedByteArray = (base[at] as PackedFloat32Array).to_byte_array()
		if now.size() == was.size():
			for i: int in now.size():
				now[i] = now[i] ^ was[i]
		out.append(now)
	out.append(state[4])
	return out
