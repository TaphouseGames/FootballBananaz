"""Turns a rigged Tripo character into a player the game can dress in a kit.

Run from the project root:

    blender -b --factory-startup --python tools/prep_player.py -- [only=<id>] [preview=<dir>]

It reads tools/players.json (every player with a `source`, or the one named)
and writes, per player:

    assets/player/people/<id>.glb          the rigged model with its textures at 1024
    assets/player/people/<id>_mask.png     what the kit shader repaints
    assets/player/source/people/<id>.blend the cleaned model, to touch up by hand

What happens to a player:

1. Clean-up: one welded mesh that keeps its quads, the front looking down -Y,
   the player's left at +X, the feet on the ground, no transforms left on the
   armature or the mesh, at most four bones a vertex.
2. The kit is found in the colour texture. The character is made in a white
   jersey, mid grey pants and dark grey socks; which of those a texel may be
   goes by the bones its triangle hangs on, and whether it is one by its
   colour: a kit colour has no hue, skin has (the colour of the hands). The
   jersey is told from the pants by brightness and by lying above them, the
   socks from the pants by lying below the knee. Where
   it is kit, the colour texture is reduced to its shading and the mask says
   what it is:
       mask R  jersey      mask G  pants      mask B  socks
   Skin, hair, shoes and whatever else the player wears stay as painted.
3. A mask that was painted by hand wins: if assets/player/source/people/
   <id>_mask_paint.png exists it is used as it is (see `paint` below).

Per player in players.json, all optional:
    source    the rigged FBX, from the project root
    yaw       degrees to turn the model so it faces -Y (-90 if not given: Tripo's face +X)
    options   chroma (0.5: how far toward the skin's hue a kit texel may be, 0..1),
              luma ([0.3, 1.9]: how much darker and brighter than the jersey a texel of it may be),
              socks_from (0.0: no sock below this height, as a share of the player's)

With `preview`, pictures are saved there: the model as painted and in a test
kit from four sides, and its mask.
"""

import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "player", "people")
BLEND_DIR = os.path.join(ROOT, "assets", "player", "source", "people")
SIZE = 1024
LUMA = np.array([0.3, 0.59, 0.11])
JERSEY, PANTS, SOCKS = 1, 2, 4
# Darker than this a texel is in deep shadow.
DEEP = 0.13
# Darker than this a plain texel on a leg is a sock, not the pants.
SOCK_DARK = 0.2
# How many ways round the body the hem of the jersey is looked for.
SECTORS = 48
GARMENTS = ((JERSEY, "jersey"), (PANTS, "pants"), (SOCKS, "socks"))
# What the triangles that hang on a kind of bone may be.
KINDS = ["head", "hand", "forearm", "neck", "arm", "spine", "hips", "thigh", "calf", "foot"]
ALLOWED = {
    # (Sleeves are short: nothing below the elbow is the jersey. On the head
# and the neck only what is below the line of the collar is.)
    "head": JERSEY, "hand": 0, "forearm": 0, "foot": 0,
    "neck": JERSEY, "arm": JERSEY, "spine": JERSEY,
    "hips": JERSEY | PANTS, "thigh": JERSEY | PANTS, "calf": PANTS | SOCKS,
}
# The bones the game's animator turns: a player must have them all.
NEEDED = [
    "Hip", "Waist", "Spine02", "NeckTwist01", "Head",
    "L_Upperarm", "L_Forearm", "L_Hand", "R_Upperarm", "R_Forearm", "R_Hand",
    "L_Thigh", "L_Calf", "L_Foot", "R_Thigh", "R_Calf", "R_Foot",
]

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
options = dict(arg.split("=", 1) for arg in argv)
unknown = [key for key in options if key not in ("only", "preview")]
if unknown:
    raise SystemExit("usage: prep_player.py -- [only=<id>] [preview=<dir>]  (unknown: %s)" % ", ".join(unknown))
preview_dir = options.get("preview")

with open(os.path.join(ROOT, "tools", "players.json"), encoding="utf-8") as handle:
    CONFIG = json.load(handle)


def kind_of(bone):
    for word in ("Hand", "Pinky", "Ring", "Mid", "Index", "Thumb"):
        if word in bone:
            return "hand"
    if "Neck" in bone:
        return "neck"
    if "Head" in bone or "Facial" in bone or "Eye" in bone:
        return "head"
    if "Forearm" in bone or "Elbow" in bone:
        return "forearm"
    if "Upperarm" in bone or "Clavicle" in bone:
        return "arm"
    if "Spine" in bone:
        return "spine"
    if "Thigh" in bone:
        return "thigh"
    if "Calf" in bone or "Knee" in bone:
        return "calf"
    if "Foot" in bone or "Toe" in bone:
        return "foot"
    return "hips"


def pixels_of(image, size, channels=3):
    """The picture at `size` a side: rows from the bottom, values as in the file."""
    if tuple(image.size) != (size, size):
        image.scale(size, size)
    pixels = np.empty(size * size * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    return pixels.reshape(size, size, 4)[:, :, :channels].astype(np.float64)


def new_image(name, array, path=None, colour=True):
    """An image from (rows from the bottom, 0..1, 3 channels), saved as a PNG if `path`."""
    height, width = array.shape[:2]
    image = bpy.data.images.new(name, width, height, alpha=False)
    if not colour:
        image.colorspace_settings.name = "Non-Color"
    pixels = np.ones((height, width, 4), dtype=np.float32)
    pixels[:, :, :3] = array
    image.pixels.foreach_set(pixels.ravel())
    if path:
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
    else:
        image.pack()
    return image


def chroma(colour):
    return colour / (colour.sum(-1, keepdims=True) + 1e-4)


def box_sum(flags, reach):
    total = np.pad(flags.astype(np.int32), (reach + 1, reach)).cumsum(0).cumsum(1)
    size = 2 * reach + 1
    return total[size:, size:] - total[:-size, size:] - total[size:, :-size] + total[:-size, :-size]


def raster(uvs, values, size):
    """A map (size, size) of the value of the triangle each texel lies in (-1: none)."""
    out = np.full((size, size), -1, dtype=np.int32)
    px = np.mod(uvs, 1.0) * size
    lo = np.clip(np.floor(px.min(1)).astype(int), 0, size - 1)
    hi = np.clip(np.floor(px.max(1)).astype(int), 0, size - 1)
    for f in range(len(px)):
        x0, y0 = lo[f]
        x1, y1 = hi[f]
        if x1 - x0 < 2 and y1 - y0 < 2:
            out[y0:y1 + 1, x0:x1 + 1] = values[f]
            continue
        a, b, c = px[f]
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / d
        w1 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / d
        inside = (w0 >= -0.05) & (w1 >= -0.05) & (w0 + w1 <= 1.05)
        out[y0:y1 + 1, x0:x1 + 1][inside] = values[f]
    # A few texels past the edges of the islands, so no seam shows.
    for _ in range(6):
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            moved = np.roll(out, (dy, dx), axis=(0, 1))
            empty = out < 0
            out[empty] = moved[empty]
    return out


def load(player_id, entry):
    """The player's armature and mesh, cleaned (see the top of the file)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, entry["source"]))
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    missing = [bone for bone in NEEDED if bone not in armature.data.bones]
    if missing:
        raise SystemExit("%s: the rig has no %s" % (player_id, ", ".join(missing)))

    # Turned to face -Y, and everything put into the data.
    armature.matrix_world = Matrix.Rotation(math.radians(float(entry.get("yaw", -90.0))), 4, "Z") @ armature.matrix_world
    bpy.context.view_layer.update()
    body.data.transform(body.matrix_world)
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    body.parent = armature
    body.matrix_parent_inverse = Matrix.Identity(4)
    body.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()

    # The feet on the ground, the middle over the origin.
    points = np.empty(len(body.data.vertices) * 3)
    body.data.vertices.foreach_get("co", points)
    points = points.reshape(-1, 3)
    shift = Vector((-(points[:, 0].min() + points[:, 0].max()) * 0.5, 0.0, -points[:, 2].min()))
    body.data.transform(Matrix.Translation(shift))
    armature.data.transform(Matrix.Translation(shift))

    bm = bmesh.new()
    bm.from_mesh(body.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bm.normal_update()
    bm.to_mesh(body.data)
    bm.free()
    body.data.polygons.foreach_set("use_smooth", [True] * len(body.data.polygons))
    body.data.update()
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    loose = sum(1 for v in body.data.vertices if not v.groups)
    sides = {}
    for poly in body.data.polygons:
        sides[len(poly.vertices)] = sides.get(len(poly.vertices), 0) + 1
    body.name = armature.name = player_id
    body.data.name = player_id
    armature.name = player_id + "_rig"
    print("CLEANED %s: %d vertices (%d welded away), faces by corners %s, %d without a bone, %.3f tall" % (
        player_id, len(body.data.vertices), before - len(body.data.vertices), sides, loose, points[:, 2].max() - points[:, 2].min()))
    return armature, body


def textures_of(body):
    """The material's pictures: colour, normal, roughness (any may be None)."""
    found = {"colour": None, "normal": None, "rough": None}
    for material in body.data.materials:
        if material is None or material.node_tree is None:
            continue
        nodes = material.node_tree.nodes
        shader = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
        if shader is None:
            continue
        for key, socket in (("colour", "Base Color"), ("rough", "Roughness")):
            if shader.inputs[socket].links:
                source = shader.inputs[socket].links[0].from_node
                if source.type == "TEX_IMAGE" and source.image is not None:
                    found[key] = source.image
        bump = next((n for n in nodes if n.type == "NORMAL_MAP"), None)
        if bump is not None and bump.inputs["Color"].links:
            source = bump.inputs["Color"].links[0].from_node
            if source.type == "TEX_IMAGE" and source.image is not None:
                found["normal"] = source.image
    return found


def find_kit(player_id, entry, armature, body, texture):
    """The mask (H, W, 3: jersey, pants, socks) and the colour texture with
    the kit reduced to its shading."""
    given = entry.get("options", {})
    lean = float(given.get("chroma", 0.5))
    dark, bright = given.get("luma", [0.3, 1.9])
    mesh = body.data
    names = [group.name for group in body.vertex_groups]
    kind_index = np.array([KINDS.index(kind_of(name)) for name in names])
    shares = np.zeros((len(mesh.vertices), len(KINDS)))
    for vertex in mesh.vertices:
        for element in vertex.groups:
            shares[vertex.index, kind_index[element.group]] += element.weight
    mesh.calc_loop_triangles()
    tris = np.array([tri.vertices[:] for tri in mesh.loop_triangles])
    loops = np.array([tri.loops[:] for tri in mesh.loop_triangles])
    uv_all = np.empty(len(mesh.loops) * 2)
    mesh.uv_layers.active.data.foreach_get("uv", uv_all)
    uvs = uv_all.reshape(-1, 2)[loops]
    at = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", at)
    at = at.reshape(-1, 3)
    tall = at[:, 2].max()
    centres = at[tris].mean(1)
    face_map = raster(uvs, np.arange(len(tris)), SIZE)
    on_model = face_map >= 0
    face_map = np.maximum(face_map, 0)
    kind_map = np.where(on_model, shares[tris].mean(1).argmax(1)[face_map], -1)
    z_map = centres[:, 2][face_map]
    x_map = centres[:, 0][face_map]
    # How much a texel's triangle faces up (1) or down (-1).
    across = np.cross(at[tris[:, 1]] - at[tris[:, 0]], at[tris[:, 2]] - at[tris[:, 0]])
    up_map = (across[:, 2] / (np.linalg.norm(across, axis=1) + 1e-12))[face_map]
    # Which way round the body a texel is, in SECTORS steps.
    hip = np.array(armature.data.bones["Hip"].head_local)
    knee = min(armature.data.bones["L_Calf"].head_local.z, armature.data.bones["R_Calf"].head_local.z)
    sector_map = (np.floor((np.arctan2(centres[:, 1] - hip[1], centres[:, 0] - hip[0]) + math.pi) / (2.0 * math.pi) * SECTORS).astype(int) % SECTORS)[face_map]

    def is_kind(*kinds):
        return np.isin(kind_map, [KINDS.index(kind) for kind in kinds])

    luma = texture @ LUMA
    tone = chroma(texture)
    may = np.zeros((SIZE, SIZE), dtype=np.int8)
    for index, kind in enumerate(KINDS):
        may[kind_map == index] = ALLOWED[kind]

    def middle(where, keep=None):
        """The middle colour of the texels `where`; `keep` picks among them by luma share."""
        colours = texture[where]
        if len(colours) < 50:
            return None
        if keep is not None:
            lumas = colours @ LUMA
            lo, hi = np.percentile(lumas, keep)
            colours = colours[(lumas >= lo) & (lumas <= hi)]
        return np.median(colours, axis=0)

    skin = middle(is_kind("hand"))
    grey = np.array([1.0, 1.0, 1.0]) / 3.0
    if skin is None:
        skin = np.array([0.85, 0.65, 0.55])
    # How far a texel's hue is from no hue at all toward the skin's: 0 grey, 1 skin.
    toward = chroma(skin) - grey
    hue = ((tone - grey) @ toward) / float(toward @ toward)
    # Going by darkness alone (a shadow, a sock) only works beside light skin:
    # dark skin is as dark as either, but has far more hue, which is enough.
    light_skin = float(skin @ LUMA) > 0.35
    deep = DEEP if light_skin else DEEP * 0.4
    sock_dark = SOCK_DARK if light_skin else 0.0
    # No hue at all, toward any colour: navy shoes are dark but are not socks.
    # (How far apart its red, green and blue are: the darker a texel, the less
    # its hue as a share says.)
    spread = texture.max(-1) - texture.min(-1)
    neutral = spread < 0.09
    # No skin shows at the hips, the chest or the back, whatever hue a shadow has there; on the
    # thighs a shadow on the pants is warmer than the pants are. What lies in
    # deep shadow has no hue to go by.
    plain = (hue < lean) | (luma < deep) | is_kind("hips", "spine") | (is_kind("thigh") & (hue < lean + 0.25))
    sector_of = [np.isin(sector_map, [(s - 1) % SECTORS, s, (s + 1) % SECTORS]) for s in range(SECTORS)]

    def part(ups, downs, lowest, highest):
        """The value between `lowest` and `highest` that best parts the
        values `ups` (above it) from the values `downs` (below it)."""
        steps = np.linspace(lowest, highest, 80)
        ups, downs = np.sort(ups), np.sort(downs)
        wrong = np.searchsorted(ups, steps) + (len(downs) - np.searchsorted(downs, steps))
        return float(steps[int(np.argmin(wrong))])

    def line(above, below, lowest, highest):
        """Per sector, the height that best parts the texels `above` from
        the texels `below` it, evened out round the body."""
        steps = np.linspace(lowest, highest, 80)
        found = np.empty(SECTORS)
        for sector in range(SECTORS):
            ups = np.sort(z_map[above & sector_of[sector]])  # (sector_of is read when called)
            downs = np.sort(z_map[below & sector_of[sector]])
            if len(ups) < 30 and len(downs) < 30:
                found[sector] = np.nan
                continue
            # The texels on the wrong side of each height: `above` ones under it, `below` ones over it.
            wrong = np.searchsorted(ups, steps) + (len(downs) - np.searchsorted(downs, steps))
            found[sector] = steps[int(np.argmin(wrong))]
        if np.isnan(found).all():
            return np.full(SECTORS, lowest)
        found[np.isnan(found)] = np.nanmedian(found)
        return np.array([np.median(np.take(found, range(s - 2, s + 3), mode="wrap")) for s in range(SECTORS)])

    # The hem of the pants: below it the legs are bare or in socks, above it
    # everything is the pants, however warm a shadow on them is.
    legs = is_kind("thigh", "calf") & (z_map > knee - 0.08 * tall)
    # (Where socks come up to the pants there is no bare leg to go by: they
    # are far darker than the pants.)
    bare = (hue > lean + 0.25) & (luma > deep)
    hem = line(legs & neutral & (luma >= SOCK_DARK), legs & (bare | (neutral & (luma < SOCK_DARK))), knee - 0.08 * tall, hip[2])[sector_map]
    plain |= is_kind("thigh", "calf") & (z_map > hem + 0.012 * tall)
    # A dark sock has no hue worth reading, and no skin is as dark.
    plain |= is_kind("calf", "foot") & (luma < sock_dark) & neutral
    # The sleeves: along each arm there is one place where the sleeve ends
    # and the bare arm begins. In from it everything is the sleeve, whatever
    # hue a shadow on it has, and well out from it nothing is, however pale
    # the arm.
    bones = armature.data.bones
    for side in ("L_", "R_"):
        shoulder = np.array(bones[side + "Upperarm"].head_local)
        along = np.array(bones[side + "Forearm"].head_local) - shoulder
        along /= np.linalg.norm(along)
        out = ((centres - shoulder) @ along)[face_map]
        arm = is_kind("arm") & (x_map * shoulder[0] > 0.0) & (out > 0.0)
        if (arm & bare).sum() > 30 and (arm & (hue < lean)).sum() > 30:
            cuff = part(out[arm & bare], out[arm & (hue < lean)], 0.0, float(out[arm].max()))
            # (In from the shoulder too: the collarbone's part of the jersey.)
            plain |= is_kind("arm") & (x_map * shoulder[0] > 0.0) & (out < cuff - 0.012 * tall)
            plain &= ~(arm & (out > cuff + 0.03 * tall))
    # The collar: in the neckline the throat shows, and it hangs on the bones
    # of the chest as much as on those of the neck. There, in front and close
    # round the neck, a texel is the jersey only if it has no hue, shadow or
    # not. Behind, the jersey ends where the bones of the head begin.
    neck = np.array(bones["NeckTwist01"].head_local)
    y_map = centres[:, 1][face_map]
    close = np.hypot(x_map - neck[0], y_map - neck[1]) < abs(float(bones["L_Upperarm"].head_local[0]) - neck[0]) * 0.6
    throat = close & (y_map < neck[1]) & (z_map > neck[2] - 0.07 * tall)
    plain = np.where(throat & is_kind("neck", "head", "spine", "arm"), (hue < lean) & (luma >= deep), plain)
    plain &= ~(is_kind("head") & ~(throat & (z_map < neck[2] + 0.02 * tall)))
    keys = {
        # The chest and the back are the jersey, the darker of the hips and
        # thighs' plain texels the pants.
        "jersey": middle(is_kind("spine") & plain, (30, 95)),
        "pants": middle(is_kind("thigh", "hips") & plain & (spread < 0.13), (5, 45)),
    }
    for key, value in entry.get("keys", {}).items():
        keys[key] = None if value is None else np.array(value, dtype=float)
    print("KEYS %s skin %s %s" % (player_id, [round(float(c), 3) for c in skin],
                                  json.dumps({k: None if v is None else [round(float(c), 3) for c in v] for k, v in keys.items()})))
    jersey_luma = max(float(keys["jersey"] @ LUMA), 0.02)
    pants_luma = max(float(keys["pants"] @ LUMA), 0.02)

    kind = np.zeros((SIZE, SIZE), dtype=np.int8)
    # The jersey where nothing else can be.
    ratio = luma / jersey_luma
    kind[(may == JERSEY) & plain & (((ratio > dark) & (ratio < bright)) | (luma < deep) | is_kind("spine", "neck", "head"))] = JERSEY
    # Round the hips and the thighs a plain texel is the jersey or the pants,
    # whichever it is nearer in brightness...
    either = (may == (JERSEY | PANTS)) & plain
    split = math.sqrt(jersey_luma * pants_luma)
    kind[either & (luma >= split)] = JERSEY
    kind[either & (luma < split)] = PANTS
    # ...but the jersey hangs over the pants, never the other way round: seen
    # from any side there is one height where the one ends and the other
    # begins, and a dark crease above it is still the jersey.
    # (The underside of the hem lies in shadow and is as dark as the pants:
    # what faces down says nothing, and next to the line it is the hem.)
    under = up_map < -0.35
    waist = line(either & (luma >= split) & ~under, either & (luma < split) & ~under, knee, hip[2] + 0.2 * tall)
    # A hem is level, give or take: where one side of the body says otherwise
    # (the lit side of wide shorts is as bright as a shaded jersey), it is wrong.
    level = float(np.median(waist))
    waist = np.clip(waist, level - 0.03 * tall, level + 0.03 * tall)[sector_map]
    kind[either & (z_map > waist)] = JERSEY
    kind[either & (z_map <= waist)] = PANTS
    kind[either & under & (z_map > waist - 0.04 * tall)] = JERSEY
    # Below the hem of the pants what is plain is a sock.
    lower = (may == (PANTS | SOCKS)) & plain
    socks_from = float(given.get("socks_from", 0.0)) * tall
    kind[lower & (z_map > hem)] = PANTS
    kind[lower & (z_map <= hem) & (z_map >= socks_from) & neutral & (luma < 0.5)] = SOCKS
    # A sock goes on down into the shoe: what is dark and plain on the foot
    # above the ankle is still the sock.
    ankle = max(armature.data.bones["L_Foot"].head_local.z, armature.data.bones["R_Foot"].head_local.z)
    kind[is_kind("foot") & neutral & (luma < SOCK_DARK) & (z_map > max(ankle * 0.6, socks_from))] = SOCKS
    # Specks go with what is round them, among what a texel may be.
    counts = [box_sum(kind == bit, 3) for bit, _name in GARMENTS]
    most = np.stack([box_sum(kind == 0, 3)] + counts).argmax(0)
    smoothed = np.array([0] + [bit for bit, _name in GARMENTS], dtype=np.int8)[most]
    ok = ((((may & smoothed) > 0) | ((smoothed == SOCKS) & is_kind("foot") & (kind == SOCKS))) & plain) | (smoothed == 0)
    kind = np.where(ok, smoothed, kind)
    kind[~on_model] = 0
    # The edges of the jersey are evened out: a collar or a cuff is a line,
    # not a fringe.
    for _ in range(2):
        share = box_sum(kind == JERSEY, 4) / np.maximum(box_sum(on_model, 4), 1)
        kind[(kind == JERSEY) & (share < 0.4)] = 0
        kind[(kind == 0) & on_model & ((may & JERSEY) > 0) & (share > 0.6)] = JERSEY

    # What is repainted is kept as its shading only: how light it is beside
    # the garment as a whole, at 0.8 of full to leave room for highlights.
    colour = texture.copy()
    mask = np.zeros((SIZE, SIZE, 3))
    for channel, (bit, name) in enumerate(GARMENTS):
        fits = kind == bit
        if not fits.any():
            continue
        key_luma = max(float(np.percentile(luma[fits], 60)), 0.1)
        shading = luma[fits] / key_luma
        if bit == SOCKS:
            # Socks are made as good as black: what shading they have is noise.
            shading = 0.75 + 0.25 * np.clip(shading, 0.0, 1.5)
        colour[fits] = np.clip(shading * 0.8, 0.0, 1.0)[:, None]
        mask[:, :, channel] = fits
        print("PAINTED %s: %s is %.1f %% of the texture" % (player_id, name, fits.mean() * 100.0))
    return mask, colour


def shoot_previews(player_id, armature, body, colour_image, mask, shading):
    """Pictures of the model as painted and in a test kit, from four sides."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.film_transparent = False
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    tall = max(v.co.z for v in body.data.vertices)
    wide = max(abs(v.co.x) for v in body.data.vertices) * 2.0
    cam_data.ortho_scale = max(tall, wide) * 1.08
    scene.render.resolution_x = scene.render.resolution_y = 900

    test = shading.copy()
    for channel, tint in enumerate(((0.98, 0.8, 0.1), (0.15, 0.2, 0.45), (0.98, 0.8, 0.1))):
        on = mask[:, :, channel] > 0.5
        test[on] = np.clip(shading[on] / 0.8, 0.0, 1.2) * np.array(tint)
    test_image = new_image("TestKit", np.clip(test, 0.0, 1.0))
    material = body.data.materials[0]
    nodes = material.node_tree.nodes
    picture = next(n for n in nodes if n.type == "TEX_IMAGE" and n.image == colour_image)
    for label, image in (("painted", colour_image), ("kit", test_image)):
        picture.image = image
        nodes.active = picture
        for side, offset in (("front", (0.0, -6.0, 0.6)), ("quarter", (4.0, -4.5, 0.6)), ("side", (6.0, 0.0, 0.6)), ("back", (0.0, 6.0, 0.6))):
            aim = Vector((0.0, 0.0, tall * 0.5))
            cam.location = aim + Vector(offset)
            cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(preview_dir, "%s_%s_%s.png" % (player_id, label, side))
            bpy.ops.render.render(write_still=True)
    picture.image = colour_image
    bpy.data.objects.remove(cam)


def build(player_id, entry):
    armature, body = load(player_id, entry)
    found = textures_of(body)
    if found["colour"] is None:
        raise SystemExit("%s: the model has no colour texture" % player_id)
    texture = pixels_of(found["colour"], SIZE)
    painted = os.path.join(BLEND_DIR, "%s_mask_paint.png" % player_id)
    mask, colour = find_kit(player_id, entry, armature, body, texture)
    if os.path.exists(painted):
        mask = (pixels_of(bpy.data.images.load(painted), SIZE) > 0.5).astype(float)
        # A texel is one garment only.
        mask[:, :, 1] *= 1.0 - mask[:, :, 0]
        mask[:, :, 2] *= 1.0 - np.maximum(mask[:, :, 0], mask[:, :, 1])
        luma = texture @ LUMA
        colour = texture.copy()
        for channel in range(3):
            on = mask[:, :, channel] > 0.5
            if on.any():
                colour[on] = np.clip(luma[on] / max(float(np.median(luma[on])), 0.02) * 0.8, 0.0, 1.0)[:, None]
        print("MASK %s: painted by hand (%s)" % (player_id, painted))
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(BLEND_DIR, exist_ok=True)
    new_image("Mask_" + player_id, mask, os.path.join(OUT_DIR, "%s_mask.png" % player_id), colour=False)

    # The textures the model goes out with, at SIZE: the colour with the kit
    # as shading, the others as they came.
    material = body.data.materials[0]
    nodes = material.node_tree.nodes
    colour_image = new_image(player_id + "_colour", np.clip(colour, 0.0, 1.0))
    for node in nodes:
        if node.type != "TEX_IMAGE" or node.image is None:
            continue
        if node.image == found["colour"]:
            node.image = colour_image
        else:
            node.image.scale(SIZE, SIZE)
            node.image.pack()
    material.name = player_id

    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        shown = colour * 0.35
        shown += mask * 0.65
        new_image("MaskShown", np.clip(shown, 0.0, 1.0), os.path.join(preview_dir, "%s_mask.png" % player_id))
        shoot_previews(player_id, armature, body, colour_image, mask, colour)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, "%s.blend" % player_id), compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = armature
    out_path = os.path.join(OUT_DIR, "%s.glb" % player_id)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=False,
        export_image_format="JPEG",
        export_image_quality=92,
    )
    print("EXPORTED %s (%.1f MB)" % (out_path, os.path.getsize(out_path) / 1e6))


players = [options["only"]] if "only" in options else [p for p in CONFIG["players"] if CONFIG["players"][p].get("source")]
for player_id in players:
    if player_id not in CONFIG["players"] or not CONFIG["players"][player_id].get("source"):
        raise SystemExit("players.json: %s has no source" % player_id)
    build(player_id, CONFIG["players"][player_id])
