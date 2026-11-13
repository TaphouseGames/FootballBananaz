extends SceneTree
## Check of the pregame intro. A match flagged by the main menu has to open in
## the Intro state with the television card up, let Jim and Tony finish one
## exchange without talking over each other, and hand over to the kickoff in
## 5 to 12 seconds with the camera and the scoreboard back. A second match is
## skipped with (A), a third one without the flag goes straight to the kickoff,
## and the openings must come round without repeats.
##
## Real time, so no --fixed-fps. With `out=<dir>` (and a window, so no
## --headless) it saves pictures of the first intro on the way.
## Run:  godot --headless --path . --script res://tests/intro_check.gd

enum Step { WATCH, SKIP, PLAIN }

const MIN_SECONDS: float = 5.0
const MAX_SECONDS: float = 12.0
const SKIP_AT: float = 1.5
## Seconds into the intro at which a picture is taken.
const SHOTS: Array[float] = [0.3, 1.2, 3.0, 6.0]

var _game: Game
var _step: Step = Step.WATCH
var _start: int = 0
var _frames: int = 0
var _overlaps: int = 0
var _pressed: bool = false
var _out: String = ""
var _shots_taken: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
	_check_bag()
	_open(true)


func _open(with_intro: bool) -> void:
	if _game != null:
		_game.free()
	Game.show_intro = with_intro
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	root.add_child(_game)
	_start = Time.get_ticks_msec()
	_frames = 0
	_pressed = false


func _process(_delta: float) -> bool:
	_frames += 1
	var audio: AudioDirector = _game.audio
	var state: StringName = _game.play_controller.state_machine.current_name()
	var elapsed: float = float(Time.get_ticks_msec() - _start) / 1000.0
	if audio._announcer.playing and audio._color.playing:
		_overlaps += 1
	match _step:
		Step.WATCH:
			if _frames == 1:
				if state != &"Intro":
					_failures.append("the match opened in '%s', not Intro" % state)
				if _game.hud.top_bar.visible or _game.hud._intro_card == null:
					_failures.append("the intro card is not up in place of the scoreboard")
				if Game.show_intro:
					_failures.append("the intro flag was not cleared")
			if _out != "" and _shots_taken < SHOTS.size() and elapsed >= SHOTS[_shots_taken]:
				root.get_texture().get_image().save_png(_out.path_join("intro_%d.png" % _shots_taken))
				_shots_taken += 1
			if state == &"Intro" and elapsed < MAX_SECONDS + 3.0:
				return false
			print("Intro lasted %.1f s.  Exchanges: %s" % [elapsed, str(audio.exchange_counts)])
			if state == &"Intro":
				_failures.append("still in the intro after %.0f s" % elapsed)
			elif elapsed < MIN_SECONDS or elapsed > MAX_SECONDS:
				_failures.append("the intro lasted %.1f s, outside %.0f-%.0f" % [elapsed, MIN_SECONDS, MAX_SECONDS])
			if audio.exchange_counts[&"started"] != 1 or audio.exchange_counts[&"finished"] != 1:
				_failures.append("the booth did not say exactly one whole exchange")
			if audio.play_counts.get(&"music_open", 0) != 1 or audio.missing.has(&"music_open"):
				_failures.append("the fanfare did not play")
			if _overlaps > 0:
				_failures.append("the two voices overlapped on %d frames" % _overlaps)
			_check_handed_over()
			_step = Step.SKIP
			_open(true)
		Step.SKIP:
			if not _pressed and elapsed >= SKIP_AT:
				_pressed = true
				if state != &"Intro":
					_failures.append("the intro was over before it could be skipped")
				Input.action_press(&"confirm")
				return false
			if not _pressed or (state == &"Intro" and elapsed < SKIP_AT + 1.0):
				return false
			Input.action_release(&"confirm")
			if state == &"Intro":
				_failures.append("(A) did not skip the intro")
			if audio.booth_busy():
				_failures.append("the booth kept talking after the skip")
			_check_handed_over()
			_step = Step.PLAIN
			_open(false)
		Step.PLAIN:
			if state != &"Kickoff":
				_failures.append("a match without the flag opened in '%s'" % state)
			return _report()
	return false


## The kickoff has the picture: camera on its rig, scoreboard up, card gone.
func _check_handed_over() -> void:
	var rig: CameraRig = _game.camera_rig
	if rig._shot or not rig.camera.transform.is_equal_approx(rig._home):
		_failures.append("the camera did not go back to its rig")
	if not _game.hud.top_bar.visible or _game.hud._intro_card != null:
		_failures.append("the scoreboard did not come back")


## Two rounds of the openings: each once a round, none twice running.
func _check_bag() -> void:
	const COUNT: int = 8
	var last: int = -1
	for lap: int in 2:
		var seen: Dictionary[int, bool] = {}
		for i: int in COUNT:
			var pick: int = AudioDirector.next_intro(COUNT)
			if pick == last:
				_failures.append("opening %d came up twice running" % pick)
			last = pick
			seen[pick] = true
		if seen.size() != COUNT:
			_failures.append("a round of openings had only %d of %d" % [seen.size(), COUNT])


func _report() -> bool:
	var openings: int = (_game.audio._exchanges.get(AudioDirector.QUIP_INTRO, []) as Array).size()
	print("Openings on file: %d" % openings)
	if openings < 2:
		_failures.append("fewer than two chat_intro_* exchanges in assets/audio")
	for chat: String in _game.audio.broken_exchanges:
		_failures.append("exchange '%s' has a part missing or a bad name" % chat)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("INTRO CHECK PASSED" if _failures.is_empty() else "INTRO CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true
