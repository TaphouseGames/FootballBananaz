extends SceneTree
## Headless check of the booth's word on the kickoff that opens a half or
## sudden death (`announcer_kickoff`, `color_kickoff`). A CPU game starts: Jim
## and Tony have to be asked for the line at the opening kickoff, the kick has
## to clear Game.opening_kickoff, a kickoff after a score must not ask again,
## and the second half and sudden death must set it once more.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/kickoff_call_check.gd

const STUCK_FRAMES: int = 20000
const LINES: int = 3

var _game: Game
var _frames: int = 0
var _opened: bool = false
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
		_failures.append("the opening kickoff was never kicked")
		return _finish()
	var audio: AudioDirector = _game.audio
	var state: StringName = _game.play_controller.state_machine.current_name()
	if not _opened:
		if state != &"Kickoff":
			return false
		_opened = true
		_expect(_game.play_controller.kickoff, "the match did not open with a kickoff")
		_expect(_game.offense == _game.opening_receiver, "the opening kickoff does not go to the opening receiver")
		_expect(_game.opening_kickoff, "the opening kickoff is not marked as one")
		_expect(_asks(audio) == Vector2i(1, 1), "at the opening kickoff Jim and Tony were asked %s times" % _asks(audio))
		for sound: StringName in [AudioDirector.CALL_KICKOFF, AudioDirector.QUIP_KICKOFF]:
			var lines: int = (audio._streams.get(sound, []) as Array).size()
			_expect(lines == LINES, "expected %d lines of '%s', found %d" % [LINES, sound, lines])
		return false
	if state != &"Live":
		return false

	# The ball is in the air: the next kickoff is an ordinary one.
	_expect(not _game.opening_kickoff, "the kick did not clear the opening kickoff")
	audio._on_state_changed(&"", &"Kickoff")
	_expect(_asks(audio) == Vector2i(1, 1), "a kickoff after a score had the booth asked again")

	_game.start_second_half()
	_expect(_game.opening_kickoff and _game.kickoff_to == _game.opening_receiver.opponent, "the second half's kickoff is not an opening one to the other team")
	audio._on_state_changed(&"", &"Kickoff")
	_expect(_asks(audio) == Vector2i(2, 2), "the second half's kickoff had the booth asked %s times in all" % _asks(audio))

	_game.opening_kickoff = false
	_game.kickoff_to = null
	_game.start_overtime()
	_expect(_game.opening_kickoff and _game.kickoff_to != null, "sudden death does not open with a kickoff")
	return _finish()


## How often Jim and Tony have been asked for the line.
func _asks(audio: AudioDirector) -> Vector2i:
	return Vector2i(audio.remark_asks.get(AudioDirector.CALL_KICKOFF, 0), audio.quip_asks.get(AudioDirector.QUIP_KICKOFF, 0))


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("KICKOFF CALL CHECK PASSED" if _failures.is_empty() else "KICKOFF CALL CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true
