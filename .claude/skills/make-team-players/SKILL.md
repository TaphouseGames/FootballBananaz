---
name: make-team-players
description: Make the players of a team as whole characters of their own - everyday people with their own face, body and shoes, generated with Tripo (smart low poly, about 10k quads, smart UV, PBR, ActorCore rig), cleaned up in Blender and dressed in the team's kit by the game. Takes the team's name. Use when the user says "make the Peachez players", "do the Coconutz like the Bananaz", "generate the rest of the roster", "/make-team-players grapes", or wants one player of a team made or redone this way.
---

# Make a team's players

Every player made this way is one rigged character: face, body, shoes and all. The Bananaz
were the first team (`dash_plantain`, `moe_peel`, ...). The game dresses them through a mask
(`assets/player/kit_person.gdshader`: jersey, pants, socks in the team's colours, number and
name printed on), so a model is made once and works for any kit.

- `tools/players.json` - who each player is (the prompt), and where the rigged model is
- `tools/make_player.sh` - the four Tripo steps
- `tools/prep_player.py` - the Blender clean-up and the kit mask
- `scripts/look/player_parts.gd` (`PEOPLE`) - what the game can load
- `resources/rosters/<team>.tres` - which player is which character (`look.person`)

## The argument

The team: a file name in `resources/teams` without `.tres` (`bananaz`, `peachez`, `applez`,
`berries`, `coconuts`, `grapes`), however the user spells it. With a player's name as well,
only that player. No team named: ask which.

## Before spending anything

1. Read `resources/rosters/<team>.tres`: names, positions, numbers and ratings. A rating
   that is not written is the default (50). A player who already has a `look` with a
   `person` is done: skip him unless asked to redo him.
2. `tripo balance`. A player costs about 105 credits when his first concept is usable
   (concept 5, model 55, UV 20, rig 25), about 110-120 with concept redos. Tell the user what
   the team will cost and what is there. If it is not enough for the whole team, say how
   many players it covers and ask before starting.

## Who they are

Write each player's `who` from his name and ratings: the ratings decide build, age and
attitude, the name gives the joke. Examples from the Bananaz:

| Ratings | Character |
|---|---|
| QB, agile, weak | tall, wiry, cocky |
| lineman, slow, average | heavy, big belly, grumpy |
| WR, catching 90, slow | small old lady with big hands |
| WR, speed 88, strength 30 | skinny teenage boy |
| RB, juke 88 | small nimble woman with a sly smirk |
| lineman, strongest on the team | gentle giant |

Rules the user set:

- **Everyday people, everything from a teenage boy to an old lady.** Not athletes.
- **A mixed team**: African American, Asian, Latino, white and others, men and women, young
  and old. Never a team of white men. Spread it over the positions.
- Every player on a team looks unlike every other: age, build, hair, face, shoes.

Give each: age, ethnicity and skin, build in several words (the picture model follows the
reference picture's body unless told firmly), hair, two or three features of the face, an
expression with the mouth closed, and **shoes in a colour** (never black or dark grey:
dark shoes get read as socks). Nothing else worn: no jewellery, straps or bags.

## The steps

Everything runs from the project root. `tripo` is on PATH; Blender and Godot are not (see
the `godot-executable-location` memory: Blender 5.2 is at
`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`).

### 1. Add the players to `tools/players.json`

Id: the name in lower case with underscores. Per player `name`, `who`, `refs`, `images`.
`images` is one concept picture of a player who is already made, as the kit and style
reference. **Pick one whose body is like the new player's**: the body in the picture pulls
the new one toward it.

- heavy people: Moe Peel's or Big Bunch's concept
- thin people: Dash Plantain's or Zip Cavendish's
- sturdy women: Bo Split's; small old people: Sticky Fingers'

(The newest `generated_image.png` under `assets/player/source/tripo/<id>_concept/`.) `refs`
then reads like the others in the file: same kit and clay style as image[1], "but is a
completely different person: a different face, skin colour, hair, age and body", followed by
what must not be carried over from the picture ("no moustache, no bald head", "no glasses").
Keep the whole prompt under 1,800 characters.

### 2. Concepts (5 credits each), and look at every one

```bash
tools/make_player.sh concept <id> <id>      # two at a time: a third is refused ("concurrency limit", nothing charged)
```

Read each `generated_image.png`. It must show: the right person (ethnicity, age and build as
written, and not a copy of the reference's face), white jersey, mid grey shorts, dark grey
socks, coloured shoes, a T-pose with the whole figure in view. Fixing one:

- **Wrong kit or a detail to remove**: an edit. `tripo generate image-to-image <that picture>
  --prompt "Exactly the same character ... Change only ..."` with `-o <id>_concept`. Edits
  keep the face, so they are good for clothes and builds and useless for a wrong face.
- **Wrong face**: change `who`/`refs`, pick another reference picture, run the concept again.
- **Right face on the wrong body**: give the good picture as image[1] ("his head and face
  are exactly those of image[1]; only the head is taken from it") and a player with the
  right body as image[2].

The model step takes the newest picture in `<id>_concept`, so the last one made must be the
good one.

### 3. Model, UV, rig

```bash
tools/make_player.sh model <id> <id>     # 55 each; several minutes, up to 15
tools/make_player.sh uv <id> <id>        # 20 each
tools/make_player.sh rig <id> <id>       # 25 each
```

Two ids a call, and run the long ones in the background. On "concurrency limit" wait a
minute and run the same step again for those ids. Never run a step twice for a player whose
first run succeeded: it is charged again. The settings are in the script and are what the
user asked for (H3.1 smart low poly, 10k quads, PBR, detailed texture, smart UV, ActorCore
rig): do not change them.

Then put each rig's `model.fbx` (under `assets/player/source/tripo/<id>_rig/tripo-out/...`,
from the project root) into the player's `source` in `players.json`.

### 4. Blender clean-up and kit mask

```bash
"<blender>" -b --factory-startup --python tools/prep_player.py -- only=<id> preview=<scratchpad>/prep
```

Writes `assets/player/people/<id>.glb`, `<id>_mask.png` and the `.blend`. It prints how much
of the texture each garment takes: jersey about 25-33 %, pants 5-12 %, socks 2-3 % (and how much of the jersey is its second
colour, about 10-25 %). A garment
at 0 % or far off means the mask went wrong: look at `<id>_kit_front.png` and
`<id>_kit_back.png` in the preview folder. Per player `options` in `players.json` that help:
`socks_from` (share of the height below which nothing is a sock: for high boots), `chroma`
(0.5: lower if skin is being painted, higher if kit is left out).

A `JOINED` line means the model came as separate torso and legs with a see-through gap at
the waist (Fuji Stem did), which the script closed: look at the waist in the preview pictures.

Small flaws at collars, cuffs and where socks meet shoes are expected and are fixed by
painting the mask by hand in the kit painter (`tools\kit_painter.bat player=<id>`, or
`tools/kit_painter.tscn` with F6): it brushes jersey, pants and socks straight onto the
model, erases kit back to the texture the model came with, paints skin over places the
model itself has wrong, and paints where the jersey has its second colour (Trim: the
sleeves and collar of the home kit, which the script takes from the arm, head and neck
bones). Saving there writes the game's mask and colour texture, so the
script need not be run again, and `assets/player/source/people/<id>_mask_paint.png` and
`<id>_skin_paint.png`, which the script uses when they exist.

For more than that (repainting a face, a shoe), the texture is painted in a texture painter
such as 3DCoat Textura, which does not read `.glb`: the script with `only=<id> obj=<dir>`
writes the model as an `.obj` with its texture. The painted colour texture goes back as
`assets/player/source/people/<id>_colour_paint.png` and is the player's texture from then
on; run the script for the player again afterwards.

### 5. The character sheet

Give every player a `character` in `players.json`, right after `name`, as the Bananaz have:
`team`, `position`, `number`, a one-line `summary` ("sturdy Korean American woman in her late
thirties with a chin-length black bob, rectangular glasses and a firm little smile, sky blue
sneakers"), then `gender`, `age`, `heritage`, `build`, `look`, `personality` and `plays_like`
(what the ratings say, with the numbers). The user uses these later for voice lines and the
like, so write it from the model **as it came out** (look at the gallery picture), not from
what the prompt asked for, and update it whenever a player is redone.

### 6. Into the game

1. `scripts/look/player_parts.gd`: an entry in `PEOPLE` (`name`, `path`, `mask`).
2. `resources/rosters/<team>.tres`: a `PlayerLook` sub-resource per player (`person`,
   `height_in`, and `gender`/`build` as a fallback) and `look = SubResource(...)` on the
   player, as in `bananaz.tres`. Heights follow the character: 62 for a small old lady, 78
   for a giant.
3. Import and render:

   ```bash
   timeout 400 "$G" --headless --path . --import 2>&1 | grep -i error
   timeout 180 "$G" --path . --script res://tests/model_gallery.gd -- out=<scratchpad>/gallery only=people team=<team>
   ```

   Look at `people_<team>.png` (every player, away and home kit, five sides) and
   `people_<team>_close.png` (faces). Check: kit colours where the kit is and nowhere else,
   number and name readable front and back, nobody facing the wrong way.
4. `timeout 400 "$G" --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd -- games=1 2>&1 | grep -E "SCRIPT ERROR|PASSED|FAILED" | cut -c1-200`:
   no SCRIPT ERROR (it reports FAILED over counters one game cannot fill).

## Report

A table of who each player came out as (the `summary` of each character sheet), the credits spent and what is left, the full paths
of the gallery pictures, and which players have mask flaws worth painting. Do not commit
unless asked.
