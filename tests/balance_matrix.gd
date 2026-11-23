extends SceneTree
## Headless balance check. Runs every offensive play against every defensive
## play many times from the same spot and prints the average gain.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/balance_matrix.gd
## Optional user args after "--":
##   mode=matrix   CPU quarterback reads the field (default)
##   mode=spam     the test throws to one fixed receiver at one fixed time, for
##                 every receiver and several times: the "same throw every down" case
##   mode=scramble the quarterback tucks the ball and runs at a fixed time
##   mode=all      matrix and spam
##   rollout       scramble probe: the quarterback runs out wide first
##   rollout=<width>/<forward>   the same, this many yards out and this much
##                 upfield for every yard across (default 9/0.35)
##   scout         leave the defense's memory of earlier plays on (off by default,
##                 so every snap is defended as if seen for the first time)
##   motion        send the motion man (LB) on every play that has one, and snap
##                 once he has set (a jet: as he gets to the quarterback)
##   snaps=<n>     snaps per cell (default 120 for matrix, 40 for spam)
##   off=<text>    only offensive plays whose name contains the text
##   tab=<text>    only offensive plays on the tab (formation) whose name contains the text
##   def=<text>    only defensive plays whose name contains the text
##   detail        also print yards, completion, turnover and sack rates per cell
##   big           also print, per defensive play, how often it gives up BIG_PLAY
##                 yards or more (uncapped), how many of those were caught with
##                 nobody within ALONE yards, who caught them, what the nearest
##                 defender's job was and what the defense had gambled on
##   place=normal|lead|under|cpu   spam probe: how the throw is placed (cpu lets
##                 the CPU quarterback choose; default normal)
##   times=<a>/<b>/...   release times for the spam probe (default 0.8/1.4/2.0/2.6)
##   set=<name>:<value>[,<name>:<value>...]   override Tuning values for this run
##   yard=<n>      yard line from the own goal the snaps start on (default 25);
##                 96 puts the ball on the 4 for the goal line plays
##   home=<short name>, away=<short name>   the league teams that play, taking
##                 turns on offense; the scene's own two otherwise
##
## Gains are capped at CAP yards so one long touchdown does not swamp a cell, and
## a turnover counts as TURNOVER_COST yards lost.

const SPEED: float = 16.0
const CAP: float = 30.0
const TURNOVER_COST: float = 12.0
const START_YARD: float = 25.0
## Yard line (from the own goal) every snap starts on. `yard=<n>` changes it.
var _start_yard: float = START_YARD
const MAX_PLAY_TIME: float = 25.0

var _game: Game
var _pc: PlayController
var _mode: String = "matrix"
var _snaps: int = 0
var _off_filter: String = ""
var _tab_filter: String = ""
var _def_filter: String = ""
var _detail: bool = false
var _spam_times: PackedFloat64Array = PackedFloat64Array([0.8, 1.4, 2.0, 2.6])
var _overrides: Dictionary[String, float] = {}
var _scout: bool = false
## Every play that has a motion (LB) is run with its man sent.
var _motion: bool = false
## Spam probe: how the fixed throw is placed (normal, lead, under, or cpu to let
## the CPU quarterback choose).
var _place: String = "normal"
## Scramble probe: +1 runs the quarterback out wide before he turns upfield.
var _rollout: float = 0.0
var _rollout_width: float = 9.0
var _rollout_forward: float = 0.35
## Slot value of a job in which the quarterback runs instead of throwing.
const SCRAMBLE: int = -2
## When the receivers are judged for how open they are, and how much room
## counts as wide open.
const OPEN_SAMPLE_TIME: float = 1.8
const WIDE_OPEN: float = 6.0
var _sampled: bool = false
## The `big` report: a gain of this many yards, and a catcher with no defender
## within this many.
const BIG_PLAY: float = 25.0
const ALONE: float = 7.0
var _big: bool = false
## Defensive play index -> what it gave up (see _note_big).
var _big_rows: Dictionary[int, Dictionary] = {}

## One job: an offensive play against a defensive play, optionally with a fixed
## throw (slot >= 0) at a fixed time.
var _jobs: Array[Dictionary] = []
var _job_index: int = -1
var _snaps_left: int = 0
var _live: bool = false
var _thrown: bool = false
var _completions_before: int = 0
var _home_next: bool = true
## Short names of the league teams to play as home and away, "" for the scene's.
var _teams: PackedStringArray = PackedStringArray(["", ""])


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("mode="):
			_mode = arg.trim_prefix("mode=")
		elif arg.begins_with("snaps="):
			_snaps = maxi(int(arg.trim_prefix("snaps=")), 1)
		elif arg.begins_with("off="):
			_off_filter = arg.trim_prefix("off=").to_lower()
		elif arg.begins_with("def="):
			_def_filter = arg.trim_prefix("def=").to_lower()
		elif arg.begins_with("tab="):
			_tab_filter = arg.trim_prefix("tab=").to_lower()
		elif arg.begins_with("place="):
			_place = arg.trim_prefix("place=")
		elif arg.begins_with("yard="):
			_start_yard = float(arg.trim_prefix("yard="))
		elif arg == "detail":
			_detail = true
		elif arg == "big":
			_big = true
		elif arg == "rollout":
			_rollout = 1.0
		elif arg.begins_with("rollout="):
			var shape: PackedFloat64Array = arg.trim_prefix("rollout=").split_floats("/")
			_rollout = 1.0
			_rollout_width = shape[0]
			_rollout_forward = shape[1] if shape.size() > 1 else _rollout_forward
		elif arg == "scout":
			_scout = true
		elif arg == "motion":
			_motion = true
		elif arg.begins_with("home=") or arg.begins_with("away="):
			_teams[0 if arg.begins_with("home=") else 1] = arg.get_slice("=", 1)
		elif arg.begins_with("times="):
			_spam_times = arg.trim_prefix("times=").split_floats("/")
		elif arg.begins_with("set="):
			for pair: String in arg.trim_prefix("set=").split(","):
				var parts: PackedStringArray = pair.split(":")
				if parts.size() == 2:
					_overrides[parts[0]] = float(parts[1])
	# Time scale alone would stretch the physics step and change the simulation
	# (blocks stop holding), so the tick rate goes up with it: every tick is
	# still 1/60 s of game time.
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	for i: int in 2:
		if _teams[i] != "":
			Game.team_picks[i] = _game.league.find(_teams[i])
	root.add_child(_game)
	physics_frame.connect(_tick)


## The scene is not ready inside _initialize, so the run is set up on the first tick.
func _begin() -> void:
	_pc = _game.play_controller
	for key: String in _overrides:
		_game.tuning.set(key, _overrides[key])
		print("tuning.%s = %s" % [key, _game.tuning.get(key)])
	if not _scout and not _overrides.has("ai_scout_strength"):
		_game.tuning.set("ai_scout_strength", 0.0)
	_build_jobs()
	_next_job()


func _build_jobs() -> void:
	var offs: Array[OffensePlay] = _game.offense_playbook.plays
	var defs: Array[DefensePlay] = _game.defense_playbook.plays
	for o: int in offs.size():
		if _off_filter != "" and not offs[o].play_name.to_lower().contains(_off_filter):
			continue
		if _tab_filter != "" and not OffensePlay.GROUP_NAMES[offs[o].group].to_lower().contains(_tab_filter):
			continue
		if _mode == "matrix" or _mode == "all":
			for d: int in defs.size():
				if _def_filter == "" or defs[d].play_name.to_lower().contains(_def_filter):
					_jobs.append(_new_job(o, d, -1, 0.0))
		if _mode == "scramble" and not offs[o].is_run:
			for time: float in _spam_times:
				for d: int in defs.size():
					_jobs.append(_new_job(o, d, SCRAMBLE, time))
		if (_mode == "spam" or _mode == "all") and not offs[o].is_run:
			for slot: int in 3:
				for time: float in _spam_times:
					for d: int in defs.size():
						_jobs.append(_new_job(o, d, slot, time))


func _new_job(o: int, d: int, slot: int, time: float) -> Dictionary:
	return {"off": o, "def": d, "slot": slot, "time": time, "n": 0, "gain": 0.0, "value": 0.0, "comp": 0, "turnover": 0, "sack": 0, "big": 0, "time_sum": 0.0, "open": 0, "open_sum": 0.0}


func _next_job() -> void:
	_job_index += 1
	if _job_index >= _jobs.size():
		_report()
		return
	var spam: bool = int(_jobs[_job_index]["slot"]) != -1
	_snaps_left = _snaps if _snaps > 0 else (40 if spam else 120)
	# In spam mode the test is the quarterback: the CPU one never decides.
	_game.tuning.ai_qb_min_time = 1.0e9 if spam else _overrides.get("ai_qb_min_time", Tuning.new().ai_qb_min_time)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_begin()
	if _job_index >= _jobs.size():
		return
	if not _live:
		_start_play()
		return
	var job: Dictionary = _jobs[_job_index]
	if _pc.ball_dead:
		_record(job)
		return
	if _pc.live_time > MAX_PLAY_TIME:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
		return
	var slot: int = job["slot"]
	if not _sampled and _pc.live_time >= OPEN_SAMPLE_TIME and _pc.phase == PlayController.Phase.POCKET and not _pc.off_play.is_run:
		# How open the most open receiver downfield is at a fixed moment.
		_sampled = true
		var best: float = 0.0
		for receiver: Player in _pc.eligible:
			if (receiver.position.x - _pc.los_x) * _pc.off_dir >= 3.0 and not receiver.is_down():
				best = maxf(best, minf(_pc.nearest_opponent_distance(receiver), 15.0))
		job["open_sum"] = float(job["open_sum"]) + best
		job["open_n"] = int(job.get("open_n", 0)) + 1
		if best >= WIDE_OPEN:
			job["open"] = int(job["open"]) + 1
	if slot == SCRAMBLE and not _thrown and _pc.live_time >= float(job["time"]) and _pc.ball.carrier == _pc.qb:
		_thrown = true
		_pc.qb.brain.start_scramble(_rollout, true, _rollout_width, _rollout_forward)
	if slot >= 0 and not _thrown and _pc.live_time >= float(job["time"]) and _pc.can_pass():
		_thrown = true
		var target: Player = _pc.eligible[mini(slot, _pc.eligible.size() - 1)]
		# The same choice of lob, regular pass or bullet the CPU quarterback makes.
		var open: float = minf(_pc.nearest_opponent_distance(target), 10.0)
		var power: float = _pc.qb.brain.choose_pass(_pc, target, open, false)
		var placement: PlayController.Placement = PlayController.Placement.NORMAL
		match _place:
			"lead":
				placement = PlayController.Placement.LEAD
			"under":
				placement = PlayController.Placement.UNDER
			"cpu":
				placement = _pc.qb.brain.choose_placement(_pc, target, power)
		_pc.throw_ball(target, power, placement)


func _start_play() -> void:
	var job: Dictionary = _jobs[_job_index]
	var team: Team = _game.home if _home_next else _game.away
	_home_next = not _home_next
	_game.clock = 1.0e6
	_game.start_drive(team, _game.tuning.yard_to_x(team.attack_dir, _start_yard))
	var off_index: int = job["off"]
	var def_index: int = job["def"]
	_pc.line_up(_game.offense_playbook.plays[off_index], _game.defense_playbook.plays[def_index])
	if _motion and _pc.motion.call_motion():
		# The man is sent and the ball snapped once he has set, or with a jet
		# as he gets to the quarterback.
		for _i: int in 720:
			_pc.motion.tick(1.0 / 60.0)
			if _pc.motion.state == PreSnapMotion.State.SET or _pc.motion.jet_in_window():
				break
		if _pc.motion.state == PreSnapMotion.State.SET:
			# The defense gets the moment it takes to settle, too.
			for _i: int in 90:
				_pc.motion.tick(1.0 / 60.0)
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	_completions_before = _game.get_stat(&"completions")
	_thrown = false
	_sampled = false
	_live = true


func _record(job: Dictionary) -> void:
	_live = false
	var turnover: bool = _pc.final_team != _pc.offense
	var gain: float = 0.0
	if not turnover:
		gain = minf((_pc.dead_spot_x - _pc.los_x) * _pc.off_dir, CAP)
	var n: int = job["n"]
	job["n"] = n + 1
	var total: float = job["gain"]
	job["gain"] = total + gain
	var value: float = job["value"]
	job["value"] = value + (gain - (TURNOVER_COST if turnover else 0.0))
	if _game.get_stat(&"completions") > _completions_before:
		var comp: int = job["comp"]
		job["comp"] = comp + 1
	if turnover:
		var turnovers: int = job["turnover"]
		job["turnover"] = turnovers + 1
	if _pc.was_sack:
		var sacks: int = job["sack"]
		job["sack"] = sacks + 1
	var time: float = job["time_sum"]
	job["time_sum"] = time + _pc.live_time
	if gain >= 20.0:
		var big: int = job["big"]
		job["big"] = big + 1
	if _big and int(job["slot"]) == -1:
		_note_big(int(job["def"]), turnover)
	_snaps_left -= 1
	if _snaps_left <= 0:
		_next_job()


## The `big` report: what this snap adds to the row of its defensive play.
func _note_big(def_index: int, turnover: bool) -> void:
	if not _big_rows.has(def_index):
		_big_rows[def_index] = {"n": 0, "pass": 0, "big": 0, "td": 0, "alone": 0, "who": {}, "near": {}, "gambles": {}, "all_gambles": {}}
	var row: Dictionary = _big_rows[def_index]
	row["n"] = int(row["n"]) + 1
	var all_gambles: Dictionary = row["all_gambles"]
	for gamble: StringName in _unique(_pc.gambles):
		all_gambles[gamble] = int(all_gambles.get(gamble, 0)) + 1
	if _pc.off_play.is_run:
		return
	row["pass"] = int(row["pass"]) + 1
	if turnover or _pc.catcher == null or (_pc.dead_spot_x - _pc.los_x) * _pc.off_dir < BIG_PLAY:
		return
	row["big"] = int(row["big"]) + 1
	if _pc.result == PlayController.Result.TOUCHDOWN:
		row["td"] = int(row["td"]) + 1
	var who: Dictionary = row["who"]
	var label: String = _pc.catcher.brain.off_assign.label
	who[label] = int(who.get(label, 0)) + 1
	var gambles: Dictionary = row["gambles"]
	for gamble: StringName in _unique(_pc.gambles):
		gambles[gamble] = int(gambles.get(gamble, 0)) + 1
	if _pc.catch_open < ALONE:
		return
	row["alone"] = int(row["alone"]) + 1
	if _pc.catch_nearest != null and _pc.catch_nearest.brain.def_assign != null:
		var near: Dictionary = row["near"]
		var assignment: DefenseAssignment = _pc.catch_nearest.brain.def_assign
		var job: String = "%s %s%s" % [assignment.label, ["rush", "man", "zone", "spy"][assignment.job], " deep" if assignment.deep else ""]
		near[job] = int(near.get(job, 0)) + 1


func _unique(names: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for name: StringName in names:
		if not result.has(name):
			result.append(name)
	return result


func _counts(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(counts[a]) > int(counts[b]))
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in keys:
		parts.append("%s %d" % [key, counts[key]])
	return ", ".join(parts)


func _report_big(defs: Array[DefensePlay]) -> void:
	print("
BIG PLAYS: completed passes of %d+ yards (uncapped), per defensive play, pass plays only." % int(BIG_PLAY))
	print("alone = caught with no defender within %d yd. near = the job of the nearest defender on those." % int(ALONE))
	print("%-18s %5s %5s %5s %6s   %s" % ["", "snaps", "big%", "td%", "alone%", "who caught | near | gambles on big plays (on all snaps)"])
	var total: Dictionary = {"pass": 0, "big": 0, "td": 0, "alone": 0}
	for d: int in defs.size():
		if not _big_rows.has(d):
			continue
		var row: Dictionary = _big_rows[d]
		var passes: float = maxf(float(row["pass"]), 1.0)
		for key: String in total:
			total[key] = int(total[key]) + int(row[key])
		var gambles: Dictionary = row["gambles"]
		var all_gambles: Dictionary = row["all_gambles"]
		var gamble_text: PackedStringArray = PackedStringArray()
		for gamble: Variant in all_gambles:
			gamble_text.append("%s %d (%d)" % [gamble, gambles.get(gamble, 0), all_gambles[gamble]])
		print("%-18s %5d %5.1f %5.1f %6.1f   %s | %s | %s" % [defs[d].play_name.substr(0, 18), int(row["pass"]), 100.0 * float(row["big"]) / passes, 100.0 * float(row["td"]) / passes, 100.0 * float(row["alone"]) / passes, _counts(row["who"]), _counts(row["near"]), ", ".join(gamble_text)])
	var all_passes: float = maxf(float(total["pass"]), 1.0)
	print("%-18s %5d %5.1f %5.1f %6.1f" % ["ALL", int(total["pass"]), 100.0 * float(total["big"]) / all_passes, 100.0 * float(total["td"]) / all_passes, 100.0 * float(total["alone"]) / all_passes])


func _mean(job: Dictionary, key: String) -> float:
	var n: int = job["n"]
	return float(job[key]) / float(maxi(n, 1))


func _report() -> void:
	physics_frame.disconnect(_tick)
	# What the coverage did over the whole run: see PlayController._count_arrival.
	var coverage: PackedStringArray = PackedStringArray()
	for key: StringName in _game.stats:
		var text: String = String(key)
		if text.begins_with("arrival") or text.begins_with("undercut") or text.begins_with("air_hit") or text.begins_with("technique") or text == "interceptions" or text == "passes":
			coverage.append("%s=%d" % [text, _game.stats[key]])
	coverage.sort()
	print("COVERAGE " + " ".join(coverage))
	var offs: Array[OffensePlay] = _game.offense_playbook.plays
	var defs: Array[DefensePlay] = _game.defense_playbook.plays

	var matrix: Array[Dictionary] = _jobs.filter(func(job: Dictionary) -> bool: return int(job["slot"]) == -1)
	if not matrix.is_empty():
		print("\nVALUE per snap (yards capped at %d, turnover = -%d). Rows: offense. Columns: defense." % [int(CAP), int(TURNOVER_COST)])
		var header: String = "%-14s" % ""
		for def_play: DefensePlay in defs:
			if _def_filter == "" or def_play.play_name.to_lower().contains(_def_filter):
				header += "%8s" % def_play.play_name.substr(0, 7)
		print(header + "     mean   min   max  comp%  to%  sack%  big%  open  wide%")
		var column_sum: PackedFloat32Array = PackedFloat32Array()
		column_sum.resize(defs.size())
		var rows: int = 0
		for o: int in offs.size():
			var cells: Array[Dictionary] = matrix.filter(func(job: Dictionary) -> bool: return int(job["off"]) == o)
			if cells.is_empty():
				continue
			rows += 1
			var line: String = "%-14s" % offs[o].play_name.substr(0, 13)
			var total: float = 0.0
			var low: float = INF
			var high: float = -INF
			var comp: float = 0.0
			var turnover: float = 0.0
			var sack: float = 0.0
			var big: float = 0.0
			var open_sum: float = 0.0
			var open_wide: float = 0.0
			var open_n: float = 0.0
			for cell: Dictionary in cells:
				open_sum += float(cell["open_sum"])
				open_wide += float(cell["open"])
				open_n += float(cell.get("open_n", 0))
				var value: float = _mean(cell, "value")
				line += "%8.1f" % value
				var d: int = cell["def"]
				column_sum[d] += value
				total += value
				low = minf(low, value)
				high = maxf(high, value)
				comp += _mean(cell, "comp")
				turnover += _mean(cell, "turnover")
				sack += _mean(cell, "sack")
				big += _mean(cell, "big")
			var count: float = float(cells.size())
			print(line + "   %6.1f %5.1f %5.1f  %5.0f %4.0f  %5.0f %5.0f %5.1f %5.0f" % [total / count, low, high, 100.0 * comp / count, 100.0 * turnover / count, 100.0 * sack / count, 100.0 * big / count, open_sum / maxf(open_n, 1.0), 100.0 * open_wide / maxf(open_n, 1.0)])
			if _detail:
				for key: String in ["gain", "comp", "turnover", "sack", "time_sum"]:
					var detail: String = "%14s" % ("  " + key)
					for cell: Dictionary in cells:
						detail += "%8.1f" % (_mean(cell, key) * (1.0 if key == "gain" or key == "time_sum" else 100.0))
					print(detail)
		var footer: String = "%-14s" % "mean allowed"
		for d: int in defs.size():
			if _def_filter == "" or defs[d].play_name.to_lower().contains(_def_filter):
				footer += "%8.1f" % (column_sum[d] / float(maxi(rows, 1)))
		print(footer)
		if _big:
			_report_big(defs)

	var spam: Array[Dictionary] = _jobs.filter(func(job: Dictionary) -> bool: return int(job["slot"]) != -1)
	if not spam.is_empty():
		print("\nPROBE: always throw to one receiver at one time, or (slot %d) keep the ball and run. Value per snap across the defenses." % SCRAMBLE)
		print("%-14s slot  time    mean  best-counter  worst-counter  comp%%  to%%  sack%%  secs" % "")
		var index: int = 0
		while index < spam.size():
			var first: Dictionary = spam[index]
			var total: float = 0.0
			var low: float = INF
			var high: float = -INF
			var comp: float = 0.0
			var turnover: float = 0.0
			var sack: float = 0.0
			var secs: float = 0.0
			var count: int = 0
			while index < spam.size() and int(spam[index]["off"]) == int(first["off"]) and int(spam[index]["slot"]) == int(first["slot"]) and is_equal_approx(float(spam[index]["time"]), float(first["time"])):
				var value: float = _mean(spam[index], "value")
				total += value
				low = minf(low, value)
				high = maxf(high, value)
				comp += _mean(spam[index], "comp")
				turnover += _mean(spam[index], "turnover")
				sack += _mean(spam[index], "sack")
				secs += _mean(spam[index], "time_sum")
				count += 1
				index += 1
			var off_index: int = first["off"]
			print("%-14s %4d  %4.1f  %6.1f  %12.1f  %13.1f  %5.0f %4.0f  %5.0f  %4.1f" % [offs[off_index].play_name.substr(0, 13), int(first["slot"]), float(first["time"]), total / float(count), low, high, 100.0 * comp / float(count), 100.0 * turnover / float(count), 100.0 * sack / float(count), secs / float(count)])
	quit(0)
