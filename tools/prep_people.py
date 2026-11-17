"""Turns whole Tripo characters into the people who fill the stands.

Run from the project root:

    blender -b --factory-startup --python tools/prep_people.py -- [preview=<dir>]

It reads tools/crowd_people.json (every person with a `source`) and writes

    assets/stadium/crowd_people.glb         the people, posed sitting, as plain meshes
    assets/stadium/crowd_people_atlas.png   every person's colour texture, one cell each
    assets/stadium/crowd_people_mask.png    what the crowd shader repaints in it
    assets/stadium/crowd_people_normal.png  every person's normal map, same cells

To add a person: give one in crowd_people.json a `source` (see the `_about`
there for how the model is made) and run this again. It always rebuilds all.

What happens to a person:

1. Clean-up: one welded triangle mesh, facing -Y, feet on the ground, one unit
   tall while it is worked on. The model is about 1,500 triangles as it comes
   and is not thinned for the nearest level.
2. Its joints are found from its shape (it stands in a T-pose); `joints` in
   the JSON overrides any of them.
3. Its texture goes into its cell of the atlas. The top is plain light grey
   and the trousers plain mid grey: where the texture is one of those greys,
   on the part of the body where that garment is, it is reduced to its
   shading and the mask says what it is, so the shader can give every fan a
   colour of its own:
       mask R  the top: takes the fan's shirt colour
       mask G  the trousers: take the fan's trouser colour
   Skin, hair, face and shoes are left as they are.
4. Two plainer levels of detail are thinned from it (`budgets`).
5. Each level is posed sitting, once with the arms down and once with them
   up (a fan with a sign). The crowd is drawn with MultiMeshes, which cannot
   have skeletons, so the pose is baked in and the crowd shader does the
   moving.

The meshes, with the seat at y = 0 in Godot and the person facing +Z:

    Person<n>, Person<n>Mid, Person<n>Far              arms down
    Person<n>Sign, Person<n>SignMid, Person<n>SignFar  arms up

UV is the atlas. The second UV set, as Godot reads it, is for the shader:

    UV2.x  0.5 on the body; towards 1 the more a vertex belongs to the left
           arm, towards 0 the more it belongs to the right one
    UV2.y  how much it belongs to an arm that is held up (a ...Sign mesh)

Each object's custom properties (glTF "extras") say what it is (`kind`:
"person", `gender`, `index`, `tier`, `sign`, `fan`: its id) and, in Godot's
axes and the mesh's units, `shoulder` (the left one: where the arms turn) and
`hand` (the left hand of a person with a sign).

With `preview`, pictures are saved there: every person's joints and mask, the
atlas, and every mesh that was built.
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
# The texture is looked at with this many pixels a side.
WORK_TEXTURE = 1024
TIERS = (("", "near"), ("Mid", "mid"), ("Far", "far"))
# What a triangle may be painted as.
TOP, PANTS, EITHER = 1, 2, 3
# How far below the hip joints the seat is, with the height = 1.
SEAT_DROP = 0.055
# How far above the waist a triangle may still be trousers, and how far above
# the neck it may still be the top (a collar).
WAISTBAND = 0.04
COLLAR = 0.03
# How far above the shoulder joints the top of a shoulder or a sleeve may be.
SHOULDER_RISE = 0.08
# Where a triangle may be the top or the trousers: how far from the trousers'
# brightness toward the top's a pixel has to be to count as the top.
EITHER_BIAS = 0.7
# How much less a face is thinned out than the rest (0: no less).
KEEP_STRENGTH = 0.7
# Degrees the arms hang below level, and are held above it with a sign.
ARMS_DOWN = 76.0
ARMS_UP = 72.0

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
options = dict(arg.split("=", 1) for arg in argv)
preview_dir = options.get("preview")
unknown = [key for key in options if key != "preview"]
if unknown:
    raise SystemExit("usage: prep_people.py -- [preview=<dir>]  (unknown: %s)" % ", ".join(unknown))

with open(os.path.join(ROOT, "tools", "crowd_people.json"), encoding="utf-8") as handle:
    CONFIG = json.load(handle)
CELL = int(CONFIG.get("atlas_cell", 512))
GRID = int(CONFIG.get("atlas_grid", 4))

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
    of each other: an imported model comes apart along its UV seams."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    if weld:
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def thin(obj, tris, keep):
    """Cuts `obj` down to about `tris` triangles and returns it. `keep`
    (points -> 0..1 per vertex) marks what should lose the fewest: the face."""
    have = len(obj.data.polygons)
    if have <= tris:
        return obj
    weights = 1.0 - KEEP_STRENGTH * keep(coords(obj.data))
    group = obj.vertex_groups.new(name="Thin")
    for index, weight in enumerate(weights):
        group.add([index], float(weight), "REPLACE")
    select_only(obj)
    modifier = obj.modifiers.new("Thin", "DECIMATE")
    modifier.ratio = tris / have
    modifier.vertex_group = "Thin"
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.vertex_groups.clear()
    if len(obj.data.polygons) > tris * 1.25:
        # It did not come down far enough with the face spared: evenly, then.
        modifier = obj.modifiers.new("Thin", "DECIMATE")
        modifier.ratio = tris / len(obj.data.polygons)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    triangulate(obj.data)
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


def rot_x(degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]])


def rot_y(degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def about(pivot, linear):
    """`linear` applied about `pivot`, as a 4 x 4 matrix."""
    pivot = np.asarray(pivot, dtype=float)
    out = np.eye(4)
    out[:3, :3] = linear
    out[:3, 3] = pivot - linear @ pivot
    return out


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


def pixels_of(image, size):
    """The picture at `size` pixels a side: rows from the bottom, 3 channels,
    the values as they are in the file."""
    image.scale(size, size)
    pixels = np.empty(size * size * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    return pixels.reshape(size, size, 4)[:, :, :3].astype(np.float64)


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


# --- Loading a person -----------------------------------------------------------------

def load_person(person_id, entry):
    """The person as one triangle mesh at the origin, facing -Y, one unit
    tall, with its colour texture and its normal map (or None) as arrays."""
    path = os.path.join(ROOT, entry["source"])
    old_objects = set(o.name for o in bpy.data.objects)
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o.name not in old_objects]
    meshes = [o for o in new if o.type == "MESH"]
    if not meshes:
        raise SystemExit("%s: no mesh in %s" % (person_id, entry["source"]))
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "Person_" + person_id
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

    colour = None
    bumps = None
    for material in mesh.materials:
        if material is None or material.node_tree is None:
            continue
        nodes = material.node_tree.nodes
        shader = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
        if shader is not None and shader.inputs["Base Color"].links:
            source = shader.inputs["Base Color"].links[0].from_node
            if source.type == "TEX_IMAGE" and source.image is not None:
                colour = source.image
        bump = next((n for n in nodes if n.type == "NORMAL_MAP"), None)
        if bump is not None and bump.inputs["Color"].links:
            source = bump.inputs["Color"].links[0].from_node
            if source.type == "TEX_IMAGE" and source.image is not None:
                bumps = source.image
        if colour is not None:
            break
    if colour is None:
        raise SystemExit("%s: the model has no colour texture" % person_id)
    if len([m for m in mesh.materials if m is not None]) > 1:
        print("WARNING: %s has several materials; only the texture %s is used" % (person_id, colour.name))
    if bumps is None:
        print("WARNING: %s has no normal map" % person_id)
    texture = pixels_of(colour, WORK_TEXTURE)
    normal = pixels_of(bumps, CELL) if bumps is not None else None
    mesh.materials.clear()

    triangulate(mesh, weld=True)
    points = coords(mesh)
    yaw = float(entry.get("yaw", 0.0))
    if yaw != 0.0:
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        points = points @ np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]]).T
    lo, hi = points.min(0), points.max(0)
    points = (points - np.array([(lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, lo[2]])) / (hi[2] - lo[2])
    set_coords(mesh, points)
    print("LOADED %s: %d triangles, texture %s, normal map %s" % (person_id, len(mesh.polygons), colour.name, bumps.name if bumps else "none"))
    return obj, texture, normal


# --- Where the joints are -------------------------------------------------------------

def arm_joints(person_id, points, centre_x, half_width):
    """The joints of the arms of a figure in a T-pose: an arm is what is at
    the height of its fingertips, out past the body."""
    joints = {}
    for side, sign in (("L", 1.0), ("R", -1.0)):
        out = (points[:, 0] - centre_x) * sign
        far = points[out > np.percentile(out, 99.5)]
        level = float(np.median(far[:, 2]))
        arm = points[(out > half_width * 1.2) & (np.abs(points[:, 2] - level) < 0.07)]
        if len(arm) < 40:
            print("WARNING: %s: no arm found on side %s; guessing" % (person_id, side))
            shoulder = np.array([centre_x + sign * half_width * 1.2, 0.0, 0.66])
            tip = shoulder + np.array([sign * 0.3, 0.0, 0.0])
        else:
            centre = arm.mean(0)
            axis = np.linalg.svd(arm - centre, full_matrices=False)[2][0]
            if axis[0] * sign < 0.0:
                axis = -axis
            along = (arm - centre) @ axis
            shoulder = centre + axis * np.percentile(along, 2)
            tip = centre + axis * np.percentile(along, 99)
            shoulder = shoulder - (tip - shoulder) / np.linalg.norm(tip - shoulder) * 0.01
        joints["shoulder." + side] = shoulder
        joints["elbow." + side] = shoulder + (tip - shoulder) * 0.45
        joints["wrist." + side] = shoulder + (tip - shoulder) * 0.8
        joints["tip." + side] = tip
    return joints


def find_joints(person_id, points, overrides, quiet=False):
    """The person's joints, with the height = 1: name -> np.array, and the
    half width of the waist."""
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
        print("WARNING: %s: the legs were not found apart; guessing the crotch" % person_id)
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

    joints = arm_joints(person_id, points, centre_x, half_width)

    # The neck is where the middle of the body is narrowest above the shoulders.
    shoulder_z = (joints["shoulder.L"][2] + joints["shoulder.R"][2]) * 0.5
    heights = np.arange(shoulder_z + 0.03, 0.93, 0.005)
    widths = []
    for z in heights:
        part = band(z, 0.005)
        widths.append(np.percentile(part[:, 0], 98) - np.percentile(part[:, 0], 2) if len(part) > 8 else 9.0)
    widths = np.convolve(widths, np.ones(3) / 3.0, mode="same") if len(widths) > 3 else np.array(widths)
    # Going up, the narrowest place before the head widens again.
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
            raise SystemExit("crowd_people.json: %s: unknown joint %s (have %s)" % (person_id, key, ", ".join(sorted(joints))))
        joints[key] = np.array(value, dtype=float)
    if not quiet:
        print("JOINTS %s %s" % (person_id, json.dumps({k: [round(float(c), 3) for c in v] for k, v in sorted(joints.items())})))
        print("WAIST %s half width %.3f" % (person_id, half_width))
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
BONES = ["Trunk"] + [b[0] for b in LIMBS]
ARM_SIDE = np.array([0.0 if not b.split(".")[0] in ("UpperArm", "Forearm", "Hand") else (1.0 if b.endswith(".L") else -1.0) for b in BONES])


def segment_distance(points, head, tail):
    along = tail - head
    t = np.clip(((points - head) @ along) / max(float(along @ along), 1e-9), 0.0, 1.0)
    return np.linalg.norm(points - (head + t[:, None] * along), axis=1)


def bone_weights(points, joints, half_width, head_radius):
    """How much each vertex belongs to each of BONES (V, B): to a limb by how
    far it is outside a tube round the bone, and to the trunk (which does not
    move) by how far it is outside a fatter tube up the middle."""
    trunk = np.full(len(points), 9.0)
    for name, a, b in TRUNK:
        # Big hair is not a big head: a head as wide as its hair would take
        # the shoulders with it.
        radius = min(head_radius, half_width * 1.1) if name == "Head" else half_width * 0.85
        head = joints[a].copy()
        if name == "Hips":
            # So that the round end of the tube stops at the crotch.
            head[2] += radius * 0.5
        trunk = np.minimum(trunk, np.maximum(segment_distance(points, head, joints[b]) - radius, 0.0))
    outside = [trunk]
    # The limbs of a broad person are thick too.
    thick = half_width / 0.1
    # Above the neck only what is close round a limb is that limb (a sleeve):
    # hair that hangs down beside the shoulders stays with the head when the
    # arms go up.
    above = smoothstep(joints["neck"][2] - 0.01, joints["neck"][2] + 0.02, points[:, 2])
    hair = []
    for name, a, b, radius in LIMBS:
        away = segment_distance(points, joints[a], joints[b])
        outside.append(np.maximum(away - radius * thick, 0.0))
        hair.append(above * smoothstep(0.07, 0.1, away))
    raw = np.stack([1.0 / (d + 0.015) ** 4 for d in outside], axis=1)
    raw[:, 1:] *= 1.0 - np.stack(hair, axis=1)
    raw[raw < raw.max(1, keepdims=True) * 0.02] = 0.0
    raw /= raw.sum(1, keepdims=True)
    return raw


def head_radius_of(points, joints):
    # Well up the head: lower down there may be shoulders beside it.
    above = points[points[:, 2] > joints["neck"][2] + 0.35 * (points[:, 2].max() - joints["neck"][2])]
    if len(above) < 10:
        return 0.1
    return float(np.percentile(np.abs(above[:, 0] - joints["neck"][0]), 95))


def sitting(joints, arms):
    """Per bone, the matrix that seats the person, with the arms `arms`
    degrees below level (negative: above)."""
    matrices = {name: np.eye(4) for name in BONES}
    for side, sign in (("L", 1.0), ("R", -1.0)):
        thigh = about(joints["hip." + side], rot_x(-85.0))
        shin = thigh @ about(joints["knee." + side], rot_x(88.0))
        matrices["Thigh." + side] = thigh
        matrices["Shin." + side] = shin
        matrices["Foot." + side] = shin
        arm = about(joints["shoulder." + side], rot_y(sign * arms))
        for bone in ("UpperArm.", "Forearm.", "Hand."):
            matrices[bone + side] = arm
    return [matrices[name] for name in BONES]


def face_of(joints):
    """points -> 1 where they are on the face (the front of the head, between
    the chin and the brow), 0 elsewhere."""
    neck = joints["neck"]

    def marked(points):
        head = points[points[:, 2] > neck[2]]
        if len(head) < 4:
            return np.zeros(len(points))
        tall = points[:, 2].max() - neck[2]
        front = head[:, 1].min()
        deep = max(neck[1] - front, 0.02)
        on = ((points[:, 1] < front + deep * 0.75) & (np.abs(points[:, 0] - neck[0]) < deep * 1.1)
              & (points[:, 2] > neck[2] + 0.08 * tall) & (points[:, 2] < neck[2] + 0.7 * tall))
        return on.astype(float)
    return marked


# --- Texture, atlas and mask ----------------------------------------------------------

def face_arrays(mesh):
    """Per triangle: the vertex indices (F, 3) and the UVs (F, 3, 2)."""
    loops = np.empty(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", loops)
    uvs = np.empty(len(mesh.loops) * 2)
    mesh.uv_layers.active.data.foreach_get("uv", uvs)
    return loops.reshape(-1, 3), uvs.reshape(-1, 3, 2)


def region_map(uvs, parts, size):
    """What each pixel of the texture may be painted as (0: nothing), from
    what its triangle may be."""
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
    out[out < 0] = 0
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


def uv_islands(tris, uvs):
    """The pieces the texture is laid out in: lists of triangle indices,
    triangles being in one piece when they share a corner in the texture."""
    parent = list(range(len(tris)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    first = {}
    for f in range(len(tris)):
        for corner in range(3):
            key = (int(tris[f, corner]), round(float(uvs[f, corner, 0]), 5), round(float(uvs[f, corner, 1]), 5))
            if key in first:
                a, b = find(f), find(first[key])
                if a != b:
                    parent[a] = b
            else:
                first[key] = f
    groups = {}
    for f in range(len(tris)):
        groups.setdefault(find(f), []).append(f)
    return [np.array(group) for group in groups.values()]


def garments(person_id, entry, mesh, texture, joints, half_width):
    """What each triangle may be painted as (0, TOP, PANTS or EITHER, where a
    top hangs over the trousers), and the colours of the top and the
    trousers in the texture."""
    at = coords(mesh)
    tris, uvs = face_arrays(mesh)
    centres = at[tris].mean(1)
    z = centres[:, 2]
    out = np.abs(centres[:, 0] - joints["waist"][0])
    neck, waist, crotch = joints["neck"][2], joints["waist"][2], joints["crotch"][2] - 0.03
    given = entry.get("options", {})
    sleeves = given.get("sleeves", "wrist")
    legs = given.get("legs", "ankle")
    if sleeves not in ("wrist", "elbow", "shoulder") or legs not in ("ankle", "knee"):
        raise SystemExit("crowd_people.json: %s: options.sleeves is wrist, elbow or shoulder, and options.legs ankle or knee" % person_id)
    reach = abs(joints[sleeves + ".L"][0] - joints["waist"][0]) + 0.02
    floor = joints[legs + ".L"][2] + (0.02 if legs == "ankle" else 0.0)
    # The top ends at the collar in the middle, but beside the neck it goes
    # as high as the shoulders and the sleeves do, which on a short neck is
    # higher than the neck line.
    shoulder_z = max(joints["shoulder.L"][2], joints["shoulder.R"][2])
    collar = float(given.get("collar", COLLAR))
    ceiling = np.where(out > half_width * 0.45, max(neck + collar, shoulder_z + SHOULDER_RISE), neck + collar)
    top_ok = (z > crotch) & (z < ceiling) & (out < reach)
    pants_ok = (z < waist + WAISTBAND) & (z > floor)
    parts = np.zeros(len(tris), dtype=np.int8)
    parts[top_ok] = TOP
    parts[pants_ok] = PANTS
    parts[top_ok & pants_ok] = EITHER
    # A piece of the texture (triangles that share corners in it) that is
    # nearly all one garment is that garment all over: the waistband under
    # the hem of the top is trousers, however high up it is.
    area = np.linalg.norm(np.cross(at[tris[:, 1]] - at[tris[:, 0]], at[tris[:, 2]] - at[tris[:, 0]]), axis=1)
    for island in uv_islands(tris, uvs):
        tops = float(area[island][parts[island] == TOP].sum())
        pants = float(area[island][parts[island] == PANTS].sum())
        for more, fewer, value in ((tops, pants, TOP), (pants, tops, PANTS)):
            if more > 4.0 * fewer and more > 0.0:
                inside = island[parts[island] > 0]
                parts[inside] = value

    keys = {
        # The middle of the trunk, front and back, and the thighs.
        "top": sample_key(texture, uvs, (out < half_width * 0.6) & (z > waist + 0.3 * (neck - waist)) & (z < waist + 0.75 * (neck - waist))),
        # (Long hair over the chest and the back gives the wrong colour here:
        # give such a person `keys.top`.)
        # The upper half of the thighs: shorts end above the knee.
        "pants": sample_key(texture, uvs, (z > (joints["knee.L"][2] + crotch) * 0.5) & (z < crotch - 0.01)),
    }
    for key, value in entry.get("keys", {}).items():
        if key not in keys:
            raise SystemExit("crowd_people.json: %s: unknown key colour %s" % (person_id, key))
        keys[key] = None if value is None else np.array(value, dtype=float)
    print("KEYS %s %s" % (person_id, json.dumps({k: None if v is None else [round(float(c), 3) for c in v] for k, v in keys.items()})))
    return uvs, parts, keys


def box_sum(flags, reach):
    """How many of `flags` (H, W) are set within `reach` pixels of each pixel."""
    total = np.pad(flags.astype(np.int32), (reach + 1, reach)).cumsum(0).cumsum(1)
    size = 2 * reach + 1
    return total[size:, size:] - total[:-size, size:] - total[size:, :-size] + total[:-size, :-size]


def paint_cell(texture, regions, keys, given):
    """The person's cell of the atlas (RGB) and of the mask (R top, G
    trousers), and the share of the texture each garment takes."""
    near = float(given.get("chroma", 0.07))
    dark, bright = given.get("luma", [0.5, 1.7])
    luma = texture @ LUMA
    tone = chroma(texture)
    kind = np.zeros(texture.shape[:2], dtype=np.int8)
    colour = texture.copy()
    # Where a triangle may be either (the top hangs over the trousers), a
    # pixel is the top only if it is clearly as light as the top: the line is
    # EITHER_BIAS of the way from the trousers' brightness to the top's.
    split = None
    if keys.get("top") is not None and keys.get("pants") is not None:
        top_luma, pants_luma = (max(float(keys[name] @ LUMA), 0.02) for name in ("top", "pants"))
        split = math.exp((1.0 - EITHER_BIAS) * math.log(pants_luma) + EITHER_BIAS * math.log(top_luma))
        if top_luma < pants_luma:
            split = -split
    for name, value in (("top", TOP), ("pants", PANTS)):
        key = keys.get(name)
        if key is None:
            continue
        key_luma = max(float(key @ LUMA), 0.02)
        off = np.linalg.norm(tone - chroma(key), axis=-1)
        # A dark colour has no hue to speak of: go by how dark it is.
        if key_luma < 0.12:
            off = off * 0.4
        ratio = luma / key_luma
        here = regions == value
        if split is None:
            here |= regions == EITHER
        else:
            lighter = luma > split if split > 0.0 else luma < -split
            here |= (regions == EITHER) & (lighter == (value == TOP))
        fits = here & (off < near) & (ratio > dark) & (ratio < bright)
        kind[fits] = value
    # A seam or a highlight on the trousers is not a strip of the top: where
    # it may be either, a pixel is what most of those round it are.
    tops, pants = box_sum(kind == TOP, 6), box_sum(kind == PANTS, 6)
    unsure = (regions == EITHER) & (kind > 0)
    kind[unsure & (pants > tops)] = PANTS
    kind[unsure & (tops > pants)] = TOP
    # What is repainted is kept as its shading only: how light it is beside
    # the garment's own colour, at 0.8 of full to leave room for highlights.
    for value, name in ((TOP, "top"), (PANTS, "pants")):
        if keys.get(name) is None:
            continue
        fits = kind == value
        key_luma = max(float(keys[name] @ LUMA), 0.02)
        colour[fits] = np.clip(luma[fits] / key_luma * 0.8, 0.0, 1.0)[:, None]
    mask = np.zeros(texture.shape)
    mask[:, :, 0] = kind == TOP
    mask[:, :, 1] = kind == PANTS
    shares = (float((kind == TOP).mean()), float((kind == PANTS).mean()))
    step = texture.shape[0] // CELL
    if step > 1:
        colour = colour.reshape(CELL, step, CELL, step, 3).mean((1, 3))
        mask = mask.reshape(CELL, step, CELL, step, 3).mean((1, 3))
    return colour, mask, shares


def write_motion(mesh, arm, held):
    """The second UV set the crowd shader reads (see the top of the file)."""
    layer = mesh.uv_layers.get("Motion") or mesh.uv_layers.new(name="Motion")
    loops = np.empty(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", loops)
    uv = np.empty((len(loops), 2))
    uv[:, 0] = 0.5 + 0.5 * arm[loops]
    # Blender's v runs the other way from Godot's.
    uv[:, 1] = 1.0 - held[loops]
    layer.data.foreach_set("uv", uv.ravel())


def to_godot(point, height):
    return [round(float(point[0]) * height, 4), round(float(point[2]) * height, 4), round(float(-point[1]) * height, 4)]


# --- Build ----------------------------------------------------------------------------

order = list(CONFIG["people"])
people = [person_id for person_id in order if CONFIG["people"][person_id].get("source")]
if not people:
    raise SystemExit("crowd_people.json: nobody has a source")
if len(order) > GRID * GRID:
    raise SystemExit("crowd_people.json: %d people do not fit an atlas of %d x %d cells" % (len(order), GRID, GRID))

atlas = np.zeros((GRID * CELL, GRID * CELL, 3))
mask_atlas = np.zeros((GRID * CELL, GRID * CELL, 3))
normal_atlas = np.zeros((GRID * CELL, GRID * CELL, 3))
normal_atlas[:, :] = (0.5, 0.5, 1.0)
built = []   # (object, person, tier, sign)
raws = {}    # person -> (object as it came, joints), for the pictures

for index, person_id in enumerate(people):
    entry = CONFIG["people"][person_id]
    gender = entry["gender"]
    height = float(entry.get("height", CONFIG["genders"][gender]["height"]))
    obj, texture, normal = load_person(person_id, entry)
    joints, half_width = find_joints(person_id, surface_points(obj.data), entry.get("joints", {}))
    if preview_dir:
        raws[person_id] = (copy_of(obj, "Raw_" + person_id), joints)

    # Its cell is its place in the list, with or without the others.
    cell = order.index(person_id)
    cell_x, cell_y = cell % GRID, cell // GRID
    uvs, parts, keys = garments(person_id, entry, obj.data, texture, joints, half_width)
    colour, mask, shares = paint_cell(texture, region_map(uvs, parts, WORK_TEXTURE), keys, entry.get("options", {}))
    print("PAINTED %s: the top is %.0f %% of the texture, the trousers %.0f %%" % (person_id, shares[0] * 100.0, shares[1] * 100.0))
    here = (slice(cell_y * CELL, (cell_y + 1) * CELL), slice(cell_x * CELL, (cell_x + 1) * CELL))
    atlas[here] = colour
    mask_atlas[here] = mask
    if normal is not None:
        normal_atlas[here] = normal
    if preview_dir:
        shown = colour * 0.35
        shown[:, :, 0] += mask[:, :, 0] * 0.65
        shown[:, :, 1] += mask[:, :, 1] * 0.65
        save_image("Mask_" + person_id, shown, os.path.join(preview_dir, "%s_mask.png" % person_id))
    layer = obj.data.uv_layers.active.data
    uv = np.empty(len(layer) * 2)
    layer.foreach_get("uv", uv)
    uv = (np.mod(uv.reshape(-1, 2), 1.0) + np.array([cell_x, cell_y])) / float(GRID)
    layer.foreach_set("uv", uv.ravel())

    head_radius = head_radius_of(coords(obj.data), joints)
    drop = np.array([0.0, 0.0, joints["hip.L"][2] - SEAT_DROP])
    for tier, (suffix, budget_key) in enumerate(TIERS):
        level = copy_of(obj, "Level")
        if tier > 0:
            level = thin(level, int(entry.get("budgets", {}).get(budget_key, CONFIG["budgets"][budget_key])), face_of(joints))
        rest = coords(level.data)
        weights = bone_weights(rest, joints, half_width, head_radius)
        arm = weights @ ARM_SIDE
        for sign_pose in (False, True):
            matrices = sitting(joints, -ARMS_UP if sign_pose else ARMS_DOWN)
            arm_matrix = matrices[BONES.index("UpperArm.L")]
            hand = arm_matrix[:3, :3] @ joints["tip.L"] + arm_matrix[:3, 3] - drop
            shoulder = joints["shoulder.L"] - drop
            twin = copy_of(level, "Person%d%s%s" % (index + 1, "Sign" if sign_pose else "", suffix))
            set_coords(twin.data, (skin(rest, weights, matrices) - drop) * height)
            if sign_pose:
                write_motion(twin.data, np.zeros(len(rest)), np.abs(arm))
            else:
                write_motion(twin.data, arm, np.zeros(len(rest)))
            twin.data.validate()
            twin.data.polygons.foreach_set("use_smooth", [True] * len(twin.data.polygons))
            twin["kind"] = "person"
            twin["gender"] = gender
            twin["index"] = index
            twin["tier"] = tier
            twin["sign"] = 1 if sign_pose else 0
            twin["fan"] = person_id
            twin["shoulder"] = to_godot(shoulder, height)
            twin["hand"] = to_godot(hand, height)
            built.append((twin, person_id, tier, sign_pose))
            if not sign_pose:
                print("BUILT %s tris %d" % (twin.name, len(twin.data.polygons)))
        remove(level)
    remove(obj)

atlas_image = save_image("PeopleAtlas", atlas, os.path.join(OUT_DIR, "crowd_people_atlas.png"))
save_image("PeopleMask", mask_atlas, os.path.join(OUT_DIR, "crowd_people_mask.png"))
save_image("PeopleNormal", normal_atlas, os.path.join(OUT_DIR, "crowd_people_normal.png"))
print("ATLAS %dx%d, %d of %d cells: %s" % (atlas.shape[1], atlas.shape[0], len(people), GRID * GRID, ", ".join(people)))

bpy.ops.object.select_all(action="DESELECT")
for entry in built:
    entry[0].select_set(True)
bpy.context.view_layer.objects.active = built[0][0]
out_path = os.path.join(OUT_DIR, "crowd_people.glb")
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
for tier, (_suffix, name) in enumerate(TIERS):
    counts = [len(obj.data.polygons) for obj, _person, t, sign_pose in built if t == tier and not sign_pose]
    print("TRIANGLES %s: %d to %d a person" % (name, min(counts), max(counts)))


# --- Pictures -------------------------------------------------------------------------

if preview_dir:
    save_image("AtlasPreview", atlas, os.path.join(preview_dir, "atlas.png"))
    material = bpy.data.materials.new("PeopleAtlas")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    picture = nodes.new("ShaderNodeTexImage")
    picture.image = atlas_image
    shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    material.node_tree.links.new(picture.outputs["Color"], shader.inputs["Base Color"])
    nodes.active = picture

    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
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

    # Every person as it came, with the joints that were found as red sticks.
    red = bpy.data.materials.new("Bones")
    red.diffuse_color = (1.0, 0.0, 0.0, 1.0)
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_xray = True
    scene.display.shading.xray_alpha = 0.35
    for person_id, (raw, joints) in raws.items():
        curve = bpy.data.curves.new("Bones_" + person_id, "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = 0.006
        for _name, a, b in TRUNK + [limb[:3] for limb in LIMBS]:
            spline = curve.splines.new("POLY")
            spline.points.add(1)
            spline.points[0].co = (*joints[a], 1.0)
            spline.points[1].co = (*joints[b], 1.0)
        curve.materials.append(red)
        sticks = bpy.data.objects.new("Bones_" + person_id, curve)
        scene.collection.objects.link(sticks)
        raw.hide_render = False
        shoot("%s_joints_front" % person_id, (0.0, 0.0, 0.5), (0.0, -6.0, 0.0), 1.5, (700, 700))
        shoot("%s_joints_side" % person_id, (0.0, 0.0, 0.5), (6.0, 0.0, 0.0), 1.5, (700, 700))
        raw.hide_render = True
        sticks.hide_render = True
    scene.display.shading.show_xray = False
    scene.display.shading.color_type = "TEXTURE"

    # Every mesh of each person: the three levels with the arms down, then up.
    for person_id in people:
        mine = [b for b in built if b[1] == person_id]
        mine.sort(key=lambda b: (b[3], b[2]))
        for i, entry in enumerate(mine):
            obj = entry[0]
            obj.hide_render = False
            obj.location = ((i - (len(mine) - 1) * 0.5) * 1.5, 0.0, 0.0)
            if not obj.data.materials:
                obj.data.materials.append(material)
        span = len(mine) * 1.5 + 0.4
        size = (260 * len(mine) + 100, 520)
        shoot("%s_built_front" % person_id, (0.0, 0.0, 0.45), (1.5, -8.0, 1.2), span, size)
        shoot("%s_built_side" % person_id, (0.0, 0.0, 0.45), (-8.0, -1.5, 0.8), span, size)
        shoot("%s_built_back" % person_id, (0.0, 0.0, 0.45), (-1.5, 8.0, 1.2), span, size)
        for entry in mine:
            entry[0].hide_render = True
            entry[0].location = (0.0, 0.0, 0.0)
    print("PREVIEWS", preview_dir)
