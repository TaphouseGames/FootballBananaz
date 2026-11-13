class_name League
extends Resource
## Every team there is to pick on the team select, in the order it shows them.

@export var teams: Array[TeamData] = []


## The place in `teams` of the one whose short name is `short_name` (any case),
## or -1.
func find(short_name: String) -> int:
	for i: int in teams.size():
		if teams[i].short_name.to_lower() == short_name.to_lower():
			return i
	return -1
