class_name PlayArt
extends Node3D
## A play drawn on the turf before the snap, from where the players stand:
## routes, runs and the motion for an offense; rushes, man coverage and zones
## for a defense. The colours are those of the play-select cards (PlayDiagram).
##
## PreSnapState decides which play is shown: the one that was called, or a fake
## from the same formation. Every play of a formation lines up on the same
## spots, so a fake starts under the same feet as the real one.

## Above the turf's paint and the marks players leave on it.
const HEIGHT: float = 0.07
const WIDTH: float = 0.22
const THIN: float = 0.14
const DASH: float = 0.7
const GAP: float = 0.5
const ARROW: float = 0.9
const ALPHA: float = 0.9
## The route a man has now, under a hot route that is being shown for him.
const FAINT: float = 0.3
const ZONE_FILL: float = 0.16
const ZONE_STEPS: int = 32

## The play drawn right now (an OffensePlay or a DefensePlay), or null.
var shown: Resource
## Triangles in the drawing as it was last built.
var triangles: int = 0
## A hot route the person is looking at before calling it: the man it would go
## to and the route, drawn over the one he has. Null with none.
var hot_preview_man: Player
var hot_preview: OffenseAssignment

var _game: Game
var _flipped: bool = false
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _points: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()


func setup(game: Game) -> void:
	_game = game
	# Rebuilt every frame from where the players are drawn.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 3
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = _mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func show_offense(play: OffensePlay, flipped: bool) -> void:
	_show(play, flipped)


func show_defense(play: DefensePlay, flipped: bool) -> void:
	_show(play, flipped)


## Shows `assignment` as the route of `man`, for as long as the called play is
## drawn (see PreSnapState: a hot route with the left trigger held).
func set_hot_preview(man: Player, assignment: OffenseAssignment) -> void:
	hot_preview_man = man
	hot_preview = assignment


func clear_hot_preview() -> void:
	hot_preview_man = null
	hot_preview = null


func clear() -> void:
	clear_hot_preview()
	if shown == null:
		return
	shown = null
	triangles = 0
	_mesh.clear_surfaces()


func _show(play: Resource, flipped: bool) -> void:
	if play == null:
		clear()
		return
	shown = play
	_flipped = flipped
	_rebuild()


func _process(_delta: float) -> void:
	# A man in motion and whoever goes with him move under the drawing.
	if shown != null:
		_rebuild()


func _rebuild() -> void:
	_points.clear()
	_colors.clear()
	var pc: PlayController = _game.play_controller
	if pc.offense != null and pc.defense != null:
		if shown is OffensePlay:
			_draw_offense(pc, shown as OffensePlay)
		elif shown is DefensePlay:
			_draw_defense(pc, shown as DefensePlay)
	_mesh.clear_surfaces()
	triangles = _points.size() / 3
	if _points.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in _points.size():
		_mesh.surface_set_color(_colors[i])
		_mesh.surface_add_vertex(_points[i])
	_mesh.surface_end()


# --- Offense ---------------------------------------------------------------------

func _draw_offense(pc: PlayController, play: OffensePlay) -> void:
	var flip: float = -1.0 if _flipped else 1.0
	var motion: PreSnapMotion = pc.motion
	var called: bool = motion.state == PreSnapMotion.State.MOVING or motion.state == PreSnapMotion.State.SET
	var players: Array[Player] = pc.offense.players
	for i: int in players.size():
		var player: Player = players[i]
		var as_drawn: OffenseAssignment = play.assignments[mini(i, play.assignments.size() - 1)]
		var assignment: OffenseAssignment = as_drawn
		# A hot route given at the line is the route he runs.
		if play == pc.off_play and pc.hot_routes.has(player):
			assignment = pc.hot_routes[player]
		var path: PackedVector3Array = PackedVector3Array([_flat(player.position)])
		if called and play == pc.off_play and player == motion.man:
			# The man in motion: the job the snap would give him now.
			assignment = _motion_job(play, as_drawn, motion)
			if assignment == null:
				continue
			if motion.state == PreSnapMotion.State.MOVING and assignment != as_drawn:
				path.append(_flat(pc.to_world(assignment.start, flip)))
		if play == pc.off_play and player == hot_preview_man and hot_preview != null:
			# A hot route being looked at: white, over the route he has now.
			_draw_route(pc, play, assignment, path.duplicate(), flip, FAINT)
			_draw_route(pc, play, hot_preview, path, flip, ALPHA, PlayDiagram.QB_COLOR)
		else:
			_draw_route(pc, play, assignment, path, flip)
	# Not the called play's once its man has a hot route, or is shown one: it is
	# off then.
	var hot_shown: bool = play == pc.off_play and hot_preview_man != null and hot_preview_man == motion.man
	if not called and not hot_shown and (play != pc.off_play or motion.available()):
		_draw_motion(pc, play, flip)


## One man's job from the end of `path` (where he stands, or where his motion
## takes him): a line along his route with an arrow, or a bar where he stops.
## `ink` in place of the job's own colour when it is not transparent.
func _draw_route(pc: PlayController, play: OffensePlay, assignment: OffenseAssignment, path: PackedVector3Array, flip: float, alpha: float = ALPHA, ink: Color = Color.TRANSPARENT) -> void:
	if assignment.route.is_empty():
		return
	var color: Color = PlayDiagram.ROUTE_COLOR
	var width: float = WIDTH
	var arrow: bool = not assignment.settle
	match assignment.job:
		OffenseAssignment.Job.QB:
			color = PlayDiagram.QB_COLOR
			width = THIN
			arrow = false
		OffenseAssignment.Job.BLOCK:
			# A lead blocker's path is only there on a run play.
			if not play.is_run:
				return
			color = PlayDiagram.BLOCK_COLOR
			width = THIN
		OffenseAssignment.Job.RUNNER:
			color = PlayDiagram.RUN_COLOR
	if ink.a > 0.0:
		color = ink
	var base: Vector3 = path[path.size() - 1]
	var drawn: Vector3 = pc.to_world(assignment.start, flip)
	for waypoint: Vector2 in assignment.route:
		path.append(_flat(base + pc.to_world(assignment.start + waypoint, flip) - drawn))
	_polyline(path, color, width, alpha)
	var tip: Vector3 = path[path.size() - 1]
	var from: Vector3 = path[path.size() - 2]
	if arrow:
		_arrow_head(from, tip, color, alpha)
	else:
		_end_bar(from, tip, color, width, alpha)


## The job of the man in motion were the ball snapped now (see
## PreSnapMotion.settle); null when he would only block.
func _motion_job(play: OffensePlay, drawn: OffenseAssignment, motion: PreSnapMotion) -> OffenseAssignment:
	match play.motion:
		OffensePlay.Motion.RETURN:
			return drawn
		OffensePlay.Motion.JET:
			if motion.state == PreSnapMotion.State.SET:
				return play.motion_set_assignment
	return play.motion_assignment if play.motion_assignment != null else drawn


## The motion (LB) or (RB) would send a receiver on: a dashed line along his way.
func _draw_motion(pc: PlayController, play: OffensePlay, flip: float) -> void:
	var path: PackedVector2Array = MotionRules.path(play)
	var index: int = MotionRules.pick(play)
	if path.is_empty() or index < 0 or index >= pc.offense.players.size():
		return
	var from: Vector3 = _flat(pc.offense.players[index].position)
	var color: Color = PlayDiagram.MOTION_COLOR
	if play.motion == OffensePlay.Motion.RETURN:
		var turn: Vector3 = _flat(pc.to_world(path[0], flip))
		_dashed(from, turn, color, THIN)
		_end_bar(from, turn, color, THIN)
		return
	for point: Vector2 in path:
		var to: Vector3 = _flat(pc.to_world(point, flip))
		_dashed(from, to, color, THIN)
		from = to
	_ring(from, 0.5, color, THIN)


# --- Defense ---------------------------------------------------------------------

func _draw_defense(pc: PlayController, play: DefensePlay) -> void:
	var flip: float = -1.0 if _flipped else 1.0
	var players: Array[Player] = pc.defense.players
	var qb_spot: Vector3 = _flat(pc.qb.position) if pc.qb != null else _flat(pc.to_world(Vector2(-4.5, 0.0)))
	for i: int in players.size():
		var from: Vector3 = _flat(players[i].position)
		var assignment: DefenseAssignment = play.assignments[mini(i, play.assignments.size() - 1)]
		match assignment.job:
			DefenseAssignment.Job.RUSH:
				var to: Vector3 = from.lerp(qb_spot, 0.75)
				_segment(from, to, PlayDiagram.RUSH_COLOR, WIDTH)
				_arrow_head(from, to, PlayDiagram.RUSH_COLOR)
			DefenseAssignment.Job.MAN:
				var target: Player = pc.man_target_of(assignment, flip)
				if target != null:
					var at: Vector3 = _flat(target.position)
					# Up to his man, not through him.
					_dashed(from, at.move_toward(from, 0.8), PlayDiagram.MAN_COLOR, WIDTH)
			DefenseAssignment.Job.ZONE:
				var color: Color = PlayDiagram.DEEP_COLOR if assignment.deep else PlayDiagram.ZONE_COLOR
				var center: Vector3 = _flat(pc.zone_world(play, assignment, flip))
				_zone(center, assignment.zone_radius * 0.6, color)
				if from.distance_to(center) > 1.0:
					_segment(from, center, color, THIN)
			DefenseAssignment.Job.SPY:
				_dashed(from, from.lerp(qb_spot, 0.6), PlayDiagram.SPY_COLOR, WIDTH)


# --- Shapes ----------------------------------------------------------------------

func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, HEIGHT, point.z)


## The way across a line from `a` to `b`, on the turf.
func _across(a: Vector3, b: Vector3) -> Vector3:
	var along: Vector3 = b - a
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return Vector3.ZERO
	along = along.normalized()
	return Vector3(-along.z, 0.0, along.x)


func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_points.append_array([a, b, c])
	_colors.append_array([color, color, color])


func _segment(a: Vector3, b: Vector3, color: Color, width: float, alpha: float = ALPHA) -> void:
	_polyline(PackedVector3Array([a, b]), color, width, alpha)


## A ribbon through `path`, with its corners joined.
func _polyline(path: PackedVector3Array, color: Color, width: float, alpha: float = ALPHA) -> void:
	var ink: Color = Color(color, alpha)
	var left: PackedVector3Array = PackedVector3Array()
	var right: PackedVector3Array = PackedVector3Array()
	for i: int in path.size():
		var side: Vector3 = Vector3.ZERO
		if i > 0:
			side += _across(path[i - 1], path[i])
		if i < path.size() - 1:
			side += _across(path[i], path[i + 1])
		if side.length_squared() < 0.0001:
			# A point where the line turns straight back, or one drawn twice.
			side = _across(path[maxi(i - 1, 0)], path[mini(i + 1, path.size() - 1)])
			if side == Vector3.ZERO and i > 0:
				side = _across(path[i - 1], path[i])
		side = side.normalized() * width * 0.5
		left.append(path[i] + side)
		right.append(path[i] - side)
	for i: int in path.size() - 1:
		_triangle(left[i], left[i + 1], right[i + 1], ink)
		_triangle(left[i], right[i + 1], right[i], ink)


func _dashed(a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var length: float = a.distance_to(b)
	if length < 0.05:
		return
	var along: Vector3 = (b - a) / length
	var at: float = 0.0
	while at < length:
		_segment(a + along * at, a + along * minf(at + DASH, length), color, width)
		at += DASH + GAP


func _arrow_head(from: Vector3, tip: Vector3, color: Color, alpha: float = ALPHA) -> void:
	var side: Vector3 = _across(from, tip)
	if side == Vector3.ZERO:
		return
	var along: Vector3 = (tip - from).normalized()
	var back: Vector3 = tip - along * ARROW * 0.4
	_triangle(tip + along * ARROW * 0.6, back + side * ARROW * 0.5, back - side * ARROW * 0.5, Color(color, alpha))


## A route that stops: a short bar across its end.
func _end_bar(from: Vector3, tip: Vector3, color: Color, width: float, alpha: float = ALPHA) -> void:
	var side: Vector3 = _across(from, tip) * ARROW * 0.5
	if side != Vector3.ZERO:
		_segment(tip - side, tip + side, color, width, alpha)


func _ring(center: Vector3, radius: float, color: Color, width: float, alpha: float = ALPHA) -> void:
	var path: PackedVector3Array = PackedVector3Array()
	for i: int in ZONE_STEPS + 1:
		var angle: float = TAU * float(i % ZONE_STEPS) / float(ZONE_STEPS)
		path.append(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	_polyline(path, color, width, alpha)


## The area a zone defender guards: a faint disc with an edge.
func _zone(center: Vector3, radius: float, color: Color) -> void:
	var fill: Color = Color(color, ZONE_FILL)
	# A little lower than the lines, which are drawn over it.
	var middle: Vector3 = center - Vector3(0.0, 0.02, 0.0)
	for i: int in ZONE_STEPS:
		var a: float = TAU * float(i) / float(ZONE_STEPS)
		var b: float = TAU * float(i + 1) / float(ZONE_STEPS)
		_triangle(middle, middle + Vector3(cos(a), 0.0, sin(a)) * radius, middle + Vector3(cos(b), 0.0, sin(b)) * radius, fill)
	_ring(center, radius, color, THIN, 0.7)
