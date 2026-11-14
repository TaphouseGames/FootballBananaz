# The stadium

The bowl round the field: wall, tiered stands with aisles and tunnel mouths, about 3,600 fans the size of the players, ad boards, two jumbotrons, four light towers, a hot dog stand and the two teams' mascots. It is scenery only. Nothing in it collides and no gameplay code reads it, with one exception: the mascots also play the scramble that opens a half (see Mascots, On the field).

## How it is put together

- `scripts/stadium.gd` (`Stadium`) builds everything in code when `Field.setup()` runs, from the field's size in `Tuning`. It is the `Stadium` node in `scenes/field.tscn`, so the match and the main menu both get it.
- The outline is a rectangle with rounded corners: eight "runs" (four straights, four quarter circles). Every row is that outline pushed 0.9 further out and 0.45 higher. The sizes are the constants at the top of the script (`WALL_GAP_SIDE`, `ROW_DEPTH`, `SEAT_PITCH`, ...).
- The fans are as big as the players, so there are far fewer of them than seats in a real stadium: 13 rows, about 3,600 fans. Each is put together from a **head**, a **torso** (the outfit: jersey, hoodie, tank top) and **legs** out of a kit of parts, `assets/stadium/crowd_kit.glb`. `tools/prep_crowd.py` cuts the kit from whole Tripo characters, fits the parts to each other, and bakes them sitting, because a `MultiMesh` cannot have a skeleton. `Stadium._seat()` gives every seat a gender, a head, an outfit and legs at random; the three parts are `MultiMesh` instances with the same transform, so they move as one. The crowd is cut into 34 pieces (one per bay of a straight, three per corner). Each piece holds its fans three times, at three levels of detail, and shows the one that fits its distance from the camera: parts in full detail (about 1,000 triangles a fan) up to `crowd_lod_near` yards, plainer parts (about 360) up to `crowd_lod_far`, and one whole plain fan per gender (about 140) beyond. The levels blend over `LOD_BLEND` yards.
- All of them share `assets/stadium/crowd.gdshader`. It does the bobbing, cheering, sulking and the wave from a per-fan phase and speed, so the CPU only sets a few uniforms per frame and no two fans move in step. The arms swing up about the shoulders by how much each vertex belongs to an arm, which `prep_crowd.py` writes into the second UV set, along with which part a vertex is on. Colour comes from two pictures the script makes: `crowd_atlas.png` (every source fan's texture, with cloth, hair and skin reduced to their shading) and `crowd_mask.png` (red: paint with the part's colour, green: paint with the skin tone). The shirt colour, skin tone, hair colour and trouser colour are per fan (`Stadium._fan()`); a shoe, an eye or the number on a jersey is not painted and keeps the texture's colour.
- The signs are separate flat boards (`assets/stadium/crowd_sign.gdshader`), one per fan with the arms up, 2.5 yards wide. Both shaders include `assets/stadium/crowd_motion.gdshaderinc`, so a board moves with the hands that hold it.
- Reactions come from the audio: `AudioDirector.crowd_react()` calls `Stadium.react(for_home, size)`. Anything that already makes the crowd cheer or groan moves the stands too. `Game._ready()` calls `stadium.watch(self)` so the stadium can read the score (jumbotrons), `audio.excitement` (livelier bobbing) and the state (a wave only starts between plays).

## Changing things

| What | Where |
| --- | --- |
| Team colours | Nothing to set. Fans, seats and props take `team_color` from the two teams, so they follow the team select. |
| Crowd density | `crowd_density` in the Stadium group of `resources/tuning.tres` (0..1 of about 3,900 seats). |
| A different crowd | `crowd_seed`: who sits where and what they look like. The same number gives the same crowd. |
| Rows | `stadium_rows`. Past about 18 the stand reaches the game camera. |
| Size of the fans and room each one gets | `FAN_SCALE` (the players' scale in `player.tscn`), `SEAT_PITCH`, `ROW_DEPTH`, `ROW_RISE` in `scripts/stadium.gd`. |
| Who sits where | `crowd_home_share` (the -Z stand and the home end), `crowd_away_share` (the +Z stand and the other end), `crowd_neutral_share` (fans in no team's colour). Corners are half and half. `crowd_female_share` once the kit has women. |
| How dark the crowd is | `crowd_dim`, `crowd_saturation`; `self_lit` in the shader lifts the stand that faces away from the sun. |
| How round and how bright the fans look | In the shader: `wrap` (how far the sun reaches round a body), `rim` (glow along the outline), `brightness` (the unpainted parts), `light_skin` and `dark_skin` (the two ends of the skin tones). |
| Where the detail drops | `crowd_lod_near`, `crowd_lod_far` (yards from the camera to a piece of the stands). |
| Waves | `wave_min_gap`, `wave_max_gap`, `wave_lap_time`. |
| Everything off | `stadium_enabled`. |
| Ad board texts | `BOARD_TEXTS` in `scripts/stadium.gd`. |
| Signs in the crowd | `SIGN_TEXTS` in `scripts/stadium.gd` (16 of them, one per cell of `SIGN_GRID`); paper and ink colours in `SIGN_PAPER` and `SIGN_INK`. The lettering is sized to fit. How big a board is: `SIGN_WIDTH`. |
| Mix of fans | In `scripts/stadium.gd`: `SIGN_SHARE` (fans holding a sign), `HAIR_COLORS`, `PANTS_COLORS`, `TEAM_PANTS_SHARE`, and the ranges for height and width in `_fan()`. |

## Where the objects are

All under `Field/Stadium/Props` at run time (the nodes are made in `Stadium._build_props()`, which is where to move them):

- `Jumbotrons/Jumbotron0` and `Jumbotron4`: behind the back wall at each end. The score is a `Label3D` on a quad in front of the model's screen (`SCREEN_RECT`). Hidden on the main menu, where the title stands in front of one.
- `LightTowers/LightTower1, 3, 5, 7`: outside the four corners.
- `HotDogStand`: on the walkway at the top of the home stand (-Z), about 30 % of the way along.
- `Mascot`: the home team's mascot, inside the wall on the home sideline, 14 yards from midfield. `MascotAway`: the visitors', at the same place on the far sideline.
- `BoothAnchor`: an empty marker at the top of the home stand at midfield. There is no booth model yet; this is where one would go.

## Assets and how to rebuild them

Blender is at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`. From the project root:

```
blender -b --factory-startup --python tools/prep_crowd.py -- [preview=<dir>] [rig=<file.blend>]
blender -b --factory-startup --python tools/prep_prop.py -- assets/stadium/source/tripo/<prop>/tripo-out/<task>/model.glb assets/stadium/<prop>.glb tris=5000 yaw=-90
```

- `crowd_kit.glb`, `crowd_atlas.png` and `crowd_mask.png` are the crowd's parts; see "The crowd's parts" below. The kit's import has `generate_lods` off, since the levels are made by the script. (`fan.glb` and `tools/prep_fan.py` are the old single-model crowd and are no longer used.)
- The signs are not files. `Stadium._bake_signs()` writes the 16 texts into one picture at the start of a match (a viewport that is thrown away afterwards) and the crowd shader shows one cell on the front of each board. The picture is ready by the second frame of a match. Headless runs skip the bake.
- `jumbotron.glb` and `hot_dog_stand.glb` are Tripo models (prompts in each `task.json`), and `light_tower.glb` is made from `TripoModels/floodlight_tower_3d_model_1/floodlight_tower_3d_model_1.fbx` (`tris=9000`, which leaves it whole, and no `yaw`; the script reads FBX too). The others are cut to 5,000 triangles or fewer and 1024 px textures. `yaw=-90` because Tripo's models came out facing +X. `Stadium._prop()` scales each to the height it wants, and shows a plain box if a file is missing.
- `assets/stadium/source/` has a `.gdignore`, so Godot does not import the raw models.

## The crowd's parts

The kit is cut from whole characters, not modelled part by part: Tripo is good at a whole figure and poor at a loose torso, and parts cut from figures of the same build fit each other. `tools/crowd_parts.json` lists the source fans (prompt, model, which of its parts are used); `tools/prep_crowd.py` rebuilds the whole kit from it in about a minute.

What the script does with each fan: finds its joints from its shape, bends it onto one skeleton per gender (the average of that gender's fans, arms straight out), cuts it at the neck and the waist, brings the cut edges to one size for the gender, closes them, thins each part to its budget (`budgets` in the JSON) and seats it. A collar or a hood stays with the outfit, not the head. The skeleton is only used here: in the game the shader moves the fans. `rig=<file.blend>` also saves the full-detail parts standing in the T-pose with that skeleton and their weights, for anything that needs real bones.

To add a head or an outfit:

1. Add a fan to `tools/crowd_parts.json`: copy one, change `who` (the template's `{who}`), and list in `use` which of its parts go into the kit. Ask for plain light grey for whatever should take the team's colour, hair clearly darker or lighter than the skin, bare hands, and trousers or shorts (not a skirt).
2. Make a concept picture in the mascots' style, then the model (5 + about 110 credits):
   ```
   tripo generate image-to-image ./assets/stadium/source/tripo/mascot/tripo-out/mascot-07cf547b/generated_image.jpeg --prompt "A new character: a human sports fan, <who>. Full body, front view, standing upright in a T-pose with arms straight out to the sides and legs slightly apart, smooth skin. Chunky stylized cartoon character with simple shapes, a big head and big sneakers, in exactly the smooth vinyl toy 3D art style and lighting of image[1]. Single isolated figure on a plain grey background." -p template=t_pose -o assets/stadium/source/tripo/fans/<id>_concept
   tripo make ./<the concept's generated_image.png> --model tripo-p2 -p pbr=false -p face_limit=30000 -o assets/stadium/source/tripo/fans/<id>
   ```
   Look at the concept before paying for the model. If the model comes back grey, texture it from the concept (`tripo model texture <task id> -p pbr=false -p 'texture_prompt={"image":"./<concept>"}'`, 10 credits) and then run `tripo mesh uv <that task id>` (20 credits), or its face will not survive the thinning.
3. Put the path of `model.glb` into the fan's `source` and run `prep_crowd.py` with `preview=<dir>`. Look at `<id>_joints_front.png` (the skeleton it found; override a joint under `joints`), `<id>_mask.png` (red: painted with the part's colour, green: skin; override a sampled colour under `keys`) and `kit_<gender>_near_front.png`.
4. `godot --headless --path . --import`, then the crowd gallery (under Checks) for every head on every outfit with the real shader.

Nothing in the game needs changing: `Stadium` reads what is in the kit.

## Mascots

Every team has a fruit mascot: `assets/stadium/mascot_<team>.glb`, where `<team>` is the team's short name in lower case (`mascot_peachez.glb`). A team without a file gets the banana. All six in one picture: `docs/images/mascot_lineup.png`.

- **Same build for all.** A fruit body with the face on it, thin black arms and legs, white gloves, sneakers, arms raised. 5,000 triangles or fewer, one 1024 px texture, one unit tall, feet on the origin, facing +Z.
- **Same skeleton.** `Root`, `Body`, and `UpperArm`, `Forearm`, `Hand`, `Thigh`, `Shin`, `Foot` with `.L` and `.R`. The legs hang from `Root`, so the feet stay put when the body sways.
- **Same clips.** `idle`, `cheer`, `sulk`, `wave`, `run`, 30 frames a second. `run` is for the field (see below); the sideline never plays it. `Stadium._play_mascot()` picks one: `cheer` while that side's crowd is up, `sulk` while it is slumped, `wave` during a wave, else `idle`. The hop and rock from code go on top.
- **Size.** `MASCOT_HEIGHT` (2.8 yards, the banana), but no wider than `MASCOT_WIDTH` (2 yards), so the round ones stand about 2 yards tall.

### On the field

The scramble that opens each half (and sudden death) is mascot against mascot: nobody else is on the field. Each team has a `Mascot` (`scripts/mascot.gd`, `scenes/mascot.tscn`), a `Player` that wears the model from `Stadium.mascot_model()` and plays its clips (`run` while moving, `cheer` or `sulk` after a score) in place of a `PlayerAnimator`. The one that comes up with the ball runs it back and the other one tackles it.

- **Equal.** Every mascot is rated 50 in everything (`Mascot.ratings_for()`), and the CPU's skill edge is off during a scramble (`PlayController.team_edge()`).
- **Who is on the field.** `Team.players` is whoever is playing: the mascot alone during a scramble, the seven otherwise. `Team.squad` is always the seven; the box score and the roster screen go by it. `PlayController._field()` swaps them, hides the seven and the two sideline mascots for the scramble, and `_reset_play()` puts everything back at the next line-up.
- `tests/scramble_check.gd` checks that only the two mascots are out there, that both are rated 50, and that neither team wins nearly all of them.

To add a mascot for a new team:

1. Add the team to `tools/mascots.json` with a prompt. Copy one of the others and change only the costume and its accessories.
2. `tools/make_mascot.sh <team>` generates the model with Tripo (about 110 credits). Put the path of its `model.glb` into the team's `source`.
3. `blender -b --factory-startup --python tools/prep_mascot.py -- <team> preview=<dir>` cleans it up, rigs it, writes the clips and exports the GLB. Look at the previews: `<team>_bones_front.png` shows the skeleton, the others a few poses.
4. `blender -b --factory-startup --python tools/mascot_lineup.py -- docs/images/mascot_lineup.png [clip=sulk]` renders all of them side by side.

`prep_mascot.py` finds the joints from the separate pieces Tripo builds these figures from (body, gloves, shoes, tubes for the limbs). If a limb came out fused to its glove or shoe, it says so and that limb moves as one piece (the apple's arms). If a joint lands in the wrong place, set it by hand under `joints` in `mascots.json`. To change a clip, edit `CLIPS` in the script and run it again for every team.

## Checks

- `godot --headless --path . --script res://tests/stadium_check.gd` (real time, about 10 s): built, fans behind the wall, shares per side, reactions, both mascots and their clips, jumbotron, density, off switch.
- `godot --path . --resolution 1280x720 --script res://tests/stadium_gallery.gd -- out=<dir> [only=<text>]` (window): screenshots from the game camera, the intro shot, each prop, both mascots (`only=mascot home=<team> away=<team>` picks the teams), a cheer and a wave.
- `godot --path . --resolution 1400x1000 --script res://tests/crowd_gallery.gd -- out=<dir>` (window): every head on every outfit with the crowd's shader, from the front, behind, the side and in a cheer, each row close up, a fan with a sign and the plainest level.
- `godot --path . --resolution 1280x720 --script res://tests/stadium_perf.gd` (window): frame times with the stadium off and on.

## Cost

Measured 2026-11-14 on an RTX 4070 Ti / i7-9700K, v-sync off, eight camera stops, 4x MSAA, stadium on, three runs each:

| | frame time (fps) | most triangles in a frame | most draw calls in a frame |
| --- | --- | --- | --- |
| One placeholder man, 1280x720 | 2.06 to 2.49 ms (401 to 485) | 2.1 to 2.2 million | 2,420 |
| One placeholder man, 1920x1080 | 1.95 to 2.27 ms (441 to 514) | 2.2 to 2.8 million | 2,420 |
| Kit of parts (men), 1280x720 | 1.85 to 2.11 ms (475 to 542) | 1.5 to 1.6 million | 2,468 |
| Kit of parts (men), 1920x1080 | 1.80 to 1.88 ms (532 to 557) | 1.4 to 1.6 million | 2,468 |

So the kit is a little faster than the one man it replaced: about a third fewer triangles for 48 more draw calls. Runs differ by up to 0.4 ms on the same build, so read the frame times as "no slower, probably 10 % faster". The women's parts will add draw calls (more meshes per piece of the stands) and no triangles. The game runs at about 500 fps on this machine and is not limited by the graphics card, so this says little about a weak GPU; there, lower `crowd_lod_near` and `crowd_lod_far` first, then `crowd_density`, then `anti_aliasing/quality/msaa_3d` in the project settings.

## Open issues

- The game camera looks down at the field and never sees above the top rows, so the jumbotrons and light towers only show in the intro, on the menu (towers) and in shots from further out.
- When the ball carrier is deep in their own end zone, the front rows of the stand behind come into the bottom of the picture. They do not cover the field.
- The ball does not collide with the wall or the stands; thrown far out of bounds it passes through them.
- The kit has men only so far (3 heads, 3 outfits, 1 pair of legs); the women are to come. Until then `crowd_female_share` does nothing.
- A fan with a sign always wears the first outfit (the jersey): only that one is made with the arms up, to save draw calls.
- Beyond `crowd_lod_far` every fan of a gender has the same shape (colours still differ), and at the middle level the faces are rough. Neither shows from the game camera; they do in a close shot of a far stand.
- A head keeps its own size, and the first fan's is big: on the lean hoodie it looks a little heavy.
- Hands are thinned to a few triangles and the fingers come out as points when seen close.
- A source model whose texture is in many small islands (the re-textured hoodie fan was) loses its face when thinned; `tripo mesh uv` on it fixes that.
- No props besides the signs yet (foam finger, hat, hot dog).
- The fans sit with their legs bent even when they are up in a cheer; only the arms and the height change.
- The mascot on the far sideline stands in the shade and looks dull and bluish (a yellow banana turns olive).
- The lineup render's colours are flatter than the game's.
