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
	"rocket_husk": {
		"name": "Rocket Husk",
		"path": "res://assets/player/people/rocket_husk.glb",
		"mask": "res://assets/player/people/rocket_husk_mask.png",
	},
	"stone_palm": {
		"name": "Stone Palm",
		"path": "res://assets/player/people/stone_palm.glb",
		"mask": "res://assets/player/people/stone_palm_mask.png",
	},
	"rex_shell": {
		"name": "Rex Shell",
		"path": "res://assets/player/people/rex_shell.glb",
		"mask": "res://assets/player/people/rex_shell_mask.png",
	},
	"tank_copra": {
		"name": "Tank Copra",
		"path": "res://assets/player/people/tank_copra.glb",
		"mask": "res://assets/player/people/tank_copra_mask.png",
	},
	"miles_frond": {
		"name": "Miles Frond",
		"path": "res://assets/player/people/miles_frond.glb",
		"mask": "res://assets/player/people/miles_frond_mask.png",
	},
	"hands_kernel": {
		"name": "Hands Kernel",
		"path": "res://assets/player/people/hands_kernel.glb",
		"mask": "res://assets/player/people/hands_kernel_mask.png",
	},
	"bruno_drupe": {
		"name": "Bruno Drupe",
		"path": "res://assets/player/people/bruno_drupe.glb",
		"mask": "res://assets/player/people/bruno_drupe_mask.png",
	},
	"moose_macaroon": {
		"name": "Moose Macaroon",
		"path": "res://assets/player/people/moose_macaroon.glb",
		"mask": "res://assets/player/people/moose_macaroon_mask.png",
	},
	"georgia_pitt": {
		"name": "Georgia Pitt",
		"path": "res://assets/player/people/georgia_pitt.glb",
		"mask": "res://assets/player/people/georgia_pitt_mask.png",
	},
	"fuzz_melba": {
		"name": "Fuzz Melba",
		"path": "res://assets/player/people/fuzz_melba.glb",
		"mask": "res://assets/player/people/fuzz_melba_mask.png",
	},
	"donut_clingstone": {
		"name": "Donut Clingstone",
		"path": "res://assets/player/people/donut_clingstone.glb",
		"mask": "res://assets/player/people/donut_clingstone_mask.png",
	},
	"hal_freestone": {
		"name": "Hal Freestone",
		"path": "res://assets/player/people/hal_freestone.glb",
		"mask": "res://assets/player/people/hal_freestone_mask.png",
	},
	"belle_nectar": {
		"name": "Belle Nectar",
		"path": "res://assets/player/people/belle_nectar.glb",
		"mask": "res://assets/player/people/belle_nectar_mask.png",
	},
	"skip_blossom": {
		"name": "Skip Blossom",
		"path": "res://assets/player/people/skip_blossom.glb",
		"mask": "res://assets/player/people/skip_blossom_mask.png",
	},
	"rusty_cobbler": {
		"name": "Rusty Cobbler",
		"path": "res://assets/player/people/rusty_cobbler.glb",
		"mask": "res://assets/player/people/rusty_cobbler_mask.png",
	},
	"dixie_crumble": {
		"name": "Dixie Crumble",
		"path": "res://assets/player/people/dixie_crumble.glb",
		"mask": "res://assets/player/people/dixie_crumble_mask.png",
	},
	"cannon_cortland": {
		"name": "Cannon Cortland",
		"path": "res://assets/player/people/cannon_cortland.glb",
		"mask": "res://assets/player/people/cannon_cortland_mask.png",
	},
	"granny_smith": {
		"name": "Granny Smith",
		"path": "res://assets/player/people/granny_smith.glb",
		"mask": "res://assets/player/people/granny_smith_mask.png",
	},
	"mac_intosh": {
		"name": "Mac Intosh",
		"path": "res://assets/player/people/mac_intosh.glb",
		"mask": "res://assets/player/people/mac_intosh_mask.png",
	},
	"gala_core": {
		"name": "Gala Core",
		"path": "res://assets/player/people/gala_core.glb",
		"mask": "res://assets/player/people/gala_core_mask.png",
	},
	"jet_pippin": {
		"name": "Jet Pippin",
		"path": "res://assets/player/people/jet_pippin.glb",
		"mask": "res://assets/player/people/jet_pippin_mask.png",
	},
	"fuji_stem": {
		"name": "Fuji Stem",
		"path": "res://assets/player/people/fuji_stem.glb",
		"mask": "res://assets/player/people/fuji_stem_mask.png",
	},
	"honey_crisp": {
		"name": "Honey Crisp",
		"path": "res://assets/player/people/honey_crisp.glb",
		"mask": "res://assets/player/people/honey_crisp_mask.png",
	},
	"bram_russet": {
		"name": "Bram Russet",
		"path": "res://assets/player/people/bram_russet.glb",
		"mask": "res://assets/player/people/bram_russet_mask.png",
	},
	"jet_huckle": {
		"name": "Jet Huckle",
		"path": "res://assets/player/people/jet_huckle.glb",
		"mask": "res://assets/player/people/jet_huckle_mask.png",
	},
	"pip_bramble": {
		"name": "Pip Bramble",
		"path": "res://assets/player/people/pip_bramble.glb",
		"mask": "res://assets/player/people/pip_bramble_mask.png",
	},
	"tad_thorn": {
		"name": "Tad Thorn",
		"path": "res://assets/player/people/tad_thorn.glb",
		"mask": "res://assets/player/people/tad_thorn_mask.png",
	},
	"sol_briar": {
		"name": "Sol Briar",
		"path": "res://assets/player/people/sol_briar.glb",
		"mask": "res://assets/player/people/sol_briar_mask.png",
	},
	"ray_acai": {
		"name": "Ray Acai",
		"path": "res://assets/player/people/ray_acai.glb",
		"mask": "res://assets/player/people/ray_acai_mask.png",
	},
	"cole_currant": {
		"name": "Cole Currant",
		"path": "res://assets/player/people/cole_currant.glb",
		"mask": "res://assets/player/people/cole_currant_mask.png",
	},
	"flash_elder": {
		"name": "Flash Elder",
		"path": "res://assets/player/people/flash_elder.glb",
		"mask": "res://assets/player/people/flash_elder_mask.png",
	},
	"boyd_mulberry": {
		"name": "Boyd Mulberry",
		"path": "res://assets/player/people/boyd_mulberry.glb",
		"mask": "res://assets/player/people/boyd_mulberry_mask.png",
	},
	"clyde_concord": {
		"name": "Clyde Concord",
		"path": "res://assets/player/people/clyde_concord.glb",
		"mask": "res://assets/player/people/clyde_concord_mask.png",
	},
	"mack_vine": {
		"name": "Mack Vine",
		"path": "res://assets/player/people/mack_vine.glb",
		"mask": "res://assets/player/people/mack_vine_mask.png",
	},
	"otis_raisin": {
		"name": "Otis Raisin",
		"path": "res://assets/player/people/otis_raisin.glb",
		"mask": "res://assets/player/people/otis_raisin_mask.png",
	},
	"brick_tannin": {
		"name": "Brick Tannin",
		"path": "res://assets/player/people/brick_tannin.glb",
		"mask": "res://assets/player/people/brick_tannin_mask.png",
	},
	"gus_trellis": {
		"name": "Gus Trellis",
		"path": "res://assets/player/people/gus_trellis.glb",
		"mask": "res://assets/player/people/gus_trellis_mask.png",
	},
	"hank_cluster": {
		"name": "Hank Cluster",
		"path": "res://assets/player/people/hank_cluster.glb",
		"mask": "res://assets/player/people/hank_cluster_mask.png",
	},
	"crush_merlot": {
		"name": "Crush Merlot",
		"path": "res://assets/player/people/crush_merlot.glb",
		"mask": "res://assets/player/people/crush_merlot_mask.png",
	},
	"bull_malbec": {
		"name": "Bull Malbec",
		"path": "res://assets/player/people/bull_malbec.glb",
		"mask": "res://assets/player/people/bull_malbec_mask.png",
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
