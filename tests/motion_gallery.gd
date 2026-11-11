extends SceneTree
## Contact sheets (one PNG per sequence, frames left to right) of one player's procedural motion: a walk, run and
## sprint stride, and each kind of knock-down from the hit to getting back up.
## The player is stepped by hand, so every run shows the same moments.
## Needs a window (no --headless), since headless does not render.
##
## Run:  godot --path . --script res://tests/motion_gallery.gd -- out=<folder>

const TICK: float = 1.0 / 60.0
const SPOT: Vector3 = Vector3(60.0, 0.0, 0.0)

var _out_dir: String = "user://motion_gallery"
var _game: Game
var _cam: Camera3D
var _subject: Player
var _strip: Array[Image] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	physics_interpolation = false
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	root.add_child(_game)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	root.add_child(_cam)
	_run()


func _run() -> void:
	await create_timer(0.6).timeout
	# From here on nothing moves unless this script steps it.
	_game.play_controller.set_physics_process(false)
	_game.hud.visible = false
	_subject = _game.home.players[3]

	await _stride("walk", 2.6, false, 5)
	await _stride("run", 1.0, false, 4)
	await _stride("sprint", 1.0, true, 3)
	await _backpedal()

	var k: Tuning = _game.tuning
	var ahead: Vector3 = Vector3.RIGHT
	var side: Vector3 = Vector3.BACK
	await _knockdown("front_high", ahead * 7.0, -ahead * 10.0, PlayerFall.Kind.HIGH, false, false)
	await _knockdown("behind_high", ahead * 7.0, ahead * 10.0, PlayerFall.Kind.HIGH, false, false)
	await _knockdown("side_high", ahead * 7.0, side * 10.0, PlayerFall.Kind.HIGH, false, false)
	await _knockdown("low_flip", ahead * 9.0, -ahead * 8.0, PlayerFall.Kind.LOW, false, true)
	await _knockdown("low_trip", ahead * 4.0, side * 8.0, PlayerFall.Kind.LOW, false, false)
	await _knockdown("airborne", ahead * 6.0, -ahead * 8.0, PlayerFall.Kind.HIGH, true, false)
	await _knockdown("wrap", ahead * 7.0, (side - ahead * 0.3).normalized() * 8.0, PlayerFall.Kind.WRAP, false, false)
	await _knockdown("pancake", Vector3.ZERO, -ahead * 4.0, PlayerFall.Kind.PANCAKE, false, false, k.block_beaten_time)
	await _knockdown("bounce_off", ahead * 6.0, -ahead * 3.0, PlayerFall.Kind.BOUNCE_OFF, false, false, k.broken_tackle_stun)
	await _dive()
	quit(0)


func _place(velocity: Vector3) -> void:
	_subject.reset_for_play(SPOT, Vector3.RIGHT)
	_subject.frozen = false
	_subject.velocity = velocity
	_subject.move_input = velocity.normalized()


func _step(ticks: int) -> void:
	for i: int in ticks:
		_subject.integrate(TICK)


## Six frames spread over one stride cycle, from the side.
func _stride(label: String, speed_divisor: float, turbo: bool, gap: int) -> void:
	_place(Vector3.ZERO)
	_subject.move_input = Vector3.RIGHT / speed_divisor
	_subject.wants_turbo = turbo
	_step(50)
	for i: int in 6:
		_step(gap)
		await _shot(5.5)
	_subject.wants_turbo = false
	_save_sheet(label)


## A quarterback dropping back: moving one way, facing the other.
func _backpedal() -> void:
	_place(Vector3.ZERO)
	_subject.look_dir = Vector3.RIGHT
	for i: int in 6:
		for tick: int in 6 if i > 0 else 30:
			_subject.move_input = Vector3.LEFT * 0.8
			_subject.integrate(TICK)
		await _shot(5.5)
	_subject.look_dir = Vector3.ZERO
	_save_sheet("backpedal")


func _knockdown(label: String, velocity: Vector3, impulse: Vector3, kind: PlayerFall.Kind, jump: bool, want_flip: bool, duration: float = 1.1) -> void:
	for attempt: int in 40:
		_place(velocity)
		_step(20)
		if jump:
			_subject.start_jump()
			_step(10)
		_subject.move_input = Vector3.ZERO
		_subject.knock_down(impulse, duration, kind)
		if _subject.fall.flip == want_flip:
			break
	var total: int = int(duration * 60.0)
	var at: Array[int] = [4, 10, 17, 26, total - 22, total - 12, total - 4]
	var done: int = 0
	for i: int in at.size():
		_step(at[i] - done)
		done = at[i]
		await _shot(7.0)
	_save_sheet(label)


func _dive() -> void:
	_place(Vector3.RIGHT * 7.0)
	_step(20)
	_subject.start_dive(Vector3.RIGHT)
	var at: Array[int] = [6, 14, 20, 28, 45, 54, 60]
	var done: int = 0
	for i: int in at.size():
		_step(at[i] - done)
		done = at[i]
		await _shot(7.0)
	_save_sheet("dive")


func _shot(distance: float) -> void:
	var target: Vector3 = _subject.position + Vector3(0.0, 1.0, 0.0)
	_cam.look_at_from_position(target + Vector3(distance * 0.25, 1.2, distance), target, Vector3.UP)
	_cam.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	# Keep the middle of the frame, where the player is.
	var width: int = image.get_width() * 2 / 5
	_strip.append(image.get_region(Rect2i((image.get_width() - width) / 2, 0, width, image.get_height())))


func _save_sheet(label: String) -> void:
	if _strip.is_empty():
		return
	var tile: Vector2i = _strip[0].get_size()
	var sheet: Image = Image.create(tile.x * _strip.size(), tile.y, false, _strip[0].get_format())
	for i: int in _strip.size():
		sheet.blit_rect(_strip[i], Rect2i(Vector2i.ZERO, tile), Vector2i(tile.x * i, 0))
	sheet.save_png(_out_dir.path_join(label + ".png"))
	print("saved ", label)
	_strip.clear()
