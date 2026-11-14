extends SceneTree
## What the stadium costs: frame times of the match scene from a set of camera
## stops (both ends, midfield, each way, a look across at each sideline), with
## the stadium on and off. Needs a window (no --headless), since headless does
## not render. V-sync is switched off for the run.
##
## Run:  godot --path . --resolution 1280x720 --script res://tests/stadium_perf.gd -- [stadium=on|off|both] [seconds=3]

## Seconds at each stop before measuring starts (shaders, streaming).
const SETTLE: float = 0.7

var _modes: Array[bool] = [false, true]
var _seconds: float = 3.0
var _game: Game
var _stops: Array = []
var _stop: int = -1
var _stop_start: int = 0
var _times: PackedFloat32Array = PackedFloat32Array()
var _last: int = 0
var _all: PackedFloat32Array = PackedFloat32Array()
var _results: PackedStringArray = PackedStringArray()
## The busiest frame of the run.
var _draws: int = 0
var _primitives: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "stadium=on":
			_modes = [true]
		elif arg == "stadium=off":
			_modes = [false]
		elif arg.begins_with("seconds="):
			_seconds = float(arg.trim_prefix("seconds="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_open()


func _open() -> void:
	if _game != null:
		_game.free()
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	_game.tuning = _game.tuning.duplicate() as Tuning
	_game.tuning.stadium_enabled = _modes[0]
	_game.tuning.audio_enabled = false
	root.add_child(_game)
	var t: Tuning = _game.tuning
	var length: float = t.field_length
	# [eye, aim]: the game camera's own height and distance, from behind a
	# player at several places, looking each way, then two looks across.
	_stops.clear()
	for spot: Array in [[5.0, 1.0], [50.0, 1.0], [95.0, 1.0], [95.0, -1.0], [50.0, -1.0], [5.0, -1.0]]:
		var x: float = spot[0]
		var dir: float = spot[1]
		_stops.append([Vector3(x - dir * t.camera_distance, t.camera_height, 0.0), Vector3(x + dir * t.camera_look_ahead, 0.0, 0.0)])
	_stops.append([Vector3(length * 0.5, t.camera_height, t.camera_distance), Vector3(length * 0.5, 0.0, -t.camera_look_ahead)])
	_stops.append([Vector3(length * 0.5, t.camera_height, -t.camera_distance), Vector3(length * 0.5, 0.0, t.camera_look_ahead)])
	_stop = -1
	_all.clear()
	_draws = 0
	_primitives = 0
	_next_stop()


func _next_stop() -> void:
	_stop += 1
	_times.clear()
	_stop_start = Time.get_ticks_usec()
	_last = _stop_start


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	var frame: float = float(now - _last) / 1000.0
	_last = now
	if _stop >= _stops.size():
		return _finish_mode()
	var stop: Array = _stops[_stop]
	_game.camera_rig.shot(stop[0], stop[1], true)
	var at: float = float(now - _stop_start) / 1000000.0
	if at > SETTLE:
		_times.append(frame)
		_draws = maxi(_draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_primitives = maxi(_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	if at > SETTLE + _seconds:
		_all.append_array(_times)
		_next_stop()
	return false


func _finish_mode() -> bool:
	var sorted: Array = Array(_all)
	sorted.sort()
	var total: float = 0.0
	for ms: float in sorted:
		total += ms
	var mean: float = total / maxf(float(sorted.size()), 1.0)
	var worst: float = sorted[mini(int(float(sorted.size()) * 0.99), sorted.size() - 1)]
	var size: Vector2i = root.size
	var fans: int = 0
	if _game.field.stadium != null:
		fans = _game.field.stadium.fan_count
	_results.append("stadium %s  %dx%d  mean %.2f ms (%.0f fps)  99th %.2f ms  most draw calls %d  most primitives %d  fans %d" % [
		"on " if _modes[0] else "off", size.x, size.y, mean, 1000.0 / maxf(mean, 0.001), worst,
		_draws, _primitives, fans])
	_modes.remove_at(0)
	if not _modes.is_empty():
		_open()
		return false
	for line: String in _results:
		print("PERF: ", line)
	_game.free()
	_game = null
	quit(0)
	return true
