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
## Receivers keep running in the direction of the last leg. For a blocker on a
## run play it is the path he leads the carrier along until somebody is there
## to block.
@export var route: PackedVector2Array = PackedVector2Array()
## Stop at the end of the route (curl, hitch, screen) instead of running on.
@export var settle: bool = false
## ROUTE: he blocks for this many seconds after the snap and then goes out on
## his route (a chip and release). Nobody throws to him before that.
@export var block_time: float = 0.0

## A route the quarterback can give a receiver at the line in place of the one
## the play draws for him. On the left stick: straight up the field, a stop that
## turns back to the ball, or a slant to a side. On the right stick: a post
## over the middle, a drag under it, or an out to a side.
enum Hot { STREAK, CURL, SLANT, POST, DRAG, OUT }


## `drawn` with the hot route `kind` in place of its own. `side` (+1 or -1) is
## the way a slant or an out breaks, in the play's own frame.
static func hot_route(drawn: OffenseAssignment, kind: Hot, side: float) -> OffenseAssignment:
	var hot: OffenseAssignment = OffenseAssignment.new()
	hot.label = drawn.label
	hot.job = Job.ROUTE
	hot.start = drawn.start
	# Toward the ball, where the quarterback is. A man lined up behind it goes right.
	var inside: float = -signf(drawn.start.y) if absf(drawn.start.y) > 0.5 else 1.0
	match kind:
		Hot.STREAK:
			hot.route = PackedVector2Array([Vector2(20.0, 0.0)])
		Hot.CURL:
			hot.route = PackedVector2Array([Vector2(8.0, 0.0), Vector2(6.5, inside)])
			hot.settle = true
		Hot.SLANT:
			hot.route = PackedVector2Array([Vector2(2.0, 0.0), Vector2(9.0, 7.0 * side)])
		Hot.POST:
			hot.route = PackedVector2Array([Vector2(10.0, 0.0), Vector2(22.0, 8.0 * inside)])
		Hot.DRAG:
			hot.route = PackedVector2Array([Vector2(2.0, 0.0), Vector2(4.0, 12.0 * inside)])
		Hot.OUT:
			hot.route = PackedVector2Array([Vector2(6.0, 0.0), Vector2(6.5, 8.0 * side)])
	return hot
