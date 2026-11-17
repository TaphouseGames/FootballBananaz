class_name DefenseAssignment
extends Resource
## One defender's job in a play.
## Coordinates are in the offense's frame: x = yards downfield from the line of
## scrimmage (positive = the defense's side), y = yards lateral from the ball.

## SPY: shadow the quarterback from a few yards past the line and go for him the
## moment he runs.
enum Job { RUSH, MAN, ZONE, SPY }

## How the drawn lineup spot is fitted to the offense's formation before the
## snap (see DefenseAligner). A MAN defender always lines up across from his
## man, whatever this says.
## SPOT: where the play draws him: the line, a blitzer in the box.
## OUTSIDE: a corner. Out with the widest receiver of his side at his drawn
##   depth; in to the edge of the formation when nobody is split out there.
## SLOT: walks out over a slot or wing nobody else has on his side, and slides
##   toward the strong side otherwise.
## STRENGTH: slides toward the side with more receivers: safeties, the men in
##   the middle.
enum Align { SPOT, OUTSIDE, SLOT, STRENGTH }

@export var label: String = "DB"
@export var job: Job = Job.MAN
## Lineup spot as drawn: `x` is his depth, `y` puts him on a side.
@export var start: Vector2 = Vector2(5.0, 0.0)
@export var align: Align = Align.SPOT
## MAN: which offensive player to cover, by where he lines up: 0 = the widest
## receiver on the left, 1 = the widest on the right, 2 = the back, 3 = whoever
## is left (tight end, fullback, a slot). See DefenseAligner.man_order.
@export var man_target: int = 0
## MAN: play in front of the receiver, between him and the quarterback, instead
## of on his deep side. For a second defender on a man who is already covered.
@export var underneath: bool = false
## MAN: a green dog. When the man he covers stays in to block, he rushes the
## quarterback instead of standing over a blocker.
@export var green_dog: bool = false
## ZONE: centre and radius of the area to guard.
@export var zone_center: Vector2 = Vector2(10.0, 0.0)
@export var zone_radius: float = 9.0
## ZONE: a deep defender stays over the top of the deepest receiver in his area
## instead of sitting on him.
@export var deep: bool = false
