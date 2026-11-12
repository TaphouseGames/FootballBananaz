extends SceneTree
## Headless check of what happens after a touchdown: the scorer stays and spikes
## the ball, his teammates gather round him, the other team stops, and a cheap
## shot lands about as often as Tuning says.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/celebration_check.gd
## Optional user args after "--":
##   scores=<n>   touchdowns to look at (default 12)
##   set=<name>:<value>[,<name>:<value>...]   override Tuning values for this run

const SPEED: float = 8.0

var _game: Game
var _pc: PlayController
var _failures: PackedStringArray = PackedStringArray()
var _overrides: Dictionary[String, float] = {}
var _scores_left: int = 12
var _scores: int = 0
## Where the trial is: 0 = snap it, 1 = put the carrier in the end zone,
## 2 = watching the celebration.
var _step: int = 0
var _scorer_start: Vector3 = Vector3.ZERO
var _sampled: bool = false
var _gathered_total: int = 0
var _mates_total: int = 0
var _floored: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("scores="):
			_scores_left = maxi(int(arg.trim_prefix("scores=")), 1)
		elif arg.begins_with("set="):
			for pair: String in arg.trim_prefix("set=").split(","):
				var parts: PackedStringArray = pair.split(":")
				if parts.size() == 2:
					_overrides[parts[0]] = float(parts[1])
	# See smoke_test.gd: the tick rate has to go up with the time scale.
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	for key: String in _overrides:
		_game.tuning.set(key, _overrides[key])
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
	var state: StringName = _pc.state_machine.current_name()
	match _step:
		0:
			_snap()
			_step = 1
		1:
			var carrier: Player = _pc.ball.carrier
			if carrier == null:
				_step = 0
				return
			var dir: float = float(carrier.team.attack_dir)
			carrier.position = Vector3(_game.tuning.goal_x(carrier.team.attack_dir) + dir * 3.0, 0.0, 0.0)
			_scorer_start = carrier.position
			_sampled = false
			_step = 2
		2:
			if state == &"Live":
				return
			if state == &"Scored":
				if not _sampled and _pc.state_machine.current.time_in_state >= _game.tuning.scored_banner_time - 0.2:
					_sample()
				return
			if not _sampled:
				_failures.append("score %d: the play ended in state '%s', not a touchdown" % [_scores + 1, state])
			_scores += 1
			if _scores >= _scores_left:
				_finish()
			else:
				_step = 0


## Home, first and goal from the 8.
func _snap() -> void:
	var team: Team = _game.home
	_game.conversion = false
	_game.half = 1
	_game.clock = 100.0
	_game.start_drive(team, _game.tuning.yard_to_x(team.attack_dir, 92.0))
	_pc.line_up(_game.offense_playbook.plays[0], _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")


## The picture just before the celebration is over.
func _sample() -> void:
	_sampled = true
	var scorer: Player = _pc.scorer
	if scorer == null:
		_failures.append("score %d: nobody was the scorer" % (_scores + 1))
		return
	var ring: float = _game.tuning.celebration_ring_radius
	var hit: bool = false
	var gathered: int = 0
	for mate: Player in scorer.team.players:
		hit = hit or mate.is_down()
		if mate != scorer and _flat(mate.position, scorer.position) <= ring + 1.5:
			gathered += 1
	_gathered_total += gathered
	_mates_total += scorer.team.players.size() - 1
	if hit:
		_floored += 1
	elif _flat(scorer.position, _scorer_start) > 4.0:
		_failures.append("score %d: the scorer wandered %.1f yd off" % [_scores + 1, _flat(scorer.position, _scorer_start)])
	if scorer.has_ball and not hit:
		_failures.append("score %d: the scorer never spiked the ball" % (_scores + 1))
	# Nobody on the other side is still running: the most any of them does is
	# walk, off on his own or out of the huddle (about 2.7 yd/s).
	for loser: Player in scorer.team.opponent.players:
		if not loser.is_down() and loser.velocity.length() > 3.5 and loser.brain.cheap_shot_delay < 0.0:
			_failures.append("score %d: a beaten player was still running at %.1f yd/s" % [_scores + 1, loser.velocity.length()])


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _finish() -> void:
	physics_frame.disconnect(_tick)
	var shots: int = _game.get_stat(&"cheap_shots")
	var chance: float = _game.tuning.cheap_shot_chance
	var share: float = float(_gathered_total) / maxf(float(_mates_total), 1.0)
	print("%d scores: %d spikes, %.0f%% of teammates in the huddle at the end, %d cheap shots landed (chance %.2f), %d ended with a celebrating player on the turf" % [_scores, _game.get_stat(&"spikes"), share * 100.0, shots, chance, _floored])
	if share < 0.7:
		_failures.append("only %.0f%% of the scorer's teammates reached him" % (share * 100.0))
	if _game.get_stat(&"spikes") < _scores - shots:
		_failures.append("%d spikes in %d scores" % [_game.get_stat(&"spikes"), _scores])
	if chance <= 0.0 and shots > 0:
		_failures.append("%d cheap shots with the chance at zero" % shots)
	if chance >= 1.0 and float(shots) < 0.6 * float(_scores):
		_failures.append("only %d cheap shots landed in %d scores with the chance at one" % [shots, _scores])
	if _failures.is_empty():
		print("CELEBRATION CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("FAILED: ", failure)
		quit(1)
