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
@export var assignments: Array[OffenseAssignment] = []
