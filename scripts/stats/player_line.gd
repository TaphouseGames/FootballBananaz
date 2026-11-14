class_name PlayerLine
extends RefCounted
## One footballer's numbers for the game. Everybody plays both ways, so one line
## holds his offense and his defense.

var pass_att: int = 0
var pass_comp: int = 0
var pass_yds: int = 0
var pass_td: int = 0
var pass_int: int = 0
var sacked: int = 0
var sacked_yds: int = 0

var rush_att: int = 0
var rush_yds: int = 0
var rush_td: int = 0
var rush_long: int = 0

var targets: int = 0
var rec: int = 0
var rec_yds: int = 0
var rec_td: int = 0
var rec_long: int = 0

var tackles: int = 0
var sacks: int = 0
var interceptions: int = 0
var forced_fumbles: int = 0
var fumble_recoveries: int = 0
## Touchdowns on a return: an interception, a fumble or a kickoff.
var return_td: int = 0
var fumbles_lost: int = 0


func add_rush(yards: int) -> void:
	rush_long = yards if rush_att == 0 else maxi(rush_long, yards)
	rush_att += 1
	rush_yds += yards


func add_catch(yards: int) -> void:
	rec_long = yards if rec == 0 else maxi(rec_long, yards)
	rec += 1
	rec_yds += yards


func has_passing() -> bool:
	return pass_att > 0 or sacked > 0


func has_defense() -> bool:
	return tackles + sacks + interceptions + forced_fumbles + fumble_recoveries + return_td > 0


## Adds what `other` did to this line: a game onto a season.
func add(other: PlayerLine) -> void:
	var rush_first: bool = rush_att == 0
	var catch_first: bool = rec == 0
	var longest_rush: int = other.rush_long if rush_first else (maxi(rush_long, other.rush_long) if other.rush_att > 0 else rush_long)
	var longest_catch: int = other.rec_long if catch_first else (maxi(rec_long, other.rec_long) if other.rec > 0 else rec_long)
	for field: StringName in fields(self):
		set(field, int(get(field)) + int(other.get(field)))
	rush_long = longest_rush
	rec_long = longest_catch


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for field: StringName in fields(self):
		out[String(field)] = get(field)
	return out


static func from_dict(values: Dictionary) -> PlayerLine:
	var line: PlayerLine = PlayerLine.new()
	for field: StringName in fields(line):
		line.set(field, int(values.get(String(field), 0)))
	return line


## The names of the numbers `line` (a PlayerLine or a TeamLine) keeps.
static func fields(line: RefCounted) -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in line.get_property_list():
		var usage: int = property[&"usage"]
		var type: int = property[&"type"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and (type == TYPE_INT or type == TYPE_FLOAT):
			names.append(StringName(property[&"name"]))
	return names
