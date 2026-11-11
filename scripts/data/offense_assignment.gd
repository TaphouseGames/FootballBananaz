class_name OffenseAssignment
extends Resource
## One offensive player's job in a play.
## Coordinates are in the offense's frame: x = yards downfield from the line of
## scrimmage (negative = backfield), y = yards lateral from the ball.

enum Job { QB, ROUTE, BLOCK, RUNNER }

@export var label: String = "WR"
@export var job: Job = Job.ROUTE
@export var start: Vector2 = Vector2.ZERO
## Waypoints relative to `start`. For the QB this is the drop-back path.
## Receivers keep running in the direction of the last leg.
@export var route: PackedVector2Array = PackedVector2Array()
