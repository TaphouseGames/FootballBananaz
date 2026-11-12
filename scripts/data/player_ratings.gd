class_name PlayerRatings
extends Resource
## One footballer's ratings, 0..100. 50 is an average player. What each rating
## is worth in yards, seconds and chances is set in Tuning ("Ratings" group).
## A position simply ignores the ratings it has no use for.

@export var display_name: String = ""
@export_enum("QB", "LINE", "WR", "RB") var position: String = "LINE"
## Jersey number. 0 = none.
@export_range(0, 99) var number: int = 0

@export_group("Everyone")
## Run speed, with and without turbo.
@export_range(0, 100) var speed: int = 50
## How long the turbo meter lasts.
@export_range(0, 100) var endurance: int = 50
## How hard he is to bring down once a defender has hold of him, how well his
## stiff arm holds a tackler off, and how fast he fights through a block.
@export_range(0, 100) var strength: int = 50

@export_group("Contact")
## How long he holds a block before the man he is blocking gets past him.
@export_range(0, 100) var blocking: int = 50
## How surely he brings the ball carrier down.
@export_range(0, 100) var tackling: int = 50

@export_group("Coverage")
## How well he stays with a receiver through his cuts.
@export_range(0, 100) var coverage: int = 50
## How well he shakes his defender and finds open space as a receiver.
@export_range(0, 100) var get_open: int = 50

@export_group("Ball Skills")
## Chance to hold on to a pass (and to pick one off on defense).
@export_range(0, 100) var catching: int = 50
## How well a spin or a jump beats a tackle (the stiff arm goes by strength).
@export_range(0, 100) var juke: int = 50
## How well he holds on to the ball when he is tackled.
@export_range(0, 100) var security: int = 50

@export_group("Quarterback")
## How far he can throw.
@export_range(0, 100) var power: int = 50
## How close to the target his passes land.
@export_range(0, 100) var accuracy: int = 50
## How well he throws without his feet set.
@export_range(0, 100) var agility: int = 50


## The ratings that make a player at each position, best described first.
const KEY_RATINGS: Dictionary[String, Array] = {
	"QB": [&"accuracy", &"power", &"agility", &"speed"],
	"WR": [&"get_open", &"catching", &"speed", &"juke"],
	"RB": [&"speed", &"juke", &"strength", &"security"],
	"LINE": [&"blocking", &"tackling", &"strength"],
}
## Every rating a player card shows, in order, with the name it goes by there.
## The last three only mean something for a quarterback.
const CARD_ORDER: Array[StringName] = [
	&"speed", &"endurance", &"strength", &"blocking", &"tackling", &"coverage",
	&"get_open", &"catching", &"juke", &"security", &"power", &"accuracy", &"agility",
]
const CARD_LABELS: Dictionary[StringName, String] = {
	&"speed": "SPEED", &"endurance": "ENDURANCE", &"strength": "STRENGTH",
	&"blocking": "BLOCKING", &"tackling": "TACKLING", &"coverage": "COVERAGE",
	&"get_open": "GET OPEN", &"catching": "CATCHING", &"juke": "JUKE",
	&"security": "BALL SECURITY", &"power": "THROW POWER", &"accuracy": "THROW ACCURACY",
	&"agility": "THROW ON THE RUN",
}
const QB_ONLY: Array[StringName] = [&"power", &"accuracy", &"agility"]


## One number for how good he is at his position: the mean of its key ratings.
func overall() -> int:
	var keys: Array = KEY_RATINGS.get(position, KEY_RATINGS["LINE"])
	var sum: int = 0
	for key: StringName in keys:
		var value: int = get(key)
		sum += value
	return roundi(float(sum) / float(keys.size()))


## [label, value, is a key rating] for each rating on his card: the ones his
## position lives on first, then the rest.
func card_ratings() -> Array[Array]:
	var keys: Array = KEY_RATINGS.get(position, KEY_RATINGS["LINE"])
	var rows: Array[Array] = []
	for key: StringName in keys:
		rows.append([CARD_LABELS[key], get(key), true])
	for key: StringName in CARD_ORDER:
		if keys.has(key) or (position != "QB" and QB_ONLY.has(key)):
			continue
		rows.append([CARD_LABELS[key], get(key), false])
	return rows


## What a rating is worth: `low` for a player rated 0, `high` for one rated 100.
static func blend(rating: int, low: float, high: float) -> float:
	return lerpf(low, high, clampf(float(rating) / 100.0, 0.0, 1.0))
