"""Turns a rigged character into the fans that fill the stands and exports a GLB.

Run from the project root:

    blender -b --factory-startup --python tools/prep_fan.py -- \
        assets/player/dudeman.glb assets/stadium/fan.glb [near=2600] [mid=800] [far=260] [preview=dir]

The source is a character as the game's players use it (see prep_dudeman.py):
a T-pose, facing -Y in Blender, with the bones Thigh/Shin/UpperArm/Forearm
".L" and ".R". Any model rigged that way will do; to change the crowd, run this
on another file.

The crowd is drawn with MultiMeshes, which cannot have skeletons, so the
character is posed here and the pose baked into plain meshes:

    Fan      sitting, arms down (they swing up in a cheer)
    FanSign  sitting, arms up (holding a sign, which the Stadium script adds)

each at three levels of detail: the name alone (at most `near` triangles),
with "Mid" on the end and with "Far" on the end. The seat is at y = 0 in
Godot, the fan faces +Z, and the size is the source's (the Stadium script
scales fans to match the players).

The texture and its UVs are kept. What the crowd shader needs to move the
arms is written into the second UV set (as Godot reads it):

    UV2.x  0.5 on the body; towards 1 the more a vertex belongs to the left
           arm, towards 0 the more it belongs to the right one (Fan only)
    UV2.y  how much a vertex belongs to an arm that is held up (FanSign only)

and where the arms turn is written into each object's custom properties
(glTF "extras"), in Godot's axes and the mesh's units:

    shoulder  [x of the left shoulder, height above the seat, z]
    hand      [x of the left hand, height above the seat, z]
"""

import math
import sys

import bpy
from mathutils import Matrix, Vector

TIERS = (("", "near", 2600), ("Mid", "mid", 800), ("Far", "far", 260))
# Bone -> (axis, degrees) list, rotations in the armature's space.
SITTING = {
    "Thigh.L": [("X", -85)], "Shin.L": [("X", 88)],
    "Thigh.R": [("X", -85)], "Shin.R": [("X", 88)],
}
POSES = {
    "Fan": dict(SITTING, **{
        "UpperArm.L": [("Y", 76)], "UpperArm.R": [("Y", -76)],
    }),
    "FanSign": dict(SITTING, **{
        "UpperArm.L": [("Y", -72)], "UpperArm.R": [("Y", 72)],
    }),
}
HELD = ("FanSign",)
# How far below the hip joints the seat is, as a share of the height.
SEAT_DROP = 0.055

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    raise SystemExit("usage: prep_fan.py -- <in.glb> <out.glb> [near=N] [mid=N] [far=N] [preview=dir]")
src_path, out_path = argv[0], argv[1]
limits = {key: tris for _, key, tris in TIERS}
preview_dir = None
for arg in argv[2:]:
    key, _, value = arg.partition("=")
    if key == "preview":
        preview_dir = value
    elif key in limits:
        limits[key] = int(value)
    else:
        raise SystemExit("unknown argument: %s" % arg)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=bpy.path.abspath(src_path))
source = next(o for o in bpy.data.objects if o.type == "MESH")
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
missing = [name for name in POSES["Fan"] if name not in rig.data.bones]
if missing:
    raise SystemExit("the rig is missing bones: %s" % ", ".join(missing))
height = max((source.matrix_world @ v.co).z for v in source.data.vertices)


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def copy_of(obj, name):
    twin = obj.copy()
    twin.data = obj.data.copy()
    twin.name = name
    twin.data.name = name
    bpy.context.scene.collection.objects.link(twin)
    return twin


def set_pose(pose):
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
        rest = bone.bone.matrix_local.to_3x3()
        delta = Matrix.Identity(3)
        for axis, degrees in pose.get(bone.name, []):
            delta = Matrix.Rotation(math.radians(degrees), 3, axis) @ delta
        bone.rotation_quaternion = (rest.inverted() @ delta @ rest).to_quaternion()
    bpy.context.view_layer.update()


def arm_weights(obj):
    """Per vertex: how much it belongs to the left arm minus how much to the right."""
    sides = {}
    for side, sign in (("L", 1.0), ("R", -1.0)):
        upper = rig.data.bones["UpperArm." + side]
        for bone in [upper] + list(upper.children_recursive):
            group = obj.vertex_groups.get(bone.name)
            if group is not None:
                sides[group.index] = sign
    weights = []
    for vert in obj.data.vertices:
        total = sum(g.weight for g in vert.groups)
        arm = sum(g.weight * sides.get(g.group, 0.0) for g in vert.groups)
        weights.append(arm / total if total > 0.0 else 0.0)
    return weights


def to_godot(point):
    return [round(point.x, 4), round(point.z, 4), round(-point.y, 4)]


# One copy of the character per level of detail, thinned out while it still
# stands in its rest pose (the bone weights come through that).
thinned = []
for suffix, key, _ in TIERS:
    obj = copy_of(source, "Thin" + suffix)
    select_only(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode="OBJECT")
    tris = len(obj.data.polygons)
    if tris > limits[key]:
        modifier = obj.modifiers.new("Thin", "DECIMATE")
        modifier.ratio = limits[key] / tris
        bpy.ops.object.modifier_move_to_index(modifier=modifier.name, index=0)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    thinned.append((suffix, obj))

built = []
for column, (kind, pose) in enumerate(POSES.items()):
    set_pose(pose)
    hips = (rig.matrix_world @ rig.pose.bones["Thigh.L"].head).z
    drop = Vector((0.0, 0.0, hips - SEAT_DROP * height))
    shoulder = rig.matrix_world @ rig.pose.bones["UpperArm.L"].head - drop
    hand = rig.matrix_world @ rig.pose.bones["Hand.L"].tail - drop
    for row, (suffix, thin) in enumerate(thinned):
        obj = copy_of(thin, kind + suffix)
        weights = arm_weights(obj)
        select_only(obj)
        for modifier in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.parent = None
        obj.matrix_world = Matrix.Translation(-drop) @ obj.matrix_world
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        obj.vertex_groups.clear()
        mesh = obj.data
        motion = mesh.uv_layers.new(name="Motion")
        for loop in mesh.loops:
            weight = weights[loop.vertex_index]
            if kind in HELD:
                # Blender's v runs the other way from Godot's.
                motion.data[loop.index].uv = (0.5, 1.0 - abs(weight))
            else:
                motion.data[loop.index].uv = (0.5 + 0.5 * weight, 1.0)
        bpy.ops.object.shade_smooth()
        obj["shoulder"] = to_godot(shoulder)
        obj["hand"] = to_godot(hand)
        built.append((obj, column, row))
        print("BUILT", obj.name, "tris", len(mesh.polygons), "shoulder", obj["shoulder"], "hand", obj["hand"])

bpy.ops.object.select_all(action="DESELECT")
for obj, _, _ in built:
    obj.select_set(True)
bpy.context.view_layer.objects.active = built[0][0]
bpy.ops.export_scene.gltf(
    filepath=bpy.path.abspath(out_path),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=True,
    export_skins=False,
    export_animations=False,
    export_extras=True,
)
print("EXPORTED", out_path)

if preview_dir:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    for obj in (source, rig) + tuple(thin for _, thin in thinned):
        obj.hide_render = True
    for obj, column, row in built:
        obj.location.x = (row - 1.0) * 2.2
        obj.location.z = (0.5 - column) * 2.6
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 8.0
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (3.0, -9.0, 2.0)
    cam.rotation_euler = (Vector((0.0, 0.0, 0.4)) - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = "%s/fans.png" % preview_dir
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
