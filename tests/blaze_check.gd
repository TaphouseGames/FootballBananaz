extends SceneTree
## Headless check of the booth's fourth-and-twenty joke (`color_blaze`,
## `chat_blaze_*`). Waits for the first line-up from scrimmage of a CPU game,
## then puts the down and distance where it wants them: the joke has to be
## asked for in the huddle on 4th & 20 and on nothing else, and the snap must
## not swap it for the ordinary fourth-down line.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/blaze_check.gd

const STUCK_FRAMES: int = 20000
const SOLO_LINES: int = 2
const EXCHANGES: int = 2

var _game: Game
var _audio: AudioDirector
var _frames: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready():
		return false
	_frames += 1
	if _frames > STUCK_FRAMES:
		_failures.append("no line-up from scrimmage came up")
		return _finish()
	var pc: PlayController = _game.play_controller
	if pc.state_machine.current_name() != &"PreSnap" or pc.kickoff or pc.heave or _game.conversion:
		return false
	_audio = _game.audio
	# Tony always has the thought, so only the down and distance decide.
	_game.tuning.audio_color_gap = 0.0
	_game.tuning.audio_color_repeat_gap = 0.0
	_game.tuning.audio_color_scale = 10.0
	_check_files()
	_check_huddle()
	_check_snap()
	return _finish()


func _check_files() -> void:
	var blaze: StringName = AudioDirector.QUIP_BLAZE
	var solos: int = (_audio._streams.get(blaze, []) as Array).size()
	var chats: int = (_audio._exchanges.get(blaze, []) as Array).size()
	print("color_blaze: %d solo lines, %d exchanges" % [solos, chats])
	_expect(solos == SOLO_LINES, "expected %d solo lines, found %d" % [SOLO_LINES, solos])
	_expect(chats == EXCHANGES, "expected %d exchanges, found %d" % [EXCHANGES, chats])
	for chat: String in _audio.broken_exchanges:
		_failures.append("exchange '%s' has a part missing or a bad name" % chat)


func _check_huddle() -> void:
	var blaze: StringName = AudioDirector.QUIP_BLAZE
	_expect(_huddle(4, 20.0) == blaze, "4th & 20: Tony was left holding '%s'" % _audio._quip_pending)
	_expect(_audio.quip_asks.get(blaze, 0) == 1, "4th & 20: the joke was asked for %d times" % _audio.quip_asks.get(blaze, 0))
	_expect(_audio._announcer_queue == [&"announcer_down4", &"announcer_togo20"], "4th & 20: Jim's call was %s" % str(_audio._announcer_queue))
	_expect(_huddle(4, 19.0) != blaze, "the joke came up on 4th & 19")
	_expect(_huddle(4, 21.0) != blaze, "the joke came up on 4th & 21")
	_expect(_huddle(3, 20.0) != blaze, "the joke came up on 3rd & 20")
	_put(4, 20.0)
	_game.goal_to_go = true
	_expect(not _audio.blaze_down(), "the joke came up on 4th & goal")
	_game.goal_to_go = false
	_game.conversion = true
	_expect(not _audio.blaze_down(), "the joke came up on a try")
	_game.conversion = false


func _check_snap() -> void:
	var blaze: StringName = AudioDirector.QUIP_BLAZE
	# Any other fourth down: the snap brings the usual line, so this check
	# would notice the snap stepping on the joke.
	_put(4, 19.0)
	_quiet()
	_game.play_controller.snap()
	_expect(_audio._quip_pending == &"color_fourth", "4th & 19 snap: Tony was left holding '%s'" % _audio._quip_pending)
	_put(4, 20.0)
	_quiet()
	_audio._quip_pending = blaze
	_game.play_controller.snap()
	_expect(_audio._quip_pending == blaze, "4th & 20 snap: the joke was replaced by '%s'" % _audio._quip_pending)


## What Tony is holding after the huddle for `down` and `yards` to go.
func _huddle(down: int, yards: float) -> StringName:
	_put(down, yards)
	_quiet()
	_audio._on_state_changed(&"", &"PlaySelect")
	return _audio._quip_pending


func _put(down: int, yards: float) -> void:
	_game.down = down
	_game.goal_to_go = false
	_game.first_down_x = _game.los_x + yards * float(_game.play_controller.offense.attack_dir)


## Nobody talking and nothing held back.
func _quiet() -> void:
	_audio._color.stop()
	_audio._announcer.stop()
	_audio._exchange_parts.clear()
	_audio._quip_pending = &""


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("BLAZE CHECK PASSED" if _failures.is_empty() else "BLAZE CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true
