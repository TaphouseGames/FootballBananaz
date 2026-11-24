class_name NetFeel
extends CanvasLayer
## Debug: what a delay on the wire would do to the game, tried out offline before
## there is any online play. Debug builds only; nothing happens until it is
## switched on.
##
##   F9   the delay: off, 50, 100, 150 ms
##   F10  what the delay does:
##        OTHERS LATE   the person's own player answers at once and everybody
##                      else (and the ball, unless he has it) is drawn where
##                      they were that long ago (a player he takes over, or the
##                      ball coming to him, eases across). This is online play with the
##                      own player predicted: tackles, catches and throws are
##                      still decided on where everyone really is.
##        BUTTONS LATE  the person's buttons reach the game that much later.
##                      This is online play with nothing predicted.
##
## OTHERS LATE moves the players' nodes to their old places at the end of every
## physics tick, for the picture, and back again before the next one, so the
## game itself never sees them there.

enum Mode { OTHERS_LATE, BUTTONS_LATE }

const STEPS_MS: Array[int] = [0, 50, 100, 150]
const MODE_NAMES: Array[String] = ["OTHERS LATE (own player predicted)", "BUTTONS LATE (nothing predicted)"]
const TICK_MS: float = 1000.0 / 60.0
## A node that moved further than this in a tick was put there (a new play):
## it is drawn there at once, not slid over.
const JUMP: float = 4.0
## Seconds a node takes to go over from drawn late to drawn where it is (the
## person takes another player, the ball comes into his hands) and back.
const BLEND: float = 0.25

## Where a node really was on each of the last ticks (newest last), and where
## it really is while it is drawn somewhere else.
class Track:
	var node: Node3D
	var places: PackedVector3Array = PackedVector3Array()
	var turns: PackedVector3Array = PackedVector3Array()
	var real_place: Vector3 = Vector3.ZERO
	var real_turn: Vector3 = Vector3.ZERO
	var moved: bool = false
	## 0 drawn where it is, 1 drawn where it was.
	var late: float = 1.0

var delay_ms: int = 0
var mode: Mode = Mode.OTHERS_LATE

var _game: Game
var _tracks: Array[Track] = []
var _label: Label


func setup(game: Game) -> void:
	_game = game
	layer = 80
	# After everything else in the tick: the game has moved everybody by then.
	process_physics_priority = 1000
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 16)
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.3))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	game.get_tree().physics_frame.connect(_before_tick)


## Sets the delay (in ms, to the nearest tick) and what it does.
func set_lag(ms: int, p_mode: Mode = mode) -> void:
	_put_back()
	_tracks.clear()
	delay_ms = maxi(ms, 0)
	mode = p_mode
	var late_buttons: int = _ticks() if mode == Mode.BUTTONS_LATE else 0
	for person: HumanController in _game.humans:
		person.pad.delay = late_buttons
	_label.visible = delay_ms > 0
	_label.text = "NET FEEL  %d ms  %s      F9: delay   F10: mode" % [delay_ms, MODE_NAMES[mode]]


func _ticks() -> int:
	return roundi(delay_ms / TICK_MS)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or not OS.is_debug_build():
		return
	if key.keycode == KEY_F9:
		set_lag(STEPS_MS[(STEPS_MS.find(delay_ms) + 1) % STEPS_MS.size()])
	elif key.keycode == KEY_F10:
		set_lag(delay_ms, Mode.BUTTONS_LATE if mode == Mode.OTHERS_LATE else Mode.OTHERS_LATE)


## The start of a physics tick, before any node's own: everybody back where
## they really are, and the buttons noted.
func _before_tick() -> void:
	if delay_ms <= 0 or get_tree().paused:
		return
	_put_back()
	for person: HumanController in _game.humans:
		person.pad.sample()


func _put_back() -> void:
	for track: Track in _tracks:
		if track.moved and is_instance_valid(track.node):
			track.node.position = track.real_place
			track.node.rotation = track.real_turn
		track.moved = false


## The end of the tick: note where everybody is, and draw the others where
## they were.
func _physics_process(delta: float) -> void:
	if delay_ms <= 0 or mode != Mode.OTHERS_LATE:
		return
	if _tracks.is_empty():
		_gather()
	var keep: int = _ticks() + 1
	for track: Track in _tracks:
		var node: Node3D = track.node
		var jumped: bool = not track.places.is_empty() and node.position.distance_to(track.places[track.places.size() - 1]) > JUMP
		if jumped:
			track.places.clear()
			track.turns.clear()
		track.places.append(node.position)
		track.turns.append(node.rotation)
		while track.places.size() > keep:
			track.places.remove_at(0)
			track.turns.remove_at(0)
		if jumped:
			track.late = 0.0 if _is_own(node) else 1.0
		else:
			track.late = move_toward(track.late, 0.0 if _is_own(node) else 1.0, delta / BLEND)
		if track.late <= 0.0:
			continue
		track.real_place = node.position
		track.real_turn = node.rotation
		var share: float = smoothstep(0.0, 1.0, track.late)
		node.position = track.real_place.lerp(track.places[0], share)
		node.rotation.y = lerp_angle(track.real_turn.y, track.turns[0].y, share)
		track.moved = true
		if jumped:
			node.reset_physics_interpolation()


func _gather() -> void:
	var nodes: Array[Node3D] = [_game.ball]
	for player: Player in _game.play_controller.players:
		nodes.append(player)
	for node: Node3D in nodes:
		var track: Track = Track.new()
		track.node = node
		_tracks.append(track)


## A person's own player, or the ball in his hands: drawn where it is.
func _is_own(node: Node3D) -> bool:
	var player: Player = node as Player
	if player == null:
		player = _game.ball.carrier
	if player == null:
		return false
	for person: HumanController in _game.humans:
		if person.is_active() and person.controlled == player:
			return true
	return false
