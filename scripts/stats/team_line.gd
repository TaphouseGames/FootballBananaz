class_name TeamLine
extends RefCounted
## One team's numbers for the game.

var first_downs_pass: int = 0
var first_downs_rush: int = 0
var third_att: int = 0
var third_made: int = 0
var fourth_att: int = 0
var fourth_made: int = 0
## Passes, runs and sacks. Kickoffs and tries are not plays.
var plays: int = 0
var drives: int = 0

var pass_att: int = 0
var pass_comp: int = 0
## Before the yards lost to sacks come off.
var pass_yds: int = 0
var pass_td: int = 0
var pass_int: int = 0
var sacked: int = 0
var sacked_yds: int = 0

var rush_att: int = 0
var rush_yds: int = 0
var rush_td: int = 0

var fumbles_lost: int = 0
## Every time one of its carriers put the ball on the ground, whoever got it back.
var fumbles: int = 0
## Men knocked over after the whistle.
var late_hits: int = 0
## Dives of every kind: with the ball, at a carrier, at nobody.
var dives: int = 0
## The most points it has trailed by.
var max_deficit: int = 0
var red_zone_att: int = 0
var red_zone_made: int = 0
var tries_att: int = 0
var tries_made: int = 0
## Tries the other team had that this one ran back for two.
var tries_returned: int = 0
var kick_returns: int = 0
var kick_return_yds: int = 0
## Touchdowns of every kind, and the ones scored on a return.
var touchdowns: int = 0
var return_td: int = 0
var safeties: int = 0
## Seconds of game clock with the ball.
var possession: float = 0.0

## Only kept over a season (see Season): games played, and the points scored
## and given up in them.
var games: int = 0
var points_for: int = 0
var points_against: int = 0

## The drive being played has already been counted as a trip to the red zone.
var in_red_zone: bool = false


func first_downs() -> int:
	return first_downs_pass + first_downs_rush


## Passing yards with the sack yardage taken off.
func net_pass_yds() -> int:
	return pass_yds - sacked_yds


func total_yds() -> int:
	return net_pass_yds() + rush_yds


func turnovers() -> int:
	return pass_int + fumbles_lost


## Adds what `other` did to this line: a game onto a season.
func add(other: TeamLine) -> void:
	var deficit: int = maxi(max_deficit, other.max_deficit)
	for field: StringName in PlayerLine.fields(self):
		set(field, get(field) + other.get(field))
	max_deficit = deficit


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for field: StringName in PlayerLine.fields(self):
		out[String(field)] = get(field)
	return out


static func from_dict(values: Dictionary) -> TeamLine:
	var line: TeamLine = TeamLine.new()
	for field: StringName in PlayerLine.fields(line):
		var value: Variant = values.get(String(field), 0)
		if line.get(field) is float:
			line.set(field, float(value))
		else:
			line.set(field, int(value))
	return line
