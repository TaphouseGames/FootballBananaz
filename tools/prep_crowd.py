"""Cuts whole Tripo characters into the parts the crowd is mixed from.

Run from the project root:

    blender -b --factory-startup --python tools/prep_crowd.py -- [preview=<dir>] [rig=<file.blend>]

It reads tools/crowd_parts.json (every fan with a `source`) and writes

    assets/stadium/crowd_kit.glb    the parts, posed sitting, as plain meshes
    assets/stadium/crowd_atlas.png  every fan's texture, one cell each
    assets/stadium/crowd_mask.png   what the crowd shader may repaint in it

To add a head or an outfit: add a fan to crowd_parts.json, generate its model
with Tripo, fill in `source`, and run this again. It always rebuilds the whole
kit.

What happens to a fan:

1. Clean-up as for any prop: one mesh, facing -Y, feet on the ground, one unit
   tall while it is worked on.
2. Its joints are found from its shape (crotch, waist, neck, shoulders, ...);
   `joints` in the JSON overrides any of them.
3. All fans of a gender are bent onto ONE skeleton, the average of theirs with
   the arms straight out (a T-pose). After that their necks, waists, shoulders
   and hips are in the same places.
4. The fan is cut at the neck and the waist into a head, a torso (the outfit:
   torso and arms) and legs. The cut edges are brought to the same size for
   the whole gender; head and torso are closed flat where they meet, and the
   legs get a top that goes up inside any hem, so any head fits any torso and
   any torso any legs.
5. Its texture goes into its cell of the atlas, with skin and the cloth or
   hair that may be repainted reduced to their shading (the shader gives them
   a colour per fan), and the mask says which is which:
       mask R  cloth on a torso or legs, hair on a head: takes the part's tint
       mask G  skin: takes the fan's skin tone
6. Each part is thinned to its triangle budget per level of detail and posed
   sitting. The crowd is drawn with MultiMeshes, which cannot have skeletons,
   so the pose is baked in and the crowd shader does the moving.

The meshes, with the seat at y = 0 in Godot and the fan facing +Z:

    Head<G><n>, Torso<G><n>, Legs<G><n>   full detail      (G: M or F)
    ...Mid                                the middle level
    Torso<G><n>Sign[Mid]                  arms up, for a fan with a sign
    Far<G>, Far<G>Sign                    one whole fan, the plainest level

UV is the atlas. The second UV set, as Godot reads it, is for the shader:

    UV2.x  0.5 on the body; towards 1 the more a vertex belongs to the left
           arm, towards 0 the more it belongs to the right one
    UV2.y  how much it belongs to an arm that is held up (a ...Sign torso),
           plus 2 on a head and 4 on legs, which is how the shader knows what
           the part's tint is: shirt, hair or trousers

Each object's custom properties (glTF "extras") say what it is (`kind`,
`gender`, `index`, `tier`, `sign`) and, in Godot's axes and the mesh's units,
`shoulder` (the left one: where the arms turn) and `hand` (the left hand of a
fan with a sign).

With `preview`, pictures are saved there: every fan's joints and mask, the
atlas, and every head on every torso. With `rig`, the full-detail parts are
also saved standing in the T-pose with the shared skeleton and their weights.
"""

import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "stadium")
# Triangles a fan is cut down to before anything else is done with it.
WORK_TRIS = 40000
# The texture is looked at with this many pixels a side.
WORK_TEXTURE = 1024
TIERS = (("", "near"), ("Mid", "mid"), ("Far", "far"))
PART_IDS = {"torso": 0, "head": 1, "legs": 2}
# In the texture the hands are a part of their own: they are bare, so nothing
# on them is the shirt, however near its colour a shaded knuckle comes.
HANDS = 3
# How far below the hip joints the seat is, with the height = 1.
SEAT_DROP = 0.055
# The torso is cut this far below the waist, so its hem hangs over the legs.
HEM = 0.025
# How far the legs' top goes up inside the torso, and how much narrower its
# far end is.
STUB = 0.04
STUB_TAPER = 0.75
# The hem is this much wider than the waist, the legs' top this much narrower.
HEM_FLARE = 1.05
WAIST_TUCK = 0.95
# How steeply the cut under the head rises away from the neck, and how far up
# from the neck an open edge is still part of that cut.
CUP_SLOPE = 0.6
CUP_REACH = 0.3
# How far below the neck a beard may hang and still go with the head.
BEARD_REACH = 0.12
# How much less a face is thinned out than the rest of a head (0: no less).
KEEP_STRENGTH = 0.7
# Height over which a cut edge is eased to the gender's size.
SEAM_FALLOFF = 0.05
# Degrees the arms hang below level, and are held above it with a sign.
ARMS_DOWN = 76.0
ARMS_UP = 72.0

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
options = dict(arg.split("=", 1) for arg in argv)
preview_dir = options.get("preview")
rig_path = options.get("rig")
unknown = [key for key in options if key not in ("preview", "rig")]
if unknown:
    raise SystemExit("usage: prep_crowd.py -- [preview=<dir>] [rig=<file.blend>]  (unknown: %s)" % ", ".join(unknown))

with open(os.path.join(ROOT, "tools", "crowd_parts.json"), encoding="utf-8") as handle:
    CONFIG = json.load(handle)
BUDGETS = CONFIG["budgets"]
CELL = int(CONFIG.get("atlas_cell", 512))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# --- Small tools ----------------------------------------------------------------------

def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def copy_of(obj, name):
    twin = obj.copy()
    twin.data = obj.data.copy()
    twin.name = name
    twin.data.name = name
    scene.collection.objects.link(twin)
    return twin


def remove(obj):
    mesh = obj.data
    bpy.data.objects.remove(obj)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def coords(mesh):
    out = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", out)
    return out.reshape(-1, 3)


def set_coords(mesh, points):
    mesh.vertices.foreach_set("co", np.ascontiguousarray(points, dtype=np.float64).ravel())
    mesh.update()


def triangulate(mesh, weld=False):
    """Makes every face a triangle. `weld` also joins vertices that lie on top
    of each other: an imported model comes apart along its UV seams, and one
    in pieces cannot be thinned out."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    if weld:
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def thin(obj, tris, keep=None):
    """Cuts `obj` down to about `tris` triangles and returns it. `keep`
    (points -> 0..1 per vertex) marks what should lose the fewest: a face, on
    a head whose curls would otherwise get all the triangles."""
    have = len(obj.data.polygons)
    if have <= tris:
        return obj
    if keep is not None:
        # The modifier thins by a vertex's weight: the marked part gets little.
        trial = copy_of(obj, obj.name + "_Trial")
        weights = 1.0 - KEEP_STRENGTH * keep(coords(trial.data))
        group = trial.vertex_groups.new(name="Thin")
        for index, weight in enumerate(weights):
            group.add([index], float(weight), "REPLACE")
        select_only(trial)
        modifier = trial.modifiers.new("Thin", "DECIMATE")
        modifier.ratio = tris / have
        modifier.vertex_group = "Thin"
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        trial.vertex_groups.clear()
        print("THINNED %s with its face spared: %d -> %d (asked for %d)" % (obj.name, have, len(trial.data.polygons), tris))
        if len(trial.data.polygons) <= tris * 1.25:
            name = obj.name
            remove(obj)
            trial.name = name
            return trial
        # It did not come down far enough that way: thin it evenly instead.
        remove(trial)
    select_only(obj)
    modifier = obj.modifiers.new("Thin", "DECIMATE")
    modifier.ratio = tris / have
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def smoothstep(lo, hi, x):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def spans(xs, gap=0.02):
    """The stretches of x that a slice of the model covers: (from, to, points)."""
    xs = np.sort(xs)
    out = []
    start = 0
    for i in range(1, len(xs) + 1):
        if i == len(xs) or xs[i] - xs[i - 1] > gap:
            out.append((xs[start], xs[i - 1], i - start))
            start = i
    return out


def clusters(pts, cell=0.03):
    """Groups of points that touch (through neighbouring cells of a grid)."""
    cells = {}
    for i, key in enumerate(map(tuple, np.floor(pts / cell).astype(int))):
        cells.setdefault(key, []).append(i)
    seen = set()
    groups = []
    for key in cells:
        if key in seen:
            continue
        seen.add(key)
        stack = [key]
        members = []
        while stack:
            cx, cy, cz = stack.pop()
            members.extend(cells[(cx, cy, cz)])
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for dz in (-1, 0, 1):
                        other = (cx + dx, cy + dy, cz + dz)
                        if other in cells and other not in seen:
                            seen.add(other)
                            stack.append(other)
        groups.append(pts[members])
    return groups


def rot_x(degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]])


def rot_y(degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def affine(linear, offset):
    out = np.eye(4)
    out[:3, :3] = linear
    out[:3, 3] = offset
    return out


def about(pivot, linear):
    """`linear` applied about `pivot`."""
    pivot = np.asarray(pivot, dtype=float)
    return affine(linear, pivot - linear @ pivot)


def swing(a, b):
    """The smallest turn that takes direction `a` to direction `b`."""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(a @ b)
    if c < -0.9999:
        return rot_y(180.0)
    k = np.array([[0.0, -v[2], v[1]], [v[2], 0.0, -v[0]], [-v[1], v[0], 0.0]])
    return np.eye(3) + k + k @ k / (1.0 + c)


def surface_points(mesh, count=60000):
    """Points spread evenly over the surface of a triangle mesh."""
    points = coords(mesh)
    loops = np.empty(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", loops)
    a, b, c = (points[loops.reshape(-1, 3)[:, i]] for i in range(3))
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1)
    rng = np.random.default_rng(7)
    picked = rng.choice(len(area), size=count, p=area / area.sum())
    u, v = rng.random(count), rng.random(count)
    flip = u + v > 1.0
    u[flip], v[flip] = 1.0 - u[flip], 1.0 - v[flip]
    return a[picked] + (b[picked] - a[picked]) * u[:, None] + (c[picked] - a[picked]) * v[:, None]


def skin(points, weights, matrices):
    """Linear blend skinning: weights (V, B), matrices (B, 4, 4)."""
    out = np.zeros_like(points)
    for b, matrix in enumerate(matrices):
        w = weights[:, b]
        if not w.any():
            continue
        out += w[:, None] * (points @ matrix[:3, :3].T + matrix[:3, 3])
    return out


# --- Loading a fan --------------------------------------------------------------------

def load_fan(fan_id, entry):
    """The fan as one triangle mesh at the origin, facing -Y, one unit tall,
    and its texture as an array (rows from the bottom, sRGB values)."""
    path = os.path.join(ROOT, entry["source"])
    old_objects = set(o.name for o in bpy.data.objects)
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o.name not in old_objects]
    meshes = [o for o in new if o.type == "MESH"]
    if entry.get("mesh"):
        meshes = [o for o in meshes if o.name == entry["mesh"]]
    if not meshes:
        raise SystemExit("%s: no mesh in %s" % (fan_id, entry["source"]))
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "Fan_" + fan_id
    mesh = obj.data
    world = obj.matrix_world.copy()
    obj.modifiers.clear()
    obj.vertex_groups.clear()
    obj.parent = None
    mesh.transform(world)
    obj.matrix_world.identity()
    for o in new:
        if o.name in bpy.data.objects and o != obj:
            bpy.data.objects.remove(o)

    image = None
    for material in mesh.materials:
        if material is None or material.node_tree is None:
            continue
        nodes = material.node_tree.nodes
        shader = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
        if shader is not None and shader.inputs["Base Color"].links:
            source = shader.inputs["Base Color"].links[0].from_node
            if source.type == "TEX_IMAGE" and source.image is not None:
                image = source.image
        if image is None:
            image = next((n.image for n in nodes if n.type == "TEX_IMAGE" and n.image is not None), None)
        if image is not None:
            break
    if image is None:
        raise SystemExit("%s: the model has no texture" % fan_id)
    if len([m for m in mesh.materials if m is not None]) > 1:
        print("WARNING: %s has several materials; only the texture %s is used" % (fan_id, image.name))
    image.scale(WORK_TEXTURE, WORK_TEXTURE)
    pixels = np.empty(WORK_TEXTURE * WORK_TEXTURE * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    texture = pixels.reshape(WORK_TEXTURE, WORK_TEXTURE, 4)[:, :, :3].astype(np.float64)
    mesh.materials.clear()

    triangulate(mesh, weld=True)
    obj = thin(obj, WORK_TRIS)
    mesh = obj.data
    triangulate(mesh)
    points = coords(mesh)
    yaw = float(entry.get("yaw", 0.0))
    if yaw != 0.0:
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        points = points @ np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]]).T
    lo, hi = points.min(0), points.max(0)
    points = (points - np.array([(lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, lo[2]])) / (hi[2] - lo[2])
    set_coords(mesh, points)
    print("LOADED %s: %d triangles, texture %s" % (fan_id, len(mesh.polygons), image.name))
    return obj, texture


# --- Where the joints are -------------------------------------------------------------

def find_joints(fan_id, points, overrides):
    """The fan's joints, with the height = 1: name -> np.array, and the half
    width of its waist."""
    def band(z, half=0.0075):
        return points[np.abs(points[:, 2] - z) < half]

    # The crotch: going up from the shoes, the first height at which the model
    # covers the point midway between the feet.
    low = points[(points[:, 2] > 0.02) & (points[:, 2] < 0.08)]
    feet = sorted(spans(low[:, 0]), key=lambda s: -s[2])[:2]
    mid_x = sum((s[0] + s[1]) * 0.5 for s in feet) / 2.0 if len(feet) == 2 else 0.0

    def middle_span(z):
        for s in spans(band(z)[:, 0]):
            if s[0] < mid_x - 0.005 and s[1] > mid_x + 0.005:
                return s
        return None

    crotch = None
    apart = False
    z = 0.05
    while z < 0.7:
        if middle_span(z) is None:
            apart = True
        elif apart and middle_span(z + 0.015) is not None:
            crotch = z
            break
        z += 0.01
    if crotch is None:
        print("WARNING: %s: the legs were not found apart; guessing the crotch" % fan_id)
        crotch = 0.45

    # The waist is where the body is narrowest above the hips.
    half_width = None
    centre_x = mid_x
    z = crotch + 0.07
    while z < crotch + 0.2:
        s = middle_span(z)
        if s is not None and (half_width is None or (s[1] - s[0]) * 0.5 < half_width):
            half_width = (s[1] - s[0]) * 0.5
            centre_x = (s[0] + s[1]) * 0.5
        z += 0.01
    if half_width is None:
        half_width = 0.09
    waist_z = crotch + 0.09

    def spine_point(z):
        part = band(z)
        part = part[np.abs(part[:, 0] - centre_x) < half_width * 1.2]
        y = float((part[:, 1].min() + part[:, 1].max()) * 0.5) if len(part) else 0.0
        return np.array([centre_x, y, z])

    joints = {}
    # Arms: what sticks out past the body to each side, below the head.
    for side, sign in (("L", 1.0), ("R", -1.0)):
        out = (points[:, 0] - centre_x) * sign
        candidates = points[(out > half_width * 1.2) & (points[:, 2] > crotch + 0.05)]
        best = None
        best_reach = 0.12
        for group in clusters(candidates) if len(candidates) else []:
            reach = float(np.linalg.norm(group.max(0) - group.min(0)))
            if len(group) > 40 and group[:, 2].mean() < 0.8 and reach > best_reach:
                best, best_reach = group, reach
        if best is None:
            print("WARNING: %s: no arm found on side %s; guessing" % (fan_id, side))
            shoulder = np.array([centre_x + sign * half_width * 1.2, 0.0, 0.66])
            tip = shoulder + np.array([sign * 0.3, 0.0, 0.0])
        else:
            centre = best.mean(0)
            axis = np.linalg.svd(best - centre, full_matrices=False)[2][0]
            along = (best - centre) @ axis
            ends = [centre + axis * np.percentile(along, 2), centre + axis * np.percentile(along, 99)]
            # The hand is the end further from the base of the neck.
            ends.sort(key=lambda e: np.linalg.norm(e - np.array([centre_x, centre[1], 0.8])))
            shoulder, tip = ends
            shoulder = shoulder - (tip - shoulder) / np.linalg.norm(tip - shoulder) * 0.01
        joints["shoulder." + side] = shoulder
        joints["elbow." + side] = shoulder + (tip - shoulder) * 0.45
        joints["wrist." + side] = shoulder + (tip - shoulder) * 0.8
        joints["tip." + side] = tip

    # The neck is where the middle of the body is narrowest above the shoulders.
    shoulder_z = (joints["shoulder.L"][2] + joints["shoulder.R"][2]) * 0.5
    heights = np.arange(shoulder_z + 0.03, 0.93, 0.005)
    widths = []
    for z in heights:
        part = band(z, 0.005)
        widths.append(np.percentile(part[:, 0], 98) - np.percentile(part[:, 0], 2) if len(part) > 8 else 9.0)
    widths = np.convolve(widths, np.ones(3) / 3.0, mode="same") if len(widths) > 3 else np.array(widths)
    # Going up, the narrowest place before the head widens again (the crown
    # of the head is narrower still, and is not the neck).
    neck_z = shoulder_z + 0.06
    narrowest = 9.0
    for z, width in zip(heights, widths):
        if width < narrowest:
            narrowest, neck_z = width, float(z)
        elif width > narrowest * 1.25:
            break

    joints["crotch"] = spine_point(crotch + 0.03)
    joints["waist"] = spine_point(waist_z)
    joints["neck"] = spine_point(neck_z)
    joints["chest"] = spine_point(waist_z + 0.55 * (neck_z - waist_z))
    joints["top"] = np.array([joints["neck"][0], joints["neck"][1], 1.0])

    for side, sign in (("L", 1.0), ("R", -1.0)):
        def leg_point(z):
            part = band(z, 0.01)
            part = part[(part[:, 0] - mid_x) * sign > 0.0]
            if len(part) < 4:
                return np.array([mid_x + sign * half_width * 0.6, 0.0, z])
            return np.array([(part[:, 0].min() + part[:, 0].max()) * 0.5, (part[:, 1].min() + part[:, 1].max()) * 0.5, z])
        hip = leg_point(crotch - 0.02)
        hip[2] = crotch + 0.03
        ankle = leg_point(0.1)
        joints["hip." + side] = hip
        joints["knee." + side] = leg_point((hip[2] + ankle[2]) * 0.5)
        joints["ankle." + side] = ankle
        joints["toe." + side] = ankle + np.array([0.0, -0.1, -0.07])

    for key, value in overrides.items():
        if key not in joints:
            raise SystemExit("crowd_parts.json: %s: unknown joint %s (have %s)" % (fan_id, key, ", ".join(sorted(joints))))
        joints[key] = np.array(value, dtype=float)
    print("JOINTS %s %s" % (fan_id, json.dumps({k: [round(float(c), 3) for c in v] for k, v in sorted(joints.items())})))
    print("WAIST %s half width %.3f" % (fan_id, half_width))
    return joints, half_width


# The bones: name, the joint at its head, the joint at its tail, its radius
# (limbs: with the height = 1; the trunk's is set from the waist's half width).
LIMBS = []
for _side in ("L", "R"):
    LIMBS += [
        ("UpperArm." + _side, "shoulder." + _side, "elbow." + _side, 0.035),
        ("Forearm." + _side, "elbow." + _side, "wrist." + _side, 0.03),
        ("Hand." + _side, "wrist." + _side, "tip." + _side, 0.035),
        ("Thigh." + _side, "hip." + _side, "knee." + _side, 0.05),
        ("Shin." + _side, "knee." + _side, "ankle." + _side, 0.04),
        ("Foot." + _side, "ankle." + _side, "toe." + _side, 0.045),
    ]
TRUNK = [("Hips", "crotch", "waist"), ("Spine", "waist", "chest"), ("Chest", "chest", "neck"), ("Head", "neck", "top")]
BONES = [b[0] for b in TRUNK] + [b[0] for b in LIMBS]
ARM_SIDE = np.array([0.0 if not b.split(".")[0] in ("UpperArm", "Forearm", "Hand") else (1.0 if b.endswith(".L") else -1.0) for b in BONES])
IS_ARM = ARM_SIDE != 0.0
IS_LEG = np.array([b.split(".")[0] in ("Thigh", "Shin", "Foot") for b in BONES])


def segment_distance(points, head, tail):
    along = tail - head
    t = np.clip(((points - head) @ along) / max(float(along @ along), 1e-9), 0.0, 1.0)
    return np.linalg.norm(points - (head + t[:, None] * along), axis=1)


def bone_weights(points, joints, half_width, head_radius):
    """How much each vertex belongs to each of BONES (V, B). A vertex belongs
    to a limb by how far it is outside a tube round the bone, and to the trunk
    by how far it is outside a fatter tube up the middle; the trunk's share is
    then split by height between hips, spine, chest and head."""
    trunk = np.full(len(points), 9.0)
    for name, a, b in TRUNK:
        radius = head_radius if name == "Head" else half_width * 0.85
        head = joints[a].copy()
        if name == "Hips":
            # So that the round end of the tube stops at the crotch.
            head[2] += radius * 0.5
        trunk = np.minimum(trunk, np.maximum(segment_distance(points, head, joints[b]) - radius, 0.0))
    outside = [trunk]
    # The limbs of a broad fan are thick too.
    thick = half_width / 0.1
    for name, a, b, radius in LIMBS:
        outside.append(np.maximum(segment_distance(points, joints[a], joints[b]) - radius * thick, 0.0))
    raw = np.stack([1.0 / (d + 0.015) ** 4 for d in outside], axis=1)
    raw[raw < raw.max(1, keepdims=True) * 0.02] = 0.0
    raw /= raw.sum(1, keepdims=True)

    z = points[:, 2]
    over_waist = smoothstep(joints["waist"][2] - 0.02, joints["waist"][2] + 0.02, z)
    over_chest = smoothstep(joints["chest"][2] - 0.03, joints["chest"][2] + 0.03, z)
    over_neck = smoothstep(joints["neck"][2] - 0.012, joints["neck"][2] + 0.012, z)
    weights = np.zeros((len(points), len(BONES)))
    weights[:, 0] = raw[:, 0] * (1.0 - over_waist)
    weights[:, 1] = raw[:, 0] * over_waist * (1.0 - over_chest)
    weights[:, 2] = raw[:, 0] * over_chest * (1.0 - over_neck)
    weights[:, 3] = raw[:, 0] * over_neck
    weights[:, 4:] = raw[:, 1:]
    return weights


def head_radius_of(points, joints):
    # Well up the head: lower down there may be shoulders beside it.
    above = points[points[:, 2] > joints["neck"][2] + 0.35 * (points[:, 2].max() - joints["neck"][2])]
    if len(above) < 10:
        return 0.1
    return float(np.percentile(np.abs(above[:, 0] - joints["neck"][0]), 95))


def reference_joints(all_joints):
    """One skeleton for a gender: the average of its fans', the same on both
    sides, with the arms straight out."""
    mean = {key: np.mean([j[key] for j in all_joints], axis=0) for key in all_joints[0]}
    ref = {}
    for key in ("crotch", "waist", "chest", "neck", "top"):
        ref[key] = np.array([0.0, mean[key][1], mean[key][2]])
    for key in ("shoulder", "hip", "knee", "ankle", "toe"):
        left, right = mean[key + ".L"], mean[key + ".R"]
        both = np.array([(left[0] - right[0]) * 0.5, (left[1] + right[1]) * 0.5, (left[2] + right[2]) * 0.5])
        ref[key + ".L"] = both
        ref[key + ".R"] = both * np.array([-1.0, 1.0, 1.0])
    for side, sign in (("L", 1.0), ("R", -1.0)):
        at = ref["shoulder." + side].copy()
        for a, b in (("shoulder", "elbow"), ("elbow", "wrist"), ("wrist", "tip")):
            length = np.mean([np.linalg.norm(j[b + "." + s] - j[a + "." + s]) for j in all_joints for s in ("L", "R")])
            at = at + np.array([sign * length, 0.0, 0.0])
            ref[b + "." + side] = at.copy()
    return ref


def conform(points, joints, half_width, ref, ref_half_width):
    """The fan's vertices bent onto the reference skeleton."""
    weights = bone_weights(points, joints, half_width, head_radius_of(points, joints))
    matrices = []
    wide = ref_half_width / half_width
    for name, a, b in TRUNK:
        if name == "Head":
            # A head keeps its size and its shape; it only moves to its place.
            matrices.append(affine(np.eye(3), ref[a] - joints[a]))
            continue
        tall = (ref[b][2] - ref[a][2]) / max(joints[b][2] - joints[a][2], 1e-6)
        linear = np.diag([wide, wide, tall])
        matrices.append(affine(linear, ref[a] - linear @ joints[a]))
    for name, a, b, _radius in LIMBS:
        way = joints[b] - joints[a]
        ref_way = ref[b] - ref[a]
        unit = way / np.linalg.norm(way)
        stretch = np.eye(3) + (np.linalg.norm(ref_way) / np.linalg.norm(way) - 1.0) * np.outer(unit, unit)
        linear = swing(way, ref_way) @ stretch
        matrices.append(affine(linear, ref[a] - linear @ joints[a]))
    return skin(points, weights, matrices)


# --- Texture, atlas and mask ----------------------------------------------------------

def face_arrays(mesh):
    """Per triangle: the vertex indices (F, 3) and the UVs (F, 3, 2)."""
    loops = np.empty(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", loops)
    uvs = np.empty(len(mesh.loops) * 2)
    mesh.uv_layers.active.data.foreach_get("uv", uvs)
    return loops.reshape(-1, 3), uvs.reshape(-1, 3, 2)


def region_map(uvs, parts, size):
    """Which part each pixel of the texture belongs to (-1: none)."""
    out = np.full((size, size), -1, dtype=np.int8)
    px = np.mod(uvs, 1.0) * size
    lo = np.clip(np.floor(px.min(1)).astype(int), 0, size - 1)
    hi = np.clip(np.floor(px.max(1)).astype(int), 0, size - 1)
    for f in range(len(px)):
        x0, y0 = lo[f]
        x1, y1 = hi[f]
        if x1 - x0 < 2 and y1 - y0 < 2:
            out[y0:y1 + 1, x0:x1 + 1] = parts[f]
            continue
        a, b, c = px[f]
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / d
        w1 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / d
        inside = (w0 >= -0.05) & (w1 >= -0.05) & (w0 + w1 <= 1.05)
        out[y0:y1 + 1, x0:x1 + 1][inside] = parts[f]
    # Spread a few pixels past the edges of the islands.
    for _ in range(4):
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            moved = np.roll(out, (dy, dx), axis=(0, 1))
            empty = out < 0
            out[empty] = moved[empty]
    return out


def sample_key(texture, uvs, faces):
    """The middle colour of the texture under the triangles `faces`."""
    if int(faces.sum()) < 5:
        return None
    centre = np.mod(uvs[faces].mean(1), 1.0)
    size = texture.shape[0]
    x = np.clip((centre[:, 0] * size).astype(int), 0, size - 1)
    y = np.clip((centre[:, 1] * size).astype(int), 0, size - 1)
    return np.median(texture[y, x], axis=0)


LUMA = np.array([0.3, 0.59, 0.11])


def chroma(colour):
    return colour / (colour.sum(-1, keepdims=True) + 1e-4)


def find_keys(fan_id, texture, uvs, centres, normals, parts, ref, half_width, overrides):
    """The colours of the fan's skin, hair, shirt and trousers."""
    z = centres[:, 2]
    neck, waist, crotch = ref["neck"][2], ref["waist"][2], ref["crotch"][2] - 0.03
    head = parts == PART_IDS["head"]
    top = z[head].max() if head.any() else 1.0
    tall = top - neck
    keys = {}
    # The hands are bare whatever the fan wears; a face has a mouth, eyes and
    # perhaps a moustache in the middle of it.
    keys["skin"] = sample_key(texture, uvs, parts == HANDS)
    keys["hair"] = sample_key(texture, uvs, head & (z > neck + 0.85 * tall))
    keys["shirt"] = sample_key(texture, uvs, (parts == PART_IDS["torso"]) & shirt_faces(centres, normals, ref, half_width))
    keys["pants"] = sample_key(texture, uvs, (parts == PART_IDS["legs"]) & (z > crotch - 0.02) & (z < waist - 0.01))
    if keys["skin"] is not None and keys["hair"] is not None:
        ratio = (keys["hair"] @ LUMA) / max(keys["skin"] @ LUMA, 1e-3)
        if np.linalg.norm(chroma(keys["hair"]) - chroma(keys["skin"])) < 0.03 and 0.75 < ratio < 1.3:
            keys["hair"] = None
    for key, value in overrides.items():
        if key not in keys:
            raise SystemExit("crowd_parts.json: %s: unknown key colour %s" % (fan_id, key))
        keys[key] = None if value is None else np.array(value, dtype=float)
    print("KEYS %s %s" % (fan_id, json.dumps({k: None if v is None else [round(float(c), 3) for c in v] for k, v in keys.items()})))
    return keys


def shirt_faces(centres, normals, ref, half_width):
    """The triangles in the middle of the back: a chest may have a print on
    it, which is not the colour of the shirt."""
    z = centres[:, 2]
    neck, waist = ref["neck"][2], ref["waist"][2]
    return ((normals[:, 1] > 0.6) & (np.abs(centres[:, 0]) < half_width * 0.6)
            & (z > waist + 0.3 * (neck - waist)) & (z < waist + 0.75 * (neck - waist)))


def colour_test(fan_id, mesh, texture, ref, half_width, name):
    """uv -> whether the texture there is the colour of the fan's shirt
    (`name` "shirt") or of its hair ("hair")."""
    entry = fans[fan_id]
    given = entry.get("keys", {})
    if name in given:
        key = given[name]
    else:
        at = coords(mesh)
        tris, uvs = face_arrays(mesh)
        centres = at[tris].mean(1)
        if name == "shirt":
            normal = np.cross(at[tris[:, 1]] - at[tris[:, 0]], at[tris[:, 2]] - at[tris[:, 0]])
            normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-12)
            key = sample_key(texture, uvs, shirt_faces(centres, normal, ref, half_width))
        else:
            neck = ref["neck"][2]
            key = sample_key(texture, uvs, centres[:, 2] > neck + 0.85 * (at[:, 2].max() - neck))
    if key is None:
        return lambda uv: False
    key = np.array(key, dtype=float)
    options = entry.get("options", {})
    near = float(options.get("chroma", 0.07))
    dark, bright = options.get("luma", [0.4, 1.8])
    key_tone = chroma(key)
    key_luma = max(float(key @ LUMA), 0.02)
    if key_luma < 0.12:
        near /= 0.4
    size = texture.shape[0]

    def test(uv):
        colour = texture[min(int((uv[1] % 1.0) * size), size - 1), min(int((uv[0] % 1.0) * size), size - 1)]
        return bool(np.linalg.norm(chroma(colour) - key_tone) < near and dark < (colour @ LUMA) / key_luma < bright)
    return test


def paint_cell(texture, regions, keys, options):
    """The fan's cell of the atlas (RGB) and of the mask (R tint, G skin)."""
    near = float(options.get("chroma", 0.07))
    dark, bright = options.get("luma", [0.4, 1.8])
    luma = texture @ LUMA
    tone = chroma(texture)
    kind = np.zeros(texture.shape[:2], dtype=np.int8)
    best = np.full(texture.shape[:2], 9.0)
    colour = texture.copy()
    per_part = {
        PART_IDS["head"]: (("skin", 1), ("hair", 2)),
        PART_IDS["torso"]: (("skin", 1), ("shirt", 2)),
        PART_IDS["legs"]: (("skin", 1), ("pants", 2)),
        HANDS: (("skin", 1),),
    }
    for part, wanted in per_part.items():
        here = regions == part
        for name, value in wanted:
            key = keys.get(name)
            if key is None:
                continue
            key_luma = max(float(key @ LUMA), 0.02)
            off = np.linalg.norm(tone - chroma(key), axis=-1)
            # A dark colour has no hue to speak of: go by how dark it is.
            if key_luma < 0.12:
                off = off * 0.4
            ratio = luma / key_luma
            fits = here & (off < near) & (ratio > dark) & (ratio < bright) & (off < best)
            best[fits] = off[fits]
            kind[fits] = value
            if value == 1:
                colour[fits] = np.clip(texture[fits] / np.maximum(key, 0.02) * 0.8, 0.0, 1.0)
            else:
                colour[fits] = np.clip(ratio[fits] * 0.8, 0.0, 1.0)[:, None]
    mask = np.zeros(texture.shape)
    mask[:, :, 0] = kind == 2
    mask[:, :, 1] = kind == 1
    step = texture.shape[0] // CELL
    if step > 1:
        colour = colour.reshape(CELL, step, CELL, step, 3).mean((1, 3))
        mask = mask.reshape(CELL, step, CELL, step, 3).mean((1, 3))
    return colour, mask


def save_image(name, array, path):
    """Saves (rows from the bottom, values 0..1, 3 channels) as a PNG."""
    height, width = array.shape[:2]
    image = bpy.data.images.new(name, width, height, alpha=False)
    pixels = np.ones((height, width, 4), dtype=np.float32)
    pixels[:, :, :3] = array
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    return image


# --- Cutting, seams, posing -----------------------------------------------------------

def ring_of(mesh, z):
    """Middle and half size, in x and y, of the open edge of `mesh` at height z."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    found = [v.co.copy() for e in bm.edges if e.is_boundary and all(abs(v.co.z - z) < 0.004 for v in e.verts) for v in e.verts]
    bm.free()
    if len(found) < 6:
        return None
    xy = np.array([(c.x, c.y) for c in found])
    lo, hi = xy.min(0), xy.max(0)
    return np.concatenate([(lo + hi) * 0.5, (hi - lo) * 0.5])


def head_faces(bm, neck, axis, core):
    """The faces of the head. The head is cut off like a cup: flat across the
    neck (within `core` of `axis`, the middle of the neck), and rising from
    there outwards. On a stocky figure the tops of the shoulders are higher
    than the chin, and a flat cut would give them to the head."""
    found = set()
    for face in bm.faces:
        centre = face.calc_center_median()
        out = math.hypot(centre.x - axis[0], (centre.y - axis[1]) * 0.8)
        if centre.z > neck + CUP_SLOPE * max(out - core, 0.0):
            found.add(face)
    return found


def cut(obj, name, kind, neck, waist, axis, core, is_cloth, is_hair):
    """The head, the torso or the legs of `obj`, as a copy. `is_cloth` and
    `is_hair` (uv -> bool) say where the texture is the colour of the shirt
    and of the hair."""
    part = copy_of(obj, name)
    bm = bmesh.new()
    bm.from_mesh(part.data)

    def slice_at(z, drop_under=None):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                               plane_co=(0.0, 0.0, z), plane_no=(0.0, 0.0, 1.0),
                               clear_inner=drop_under is True, clear_outer=drop_under is False)

    if kind == "legs":
        slice_at(waist, False)
    else:
        slice_at(neck)
        head = head_faces(bm, neck, axis, core)
        # A collar or a hood stands up round the head, and belongs to the
        # outfit: whatever is the shirt's colour and joined to the shirt.
        uv_layer = bm.loops.layers.uv.active
        limit = neck + 0.6 * (max(v.co.z for v in bm.verts) - neck)

        def middle(face):
            return sum((loop[uv_layer].uv for loop in face.loops), Vector((0.0, 0.0))) / len(face.loops)

        def cloth(face):
            return is_cloth(middle(face))

        stack = [f for f in bm.faces if f not in head and f.calc_center_median().z > neck - 0.06 and cloth(f)]
        while stack:
            face = stack.pop()
            for edge in face.edges:
                for other in edge.link_faces:
                    if other in head and other.calc_center_median().z < limit and cloth(other):
                        head.discard(other)
                        stack.append(other)
        # A long beard hangs down over the chest, and belongs to the head:
        # whatever is the hair's colour and joined to the head.
        floor = neck - BEARD_REACH
        stack = [f for f in head if f.calc_center_median().z < neck + 0.1 and is_hair(middle(f))]
        while stack:
            face = stack.pop()
            for edge in face.edges:
                for other in edge.link_faces:
                    if other not in head and other.calc_center_median().z > floor and is_hair(middle(other)):
                        head.add(other)
                        stack.append(other)
        gone = [f for f in bm.faces if (f in head) != (kind == "head")]
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        if kind == "torso":
            slice_at(waist - HEM, True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(part.data)
    bm.free()
    part.data.update()
    return part


def ease_seam(mesh, z, ring, standard, grow):
    """Brings the cut edge at height z to the gender's size (times `grow`),
    easing the change in over SEAM_FALLOFF."""
    points = coords(mesh)
    near = np.clip(1.0 - np.abs(points[:, 2] - z) / SEAM_FALLOFF, 0.0, 1.0)
    near = near * near * (3.0 - 2.0 * near)
    # Only the neck or the waist itself, not a shoulder that is as high.
    offset = points[:, :2] - ring[:2]
    near *= (np.abs(offset) < ring[2:] * 2.2).all(1)
    scale = standard[2:] * grow / np.maximum(ring[2:], 1e-4)
    points[:, :2] += near[:, None] * ((standard[:2] - ring[:2]) + offset * (scale - 1.0))
    set_coords(mesh, points)


def close_seam(mesh, z, stub, taper, reach=0.0):
    """Flattens the open edge near height z onto it, optionally pulls a stub
    out of it (`stub` up or down, narrowing to `taper`), and closes the end.
    With `reach`, open edges up to that far above z are closed with it."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.active
    under = BEARD_REACH + 0.02 if reach > 0.0 else 0.03
    edges = [e for e in bm.edges if e.is_boundary and all(-under < v.co.z - z < max(reach, 0.03) for v in e.verts)]
    if not edges:
        bm.free()
        print("WARNING: %s has no open edge at z = %.3f" % (mesh.name, z))
        return
    ring = {v for e in edges for v in e.verts}
    uv_of = {}
    for v in ring:
        if abs(v.co.z - z) < 0.03:
            v.co.z = z
        uv_of[v] = v.link_loops[0][uv_layer].uv.copy()
    old_faces = set(bm.faces)
    if stub != 0.0:
        centre = sum((v.co for v in ring), Vector()) / len(ring)
        source = {tuple(round(c, 6) for c in v.co): v for v in ring}
        made = bmesh.ops.extrude_edge_only(bm, edges=edges)["geom"]
        new_verts = [g for g in made if isinstance(g, bmesh.types.BMVert)]
        edges = [g for g in made if isinstance(g, bmesh.types.BMEdge) and g.is_boundary]
        for v in new_verts:
            uv_of[v] = uv_of[source[tuple(round(c, 6) for c in v.co)]]
            v.co.x = centre.x + (v.co.x - centre.x) * taper
            v.co.y = centre.y + (v.co.y - centre.y) * taper
            v.co.z = z + stub
    bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    new_faces = [f for f in bm.faces if f not in old_faces]
    new_faces = bmesh.ops.triangulate(bm, faces=new_faces)["faces"]
    for face in new_faces:
        for loop in face.loops:
            if loop.vert in uv_of:
                loop[uv_layer].uv = uv_of[loop.vert]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def face_of(ref):
    """points -> 1 where they are on the face of a head (its front, between
    the chin and the brow), 0 elsewhere."""
    neck = ref["neck"]

    def marked(points):
        tall = points[:, 2].max() - neck[2]
        front = points[:, 1].min()
        deep = max(neck[1] - front, 0.02)
        on = ((points[:, 1] < front + deep * 0.75) & (np.abs(points[:, 0] - neck[0]) < deep * 1.1)
              & (points[:, 2] > neck[2] + 0.08 * tall) & (points[:, 2] < neck[2] + 0.7 * tall))
        return on.astype(float)
    return marked


def sitting(ref, arms):
    """Per bone, the matrix that seats the reference skeleton, with the arms
    `arms` degrees below level (negative: above)."""
    matrices = {name: np.eye(4) for name in BONES}
    for side, sign in (("L", 1.0), ("R", -1.0)):
        thigh = about(ref["hip." + side], rot_x(-85.0))
        shin = thigh @ about(ref["knee." + side], rot_x(88.0))
        matrices["Thigh." + side] = thigh
        matrices["Shin." + side] = shin
        matrices["Foot." + side] = shin
        arm = about(ref["shoulder." + side], rot_y(sign * arms))
        for bone in ("UpperArm.", "Forearm.", "Hand."):
            matrices[bone + side] = arm
    return [matrices[name] for name in BONES]


def part_weights(points, kind, ref, half_width, head_radius):
    """The weights a part is posed with. A head does not move at all, a torso
    only at the arms and legs only below the waist, so that the cut edges stay
    as they were made."""
    # Off a torso the head is gone, and what is up there is shoulder.
    weights = bone_weights(points, ref, half_width, half_width * 0.6 if kind == "torso" else head_radius)
    if kind == "head":
        weights[:] = 0.0
        weights[:, 3] = 1.0
        return weights
    if kind == "torso":
        weights[:, IS_LEG] = 0.0
    else:
        weights[:, IS_ARM] = 0.0
        waist = ref["waist"][2]
        weights[:, IS_LEG] *= (1.0 - smoothstep(waist - 0.06, waist - 0.01, points[:, 2]))[:, None]
    weights[:, 0] += 1.0 - weights.sum(1)
    return weights


def write_motion(mesh, arm, held, part):
    """The second UV set the crowd shader reads (see the top of the file)."""
    layer = mesh.uv_layers.get("Motion") or mesh.uv_layers.new(name="Motion")
    loops = np.empty(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", loops)
    uv = np.empty((len(loops), 2))
    uv[:, 0] = 0.5 + 0.5 * arm[loops]
    # Blender's v runs the other way from Godot's.
    uv[:, 1] = 1.0 - (held[loops] + 2.0 * part)
    layer.data.foreach_set("uv", uv.ravel())


def to_godot(point, height):
    return [round(float(point[0]) * height, 4), round(float(point[2]) * height, 4), round(float(-point[1]) * height, 4)]


# --- Build ----------------------------------------------------------------------------

fans = {}
for fan_id, entry in CONFIG["fans"].items():
    if entry.get("source"):
        fans[fan_id] = entry
by_gender = {}
for fan_id, entry in fans.items():
    by_gender.setdefault(entry["gender"], []).append(fan_id)
for gender, ids in by_gender.items():
    real = [i for i in ids if not fans[i].get("placeholder")]
    by_gender[gender] = real if real else ids
used = [fan_id for ids in by_gender.values() for fan_id in ids]
if not used:
    raise SystemExit("crowd_parts.json: no fan has a source")

columns = int(math.ceil(math.sqrt(len(used))))
rows = int(math.ceil(len(used) / columns))
atlas = np.zeros((rows * CELL, columns * CELL, 3))
mask_atlas = np.zeros((rows * CELL, columns * CELL, 3))
built = []       # (object, gender, kind, index, tier, sign)
rest_parts = []  # (object, gender, kind): full detail, standing in the T-pose
references = {}
cell_of = {}

for gender, ids in sorted(by_gender.items()):
    height = float(CONFIG["genders"][gender]["height"])
    letter = gender.upper()
    loaded = {}
    for fan_id in ids:
        obj, texture = load_fan(fan_id, fans[fan_id])
        joints, half_width = find_joints(fan_id, surface_points(obj.data), fans[fan_id].get("joints", {}))
        loaded[fan_id] = [obj, texture, joints, half_width]
    ref = reference_joints([loaded[i][2] for i in ids])
    ref_half_width = float(np.mean([loaded[i][3] for i in ids]))
    references[gender] = (ref, ref_half_width, height)
    print("REFERENCE %s %s" % (gender, json.dumps({k: [round(float(c), 3) for c in v] for k, v in sorted(ref.items())})))

    if preview_dir:
        # Kept as they came, to show the joints that were found.
        for fan_id in ids:
            loaded[fan_id].append(copy_of(loaded[fan_id][0], "Raw_" + fan_id))

    # Every fan bent onto the skeleton and cut into its three parts, still in
    # full detail, and the size of each cut edge.
    rings = {"neck": {}, "waist": {}, "hem": {}}
    whole = {}
    neck, waist = ref["neck"][2], ref["waist"][2]
    for fan_id in ids:
        obj, _texture, joints, half_width = loaded[fan_id][:4]
        set_coords(obj.data, conform(coords(obj.data), joints, half_width, ref, ref_half_width))
        is_cloth = colour_test(fan_id, obj.data, _texture, ref, ref_half_width, "shirt")
        # Only where asked for: hair the colour of the shirt would take the
        # shirt with it.
        is_hair = lambda uv: False
        if fans[fan_id].get("options", {}).get("beard"):
            is_hair = colour_test(fan_id, obj.data, _texture, ref, ref_half_width, "hair")
        whole[fan_id] = {kind: cut(obj, "Whole_%s_%s" % (fan_id, kind), kind, neck, waist, ref["neck"], ref_half_width * 0.75, is_cloth, is_hair)
                         for kind in ("head", "torso", "legs")}
        for seam, kind, z in (("neck", "head", neck), ("waist", "legs", waist), ("hem", "torso", waist - HEM)):
            ring = ring_of(whole[fan_id][kind].data, z)
            if ring is None:
                raise SystemExit("%s: no cut edge at the %s (z = %.3f); check its joints" % (fan_id, seam, z))
            rings[seam][fan_id] = ring
    standard = {seam: np.mean(list(found.values()), axis=0) for seam, found in rings.items()}
    # One waist for both sides of that seam.
    standard["hem"] = standard["waist"]
    for seam in ("neck", "waist"):
        standard[seam][0] = 0.0

    counts = {"head": 0, "torso": 0, "legs": 0}
    for order, fan_id in enumerate(ids):
        entry = fans[fan_id]
        obj, texture = loaded[fan_id][:2]
        points = coords(obj.data)
        head_radius = head_radius_of(points, ref)
        cell = used.index(fan_id)
        cell_of[fan_id] = cell
        cell_x, cell_y = cell % columns, cell // columns

        # The texture: which part each pixel is on, what it is, and its cell.
        gathered = [[], [], [], []]
        for kind in ("legs", "torso", "head"):
            mesh = whole[fan_id][kind].data
            at = coords(mesh)
            tris, part_uvs = face_arrays(mesh)
            normal = np.cross(at[tris[:, 1]] - at[tris[:, 0]], at[tris[:, 2]] - at[tris[:, 0]])
            gathered[0].append(part_uvs)
            gathered[1].append(at[tris].mean(1))
            gathered[2].append(normal / np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-12))
            face_parts = np.full(len(tris), PART_IDS[kind], dtype=np.int8)
            if kind == "torso":
                face_parts[np.abs(at[tris].mean(1)[:, 0]) > abs(ref["wrist.L"][0])] = HANDS
            gathered[3].append(face_parts)
        uvs, centres, normals, parts = (np.concatenate(g) for g in gathered)
        keys = find_keys(fan_id, texture, uvs, centres, normals, parts, ref, ref_half_width, entry.get("keys", {}))
        colour, mask = paint_cell(texture, region_map(uvs, parts, WORK_TEXTURE), keys, entry.get("options", {}))
        atlas[cell_y * CELL:(cell_y + 1) * CELL, cell_x * CELL:(cell_x + 1) * CELL] = colour
        mask_atlas[cell_y * CELL:(cell_y + 1) * CELL, cell_x * CELL:(cell_x + 1) * CELL] = mask
        if preview_dir:
            shown = colour * 0.35
            shown[:, :, 0] += mask[:, :, 0] * 0.65
            shown[:, :, 1] += mask[:, :, 1] * 0.65
            save_image("Mask_" + fan_id, shown, os.path.join(preview_dir, "%s_mask.png" % fan_id))

        # Its UVs, moved into its cell.
        for part in whole[fan_id].values():
            layer = part.data.uv_layers.active.data
            uv = np.empty(len(layer) * 2)
            layer.foreach_get("uv", uv)
            uv = np.mod(uv.reshape(-1, 2), 1.0)
            uv = (uv + np.array([cell_x, cell_y])) / np.array([columns, rows])
            layer.foreach_set("uv", uv.ravel())

        # The first fan of a gender is also its plainest level, whole.
        wanted = set(entry.get("use", ["head", "torso", "legs"]))
        index = {}
        for kind in ("head", "torso", "legs"):
            if kind in wanted:
                index[kind] = counts[kind]
                counts[kind] += 1
        for tier, (suffix, budget_key) in enumerate(TIERS):
            far = tier == 2
            if far and order != 0:
                continue
            pieces = {}
            for kind in ("head", "torso", "legs"):
                if not far and kind not in wanted:
                    continue
                part = copy_of(whole[fan_id][kind], "Cut")
                # A fan may ask for more or fewer triangles than the rest.
                budget = entry.get("budgets", {}).get(budget_key, {}).get(kind, BUDGETS[budget_key][kind])
                part = thin(part, budget, face_of(ref) if kind == "head" and not far else None)
                triangulate(part.data)
                if kind == "head":
                    ease_seam(part.data, neck, rings["neck"][fan_id], standard["neck"], 1.0)
                    # A neck slants, so a stub would stick out of it: the head and
                    # the torso are both closed flat where they meet.
                    close_seam(part.data, neck, 0.0, 1.0, CUP_REACH)
                elif kind == "torso":
                    ease_seam(part.data, neck, rings["neck"][fan_id], standard["neck"], 1.0)
                    close_seam(part.data, neck, 0.0, 1.0, CUP_REACH)
                    ease_seam(part.data, waist - HEM, rings["hem"][fan_id], standard["hem"], HEM_FLARE)
                else:
                    ease_seam(part.data, waist, rings["waist"][fan_id], standard["waist"], WAIST_TUCK)
                    close_seam(part.data, waist, STUB, STUB_TAPER)
                pieces[kind] = part
                if tier == 0:
                    rest_parts.append((copy_of(part, "%s%s%d_Rest" % (kind.capitalize(), letter, index[kind] + 1)), gender, kind))

            drop = np.array([0.0, 0.0, ref["hip.L"][2] - SEAT_DROP])
            for sign_pose in (False, True):
                matrices = sitting(ref, -ARMS_UP if sign_pose else ARMS_DOWN)
                arm_matrix = matrices[BONES.index("UpperArm.L")]
                hand = arm_matrix[:3, :3] @ ref["tip.L"] + arm_matrix[:3, 3] - drop
                shoulder = ref["shoulder.L"] - drop
                posed = []
                for kind, part in pieces.items():
                    # Only a torso looks any different with the arms up.
                    if sign_pose and kind != "torso" and not far:
                        continue
                    twin = copy_of(part, "Posed")
                    rest = coords(twin.data)
                    weights = part_weights(rest, kind, ref, ref_half_width, head_radius)
                    set_coords(twin.data, (skin(rest, weights, matrices) - drop) * height)
                    arm = weights @ ARM_SIDE
                    if sign_pose:
                        write_motion(twin.data, np.zeros(len(rest)), np.abs(arm), PART_IDS[kind])
                    else:
                        write_motion(twin.data, arm, np.zeros(len(rest)), PART_IDS[kind])
                    posed.append((kind, twin))
                results = []
                if far:
                    select_only(posed[0][1])
                    for _kind, twin in posed[1:]:
                        twin.select_set(True)
                    bpy.ops.object.join()
                    results.append(("far", bpy.context.view_layer.objects.active, 0, "Far%s%s" % (letter, "Sign" if sign_pose else "")))
                else:
                    for kind, twin in posed:
                        results.append((kind, twin, index[kind], "%s%s%d%s%s" % (kind.capitalize(), letter, index[kind] + 1, "Sign" if sign_pose else "", suffix)))
                for kind, twin, number, name in results:
                    twin.name = name
                    twin.data.name = name
                    twin.data.validate()
                    twin.data.polygons.foreach_set("use_smooth", [True] * len(twin.data.polygons))
                    twin["kind"] = kind
                    twin["gender"] = gender
                    twin["index"] = number
                    twin["tier"] = tier
                    twin["sign"] = 1 if sign_pose else 0
                    twin["fan"] = fan_id
                    twin["shoulder"] = to_godot(shoulder, height)
                    twin["hand"] = to_godot(hand, height)
                    built.append((twin, gender, kind, number, tier, sign_pose))
                    print("BUILT %s tris %d" % (name, len(twin.data.polygons)))
            for part in pieces.values():
                remove(part)
    for fan_id in ids:
        remove(loaded[fan_id][0])
        for part in whole[fan_id].values():
            remove(part)

atlas_image = save_image("CrowdAtlas", atlas, os.path.join(OUT_DIR, "crowd_atlas.png"))
save_image("CrowdMask", mask_atlas, os.path.join(OUT_DIR, "crowd_mask.png"))
print("ATLAS %dx%d, %d cells: %s" % (atlas.shape[1], atlas.shape[0], len(used), ", ".join(used)))

bpy.ops.object.select_all(action="DESELECT")
for entry in built:
    entry[0].select_set(True)
bpy.context.view_layer.objects.active = built[0][0]
out_path = os.path.join(OUT_DIR, "crowd_kit.glb")
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=False,
    export_skins=False,
    export_animations=False,
    export_extras=True,
    export_materials="NONE",
)
print("EXPORTED", out_path)
for tier in range(3):
    for gender in sorted(by_gender):
        total = {}
        for obj, g, kind, number, t, sign_pose in built:
            if g == gender and t == tier and not sign_pose:
                total.setdefault(kind, []).append(len(obj.data.polygons))
        whole = sum(max(v) for v in total.values())
        print("TRIANGLES %s %s: at most %d a fan (%s)" % (gender, TIERS[tier][1], whole, ", ".join("%s %d" % (k, max(v)) for k, v in total.items())))


# --- The parts with their skeleton, for whoever wants to animate them ------------------

def make_rig(gender):
    ref, half_width, height = references[gender]
    data = bpy.data.armatures.new("CrowdRig" + gender.upper())
    rig = bpy.data.objects.new("CrowdRig" + gender.upper(), data)
    scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    parents = {"Spine": "Hips", "Chest": "Spine", "Head": "Chest"}
    for side in ("L", "R"):
        parents.update({"UpperArm." + side: "Chest", "Forearm." + side: "UpperArm." + side, "Hand." + side: "Forearm." + side,
                        "Thigh." + side: "Hips", "Shin." + side: "Thigh." + side, "Foot." + side: "Shin." + side})
    for name, a, b in TRUNK + [limb[:3] for limb in LIMBS]:
        bone = data.edit_bones.new(name)
        bone.head = ref[a] * height
        bone.tail = ref[b] * height
        bone.roll = 0.0
    for name, parent in parents.items():
        data.edit_bones[name].parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


if rig_path:
    kept = []
    for gender in sorted(by_gender):
        ref, half_width, height = references[gender]
        rig = make_rig(gender)
        kept.append(rig)
        for obj, g, kind in rest_parts:
            if g != gender:
                continue
            rest = coords(obj.data)
            weights = part_weights(rest, kind, ref, half_width, head_radius_of(rest, ref) if kind == "head" else 0.1)
            set_coords(obj.data, rest * height)
            obj.name = obj.name.replace("_Rest", "")
            groups = [obj.vertex_groups.new(name=name) for name in BONES]
            for v in range(len(rest)):
                for b in np.nonzero(weights[v])[0]:
                    groups[b].add([v], float(weights[v, b]), "REPLACE")
            obj.parent = rig
            obj.modifiers.new("Armature", "ARMATURE").object = rig
            kept.append(obj)
    for obj in list(bpy.data.objects):
        if obj not in kept:
            obj.hide_viewport = True
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(rig_path), copy=True)
    print("RIG", rig_path)
    for obj in list(bpy.data.objects):
        obj.hide_viewport = obj not in kept and obj.hide_viewport


# --- Pictures -------------------------------------------------------------------------

if preview_dir:
    save_image("AtlasPreview", atlas, os.path.join(preview_dir, "atlas.png"))
    material = bpy.data.materials.new("CrowdAtlas")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    picture = nodes.new("ShaderNodeTexImage")
    picture.image = atlas_image
    shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    material.node_tree.links.new(picture.outputs["Color"], shader.inputs["Base Color"])
    nodes.active = picture

    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.film_transparent = False
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    def shoot(name, aim, offset, scale, size):
        cam_data.ortho_scale = scale
        cam.location = Vector(aim) + Vector(offset)
        cam.rotation_euler = (-Vector(offset)).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = size
        scene.render.filepath = os.path.join(preview_dir, name + ".png")
        bpy.ops.render.render(write_still=True)

    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.hide_render = True

    # Every fan as it came, with the joints that were found as red sticks.
    red = bpy.data.materials.new("Bones")
    red.diffuse_color = (1.0, 0.0, 0.0, 1.0)
    for gender, ids in sorted(by_gender.items()):
        for fan_id in ids:
            raw = bpy.data.objects["Raw_" + fan_id]
            joints = find_joints(fan_id, surface_points(raw.data), fans[fan_id].get("joints", {}))[0]
            curve = bpy.data.curves.new("Bones_" + fan_id, "CURVE")
            curve.dimensions = "3D"
            curve.bevel_depth = 0.006
            for _name, a, b in TRUNK + [limb[:3] for limb in LIMBS]:
                spline = curve.splines.new("POLY")
                spline.points.add(1)
                spline.points[0].co = (*joints[a], 1.0)
                spline.points[1].co = (*joints[b], 1.0)
            curve.materials.append(red)
            sticks = bpy.data.objects.new("Bones_" + fan_id, curve)
            scene.collection.objects.link(sticks)
            raw.hide_render = False
            scene.display.shading.color_type = "MATERIAL"
            scene.display.shading.show_xray = True
            scene.display.shading.xray_alpha = 0.35
            shoot("%s_joints_front" % fan_id, (0.0, 0.0, 0.5), (0.0, -6.0, 0.0), 1.5, (700, 700))
            shoot("%s_joints_side" % fan_id, (0.0, 0.0, 0.5), (6.0, 0.0, 0.0), 1.5, (700, 700))
            raw.hide_render = True
            sticks.hide_render = True
    scene.display.shading.show_xray = False
    scene.display.shading.color_type = "TEXTURE"

    # Every head on every torso, level by level, from the front and from behind.
    twins = []
    for gender in sorted(by_gender):
        height = references[gender][2]
        for tier in (0, 1):
            parts = {kind: sorted([b for b in built if b[1] == gender and b[2] == kind and b[4] == tier and not b[5]], key=lambda b: b[3])
                     for kind in ("head", "torso", "legs")}
            for obj in twins:
                bpy.data.objects.remove(obj)
            twins = []
            wide = len(parts["head"])
            deep = len(parts["torso"])
            for row, torso in enumerate(parts["torso"]):
                for column, head in enumerate(parts["head"]):
                    legs = parts["legs"][(row + column) % len(parts["legs"])]
                    for source in (head, torso, legs):
                        twin = source[0].copy()
                        scene.collection.objects.link(twin)
                        twin.location = ((column - (wide - 1) * 0.5) * height * 0.75, 0.0, -(row - (deep - 1) * 0.5) * height * 0.8)
                        twin.hide_render = False
                        if not twin.data.materials:
                            twin.data.materials.append(material)
                        twins.append(twin)
            span = max(wide * 0.75, deep * 0.8 * 1.3) * height + 0.3
            size = (int(360 * wide * 0.75 / 0.8) + 120, 360 * deep + 120)
            name = "kit_%s_%s" % (gender, TIERS[tier][1])
            shoot(name + "_front", (0.0, 0.0, 0.15 * height), (1.5, -8.0, 1.2), span, size)
            shoot(name + "_back", (0.0, 0.0, 0.15 * height), (-1.5, 8.0, 1.2), span, size)
            shoot(name + "_side", (0.0, 0.0, 0.15 * height), (-8.0, -1.0, 0.6), span, size)
    for obj in twins:
        bpy.data.objects.remove(obj)
    # The arms-up torsos and the plainest level, each on its own.
    rest = [b for b in built if b[5] or b[4] == 2]
    for i, entry in enumerate(rest):
        obj = entry[0]
        obj.hide_render = False
        obj.location = ((i - (len(rest) - 1) * 0.5) * 1.6, 0.0, 0.0)
        if not obj.data.materials:
            obj.data.materials.append(material)
    if rest:
        shoot("kit_sign_and_far", (0.0, 0.0, 0.4), (1.5, -8.0, 1.2), len(rest) * 1.6 + 0.4, (220 * len(rest) + 100, 420))
    print("PREVIEWS", preview_dir)
