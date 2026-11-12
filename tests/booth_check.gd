extends SceneTree
## Headless check of the exchanges between Jim and Tony (the `chat_*` files).
## Keeps Tony talking through a CPU game for a while at normal speed: exchanges
## have to start and reach their last line, the two voices must never overlap,
## and a shouted call has to cut an exchange short.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/booth_check.gd -- seconds=90

var _game: Game
var _seconds: float = 90.0
var _start: int = 0
var _overlaps: int = 0
var _shouted: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_seconds = arg.trim_prefix("seconds=").to_float()
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	_game.tuning.audio_color_gap = 0.0
	_game.tuning.audio_color_repeat_gap = 0.0
	_start = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	var audio: AudioDirector = _game.audio
	var elapsed: float = float(Time.get_ticks_msec() - _start) / 1000.0
	if audio._announcer.playing and audio._color.playing:
		_overlaps += 1
	audio.quip(AudioDirector.QUIP_IDLE, 1.0)
	# Once the first few have run their course, interrupt the next one.
	if not _shouted and audio.exchange_counts[&"finished"] >= 1 and not audio._exchange_parts.is_empty():
		_shouted = true
		audio.shout(&"announcer_touchdown")
	if elapsed < _seconds:
		return false

	var counts: Dictionary[StringName, int] = audio.exchange_counts
	var failures: PackedStringArray = PackedStringArray()
	if audio._exchanges.is_empty():
		failures.append("no chat_* exchanges were found in assets/audio")
	for chat: String in audio.broken_exchanges:
		failures.append("exchange '%s' has a part missing or a bad name" % chat)
	if counts[&"started"] == 0:
		failures.append("no exchange started")
	if counts[&"finished"] == 0:
		failures.append("no exchange reached its last line")
	if _shouted and counts[&"cut"] == 0:
		failures.append("a shout did not cut the exchange short")
	if _overlaps > 0:
		failures.append("the two voices overlapped on %d frames" % _overlaps)
	var total: int = 0
	for sound: StringName in audio._exchanges:
		total += audio._exchanges[sound].size()
	print("Exchanges on file: %d over %d moments.  This run: %s" % [total, audio._exchanges.size(), str(counts)])
	for failure: String in failures:
		print("FAIL: %s" % failure)
	print("BOOTH CHECK PASSED" if failures.is_empty() else "BOOTH CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if failures.is_empty() else 1)
	return true
