class_name PlayerParts
extends RefCounted
## The models players are put together from: a body for each gender and build
## (white all over, no skin, no head: see KitBase) and the heads that go on
## them. PlayerLook picks from these by gender, build and head.
##
## The skill add-player-part (.claude/skills/add-player-part) adds to BODIES
## and HEADS; tests/model_gallery.gd shows what is here.

const GENDERS: PackedStringArray = ["male", "female"]
const GENDER_NAMES: PackedStringArray = ["Male", "Female"]
const BUILDS: PackedStringArray = ["lean", "athletic", "big"]
const BUILD_NAMES: PackedStringArray = ["Lean", "Athletic", "Big"]

## The bodies, by "<gender>_<build>". `path` is the rigged model. Where the
## kit's parts and its print go is worked out from the body's skeleton (see
## KitBase); any of these overrides one of them, in the body's own units (z
## up, the feet at 0):
##   belt_z, hem_z, boot_z                    the waistband, the hem of the
##                                            pants and the top of the boots
##   front_number, back_number, back_name     [centre z, half width, half height]
const BODIES: Dictionary[String, Dictionary] = {
	"male_athletic": {
		"path": "res://TripoModels/human_figure_3d_model/human_figure_3d_model.fbx",
	},
}

## The heads, by id. `name` is what the team editor calls it, `gender` whose
## bodies it goes on, `path` the model. How it is put on a body:
##   size      how tall the model is, neck and all, in the body's units
##   neck      how far up the model the line is that goes into the collar
##             (0 its bottom, 1 its top): higher shows less neck
##   sink      how far below the top of the collar that line sits
##   forward   moves the head toward the face
const HEADS: Dictionary[String, Dictionary] = {
	"dash_plantain": {
		"name": "Dash Plantain", "gender": "male",
		"path": "res://TripoModels/stylized_male_head_3d_model/stylized_male_head_3d_model.fbx",
		"size": 0.272, "neck": 0.205, "sink": 0.035, "forward": 0.027,
	},
}
const HEAD_FIT: Dictionary = {"size": 0.3, "neck": 0.15, "sink": 0.035, "forward": 0.0}


static func body_id(gender: int, build: int) -> String:
	return "%s_%s" % [GENDERS[clampi(gender, 0, GENDERS.size() - 1)], BUILDS[clampi(build, 0, BUILDS.size() - 1)]]


static func has_body(gender: int, build: int) -> bool:
	return BODIES.has(body_id(gender, build))


## The body a player of `gender` and `build` gets: his own if there is a model
## of it, else the nearest build of his gender, else any body there is.
static func body_for(gender: int, build: int) -> String:
	if has_body(gender, build):
		return body_id(gender, build)
	for other: int in [1, 0, 2]:
		if has_body(gender, other):
			return body_id(gender, other)
	for id: String in BODIES:
		return id
	return ""


## The ids of the heads of `gender`, in the order they are listed.
static func heads_of(gender: int) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for id: String in HEADS:
		if HEADS[id]["gender"] == GENDERS[clampi(gender, 0, GENDERS.size() - 1)]:
			ids.append(id)
	return ids


## The head a player of `gender` wears who asks for `id`: that one if it is a
## head of his gender, else the first of his gender, else any head there is.
static func head_for(gender: int, id: String) -> String:
	var ids: PackedStringArray = heads_of(gender)
	if ids.has(id):
		return id
	if not ids.is_empty():
		return ids[0]
	for any: String in HEADS:
		return any
	return ""


static func head_name(id: String) -> String:
	if not HEADS.has(id):
		return id
	return HEADS[id]["name"]


## One of how a head is put on (see HEADS), or what is usual if it does not say.
static func head_fit(id: String, key: String) -> float:
	var entry: Dictionary = HEADS.get(id, {})
	return entry.get(key, HEAD_FIT[key])
