class_name OffensePlay
extends Resource
## An offensive play: one assignment per player (7). Exactly one should be the QB.

## What the play attacks. The CPU play caller uses it to pick and to counter.
enum Category { RUN, SHORT, DEEP }

@export var play_name: String = "Play"
@export var description: String = ""
@export var category: Category = Category.SHORT
## Run play: the ball is handed to the RUNNER after `handoff_delay` seconds.
@export var is_run: bool = false
@export var handoff_delay: float = 0.5
## Pass play that starts with a faked handoff to the RUNNER, who then runs his
## route as a receiver. The fake lasts `handoff_delay` seconds: the quarterback
## cannot throw until it is over, and coverage defenders may come up for the run.
@export var play_action: bool = false
@export var assignments: Array[OffenseAssignment] = []


## How many yards past the line the deepest route of the play is drawn.
func deepest_route() -> float:
	var deepest: float = 0.0
	for assignment: OffenseAssignment in assignments:
		if assignment.job == OffenseAssignment.Job.QB or assignment.job == OffenseAssignment.Job.BLOCK:
			continue
		for waypoint: Vector2 in assignment.route:
			deepest = maxf(deepest, assignment.start.x + waypoint.x)
	return deepest
