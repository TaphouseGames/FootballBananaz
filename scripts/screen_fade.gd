class_name ScreenFade
extends CanvasLayer
## A black screen over everything, for short dips between shots and scenes, and
## a helper that fades menus in and out.
## Not an autoload (the tests run with --script): ScreenFade.of() makes it the
## first time it is asked for and hangs it on the root, so it outlives scene
## changes. Without a window (the headless tests) every fade is instant.

## Seconds to go to black, and to come back up from it.
const FADE_OUT: float = 0.18
const FADE_IN: float = 0.25
## Seconds a menu takes to fade in or out.
const MENU_FADE: float = 0.12

## Off makes every fade instant.
static var enabled: bool = true
static var _instance: ScreenFade

var _black: ColorRect
var _tween: Tween
## Held so tweens can be made before the layer is in the tree.
var _tree: SceneTree
## In the middle of a change of scene: nothing else moves the black meanwhile.
var _changing: bool = false


static func of(tree: SceneTree) -> ScreenFade:
	if not is_instance_valid(_instance):
		_instance = ScreenFade.new()
		_instance.name = &"ScreenFade"
		_instance._tree = tree
		tree.root.add_child.call_deferred(_instance)
		# Ready at once, though it only goes into the tree at the end of the frame.
		_instance._build()
	return _instance


## Fades are on and there is a window to see them in. The test scripts (run
## with --script, so the SceneTree has a script) get none either: their
## timings and screenshots would not want them.
static func active() -> bool:
	return enabled and DisplayServer.get_name() != "headless" and Engine.get_main_loop().get_script() == null


## Fades `control` in (showing it first) or out (hiding it at the end).
## `paused` keeps the fade going while the tree is paused (the pause menu).
static func pop(control: CanvasItem, show: bool, time: float = MENU_FADE, paused: bool = false) -> void:
	var old: Tween = control.get_meta(&"fade_tween") as Tween if control.has_meta(&"fade_tween") else null
	if old != null and old.is_valid():
		old.kill()
	if not active() or time <= 0.0:
		control.modulate.a = 1.0
		control.visible = show
		return
	if show:
		if not control.visible:
			control.modulate.a = 0.0
		control.visible = true
	elif not control.visible:
		return
	var tween: Tween = control.create_tween()
	if paused:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, ^"modulate:a", 1.0 if show else 0.0, time)
	if not show:
		tween.tween_callback(func() -> void:
			control.visible = false
			control.modulate.a = 1.0)
	control.set_meta(&"fade_tween", tween)


func _build() -> void:
	if _black != null:
		return
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_black = ColorRect.new()
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.visible = false
	add_child(_black)


## Goes to black. Game time and stopped by a pause, unless `paused`.
func cover(time: float = FADE_OUT, paused: bool = false) -> void:
	if not _changing:
		_fade_to(1.0, time, paused)


## Comes back up from black.
func reveal(time: float = FADE_IN, paused: bool = false) -> void:
	if not _changing:
		_fade_to(0.0, time, paused)


func is_covered() -> bool:
	return _black.color.a >= 1.0


## Dips to black, changes to the scene at `path`, and comes back up in it.
func change_scene(path: String) -> void:
	if not active():
		# Deferred: the caller may be in the middle of handling an input event.
		_tree.change_scene_to_file.call_deferred(path)
		return
	if _changing:
		return
	_changing = true
	_fade_to(1.0, FADE_OUT, true)
	if _tween != null:
		await _tween.finished
	_tree.change_scene_to_file(path)
	# The new scene comes in at the end of this frame: up once it is there.
	await _tree.process_frame
	await _tree.process_frame
	_changing = false
	reveal(FADE_IN, true)


func _fade_to(alpha: float, time: float, paused: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if not active() or time <= 0.0:
		_black.color.a = alpha
		_black.visible = alpha > 0.0
		return
	if is_equal_approx(_black.color.a, alpha):
		_black.visible = alpha > 0.0
		return
	_black.visible = true
	_tween = _tree.create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS if paused else Tween.TWEEN_PAUSE_STOP)
	_tween.tween_property(_black, ^"color:a", alpha, time)
	if alpha <= 0.0:
		_tween.tween_callback(_black.hide)
