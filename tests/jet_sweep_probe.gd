extends SceneTree
## Where a jet sweep ends: the play is snapped as the jet man gets to the
## quarterback, a number of times against a few defenses, and for each run it
## prints when and where he got the ball, where he was 0.5 and 1 s later, and
## where, when and by whom he was brought down.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/jet_sweep_probe.gd
## Optional user args after "--":
##   off=<text>    offensive play whose name contains the text (default "gun counter")
##   def=<text>    only defensive plays whose name contains the text
##   runs=<n>      snaps per defense (default 6)
##   plain         no motion: the play as drawn, for comparison

const Probe: GDScript = preload("res://tests/playbook_probe.gd")
const DT: float = 1.0 / 60.0

var _game: Game
var _pc: PlayController
var _off: String = "gun counter"
var _def: String = ""
var _runs: int = 6
var _plain: bool = false
var _done: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("off="):
			_off = arg.trim_prefix("off=").to_lower()
		elif arg.begins_with("def="):
			_def = arg.trim_prefix("def=").to_lower()
		elif arg.begins_with("runs="):
			_runs = int(arg.trim_prefix("runs="))
		elif arg == "plain":
			_plain = true
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _done or _game == null or not _game.is_node_ready() or _game.play_controller == null or _game.offense == null:
		return
	_done = true
	_pc = _game.play_controller
	_game.tuning.audio_enabled = false
	_game.tuning.ai_scout_strength = 0.0
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.play_name.to_lower().contains(_off):
			play = candidate
			break
	var names: PackedStringArray = ["man cover 1", "zone cover 2", "cover 3", "all-out blitz"]
	for defense: DefensePlay in _game.defense_playbook.plays:
		var name: String = defense.play_name.to_lower()
		if (_def != "" and not name.contains(_def)) or (_def == "" and not names.has(name)):
			continue
		var total: float = 0.0
		for run: int in _runs:
			total += _run(play, defense, run)
		print("%s against %s: %.1f yd a run\n" % [play.play_name, defense.play_name, total / float(_runs)])
	quit(0)


func _run(play: OffensePlay, defense: DefensePlay, run: int) -> float:
	_game.clock = 1.0e6
	_game.start_drive(_game.home, _game.tuning.yard_to_x(_game.home.attack_dir, 30.0))
	_pc.line_up(play, defense)
	var motion: PreSnapMotion = _pc.motion
	if not _plain and motion.call_motion():
		for _i: int in 720:
			motion.tick(DT)
			if motion.state == PreSnapMotion.State.SET or motion.jet_in_window():
				break
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	var carrier: Player = _pc.runner
	var got: float = -1.0
	var notes: PackedStringArray = PackedStringArray()
	for _i: int in 600:
		_pc.simulate(DT)
		if got < 0.0 and _pc.ball.carrier == carrier and _pc.phase == PlayController.Phase.RUN:
			got = _pc.live_time
			notes.append("ball at %.2f s %s" % [got, _at(carrier)])
		for later: float in [0.5, 1.0, 1.5]:
			if got >= 0.0 and absf(_pc.live_time - got - later) < DT * 0.5:
				notes.append("+%.1f s %s" % [later, _at(carrier)])
		if _pc.ball_dead:
			break
	var gain: float = (_pc.dead_spot_x - _pc.los_x) * _pc.off_dir
	var by: String = "nobody"
	if _pc.tackled_by != null and _pc.tackled_by.brain.def_assign != null:
		var assignment: DefenseAssignment = _pc.tackled_by.brain.def_assign
		by = "%s (%s)" % [assignment.label, ["rush", "man", "zone", "spy"][assignment.job]]
	print("  %d: %s, down at %.2f s %s by %s, %+.1f yd%s" % [run + 1, ", ".join(notes), _pc.live_time, _at(_pc.ball.carrier if _pc.ball.carrier != null else carrier), by, gain, "  FUMBLE" if _pc.was_fumble else ""])
	if not _pc.ball_dead:
		_pc.end_play(PlayController.Result.TACKLED, _pc.ball.flat_position().x)
	return gain


func _at(player: Player) -> String:
	var at: Vector2 = Probe.frame(_pc, player.position)
	return "(%.1f, %.1f)" % [at.x, at.y]
