# The stadium

The bowl round the field: wall, tiered stands with aisles and tunnel mouths, about 3,150 fans the size of the players, ad boards, two jumbotrons, four light towers and a hot dog stand. It stands right on the field, as in an arena: the wall is `Tuning.wall_gap` (0.7 yards) past the sidelines and the end lines, on all four sides. It is scenery, except for the wall, which is solid and part of the game (see The wall), and the stands, which a ball that clears the wall lands on (`Stadium.surface_height()`). The teams' mascots are not part of it any more: they stand on the field with their teams (see Mascots).

## How it is put together

- `scripts/stadium.gd` (`Stadium`) builds everything in code when `Field.setup()` runs, from the field's size in `Tuning` (100 yards by 53.33, the NFL's 160 feet, with 10-yard end zones), so a change to `field_width` or `field_length` moves the wall, the stands and the props with it. The plays do not follow by themselves: `tools/stretch_plays.py` rewrites their lateral spacing for a new width. It is the `Stadium` node in `scenes/field.tscn`, so the match and the main menu both get it.
- The outline is a rectangle with tight corners: eight "runs" (four straights, four quarter circles of `CORNER_RADIUS`, 1.5 yards; any rounder and the wall would cut across the corners of the end zones). Every row is that outline pushed `ROW_DEPTH` (1.5) further out and `ROW_RISE` (0.75) higher. The sizes are the constants at the top of the script (`ROW_DEPTH`, `SEAT_PITCH`, ...) and `Tuning.wall_gap`.
- Every place a fan can sit has a seat: the part he sits on and a back that stands on the floor of the row (`Stadium._build_seats()`, one mesh, `Seats`, in the colour of that part of the crowd). The seats and the fans take their places from the same list (`_seat_spots()`), so they cannot come apart; the sizes are the `SEAT_*` constants, set to fit the sitting pose `tools/prep_crowd.py` bakes. Empty seats show where `crowd_density` leaves one free.
- The fans are as big as the players, so there are far fewer of them than seats in a real stadium: 13 rows, about 3,150 fans. Each is put together from a **head**, a **torso** (the outfit: jersey, hoodie, tank top) and **legs** out of a kit of parts, `assets/stadium/crowd_kit.glb`. `tools/prep_crowd.py` cuts the kit from whole Tripo characters, fits the parts to each other, and bakes them sitting, because a `MultiMesh` cannot have a skeleton. `Stadium._seat()` gives every seat a gender, a head, an outfit and legs at random; the three parts are `MultiMesh` instances with the same transform, so they move as one. The crowd is cut into 36 pieces (one per bay of a straight, three per corner). Each piece holds its fans three times, at three levels of detail, and shows the one that fits its distance from the camera: parts in full detail (about 1,000 triangles a fan) up to `crowd_lod_near` yards, plainer parts (about 360) up to `crowd_lod_far`, and one whole plain fan per gender (about 140) beyond. The levels blend over `LOD_BLEND` yards.
- All of them share `assets/stadium/crowd.gdshader`. It does the bobbing, cheering, sulking and the wave from a per-fan phase and speed, so the CPU only sets a few uniforms per frame and no two fans move in step. The arms swing up about the shoulders by how much each vertex belongs to an arm, which `prep_crowd.py` writes into the second UV set, along with which part a vertex is on. Colour comes from two pictures the script makes: `crowd_atlas.png` (every source fan's texture, with cloth, hair and skin reduced to their shading) and `crowd_mask.png` (red: paint with the part's colour, green: paint with the skin tone). The shirt colour, skin tone, hair colour and trouser colour are per fan (`Stadium._fan()`); a shoe, an eye or the number on a jersey is not painted and keeps the texture's colour.
- The signs are separate flat boards (`assets/stadium/crowd_sign.gdshader`), one per fan with the arms up, 2.5 yards wide. Both shaders include `assets/stadium/crowd_motion.gdshaderinc`, so a board moves with the hands that hold it.
- Reactions come from the audio: `AudioDirector.crowd_react()` calls `Stadium.react(for_home, size)`. Anything that already makes the crowd cheer or groan moves the stands too. `Game._ready()` calls `stadium.watch(self)` so the stadium can read the score (jumbotrons), `audio.excitement` (livelier bobbing) and the state (a wave only starts between plays).

## The wall

The wall is 2.3 yards high (`WALL_HEIGHT`), a little taller than a player (1.95), and nothing goes through it. There is no out of bounds: the strip between the lines and the wall is live turf, and the play goes on until somebody is down, scores, or the ball lands.

- **Where it is.** `Stadium.wall_distance(tuning, x, z)` is the distance to its face (below 0 on the field) and `Stadium.wall_normal(tuning, x, z)` the way it faces, round the corners too. Both are static and go by the `Tuning` alone, so the wall is there for the players even with `stadium_enabled` off. `Stadium.keep_inside()` brings a spot back inside it.
- **Players on their feet** are stopped `wall_standoff` (0.4 yards) short of it and slide along it, like a skater on the boards (`Player.keep_on_field()`, `Player._meet_wall()`). A carrier is not down for touching it.
- **No part of a player is in the wall.** It is not only his middle that is held back: after he is posed each tick, `Player._clear_wall()` measures how far his body reaches toward the wall (every bone below the top of it, plus `LIMB_THICKNESS`) and moves him out by whatever is in it. So one lying with his head to the wall is about a yard off it, a diver meets it with his hands, and one tipping off it after being flattened keeps his feet at the foot of it. `Player._wall_room()` is the room his middle needs.
- **Players thrown at it** are flattened against it. Anyone who goes into it in a dive or while knocked down (a tackle, a shove, a dive hit) at `wall_splat_speed` (4 yd/s straight at it) or more sticks to it, arms and legs out and pressed thin, for `wall_splat_stick_time` (0.8 s), then tips off it like a board, lands on the turf and lies there dazed, stars round his head, for `wall_splat_daze_time` (2.6 s). He gets up injured, exactly as after a jump dive: his ratings are halved for the rest of the play and the one after it (`injury_rating_scale`, `injury_plays`) (`Player.splat()`, `PlayerFall.Kind.SPLAT`; the look is the `SPLAT_*` constants in `scripts/player_fall.gd`). Slower than that he just comes back off it a little (`wall_bounce`). A carrier's own dive into the wall is down where he hits it. Mascots are players, so it happens to them as well. The stat is `wall_splats`.
- **The ball** comes back off it (`Ball._off_wall()`): what was going into the wall returns at `Ball.WALL_BOUNCE` (0.4) of it and the rest carries on along the wall. A pass that meets its face is live like a tipped one, for either team, until it touches the turf (`PlayController._pass_off_wall()`, stat `wall_passes`). A ball that goes over the wall is gone: a pass into the stands is incomplete, which is what the throw-away does (it is aimed at the seats), and a fumble into the stands is dead where it left, with the team that had it (`Result.OUT_OF_PLAY`, stat `fumbles_out_of_play`).
- **Nothing marks the edge on the turf.** There are no sidelines, end lines or pylons: the mown grass, the yard lines and the end zone colour run on to the foot of the wall (`margin` in `assets/field/turf.gdshader`, set by `Field.setup()`). The turf shader also paints the hash marks (the inner rows `hash_offset`, 3.08 yards, either side of the middle, as in the NFL) and the yard numbers (`number_inset`, 11 yards, in from each side; block numerals, each row's feet toward its own side, with an arrow to the nearer goal line) and the two mascots either side of the 50, facing each other (see Mascots).
- The CPU still steers by the lines (`half_width()` less a yard or two in `scripts/player_brain.gd`), which keeps runners and routes off the wall. It does not yet use the wall on purpose.

## Changing things

| What | Where |
| --- | --- |
| Team colours | Nothing to set. Fans, seats and props take `team_color` from the two teams, so they follow the team select. |
| Crowd density | `crowd_density` in the Stadium group of `resources/tuning.tres` (0..1 of about 3,700 seats). |
| A different crowd | `crowd_seed`: who sits where and what they look like. The same number gives the same crowd. |
| One head, outfit or pair of legs for everybody | `crowd_head`, `crowd_torso` and `crowd_legs`: the id of a fan in `tools/crowd_parts.json` (`m5`, `m8`, `m11`: the heads; `m6`, `m9`, `m10`: the outfits; `m7`: the legs). Empty, as they are now, for one at random out of the kit: with three heads and three outfits in it, the crowd is split evenly between them. A fan keeps its head and its outfit at every level of detail: the plainest level is drawn in parts too (the kit's one whole fan at that level, with the parts named by `far_head`, `far_torso` and `far_legs`, is only for the viewer and the gallery). |
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
- `BoothAnchor`: an empty marker at the top of the home stand at midfield. There is no booth model yet; this is where one would go.

## Assets and how to rebuild them

Blender is at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`. From the project root:

```
blender -b --factory-startup --python tools/prep_crowd.py -- [preview=<dir>] [rig=<file.blend>]
blender -b --factory-startup --python tools/prep_prop.py -- assets/stadium/source/tripo/<prop>/tripo-out/<task>/model.glb assets/stadium/<prop>.glb tris=5000 yaw=-90
```

- `crowd_kit.glb`, `crowd_atlas.png` and `crowd_mask.png` are the crowd's parts; see "The crowd's parts" below. The kit's import has `generate_lods` off, since the levels are made by the script. (`fan.glb` and `tools/prep_fan.py` are the old single-model crowd and are no longer used.)
- The signs are not files. `Stadium._bake_signs()` writes the 16 texts into one picture at the start of a match (a viewport that is thrown away afterwards) and the crowd shader shows one cell on the front of each board. The picture is ready by the second frame of a match. Headless runs skip the bake.
- `jumbotron.glb` and `hot_dog_stand.glb` are Tripo models (prompts in each `task.json`), and `light_tower.glb` is made from `TripoModels/stadium_light_tower/stadium_light_tower.fbx` (`tris=9000`, which leaves it whole, and no `yaw`; the script reads FBX too). The others are cut to 5,000 triangles or fewer and 1024 px textures. `yaw=-90` because Tripo's models came out facing +X. `Stadium._prop()` scales each to the height it wants, and shows a plain box if a file is missing.
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

The kit is now made of parts that came by themselves, each a fan with `only` (the whole characters it was first cut from, `m1` to `m4`, are gone; the skeleton they gave is kept as the gender's `skeleton` in `crowd_parts.json`, and a run with whole fans prints a new one after SKELETON):

- `"only": "head"`: a head with its neck (`TripoModels/crowd_head_m5_brown_beard`, fan `m5`). It is not cut, only put on the gender's neck: `neck` says how far up the model its neck line is, `size` and `shift` adjust it. With `"keys": {"skin": null, "hair": null}` it keeps the colours of its own texture, so every fan has the same face whatever the skin tone of the arms; without that it is repainted like the others, which needs clean, flat-coloured skin and hair to look right.
- `"only": "torso"`: a torso with its arms, open at the neck and at the waist (`TripoModels/crowd_torso_m6_grey_vneck`, fan `m6`). Its collar goes to the gender's neck and its hem to the waist, its arms are found and bent like a whole fan's, and its shirt and skin are repainted as usual, unless `keys` says otherwise: `m6` has `"keys": {"shirt": null, "skin": null}` and keeps the colours of its own texture, so its shirt is the same grey on both teams. To repaint a torso like it, with short sleeves on arms whose skin is near the shirt's colour, give it `"options": {"bare": "elbow"}`.

- `"only": "legs"`: trousers and shoes, open at the waist (`TripoModels/crowd_legs_m7_jeans_sneakers`, fan `m7`). They stand on the ground with the waistband at the gender's waist, and the legs are found and bent like a whole fan's. `m7` keeps its own colours too (`"keys": {"pants": null, "skin": null}`).

`tools/crowd_viewer.tscn` (F6) opens on the head, the outfit and the legs the whole crowd has; B comes back to them.

## Mascots

Every team has a fruit mascot: `assets/stadium/mascot_<team>.glb`, where `<team>` is the team's short name in lower case (`mascot_peachez.glb`). A team without a file gets the banana. All six in one picture: `docs/images/mascot_lineup.png`.

- **Same build for all.** A fruit body with the face on it, thin black arms and legs, white gloves, sneakers, arms raised. 5,000 triangles or fewer, one 1024 px texture, one unit tall, feet on the origin, facing +Z.
- **Same skeleton.** `Root`, `Body`, and `UpperArm`, `Forearm`, `Hand`, `Thigh`, `Shin`, `Foot` with `.L` and `.R`. The legs hang from `Root`, so the feet stay put when the body sways.
- **Same clips.** `idle`, `cheer`, `sulk`, `wave`, `run`, `point`, `flex`, `faint`, 30 frames a second. `Mascot._update_visual()` picks one: `faint` while it is knocked down, `run` while it is moving, a clip it has been asked to act out, `cheer` or `sulk` after a touchdown, else `idle`.
- **Size.** `MASCOT_HEIGHT` (2.8 yards, the banana), but no wider than `MASCOT_WIDTH` (2 yards), so the round ones stand about 2 yards tall.

### Standing by

There is no room between the lines and the wall, so each team's mascot is on the field with its team on every play. It is the team's `Mascot` (`scripts/mascot.gd`, `scenes/mascot.tscn`), a `Player` with `bystander` set: it has no assignment and leaves the ball alone, but it is as solid as anyone.

- **Where it stands.** `PlayController._place_mascots()` (from `line_up()` and `line_up_kickoff()`) puts it with its own side, out of the way: `mascot_off_depth` (14 yards) behind the line of scrimmage with the offense, `mascot_def_depth` (8 yards) behind the deepest defender with the defense (behind the rearmost man of either team at a kickoff), `mascot_sideline_inset` (1.5 yards) in from its own sideline. The home team's sideline is the one at -Z. It stays there and turns to watch the ball (`PlayerBrain._stand_by()`).
- **Not one of the team.** It is in `PlayController.players`, so it moves, collides and can be hit like everyone, but not in `Team.players`, so no play gives it a job, nobody covers it, it cannot catch, tip or pick up a ball, and the person cannot switch to it.
- **Contact.** Bodies keep each other out as usual, and the mascot is `mascot_extra_radius` (0.4 yards) wider than a footballer. A player who runs into it at `mascot_bump_speed` (5 yards a second) or more knocks it over (`PlayController._bump_mascot()`, the stat `mascot_bumps`) and is slowed for `mascot_bump_slow_time`. The person's dive flattens it like any bystander. A carrier who runs into the other team's mascot gets an ordinary tackle attempt from it, broken tackles and fumbles included. Knocked down, it plays `faint` (a model without that clip tips over on its back) and gets up again.
- **It acts things out.** `Game.mascot_moment(team, clip)` calls `Mascot.react()`, which holds a clip for `ACT_TIME` seconds:

  | What happened | The team's own mascot | The other one |
  | --- | --- | --- |
  | A first down | `point` | |
  | A sack, a stop on fourth down | `flex` (the defense's) | |
  | An interception, a fumble lost | `flex` (the taker's) | `faint` |
  | A touchdown | joins the huddle (below) | `faint` |

  `faint` is played once and held (`ONE_SHOT`). A model without one of the three plays a stand-in (`STAND_INS`).
- **It joins the touchdown huddle.** `PlayController._invite_mascot()` makes the scoring team's mascot one of `Team.players` until the next line-up: it runs over from where it stood, gets a place in the ring like any teammate, can be the victim of a cheap shot, and dives onto the heap with the rest when the person's player dives during the celebration (`PlayController.start_pile_on()`); `_dismiss_mascot()` (from `_reset_play()`) makes it a bystander again. `Tuning.mascot_joins_party` turns it off.
- `tests/mascot_bystander_check.gd` checks where the two stand, that they never have the ball, that one run into goes over and gets up, and the wall (players kept inside it, a ball landing on the stands).

### On the team select

`TeamSelect` stands each side's mascot on the top edge of its panel (`_build_mascot()`, `_show_mascot()`): the same model, drawn in a small world of its own (a `SubViewport` with a camera and a light) only while the screen is up. It cheers on the side the controller is under and idles on the other. Here a round mascot is not kept small as on the sideline: each is scaled to `MASCOT_TALL`, unless that makes it wider than `MASCOT_WIDE`. `tests/menu_check.gd` checks that each side shows its own team's.

### A new mascot

To add a mascot for a new team:

1. Add the team to `tools/mascots.json` with a prompt. Copy one of the others and change only the costume and its accessories.
2. `tools/make_mascot.sh <team>` generates the model with Tripo (about 110 credits). Put the path of its `model.glb` into the team's `source`.
3. `blender -b --factory-startup --python tools/prep_mascot.py -- <team> preview=<dir>` cleans it up, rigs it, writes the clips and exports the GLB. Look at the previews: `<team>_bones_front.png` shows the skeleton, the others a few poses.
4. `blender -b --factory-startup --python tools/mascot_lineup.py -- docs/images/mascot_lineup.png [clip=sulk]` renders all of them side by side.

`prep_mascot.py` finds the joints from the separate pieces Tripo builds these figures from (body, gloves, shoes, tubes for the limbs). If a limb came out fused to its glove or shoe, it says so and that limb moves as one piece (the apple's arms). If a joint lands in the wrong place, set it by hand under `joints` in `mascots.json`. To change a clip, edit `CLIPS` in the script and run it again for every team.

### The pictures at midfield

`tools/mascot_decal.py` (Blender, run like `mascot_lineup.py`, with team keys or none for all) renders each mascot flat-lit on a clear background to `assets/field/mascot_<team>.png`, turned to look toward the right of the picture. `Field` gives the picture of the team on each half to the turf shader (`left_mascot`, `right_mascot`; the banana's if a team has none), which paints them `mascot_size` (8 yards) square either side of the 50, heads toward -z, the right-hand one mirrored. `stadium_gallery.gd -- only=field` shows them and the numbers.

## Checks

- `godot --headless --path . --script res://tests/stadium_check.gd` (real time, about 10 s): built, fans behind the wall, shares per side, reactions, jumbotron, density, off switch.
- `godot --path . --resolution 1280x720 --script res://tests/stadium_gallery.gd -- out=<dir> [only=<text>]` (window): screenshots from the game camera, the intro's first and last shot, the wall along a sideline and at an end, each prop, both mascots where a play puts them (`only=mascot home=<team> away=<team>` picks the teams), what they act out and one knocked over, a cheer and a wave.
- `godot --headless --fixed-fps 60 --path . --script res://tests/wall_probe.gd -- seconds=400` (about a minute): the CPU plays both teams and every bone of every player and mascot is looked at every frame; it fails if any is in the wall, and says in which state.
- `godot --headless --fixed-fps 60 --path . --script res://tests/wall_check.gd` (a few seconds): the wall as a solid thing. A player run at it stays up and slides along it, one shoved at it is flattened, sticks and gets up, a carrier's dive into it is down, a loose ball and a pass come back off it (the pass still live), a carrier or a ball past the sideline is in play, and a ball in the stands is dead. The gallery's `only=wall` shots show the wall's height against a player and the squish from hit to getting up.
- `tests/celebration_check.gd` checks that the mascot of the scorer's team reaches the huddle and is standing by again at the next line-up.
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
- When the ball carrier is deep in their own end zone, the stand behind fills the bottom third of the picture (the camera is over its rows). It does not cover the field.
- A ball in the stands lies on the row it landed on, among the fans; it does not bounce off them, and nobody throws it back.
- With no sideline to run out of, plays to the edge gain more than they did and the clock never stops for a carrier going out. Nothing has been retuned for that yet.
- Being flattened on the wall has no sound of its own: it plays the big hit lower.
- The CPU does not steer round a mascot standing by (its brains only look at `Team.players`), and the other team's mascot will tackle a carrier who runs into it.
- The kit has men only so far (3 heads, 3 outfits, 1 pair of legs, all in the colours of their own textures, so shirts do not show the teams' colours); the women are to come. Until then `crowd_female_share` does nothing.
- A fan with a sign always wears the first outfit (the jersey): only that one is made with the arms up, to save draw calls.
- Beyond `crowd_lod_far` every fan of a gender has the same shape (colours still differ), and at the middle level the faces are rough. Neither shows from the game camera; they do in a close shot of a far stand.
- A head keeps its own size, and the first fan's is big: on the lean hoodie it looks a little heavy.
- Hands are thinned to a few triangles and the fingers come out as points when seen close.
- A source model whose texture is in many small islands (the re-textured hoodie fan was) loses its face when thinned; `tripo mesh uv` on it fixes that.
- No props besides the signs yet (foam finger, hat, hot dog).
- The fans sit with their legs bent even when they are up in a cheer; only the arms and the height change.
- The lineup render's colours are flatter than the game's.
