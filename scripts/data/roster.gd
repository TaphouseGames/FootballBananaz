class_name Roster
extends Resource
## A team's players, in the order of the Player nodes under the Team. Every play
## lists its assignments in the same order: QB, three linemen, two receivers,
## then the back.

@export var players: Array[PlayerRatings] = []
