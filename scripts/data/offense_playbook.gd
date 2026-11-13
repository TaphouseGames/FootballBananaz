class_name OffensePlaybook
extends Resource
## The offensive plays offered on the play-select screen. Add a play .tres here.

@export var plays: Array[OffensePlay] = []
## Takes the first play's place in the game's last seconds (Tuning.hail_mary_time).
@export var hail_mary: OffensePlay
