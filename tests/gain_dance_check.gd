extends SceneTree
## Headless check of the dance after a first down or a long gain: a person's
## carrier may pick one until the late-hit window closes, the next play waits
## for a dance that was picked and for nothing when none was, and a short gain
## or a CPU carrier is offered none.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/gain_dance_check.gd

const SPEED: float = 8.0
## What each play is: yards gained (negative: a yard past the first-down marker,
## with the long gain out of reach), whether the carrier is a person's, whether
## they pick a dance, and whether one is to be on offer at all.
const CASES: Array[Dictionary] = [
	{"name": "long gain, picked", "yards": 22.0, "person": true, "pick": true, "offered": true},
	{"name": "first down, picked", "yards": -1.0, "person": true, "pick": true, "offered": true},
	{"name": "first down, left alone", "yards": -1.0, "person": true, "pick": false, "offered": true},
	{"name": "short gain", "yards": 4.0, "person": true, "pick": false, "offered": false},
	{"name": "long gain by the CPU", "yards": 22.0, "person": false, "pick": false, "offered": false},
]

var _game: Game
var _pc: PlayController
var _failures: PackedStringArray = PackedStringArray()
var _case: int = 0
## 0 = snap it, 1 = move the carrier and blow the whistle, 2 = watching.
var _step: int = 0
var _carrier: Player
var _looked: bool = false
var _picked_style: int = -1
var _danced: bool = false
var _dead_for: float = 0.0
var _was_dead: bool = false
var _dance_time: float = 0.0
var _pressed: StringName = &""


func _initialize() -> void:
	# See smoke_test.gd: the tick rate has to go up with the time scale.
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	# Nobody changes the play under the test.
	_game.tuning.ai_motion_chance = 0.0
	_game.tuning.ai_audible_chance = 0.0
	_game.tuning.ai_hot_route_chance = 0.0
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
	var state: StringName = _pc.state_machine.current_name()
	var case: Dictionary = CASES[_case]
	match _step:
		0:
			_snap()
			_step = 1
		1:
			_carrier = _pc.ball.carrier
			if _carrier == null:
				_step = 0
				return
			if case["person"]:
				_game.human.team = _carrier.team
				_game.human.set_controlled(_carrier)
			var dir: float = float(_carrier.team.attack_dir)
			var yards: float = case["yards"]
			_game.tuning.celebration_gain_yards = 15.0
			if yards < 0.0:
				yards = _game.tuning.yards_to_gain + 1.0
				_game.tuning.celebration_gain_yards = 200.0
			_carrier.position = Vector3(_pc.los_x + dir * yards, 0.0, 0.0)
			_looked = false
			_picked_style = -1
			_danced = false
			_dead_for = 0.0
			_was_dead = false
			_dance_time = 0.0
			_pc.end_play(PlayController.Result.TACKLED, _carrier.position.x)
			if _pc.celebration_pick_open != bool(case["offered"]):
				_failures.append("%s: a dance was %s at the whistle" % [case["name"], "on offer" if _pc.celebration_pick_open else "not on offer"])
			_step = 2
		2:
			if state == &"Live":
				return
			if state == &"Dead":
				_was_dead = true
				_dead_for = _pc.state_machine.current.time_in_state
				_watch(case)
				return
			_judge(case)
			_game.human.set_controlled(null)
			_game.human.team = null
			_case += 1
			if _case >= CASES.size():
				_finish()
			else:
				_step = 0


## Home, first and ten at its own 30.
func _snap() -> void:
	var team: Team = _game.home
	_game.conversion = false
	_game.half = 1
	_game.clock = 100.0
	_game.start_drive(team, _game.tuning.yard_to_x(team.attack_dir, 30.0))
	_pc.line_up(_game.offense_playbook.plays[0], _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")


func _watch(case: Dictionary) -> void:
	var tuning: Tuning = _game.tuning
	var name: String = case["name"]
	if _pc.dead_time < tuning.celebration_pick_delay and _pc.can_pick_celebration(_carrier):
		_failures.append("%s: the dance could be picked %.2f s after the whistle" % [name, _pc.dead_time])
	# A few ticks later: the press is read on the tick after it is made.
	if _pressed != &"" and _looked and _pc.dead_time >= 0.9:
		Input.action_release(_pressed)
		_pressed = &""
		if not _pc.gain_dance or posmod(_pc.celebration_style, PlayerAnimator.DANCES) != _picked_style:
			_failures.append("%s: the button for dance %d did not pick it" % [name, _picked_style])
	if _picked_style >= 0 and not _carrier.has_ball and _carrier.can_act():
		_danced = true
	_dance_time = maxf(_dance_time, _pc.gain_dance_time)
	# The person lets go a moment before the window closes, so the next state
	# is not entered with somebody playing.
	if not case["pick"] and _pc.dead_time >= tuning.late_hit_window - 0.15:
		_game.human.set_controlled(null)
		_game.human.team = null
	if _looked or _pc.dead_time < 0.8:
		return
	_looked = true
	if _pc.can_pick_celebration(_carrier) != bool(case["offered"]):
		_failures.append("%s: 0.8 s after the whistle a dance %s be picked" % [name, "could" if not case["offered"] else "could not"])
	if not case["pick"]:
		return
	_picked_style = _case % PlayerAnimator.DANCES
	if _case % 2 == 1:
		# The button itself, read by the person's controller on the next tick.
		if not _game.humans.has(_game.human):
			_game.humans.append(_game.human)
		_pressed = HumanController.PASS_ACTIONS[_picked_style]
		Input.action_press(_pressed)
		return
	_pc.pick_celebration(_picked_style)
	if not _pc.gain_dance or _pc.celebration_pick_open or posmod(_pc.celebration_style, PlayerAnimator.DANCES) != _picked_style:
		_failures.append("%s: dance %d was picked and it did not take" % [name, _picked_style])


func _judge(case: Dictionary) -> void:
	var tuning: Tuning = _game.tuning
	var name: String = case["name"]
	if not _was_dead:
		_failures.append("%s: the play never went dead" % name)
		return
	if _pc.celebration_pick_open:
		_failures.append("%s: the dance was still open to pick after the window" % name)
	var window: float = tuning.late_hit_window
	if case["pick"]:
		var longest: float = window + 2.0 * tuning.celebration_gain_dance_time + 0.1
		if _dead_for < window + 0.5 or _dead_for > longest:
			_failures.append("%s: the next play came after %.2f s with a dance picked" % [name, _dead_for])
		if not _danced:
			_failures.append("%s: he never spiked the ball and danced" % name)
		if _dance_time < tuning.celebration_gain_dance_time - 0.05 and _dead_for < longest - 0.2:
			_failures.append("%s: he danced for only %.2f s" % [name, _dance_time])
	elif _dead_for > window + 0.1:
		_failures.append("%s: the next play came after %.2f s with no dance picked" % [name, _dead_for])
	print("%-26s dead for %.2f s, danced %.2f s" % [name, _dead_for, _dance_time])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _game.get_stat(&"gain_dances") != 2:
		_failures.append("%d dances after a gain counted, not 2" % _game.get_stat(&"gain_dances"))
	if _failures.is_empty():
		print("GAIN DANCE CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("FAILED: ", failure)
		quit(1)
