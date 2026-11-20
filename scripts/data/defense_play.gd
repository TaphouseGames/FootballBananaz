class_name DefensePlay
extends Resource
## A defensive play: one assignment per player (8).

## The tab of the play-select screen the play is on.
enum Group { MAN, ZONE, BLITZ, GOAL_LINE }

## The tabs' titles, in Group order.
const GROUP_NAMES: PackedStringArray = ["MAN", "ZONE", "BLITZ", "GOAL LINE"]

@export var play_name: String = "Play"
@export var description: String = ""
@export var group: Group = Group.MAN
## How well the play holds up against each kind of offensive play (0..1). Only
## the CPU play caller reads these; they do not change how the play is run.
@export_range(0.0, 1.0) var run_fit: float = 0.5
@export_range(0.0, 1.0) var short_fit: float = 0.5
@export_range(0.0, 1.0) var deep_fit: float = 0.5
## Drawn for a stand at the goal line. The CPU play caller calls it there
## (Tuning.ai_goal_line_distance) and hardly ever anywhere else.
@export var goal_line: bool = false
## For a play drawn with one side different from the other: where the CPU puts
## the side drawn on the right. +1 toward the offense's strong side, -1 away
## from it, 0 either side. See DefenseAligner.cpu_flip.
@export_range(-1, 1) var strength_side: int = 0


func fit(category: OffensePlay.Category) -> float:
	match category:
		OffensePlay.Category.RUN:
			return run_fit
		OffensePlay.Category.DEEP:
			return deep_fit
	return short_fit
@export var assignments: Array[DefenseAssignment] = []


## The quick audible against a play of `kind` from the tab of `called`: the play
## that fits it best and is not the called one. Null: the tab has no other play.
static func quick_pick(plays: Array[DefensePlay], called: DefensePlay, kind: OffensePlay.Category) -> DefensePlay:
	var best: DefensePlay = null
	for play: DefensePlay in plays:
		if play != called and play.group == called.group and (best == null or play.fit(kind) > best.fit(kind)):
			best = play
	return best
