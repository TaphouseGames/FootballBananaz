class_name TeamData
extends Resource
## One team of the league: what it is called, its colour and its players. A
## Team node takes all of it over in setup. How the CPU calls its offense is
## not set here: it comes from the roster (see Roster.call_bias()).

@export var team_name: String = "Team"
@export var short_name: String = "TEAM"
@export var team_color: Color = Color.WHITE
@export var roster: Roster
