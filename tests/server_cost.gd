extends SceneTree
## What one match costs a server: the CPU plays both teams headless, one 1/60 s
## tick a frame with nothing holding the frames back, and every frame is timed.
## Prints the time a tick takes, how many matches one core could run at 60
## ticks a second, and what that comes to per match at a host's price.
##
## The whole game runs as it does on a person's machine (animation, crowd,
## sound, HUD), so the number is an upper bound: a server build leaves those out.
## "simulation" is the physics step alone, where the rules and the CPU's
## thinking are; that is the part a server cannot leave out.
##
## Run alone (another Godot process beside it spoils the timing):
##   godot --headless --fixed-fps 60 --path . --script res://tests/server_cost.gd
## Optional user args after "--":
##   ticks=<n>    stop after n ticks instead of at the final whistle
##   price=<n>    dollars per vCPU-hour (default 0.069, Edgegap's listed rate)
##   minutes=<n>  real minutes an online match is taken to last (default 20)

const TICK_RATE: float = 60.0
## Frames left out at the start: loading and first-use hitches.
const WARM_UP: int = 120
## Buckets of 0.1 ms for the frame times, up to 50 ms.
const BUCKET_USEC: int = 100
const BUCKETS: int = 500

var _game: Game
var _max_ticks: int = 0
var _price: float = 0.069
var _match_minutes: float = 20.0

var _frames: int = 0
var _last_usec: int = 0
## When the frame's physics step began.
var _physics_start_usec: int = 0
var _total_usec: int = 0
var _worst_usec: int = 0
var _histogram: PackedInt32Array = PackedInt32Array()
var _physics_sec: float = 0.0
var _process_sec: float = 0.0
## Ticks and time with the ball live, when all sixteen brains are at work.
var _live_frames: int = 0
var _live_usec: int = 0
var _live_physics_sec: float = 0.0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("ticks="):
			_max_ticks = maxi(int(arg.trim_prefix("ticks=")), 1)
		elif arg.begins_with("price="):
			_price = float(arg.trim_prefix("price="))
		elif arg.begins_with("minutes="):
			_match_minutes = float(arg.trim_prefix("minutes="))
	_histogram.resize(BUCKETS)
	physics_frame.connect(func() -> void: _physics_start_usec = Time.get_ticks_usec())
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or _game.play_controller == null:
		return false
	var now: int = Time.get_ticks_usec()
	_frames += 1
	if _frames > WARM_UP:
		var took: int = now - _last_usec
		# This runs right after the frame's physics step and before the nodes'
		# _process: the step is what lies between its start and now. (The
		# engine's own monitors read wrong under --fixed-fps.)
		var physics: float = (now - _physics_start_usec) / 1000000.0
		_total_usec += took
		_worst_usec = maxi(_worst_usec, took)
		_histogram[mini(took / BUCKET_USEC, BUCKETS - 1)] += 1
		_physics_sec += physics
		_process_sec += took / 1000000.0 - physics
		if _game.play_controller.state_machine.current_name() == &"Live":
			_live_frames += 1
			_live_usec += took
			_live_physics_sec += physics
	_last_usec = now
	var counted: int = _frames - WARM_UP
	var over: bool = _game.play_controller.state_machine.current_name() == &"GameOver"
	if over or (_max_ticks > 0 and counted >= _max_ticks):
		_report(counted)
		quit(0)
		return true
	return false


func _report(counted: int) -> void:
	if counted <= 0:
		printerr("SERVER COST: no ticks were timed")
		return
	var tick_ms: float = _total_usec / 1000.0 / counted
	var budget_ms: float = 1000.0 / TICK_RATE
	print("ticks timed: %d (%.1f minutes of match, %d with the ball live)" % [counted, counted / TICK_RATE / 60.0, _live_frames])
	print("whole frame:  %.3f ms a tick on average, 99%% under %.1f ms, worst %.1f ms" % [tick_ms, _percentile(0.99, counted), _worst_usec / 1000.0])
	print("  of which simulation (physics step) %.3f ms, everything else in the frame %.3f ms" % [_physics_sec * 1000.0 / counted, _process_sec * 1000.0 / counted])
	if _live_frames > 0:
		print("ball live:    %.3f ms a tick, simulation %.3f ms" % [_live_usec / 1000.0 / _live_frames, _live_physics_sec * 1000.0 / _live_frames])
	print("memory: %.0f MB static" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	_print_cost("whole game as it is", tick_ms, budget_ms)
	_print_cost("simulation alone   ", _physics_sec * 1000.0 / counted, budget_ms)


## What a core can carry at 60 ticks a second, at the average and keeping half
## of it free for the bad moments.
func _print_cost(label: String, tick_ms: float, budget_ms: float) -> void:
	if tick_ms <= 0.0:
		return
	var matches: float = budget_ms / tick_ms
	var safe: float = matches * 0.5
	var per_match: float = _price * (_match_minutes / 60.0) / maxf(safe, 0.001)
	print("%s: %.1f matches a core flat out, %.1f with half kept free -> $%.4f a %d-minute match at $%.3f a vCPU-hour" % [label, matches, safe, per_match, roundi(_match_minutes), _price])


## The frame time, in ms, that `share` of the frames stayed under.
func _percentile(share: float, counted: int) -> float:
	var wanted: int = ceili(counted * share)
	var seen: int = 0
	for bucket: int in BUCKETS:
		seen += _histogram[bucket]
		if seen >= wanted:
			return (bucket + 1) * BUCKET_USEC / 1000.0
	return BUCKETS * BUCKET_USEC / 1000.0
