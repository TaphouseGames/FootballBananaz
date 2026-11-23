extends SceneTree
## Headless check of run blocking at the hole (PlayController._assign_run_blocks,
## _roll_drive, _drive_block): the inside runs are played CPU against CPU with a
## strong offensive line against a weak defensive line, the other way round,
## and with both as the rosters have them, with and without the hole. A good
## line has to win most of its blocks at the hole and a bad one hardly any, and
## the lane has to be there in time behind the good one and mostly not behind
## the bad one. The lane is PlayController.hole_lane(): the room clear of
## bodies of either team at the hole, looked at 0.7 seconds after the snap and
## again when the back is a yard and a half short of the line. The yards a
## run, and the share of runs stuffed, long or given the burst, are printed to
## compare, not judged: yards swing by a yard or more from one run of this
## check to the next (216 runs a case).
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/run_hole_check.gd
## Optional user args after "--":
##   snaps=<n>   snaps per play and defense in each case (default 6: about 4 minutes)
##   dump=<play name>   print where everyone near the hole stands at MEASURE_TIME
##       on every snap of that play (see _print_bodies)
## After each play's yards a run comes the share of its snaps with the lane open.
##   set=<name>:<value>[,<name>:<value>...]   override Tuning values for this run

const SPEED: float = 16.0
const MAX_PLAY_TIME: float = 20.0
const CAP: float = 30.0
const DEFENSES: PackedStringArray = ["Man Cover 1", "Cover 3", "Zone Cover 2", "Cover 1 Spy"]
const STRONG: int = 90
## Seconds after the snap that the lane is measured, how far short of the line
## the back is when it is measured again, and the width that counts as open.
const MEASURE_TIME: float = 0.7
const MEASURE_DEPTH: float = -1.5
const OPEN_WIDTH: float = 1.6
## A run for this little is stuffed, and for this much a long one.
const STUFFED: float = 1.0
const LONG: float = 20.0
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
## Per case: the lane at MEASURE_TIME, summed, how often it was open and how
## often measured; the same when the back got to MEASURE_DEPTH.
var _room: PackedFloat32Array = PackedFloat32Array()
var _room_open: PackedInt32Array = PackedInt32Array()
var _room_count: PackedInt32Array = PackedInt32Array()
var _back_room: PackedFloat32Array = PackedFloat32Array()
var _back_open: PackedInt32Array = PackedInt32Array()
var _back_count: PackedInt32Array = PackedInt32Array()
## Per case: runs stuffed, long runs, bursts.
var _stuffed: PackedInt32Array = PackedInt32Array()
var _long: PackedInt32Array = PackedInt32Array()
var _bursts: PackedInt32Array = PackedInt32Array()
var _measured: bool = false
var _back_measured: bool = false
## Per case and play name: snaps with the lane open at MEASURE_TIME.
var _open_by_play: Array[Dictionary] = []
var _dump: String = ""
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("snaps="):
			_snaps = maxi(arg.trim_prefix("snaps=").to_int(), 1)
		elif arg.begins_with("dump="):
			_dump = arg.trim_prefix("dump=")
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
		_measured = true
		var lane: float = _pc.hole_lane().y
		_room[_case] += lane
		_room_count[_case] += 1
		if lane >= OPEN_WIDTH:
			_room_open[_case] += 1
			_open_by_play[_case][_pc.off_play.play_name] = int(_open_by_play[_case].get(_pc.off_play.play_name, 0)) + 1
		if _dump != "" and _pc.off_play.play_name == _dump:
			_print_bodies(lane)
	if not _back_measured and _pc.runner != null and (_pc.runner.position.x - _pc.los_x) * _pc.off_dir >= MEASURE_DEPTH:
		_back_measured = true
		var lane: float = _pc.hole_lane().y
		_back_room[_case] += lane
		_back_count[_case] += 1
		if lane >= OPEN_WIDTH:
			_back_open[_case] += 1
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
	_room_open.append(0)
	_room_count.append(0)
	_back_room.append(0.0)
	_back_open.append(0)
	_back_count.append(0)
	_open_by_play.append({})
	_stuffed.append(0)
	_long.append(0)
	_bursts.append(0)
	_job = 0
	_left = _snaps
	_game.stats.clear()


func _start_play() -> void:
	# The home team has the ball every time, so one line is always the offense's.
	_game.clock = 1.0e6
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	@warning_ignore("integer_division")
	var play: OffensePlay = _plays[_job / _defenses.size()]
	# Where the play is aimed, found with the hole on whatever the case: with it
	# off the second line-up leaves PlayController.run_hole where it was, so
	# hole_lane() looks at the same spot in every case.
	var width: float = _game.tuning.hole_max_width
	_game.tuning.hole_max_width = _hole_width
	_pc.line_up(play, _defenses[_job % _defenses.size()])
	_game.tuning.hole_max_width = width
	_pc.line_up(play, _defenses[_job % _defenses.size()])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_live = true
	_measured = false
	_back_measured = false


func _record() -> void:
	_live = false
	var gain: float = 0.0
	if _pc.final_team == _pc.offense:
		gain = minf((_pc.dead_spot_x - _pc.los_x) * _pc.off_dir, CAP)
	_yards[_case] += gain
	_count[_case] += 1
	if gain <= STUFFED:
		_stuffed[_case] += 1
	if gain >= LONG:
		_long[_case] += 1
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
		_bursts[_case] = _game.get_stat(&"hole_bursts")
		_next_case()


func _mean(case: int) -> float:
	return _yards[case] / float(maxi(_count[case], 1))


func _room_at(case: int) -> float:
	return _room[case] / float(maxi(_room_count[case], 1))


## dump=<play>: everyone near the hole at MEASURE_TIME, as yards past the line
## and yards across from the hole. O is the offense and D the defense; then his
## side of the hole, `>` and the speed he is being moved at, `*` for the back.
func _print_bodies(lane: float) -> void:
	var parts: PackedStringArray = PackedStringArray()
	for player: Player in _pc.players:
		var depth: float = (player.position.x - _pc.los_x) * _pc.off_dir
		var across: float = player.position.z - _pc.run_hole.z
		if depth < -4.0 or depth > 4.0 or absf(across) > 5.0:
			continue
		var tag: String = "O" if player.team == _pc.offense else "D"
		if player == _pc.runner:
			tag += "*"
		if player.is_down():
			tag += "x"
		if player.hole_side != 0.0:
			tag += "+" if player.hole_side > 0.0 else "-"
		if player.hole_block and player.block_slow_timer > 0.0:
			tag += ">%.1f" % (player.block_drive * player.block_drive_side)
		parts.append("%s(%.1f,%.1f)" % [tag, depth, across])
	print("  %s vs %s  lane %.2f: %s" % [_pc.off_play.play_name, _pc.def_play.play_name, lane, " ".join(parts)])


## Share of snaps with the lane open as the back got to it.
func _open_at(case: int) -> float:
	return float(_back_open[case]) / float(maxi(_back_count[case], 1))


func _share(count: int, case: int) -> float:
	return 100.0 * float(count) / float(maxi(_count[case], 1))


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
			detail.append("%s %.1f yd %.0f%%" % [name, float(_by_play[case][name]) / per_play, 100.0 * float(_open_by_play[case].get(name, 0)) / per_play])
		print("%-18s lane at %.1f s: %4.2f yd, open %3.0f%%;  as the back arrives: %4.2f yd, open %3.0f%%;  %3.0f%% of %d blocks won" % [CASES[case][0], MEASURE_TIME, _room_at(case), 100.0 * float(_room_open[case]) / float(maxi(_room_count[case], 1)), _back_room[case] / float(maxi(_back_count[case], 1)), 100.0 * float(_back_open[case]) / float(maxi(_back_count[case], 1)), 100.0 * share, _blocks[case]])
		print("%-18s %5.1f yd a run over %d runs, stuffed %2.0f%%, long %2.0f%%, burst %2.0f%%   (%s)" % ["", _mean(case), _count[case], _share(_stuffed[case], case), _share(_long[case], case), _share(_bursts[case], case), ", ".join(detail)])
	if _yards.size() == CASES.size():
		var strong_share: float = float(_won[2]) / float(maxi(_blocks[2], 1))
		var weak_share: float = float(_won[3]) / float(maxi(_blocks[3], 1))
		_expect(_blocks[0] == 0, "blocks at the hole were rolled with the hole off")
		_expect(_blocks[1] > 0, "no block at the hole was rolled")
		_expect(strong_share >= 0.85, "a strong line won only %.0f%% of its blocks at the hole" % (100.0 * strong_share))
		_expect(weak_share <= 0.15, "a weak line won %.0f%% of its blocks at the hole" % (100.0 * weak_share))
		_expect(_room_at(2) >= _room_at(3) + 0.5, "the lane was %.2f yd wide behind a strong line, %.2f behind a weak one" % [_room_at(2), _room_at(3)])
		_expect(_room_at(1) > _room_at(0), "with the rosters as they are the lane was %.2f yd wide with the blocking for it, %.2f without" % [_room_at(1), _room_at(0)])
		_expect(_open_at(1) >= 0.8, "with the rosters as they are the lane was open as the back got there on only %.0f%% of snaps" % [100.0 * _open_at(1)])
		_expect(_open_at(2) >= 0.95, "behind a strong line the lane was open as the back got there on only %.0f%% of snaps" % [100.0 * _open_at(2)])
		_expect(_open_at(3) <= 0.4, "behind a weak line the lane was open as the back got there on %.0f%% of snaps" % [100.0 * _open_at(3)])
	for failure: String in _failures:
		print("FAIL: " + failure)
	print("run_hole_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message):
		_failures.append(message)
