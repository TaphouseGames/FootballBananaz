extends SceneTree
## Headless check that the mascots are off the field during a play, and of the
## wall round it. Lines a play up at several spots and lets the CPU play it:
## neither team's mascot is to be seen, is one of the players on the field or
## of its team, or has the ball, unless its team has just scored (then it is a
## guest at the party: see celebration_check.gd), and nobody gets past the
## wall. Then a player is put past the wall (he is brought back inside it), and
## a ball is dropped over the stands (it comes to rest on them, not under them).
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/mascot_check.gd [-- plays=N]

## Yards from its own goal line each play starts at, in turn.
const YARDS: PackedFloat32Array = [30.0, 5.0, 92.0, 50.0, 70.0, 12.0]
## Physics ticks a play, or one of the checks after them, may take.
const STUCK_TICKS: int = 1500

enum Step { PLAYS, WALL, BALL, DONE }

var _game: Game
var _pc: PlayController
var _plays: int = 12
var _played: int = 0
var _step: int = Step.PLAYS
var _ticks: int = 0
var _lined_up: bool = false
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("plays="):
			_plays = maxi(int(arg.trim_prefix("plays=")), 1)
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
		return
	_ticks += 1
	match _step:
		Step.PLAYS:
			_tick_play()
		Step.WALL:
			_tick_wall()
		Step.BALL:
			_tick_ball()
		Step.DONE:
			_finish()


# --- Plays -------------------------------------------------------------------------

func _tick_play() -> void:
	if not _lined_up:
		_line_up(YARDS[_played % YARDS.size()], _played % 2 == 0)
		_check_line_up()
		return
	# One flattened against the wall is right up to it, nearer than side_limit().
	for player: Player in _pc.players:
		if Stadium.wall_distance(_game.tuning, player.position.x, player.position.z) > -PlayerFall.SPLAT_GAP + 0.01:
			_fail("%s is %.2f yd from the middle, in the wall" % [player.ratings.display_name, absf(player.position.z)])
	for team: Team in [_game.home, _game.away]:
		if team.mascot.has_ball or _pc.ball.carrier == team.mascot:
			_fail("the %s mascot has the ball" % team.short_name)
		# Only a touchdown brings one on, and only the scorer's.
		var party: bool = _pc.ball_dead and _pc.result == PlayController.Result.TOUCHDOWN and _pc.scorer != null and _pc.scorer.team == team
		if not party:
			_check_away(team, "during a play")
	if _pc.ball_dead or _ticks > STUCK_TICKS:
		_played += 1
		_lined_up = false
		if _played >= _plays:
			_next(Step.WALL)


func _line_up(yard: float, home_ball: bool) -> void:
	var team: Team = _game.home if home_ball else _game.away
	_game.conversion = false
	_game.half = 1
	_game.clock = 100.0
	_game.start_drive(team, _game.tuning.yard_to_x(team.attack_dir, yard))
	var plays: Array = _game.offense_playbook.plays
	_pc.line_up(plays[_played % plays.size()], _game.defense_playbook.plays[_played % _game.defense_playbook.plays.size()])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_lined_up = true
	_ticks = 0


## At the line-up there are the two eights and nobody else, whatever the play
## before ended in.
func _check_line_up() -> void:
	if _pc.players.size() != 16:
		_fail("%d on the field at the line-up, not the two eights" % _pc.players.size())
	for team: Team in [_game.home, _game.away]:
		_check_away(team, "at the line-up")


## `team`'s mascot is off the field: not to be seen and nobody's player.
func _check_away(team: Team, when: String) -> void:
	var mascot: Mascot = team.mascot
	var who: String = "the %s mascot" % team.short_name
	if mascot.visible:
		_fail("%s is to be seen %s" % [who, when])
	if _pc.players.has(mascot):
		_fail("%s is on the field %s" % [who, when])
	if team.players.has(mascot) or team.players.size() != 8:
		_fail("%s is one of its team's %d players %s" % [who, team.players.size(), when])


# --- The wall ----------------------------------------------------------------------

func _tick_wall() -> void:
	var tuning: Tuning = _game.tuning
	var stadium: Stadium = _game.field.stadium
	var player: Player = _game.away.players[0]
	if _ticks == 1:
		player.position = Vector3(50.0, 0.0, tuning.half_width() + 6.0)
		return
	if _ticks < 4:
		return
	if absf(player.position.z) > tuning.side_limit() + 0.01:
		_fail("a player put 6 yd past the sideline stayed at z %.1f" % player.position.z)
	if tuning.side_limit() <= tuning.half_width():
		_fail("nobody can step out of bounds: the wall stops them at the line")
	if tuning.stadium_enabled:
		var face: float = tuning.half_width() + tuning.wall_gap
		if tuning.wall_gap >= 1.0:
			_fail("the wall is %.1f yd off the lines" % tuning.wall_gap)
		if stadium.surface_height(50.0, face - 0.1) != 0.0 or stadium.surface_height(50.0, -face + 0.1) != 0.0:
			_fail("the turf just inside the wall is not at 0")
		if stadium.surface_height(50.0, face + 0.1) < Stadium.WALL_HEIGHT - 0.01 or stadium.surface_height(50.0, -face - 0.1) < Stadium.WALL_HEIGHT - 0.01:
			_fail("no wall just past the sidelines")
		var end: float = tuning.field_length + tuning.end_zone_depth + tuning.wall_gap
		if stadium.surface_height(end - 0.1, 0.0) != 0.0 or stadium.surface_height(end + 0.1, 0.0) < Stadium.WALL_HEIGHT - 0.01:
			_fail("no wall just past the right end line")
		if stadium.surface_height(-tuning.end_zone_depth - tuning.wall_gap - 0.1, 0.0) < Stadium.WALL_HEIGHT - 0.01:
			_fail("no wall just past the left end line")
		for fan: Vector3 in stadium.fan_positions:
			if absf(fan.z) < face and fan.x > -tuning.end_zone_depth - tuning.wall_gap and fan.x < end:
				_fail("a fan sits inside the wall at (%.1f, %.1f)" % [fan.x, fan.z])
				break
	_next(Step.BALL)


func _tick_ball() -> void:
	var tuning: Tuning = _game.tuning
	if not tuning.stadium_enabled:
		_next(Step.DONE)
		return
	var ball: Ball = _game.ball
	var over: Vector3 = Vector3(50.0, 9.0, tuning.half_width() + 5.0)
	if _ticks == 1:
		# The play is stopped, so that nothing else moves the ball.
		_pc.process_mode = Node.PROCESS_MODE_DISABLED
		ball.position = over
		ball.spike(Vector3.ZERO)
		return
	ball.integrate(1.0 / 60.0)
	if _ticks < 240:
		return
	var under: float = _game.field.stadium.surface_height(ball.position.x, ball.position.z)
	if under < Stadium.FIRST_ROW_HEIGHT or absf(ball.position.y - under - Ball.GROUND_HEIGHT) > 0.05:
		_fail("a ball dropped over the stands is at height %.2f where they are %.2f high" % [ball.position.y, under])
	_next(Step.DONE)


# --- Helpers -----------------------------------------------------------------------

func _next(step: int) -> void:
	_step = step
	_ticks = 0


func _fail(what: String) -> void:
	if not _failures.has(what):
		_failures.append(what)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	print("Played %d plays with the mascots off the field." % _played)
	if _failures.is_empty():
		print("mascot_check PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("FAIL: %s" % failure)
		print("mascot_check FAILED")
		quit(1)
