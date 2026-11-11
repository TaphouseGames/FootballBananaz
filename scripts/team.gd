class_name Team
extends Node3D
## A side: its identity, direction of attack, score, and seven Player children.

@export var team_name: String = "Team"
@export var short_name: String = "TEAM"
@export var team_color: Color = Color.WHITE
## +1 attacks toward +X (right on screen), -1 toward -X.
@export_enum("Left:-1", "Right:1") var attack_dir: int = 1
## Controlled by the person at the keyboard (unless Game.autoplay is on).
@export var is_human: bool = false
## Ratings for each Player child, in order. Missing entries play as average.
@export var roster: Roster

var score: int = 0
var opponent: Team
var players: Array[Player] = []


func setup(tuning: Tuning, p_opponent: Team) -> void:
	opponent = p_opponent
	players.clear()
	for child: Node in get_children():
		var player: Player = child as Player
		if player != null:
			var slot: int = players.size()
			var ratings: PlayerRatings = null
			if roster != null and slot < roster.players.size():
				ratings = roster.players[slot]
			player.setup(self, slot, tuning, ratings if ratings != null else PlayerRatings.new())
			players.append(player)
