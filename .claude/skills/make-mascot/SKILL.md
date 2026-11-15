---
name: make-mascot
description: Make a new fruit mascot in the same style as the existing six (banana, peach, apple, blueberry, coconut, grapes) - generated with Tripo, then cleaned up, rigged and animated with the same Blender script, so it has the same skeleton and clips. Use when the user names a fruit or a team and asks for a mascot, e.g. "make a strawberry mascot", "the Lemonz need a mascot", "another mascot like the others", or asks to redo one.
---

# Make a mascot

Every mascot is the same kind of figure made the same way: a fruit body with the face on
it, thin black arms and legs, white gloves, big sneakers, arms raised. One Tripo generation
(about 110 credits), then `tools/prep_mascot.py` cleans it up, gives it the shared skeleton
and writes the shared clips. Nothing in the game's code changes for a new one.

- The list of mascots and their prompts: `tools/mascots.json` (its `_about` string documents the keys).
- The long explanation: the Mascots section of `docs/stadium.md`.
- Blender: `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` (not on PATH). Godot: see the memory note on the Godot executable. `tripo` is on PATH.

Run everything from the project root.

## Steps

### 1. Pick the key

The key is the short name, in lower case, of the team the mascot is for: the game loads
`assets/stadium/mascot_<key>.glb` for the team whose `short_name` is `<KEY>`
(`resources/teams/*.tres`).

- The user names a team: use its short name (`Lemonz` -> `lemonz`).
- The user names only a fruit: use the league's spelling, the plural with a z (`strawberry` -> `strawberriez`, `lemon` -> `lemonz`). Say in the report that the mascot shows up in the game once a team with that short name exists; do not create the team unless asked.
- The key is already in `mascots.json`: the user wants that one redone. Keep the entry, change the prompt only if they asked for a different look, and go on from step 3. The old raw model stays on disk.

### 2. Add the entry

Add to `tools/mascots.json`, after the last mascot:

```json
"<key>": {
  "fruit": "<fruit>",
  "prompt": "<see below>",
  "source": "",
  "joints": {}
}
```

The prompt is this sentence with only the two slots filled. Do not reword the rest: the
fixed parts are what makes the family match.

```
a goofy sports team mascot, a person in a big <SHAPE AND COLOUR> <FRUIT> costume with a grinning face and big white cartoon eyes, <ACCESSORIES>, thin black arms and legs, white gloves and big white sneakers, standing upright with arms raised cheering, chunky stylized cartoon character, single isolated figure
```

- `<SHAPE AND COLOUR>`: two or three plain words for the fruit's body (`round fuzzy matte orange-pink`, `round shiny green`, `round brown hairy`). For a fruit that is not one lump, describe it as the grapes are: `a big costume of a bunch of round purple grapes`.
- `<ACCESSORIES>`: what grows on the fruit (`a short brown stem with one green leaf on top`, `the little star-shaped crown of a blueberry on top`) plus at most one piece of kit in the team's colour (`and a red sweatband`). If the fruit's own colour is far from the team's colour (`team_color` in the team's `.tres`), the sneakers may take the team's colour instead of white, as the coconut's red ones do.
- Read two or three of the existing prompts first and stay that close to them.

### 3. Generate the model

```
bash tools/make_mascot.sh <key>
```

It takes two to three minutes and prints the credits and the `model_file`. Several keys can
go in one call; they run side by side.

- Put the model's path into the entry's `source`, relative to `assets/stadium/source/tripo/` and with forward slashes: `mascot_<key>/tripo-out/mascot-<key>-<id>/model.glb`.
- "Insufficient credits" (exit code 4): stop. Do not retry. Tell the user to top up (`tripo topup`) and wait for them.
- Look at `preview.png` next to the model. It should have: the face on the fruit, big white eyes, black limbs, white gloves, sneakers, both arms up and clear of the body, and be recognisable as the fruit. If it clearly is not that, show it to the user and ask before spending another 110 credits on a re-run. Small differences (a fist where another has an open hand) are fine.

### 4. Clean up, rig and animate

```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/prep_mascot.py -- <key> preview=<a folder in the scratchpad>
```

Read what it prints:

| Line | Meaning |
| --- | --- |
| `PIECES n: body .., gloves .., shoes ..` | The normal case: joints found from the model's separate pieces. |
| `NOTE: no separate limb pieces between the body and Hand.L` | That limb is fused to its glove or shoe and moves as one piece. Fine (the apple's arms are like this). |
| `ONE PIECE: joints and weights from the shape` | The model is one fused surface. Rougher: check the previews with extra care. |
| `WARNING: ...` | A limb was not found. The previews will show it. |
| `EXPORTED ...` | Done: `assets/stadium/mascot_<key>.glb`. |

Then look at the previews, at least these three:

- `<key>_bones_front.png`: red sticks through the grey model. Each arm stick runs from the body to the wrist and stops there, not through the glove; each leg stick from the body to the ankle.
- `<key>_sulk00_front.png`: both arms hang down, gloves whole, nothing torn or left behind up by the head.
- `<key>_cheer07_angle.png`: arms out to the sides, knees bent, shoes whole.

If a joint is in the wrong place, set it by hand in the entry's `joints` and run the script
again. The names and the values it found are on the `JOINTS` line (`"elbow.L": [x, y, z]`,
height = 1, front = -Y, `.L` = the mascot's own left = +X). Fix only the joints that are
wrong. If the model cannot be rescued that way (limbs missing, two figures, no feet), it is
a generation problem: back to step 3, after asking the user.

Never edit `prep_mascot.py` to make one mascot work. It is shared: a change there means
running it again for every key in `mascots.json` and checking all of them.

### 5. Lineup and the game

```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/mascot_lineup.py -- docs/images/mascot_lineup.png
```

The new one should stand as tall as the other round ones (about 2 yards; only the banana is
taller) and look like one of the family. Then the flat picture that is painted on the turf
at midfield (`assets/field/mascot_<key>.png`; look at it: the mascot should fill the square
and look toward the right):

```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/mascot_decal.py -- <key>
```

Then:

```
godot --headless --path . --import
godot --headless --path . --script res://tests/stadium_check.gd
```

Grep the import for `ERROR` (ignore the `Tripo Bridge` line) and the check for `PASSED`.
If a team with this short name exists, also take pictures in the game and look at one:

```
godot --path . --resolution 1280x720 --script res://tests/stadium_gallery.gd -- out=<folder> only=mascot home=<key> away=bananaz
```

### 6. Report

Show the user the lineup picture and one preview or game shot, and say:

- the key and file made, and whether a team with that short name exists yet;
- the credits spent (and the balance, `tripo balance`);
- anything that differs from the others: a fused limb, joints set by hand, a colour or accessory Tripo changed.

Do not commit unless asked.
