extends SceneTree
## Measures how far any part of a player gets into the wall round the field
## while the CPU plays both teams: every bone of every player and mascot, every
## frame. Prints the worst case for each game state, player state and kind of
## fall, and fails if anything is deeper in than MAX_DEPTH.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/wall_probe.gd -- [seconds=<game seconds>]

const SPEED: float = 8.0
## A bone is the middle of a limb, so this much of it is the limb's own
## thickness: deeper than that and the body is showing through the wall.
const MAX_DEPTH: float = 0.02

var _game: Game
var _seconds: float = 240.0
var _frames: int = 0
## Key -> [worst depth, frames over MAX_DEPTH, frames seen, where].
var _worst: Dictionary = {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_seconds = float(arg.trim_prefix("seconds="))
	Game.base_time_scale = SPEED
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = roundi(SPEED)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or _game.play_controller == null:
		return false
	_frames += 1
	var state: StringName = _game.play_controller.state_machine.current_name()
	for team: Team in [_game.home, _game.away]:
		for player: Player in team.players:
			_measure(player, state)
		if team.mascot != null:
			_measure(team.mascot, state)
	if float(_frames) * SPEED / 60.0 < _seconds and state != &"GameOver":
		return false
	return _report()


func _measure(player: Player, state: StringName) -> void:
	if player.animator == null or not player.visible:
		return
	var skeleton: Skeleton3D = player.animator.skeleton
	var to_world: Transform3D = skeleton.global_transform
	var deepest: float = -100.0
	var bone_name: String = ""
	for i: int in skeleton.get_bone_count():
		var at: Vector3 = to_world * skeleton.get_bone_global_pose(i).origin
		var depth: float = Stadium.wall_distance(_game.tuning, at.x, at.z)
		if depth > deepest and at.y < Stadium.WALL_HEIGHT:
			deepest = depth
			bone_name = skeleton.get_bone_name(i)
	var kind: String = PlayerFall.Kind.keys()[player.fall.kind] if player.fall.active else "-"
	var key: String = "%-12s %-10s %-10s%s" % [state, Player.State.keys()[player.state], kind, " mascot" if player is Mascot else ""]
	var row: Array = _worst.get(key, [-100.0, 0, 0, ""])
	row[2] += 1
	if deepest > MAX_DEPTH:
		row[1] += 1
	if deepest > row[0]:
		row[0] = deepest
		row[3] = "%s, centre %.2f from the wall" % [bone_name, -Stadium.wall_distance(_game.tuning, player.position.x, player.position.z)]
	_worst[key] = row


func _report() -> bool:
	var keys: Array = _worst.keys()
	keys.sort()
	var bad: int = 0
	print("game state   player     fall        deepest  frames in  of      worst bone")
	for key: String in keys:
		var row: Array = _worst[key]
		if row[0] <= 0.0:
			continue
		bad += int(row[0] > MAX_DEPTH)
		print("%s %6.2f  %8d  %-7d %s" % [key, row[0], row[1], row[2], row[3]])
	print("wall_probe %s" % ("PASSED" if bad == 0 else "FAILED: %d cases deeper than %.2f yd in the wall" % [bad, MAX_DEPTH]))
	_game.free()
	_game = null
	quit(0 if bad == 0 else 1)
	return true
