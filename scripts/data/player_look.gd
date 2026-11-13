class_name PlayerLook
extends Resource
## What one footballer looks like: which base model he or she is built on, the
## build, and every feature of the head. PlayerModel turns it into a model.
## Sizes run 0..1 with 0.5 as the base model is sculpted.

enum Base { MALE, FEMALE }
enum Glasses { NONE, NERDY, SUNGLASSES, EYEPATCH }
enum Eye { LEFT, RIGHT }

const BASE_NAMES: PackedStringArray = ["Male", "Female"]
## Per base: what `hair_style` picks from. The first is always no hair.
const HAIR_NAMES: Array[Array] = [
	["Bald", "Buzz cut", "Crop", "Flat top", "Mohawk", "Afro", "Mullet"],
	["Bald", "Pixie", "Bob", "Ponytail", "Top bun", "Long", "Pigtails"],
]
const EYE_NAMES: PackedStringArray = ["Round", "Almond", "Sleepy", "Fierce", "Dots", "Wide"]
const GLASSES_NAMES: PackedStringArray = ["None", "Nerdy", "Sunglasses", "Eyepatch"]
const SIDE_NAMES: PackedStringArray = ["Left eye", "Right eye"]
## Male base only. The first is clean shaven.
const FACIAL_HAIR_NAMES: PackedStringArray = ["None", "Stubble", "Moustache", "Goatee", "Full beard", "Handlebar", "Mutton chops"]
const NOSE_NAMES: PackedStringArray = ["Button", "Straight", "Wide", "Hooked", "Upturned", "Pointed"]
const MOUTH_NAMES: PackedStringArray = ["Line", "Smile", "Grin", "Frown", "Lips", "Smirk"]

const HEIGHT_MIN: int = 60
const HEIGHT_MAX: int = 84
const WEIGHT_MIN: int = 130
const WEIGHT_MAX: int = 400

const SKIN_PRESETS: Array[Color] = [
	Color(0.98, 0.84, 0.72), Color(0.93, 0.74, 0.6), Color(0.82, 0.62, 0.46),
	Color(0.66, 0.46, 0.32), Color(0.48, 0.32, 0.22), Color(0.3, 0.2, 0.14),
]
const HAIR_PRESETS: Array[Color] = [
	Color(0.07, 0.06, 0.06), Color(0.25, 0.14, 0.07), Color(0.45, 0.27, 0.12),
	Color(0.85, 0.68, 0.32), Color(0.7, 0.25, 0.1), Color(0.75, 0.75, 0.76),
]

@export var base: Base = Base.MALE

@export_group("Build")
## In inches.
@export_range(60, 84) var height_in: int = 72
## In pounds. How heavy it makes the model look goes by the height as well.
@export_range(130, 400) var weight_lb: int = 215
@export var skin_color: Color = Color(0.82, 0.62, 0.46)

@export_group("Head")
@export_range(0.0, 1.0) var forehead_size: float = 0.5
@export_range(0.0, 1.0) var chin_size: float = 0.5
## A place in HAIR_NAMES of the base.
@export_range(0, 6) var hair_style: int = 1
@export var hair_color: Color = Color(0.25, 0.14, 0.07)
## A place in FACIAL_HAIR_NAMES. Only shown on the male base.
@export_range(0, 6) var facial_hair: int = 0

@export_group("Face")
@export_range(0, 5) var eye_type: int = 0
@export var glasses: Glasses = Glasses.NONE
## Which eye the eyepatch covers: the player's own left or right.
@export var eyepatch_side: Eye = Eye.LEFT
@export_range(0, 5) var nose_type: int = 0
@export_range(0.0, 1.0) var nose_size: float = 0.5
@export_range(0, 5) var mouth_type: int = 0
@export_range(0.0, 1.0) var mouth_size: float = 0.5


## Height the way it is said: 6'2".
func height_text() -> String:
	@warning_ignore("integer_division")
	return "%d'%d\"" % [height_in / 12, height_in % 12]


func height_m() -> float:
	return float(height_in) * 0.0254


## How heavy the build is for the height: -1 a rake, 0 as the base model is
## sculpted, 1 the biggest lineman.
func heaviness() -> float:
	var bmi: float = 703.0 * float(weight_lb) / float(height_in * height_in)
	if bmi < 28.0:
		return remap(maxf(bmi, 17.0), 17.0, 28.0, -1.0, 0.0)
	return remap(minf(bmi, 50.0), 28.0, 50.0, 0.0, 1.0)


## The last word of `display_name`, as the back of a jersey says it.
static func last_name(display_name: String) -> String:
	var words: PackedStringArray = display_name.strip_edges().split(" ", false)
	return "" if words.is_empty() else words[words.size() - 1].to_upper()


## A look made up from `seed_value`: the same one every time for the same
## number, so a player nobody has edited yet still looks like somebody.
static func random(seed_value: int, position: String = "") -> PlayerLook:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var look: PlayerLook = PlayerLook.new()
	look.base = Base.FEMALE if rng.randf() < 0.3 else Base.MALE
	look.height_in = rng.randi_range(68, 78)
	look.weight_lb = rng.randi_range(180, 240)
	if position == "LINE":
		look.weight_lb = rng.randi_range(280, 340)
	look.skin_color = SKIN_PRESETS[rng.randi() % SKIN_PRESETS.size()]
	look.hair_color = HAIR_PRESETS[rng.randi() % HAIR_PRESETS.size()]
	look.hair_style = rng.randi_range(0, 6)
	look.facial_hair = rng.randi_range(0, 6) if rng.randf() < 0.5 else 0
	look.eye_type = rng.randi_range(0, 5)
	look.nose_type = rng.randi_range(0, 5)
	look.mouth_type = rng.randi_range(0, 5)
	look.forehead_size = rng.randf_range(0.3, 0.7)
	look.chin_size = rng.randf_range(0.3, 0.7)
	look.nose_size = rng.randf_range(0.35, 0.65)
	look.mouth_size = rng.randf_range(0.35, 0.65)
	var roll: float = rng.randf()
	if roll < 0.08:
		look.glasses = Glasses.NERDY
	elif roll < 0.14:
		look.glasses = Glasses.SUNGLASSES
	elif roll < 0.17:
		look.glasses = Glasses.EYEPATCH
		look.eyepatch_side = Eye.RIGHT if rng.randf() < 0.5 else Eye.LEFT
	return look
