class_name OffensePlay
extends Resource
## An offensive play: one assignment per player (8). Exactly one should be the QB.

## What the play attacks. The CPU play caller uses it to pick and to counter.
enum Category { RUN, SHORT, DEEP }
## The formation the play lines up in, which is also its tab on the play-select
## screen. Every play of a formation has all eight players on the same spots
## before the snap, so the line-up does not give the play away
## (tests/playbook_rules_check.gd fails if one does not).
enum Group { I_FORM, SINGLEBACK, HEAVY, GUN_SPREAD, GUN_TRIPS, GOAL_LINE }

## The tabs' titles, in Group order.
const GROUP_NAMES: PackedStringArray = ["I-FORM", "SINGLEBACK", "HEAVY", "GUN SPREAD", "GUN TRIPS", "GOAL LINE"]

@export var play_name: String = "Play"
@export var description: String = ""
@export var category: Category = Category.SHORT
@export var group: Group = Group.I_FORM
## The CPU play caller only calls it as a last-play heave. The person can pick
## it at any time.
@export var heave_only: bool = false
## A home-run shot. The CPU play caller saves it for when it needs a lot at
## once: long yardage, a half running out, a game to catch up in.
@export var shot_play: bool = false
## Run play: the ball is handed to the RUNNER after `handoff_delay` seconds.
@export var is_run: bool = false
@export var handoff_delay: float = 0.5
## Pass play that starts with a faked handoff to the RUNNER, who then runs his
## route as a receiver. The fake lasts `handoff_delay` seconds: the quarterback
## cannot throw until it is over, and coverage defenders may come up for the run.
@export var play_action: bool = false
## Pass play on which the ball really is given to the RUNNER after
## `handoff_delay` seconds. He holds it for `flick_delay` seconds and pitches it
## back to the quarterback, who then throws. With the quarterback down by then,
## the runner keeps it and the play is a run.
@export var flea_flicker: bool = false
@export var flick_delay: float = 0.55
## How often the CPU play caller calls it, next to another play of its category.
## Below 1 for a trick play, which works because it is not seen often.
@export_range(0.0, 2.0) var cpu_weight: float = 1.0
## Drawn for the last few yards before the end zone. The CPU play caller calls
## it there (Tuning.ai_goal_line_distance) and hardly ever anywhere else.
@export var goal_line: bool = false
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
