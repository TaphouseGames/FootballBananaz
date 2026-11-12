extends SceneTree
## Headless check of a pass thrown before the receiver's cut. On Curl Flat each
## wideout is thrown to while still on his way up the field, once with every
## placement:
##   normal  the ball comes down where the curl ends, and he is there for it
##   under   it comes down short of where he was as it was thrown, on the line
##           back to the quarterback, and he comes back for it
##   lead    it goes on up the field past the curl
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/route_throw_check.gd
## Optional user args after "--":
##   play=<text>   offensive play whose name contains the text (default "curl flat")
##   at=<yards>    how far downfield the wideout is when the ball is thrown (default 5)

const PLACEMENTS: Array[String] = ["normal", "under", "lead"]

var _game: Game
var _pc: PlayController
var _play: OffensePlay
var _play_filter: String = "curl flat"
var _throw_at: float = 5.0
var _case: int = -1
var _receiver: Player
var _route_end: Vector3 = Vector3.ZERO
var _thrown: bool = false
var _landing: Vector3 = Vector3.ZERO
var _qb_at_throw: Vector3 = Vector3.ZERO
var _receiver_at_throw: Vector3 = Vector3.ZERO
var _failed: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("play="):
			_play_filter = arg.trim_prefix("play=").to_lower()
		elif arg.begins_with("at="):
			_throw_at = float(arg.trim_prefix("at="))
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
		var tuning: Tuning = _game.tuning
		# The test is the quarterback, and every throw goes exactly where it is aimed.
		tuning.ai_qb_min_time = 1.0e9
		tuning.accuracy_error_low = 0.0
		tuning.accuracy_error_high = 0.0
		tuning.pass_scramble_error = 0.0
		tuning.pass_overlead_chance = 0.0
		tuning.pass_lead_error = 0.0
		tuning.pass_under_error = 0.0
		for play: OffensePlay in _game.offense_playbook.plays:
			if play.play_name.to_lower().contains(_play_filter):
				_play = play
		if _play == null:
			print("no play named like '%s'" % _play_filter)
			_finish(true)
			return
		_next()
		return
	if _receiver == null:
		return
	if not _thrown:
		if _pc.ball_dead or _pc.live_time > 6.0:
			_report(false, "never thrown")
			return
		var downfield: float = (_receiver.position.x - _pc.los_x) * _pc.off_dir
		if downfield >= _throw_at and _pc.can_pass():
			_thrown = true
			_qb_at_throw = _pc.qb.position
			_receiver_at_throw = _receiver.position
			@warning_ignore("integer_division")
			_pc.throw_ball(_receiver, 0.5, _placement(_case / 2))
			_landing = _pc.ball.target_point
		return
	if _pc.phase == PlayController.Phase.AIR and not _pc.ball_dead:
		return
	_judge()


func _placement(index: int) -> PlayController.Placement:
	match PLACEMENTS[index]:
		"under":
			return PlayController.Placement.UNDER
		"lead":
			return PlayController.Placement.LEAD
	return PlayController.Placement.NORMAL


func _judge() -> void:
	@warning_ignore("integer_division")
	var kind: String = PLACEMENTS[_case / 2]
	var from_end: float = _flat(_landing, _route_end)
	var deeper: float = (_landing.x - _route_end.x) * _pc.off_dir
	var closer: float = _flat(_qb_at_throw, _route_end) - _flat(_qb_at_throw, _landing)
	var gap: float = _flat(_receiver.position, _landing)
	var ok: bool = true
	match kind:
		"normal":
			ok = from_end <= 1.5 and gap <= 2.0
		"under":
			# Between where he was and the quarterback, whatever the route does.
			var line: float = _flat(_qb_at_throw, _receiver_at_throw)
			var nearer: float = line - _flat(_qb_at_throw, _landing)
			var off_line: float = _flat(_qb_at_throw, _landing) + _flat(_landing, _receiver_at_throw) - line
			ok = nearer >= _game.tuning.pass_under_min - 0.1 and off_line <= 0.1 and gap <= 2.5
			_report(ok, "%.1f yd short of where he was, toward the QB; receiver %.1f yd from the ball when it came down" % [nearer, gap])
			return
		"lead":
			ok = deeper >= 1.0
	_report(ok,"%.1f yd from the route end, %.1f deeper, %.1f nearer the QB; receiver %.1f yd from the ball when it came down" % [from_end, deeper, closer, gap])


func _report(ok: bool, text: String) -> void:
	@warning_ignore("integer_division")
	var kind: String = PLACEMENTS[_case / 2]
	_failed = _failed or not ok
	print("%-6s %s z=%+.0f  %s  %s" % [kind, _receiver.brain.off_assign.label, _receiver.brain.start_point.z, text, "ok" if ok else "FAILED"])
	_next()


func _next() -> void:
	_case += 1
	_receiver = null
	if _case >= PLACEMENTS.size() * 2:
		_finish(_failed)
		return
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	_pc.line_up(_play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	# The receivers whose route stops, in line-up order: one case each.
	var settlers: Array[Player] = []
	for player: Player in _pc.eligible:
		if player.brain.off_assign.settle and player.brain.route.size() > 0:
			settlers.append(player)
	if settlers.is_empty():
		print("%s has no route that stops" % _play.play_name)
		_finish(true)
		return
	_receiver = settlers[_case % settlers.size()]
	_route_end = _receiver.brain.route[_receiver.brain.route.size() - 1]
	_thrown = false


func _finish(failed: bool) -> void:
	physics_frame.disconnect(_tick)
	quit(1 if failed else 0)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
