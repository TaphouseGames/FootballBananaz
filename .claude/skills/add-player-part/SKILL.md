---
name: add-player-part
description: Add a body or a head to the football players, or get the prompts for making one. Use when the user says "base male lean", "base female big <path>", "head male <path>", "add this head", "new body for the players", gives a TripoModels/ path of a player body or head, asks which bodies are still missing, or describes a face and wants the concept-art prompt for a player's head. With no arguments it lists the bodies that are still missing with the prompt for each.
---

# Add a body or a head to the players

Every player is a **body** (one per gender and build, white all over, no skin, no head) with a
**head** on it. Both are listed in `scripts/look/player_parts.gd` (`PlayerParts.BODIES` and
`PlayerParts.HEADS`). Adding a part means adding one entry there. No other code changes: the
game, the team editor (`tools/team_editor.tscn`, "Player models": Gender, Body type, Head) and
`tests/model_gallery.gd` all read that list.

- `scripts/look/kit_base.gd` bakes a body and fits heads to its collar.
- `assets/player/kit_body.gdshader` paints the kit: jersey, pants, socks, boots, gloves, number, name.
- `scripts/data/player_look.gd` is what a player stores: gender, build, head id, height.

## How it is called

| The user says | Do |
|---|---|
| nothing (`/add-player-part`) | [List what is missing, with prompts](#no-arguments-what-is-missing) |
| `base <male\|female> <lean\|athletic\|big>` and no model | Give the image prompt for that body and the Tripo settings |
| `base <male\|female> <lean\|athletic\|big>` and a path (or a new folder in `TripoModels/`) | [Add the body](#adding-a-body) |
| `<male\|female> head` or `head <male\|female>`, with a description of a face and no model | [Write the concept-art prompt for that head](#the-head-prompt) |
| the same with a path (or a new folder in `TripoModels/`) | [Add the head](#adding-a-head) |

"atheletic" and other spellings mean athletic. If the user gives a model without saying which
kind it is, `describe` it (below): a rig means a body, no rig means a head.

## No arguments: what is missing

Read `PlayerParts.BODIES`. The six bodies are `male_lean`, `male_athletic`, `male_big`,
`female_lean`, `female_athletic`, `female_big`. Report in a short table which exist and which
are missing, then give the full body prompt (below) once for each missing one, each in its own
code block with the `{BUILD}` line filled in, and the Tripo settings once. Also say how many
heads each gender has. A gender with no heads or no bodies falls back to the other gender's, so
point that out.

## The body prompt

Four-view image for image-to-3D. Fill in `{BUILD}`:

```
Character turnaround sheet, four orthographic views of the same character side by side in one row: front view, back view, left side view, right side view. Identical proportions, pose and outfit in every view, all at the same scale, feet on the same ground line.

A headless body of a 1920s American football player, stylized chunky cartoon character, simple rounded shapes, slightly oversized hands and boots, thick sturdy limbs with clearly defined elbows and knees. {BUILD}. The figure ends at the top in a tall ribbed turtleneck collar with an open, empty neck hole; there is no head and no neck.

Standing upright in a T-pose: arms straight out to the sides at shoulder height, palms down, fingers together, legs straight and slightly apart, feet pointing forward.

Outfit: vintage 1920s football uniform, entirely plain white. Long-sleeved wool jersey with a high turtleneck collar, padded gloves, high-waisted padded canvas knickers ending below the knee, long socks, ankle-high lace-up leather boots. Every part is the same plain matte white, including gloves, socks and boots. No skin visible anywhere. No numbers, no letters, no logos, no stripes, no patterns, no colored trim.

Matte, non-reflective fabric, no gloss, no shine. Flat, even, shadowless studio lighting, with only soft shading in the folds and seams. Plain flat mid-grey background, no floor shadow, no text, no labels, no props, no helmet.
```

`{BUILD}` lines (for female, the same with `female` and the second set):

- male lean: `Lean male build: slim, narrow waist, long legs, light shoulders`
- male athletic: `Athletic male build: broad shoulders, solid chest, medium waist`
- male big: `Big male build: very wide and heavy, barrel chest, large belly, thick neck opening, massive arms and thighs`
- female lean: `Lean female build: slim, narrow shoulders, long legs`
- female athletic: `Athletic female build: strong shoulders, defined waist, powerful legs`
- female big: `Big female build: very wide and heavy, broad chest and hips, thick neck opening, massive arms and thighs`

Tell the user to use the image of a body they already like as a reference for the next ones,
so all bodies wear the same cut of uniform.

## The head prompt

The user describes the player (who he is, how he plays, what his face is like). Turn that into
the third paragraph below and keep the other four word for word: they are what makes a head
fit the bodies. In the third paragraph give age, skin, hair (colour, cut, where it is), facial
hair, the shape of jaw, nose and brows, and an expression that fits how he plays. Keep the
mouth closed, and make thin things thick and chunky (moustache tips, strands, eyelashes,
earrings): thin detail breaks up at 2-3 thousand triangles.

```
Character turnaround sheet, four orthographic views of the same head side by side in one row: front view, back view, left side view, right side view. Identical proportions and features in every view, all at the same scale, aligned on the same horizontal line.

A head and short neck only, no shoulders, no body, no clothing, no collar. Stylized chunky 3D cartoon character in the manner of a 1920s sports hero, simple rounded shapes, slightly exaggerated features.

{WHO: e.g. "A white man in his early thirties, a dashing and cocky quarterback. Balding: the top of the head is bare and smooth, with short, neat black hair around the sides and back only. A big old-fashioned black handlebar mustache with thick, chunky tips curled upward into twirls. Clean-shaven chin and cheeks. Strong jaw, lively eyes, one eyebrow slightly raised, a confident closed-mouth smirk."}

The head is held perfectly upright and level, looking straight ahead, chin not pushed forward. The neck is a short, straight, vertical cylinder directly under the middle of the head, ending in a flat horizontal cut.

Matte skin and hair, no gloss, no shine. Flat, even, shadowless studio lighting. Plain flat mid-grey background, no text, no labels, no hat, no helmet, no glasses.
```

Drop "no glasses" or "no hat" from the last paragraph only if the user asks for them. For a
woman say "woman" in the third paragraph and change nothing else. Give the prompt in one code
block, then the Tripo settings.

## Tripo settings

| | Body | Head |
|---|---|---|
| Topology | quads | triangles |
| Faces | 6-8 thousand quads | 2-3 thousand triangles |
| Rig | Tripo's auto-rig, T-pose | none |
| Texture | standard (2048), no HD/4K | standard (2048), no HD/4K |
| PBR | on (for the normal map) | on |

Export FBX into a folder of its own under `TripoModels/`.

## Finding the model

The user gives a folder such as `res://TripoModels/<name>/`; the source is the `.fbx` in it.
Without a path, take the newest folder in `TripoModels/` whose `.fbx` no entry of
`player_parts.gd` (and no fan in `tools/crowd_parts.json`) uses, and say which one you took. If
the path is already in `player_parts.gd`, say so and stop.

Godot is not on PATH; its location is in the `godot-executable-location` memory
(`Godot_v4.7.2-stable_win64_console.exe`). With `G` set to it, from the project root:

```bash
"$G" --headless --path . --import      # after any new or changed file, and to catch script errors
"$G" --headless --path . --script res://tests/model_gallery.gd -- describe=res://TripoModels/<folder>/<file>.fbx
```

`describe` prints triangles, size, texture and, for a rigged model, whether it has every bone
a body needs. Put `timeout 120` in front of every Godot call: a script error leaves it hanging.

In the model's `.fbm` folder, set `process/size_limit=1024` in the `.import` file of the colour
texture (`*basecolor*` or `*rgb*`) and of the normal map, then run `--import` again. The game
loads them at 1024; the 2048 sources stay as they are.

## Adding a body

1. `describe` it. It must say "all the bones a body needs". If bones are missing it was not
   rigged by Tripo's auto-rig: stop and tell the user. About 12-16 thousand triangles is
   expected; say so if it is far off, but go on.
2. Add it to `BODIES` under `"<gender>_<build>"` with only its `path`:

   ```gdscript
   "male_big": {
   	"path": "res://TripoModels/<folder>/<file>.fbx",
   },
   ```

   Replacing an existing body: change its `path` and remove its overrides.
3. Import, then render and look at the pictures (a window is needed, so no `--headless`):

   ```bash
   "$G" --path . --script res://tests/model_gallery.gd -- out=<scratchpad>/gallery only=body_<gender>_<build>
   ```

   The sheet shows the body in away and home kits at several heights from four sides. Check:
   - **Jersey / pants** meet at the waistband, not above or below it.
   - **Pants / socks** meet at the hem of the pants: no sock colour on the pants' cuff.
   - **Socks / boots** meet at the top of the boots.
   - **Number** sits in the middle of the chest and of the back, **name** across the shoulders
     below the collar, neither running onto the sleeves.
   - Gloves are brown to the wrist; the collar is the jersey's colour (team colour at home).

   These lines come from the body's joints. Where one is off, add an override to the entry and
   render again. All are in the body's own units: z up, feet at 0, and the body about 0.8
   tall to the top of the collar.

   ```gdscript
   "belt_z": 0.47, "hem_z": 0.19, "boot_z": 0.109,
   "front_number": [0.6, 0.06, 0.045],   # centre z, half width, half height
   "back_number": [0.585, 0.07, 0.052],
   "back_name": [0.672, 0.095, 0.026],
   ```

   Those numbers are what the male athletic body comes to, as a starting point.
4. Look at the heads on it too (`only=heads_<gender>`, which uses the athletic body, or pick
   the body in the team editor): a head that sat well on another body can sit differently on
   a wider or narrower collar.
5. Run the [checks](#checks).

## Adding a head

1. `describe` it: no rig, about 2-3 thousand triangles (more is fine).
2. Add it to `HEADS`. The id is the player's name in lower case with underscores (or what the
   head looks like, if it is not made for one player); ids are what rosters store, so never
   rename one that is in use.

   ```gdscript
   "dash_plantain": {
   	"name": "Dash Plantain", "gender": "male",
   	"path": "res://TripoModels/<folder>/<file>.fbx",
   	"size": 0.272, "neck": 0.205, "sink": 0.035, "forward": 0.027,
   },
   ```

3. Import, render and look (`only=heads_<gender>` shows every head of the gender close up from
   four sides; `only=body_` shows whole players):

   ```bash
   "$G" --path . --script res://tests/model_gallery.gd -- out=<scratchpad>/gallery only=heads_<gender>
   ```

   The neck is narrowed and stood upright automatically so that it goes into the collar. What
   is left to set, one value at a time, rendering in between:

   | What you see | Change |
   |---|---|
   | Head too small or too big for the body, or its neck too wide for the collar | `size` (0.26-0.32) |
   | Too much neck above the collar | raise `neck` (0.15-0.25); it is the height on the model that goes into the collar |
   | Chin or beard sinks into the collar | lower `neck`, or lower `sink` |
   | Neck or its cut bottom shows behind the collar (side view) | raise `forward` by 0.01-0.03 |
   | Neck shows in front of the collar | lower `forward` (it may be negative) |
   | The model faces backwards or sideways | it has to be regenerated or turned in Blender: there is no yaw setting |

   Dash Plantain needed `size` 0.272 (his neck was too wide for the collar at 0.3), `neck`
   0.205 and `forward` 0.027. The side view is the one that shows a bad fit. Body and head
   are sized against each other only (a player's height comes from his look), so "a bigger
   body" and "a smaller head" are the same change: `size`.
4. If the head was made for a player, offer to give it to that player: in the team editor
   (Player models > Head), or by setting `head` on his look in `resources/rosters/<team>.tres`.
   A player without a saved look gets a head picked from his name among those of his gender.
5. Run the [checks](#checks).

## Checks

```bash
timeout 120 "$G" --headless --path . --import 2>&1 | grep -i error
timeout 120 "$G" --headless --path . --script res://tests/team_editor_check.gd 2>&1 | grep -E "FAIL|PASSED|SCRIPT ERROR"
timeout 300 "$G" --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd -- games=1 2>&1 | grep -E "SCRIPT ERROR|PASSED|FAILED" | cut -c1-200
```

One smoke game is only there to catch script errors with the new part on the field: it
reports FAILED over event counters that need about six games ("no 'drags' happened"), which
says nothing about the part.

## Report

Say what was added (id, kind, triangles), which values had to be set by hand and why, what
the checks said, and give the full path of the gallery pictures. If bodies are still missing,
name them in one line.
