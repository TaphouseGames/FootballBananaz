class_name DefenseAssignment
extends Resource
## One defender's job in a play.
## Coordinates are in the offense's frame: x = yards downfield from the line of
## scrimmage (positive = the defense's side), y = yards lateral from the ball.

## SPY: shadow the quarterback from a few yards past the line and go for him the
## moment he runs.
enum Job { RUSH, MAN, ZONE, SPY }

@export var label: String = "DB"
@export var job: Job = Job.MAN
## Lineup spot. MAN defenders slide laterally to line up across from their man.
@export var start: Vector2 = Vector2(5.0, 0.0)
## MAN: which offensive player to cover. 0 = first eligible receiver in the
## offensive play, 1 = second, and so on (blockers split wide come last).
@export var man_target: int = 0
## MAN: play in front of the receiver, between him and the quarterback, instead
## of on his deep side. For a second defender on a man who is already covered.
@export var underneath: bool = false
## ZONE: centre and radius of the area to guard.
@export var zone_center: Vector2 = Vector2(10.0, 0.0)
@export var zone_radius: float = 9.0
## ZONE: a deep defender stays over the top of the deepest receiver in his area
## instead of sitting on him.
@export var deep: bool = false
