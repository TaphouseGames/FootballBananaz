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
