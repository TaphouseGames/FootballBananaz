extends SceneTree
## Headless check of run blocking at the hole (PlayController._roll_drive): the
## inside runs are played CPU against CPU with a strong offensive line against
## a weak defensive line, the other way round, and with both as the rosters
## have them, with and without the hole. A good line has to win most of its
## blocks at the hole and a bad one hardly any, and the hole has to be
## clearly wider behind the good one: the width is the gap between the nearest
## defenders standing at the line either side of the hole, a second after the
## snap. The yards a run are printed to compare, not judged: they
## swing by a yard or more from one run of this check to the next (216 runs a
## case).
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/run_hole_check.gd
## Optional user args after "--":
##   snaps=<n>   snaps per play and defense in each case (default 6: about 4 minutes)
##   set=<name>:<value>[,<name>:<value>...]   override Tuning values for this run

const SPEED: float = 16.0
const MAX_PLAY_TIME: float = 20.0
const CAP: float = 30.0
const DEFENSES: PackedStringArray = ["Man Cover 1", "Cover 3", "Zone Cover 2", "Cover 1 Spy"]
const STRONG: int = 90
## Seconds after the snap that the hole is measured, and the widest it counts as.
const MEASURE_TIME: float = 1.0
const MAX_WIDTH: float = 10.0
const WEAK: int = 35
## What a case is: [name, the offensive line's blocking, the defensive line's
## strength (-1 = as the roster has it), the hole on].
const CASES: Array[Array] = [
	["rosters, no hole", -1, -1, false],
	["rosters, hole", -1, -1, true],
	["strong line", STRONG, WEAK, true],
	["weak line", WEAK, STRONG, true],
]

var _snaps: int = 6
var _overrides: Dictionary[String, String] = {}
var _game: Game
var _pc: PlayController
var _plays: Array[OffensePlay] = []
var _defenses: Array[DefensePlay] = []
var _case: int = -1
var _job: int = 0
var _left: int = 0
var _live: bool = false
var _hole_width: float = 0.0
var _own: Dictionary[Player, PlayerRatings] = {}
## Per case: yards, snaps, and per play name the yards.
var _yards: PackedFloat32Array = PackedFloat32Array()
var _count: PackedInt32Array = PackedInt32Array()
var _blocks: PackedInt32Array = PackedInt32Array()
var _won: PackedInt32Array = PackedInt32Array()
var _by_play: Array[Dictionary] = []
## Per case: the room the back had at the line, summed, and how often measured.
var _room: PackedFloat32Array = PackedFloat32Array()
var _room_count: PackedInt32Array = PackedInt32Array()
var _measured: bool = false
var _hole_z: float = 0.0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("snaps="):
			_snaps = maxi(arg.trim_prefix("snaps=").to_int(), 1)
		elif arg.begins_with("set="):
			for pair: String in arg.trim_prefix("set=").split(","):
				_overrides[pair.get_slice(":", 0)] = pair.get_slice(":", 1)
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_begin()
		return
	if _case >= CASES.size():
		return
	if not _live:
		_start_play()
		return
	if not _measured and _pc.live_time >= MEASURE_TIME:
		_measure()
	if _pc.ball_dead:
		_record()
	elif _pc.live_time > MAX_PLAY_TIME:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)


func _begin() -> void:
	_pc = _game.play_controller
	_game.tuning.ai_scout_strength = 0.0
	for key: String in _overrides:
		_game.tuning.set(key, str_to_var(_overrides[key]))
		print("tuning.%s = %s" % [key, _game.tuning.get(key)])
	_hole_width = _game.tuning.hole_max_width
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	# The run plays that have a hole, found by lining each one up.
	for play: OffensePlay in _game.offense_playbook.plays:
		if not play.is_run or play.goal_line:
			continue
		_pc.line_up(play, _game.defense_playbook.plays[0])
		if _pc.has_run_hole:
			_plays.append(play)
	for play: DefensePlay in _game.defense_playbook.plays:
		if DEFENSES.has(play.play_name):
			_defenses.append(play)
	_expect(_plays.size() >= 5, "only %d run plays have a hole" % _plays.size())
	_expect(_defenses.size() == DEFENSES.size(), "a defense of the test is not in the playbook")
	var names: PackedStringArray = PackedStringArray()
	for play: OffensePlay in _plays:
		names.append(play.play_name)
	print("runs with a hole: %s" % ", ".join(names))
	for team: Team in [_game.home, _game.away]:
		for player: Player in team.players:
			_own[player] = player.ratings
	if _plays.is_empty() or _defenses.is_empty():
		_finish()
		return
	_next_case()


func _next_case() -> void:
	_case += 1
	if _case >= CASES.size():
		_finish()
		return
	var case: Array = CASES[_case]
	_game.tuning.hole_max_width = _hole_width if bool(case[3]) else -1.0
	# The three linemen of each side are players 1 to 3 (see Roster).
	for team: Team in [_game.home, _game.away]:
		for i: int in range(1, 4):
			var player: Player = team.players[i]
			var ratings: PlayerRatings = _own[player].duplicate() as PlayerRatings
			if int(case[1]) >= 0:
				ratings.blocking = int(case[1])
				ratings.strength = int(case[2])
			player.ratings = ratings
	_yards.append(0.0)
	_count.append(0)
	_blocks.append(0)
	_won.append(0)
	_by_play.append({})
	_room.append(0.0)
	_room_count.append(0)
	_job = 0
	_left = _snaps
	_game.stats.clear()


func _start_play() -> void:
	# The home team has the ball every time, so one line is always the offense's.
	_game.clock = 1.0e6
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	@warning_ignore("integer_division")
	var play: OffensePlay = _plays[_job / _defenses.size()]
	# Where the play is aimed, read with the hole on whatever the case.
	var width: float = _game.tuning.hole_max_width
	_game.tuning.hole_max_width = _hole_width
	_pc.line_up(play, _defenses[_job % _defenses.size()])
	_hole_z = _pc.run_hole.z
	_game.tuning.hole_max_width = width
	_pc.line_up(play, _defenses[_job % _defenses.size()])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_live = true
	_measured = false


## How wide the hole is: from the nearest defender on his feet at the line on
## one side of it to the nearest on the other.
func _measure() -> void:
	_measured = true
	var left: float = MAX_WIDTH * 0.5
	var right: float = MAX_WIDTH * 0.5
	for defender: Player in _pc.defense.players:
		var depth: float = (defender.position.x - _pc.los_x) * _pc.off_dir
		if defender.is_down() or depth < -2.0 or depth > 2.5:
			continue
		var across: float = defender.position.z - _hole_z
		if across < 0.0:
			left = minf(left, -across)
		else:
			right = minf(right, across)
	_room[_case] += left + right
	_room_count[_case] += 1


func _record() -> void:
	_live = false
	var gain: float = 0.0
	if _pc.final_team == _pc.offense:
		gain = minf((_pc.dead_spot_x - _pc.los_x) * _pc.off_dir, CAP)
	_yards[_case] += gain
	_count[_case] += 1
	var name: String = _pc.off_play.play_name
	_by_play[_case][name] = float(_by_play[_case].get(name, 0.0)) + gain
	_left -= 1
	if _left > 0:
		return
	_left = _snaps
	_job += 1
	if _job >= _plays.size() * _defenses.size():
		_blocks[_case] = _game.get_stat(&"hole_blocks")
		_won[_case] = _game.get_stat(&"hole_blocks_won")
		_next_case()


func _mean(case: int) -> float:
	return _yards[case] / float(maxi(_count[case], 1))


func _room_at(case: int) -> float:
	return _room[case] / float(maxi(_room_count[case], 1))


func _finish() -> void:
	physics_frame.disconnect(_tick)
	for player: Player in _own:
		player.ratings = _own[player]
	_game.tuning.hole_max_width = _hole_width
	var per_play: float = float(_snaps * _defenses.size())
	for case: int in _yards.size():
		var share: float = float(_won[case]) / float(maxi(_blocks[case], 1))
		var detail: PackedStringArray = PackedStringArray()
		for name: String in _by_play[case]:
			detail.append("%s %.1f" % [name, float(_by_play[case][name]) / per_play])
		print("%-18s %4.2f yd wide at the hole, %3.0f%% of %d blocks at the hole won, %5.1f yd a run over %d runs   (%s)" % [CASES[case][0], _room_at(case), 100.0 * share, _blocks[case], _mean(case), _count[case], ", ".join(detail)])
	if _yards.size() == CASES.size():
		var strong_share: float = float(_won[2]) / float(maxi(_blocks[2], 1))
		var weak_share: float = float(_won[3]) / float(maxi(_blocks[3], 1))
		_expect(_blocks[0] == 0, "blocks at the hole were rolled with the hole off")
		_expect(_blocks[1] > 0, "no block at the hole was rolled")
		_expect(strong_share >= 0.85, "a strong line won only %.0f%% of its blocks at the hole" % (100.0 * strong_share))
		_expect(weak_share <= 0.15, "a weak line won %.0f%% of its blocks at the hole" % (100.0 * weak_share))
		_expect(_room_at(2) >= _room_at(3) + 0.5, "the hole was %.2f yd wide behind a strong line, %.2f behind a weak one" % [_room_at(2), _room_at(3)])
		_expect(_room_at(1) > _room_at(0), "with the rosters as they are the hole was %.2f yd wide with the blocking for it, %.2f without" % [_room_at(1), _room_at(0)])
	for failure: String in _failures:
		print("FAIL: " + failure)
	print("run_hole_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message):
		_failures.append(message)
