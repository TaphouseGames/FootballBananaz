extends SceneTree
## Headless check of the flea flicker plays: the ball goes from the quarterback
## to the back and back again without a jump, nothing can be thrown until it is
## back, a pass follows, and a back whose quarterback is on the turf keeps the
## ball and runs with it.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/flea_flicker_check.gd
## Optional user args after "--":
##   snaps=<n>   CPU snaps per play (default 30)

const MAX_PLAY_TIME: float = 8.0

var _snaps: int = 30
var _game: Game
var _pc: PlayController
var _plays: Array[OffensePlay] = []
var _index: int = 0
var _snap: int = -1
## The last snap of each play is the one where the quarterback is knocked down.
var _forced: bool = false
var _knocked: bool = false
var _last: Vector3 = Vector3.ZERO
var _worst: float = 0.0
## Who has held the ball on this snap, in order.
var _holders: Array[Player] = []
var _returned: int = 0
var _passes: int = 0
var _yards: float = 0.0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("snaps="):
			_snaps = maxi(arg.trim_prefix("snaps=").to_int(), 1)
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
		_game.tuning.ai_scout_strength = 0.0
		for play: OffensePlay in _game.offense_playbook.plays:
			if play.flea_flicker:
				_plays.append(play)
		_expect(_plays.size() >= 2, "%d flea flicker plays in the playbook, wanted 2 or more" % _plays.size())
		if _plays.is_empty():
			_finish()
			return
		_next()
		return
	var play: OffensePlay = _plays[_index]
	var ball: Ball = _pc.ball
	if not _pc.ball_dead:
		if ball.carrier != null and (_holders.is_empty() or _holders[_holders.size() - 1] != ball.carrier):
			_holders.append(ball.carrier)
		if _pc.flicking():
			# Nothing leaves the quarterback's hand while the trick is on.
			_expect(not _pc.can_pass(), "%s: the quarterback can pass during the flea flicker" % play.play_name)
			_pc.throw_ball(_pc.eligible[0])
			_expect(_pc.phase != PlayController.Phase.AIR, "%s: a pass was thrown during the flea flicker" % play.play_name)
		if _forced and not _knocked and ball.carrier == _pc.runner:
			_knocked = true
			_pc.qb.knock_down(Vector3.ZERO, 3.0)
		# Only the two exchanges: the quarterback's hold changes when a fake ends,
		# as on any play-action play, and that is not the ball changing hands.
		if (ball.carrier == _pc.runner and _pc.phase == PlayController.Phase.POCKET) or _pc.flick_returning():
			_worst = maxf(_worst, ball.position.distance_to(_last))
	_last = ball.position
	if _pc.ball_dead or _pc.live_time > MAX_PLAY_TIME:
		_score(play)
		_next()


func _score(play: OffensePlay) -> void:
	_expect(_worst < 0.9, "%s: the ball jumped %.2f yd in one tick" % [play.play_name, _worst])
	var came_back: bool = _holders.size() >= 3 and _holders[0] == _pc.qb and _holders[1] == _pc.runner and _holders[2] == _pc.qb
	if _forced:
		_expect(_knocked, "%s: the back never got the ball on the forced snap" % play.play_name)
		_expect(not came_back, "%s: the ball went back to a quarterback on the turf" % play.play_name)
		_expect(_pc.passer == null, "%s: a pass was thrown with the quarterback down" % play.play_name)
		_expect(_game.get_stat(&"flea_flicker_kept") > 0, "%s: the back did not keep the ball" % play.play_name)
		return
	if came_back:
		_returned += 1
	if _pc.passer != null:
		_passes += 1
	if _pc.final_team == _pc.offense:
		_yards += (_pc.dead_spot_x - _pc.los_x) * _pc.off_dir


func _next() -> void:
	_snap += 1
	if _snap > _snaps:
		var play: OffensePlay = _plays[_index]
		print("%-18s  %d snaps: back to the quarterback %d, passes %d, %.1f yd a snap" % [play.play_name, _snaps, _returned, _passes, _yards / float(_snaps)])
		_expect(_returned >= _snaps * 0.6, "%s: the ball came back to the quarterback on %d of %d snaps" % [play.play_name, _returned, _snaps])
		_expect(_passes >= _snaps * 0.4, "%s: a pass on %d of %d snaps" % [play.play_name, _passes, _snaps])
		_index += 1
		_snap = 0
		_returned = 0
		_passes = 0
		_yards = 0.0
		if _index >= _plays.size():
			_finish()
			return
	_forced = _snap == _snaps
	_knocked = false
	_holders.clear()
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	_pc.line_up(_plays[_index], _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_last = _pc.ball.position
	_worst = 0.0


func _finish() -> void:
	physics_frame.disconnect(_tick)
	print("flea flickers %d, kept by the back %d" % [_game.get_stat(&"flea_flickers"), _game.get_stat(&"flea_flicker_kept")])
	for failure: String in _failures:
		print("FAIL: " + failure)
	print("flea_flicker_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message):
		_failures.append(message)
