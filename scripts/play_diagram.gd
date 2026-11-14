class_name PlayDiagram
extends Control
## Chalkboard drawing of one play, made from the play resource itself so it
## always matches what the players will do.
## Both are drawn with the line of scrimmage low on the board and the deep men
## above it. Left and right are as the person sees them on the field when they
## play that side: from behind the offense, or from behind the defense.

const LATERAL: float = 21.0
## Yards shown past the line of scrimmage and behind it, for an offensive play.
const OFFENSE_AHEAD: float = 21.0
const OFFENSE_BEHIND: float = 9.0
const DEFENSE_AHEAD: float = 26.0
const DEFENSE_BEHIND: float = 7.0

const LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.28)
const ROUTE_COLOR: Color = Color(1.0, 0.85, 0.2)
const RUN_COLOR: Color = Color(1.0, 0.5, 0.15)
const QB_COLOR: Color = Color(1.0, 1.0, 1.0)
const BLOCK_COLOR: Color = Color(0.85, 0.88, 0.9)
const RUSH_COLOR: Color = Color(1.0, 0.36, 0.3)
const MAN_COLOR: Color = Color(0.45, 0.9, 0.45)
const ZONE_COLOR: Color = Color(0.4, 0.7, 1.0)
const DEEP_COLOR: Color = Color(0.75, 0.6, 1.0)
const SPY_COLOR: Color = Color(1.0, 0.7, 0.25)

var _offense: OffensePlay
var _defense: DefensePlay
## Drawn mirrored left to right.
var _flipped: bool = false


func set_flipped(flipped: bool) -> void:
	_flipped = flipped
	queue_redraw()


func show_offense(play: OffensePlay) -> void:
	_offense = play
	_defense = null
	queue_redraw()


func show_defense(play: DefensePlay) -> void:
	_defense = play
	_offense = null
	queue_redraw()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if _offense != null:
		_draw_offense()
	elif _defense != null:
		_draw_defense()


# --- Offense ---------------------------------------------------------------------

func _draw_offense() -> void:
	var los_a: Vector2 = _off_point(Vector2(0.0, -LATERAL))
	var los_b: Vector2 = _off_point(Vector2(0.0, LATERAL))
	draw_line(los_a, los_b, LINE_COLOR, 1.0, true)
	for assignment: OffenseAssignment in _offense.assignments:
		var start: Vector2 = _off_point(assignment.start)
		match assignment.job:
			OffenseAssignment.Job.QB:
				_draw_path(assignment, QB_COLOR, 1.5, false)
				draw_circle(start, 4.0, QB_COLOR, true, -1.0, true)
			OffenseAssignment.Job.BLOCK:
				draw_circle(start, 3.5, BLOCK_COLOR, false, 1.5, true)
			OffenseAssignment.Job.RUNNER:
				_draw_path(assignment, RUN_COLOR, 2.5, true)
				draw_circle(start, 4.0, RUN_COLOR, true, -1.0, true)
			_:
				_draw_path(assignment, ROUTE_COLOR, 2.0, not assignment.settle)
				draw_circle(start, 4.0, ROUTE_COLOR, true, -1.0, true)


func _draw_path(assignment: OffenseAssignment, color: Color, width: float, arrow: bool) -> void:
	if assignment.route.is_empty():
		return
	var points: PackedVector2Array = PackedVector2Array([_off_point(assignment.start)])
	var top: float = OFFENSE_AHEAD - 1.5
	var previous: Vector2 = assignment.start
	for waypoint: Vector2 in assignment.route:
		var point: Vector2 = assignment.start + waypoint
		# A route that runs off the top of the board is cut where it leaves.
		if point.x > top and previous.x < top:
			point = previous.lerp(point, (top - previous.x) / (point.x - previous.x))
			points.append(_off_point(point))
			break
		points.append(_off_point(point))
		previous = point
	draw_polyline(points, color, width, true)
	var tip: Vector2 = points[points.size() - 1]
	var from: Vector2 = points[points.size() - 2]
	if arrow:
		_draw_arrow_head(from, tip, color)
	else:
		# A route that stops: a short bar across the end.
		var across: Vector2 = (tip - from).normalized().orthogonal() * 4.0
		draw_line(tip - across, tip + across, color, width, true)


func _off_point(play_point: Vector2) -> Vector2:
	var lateral: float = -play_point.y if _flipped else play_point.y
	var u: float = (lateral + LATERAL) / (2.0 * LATERAL)
	var v: float = (OFFENSE_AHEAD - play_point.x) / (OFFENSE_AHEAD + OFFENSE_BEHIND)
	return Vector2(u * size.x, v * size.y)


# --- Defense ---------------------------------------------------------------------

func _draw_defense() -> void:
	draw_line(_def_point(Vector2(0.0, -LATERAL)), _def_point(Vector2(0.0, LATERAL)), LINE_COLOR, 1.0, true)
	# Where the pass rush is headed: a few yards behind the ball.
	var qb_spot: Vector2 = Vector2(-4.5, 0.0)

	# Zones first so the players are drawn on top of them.
	for assignment: DefenseAssignment in _defense.assignments:
		if assignment.job == DefenseAssignment.Job.ZONE:
			var color: Color = DEEP_COLOR if assignment.deep else ZONE_COLOR
			_draw_zone(assignment.zone_center, assignment.zone_radius * 0.6, color)
	for assignment: DefenseAssignment in _defense.assignments:
		var start: Vector2 = _def_point(assignment.start)
		match assignment.job:
			DefenseAssignment.Job.RUSH:
				var target: Vector2 = _def_point(assignment.start.lerp(qb_spot, 0.75))
				draw_line(start, target, RUSH_COLOR, 1.5, true)
				_draw_arrow_head(start, target, RUSH_COLOR)
				draw_circle(start, 3.0, RUSH_COLOR, true, -1.0, true)
			DefenseAssignment.Job.MAN:
				# Man coverage: a dashed line toward the receiver across the line.
				var across: Vector2 = _def_point(Vector2(0.4, assignment.start.y))
				draw_dashed_line(start, across, MAN_COLOR, 1.5, 3.0, true, true)
				draw_rect(Rect2(start - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), MAN_COLOR, true)
			DefenseAssignment.Job.ZONE:
				var color: Color = DEEP_COLOR if assignment.deep else ZONE_COLOR
				var center: Vector2 = _def_point(assignment.zone_center)
				if start.distance_to(center) > 5.0:
					draw_line(start, center, color, 1.5, true)
				draw_circle(start, 4.0, color, true, -1.0, true)
			DefenseAssignment.Job.SPY:
				# A spy: a dashed line at the quarterback.
				draw_dashed_line(start, _def_point(assignment.start.lerp(qb_spot, 0.6)), SPY_COLOR, 1.5, 3.0, true, true)
				draw_circle(start, 4.0, SPY_COLOR, true, -1.0, true)


func _draw_zone(center: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		var angle: float = TAU * float(i) / 24.0
		points.append(_def_point(center + Vector2(cos(angle), sin(angle)) * radius))
	var fill: Color = color
	fill.a = 0.16
	draw_colored_polygon(points, fill)
	var edge: Color = color
	edge.a = 0.7
	draw_polyline(points, edge, 1.0, true)


func _def_point(play_point: Vector2) -> Vector2:
	var lateral: float = -play_point.y if _flipped else play_point.y
	var u: float = (LATERAL - lateral) / (2.0 * LATERAL)
	var v: float = (DEFENSE_AHEAD - play_point.x) / (DEFENSE_AHEAD + DEFENSE_BEHIND)
	return Vector2(u * size.x, v * size.y)


# --- Shared ----------------------------------------------------------------------

func _draw_arrow_head(from: Vector2, tip: Vector2, color: Color) -> void:
	var dir: Vector2 = tip - from
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	var side: Vector2 = dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip + dir * 3.0, tip - dir * 5.0 + side * 4.0, tip - dir * 5.0 - side * 4.0]), color)
