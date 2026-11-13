extends SceneTree
## Headless check of the booth's word that the half or the game is nearly over.
## First a short CPU game is played to see that the calls come up in both
## halves; then the game is put in a number of score-and-clock situations to
## see which lines are picked for each.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/late_check.gd

const SPEED: float = 8.0
const STUCK_FRAMES: int = 600
## Seconds in the game played: enough for a few plays either side of the break.
const GAME_LENGTH: float = 80.0
const LATE_GAME: Array[StringName] = [
	AudioDirector.QUIP_LATE, AudioDirector.QUIP_LATE_BLOWOUT, AudioDirector.QUIP_LATE_CLOSE,
]

var _game: Game
var _audio: AudioDirector
var _state: StringName = &""
var _state_frames: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	# See smoke_test.gd: the tick rate has to go up with the time scale.
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready():
		return false
	if _audio == null:
		_audio = _game.audio
		_game.tuning.game_length = GAME_LENGTH
		_game.clock = GAME_LENGTH * 0.5
	var now: StringName = _game.play_controller.state_machine.current_name()
	if now != _state:
		_state = now
		_state_frames = 0
	_state_frames += 1
	if _state_frames > STUCK_FRAMES:
		_failures.append("stuck in state '%s'" % _state)
		return _finish()
	if _state == &"GameOver":
		_check_game()
		_check_picks()
		return _finish()
	return false


# --- The game played ---------------------------------------------------------

func _check_game() -> void:
	var asks: Dictionary[StringName, int] = _audio.quip_asks
	var late_game: int = 0
	for sound: StringName in LATE_GAME:
		late_game += asks.get(sound, 0)
	print("late quips asked for: half %d, game %d   said by Tony in half %d" % [asks.get(AudioDirector.QUIP_LATE_HALF, 0), late_game, _audio._late_quip_said_half])
	_expect(asks.get(AudioDirector.QUIP_LATE_HALF, 0) > 0, "nothing was said about the first half running out")
	_expect(late_game > 0, "nothing was said about the game running out")
	_expect(_audio._late_called_half == 2, "Jim never said the game was nearly over")
	for sound: StringName in _audio.missing:
		_failures.append("asked for '%s', which has no file" % sound)
	for sound: StringName in [AudioDirector.CALL_LATE_HALF, AudioDirector.CALL_LATE_GAME, AudioDirector.CALL_LAST_PLAY, AudioDirector.QUIP_LATE, AudioDirector.QUIP_LATE_HALF, AudioDirector.QUIP_LATE_BLOWOUT, AudioDirector.QUIP_LATE_CLOSE]:
		_expect(_audio.has_sound(sound), "no file for '%s'" % sound)
	for chat: String in _audio.broken_exchanges:
		_failures.append("exchange '%s' has a part missing or a bad name" % chat)


# --- Which lines for which situation -----------------------------------------

func _check_picks() -> void:
	var late: float = _game.tuning.audio_late_plays
	_expect(late >= 2.0, "audio_late_plays is under two plays")

	# Plenty of clock: nothing to say.
	_fresh()
	_put(1, 90.0, 0, 0)
	_expect(_calls() == [] and _last_quip == &"", "late call with 1:30 left in the half")

	# A couple of plays left in the first half.
	_put(1, 10.0, 21, 0)
	_expect(_calls() == [AudioDirector.CALL_LATE_HALF], "Jim: expected the late-half call, got %s" % str(_last_calls))
	_expect(_last_quip == AudioDirector.QUIP_LATE_HALF, "Tony: expected the late-half line, got '%s'" % _last_quip)
	# Next huddle: Jim has said it; Tony, who has not got it out yet, is asked again.
	_expect(_calls() == [], "Jim said the half was nearly over twice")
	_expect(_last_quip == AudioDirector.QUIP_LATE_HALF, "Tony's late line was not asked for again")
	_audio._late_quip_said_half = 1
	_expect(_calls() == [] and _last_quip == &"", "the late call came up again after both had said it")

	# The last play of the half: Jim once, and Tony has had his say already.
	_put(1, 2.0, 0, 0)
	_expect(_calls() == [AudioDirector.CALL_LAST_PLAY], "Jim: expected the last-play call, got %s" % str(_last_calls))
	_expect(_calls() == [], "Jim called the last play twice")

	# The second half starts over, and the score picks Tony's line.
	_put(2, 10.0, 21, 0)
	_expect(_calls() == [AudioDirector.CALL_LATE_GAME], "Jim: expected the late-game call, got %s" % str(_last_calls))
	_expect(_last_quip == AudioDirector.QUIP_LATE_BLOWOUT, "rout: Tony's line was '%s'" % _last_quip)
	_put(2, 10.0, 0, 21)
	_calls()
	_expect(_last_quip == AudioDirector.QUIP_LATE_BLOWOUT, "rout the other way: Tony's line was '%s'" % _last_quip)
	_put(2, 10.0, 14, 13)
	_calls()
	_expect(_last_quip == AudioDirector.QUIP_LATE_CLOSE, "one-point game: Tony's line was '%s'" % _last_quip)
	_put(2, 10.0, 12, 0)
	_calls()
	_expect(_last_quip == AudioDirector.QUIP_LATE, "two-score game: Tony's line was '%s'" % _last_quip)

	# Straight to the last play with nothing said before it: one call from Jim,
	# not two, and Tony still gets his line.
	_fresh()
	_put(2, 2.0, 6, 6)
	_expect(_calls() == [AudioDirector.CALL_LAST_PLAY], "last play first: Jim's calls were %s" % str(_last_calls))
	_expect(_last_quip == AudioDirector.QUIP_LATE_CLOSE, "last play first: Tony's line was '%s'" % _last_quip)

	# The try is untimed.
	_fresh()
	_put(2, 2.0, 6, 0)
	_game.start_conversion(_game.home)
	_expect(_calls() == [] and _last_quip == &"", "late call before a try")
	_game.conversion = false


var _last_calls: Array[StringName] = []
var _last_quip: StringName = &""


## What Jim lines up and what Tony is left holding after one huddle.
func _calls() -> Array[StringName]:
	_audio._announcer_queue.clear()
	_audio._quip_pending = &""
	_audio._late_calls()
	_last_calls = _audio._announcer_queue.duplicate()
	_last_quip = _audio._quip_pending
	_audio._announcer_queue.clear()
	_audio._quip_pending = &""
	return _last_calls


## As if nothing had been said yet in either half.
func _fresh() -> void:
	_audio._late_called_half = 0
	_audio._last_play_called_half = 0
	_audio._late_quip_said_half = 0


## Home has the ball at its own 30, `home_score` to `away_score`.
func _put(half: int, clock: float, home_score: int, away_score: int) -> void:
	var team: Team = _game.home
	_game.conversion = false
	_game.half = half
	_game.clock = clock
	_game.start_drive(team, _game.tuning.yard_to_x(team.attack_dir, 30.0))
	team.score = home_score
	team.opponent.score = away_score


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	if _failures.is_empty():
		print("LATE CHECK PASSED")
	else:
		for failure: String in _failures:
			print("FAIL: %s" % failure)
		print("LATE CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true
