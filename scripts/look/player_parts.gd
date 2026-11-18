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
##   collar_depth                             how far down from its top the collar
##                                            goes, where the neck bones do not
##                                            cover all of it
##   scale                                    how much bigger than his height says
##                                            a player with this body is, head and
##                                            all (1 if not given)
##   head_scale                               how much bigger than usual heads
##                                            are on this body (1 if not given)
const BODIES: Dictionary[String, Dictionary] = {
	"male_athletic": {
		"path": "res://TripoModels/player_body_male_athletic/player_body_male_athletic.fbx",
	},
	"male_big": {
		"path": "res://TripoModels/player_body_male_big/player_body_male_big.fbx",
		"collar_depth": 0.075, "scale": 1.1, "head_scale": 0.98,
	},
}

## The heads, by id. `name` is what the team editor calls it, `gender` whose
## bodies it goes on, `path` the model. How it is put on a body:
##   size      how tall the model is, neck and all, on a body 0.8 tall to the
##             top of its collar (it grows with the body)
##   neck      how far up the model the line is that goes into the collar
##             (0 its bottom, 1 its top): higher shows less neck
##   sink      how far below the top of the collar that line sits
##   forward   moves the head toward the face
##   tilt      degrees the head nods forward (chin down) about that line
##   flare     how far above that line (as a share of the model's height) the
##             neck is back to the width it was modelled with; the neck is
##             narrowed to go into the collar, so raise it for a thick neck
##             that comes out of the collar wider than the collar
const HEADS: Dictionary[String, Dictionary] = {
	"dash_plantain": {
		"name": "Dash Plantain", "gender": "male",
		"path": "res://TripoModels/player_head_dash_plantain/player_head_dash_plantain.fbx",
		"size": 0.272, "neck": 0.205, "sink": 0.035, "forward": 0.027,
	},
	"moe_peel": {
		"name": "Moe Peel", "gender": "male",
		"path": "res://TripoModels/player_head_moe_peel/player_head_moe_peel.fbx",
		"size": 0.24, "neck": 0.235, "sink": 0.035, "forward": 0.008, "tilt": 8.0,
	},
}
## The players who are a whole character of their own, by id: one model with
## its own face, body and shoes, made by tools/make_player.sh and
## tools/prep_player.py from tools/players.json. `path` is the rigged model,
## `mask` the picture that says which of its texels are jersey (r), pants (g)
## and socks (b): kit_person.gdshader gives those the team's colours. A
## PlayerLook that names one (`person`) is that character whatever its gender,
## build and head say. Where the print goes can be overridden as for BODIES
## (front_number, back_number, back_name).
const PEOPLE: Dictionary[String, Dictionary] = {
	"dash_plantain": {
		"name": "Dash Plantain",
		"path": "res://assets/player/people/dash_plantain.glb",
		"mask": "res://assets/player/people/dash_plantain_mask.png",
	},
	"moe_peel": {
		"name": "Moe Peel",
		"path": "res://assets/player/people/moe_peel.glb",
		"mask": "res://assets/player/people/moe_peel_mask.png",
	},
	"sticky_fingers": {
		"name": "Sticky Fingers",
		"path": "res://assets/player/people/sticky_fingers.glb",
		"mask": "res://assets/player/people/sticky_fingers_mask.png",
	},
	"big_bunch": {
		"name": "Big Bunch",
		"path": "res://assets/player/people/big_bunch.glb",
		"mask": "res://assets/player/people/big_bunch_mask.png",
	},
	"lou_ripe": {
		"name": "Lou Ripe",
		"path": "res://assets/player/people/lou_ripe.glb",
		"mask": "res://assets/player/people/lou_ripe_mask.png",
	},
	"zip_cavendish": {
		"name": "Zip Cavendish",
		"path": "res://assets/player/people/zip_cavendish.glb",
		"mask": "res://assets/player/people/zip_cavendish_mask.png",
	},
	"slip_chiquita": {
		"name": "Slip Chiquita",
		"path": "res://assets/player/people/slip_chiquita.glb",
		"mask": "res://assets/player/people/slip_chiquita_mask.png",
	},
	"bo_split": {
		"name": "Bo Split",
		"path": "res://assets/player/people/bo_split.glb",
		"mask": "res://assets/player/people/bo_split_mask.png",
	},
}
const HEAD_FIT: Dictionary = {"size": 0.3, "neck": 0.15, "sink": 0.035, "forward": 0.0, "flare": 0.12, "tilt": 0.0}


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
