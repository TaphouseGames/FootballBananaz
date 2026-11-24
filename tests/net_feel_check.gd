extends SceneTree
## Checks NetFeel, the debug option that tries out a network delay offline:
##  - OTHERS LATE draws a moving player where he was that many ticks ago, and
##    the game still sees him where he is,
##  - BUTTONS LATE passes a press on that many ticks later, once,
##  - the CPU plays on through both without a state getting stuck.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/net_feel_check.gd

const LAG_MS: int = 100
const LAG_TICKS: int = 6
## Ticks of play looked at for each mode.
const WATCH: int = 1500
const STUCK: int = 1200

var _game: Game
var _tick: int = 0
var _phase: int = 0
var _phase_start: int = 0
var _failures: PackedStringArray = PackedStringArray()

## Where one player really was at the start of each tick, newest last.
var _watched: Player
var _real: PackedVector3Array = PackedVector3Array()
var _late_seen: int = 0
var _late_wrong: int = 0
var _real_wrong: int = 0

var _press_tick: int = -1
var _live_tick: int = -1
var _late_ticks: PackedInt32Array = PackedInt32Array()

var _state: StringName = &""
var _listening: bool = false
## Where the watched player was last drawn, and whether that was a late place.
var _drawn: Vector3 = Vector3.ZERO
var _drawn_late: bool = false
var _state_ticks: int = 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _on_tick() -> void:
	_tick += 1
	var now: StringName = _game.play_controller.state_machine.current_name()
	_state_ticks = _state_ticks + 1 if now == _state else 0
	_state = now
	if _state_ticks > STUCK and now != &"GameOver":
		_fail("stuck in state '%s' with the delay on" % now)
	match _phase:
		0:
			_game.net_feel.set_lag(LAG_MS, NetFeel.Mode.OTHERS_LATE)
			_watched = _game.play_controller.players[0]
			_next_phase()
		1:
			_check_real()
			if _tick - _phase_start > WATCH:
				if _late_seen < 100:
					_fail("the watched player was only seen moving on %d ticks" % _late_seen)
				if _late_wrong > 0:
					_fail("drawn somewhere other than %d ticks back on %d of %d ticks" % [LAG_TICKS, _late_wrong, _late_seen])
				# Now and then he really is back where he was six ticks ago.
				if _real_wrong * 50 > _late_seen:
					_fail("the game saw a player at his late place on %d ticks" % _real_wrong)
				_game.net_feel.set_lag(LAG_MS, NetFeel.Mode.BUTTONS_LATE)
				_next_phase()
		2:
			_check_buttons()
			if _tick - _phase_start > WATCH:
				_game.net_feel.set_lag(0)
				_report()


func _next_phase() -> void:
	_phase += 1
	_phase_start = _tick


## Notes where the watched player really is (this runs with everybody put
## back), and counts the ticks on which he is still at the place he was drawn.
func _check_real() -> void:
	if _drawn_late and _watched.position.distance_to(_drawn) < 0.001:
		_real_wrong += 1
	_drawn_late = false
	_real.append(_watched.position)
	if _real.size() > LAG_TICKS + 4:
		_real.remove_at(0)


## Between ticks: the watched player is drawn where he was LAG_TICKS ago.
func _process(_delta: float) -> bool:
	# The game is only ready once the tree runs. Listening from then on puts this
	# after NetFeel's own start of the tick: everybody is back where they really are.
	if not _listening and _game.net_feel != null:
		_listening = true
		physics_frame.connect(_on_tick)
	if _phase == 1 and _real.size() > LAG_TICKS + 2:
		var newest: Vector3 = _real[_real.size() - 1]
		var moved: float = newest.distance_to(_real[_real.size() - 1 - LAG_TICKS])
		# Standing still, or put somewhere new, there is nothing to tell apart.
		if moved > 0.2 and moved < 3.0:
			_late_seen += 1
			# The newest note is of the tick before the one just played.
			var shown: Vector3 = _watched.position
			_drawn = shown
			_drawn_late = true
			var near: float = INF
			for back: int in [LAG_TICKS - 1, LAG_TICKS, LAG_TICKS + 1]:
				near = minf(near, shown.distance_to(_real[_real.size() - 1 - back]))
			if near > 0.01:
				_late_wrong += 1
	return false


## One press of a button nothing in a CPU game listens to.
func _check_buttons() -> void:
	var pad: PadInput = _game.humans[0].pad
	var since: int = _tick - _phase_start
	if since == 30:
		Input.action_press(&"camera_view")
		_press_tick = _tick
	if since == 60:
		Input.action_release(&"camera_view")
	# The press is made here, after this tick's buttons were noted: the game
	# would first have seen it on the next tick.
	if _live_tick < 0 and _press_tick >= 0 and _tick > _press_tick and Input.is_action_pressed(&"camera_view"):
		_live_tick = _tick
	if pad.just_pressed(&"camera_view"):
		_late_ticks.append(_tick)
	if since == 120:
		if _late_ticks.size() != 1:
			_fail("the late press came through %d times" % _late_ticks.size())
		elif _late_ticks[0] - _live_tick != LAG_TICKS:
			_fail("the press came through %d ticks late, not %d" % [_late_ticks[0] - _live_tick, LAG_TICKS])
		if pad.pressed(&"camera_view"):
			_fail("the button still reads held long after it was let go")


func _fail(text: String) -> void:
	_failures.append(text)
	_report()


func _report() -> void:
	print("late picture: %d moving ticks checked, %d wrong" % [_late_seen, _late_wrong])
	if _failures.is_empty():
		print("NET FEEL CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("NET FEEL CHECK FAILED: %s" % failure)
		quit(1)
	_phase = 99
