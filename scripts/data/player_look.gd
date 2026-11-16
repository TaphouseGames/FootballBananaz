class_name PlayerLook
extends Resource
## What one footballer looks like: gender and build, which pick the body, the
## head, and how tall he or she is. PlayerModel turns it into a model from the
## bodies and heads in PlayerParts.

enum Gender { MALE, FEMALE }
enum Build { LEAN, ATHLETIC, BIG }

const HEIGHT_MIN: int = 60
const HEIGHT_MAX: int = 84

@export var gender: Gender = Gender.MALE
@export var build: Build = Build.ATHLETIC
## An id in PlayerParts.HEADS. Empty, or a head of the other gender: the
## first head of the player's gender.
@export var head: String = ""
## In inches.
@export_range(60, 84) var height_in: int = 72


## Height the way it is said: 6'2".
func height_text() -> String:
	@warning_ignore("integer_division")
	return "%d'%d\"" % [height_in / 12, height_in % 12]


func height_m() -> float:
	return float(height_in) * 0.0254


## The body and the head this look comes to, as ids in PlayerParts: what it
## asks for, or the nearest there is a model of.
func body_id() -> String:
	return PlayerParts.body_for(gender, build)


func head_id() -> String:
	return PlayerParts.head_for(gender, head)


## The last word of `display_name`, as the back of a jersey says it.
static func last_name(display_name: String) -> String:
	var words: PackedStringArray = display_name.strip_edges().split(" ", false)
	return "" if words.is_empty() else words[words.size() - 1].to_upper()


## A look made up from `seed_value`: the same one every time for the same
## number, so a player nobody has edited yet still looks like somebody. The
## build goes by `position`. Only a gender there are heads of is picked.
static func random(seed_value: int, position: String = "") -> PlayerLook:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var look: PlayerLook = PlayerLook.new()
	var female: bool = rng.randf() < 0.3
	if female and not PlayerParts.heads_of(Gender.FEMALE).is_empty():
		look.gender = Gender.FEMALE
	look.build = Build.ATHLETIC
	if position == "LINE":
		look.build = Build.BIG
	elif position == "WR":
		look.build = Build.LEAN
	look.height_in = rng.randi_range(68, 78)
	var heads: PackedStringArray = PlayerParts.heads_of(look.gender)
	var pick: int = rng.randi()
	if not heads.is_empty():
		look.head = heads[pick % heads.size()]
	return look
