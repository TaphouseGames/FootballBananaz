extends SceneTree
## Headless check of the catch chance of a receiver diving at a pass: as good as
## any catch when he is open, clearly worse with a defender nearby, and a long
## shot with two close to him. A catch on his feet is not affected.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/dive_catch_check.gd

var _game: Game
var _pc: PlayController
var _receiver: Player
var _point: Vector3
var _side: Vector3
var _far: Vector3
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	physics_frame.disconnect(_tick)
	_pc = _game.play_controller
	var tuning: Tuning = _game.tuning
	# The number itself, whoever the receiver happens to be.
	tuning.catch_scale_low = 1.0
	tuning.catch_scale_high = 1.0

	var team: Team = _game.home
	var dir: float = float(team.attack_dir)
	_game.start_drive(team, tuning.yard_to_x(team.attack_dir, 30.0))
	var play: OffensePlay = _game.offense_playbook.plays[0]
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if not candidate.is_run:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")

	# The receiver alone at midfield, the ball coming down two yards ahead of him.
	_receiver = _pc.eligible[0]
	var mid: float = tuning.field_length * 0.5
	_far = Vector3(mid - dir * 35.0, 0.0, -30.0)
	for player: Player in _pc.players:
		player.frozen = true
		player.velocity = Vector3.ZERO
		if player != _receiver and player != _pc.qb:
			player.position = _far + Vector3(0.0, 0.0, float(player.index) * 2.0)
	_pc.qb.position = Vector3(mid - dir * 20.0, 0.0, 0.0)
	_receiver.position = Vector3(mid, 0.0, 0.0)
	_receiver.facing = Vector3(dir, 0.0, 0.0)
	_pc.ball.thrower = _pc.qb
	_point = _receiver.position + Vector3(dir * 2.0, 0.0, 0.0)
	_side = Vector3(0.0, 0.0, 1.0)

	var standing_open: float = _chance([])
	var standing_one: float = _chance([2.5])
	var old_one: float = tuning.catch_base_chance - (1.0 - 2.5 / tuning.cover_radius) * tuning.cover_penalty
	print("on his feet   open %.2f   one defender at 2.5 yd %.2f (was %.2f)" % [standing_open, standing_one, old_one])
	_expect(is_equal_approx(standing_open, tuning.catch_base_chance), "an open catch on his feet changed")
	_expect(absf(standing_one - old_one) < 0.001, "a covered catch on his feet changed")

	_receiver.frozen = false
	_receiver.start_dive(Vector3(dir, 0.0, 0.0))
	_receiver.frozen = true
	_expect(_receiver.state == Player.State.DIVING and _receiver.dive_reach_timer > 0.0, "the dive did not start")
	var open: float = _chance([])
	var far_one: float = _chance([4.0])
	var one: float = _chance([2.5])
	var tight_one: float = _chance([1.0])
	var two: float = _chance([2.5, -2.5])
	var tight_two: float = _chance([1.0, -1.0])
	var at_ball: float = _chance_at([_point + _side * 1.0])
	var down: float = _chance([1.0], true)
	print("diving        open %.2f   one at 4 yd %.2f   at 2.5 yd %.2f   at 1 yd %.2f   two at 2.5 yd %.2f   two at 1 yd %.2f" % [open, far_one, one, tight_one, two, tight_two])
	print("diving        one defender a yard from the ball %.2f   one lying on the turf next to him %.2f" % [at_ball, down])
	_expect(open >= 0.9, "an open dive is caught only %.2f of the time" % open)
	_expect(far_one < open and far_one > one, "a defender 4 yd off does not count for a little")
	_expect(one <= open - 0.25, "one defender at 2.5 yd only takes it from %.2f to %.2f" % [open, one])
	_expect(one < standing_one, "a covered dive is no harder than the catch on his feet")
	_expect(tight_one < one, "a closer defender makes it no harder")
	_expect(two <= one - 0.25 and two < 0.3, "two defenders at 2.5 yd leave it at %.2f" % two)
	_expect(tight_two <= two, "two defenders right on him are easier than two nearby")
	_expect(at_ball < one, "a defender at the ball counts for less than one near the receiver")
	_expect(is_equal_approx(down, open), "a defender on the turf counts")

	if _failures.is_empty():
		print("DIVE CATCH CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("DIVE CATCH CHECK FAILED: %s" % failure)
		quit(1)


## The catch chance with a defender at each of `offsets`: yards to the side of
## the receiver, the sign giving the side.
func _chance(offsets: Array, knocked_down: bool = false) -> float:
	var spots: Array[Vector3] = []
	for offset: float in offsets:
		spots.append(_receiver.position + _side * offset)
	return _chance_at(spots, knocked_down)


func _chance_at(spots: Array[Vector3], knocked_down: bool = false) -> float:
	var defenders: Array[Player] = _pc.defense.players
	for i: int in defenders.size():
		defenders[i].position = spots[i] if i < spots.size() else _far + Vector3(0.0, 0.0, float(defenders[i].index) * 2.0)
	var saved: Player.State = defenders[0].state
	if knocked_down:
		defenders[0].state = Player.State.DOWN
	var chance: float = _pc.catch_chance(_receiver, _point)
	defenders[0].state = saved
	return chance


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
