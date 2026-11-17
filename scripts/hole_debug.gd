class_name HoleDebug
extends Node3D
## Debug drawing for runs at a hole, switched on with Tuning.hole_debug (it can
## be ticked while the game runs). On such a play it shows:
## - the lane at the hole as a strip on the turf, as wide as the room clear of
##   bodies: green while a back crossing there would get his burst, red when
##   the lane is too narrow or the hole has closed;
## - a yellow line from each lineman to the defender he was given;
## - a blue line on each defender tied up at the hole, pointing the way he is
##   being moved, longer the faster he goes;
## - seconds since the snap and the width of the lane, over the hole.
## See PlayController._assign_run_blocks, hole_lane and _drive_block.

const OPEN: Color = Color(0.2, 1.0, 0.3, 0.55)
const SHUT: Color = Color(1.0, 0.2, 0.15, 0.55)
const ASSIGNED: Color = Color(1.0, 0.9, 0.1)
const DRIVEN: Color = Color(0.2, 0.7, 1.0)

var _game: Game
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _label: Label3D = Label3D.new()


func setup(game: Game) -> void:
	_game = game
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = _mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.012
	_label.outline_size = 8
	add_child(_label)


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	var pc: PlayController = _game.play_controller
	_label.visible = false
	if not _game.tuning.hole_debug or pc.off_play == null or not pc.has_run_hole or pc.ball_dead:
		return
	var tuning: Tuning = _game.tuning
	var lane: Vector2 = pc.hole_lane()
	var open: bool = lane.y >= tuning.hole_burst_min_width and pc.live_time <= tuning.hole_close_time
	var color: Color = OPEN if open else SHUT
	var half: float = maxf(lane.y * 0.5, 0.05)
	var back: float = pc.los_x - pc.off_dir * 1.5
	var front: float = pc.los_x + pc.off_dir * 2.0
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for corner: Vector2 in [Vector2(back, -half), Vector2(front, -half), Vector2(front, half), Vector2(back, -half), Vector2(front, half), Vector2(back, half)]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(Vector3(corner.x, 0.06, lane.x + corner.y))
	_mesh.surface_end()

	var lines: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var up: Vector3 = Vector3(0.0, 1.1, 0.0)
	for player: Player in pc.offense.players:
		if player.block_target != null and not player.is_down() and not player.block_target.is_down():
			lines.append_array([player.position + up, player.block_target.position + up])
			colors.append_array([ASSIGNED, ASSIGNED])
	for player: Player in pc.defense.players:
		if player.hole_block and player.block_slow_timer > 0.0:
			var reach: float = 0.4 + player.block_drive * 0.3
			lines.append_array([player.position + up * 1.5, player.position + up * 1.5 + Vector3(0.0, 0.0, player.block_drive_side * reach)])
			colors.append_array([DRIVEN, DRIVEN])
	if not lines.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i: int in lines.size():
			_mesh.surface_set_color(colors[i])
			_mesh.surface_add_vertex(lines[i])
		_mesh.surface_end()

	_label.visible = true
	_label.position = Vector3(pc.los_x, 3.2, pc.run_hole.z)
	_label.modulate = color
	_label.text = "%.1f s   lane %.1f yd" % [pc.live_time, lane.y]
