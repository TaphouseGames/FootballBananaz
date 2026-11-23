extends SceneTree
## Headless check of the lateral (PlayController.do_lateral):
##  - a forced pitch after the handoff goes to a teammate who is not ahead of
##    the carrier, and the ball travels there (no teleport);
##  - with every teammate ahead of him there is nobody to pitch to;
##  - a pitch that goes wrong is a fumble;
##  - with the clock run out and points needed the CPU keeps the ball alive;
##  - in ordinary play the CPU pitches rarely, and never forward.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/lateral_check.gd [-- snaps=N]

enum Case { PITCH, NOBODY, BAD_PITCH, LAST_GASP, ORDINARY, DONE }

var _game: Game
var _pc: PlayController
var _run_play: OffensePlay
var _case: Case = Case.PITCH
var _snaps: int = 40
var _snap: int = 0
var _tries: int = 0
var _failures: PackedStringArray = PackedStringArray()

## The forced cases: who pitched, who should have it, and the ball's biggest step.
var _pitcher: Player
var _taker: Player
var _pitched_at: float = -1.0
var _last: Vector3 = Vector3.ZERO
var _worst: float = 0.0
## Stats before the snaps of the two CPU cases.
var _laterals_before: int = 0
var _fumbles_before: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("snaps="):
			_snaps = maxi(int(arg.trim_prefix("snaps=")), 1)
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
		for play: OffensePlay in _game.offense_playbook.plays:
			if play.is_run and not play.flea_flicker and _run_play == null:
				_run_play = play
		_start_case()
		return
	match _case:
		Case.PITCH:
			_tick_pitch()
		Case.NOBODY:
			_tick_nobody()
		Case.BAD_PITCH:
			_tick_bad_pitch()
		Case.LAST_GASP, Case.ORDINARY:
			_tick_cpu()


func _start_case() -> void:
	_snap = 0
	_tries = 0
	match _case:
		Case.PITCH, Case.NOBODY, Case.BAD_PITCH:
			_snap_forced()
		Case.LAST_GASP, Case.ORDINARY:
			_laterals_before = _game.get_stat(&"laterals")
			_fumbles_before = _game.get_stat(&"lateral_fumbles")
			_snap_cpu()
		Case.DONE:
			_report()


func _next_case() -> void:
	_case = (_case + 1) as Case
	_start_case()


# --- Forced pitches --------------------------------------------------------------

func _snap_forced() -> void:
	_tries += 1
	_reset_score(1, 120.0, 0, 0)
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	_pc.line_up(_run_play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_pitcher = null
	_taker = null
	_pitched_at = -1.0
	_worst = 0.0


## The back with the ball in his hands, the toss to him over: or null.
func _ready_carrier() -> Player:
	var carrier: Player = _pc.ball.carrier
	if _pc.ball_dead or not _pc.handoff_done or carrier == null or carrier != _pc.runner or not _pc.can_lateral(carrier):
		return null
	return carrier


func _retry_forced(what: String) -> void:
	if _tries >= 20:
		_failures.append("%s: the back never had the ball with a pitch to make in %d snaps" % [what, _tries])
		_next_case()
	else:
		_snap_forced()


func _tick_pitch() -> void:
	var tuning: Tuning = _game.tuning
	if _pitcher == null:
		var carrier: Player = _ready_carrier()
		if carrier == null or _pc.lateral_target(carrier) == null:
			if _pc.ball_dead or _pc.live_time > 4.0:
				_retry_forced("pitch")
			return
		var keep: float = tuning.lateral_fumble_chance
		var keep_grasp: float = tuning.lateral_grasp_fumble_add
		var keep_pressure: float = tuning.lateral_pressure_fumble_add
		var keep_long: float = tuning.lateral_long_fumble_add
		tuning.lateral_fumble_chance = 0.0
		tuning.lateral_grasp_fumble_add = 0.0
		tuning.lateral_pressure_fumble_add = 0.0
		tuning.lateral_long_fumble_add = 0.0
		_taker = _pc.lateral_target(carrier)
		var ahead: float = (_taker.position.x - carrier.position.x) * float(carrier.team.attack_dir)
		var before: int = _game.get_stat(&"laterals")
		var done: bool = _pc.do_lateral(carrier)
		tuning.lateral_fumble_chance = keep
		tuning.lateral_grasp_fumble_add = keep_grasp
		tuning.lateral_pressure_fumble_add = keep_pressure
		tuning.lateral_long_fumble_add = keep_long
		_pitcher = carrier
		_pitched_at = _pc.live_time
		_last = _pc.ball.position
		if not done:
			_failures.append("pitch: do_lateral said no with a teammate to pitch to")
		if _pc.ball.carrier != _taker:
			_failures.append("pitch: the ball did not go to the nearest teammate behind him")
		if _pitcher.has_ball:
			_failures.append("pitch: the pitcher still has the ball")
		if ahead > tuning.lateral_forward_slack:
			_failures.append("pitch: the teammate was %.1f yd ahead of him" % ahead)
		if _game.get_stat(&"laterals") != before + 1:
			_failures.append("pitch: the lateral was not counted")
		if _pc.phase != PlayController.Phase.RUN:
			_failures.append("pitch: the play is not a run after it")
		if _pc.can_lateral(_taker):
			_failures.append("pitch: the taker could pitch it on before it got to him")
		print("pitch        %s to %s, %.1f yd apart, %.1f yd behind" % [_pitcher.ratings.position, _taker.ratings.position,
				Vector2(_taker.position.x - _pitcher.position.x, _taker.position.z - _pitcher.position.z).length(), -ahead])
		return
	_worst = maxf(_worst, _pc.ball.position.distance_to(_last))
	_last = _pc.ball.position
	if _pc.ball_dead or _pc.live_time > _pitched_at + 0.8:
		# A sprinting carrier moves the ball about 0.2 yards a tick.
		if _worst >= 0.9:
			_failures.append("pitch: the ball jumped %.2f yd in one tick" % _worst)
		print("pitch        biggest ball step %.2f yd" % _worst)
		_next_case()


func _tick_nobody() -> void:
	var carrier: Player = _ready_carrier()
	if carrier == null:
		if _pc.ball_dead or _pc.live_time > 4.0:
			_retry_forced("nobody")
		return
	var dir: float = float(carrier.team.attack_dir)
	for mate: Player in carrier.team.players:
		if mate != carrier:
			mate.position.x = carrier.position.x + dir * 3.0
	var before: int = _game.get_stat(&"laterals")
	if _pc.lateral_target(carrier) != null:
		_failures.append("nobody: a teammate ahead of him was a target")
	if _pc.do_lateral(carrier):
		_failures.append("nobody: he pitched it with everybody ahead of him")
	if _pc.ball.carrier != carrier or _game.get_stat(&"laterals") != before:
		_failures.append("nobody: the ball left his hands")
	print("nobody       everybody ahead of him: no pitch")
	_next_case()


func _tick_bad_pitch() -> void:
	var carrier: Player = _ready_carrier()
	if carrier == null or _pc.lateral_target(carrier) == null:
		if _pc.ball_dead or _pc.live_time > 4.0:
			_retry_forced("bad pitch")
		return
	var tuning: Tuning = _game.tuning
	var keep: float = tuning.lateral_fumble_chance
	tuning.lateral_fumble_chance = 100.0
	var done: bool = _pc.do_lateral(carrier)
	tuning.lateral_fumble_chance = keep
	if not done:
		_failures.append("bad pitch: do_lateral said no")
	if _pc.phase != PlayController.Phase.LOOSE or _pc.ball.carrier != null:
		_failures.append("bad pitch: the ball is not loose")
	if _pc.fumbler != carrier:
		_failures.append("bad pitch: the pitcher is not the one who fumbled")
	if _game.get_stat(&"lateral_fumbles") < 1:
		_failures.append("bad pitch: the fumble was not counted")
	print("bad pitch    on the turf, %s's fumble" % carrier.ratings.position)
	_next_case()


# --- The CPU by itself -----------------------------------------------------------

func _snap_cpu() -> void:
	_snap += 1
	if _case == Case.LAST_GASP:
		# The second half, no time left, the offense a score behind.
		_reset_score(2, 0.0, 0, 7)
	else:
		_reset_score(1, 120.0, 0, 0)
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	if _case == Case.LAST_GASP:
		_game.clock = 0.0
	var offense: Array[OffensePlay] = _game.offense_playbook.plays
	var defense: Array[DefensePlay] = _game.defense_playbook.plays
	_pc.line_up(offense[_snap * 7 % offense.size()], defense[_snap * 5 % defense.size()])
	# The heave is its own answer to the last play: this is about what happens
	# once somebody has the ball in his hands.
	_pc.heave = false
	_pc.snap()
	_pc.state_machine.transition(&"Live")


func _tick_cpu() -> void:
	if not _pc.ball_dead and _pc.live_time < 40.0:
		return
	if _snap < _snaps:
		_snap_cpu()
		return
	var laterals: int = _game.get_stat(&"laterals") - _laterals_before
	var fumbles: int = _game.get_stat(&"lateral_fumbles") - _fumbles_before
	if _case == Case.LAST_GASP:
		print("last gasp    %d laterals in %d snaps (%d fumbled)" % [laterals, _snaps, fumbles])
		if laterals < maxi(_snaps / 4, 1):
			_failures.append("last gasp: only %d laterals in %d snaps with the clock run out" % [laterals, _snaps])
		if _game.get_stat(&"last_gasp_laterals") < laterals:
			_failures.append("last gasp: a lateral was not counted as one")
	else:
		print("ordinary     %d laterals in %d snaps (%d fumbled)" % [laterals, _snaps, fumbles])
		if laterals > _snaps / 4:
			_failures.append("ordinary: %d laterals in %d snaps is not rare" % [laterals, _snaps])
	_next_case()


func _reset_score(half: int, clock: float, offense_score: int, defense_score: int) -> void:
	_game.conversion = false
	_game.overtime = false
	_game.half = half
	_game.clock = clock
	_game.home.score = offense_score
	_game.away.score = defense_score


func _report() -> void:
	if _game.get_stat(&"forward_laterals") > 0:
		_failures.append("%d laterals went forward" % _game.get_stat(&"forward_laterals"))
	if _failures.is_empty():
		print("LATERAL CHECK PASSED")
	else:
		for failure: String in _failures:
			print("FAIL: %s" % failure)
		print("LATERAL CHECK FAILED")
	physics_frame.disconnect(_tick)
	quit(0 if _failures.is_empty() else 1)
