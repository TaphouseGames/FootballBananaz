class_name Team
extends Node3D
## A side: its identity, direction of attack, score, and eight Player children.

const MASCOT_SCENE: PackedScene = preload("res://scenes/mascot.tscn")

@export var team_name: String = "Team"
@export var short_name: String = "TEAM"
@export var team_color: Color = Color.WHITE
## +1 attacks toward +X (right on screen), -1 toward -X.
@export_enum("Left:-1", "Right:1") var attack_dir: int = 1
## Controlled by the person with the gamepad (unless Game.autoplay is on).
@export var is_human: bool = false
## Ratings for each Player child, in order. Missing entries play as average.
@export var roster: Roster
## The league team this side plays as. Set, it takes the place of the name, the
## colour and the roster above.
@export var data: TeamData

## Wears white with a band of the team colour instead of the colour all over.
## The home team does, so two teams of a similar colour are still told apart.
var white_kit: bool = false
## The person who plays this team (kept by HumanController.team), or null: the CPU.
var human: HumanController
var score: int = 0
var opponent: Team
## Who plays for this team: its eight, and its mascot while it is a guest at
## a touchdown party (PlayController._invite_mascot). The eight are always in
## `squad`. The rest of the time the mascot is off the field and hidden.
var players: Array[Player] = []
var squad: Array[Player] = []
var mascot: Mascot
## How the CPU leans when it calls this team's offense: a multiplier for each
## OffensePlay.Category (run, short, deep). See Roster.call_bias().
var call_bias: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])


## `color` as it marks what is a team's on screen (the ring under the player a
## person controls, their stamina bar, their panels): a dark one is lightened,
## or it would not show on the turf or a dark panel.
static func marker_of(color: Color) -> Color:
	return color.lightened(0.4) if color.get_luminance() < 0.3 else color


func marker_color() -> Color:
	return marker_of(team_color)


func setup(tuning: Tuning, p_opponent: Team) -> void:
	if data != null:
		team_name = data.team_name
		short_name = data.short_name
		team_color = data.team_color
		roster = data.roster
	if roster != null:
		call_bias = roster.call_bias()
	opponent = p_opponent
	squad.clear()
	for child: Node in get_children():
		var player: Player = child as Player
		if player != null and player != mascot:
			var slot: int = squad.size()
			var ratings: PlayerRatings = null
			if roster != null and slot < roster.players.size():
				ratings = roster.players[slot]
			player.setup(self, slot, tuning, ratings if ratings != null else PlayerRatings.new())
			squad.append(player)
	if mascot == null:
		mascot = MASCOT_SCENE.instantiate() as Mascot
		add_child(mascot)
		mascot.setup(self, squad.size(), tuning, Mascot.ratings_for(self))
	players.clear()
	players.append_array(squad)
	mascot.visible = false
