extends SceneTree
## Checks the kit painter (tools/kit_painter.gd) without touching any file:
## it opens on a player, points at him, paints a stroke of pants across his
## waist with the mirror on, and undoes it.
##
##   --path . --script res://tests/kit_painter_check.gd [-- player=<id> out=<dir>]
##
## With a window and `out=<dir>` it saves a picture of each view with the
## stroke painted. Headless it checks the same things without the pictures.

var _out: String = ""
var _failures: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
	_run()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var painter: Node3D = (load("res://tools/kit_painter.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(painter)
	# (It is not ready until the tree runs.)
	await process_frame
	await process_frame
	print("opened on %s in %d ms" % [painter._sheet.id if painter._sheet != null else "nobody", Time.get_ticks_msec() - started])
	_check(painter._sheet != null, "no player was opened")
	if painter._sheet == null:
		quit(1)
		return
	for frame: int in 4:
		await process_frame
	var camera: Camera3D = painter._camera
	var tall: float = painter._sheet.tall
	var before: PackedByteArray = painter._sheet.data.duplicate()

	# The middle of the chest is the model; a corner of the window is not.
	_check(painter._point(camera.unproject_position(Vector3(0.0, tall * 0.62, 0.0))), "the chest was not hit")
	_check(painter._hit_normal.z > 0.3, "the chest was hit from behind (normal %s)" % painter._hit_normal)
	_check(not painter._point(Vector2(painter.get_viewport().get_visible_rect().size.x - 4.0, 4.0)), "the corner of the window hit the model")

	painter._set_region(1)
	painter._mirror_box.button_pressed = true
	var from: Vector2 = camera.unproject_position(Vector3(0.0, tall * 0.5, 0.0))
	var to: Vector2 = camera.unproject_position(Vector3(tall * 0.07, tall * 0.5, 0.0))
	started = Time.get_ticks_msec()
	painter._begin_stroke(from)
	painter._paint_to(to)
	painter._end_stroke()
	var took: int = Time.get_ticks_msec() - started
	var changed: int = 0
	var wrong: int = 0
	for i: int in range(0, before.size(), 3):
		if before[i] != painter._sheet.data[i] or before[i + 1] != painter._sheet.data[i + 1] or before[i + 2] != painter._sheet.data[i + 2]:
			changed += 1
			if painter._sheet.data[i] != 0 or painter._sheet.data[i + 1] != 255 or painter._sheet.data[i + 2] != 0:
				wrong += 1
	print("the stroke changed %d texels in %d ms" % [changed, took])
	_check(changed > 200, "the stroke changed only %d texels" % changed)
	_check(wrong == 0, "%d changed texels are not pants" % wrong)
	_check(painter._sheet.unsaved, "the player is not marked as changed")
	_check(painter._sheet.undo.size() == 1, "the stroke is not one step to undo")

	if _out != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(_out)
		for view: int in painter.VIEW_NAMES.size():
			painter._set_view(view)
			for frame: int in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_out.path_join("kit_painter_%d.png" % view))
		# From behind and close, as it is used.
		painter._set_view(0)
		painter._yaw = PI
		painter._distance = tall * 1.6
		painter._point(camera.unproject_position(Vector3(0.0, tall * 0.62, 0.0)))
		for frame: int in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("kit_painter_back.png"))

	painter._undo()
	_check(painter._sheet.data == before, "undo did not bring the mask back")
	painter._redo()
	_check(painter._sheet.data != before, "redo did not paint it again")
	painter._undo()

	# The jersey's second colour on the chest: jersey still, and blue as well.
	painter._mirror_box.button_pressed = false
	painter._set_region(painter.TRIM)
	_check(painter._view == painter.View.HOME, "picking the trim did not show the home kit")
	var chest: Vector2 = camera.unproject_position(Vector3(0.0, tall * 0.62, 0.0))
	painter._point(chest)
	var trim_at: int = (painter._hit_texel().y * painter._sheet.width + painter._hit_texel().x) * 3
	painter._begin_stroke(chest)
	painter._end_stroke()
	_check(painter._sheet.data[trim_at] == 255 and painter._sheet.data[trim_at + 1] == 0 and painter._sheet.data[trim_at + 2] == 255, "the trim is not jersey and blue in the mask")
	if not painter._sheet.shown.is_empty():
		_check(painter._sheet.shown[trim_at] == painter._sheet.shown[trim_at + 2], "the trim is not grey in the texture")
	if _out != "" and DisplayServer.get_name() != "headless":
		for frame: int in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("kit_painter_trim.png"))
	painter._undo()
	_check(painter._sheet.data == before, "undo did not take the trim away")
	painter._set_view(painter.View.AWAY)

	# Skin on the chest and the kit erased beside it: no kit left at either,
	# skin in the texture at the one, the model as it came at the other.
	if painter._sheet.original.is_empty():
		print("no texture as the player came with it: the skin brush is not checked")
	else:
		var sheet: RefCounted = painter._sheet
		var shown_before: PackedByteArray = sheet.shown.duplicate()
		painter._mirror_box.button_pressed = false
		painter._yaw = 0.0
		painter._distance = tall * 2.3
		# (The camera follows in the painter's own frame, which comes after this one's signal.)
		await process_frame
		await process_frame
		var skin_px: Vector2 = camera.unproject_position(Vector3(tall * 0.04, tall * 0.62, 0.0))
		var erase_px: Vector2 = camera.unproject_position(Vector3(-tall * 0.04, tall * 0.62, 0.0))
		painter._point(skin_px)
		var skin_at: int = painter._hit_texel().y * sheet.width + painter._hit_texel().x
		painter._point(erase_px)
		var erase_at: int = painter._hit_texel().y * sheet.width + painter._hit_texel().x
		_check(sheet.data[skin_at * 3] == 255 and sheet.data[erase_at * 3] == 255, "the chest is not jersey to begin with")
		_check(sheet.shown[skin_at * 3] == sheet.shown[skin_at * 3 + 2], "the jersey is not grey in the texture")
		painter._set_region(painter.SKIN)
		painter._begin_stroke(skin_px)
		painter._end_stroke()
		painter._set_region(painter.ERASE)
		painter._begin_stroke(erase_px)
		painter._end_stroke()
		_check(sheet.data[skin_at * 3] == 0 and sheet.data[erase_at * 3] == 0, "kit is left where skin was painted or the kit erased")
		_check(sheet.skin[skin_at * 4 + 3] == 255 and sheet.skin[erase_at * 4 + 3] == 0, "skin is not painted where it should be and nowhere else")
		var painted: Color = Color8(sheet.shown[skin_at * 3], sheet.shown[skin_at * 3 + 1], sheet.shown[skin_at * 3 + 2])
		print("skin %s, painted %s, where the kit was erased %s" % [sheet.tone.to_html(false), painted.to_html(false), Color8(sheet.shown[erase_at * 3], sheet.shown[erase_at * 3 + 1], sheet.shown[erase_at * 3 + 2]).to_html(false)])
		_check(absf(painted.h - sheet.tone.h) < 0.03 and painted.s > 0.1, "what was painted (%s) is not the skin colour (%s)" % [painted.to_html(false), sheet.tone.to_html(false)])
		for k: int in 3:
			_check(sheet.shown[erase_at * 3 + k] == sheet.original[erase_at * 3 + k], "erasing did not bring back the texture the player came with")
		_check(sheet.undo.size() == 2, "skin and erase are not two steps to undo")
		if _out != "" and DisplayServer.get_name() != "headless":
			painter._distance = tall * 0.9
			painter._aim = Vector3(0.0, tall * 0.62, 0.0)
			for frame: int in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_out.path_join("kit_painter_skin.png"))
		painter._undo()
		painter._undo()
		_check(sheet.data == before and sheet.shown == shown_before, "undo did not bring the mask and the texture back")
		var blank: bool = true
		for texel: int in range(0, sheet.width * sheet.height, 7):
			if sheet.skin[texel * 4 + 3] != 0:
				blank = false
		_check(blank, "undo left painted skin behind")
	print("FAILED (%d)" % _failures if _failures > 0 else "PASSED")
	# Nothing is saved: the painter is not asked whether to.
	quit(1 if _failures > 0 else 0)
