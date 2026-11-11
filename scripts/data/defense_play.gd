class_name DefensePlay
extends Resource
## A defensive play: one assignment per player (7).

@export var play_name: String = "Play"
@export var description: String = ""
## How well the play holds up against each kind of offensive play (0..1). Only
## the CPU play caller reads these; they do not change how the play is run.
@export_range(0.0, 1.0) var run_fit: float = 0.5
@export_range(0.0, 1.0) var short_fit: float = 0.5
@export_range(0.0, 1.0) var deep_fit: float = 0.5


func fit(category: OffensePlay.Category) -> float:
	match category:
		OffensePlay.Category.RUN:
			return run_fit
		OffensePlay.Category.DEEP:
			return deep_fit
	return short_fit
@export var assignments: Array[DefenseAssignment] = []
