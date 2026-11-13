class_name OffensePlaybook
extends Resource
## The offensive plays offered on the play-select screen. Add a play .tres here.

@export var plays: Array[OffensePlay] = []
## Takes the first play's place in either half's last seconds (Tuning.hail_mary_time)
## when the ball is more than Tuning.hail_mary_min_distance yards from the goal line.
@export var hail_mary: OffensePlay
