extends SceneTree
## Headless check of the camera on a turnover in the middle of a play: after an
## interception and after a lost fumble it must circle round behind the new
## carrier (no cut), end up looking the way his team attacks, and stay there
## through the whistle and the turnover banner.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/camera_swing_check.gd

enum Step { WAIT, LOOSE, SWING, AFTER }

const CASES: Array[String] = ["interception", "lost fumble"]
## The swing peaks at about 5.6 degrees a tick at 60 Hz.
const MAX_STEP: float = deg_to_rad(8.0)

var _game: Game
var _pc: PlayController
var _rig: CameraRig
var _case: int = -1
var _step: Step = Step.WAIT
var _thief: Player
var _start_facing: float = 0.0
var _last_yaw: float = 0.0
var _worst: float = 0.0
var _turned: float = 0.0
var _ticks: int = 0
var _notes: PackedStringArray = []
var _failed: bool = false


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
		_rig = _game.camera_rig
		_next()
		return
	var step: float = absf(angle_difference(_last_yaw, _rig.rotation.y))
	_last_yaw = _rig.rotation.y
	_ticks += 1
	match _step:
		Step.WAIT:
			if _pc.ball_dead:
				_note("play ended before the turnover")
				_report()
			elif _pc.live_time >= 0.3 and _pc.ball.carrier != null:
				_start_facing = _rig.facing
				_thief = _pc.defense.players[0]
				for player: Player in _pc.offense.players:
					player.frozen = true
				if _case == 0:
					_pc._intercept(_thief)
					_begin_swing()
				else:
					_pc.fumbler = _pc.ball.carrier
					_pc.ball.fumble(Vector3(0.0, 4.0, 0.0))
					_pc.phase = PlayController.Phase.LOOSE
					_step = Step.LOOSE
					_ticks = 0
		Step.LOOSE:
			# Nobody has it: the camera stays where it is.
			if _rig.facing != _start_facing or step > 0.0001:
				_note("camera moved while the ball was loose")
			if _ticks >= 10:
				for attempt: int in 50:
					if _pc.ball.carrier == _thief:
						break
					_pc._grab_loose_ball(_thief)
				_begin_swing()
		Step.SWING:
			_worst = maxf(_worst, step)
			_turned += step
			if not _rig.is_swinging():
				var took: float = float(_ticks) / 60.0
				if _rig.facing != float(_thief.team.attack_dir):
					_note("camera is not behind the new carrier")
				if absf(_turned - PI) > 0.05:
					_note("turned %.0f degrees, not 180" % rad_to_deg(_turned))
				if _worst > MAX_STEP:
					_note("jumped %.1f degrees in one tick" % rad_to_deg(_worst))
				if absf(took - _game.tuning.camera_swing_time) > 0.1:
					_note("swing took %.2f s" % took)
				if not _pc.ball_dead:
					_pc.end_play(PlayController.Result.TACKLED, _thief.position.x)
				_step = Step.AFTER
				_ticks = 0
		Step.AFTER:
			if step > 0.0001 or _rig.facing != float(_thief.team.attack_dir):
				_note("camera moved again after the swing (%s)" % _pc.state_machine.current_name())
				_report()
			elif _pc.state_machine.current_name() == &"PlaySelect" or _ticks > 600:
				if _game.offense != _thief.team:
					_note("the other team did not get the ball")
				_report()


func _begin_swing() -> void:
	if _pc.ball.carrier != _thief:
		_note("could not hand the ball to the defender")
	_step = Step.SWING
	_ticks = 0
	_worst = 0.0
	_turned = 0.0


func _note(text: String) -> void:
	if not _notes.has(text):
		_notes.append(text)


func _report() -> void:
	_failed = _failed or not _notes.is_empty()
	print("%-13s turned %3.0f deg, biggest step %.1f deg  %s" % [CASES[_case], rad_to_deg(_turned), rad_to_deg(_worst), "ok" if _notes.is_empty() else "FAILED: " + ", ".join(_notes)])
	_next()


func _next() -> void:
	_case += 1
	if _case >= CASES.size():
		physics_frame.disconnect(_tick)
		print("camera swing check %s" % ("FAILED" if _failed else "PASSED"))
		quit(1 if _failed else 0)
		return
	_notes.clear()
	_game.kickoff_to = null
	_game.scramble_due = false
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	_pc.line_up(_game.offense_playbook.plays[0], _game.defense_playbook.plays[0])
	# The game cuts to the new offense between plays; here the snap comes in the
	# same tick, so do it by hand.
	_game.snap_camera()
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_step = Step.WAIT
	_ticks = 0
	_worst = 0.0
	_turned = 0.0
	_last_yaw = -PI * 0.5 * float(_game.home.attack_dir)
