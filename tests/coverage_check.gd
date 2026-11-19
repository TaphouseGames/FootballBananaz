extends SceneTree
## Headless check of what a man defender does about a receiver he is covering:
##   front      with the ball in the air to a receiver who has stopped and waits
##              for it, he gets round to the quarterback's side of him
##   hit        a defender who cannot get to the ball dives at the receiver, and
##              a receiver he knocks down does not catch it
##   technique  playing off, he is further from his man on a short route than a
##              tight defender is, and no further once they are deep
## The test is the quarterback: it throws to the first wideout once he is a set
## distance downfield. Every case is run with the feature on and off.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/coverage_check.gd
## Optional user args after "--":
##   plays=<n>   snaps per run (default 40)

const SPEED: float = 16.0
const MAX_PLAY_TIME: float = 8.0
## PlayController.in_front() from which a defender counts as in front of his man.
const FRONT: float = 0.6
## Everything that would have a defender somewhere else than his coverage, or
## the quarterback doing something of his own.
const QUIET: Dictionary[String, float] = {
	"cpu_skill": 0.0, "ai_qb_min_time": 1.0e9, "ai_qb_keeper_chance": 0.0,
	"ai_cover_bust_chance": 0.0, "ai_blown_coverage_chance": 0.0, "ai_takeout_chance": 0.0,
	"accuracy_error_low": 0.0, "accuracy_error_high": 0.0,
	"pass_overlead_chance": 0.0, "pass_under_error": 0.0,
	"ai_undercut_chance": 0.0, "ai_air_hit_chance": 0.0, "ai_cover_off_chance": 0.0,
	"ai_cover_trail_chance": 0.0, "ai_cover_leverage": 0.0,
	"undercut_coverage_scale_low": 1.0, "undercut_coverage_scale_high": 1.0,
}

var _game: Game
var _pc: PlayController
var _plays: int = 40
var _defaults: Dictionary[String, Variant] = {}
## Each run: an offensive play, the settings on top of QUIET, how far downfield
## the wideout is when the ball is thrown (negative = never) or how long after
## the snap (`time`), how it is placed, and how far downfield he is when the gap
## to his man is measured.
var _runs: Array[Dictionary] = [
	# Thrown once the curl has stopped him, with his man on his deep side.
	{"name": "front off", "play": "curl flat", "set": {}, "throw": -1.0, "time": 2.4, "under": false, "gap_at": -1.0},
	{"name": "front on", "play": "curl flat", "set": {"ai_undercut_chance": 1.0}, "throw": -1.0, "time": 2.4, "under": false, "gap_at": -1.0},
	# With no reach for the ball the defender never has a play on it himself.
	{"name": "hit off", "play": "quick slants", "set": {"defender_catch_radius": 0.05}, "throw": 3.0, "under": false, "gap_at": -1.0},
	{"name": "hit on", "play": "quick slants", "set": {"defender_catch_radius": 0.05, "ai_air_hit_chance": 1.0}, "throw": 3.0, "under": false, "gap_at": -1.0},
	{"name": "tight short", "play": "curl flat", "set": {}, "throw": -1.0, "under": false, "gap_at": 4.0},
	{"name": "off short", "play": "curl flat", "set": {"ai_cover_off_chance": 1.0}, "throw": -1.0, "under": false, "gap_at": 4.0},
	{"name": "tight deep", "play": "gun verts", "set": {}, "throw": -1.0, "under": false, "gap_at": 16.0},
	{"name": "off deep", "play": "gun verts", "set": {"ai_cover_off_chance": 1.0}, "throw": -1.0, "under": false, "gap_at": 16.0},
]
var _run: int = -1
var _left: int = 0
var _live: bool = false
var _thrown: bool = false
var _measured: bool = false
var _receiver: Player
var _play: OffensePlay
var _hits_before: int = 0
var _catches_before: int = 0
var _results: Dictionary[String, Dictionary] = {}
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("plays="):
			_plays = maxi(int(arg.trim_prefix("plays=")), 1)
	# The tick rate goes up with the time scale, so a tick is still 1/60 s.
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
		_pc = _game.play_controller
		for key: String in QUIET:
			_defaults[key] = _game.tuning.get(key)
		_defaults["defender_catch_radius"] = _game.tuning.defender_catch_radius
		_next_run()
		return
	if _run >= _runs.size():
		return
	if not _live:
		_start_play()
		return
	var run: Dictionary = _runs[_run]
	var result: Dictionary = _results[run["name"]]
	var downfield: float = (_receiver.position.x - _pc.los_x) * _pc.off_dir
	var gap_at: float = run["gap_at"]
	if gap_at >= 0.0 and not _measured and downfield >= gap_at:
		_measured = true
		var man: Player = _man_on(_receiver)
		if man != null and not man.is_down() and not _receiver.is_down():
			result["gap_sum"] = float(result["gap_sum"]) + _flat(man.position, _receiver.position)
			result["gap_n"] = int(result["gap_n"]) + 1
		_end_play()
		return
	var throw_at: float = run["throw"]
	var throw_time: float = run.get("time", -1.0)
	var due: bool = (throw_at >= 0.0 and downfield >= throw_at) or (throw_time >= 0.0 and _pc.live_time >= throw_time)
	if due and not _thrown and _pc.can_pass() and not _pc.ball_dead:
		_thrown = true
		_pc.throw_ball(_receiver, 0.5, PlayController.Placement.UNDER if run["under"] else PlayController.Placement.NORMAL)
	if _thrown and not _measured and _pc.phase == PlayController.Phase.AIR and _pc.ball.flight_time - _pc.ball.flight_elapsed < 0.04:
		# The moment before the ball arrives: where his man is.
		_measured = true
		var man: Player = _man_on(_receiver)
		if man != null and not man.is_down() and _flat(man.position, _receiver.position) <= _game.tuning.cover_radius:
			result["close"] = int(result["close"]) + 1
			if _pc.in_front(_receiver, man) >= FRONT:
				result["front"] = int(result["front"]) + 1
	if _pc.ball_dead or _pc.live_time > MAX_PLAY_TIME:
		if _thrown and _game.get_stat(&"air_hits") > _hits_before:
			result["hit_plays"] = int(result["hit_plays"]) + 1
			if _game.get_stat(&"completions") > _catches_before:
				result["hit_catches"] = int(result["hit_catches"]) + 1
		_end_play()


func _start_play() -> void:
	_game.clock = 1.0e6
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 25.0))
	# Man Cover 1: a man on every receiver.
	_pc.line_up(_play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	# The widest man out: a wideout, whatever order the play lists them in.
	_receiver = _pc.eligible[0]
	for player: Player in _pc.eligible:
		if absf(player.position.z) > absf(_receiver.position.z):
			_receiver = player
	_hits_before = _game.get_stat(&"air_hits")
	_catches_before = _game.get_stat(&"completions")
	_thrown = false
	_measured = false
	_live = true


func _end_play() -> void:
	_live = false
	if not _pc.ball_dead:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
	_left -= 1
	if _left <= 0:
		_close_run()
		_next_run()


func _next_run() -> void:
	_run += 1
	if _run >= _runs.size():
		_judge()
		return
	var run: Dictionary = _runs[_run]
	for key: String in _defaults:
		_game.tuning.set(key, _defaults[key])
	for key: String in QUIET:
		_game.tuning.set(key, QUIET[key])
	var settings: Dictionary = run["set"]
	for key: String in settings:
		_game.tuning.set(key, settings[key])
	_play = null
	for play: OffensePlay in _game.offense_playbook.plays:
		if play.play_name.to_lower().contains(String(run["play"])):
			_play = play
	if _play == null:
		_failures.append("no play named like '%s'" % run["play"])
		_judge()
		return
	_game.stats.clear()
	_results[run["name"]] = {"gap_sum": 0.0, "gap_n": 0, "hit_plays": 0, "hit_catches": 0, "close": 0, "front": 0}
	_left = _plays


## What the run came to, from the counters PlayController keeps.
func _close_run() -> void:
	var result: Dictionary = _results[_runs[_run]["name"]]
	for key: StringName in [&"undercut_tries", &"air_hit_tries", &"air_hits", &"completions", &"passes"]:
		result[String(key)] = _game.get_stat(key)


func _judge() -> void:
	physics_frame.disconnect(_tick)
	_run = _runs.size()
	for key: String in _defaults:
		_game.tuning.set(key, _defaults[key])
	if _failures.is_empty():
		var off: Dictionary = _results["front off"]
		var on: Dictionary = _results["front on"]
		var share_off: float = _front_share(off)
		var share_on: float = _front_share(on)
		print("front: defender in front of the receiver on %.0f%% of throws with the undercut, %.0f%% without (%d tries in %d passes; his man was close on %d and %d of them)" % [100.0 * share_on, 100.0 * share_off, int(on["undercut_tries"]), int(on["passes"]), int(on["close"]), int(off["close"])])
		_expect(int(on["undercut_tries"]) * 2 >= int(on["passes"]), "front: the defender tried to get in front on fewer than half the throws")
		_expect(int(on["close"]) >= 5 and int(off["close"]) >= 5, "front: too few throws with his man close to judge by")
		_expect(share_on >= 0.6 and share_on >= share_off + 0.3, "front: he is not in front of the receiver much more often for trying")
		_expect(int(off["undercut_tries"]) == 0, "front: tries with the chance at zero")

		off = _results["hit off"]
		on = _results["hit on"]
		print("hit: %d dives at the receiver in %d passes, %d landed, %d of the men hit still caught it; %d catches against %d without" % [int(on["air_hit_tries"]), int(on["passes"]), int(on["air_hits"]), int(on["hit_catches"]), int(on["completions"]), int(off["completions"])])
		_expect(int(off["air_hit_tries"]) == 0, "hit: dives at the receiver with the chance at zero")
		_expect(int(on["air_hit_tries"]) >= 5, "hit: fewer than 5 dives at the receiver in %d passes" % int(on["passes"]))
		_expect(int(on["air_hits"]) * 2 >= int(on["air_hit_tries"]), "hit: fewer than half the dives landed")
		_expect(int(on["hit_catches"]) == 0, "hit: a receiver who was knocked down caught the ball")

		var tight_short: float = _gap(_results["tight short"])
		var off_short: float = _gap(_results["off short"])
		var tight_deep: float = _gap(_results["tight deep"])
		var off_deep: float = _gap(_results["off deep"])
		print("technique: gap to his man 4 yd downfield %.1f yd playing off, %.1f tight; 16 yd downfield %.1f and %.1f" % [off_short, tight_short, off_deep, tight_deep])
		_expect(off_short >= tight_short + 1.0, "technique: playing off is not a yard looser on a short route")
		_expect(absf(off_deep - tight_deep) <= 1.0, "technique: playing off is still a yard different 16 yards downfield")
	for failure: String in _failures:
		print("FAIL: " + failure)
	print("coverage_check %s" % ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)


func _front_share(result: Dictionary) -> float:
	return float(result["front"]) / float(maxi(int(result["close"]), 1))


func _gap(result: Dictionary) -> float:
	return float(result["gap_sum"]) / float(maxi(int(result["gap_n"]), 1))


func _man_on(receiver: Player) -> Player:
	for defender: Player in _pc.defense.players:
		if defender.brain.def_assign.job == DefenseAssignment.Job.MAN and defender.brain.man_target == receiver:
			return defender
	return null


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
