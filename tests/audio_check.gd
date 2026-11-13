extends SceneTree
## Headless audio check. Every sound the scripts ask for has to exist as a file in
## assets/audio, and a CPU-vs-CPU game has to trigger the ones any game has.
## (Headless runs on the dummy audio driver: this checks the wiring, not the mix.)
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/audio_check.gd

const SPEED: float = 8.0
const STUCK_FRAMES: int = 600
const SCRIPT_DIRS: Array[String] = ["res://scripts", "res://scripts/state"]
## Sounds a whole game cannot go without.
const EXPECTED: Array[StringName] = [
	&"kick", &"catch", &"whistle", &"qb_cadence", &"qb_hut", &"snap", &"throw",
	&"tackle", &"body_fall", &"pads_clash", &"buzzer", &"announcer_down1",
	&"music_final",
]

var _game: Game
var _state: StringName = &""
var _state_frames: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null:
		return true
	var now: StringName = _game.play_controller.state_machine.current_name()
	if now != _state:
		_state = now
		_state_frames = 0
	_state_frames += 1
	if _state_frames > STUCK_FRAMES:
		_failures.append("stuck in state '%s'" % _state)
		return _report()
	if _state == &"GameOver":
		return _report()
	return false


func _report() -> bool:
	var audio: AudioDirector = _game.audio
	var named: Array[StringName] = _sounds_in_scripts()
	for sound: StringName in named:
		if not audio.has_sound(sound):
			_failures.append("no file for '%s'" % sound)
	for sound: StringName in audio.missing:
		_failures.append("asked for '%s', which has no file" % sound)
	for chat: String in audio.broken_exchanges:
		_failures.append("exchange '%s' has a part missing or a bad name" % chat)
	if AudioServer.get_bus_index(AudioDirector.BUS_MUSIC) < 0:
		_failures.append("no Music bus")
	for sound: StringName in [&"music_theme", &"music_open", &"music_halftime", &"music_final"]:
		if audio._bus_of(sound) != AudioDirector.BUS_MUSIC:
			_failures.append("'%s' is not on the Music bus" % sound)
		if not audio.has_sound(sound):
			_failures.append("no file for '%s'" % sound)
	for sound: StringName in EXPECTED:
		if audio.play_counts.get(sound, 0) == 0:
			_failures.append("'%s' never played" % sound)

	var names: Array[StringName] = audio.play_counts.keys()
	names.sort()
	print("Sounds named in scripts: %d.  Played this game:" % named.size())
	for sound: StringName in names:
		print("  %-26s %d" % [sound, audio.play_counts[sound]])
	print("Remarks asked for (before chance and gap): %s" % str(audio.remark_asks))
	print("Quips asked for (before chance and gap): %s" % str(audio.quip_asks))
	print("Exchanges between the two: %s" % str(audio.exchange_counts))
	var quiet: PackedStringArray = PackedStringArray()
	for sound: StringName in named:
		if not audio.play_counts.has(sound):
			quiet.append(String(sound))
	print("Not heard this game: %s" % (", ".join(quiet) if not quiet.is_empty() else "none"))
	if _failures.is_empty():
		print("AUDIO CHECK PASSED")
	else:
		for failure: String in _failures:
			print("FAIL: %s" % failure)
		print("AUDIO CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true


## Every sound name passed to the audio director anywhere in the game scripts.
func _sounds_in_scripts() -> Array[StringName]:
	var pattern: RegEx = RegEx.new()
	pattern.compile("(?:\\bplay|\\bsay|\\bshout|\\bremark|\\baction|_make_loop)\\((?:\\w+, )?&\"(\\w+)\"|&\"((?:crowd|ui|huddle|color)_\\w+)\"")
	var found: Dictionary[StringName, bool] = {}
	for dir: String in SCRIPT_DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if file.get_extension() != "gd":
				continue
			var text: String = FileAccess.get_file_as_string(dir.path_join(file))
			for hit: RegExMatch in pattern.search_all(text):
				var sound: String = hit.get_string(1) if hit.get_string(1) != "" else hit.get_string(2)
				# `ui_accept` and its like are buttons, not sounds.
				if not InputMap.has_action(sound):
					found[StringName(sound)] = true
	var sounds: Array[StringName] = found.keys()
	sounds.sort()
	return sounds
