extends SceneTree
## Headless check of a dive into men who are not the ball carrier, while the
## ball is live (PlayController._dive_into):
## - a man who is blocking mostly holds: the dive flattens him with
##   Tuning.dive_blocker_chance times the diver's strength and his blocking
##   rating, and otherwise the diver bounces off and the blocker stands;
## - a man who is not blocking always goes down;
## - one dive takes out one man: through a row of three, one goes down;
## - a dive into a row of blockers that hold puts nobody down but the diver;
## - after the whistle a dive still goes through all of them.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/dive_block_check.gd
## A few seconds.

enum Kind { ROLL, WHISTLE, ROW, STUFFED }

const ROLLS: int = 300
const STUCK_TICKS: int = 300
## Ticks of a row trial: the men are put in place, the dive starts, and it is
## looked at once the diver has landed.
const PLACE_TICK: int = 3
const DIVE_TICK: int = 6
const LOOK_TICK: int = 50
## Yards from the diver to each man of the row, along the dive.
const ROW: Array[float] = [1.8, 2.9, 3.4]
## And to the side of it, so that they have room to stand.
const ROW_SIDE: Array[float] = [0.0, 0.6, -0.7]

var _game: Game
var _pc: PlayController
var _tuning: Tuning
var _person: Team
var _cpu: Team
var _trials: Array[Dictionary] = []
var _trial: int = -1
var _ticks: int = 0
var _dir: float = 1.0
var _diver: Player
var _row: Array[Player] = []
var _before: Dictionary[StringName, int] = {}
var _chance: float = 0.0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _build_trials() -> void:
	for pair: Vector2i in [Vector2i(90, 20), Vector2i(50, 50), Vector2i(20, 90)]:
		_trials.append({"kind": Kind.ROLL, "label": "strength %d on blocking %d" % [pair.x, pair.y], "strength": pair.x, "blocking": pair.y, "set": true})
	_trials.append({"kind": Kind.ROLL, "label": "a man not blocking", "strength": 20, "blocking": 90, "set": false})
	_trials.append({"kind": Kind.WHISTLE, "label": "after the whistle"})
	_trials.append({"kind": Kind.ROW, "label": "row of three"})
	_trials.append({"kind": Kind.STUFFED, "label": "row of blockers that hold"})


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
		_tuning = _game.tuning
		_person = _game.human.team
		if _person == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_cpu = _person.opponent
		_chance = _tuning.dive_blocker_chance
		_build_trials()
		_next()
		return
	_ticks += 1
	if _ticks > STUCK_TICKS:
		_fail("never finished")
		_next()
		return
	var trial: Dictionary = _trials[_trial]
	match trial["kind"]:
		Kind.ROLL:
			_tick_roll(trial)
		Kind.WHISTLE:
			_tick_whistle()
		Kind.ROW, Kind.STUFFED:
			_tick_row(trial)


## Rolls the dive into one man many times over in one tick.
func _tick_roll(trial: Dictionary) -> void:
	var blocker: Player = _row[0]
	var is_set: bool = trial["set"]
	_diver.ratings.strength = trial["strength"]
	blocker.ratings.blocking = trial["blocking"]
	var spot: Vector3 = _diver.position
	var ahead: Vector3 = Vector3(-_dir, 0.0, 0.0)
	var wins: int = 0
	for i: int in ROLLS:
		_diver.reset_for_play(spot, ahead)
		_diver.state = Player.State.DIVING
		_diver.velocity = ahead * _tuning.dive_speed
		blocker.reset_for_play(spot + ahead, -ahead)
		blocker.is_blocking = is_set
		_pc._dive_into(_diver, blocker, ahead)
		if blocker.is_down():
			wins += 1
			_expect(_diver.dive_spent and not _diver.is_down(), "flattened his man and the dive is not spent, or he is down himself")
			_expect(_diver.velocity.length() < _tuning.dive_speed * (_tuning.dive_hit_speed_keep + 0.01), "the dive kept its speed through the man")
		else:
			_expect(_diver.is_down(), "the blocker held and the diver did not bounce off")
			_expect(blocker.is_blocking, "the blocker held and is no longer blocking")
	_diver.reset_for_play(spot, ahead)
	blocker.reset_for_play(spot + ahead, -ahead)
	var want: float = 1.0
	if is_set:
		want = _chance
		want *= PlayerRatings.blend(trial["strength"], _tuning.dive_blocker_strength_scale_low, _tuning.dive_blocker_strength_scale_high)
		want *= PlayerRatings.blend(trial["blocking"], _tuning.dive_blocker_blocking_scale_low, _tuning.dive_blocker_blocking_scale_high)
		want = clampf(want, 0.0, 1.0)
	var share: float = float(wins) / float(ROLLS)
	print("%-28s flattened %3d of %d: %.0f%% (should be %.0f%%)" % [trial["label"], wins, ROLLS, share * 100.0, want * 100.0])
	if is_set:
		_expect(absf(share - want) <= 0.09, "%.0f%% flattened, should be near %.0f%%" % [share * 100.0, want * 100.0])
	else:
		_expect(wins == ROLLS, "a man who is not blocking held against %d dives" % (ROLLS - wins))
	_expect(_gained(&"dive_stuffs") == ROLLS - wins, "the dive_stuffs counter says %d, there were %d" % [_gained(&"dive_stuffs"), ROLLS - wins])
	_next()


## With the ball dead one dive goes through every man in its way, blocking or not.
func _tick_whistle() -> void:
	var ahead: Vector3 = Vector3(-_dir, 0.0, 0.0)
	_diver.state = Player.State.DIVING
	_diver.dive_spent = false
	var live: bool = _pc.ball_dead
	_pc.ball_dead = true
	for man: Player in _row:
		man.is_blocking = true
		_pc._check_hit(_diver, man, ahead, 1.0)
	_pc.ball_dead = live
	var down: int = _down()
	print("%-28s %d of %d down" % ["after the whistle", down, _row.size()])
	_expect(down == _row.size(), "%d of %d down: a late dive should go through them all" % [down, _row.size()])
	_expect(_gained(&"dive_stuffs") == 0, "a blocker held against a late dive")
	_next()


## A real dive by the person's defender through three men standing in a row.
func _tick_row(trial: Dictionary) -> void:
	var stuffed: bool = trial["kind"] == Kind.STUFFED
	var ahead: Vector3 = Vector3(-_dir, 0.0, 0.0)
	_game.human.set_controlled(_diver)
	if _ticks == PLACE_TICK:
		for i: int in _row.size():
			_row[i].position = _diver.position + ahead * ROW[i] + Vector3(0.0, 0.0, ROW_SIDE[i])
			_row[i].facing = -ahead
			# Thinking for themselves from here: with the diver this close they
			# block him (a frozen man is never blocking).
			_row[i].frozen = false
	elif _ticks == DIVE_TICK:
		for man: Player in _row:
			_expect(man.is_blocking, "a man of the row stopped blocking before the dive")
		_diver.turbo = 1.0
		_pc.do_dive(_diver, ahead)
		_expect(_diver.state == Player.State.DIVING, "the dive did not start")
	elif _ticks == LOOK_TICK:
		var down: int = _down()
		print("%-28s %d of %d down, %d bounced off" % [trial["label"], down, _row.size(), _gained(&"dive_stuffs")])
		_expect(not _pc.ball_dead, "the play ended in the middle of the trial")
		if stuffed:
			_expect(down == 0, "%d blockers down with no chance of it" % down)
			_expect(_gained(&"dive_stuffs") == 1, "bounced off %d times, should be once" % _gained(&"dive_stuffs"))
			_expect(not _row[0].is_down() and _row[0].is_blocking, "the blocker who held is not blocking any more")
		else:
			_expect(down == 1, "%d men down from one dive, should be 1" % down)
			_expect(_row[0].is_down(), "the first man in the way is not the one who went down")
			_expect(_gained(&"dive_stuffs") == 0, "bounced off a man with every chance of flattening him")
		_next()


func _down() -> int:
	var down: int = 0
	for man: Player in _row:
		if man.is_down():
			down += 1
	return down


func _gained(stat: StringName) -> int:
	return _game.get_stat(stat) - _before.get(stat, 0)


func _next() -> void:
	_trial += 1
	if _trial >= _trials.size():
		_finish()
		return
	var kind: Kind = _trials[_trial]["kind"]
	_dir = float(_cpu.attack_dir)
	var middle: float = _tuning.field_length * 0.5
	# A row trial is decided beforehand: every man goes down, or every blocker holds.
	match kind:
		Kind.ROW:
			_tuning.dive_blocker_chance = 100.0
		Kind.STUFFED:
			_tuning.dive_blocker_chance = 0.0
		_:
			_tuning.dive_blocker_chance = _chance

	_game.human.team = _person
	_game.start_drive(_cpu, _tuning.yard_to_x(_cpu.attack_dir, 30.0))
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.is_run and not candidate.play_action:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_ticks = 0
	_before[&"dive_stuffs"] = _game.get_stat(&"dive_stuffs")

	# Everybody well away from the dive, standing still, the back with the ball
	# off by himself.
	for player: Player in _pc.players:
		player.heal()
		player.position = Vector3(middle + _dir * 30.0, 0.0, float(player.index) * 2.0 - 30.0)
		player.velocity = Vector3.ZERO
		player.frozen = true
	var back: Player = _pc.runner
	back.position = Vector3(middle + _dir * 30.0, 0.0, 22.0)
	_pc.handoff_done = true
	_pc.phase = PlayController.Phase.RUN
	_pc.ball.give_to(back)

	_diver = _person.players[0]
	_diver.ratings = _diver.ratings.duplicate() as PlayerRatings
	_diver.position = Vector3(middle, 0.0, 0.0)
	_diver.facing = Vector3(-_dir, 0.0, 0.0)
	_diver.frozen = false
	_game.human.set_controlled(_diver)

	_row.clear()
	for player: Player in _cpu.players:
		if player != back and player != _pc.qb and _row.size() < ROW.size():
			player.ratings = player.ratings.duplicate() as PlayerRatings
			_row.append(player)
	if kind == Kind.WHISTLE:
		for i: int in _row.size():
			_row[i].position = _diver.position + Vector3(-_dir * ROW[i], 0.0, 0.0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	var line: String = "%s (trial %d): %s" % [_trials[_trial]["label"], _trial, what]
	if not _failures.has(line):
		_failures.append(line)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	_tuning.dive_blocker_chance = _chance
	if _failures.is_empty():
		print("DIVE BLOCK CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("DIVE BLOCK CHECK FAILED: %s" % failure)
		quit(1)
