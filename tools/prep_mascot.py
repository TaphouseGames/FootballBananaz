"""Cleans up, rigs and animates a team mascot and exports it as a skinned GLB.

Run from the project root:

    blender -b --factory-startup --python tools/prep_mascot.py -- <team> \
        [tris=5000] [yaw=-90] [texture=1024] [preview=<dir>]

`<team>` is a key of tools/mascots.json (the team's short name in lower case).
Its `source` is the raw Tripo model under assets/stadium/source/tripo/, and
the result is assets/stadium/mascot_<team>.glb.

Every mascot is the same kind of figure: a fat fruit body with a face on it,
thin arms and legs, gloves and sneakers. The model is cleaned up like any
other prop (see prep_prop.py), made one unit tall, and given a skeleton whose
bones have the same names for every mascot:

    Root, Body, UpperArm/Forearm/Hand .L/.R, Thigh/Shin/Foot .L/.R

(.L is the mascot's own left, +X here.) Tripo builds these figures from
separate pieces (body, gloves, shoes, tubes for the limbs), and the joints
are where those pieces meet; a model that came out as one surface is read by
its shape instead (thin limbs, fat body). Where either is fooled, `joints`
in mascots.json overrides a joint by name ("elbow.L": [x, y, z], height = 1,
front = -Y; names as printed after JOINTS).

The same clips are written onto every skeleton: `idle`, `cheer`, `sulk` and
`wave`. They are made from each skeleton's own rest pose, so the arms end up
in the same places whatever pose the model was generated in.

With `preview`, the rest pose and a few frames of each clip are rendered
there as PNGs.
"""

import json
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "assets", "stadium", "source", "tripo")
OUT_DIR = os.path.join(ROOT, "assets", "stadium")
FPS = 30

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 1:
    raise SystemExit("usage: prep_mascot.py -- <team> [tris=N] [yaw=deg] [texture=px] [preview=dir]")
team = argv[0]
options = dict(arg.split("=", 1) for arg in argv[1:])
max_tris = int(options.get("tris", 5000))
yaw = float(options.get("yaw", -90.0))
texture_size = int(options.get("texture", 1024))
preview_dir = options.get("preview")

with open(os.path.join(ROOT, "tools", "mascots.json"), encoding="utf-8") as handle:
    entry = json.load(handle)[team]
if not entry.get("source"):
    raise SystemExit("mascots.json: %s has no source model yet" % team)
src_path = os.path.join(SOURCE_DIR, entry["source"])
out_path = os.path.join(OUT_DIR, "mascot_%s.glb" % team)
overrides = entry.get("joints", {})
name = "Mascot" + team.capitalize()

# --- Clean-up (as prep_prop.py) -------------------------------------------------------

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src_path)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body_obj = bpy.context.view_layer.objects.active
body_obj.name = name
body_obj.data.name = name
mesh = body_obj.data
world = body_obj.matrix_world.copy()
body_obj.parent = None
mesh.transform(world)
body_obj.matrix_world = Matrix.Identity(4)
for o in list(bpy.data.objects):
    if o != body_obj:
        bpy.data.objects.remove(o)
for material in mesh.materials:
    material.name = name

if yaw != 0.0:
    mesh.transform(Matrix.Rotation(math.radians(yaw), 4, "Z"))


def bounds():
    co = np.array([v.co for v in mesh.vertices])
    return Vector(co.min(0)), Vector(co.max(0))


# Feet on the ground, the middle of the footprint on the origin, one unit tall.
lo, hi = bounds()
mesh.transform(Matrix.Translation(Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))))
mesh.transform(Matrix.Scale(1.0 / (hi.z - lo.z), 4))

mesh.calc_loop_triangles()
tris = len(mesh.loop_triangles)
print("TRIS", tris)
if tris > max_tris:
    mod = body_obj.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = max_tris / tris
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print("DECIMATED")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
# Vertices doubled along texture seams are joined, so that each piece is whole.
bpy.ops.mesh.remove_doubles(threshold=1e-5)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.shade_smooth()
mesh.calc_loop_triangles()
lo, hi = bounds()
print("SIZE", tuple(round(c, 3) for c in hi - lo), "TRIS", len(mesh.loop_triangles))

for image in bpy.data.images:
    if image.size[0] > texture_size or image.size[1] > texture_size:
        image.scale(texture_size, texture_size)
        print("RESIZED", image.name)

# --- The pieces of the model ----------------------------------------------------------

# Tripo builds these figures from separate pieces: the body, two gloves, two
# shoes, a few tubes for each limb, and small ones (stem, eyes, laces). Which
# piece is which, and where they touch, gives the joints and the weights.
vert_cos = [v.co.copy() for v in mesh.vertices]
vert_array = np.array(vert_cos)
piece_of = list(range(len(vert_cos)))


def top(i):
    while piece_of[i] != i:
        piece_of[i] = piece_of[piece_of[i]]
        i = piece_of[i]
    return i


for edge in mesh.edges:
    a, b = top(edge.vertices[0]), top(edge.vertices[1])
    if a != b:
        piece_of[a] = b
ids = {}
vert_piece = np.array([ids.setdefault(top(i), len(ids)) for i in range(len(vert_cos))])
piece_count = len(ids)

# Points spread evenly over the surface, each knowing its piece.
random.seed(7)
total_area = sum(t.area for t in mesh.loop_triangles)
points = []
point_piece = []
point_normal = []
piece_tris = [[] for _ in range(piece_count)]
for tri in mesh.loop_triangles:
    piece = int(vert_piece[tri.vertices[0]])
    piece_tris[piece].append(tuple(tri.vertices))
    a, b, c = (vert_cos[i] for i in tri.vertices)
    for _ in range(max(1, round(40000 * tri.area / total_area))):
        u, v = random.random(), random.random()
        if u + v > 1.0:
            u, v = 1.0 - u, 1.0 - v
        points.append(a + (b - a) * u + (c - a) * v)
        point_piece.append(piece)
        point_normal.append(tri.normal.copy())
points = np.array(points)
point_piece = np.array(point_piece)


class Piece:
    def __init__(self, index):
        self.index = index
        self.points = points[point_piece == index]
        self.lo = self.points.min(0)
        self.hi = self.points.max(0)
        self.centre = (self.lo + self.hi) * 0.5
        self.volume = float(np.prod(np.maximum(self.hi - self.lo, 1e-4)))
        self.tree = BVHTree.FromPolygons(vert_cos, piece_tris[index])
        self.some = [Vector(p) for p in self.points[::max(1, len(self.points) // 150)]]


pieces = [Piece(i) for i in range(piece_count) if piece_tris[i]]
TOUCH = 0.012
_gaps = {}


def gap(a, b):
    """The least distance between two pieces."""
    key = (min(a.index, b.index), max(a.index, b.index))
    if key not in _gaps:
        apart = np.maximum(np.maximum(a.lo - b.hi, b.lo - a.hi), 0.0)
        if float(np.linalg.norm(apart)) > 0.1:
            _gaps[key] = 1.0
        else:
            _gaps[key] = min(min(b.tree.find_nearest(p)[3] for p in a.some),
                             min(a.tree.find_nearest(p)[3] for p in b.some))
    return _gaps[key]


def nearest_points(piece, other, share=0.12):
    """The middle of the part of `piece` that is nearest to `other`."""
    dist = np.array([other.tree.find_nearest(Vector(p))[3] for p in piece.points])
    return Vector(piece.points[dist <= np.percentile(dist, share * 100.0)].mean(0))


def path(start, goal, blocked, touch):
    """The pieces that join `start` to `goal`: the limb's tubes.

    Of all the ways through touching pieces, the one through the least bulk,
    so that a fist resting on a sweatband does not make the sweatband an arm.
    A way straight from the body to the glove only counts if there is no other.
    """
    best = {start.index: (0.0, None)}
    todo = [start]
    while todo:
        here = min(todo, key=lambda p: best[p.index][0])
        todo.remove(here)
        if here is goal:
            break
        for other in pieces:
            if other is here or (other in blocked and other is not goal):
                continue
            if (here is start and other is goal) or gap(here, other) >= touch:
                continue
            cost = best[here.index][0] + (0.0 if other is goal else other.volume + 1e-6)
            if other.index not in best or cost < best[other.index][0]:
                best[other.index] = (cost, here)
                if other not in todo:
                    todo.append(other)
    if goal.index not in best:
        return None
    chain = []
    step = best[goal.index][1]
    while step is not start:
        chain.append(step)
        step = best[step.index][1]
    return chain[::-1]


def chain_weights(pts, a, b, c):
    """How much of each point follows the second bone of a limb a-b-c."""
    pts = np.asarray(pts)
    a, b, c = (np.array(v) for v in (a, b, c))
    first, second = b - a, c - b
    t1 = np.clip(((pts - a) @ first) / max(first @ first, 1e-9), 0.0, 1.0)
    t2 = np.clip(((pts - b) @ second) / max(second @ second, 1e-9), 0.0, 1.0)
    d1 = np.linalg.norm(pts - (a + t1[:, None] * first), axis=1)
    d2 = np.linalg.norm(pts - (b + t2[:, None] * second), axis=1)
    along = np.where(d1 <= d2, (t1 - 1.0) * np.linalg.norm(first), t2 * np.linalg.norm(second))
    return np.clip(along / 0.03 + 0.5, 0.0, 1.0)


BONES = ["Body"] + [b + s for s in (".L", ".R") for b in ("UpperArm", "Forearm", "Hand", "Thigh", "Shin", "Foot")]
weights = np.zeros((len(vert_cos), len(BONES)))
joints = {}
body_x = body_y = body_top = crotch = None


def from_pieces():
    """Joints and weights from the pieces; False if the model is not built
    that way (one fused surface, say)."""
    global body_x, body_y, body_top, crotch
    if len(pieces) < 5:
        return False
    body = max(pieces, key=lambda p: p.volume)
    grounded = sorted((p for p in pieces if p is not body and p.lo[2] < 0.04), key=lambda p: -p.volume)[:2]
    if len(grounded) < 2:
        return False
    shoes = dict(zip(("L", "R"), sorted(grounded, key=lambda p: -p.centre[0])))
    shoe_top = max(p.hi[2] for p in grounded)
    reach = (body.hi[0] - body.lo[0]) * 0.4
    rest = [p for p in pieces if p is not body and p not in grounded and p.centre[2] > shoe_top]
    out = [p for p in rest if abs(p.centre[0] - body.centre[0]) > reach]
    hands = sorted(out if len(out) >= 2 else rest, key=lambda p: -p.volume)[:2]
    if len(hands) < 2:
        return False
    gloves = dict(zip(("L", "R"), sorted(hands, key=lambda p: -p.centre[0])))
    ends = [body] + grounded + hands

    body_x, body_y = float(body.centre[0]), float(body.centre[1])
    body_top = float(body.hi[2])
    role = {body.index: ("Body", None)}
    limbs = {}
    for side in ("L", "R"):
        for end, names, keys in ((gloves[side], ("UpperArm", "Forearm", "Hand"), ("shoulder", "elbow", "wrist")),
                                 (shoes[side], ("Thigh", "Shin", "Foot"), ("hip", "knee", "ankle"))):
            chain = path(body, end, ends, TOUCH)
            if chain:
                a = nearest_points(chain[0], body)
                c = nearest_points(chain[-1], end)
                if len(chain) >= 2:
                    half = len(chain) // 2
                    b = nearest_points(chain[half - 1], chain[half])
                else:
                    along = (chain[0].points - np.array(a)) @ np.array((c - a).normalized())
                    middle = np.abs(along - (c - a).length * 0.5) < (c - a).length * 0.08
                    b = Vector(chain[0].points[middle].mean(0)) if middle.any() else (a + c) * 0.5
            else:
                # The glove or shoe sits right on the body: a short stub.
                # The limb is part of the glove or shoe (or there is none):
                # short bones from where that piece meets the body, into it.
                print("NOTE: no separate limb pieces between the body and %s.%s; gaps to the body %s" % (
                    names[2], side, sorted(round(gap(body, p), 3) for p in pieces if p is not body)[:8]))
                a = nearest_points(end, body)
                into = Vector(end.centre) - a
                b = a + into * 0.2
                c = a + into * 0.4
            for key, value in zip(keys, (a, b, c)):
                joints[key + "." + side] = value
            limbs[names[0] + "." + side] = (a, b, c, names[0] + "." + side, names[1] + "." + side)
            for piece in chain or []:
                role[piece.index] = ("limb", names[0] + "." + side)
            role[end.index] = (names[2] + "." + side, None)
    crotch = min(joints["hip.L"].z, joints["hip.R"].z)

    # The small pieces go with what they sit on (laces with the shoe, a cuff
    # with the glove), and with the body if they touch it or nothing.
    waiting = [p for p in pieces if p.index not in role]
    while waiting:
        placed = []
        for piece in waiting:
            touching = sorted((gap(piece, other), other.index) for other in pieces if other.index in role)
            if not touching or touching[0][0] >= TOUCH:
                continue
            if gap(piece, body) < TOUCH:
                placed.append((piece, ("Body", None)))
            else:
                placed.append((piece, role[touching[0][1]]))
        if not placed:
            break
        for piece, what in placed:
            role[piece.index] = what
        waiting = [p for p in waiting if p.index not in role]
    for piece in waiting:
        role[piece.index] = ("Body", None)

    for piece in pieces:
        bone, limb = role[piece.index]
        chosen = np.nonzero(vert_piece == piece.index)[0]
        if bone != "limb":
            weights[chosen, BONES.index(bone)] = 1.0
            continue
        a, b, c, first, second = limbs[limb]
        lower = chain_weights(vert_array[chosen], a, b, c)
        weights[chosen, BONES.index(first)] = 1.0 - lower
        weights[chosen, BONES.index(second)] = lower
    print("PIECES %d: body %d, gloves %s, shoes %s" % (
        len(pieces), body.index, [gloves[s].index for s in "LR"], [shoes[s].index for s in "LR"]))
    return True


def from_shape():
    """The same for a model in one piece: the limbs are the thin parts, the
    body the fat one. Rougher; check the previews and override joints."""
    global body_x, body_y, body_top, crotch
    whole = BVHTree.FromPolygons(vert_cos, [t for tris in piece_tris for t in tris])
    thickness = []
    for p, normal in zip(points, point_normal):
        hit = whole.ray_cast(Vector(p) - normal * 1e-4, -normal)
        thickness.append(hit[3] if hit[0] is not None else 1.0)
    thickness = np.array(thickness)
    body_thickness = float(np.percentile(thickness, 75))
    thin_points = points[thickness < min(0.3 * body_thickness, 0.09)]
    core = points[thickness > 0.6 * body_thickness]
    core_tree = KDTree(len(core[::3]))
    for i, p in enumerate(core[::3]):
        core_tree.insert(p, i)
    core_tree.balance()
    body_x, body_y = float(core[:, 0].mean()), float(core[:, 1].mean())
    body_top = float(core[:, 2].max())

    def spans(xs, width=0.02):
        xs = np.sort(xs)
        out = []
        start = 0
        for i in range(1, len(xs) + 1):
            if i == len(xs) or xs[i] - xs[i - 1] > width:
                out.append((xs[start], xs[i - 1], i - start))
                start = i
        return out

    # The crotch: going up from the shoes, the first height at which the
    # model covers the point midway between the feet.
    step = 0.015
    low = points[(points[:, 2] > 0.02) & (points[:, 2] < 0.08)]
    feet = sorted(spans(low[:, 0]), key=lambda s: -s[2])[:2]
    mid_x = sum((s[0] + s[1]) * 0.5 for s in feet) / len(feet) if len(feet) == 2 else body_x

    def covers_middle(z):
        xs = points[np.abs(points[:, 2] - z) < step * 0.5][:, 0]
        return any(s[0] < mid_x - 0.005 and s[1] > mid_x + 0.005 for s in spans(xs))

    crotch = 0.3
    apart = False
    z = 0.03
    while z < 0.7:
        if not covers_middle(z):
            apart = True
        elif apart and covers_middle(z + step):
            crotch = z
            break
        z += step

    def leg(sign):
        # Going down from the crotch, the leg ends where it widens into the shoe.
        side_points = points[(points[:, 2] < crotch) & ((points[:, 0] - mid_x) * sign > 0.0)]
        rows = []
        narrowest = None
        z = crotch - 0.01
        while z > 0.02:
            part = side_points[np.abs(side_points[:, 2] - z) < 0.006]
            if len(part) >= 6:
                centre = part[:, :2].mean(0)
                radius = float(np.sqrt(((part[:, :2] - centre) ** 2).sum(1).mean()))
                if narrowest is not None and len(rows) >= 2 and radius > 1.8 * narrowest:
                    break
                narrowest = radius if narrowest is None else min(narrowest, radius)
                rows.append(Vector((centre[0], centre[1], z)))
            z -= 0.01
        if len(rows) < 2:
            hip = Vector((mid_x + sign * 0.06, body_y, crotch))
            ankle = Vector((mid_x + sign * 0.08, body_y, 0.1))
            return hip, (hip + ankle) * 0.5, ankle
        return rows[0], rows[len(rows) // 2], rows[-1]

    def arm(group):
        # From the end on the body outwards, to where it widens into the glove.
        centre = group.mean(0)
        axis = np.linalg.svd(group - centre, full_matrices=False)[2][0]
        along = (group - centre) @ axis
        end_a = Vector(group[along <= np.percentile(along, 6)].mean(0))
        end_b = Vector(group[along >= np.percentile(along, 94)].mean(0))
        start = np.array(end_a if core_tree.find(end_a)[2] <= core_tree.find(end_b)[2] else end_b)
        dist = np.linalg.norm(group - start, axis=1)
        bins = 14
        index = np.minimum((dist / dist.max() * bins).astype(int), bins - 1)
        rows = [group[index == i] for i in range(bins)]
        filled = [i for i in range(bins) if len(rows[i]) >= 4]
        widths = {i: float(np.sqrt(((rows[i] - rows[i].mean(0)) ** 2).sum(1).mean())) for i in filled}
        base = float(np.median([widths[i] for i in filled[1:6]] or [0.02]))
        last = filled[-1]
        for i in filled:
            if i >= 5 and widths[i] > 1.7 * base:
                last = max(j for j in filled if j < i)
                break
        middle = min((i for i in filled if i <= last), key=lambda i: abs(i - (filled[0] + last) * 0.5))
        return tuple(Vector(rows[i].mean(0)) for i in (filled[0], middle, last))

    def clusters(pts, cell=0.025):
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

    half_width = float(np.percentile(np.abs(core[:, 0] - body_x), 95))
    groups = [g for g in clusters(thin_points[thin_points[:, 2] > crotch + 0.03]) if len(g) > 40]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        joints["hip." + side], joints["knee." + side], joints["ankle." + side] = leg(sign)
        # The arm is the longest thin part well out to this side (not the
        # stem, a leaf or the mouth, which sit near the middle).
        best = None
        best_reach = 0.1
        for group in groups:
            out = (float(group[:, 0].mean()) - body_x) * sign
            reach = float(np.linalg.norm(group.max(0) - group.min(0)))
            if out > 0.75 * half_width and reach > best_reach:
                best, best_reach = group, reach
        if best is not None:
            shoulder, elbow, wrist = arm(best)
        else:
            print("WARNING: no thin arm on side", side)
            shoulder = Vector((body_x + sign * half_width, body_y, 0.6))
            elbow = shoulder + Vector((sign * 0.1, 0.0, 0.08))
            wrist = elbow + Vector((sign * 0.05, 0.0, 0.12))
        joints["shoulder." + side], joints["elbow." + side], joints["wrist." + side] = shoulder, elbow, wrist

    # Weights by distance: to the body by how far a vertex is from the fat
    # part of the surface, to a limb bone by how far it is outside a tube
    # round that bone (wider for the glove and the shoe).
    tube = {"UpperArm": 0.03, "Forearm": 0.03, "Hand": 0.08, "Thigh": 0.03, "Shin": 0.03, "Foot": 0.07}
    ends = {}
    for side in ("L", "R"):
        s, e, w = (joints[k + side] for k in ("shoulder.", "elbow.", "wrist."))
        h, k, a = (joints[k + side] for k in ("hip.", "knee.", "ankle."))
        ends["UpperArm." + side], ends["Forearm." + side] = (s, e), (e, w)
        ends["Hand." + side] = (w, w + (w - e).normalized() * 0.1)
        ends["Thigh." + side], ends["Shin." + side] = (h, k), (k, a)
        ends["Foot." + side] = (a, Vector((a.x, a.y - 0.12, 0.02)))
    outside = np.zeros((len(vert_cos), len(BONES)))
    outside[:, 0] = [core_tree.find(v)[2] for v in vert_cos]
    for column, bone in enumerate(BONES[1:], 1):
        head = np.array(ends[bone][0])
        along = np.array(ends[bone][1]) - head
        t = np.clip(((vert_array - head) @ along) / (along @ along), 0.0, 1.0)
        away = np.linalg.norm(vert_array - (head + t[:, None] * along), axis=1)
        # The small extra lets the body keep its own skin where a limb joins it.
        outside[:, column] = np.maximum(away - tube[bone.split(".")[0]], 0.0) + 0.004
    weights[:] = 1.0 / (outside + 0.004) ** 4
    weights[weights < weights.max(1, keepdims=True) * 0.02] = 0.0
    weights[:] = weights / weights.sum(1, keepdims=True)
    print("ONE PIECE: joints and weights from the shape")


if not from_pieces():
    joints.clear()
    weights[:] = 0.0
    from_shape()
for key, value in overrides.items():
    if key not in joints:
        raise SystemExit("mascots.json: unknown joint %s (have %s)" % (key, ", ".join(sorted(joints))))
    joints[key] = Vector(value)
print("JOINTS", json.dumps({k: [round(c, 3) for c in v] for k, v in sorted(joints.items())}))

# --- Skeleton and skin ----------------------------------------------------------------

arm_data = bpy.data.armatures.new("MascotRig")
rig = bpy.data.objects.new("MascotRig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")


def add_bone(bone_name, head, tail, parent=None, connect=False):
    bone = arm_data.edit_bones.new(bone_name)
    bone.head = head
    bone.tail = tail
    bone.roll = 0.0
    if parent is not None:
        bone.parent = arm_data.edit_bones[parent]
        bone.use_connect = connect
    return bone


add_bone("Root", Vector((body_x, body_y, 0.0)), Vector((body_x, body_y, 0.08)))
add_bone("Body", Vector((body_x, body_y, crotch)), Vector((body_x, body_y, body_top)), "Root")
for side in ("L", "R"):
    shoulder, elbow, wrist = (joints[k + side] for k in ("shoulder.", "elbow.", "wrist."))
    hip, knee, ankle = (joints[k + side] for k in ("hip.", "knee.", "ankle."))
    add_bone("UpperArm." + side, shoulder, elbow, "Body")
    add_bone("Forearm." + side, elbow, wrist, "UpperArm." + side, True)
    add_bone("Hand." + side, wrist, wrist + (wrist - elbow).normalized() * 0.1, "Forearm." + side, True)
    # The legs hang from the root, so that the feet stay put when the body sways.
    add_bone("Thigh." + side, hip, knee, "Root")
    add_bone("Shin." + side, knee, ankle, "Thigh." + side, True)
    add_bone("Foot." + side, ankle, Vector((ankle.x, ankle.y - 0.12, 0.02)), "Shin." + side, True)
bpy.ops.object.mode_set(mode="OBJECT")

groups = {bone: body_obj.vertex_groups.new(name=bone) for bone in BONES}
for index in range(len(vert_cos)):
    for column in np.nonzero(weights[index])[0]:
        groups[BONES[column]].add([index], float(weights[index, column]), "REPLACE")
body_obj.parent = rig
body_obj.modifiers.new("Armature", "ARMATURE").object = rig

# --- Clips ----------------------------------------------------------------------------

for bone in rig.pose.bones:
    bone.rotation_mode = "QUATERNION"
rig.animation_data_create()


def arm_turn(side, from_up):
    """Degrees about Y that bring the arm to `from_up` degrees off straight up
    (to its own side), whatever way it points at rest."""
    sign = 1.0 if side == "L" else -1.0
    d = joints["wrist." + side] - joints["shoulder." + side]
    return sign * from_up - math.degrees(math.atan2(d.x, d.z))


def bone_length(bone_name):
    return rig.data.bones[bone_name].length


def crouch(depth):
    """Bent knees with the feet flat, and how far the root has to come down."""
    drop = sum(bone_length(b + ".L") for b in ("Thigh", "Shin")) * (1.0 - math.cos(math.radians(depth)))
    pose = {}
    for side in ("L", "R"):
        pose["Thigh." + side] = [("X", -depth)]
        pose["Shin." + side] = [("X", 2.0 * depth)]
        pose["Foot." + side] = [("X", -depth)]
    return pose, -drop


def arms(left_from_up, right_from_up):
    return {
        "UpperArm.L": [("Y", arm_turn("L", left_from_up))],
        "UpperArm.R": [("Y", arm_turn("R", right_from_up))],
    }


REST_L = math.degrees(math.atan2((joints["wrist.L"] - joints["shoulder.L"]).x, (joints["wrist.L"] - joints["shoulder.L"]).z))
REST_R = -math.degrees(math.atan2((joints["wrist.R"] - joints["shoulder.R"]).x, (joints["wrist.R"] - joints["shoulder.R"]).z))
deep, deep_drop = crouch(38.0)
soft, soft_drop = crouch(18.0)

# name -> [(frame, pose, root height)], pose: bone -> [(axis, degrees)] in the
# rig's space, applied in order. +X leans forward, +Y lowers the left arm.
CLIPS = {
    "idle": [
        (0, {"Body": [("Y", 3.0)], **arms(REST_L + 4.0, REST_R - 4.0)}, 0.0),
        (30, {"Body": [("Y", -3.0)], **arms(REST_L - 4.0, REST_R + 4.0)}, 0.0),
        (60, {"Body": [("Y", 3.0)], **arms(REST_L + 4.0, REST_R - 4.0)}, 0.0),
    ],
    "cheer": [
        (0, {}, 0.0),
        (7, {**deep, "Body": [("X", 9.0)], **arms(95.0, 95.0)}, deep_drop),
        (14, {"Body": [("X", -5.0)], **arms(28.0, 28.0)}, 0.24),
        (21, {**soft, "Body": [("X", 4.0)], **arms(40.0, 40.0)}, soft_drop),
        (28, {}, 0.0),
        (36, {}, 0.0),
    ],
    "sulk": [
        (0, {"Body": [("X", 13.0), ("Y", 2.0)], **arms(168.0, 168.0)}, 0.0),
        (30, {"Body": [("X", 15.0), ("Y", -2.0)], **arms(172.0, 172.0)}, 0.0),
        (60, {"Body": [("X", 13.0), ("Y", 2.0)], **arms(168.0, 168.0)}, 0.0),
    ],
    "wave": [
        (frame, {"Body": [("Y", 2.0)], **arms(REST_L, 25.0), "Forearm.R": [("Y", swing)]}, 0.0)
        for frame, swing in ((0, -22.0), (10, 22.0), (20, -22.0), (30, 22.0), (40, -22.0))
    ],
}


def stride(frame, length):
    """One frame of the run: the legs half a turn apart, each arm swinging
    against its own leg, and the body up when the legs are furthest apart.
    A hanging limb comes forward with -X."""
    turn = 2.0 * math.pi * frame / length
    pose = {"Body": [("X", 13.0), ("Y", 4.0 * math.sin(turn))]}
    for side, at in (("L", turn), ("R", turn + math.pi)):
        ahead = math.sin(at)
        # The knee folds while the foot comes through under the body.
        fold = max(0.0, math.cos(at))
        pose["Thigh." + side] = [("X", -8.0 - 32.0 * ahead)]
        pose["Shin." + side] = [("X", 18.0 + 50.0 * fold)]
        pose["Foot." + side] = [("X", -10.0 * ahead)]
        pose["UpperArm." + side] = [("Y", arm_turn(side, 150.0)), ("X", 32.0 * ahead)]
    return (frame, pose, 0.04 * abs(math.sin(turn)))


RUN_FRAMES = 16
CLIPS["run"] = [stride(frame, RUN_FRAMES) for frame in range(0, RUN_FRAMES + 1, 2)]


def set_pose(pose, height):
    for bone in rig.pose.bones:
        rest = bone.bone.matrix_local.to_3x3()
        delta = Matrix.Identity(3)
        for axis, degrees in pose.get(bone.name, []):
            delta = Matrix.Rotation(math.radians(degrees), 3, axis) @ delta
        bone.rotation_quaternion = (rest.inverted() @ delta @ rest).to_quaternion()
    # The root bone points up, so its own Y is the height.
    rig.pose.bones["Root"].location = (0.0, height, 0.0)


for clip_name, keys in CLIPS.items():
    action = bpy.data.actions.new(clip_name)
    rig.animation_data.action = action
    previous = {}
    for frame, pose, height in keys:
        set_pose(pose, height)
        for bone in rig.pose.bones:
            # Keep to one side of the quaternion sphere between keys.
            q = bone.rotation_quaternion.copy()
            if bone.name in previous and previous[bone.name].dot(q) < 0.0:
                q.negate()
                bone.rotation_quaternion = q
            previous[bone.name] = q
            bone.keyframe_insert("rotation_quaternion", frame=frame)
        rig.pose.bones["Root"].keyframe_insert("location", frame=frame)
    track = rig.animation_data.nla_tracks.new()
    track.name = clip_name
    track.strips.new(clip_name, keys[0][0], action)
    track.mute = True
    rig.animation_data.action = None
set_pose({}, 0.0)

scene = bpy.context.scene
scene.render.fps = FPS


def show(clip_name, frame):
    """Poses the rig as `clip_name` at `frame` (None: the rest pose)."""
    for track in rig.animation_data.nla_tracks:
        track.mute = track.name != clip_name
    if clip_name is None:
        set_pose({}, 0.0)
    scene.frame_set(frame)


for track in rig.animation_data.nla_tracks:
    track.mute = False
bpy.ops.object.select_all(action="DESELECT")
body_obj.select_set(True)
rig.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_image_format="JPEG",
    export_skins=True,
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_apply=False,
)
print("EXPORTED", out_path)

if preview_dir:
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 500
    scene.render.resolution_y = 500
    scene.render.film_transparent = True
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.7
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    aim = Vector((0.0, 0.0, 0.6))
    # The front is -Y here, +Z in Godot.
    views = {"front": Vector((0.0, -6.0, 0.0)), "angle": Vector((3.6, -6.0, 2.4))}
    shots = [(None, 0, "front"), (None, 0, "angle"), ("idle", 30, "front"), ("cheer", 7, "angle"),
             ("cheer", 14, "front"), ("sulk", 0, "front"), ("sulk", 0, "angle"), ("wave", 10, "front"),
             ("run", 4, "angle"), ("run", 12, "angle"), ("run", 4, "front")]
    for clip_name, frame, view in shots:
        show(clip_name, frame)
        cam.location = aim + views[view]
        cam.rotation_euler = (-views[view]).to_track_quat("-Z", "Y").to_euler()
        label = "rest" if clip_name is None else "%s%02d" % (clip_name, frame)
        scene.render.filepath = os.path.join(preview_dir, "%s_%s_%s.png" % (team, label, view))
        bpy.ops.render.render(write_still=True)
    # The bones as red sticks, seen through the model.
    show(None, 0)
    curve = bpy.data.curves.new("Bones", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.008
    for bone in arm_data.bones:
        spline = curve.splines.new("POLY")
        spline.points.add(1)
        spline.points[0].co = (*bone.head_local, 1.0)
        spline.points[1].co = (*bone.tail_local, 1.0)
    red = bpy.data.materials.new("Bones")
    red.diffuse_color = (1.0, 0.0, 0.0, 1.0)
    curve.materials.append(red)
    scene.collection.objects.link(bpy.data.objects.new("Bones", curve))
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_xray = True
    scene.display.shading.xray_alpha = 0.35
    for view in ("front", "angle"):
        cam.location = aim + views[view]
        cam.rotation_euler = (-views[view]).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(preview_dir, "%s_bones_%s.png" % (team, view))
        bpy.ops.render.render(write_still=True)
    print("PREVIEWS", preview_dir)
