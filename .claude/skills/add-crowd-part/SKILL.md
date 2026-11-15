---
name: add-crowd-part
description: Add a new head, torso or legs model to the stadium crowd (or remove one). Use when the user gives a path under TripoModels/ (or any FBX/GLB of a head, torso or pair of legs) and asks to add it to the crowd, fans, stands or crowd viewer, e.g. "add this head", "one more torso", "new legs for the crowd".
---

# Add a part to the stadium crowd

Every fan in the stands is a head + a torso + legs picked at random from one kit. The kit
(`assets/stadium/crowd_kit.glb`, `crowd_atlas.png`, `crowd_mask.png`) is built by the Blender
script `tools/prep_crowd.py` from the list in `tools/crowd_parts.json`. Adding a part means
adding one entry to that list and rebuilding. No Godot code changes: the stadium and
`tools/crowd_viewer.tscn` pick up whatever the kit holds, and the crowd is split evenly
between the options of each kind.

`docs/stadium.md` has the long explanation; the `_about` string at the top of
`tools/crowd_parts.json` documents every key.

## Steps

### 1. Find the model and check that it is new

The user gives a folder such as `res://TripoModels/<name>/`. The source is the `.fbx` in it.

- Compare it with the `source` of every fan already in `tools/crowd_parts.json`. The user has
  pasted an already-used path before. If it is already there, look for the newest folder in
  `TripoModels/` that no fan uses, and use that one, and say so in the report.
- Two folders whose `tripo_convert_<id>.fbm` subfolder has the same id are the same model.

### 2. Add the entry

Add a fan to `"fans"` in `tools/crowd_parts.json` with the next free id (`m5`, `m6`, ... :
take the highest number + 1; ids are never reused). Templates:

Head:

```json
"m11": {
  "gender": "m",
  "only": "head",
  "who": "(a head by itself, not from the template: <what it looks like>)",
  "source": "TripoModels/<folder>/<file>.fbx",
  "yaw": 0,
  "use": ["head"],
  "neck": 0.15,
  "size": 1.0,
  "budgets": {"near": {"head": 600}, "mid": {"head": 160}, "far": {"head": 160}},
  "keys": {"skin": null, "hair": null}
}
```

Torso (with its arms):

```json
"m11": {
  "gender": "m",
  "only": "torso",
  "outfit": "<short name, e.g. red v-neck with striped sleeves>",
  "who": "(a torso with its arms by itself, not from the template: <what it looks like>)",
  "source": "TripoModels/<folder>/<file>.fbx",
  "yaw": 0,
  "use": ["torso"],
  "size": 1.0,
  "budgets": {"near": {"torso": 700}},
  "joints": {},
  "keys": {"shirt": null, "skin": null}
}
```

Legs (trousers and shoes):

```json
"m11": {
  "gender": "m",
  "only": "legs",
  "who": "(legs by themselves, not from the template: <what they look like>)",
  "source": "TripoModels/<folder>/<file>.fbx",
  "yaw": 0,
  "use": ["legs"],
  "size": 1.0,
  "budgets": {"near": {"legs": 600}},
  "joints": {},
  "keys": {"pants": null, "skin": null}
}
```

The `null` keys are deliberate: the user wants every part to keep the colours of its own
texture, not be repainted in team colours. Do not change that unless asked.

Fill in `who` / `outfit` after the first build, once you have seen what the model looks like.

### 3. Build the kit, with previews

```bash
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
  --python tools/prep_crowd.py -- preview="<scratchpad>/crowd" 2>&1 \
  | grep -E "EXPORTED|Error|Traceback|SystemExit|TRIANGLES"
```

It must print `EXPORTED`. Then look at `kit_m_near_front.png` and `kit_m_near_side.png` in the
preview folder (every head on every torso) and check the new part:

| What is wrong | Fix in the entry |
| --- | --- |
| Faces the wrong way | `yaw` (degrees; the model must face -Y in Blender) |
| Too big or too small | `size` |
| Head sits too high or low on the neck | `neck` (how far up the model its neck line is, 0 to 1) |
| This one head sits too far forward or back | `shift`: `[x, y, z]`, height = 1, front is -y |
| Arms or legs bend in the wrong place | `joints` overrides (names are printed after `JOINTS`) |
| Looks rough close up | a larger `near` budget |

Every head already gets the gender's `head_shift` (in `genders.m`), so a new head lands where
the others are. Only add a per-head `shift` if this one head is off.

### 4. Import and check in Godot

Godot is not on PATH; its location is in the `godot-executable-location` memory
(`Godot_v4.7.2-stable_win64_console.exe`). With `G` set to it:

```bash
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/stadium_check.gd
"$G" --path . --resolution 1280x720 --script res://tests/stadium_gallery.gd -- out="<scratchpad>/stadium" only=crowd
```

- The check must end with `STADIUM CHECK PASSED`, and its `Heads from:` / `Outfits from:` line
  must include the new id. It measures real time, so it can fail spuriously when run straight
  after other Godot processes; rerun it alone before believing a failure.
- Look at `crowd_close.png` from the gallery: the new part should be in the stands, with no
  gaps at the neck or the waist.
- To compare the three detail levels side by side:
  `"$G" --path . --resolution 1400x1000 --script res://tests/crowd_gallery.gd -- out="<dir>"`
  (`m_near_front.png`, `m_mid_front.png`, `m_far_front.png`).

### 5. Update the docs

In `docs/stadium.md`:

- the tuning-table row for `crowd_head`, `crowd_torso`, `crowd_legs` lists the ids of each kind
  and how the crowd is split;
- the known-limits line near the end counts the heads, outfits and legs.

### 6. Report

Say what the part looks like, that it is in the crowd and the viewer, and which checks ran.
Do not commit unless asked.

## Removing a part

Delete its entry from `tools/crowd_parts.json`. If the gender's `far_head`, `far_torso` or
`far_legs` names it, point that at a fan that is left. Then steps 3 to 5.

## Things that bite

- A bash heredoc containing an apostrophe fails in this shell. Edit the JSON with the Edit
  tool, or write a patch script to the scratchpad and run it with `python -I`.
- The source folders under `TripoModels/` also hold `.import` files and Godot's own import of
  the FBX; the game does not use those, only the kit.
- A women's kit does not exist yet (`genders.f` has no fans). A woman's part needs
  `"gender": "f"` and, as long as there are no whole female fans, a `skeleton` under
  `genders.f` like the men's; ask the user before starting on that.
- To give everybody the same part for a test, set `crowd_head`, `crowd_torso` or `crowd_legs`
  in `scripts/data/tuning.gd` to a fan id; leave them empty afterwards.
