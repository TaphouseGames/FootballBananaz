"""Rigs the static football player mesh and exports it as a skinned GLB.

Run from the project root:

    blender -b --factory-startup --python tools/rig_player.py -- \
        assets/player/source/football_player.fbx assets/player/football_player.glb [preview_dir]

The source mesh is a symmetric T-pose, feet on the origin, facing -Y (Blender
front). Joints are placed from slices of the mesh itself, so the script keeps
working if the model is regenerated with similar proportions.

The exported character faces +Z in Godot; the player scene turns it to +X.
If preview_dir is given, a few test poses are rendered there as PNGs.
"""

import math
import sys

import bpy
from mathutils import Matrix, Vector

HEIGHT = 1.85

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    raise SystemExit("usage: rig_player.py -- <in.fbx> <out.glb> [preview_dir]")
src_path, out_path = argv[0], argv[1]
preview_dir = argv[2] if len(argv) > 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=bpy.path.abspath(src_path))
mesh_obj = next(o for o in bpy.data.objects if o.type == "MESH")
mesh_obj.name = "FootballPlayer"
mesh_obj.data.name = "FootballPlayer"
for mat in mesh_obj.data.materials:
    mat.name = "PlayerSkin"

# Bake the import transform, then normalise: feet on z = 0, HEIGHT tall, centred.
mesh = mesh_obj.data
mesh.transform(mesh_obj.matrix_world)
mesh_obj.matrix_world = Matrix.Identity(4)
zs = [v.co.z for v in mesh.vertices]
xs = [v.co.x for v in mesh.vertices]
scale = HEIGHT / (max(zs) - min(zs))
mesh.transform(Matrix.Translation((-(max(xs) + min(xs)) * 0.5, 0.0, -min(zs))))
mesh.transform(Matrix.Scale(scale, 4))
mesh.update()

verts = [v.co.copy() for v in mesh.vertices]


def h(frac):
    return frac * HEIGHT


def centroid(pred, fallback):
    pts = [v for v in verts if pred(v)]
    if len(pts) < 4:
        return Vector(fallback)
    return sum(pts, Vector()) / len(pts)


def leg_point(z_frac):
    """Centre of the left (+X) leg at a given height."""
    z = h(z_frac)
    c = centroid(lambda v: abs(v.z - z) < h(0.025) and 0.0 < v.x < h(0.16), (h(0.06), 0.0, z))
    return Vector((c.x, c.y, z))


def arm_point(x_frac):
    """Centre of the left (+X) arm at a given distance from the spine."""
    x = h(x_frac)
    c = centroid(lambda v: abs(v.x - x) < h(0.025) and v.z > h(0.6), (x, 0.0, h(0.77)))
    return Vector((x, c.y, c.z))


def torso_point(z_frac):
    z = h(z_frac)
    c = centroid(lambda v: abs(v.z - z) < h(0.025) and abs(v.x) < h(0.16), (0.0, 0.0, z))
    return Vector((0.0, c.y, z))


arm_span = max(v.x for v in verts)
toe_y = min(v.y for v in verts if v.z < h(0.06))

hips = torso_point(0.52)
spine = torso_point(0.60)
chest = torso_point(0.70)
neck = torso_point(0.845)
head = torso_point(0.885)
head_top = Vector((0.0, head.y, HEIGHT))

thigh = leg_point(0.50)
knee = leg_point(0.28)
ankle = leg_point(0.07)
thigh.x = max(thigh.x, h(0.05))
toe = Vector((ankle.x, toe_y, h(0.015)))

shoulder = arm_point(0.13)
elbow = arm_point(0.27)
wrist = arm_point(0.40)
hand_tip = Vector((arm_span, wrist.y, wrist.z))

print("JOINTS", {k: tuple(round(c, 3) for c in v) for k, v in {
    "hips": hips, "spine": spine, "chest": chest, "neck": neck, "head": head,
    "thigh": thigh, "knee": knee, "ankle": ankle, "toe": toe,
    "shoulder": shoulder, "elbow": elbow, "wrist": wrist, "hand_tip": hand_tip}.items()})

arm_data = bpy.data.armatures.new("PlayerRig")
arm_obj = bpy.data.objects.new("PlayerRig", arm_data)
bpy.context.scene.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode="EDIT")


def mirror(v):
    return Vector((-v.x, v.y, v.z))


def add_bone(name, head_pos, tail_pos, parent=None, connect=False):
    bone = arm_data.edit_bones.new(name)
    bone.head = head_pos
    bone.tail = tail_pos
    bone.roll = 0.0
    if parent is not None:
        bone.parent = arm_data.edit_bones[parent]
        bone.use_connect = connect
    return bone


add_bone("Hips", hips, spine)
add_bone("Spine", spine, chest, "Hips", True)
add_bone("Chest", chest, neck, "Spine", True)
add_bone("Neck", neck, head, "Chest", True)
add_bone("Head", head, head_top, "Neck", True)
for side, flip in (("L", False), ("R", True)):
    def p(v, flip=flip):
        return mirror(v) if flip else v.copy()
    add_bone("UpperArm." + side, p(shoulder), p(elbow), "Chest")
    add_bone("Forearm." + side, p(elbow), p(wrist), "UpperArm." + side, True)
    add_bone("Hand." + side, p(wrist), p(hand_tip), "Forearm." + side, True)
    add_bone("Thigh." + side, p(thigh), p(knee), "Hips")
    add_bone("Shin." + side, p(knee), p(ankle), "Thigh." + side, True)
    add_bone("Foot." + side, p(ankle), p(toe), "Shin." + side, True)
bpy.ops.object.mode_set(mode="OBJECT")

# Skin with automatic (heat) weights.
bpy.ops.object.select_all(action="DESELECT")
mesh_obj.select_set(True)
arm_obj.select_set(True)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

weighted = sum(1 for v in mesh.vertices if any(g.weight > 0.0 for g in v.groups))
print("WEIGHTED %d / %d" % (weighted, len(mesh.vertices)))
if weighted >= len(mesh.vertices) * 0.8:
    # Heat weighting skips small loose parts: copy from the nearest skinned vertex.
    done = [v for v in mesh.vertices if any(g.weight > 0.0 for g in v.groups)]
    for v in mesh.vertices:
        if any(g.weight > 0.0 for g in v.groups):
            continue
        nearest = min(done, key=lambda d: (d.co - v.co).length_squared)
        for g in nearest.groups:
            mesh_obj.vertex_groups[g.group].add([v.index], g.weight, "REPLACE")
else:
    print("Heat weights failed; falling back to envelope weights")
    for group in list(mesh_obj.vertex_groups):
        mesh_obj.vertex_groups.remove(group)
    mesh_obj.parent = None
    for mod in list(mesh_obj.modifiers):
        mesh_obj.modifiers.remove(mod)
    for bone in arm_data.bones:
        bone.envelope_distance = h(0.09)
        bone.head_radius = h(0.04)
        bone.tail_radius = h(0.04)
    bpy.ops.object.parent_set(type="ARMATURE_ENVELOPE")

# Keep the two sides from bleeding into each other across the gap between the
# legs, then tidy up.
for v in mesh.vertices:
    if v.co.z > h(0.46):
        continue
    wrong = ".R" if v.co.x > 0.0 else ".L"
    if abs(v.co.x) < h(0.008):
        continue
    for g in v.groups:
        name = mesh_obj.vertex_groups[g.group].name
        if name.endswith(wrong) and name.split(".")[0] in ("Thigh", "Shin", "Foot"):
            g.weight = 0.0
bpy.context.view_layer.objects.active = mesh_obj
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
bpy.ops.object.shade_smooth()

bpy.ops.object.select_all(action="DESELECT")
mesh_obj.select_set(True)
arm_obj.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=bpy.path.abspath(out_path),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_skins=True,
    export_animations=False,
    export_apply=False,
)
print("EXPORTED", out_path)

if preview_dir:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 700
    scene.render.resolution_y = 700
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 3.0
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    def look_from(pos):
        target = Vector((0.0, 0.0, HEIGHT * 0.5))
        cam.location = pos
        cam.rotation_euler = (target - Vector(pos)).to_track_quat("-Z", "Y").to_euler()

    def set_pose(pose):
        """pose: bone -> (axis, degrees) list, rotations in armature space."""
        for pb in arm_obj.pose.bones:
            pb.rotation_mode = "QUATERNION"
            rest = pb.bone.matrix_local.to_3x3()
            delta = Matrix.Identity(3)
            for axis, deg in pose.get(pb.name, []):
                delta = Matrix.Rotation(math.radians(deg), 3, axis) @ delta
            pb.rotation_quaternion = (rest.inverted() @ delta @ rest).to_quaternion()

    poses = {
        "rest": {},
        "run": {
            "Spine": [("X", 15)],
            "Thigh.L": [("X", -55)], "Shin.L": [("X", 70)],
            "Thigh.R": [("X", 30)], "Shin.R": [("X", 60)],
            "UpperArm.L": [("Y", 78), ("X", 40)], "Forearm.L": [("Z", -80)],
            "UpperArm.R": [("Y", -78), ("X", -40)], "Forearm.R": [("Z", 80)],
        },
        "crouch_reach": {
            "Spine": [("X", 30)],
            "Thigh.L": [("X", -75)], "Shin.L": [("X", 100)],
            "Thigh.R": [("X", -75)], "Shin.R": [("X", 100)],
            "UpperArm.L": [("Y", -70)], "UpperArm.R": [("Y", 70)],
        },
    }
    for name, pose in poses.items():
        set_pose(pose)
        for view, pos in (("front", (2.5, -6.0, 2.2)), ("side", (-6.0, -0.5, 1.4))):
            look_from(pos)
            scene.render.filepath = "%s/%s_%s.png" % (preview_dir, name, view)
            bpy.ops.render.render(write_still=True)
    print("PREVIEWS", preview_dir)
