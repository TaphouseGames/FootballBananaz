class_name DefenseAssignment
extends Resource
## One defender's job in a play.
## Coordinates are in the offense's frame: x = yards downfield from the line of
## scrimmage (positive = the defense's side), y = yards lateral from the ball.

enum Job { RUSH, MAN, ZONE }

@export var label: String = "DB"
@export var job: Job = Job.MAN
## Lineup spot. MAN defenders slide laterally to line up across from their man.
@export var start: Vector2 = Vector2(5.0, 0.0)
## MAN: which offensive player to cover. 0 = first eligible receiver in the
## offensive play, 1 = second, and so on (blockers split wide come last).
@export var man_target: int = 0
## ZONE: centre and radius of the area to guard.
@export var zone_center: Vector2 = Vector2(10.0, 0.0)
@export var zone_radius: float = 9.0
## ZONE: a deep defender stays over the top of the deepest receiver in his area
## instead of sitting on him.
@export var deep: bool = false
