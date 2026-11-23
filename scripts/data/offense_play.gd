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

## Motion before the snap: one receiver (MotionRules.pick says which) may be
## sent on his way with (LB) or (RB). See PreSnapMotion.
## ZIP: a short way in toward the formation, on his own side.
## ACROSS: behind the line to the other side of the formation.
## JET: across at full speed in front of a shotgun quarterback, to be snapped
##   while he runs. Left unsnapped he sets on the other side.
## ORBIT: into the backfield, beside the quarterback.
## RETURN: a few yards in and back to where he was. The line-up stays as it is;
##   what the defense does about it is the point.
enum Motion { NONE, ZIP, ACROSS, JET, ORBIT, RETURN }

@export var motion: Motion = Motion.NONE
## Where he ends up, as drawn (x downfield, y lateral). RETURN: where he turns
## round.
@export var motion_to: Vector2 = Vector2.ZERO
## His job after the motion, with `start` his new spot. JET: his job when the
## ball is snapped while he runs, with `start` the point in front of the
## quarterback his path goes through. Null (RETURN): the job the play draws.
@export var motion_assignment: OffenseAssignment
## JET: his job when the ball is snapped after he has gone past the
## quarterback or has set, with `start` the spot he sets on. Null: he blocks
## from there. A pass play needs one, so he stays a man who can be thrown to.
@export var motion_set_assignment: OffenseAssignment
## Run play: snapped while he runs, the ball goes to the motion man (a jet
## sweep) and the drawn runner leads the way for him.
@export var motion_handoff: bool = false


## The quick audible to a play of `kind` from the formation of `called`: the
## first one in playbook order that is not the called play. Null: there is none.
static func quick_pick(plays: Array[OffensePlay], called: OffensePlay, kind: Category) -> OffensePlay:
	for play: OffensePlay in plays:
		if play != called and play.group == called.group and play.category == kind and not play.heave_only:
			return play
	return null


## How many yards past the line the deepest route of the play is drawn.
func deepest_route() -> float:
	var deepest: float = 0.0
	for assignment: OffenseAssignment in assignments:
		if assignment.job == OffenseAssignment.Job.QB or assignment.job == OffenseAssignment.Job.BLOCK:
			continue
		for waypoint: Vector2 in assignment.route:
			deepest = maxf(deepest, assignment.start.x + waypoint.x)
	return deepest
