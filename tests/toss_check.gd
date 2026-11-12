extends SceneTree
## Headless check of the handoff on every run play: prints how far apart the
## quarterback and the runner are when the ball changes hands, and how far the
## ball moves per tick while it does. A big jump in one tick is a teleport.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/toss_check.gd

var _game: Game
var _pc: PlayController
var _plays: Array[OffensePlay] = []
var _index: int = -1
var _last: Vector3 = Vector3.ZERO
var _worst: float = 0.0
var _gap: float = 0.0
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
		for play: OffensePlay in _game.offense_playbook.plays:
			if play.is_run:
				_plays.append(play)
		_next()
		return
	var ball: Ball = _pc.ball
	if _pc.handoff_done and _gap < 0.0:
		_gap = Vector2(_pc.qb.position.x - _pc.runner.position.x, _pc.qb.position.z - _pc.runner.position.z).length()
	# Only around the exchange: at the snap the ball comes up off the turf.
	if _pc.live_time >= _plays[_index].handoff_delay - 0.1:
		_worst = maxf(_worst, ball.position.distance_to(_last))
	_last = ball.position
	if _pc.ball_dead or _pc.live_time > _plays[_index].handoff_delay + 0.65:
		# A sprinting carrier moves the ball about 0.2 yards a tick.
		var ok: bool = _worst < 0.9
		_failed = _failed or not ok
		print("%-12s  qb-runner gap %.1f yd   tosses %d   biggest ball step %.2f yd  %s" % [_plays[_index].play_name, _gap, _game.get_stat(&"tosses"), _worst, "ok" if ok else "TELEPORT"])
		_next()


func _next() -> void:
	_index += 1
	if _index >= _plays.size():
		physics_frame.disconnect(_tick)
		quit(1 if _failed else 0)
		return
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	_pc.line_up(_plays[_index], _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_last = _pc.ball.position
	_worst = 0.0
	_gap = -1.0
