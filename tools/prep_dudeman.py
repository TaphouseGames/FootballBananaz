"""Prepares the pre-rigged "dudeman" character for the game and exports a GLB.

Run from the project root:

    blender -b --factory-startup --python tools/prep_dudeman.py -- \
        assets/player/source/dudeman/<name>.fbx assets/player/dudeman.glb [preview_dir]

The source is a Tripo rig: 1 unit tall, A-pose, facing -Y (Blender front), with
its own bone names. The game's animator wants what tools/rig_player.py makes:
HEIGHT tall, feet on the origin, a T-pose at rest, and the bone names below.
Bones the game does not drive (twist, fingers, toes, eyes) are kept and simply
follow their parents.

If preview_dir is given, a few test poses are rendered there as PNGs.
"""

import math
import sys

import bpy
from mathutils import Matrix, Vector

HEIGHT = 1.85

# Game bone -> source bone. ".L" is the character's left, which is +X here.
BONE_MAP = {
    "Hips": "Hip",
    "Spine": "Waist",
    "Chest": "Spine02",
    "Neck": "NeckTwist01",
    "Head": "Head",
}
for side in ("L", "R"):
    BONE_MAP["UpperArm." + side] = side + "_Upperarm"
    BONE_MAP["Forearm." + side] = side + "_Forearm"
    BONE_MAP["Hand." + side] = side + "_Hand"
    BONE_MAP["Thigh." + side] = side + "_Thigh"
    BONE_MAP["Shin." + side] = side + "_Calf"
    BONE_MAP["Foot." + side] = side + "_Foot"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    raise SystemExit("usage: prep_dudeman.py -- <in.fbx> <out.glb> [preview_dir]")
src_path, out_path = argv[0], argv[1]
preview_dir = argv[2] if len(argv) > 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=bpy.path.abspath(src_path))
mesh_obj = next(o for o in bpy.data.objects if o.type == "MESH")
arm_obj = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh_obj.name = "FootballPlayer"
mesh_obj.data.name = "FootballPlayer"
arm_obj.name = "PlayerRig"
arm_obj.data.name = "PlayerRig"
for mat in mesh_obj.data.materials:
    mat.name = "PlayerSkin"

missing = [src for src in BONE_MAP.values() if src not in arm_obj.data.bones]
if missing:
    raise SystemExit("source rig is missing bones: %s" % ", ".join(missing))
for game_name, src_name in BONE_MAP.items():
    arm_obj.data.bones[src_name].name = game_name
if arm_obj.data.bones["Thigh.L"].head_local.x <= arm_obj.data.bones["Thigh.R"].head_local.x:
    raise SystemExit("left and right are swapped: expected the left leg on +X")


def select_only(*objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


# Normalise: feet on z = 0, HEIGHT tall, centred. The mesh follows the armature.
world = [mesh_obj.matrix_world @ v.co for v in mesh_obj.data.vertices]
zs = [v.z for v in world]
xs = [v.x for v in world]
scale = HEIGHT / (max(zs) - min(zs))
arm_obj.matrix_world = Matrix.Scale(scale, 4) @ Matrix.Translation(
    (-(max(xs) + min(xs)) * 0.5, 0.0, -min(zs))) @ arm_obj.matrix_world
bpy.context.view_layer.update()
select_only(arm_obj, mesh_obj)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print("SCALE %.4f" % scale)

# A-pose -> T-pose: swing each upper arm, then each forearm, level with the
# shoulders, bake that into the mesh, and make it the new rest pose.
select_only(arm_obj)
bpy.ops.object.mode_set(mode="POSE")
for side, sign in (("L", 1.0), ("R", -1.0)):
    for name, child in (("UpperArm." + side, "Forearm." + side), ("Forearm." + side, "Hand." + side)):
        bpy.context.view_layer.update()
        bone = arm_obj.pose.bones[name]
        origin = bone.matrix.translation.copy()
        current = (arm_obj.pose.bones[child].matrix.translation - origin).normalized()
        swing = current.rotation_difference(Vector((sign, 0.0, 0.0))).to_matrix().to_4x4()
        print("STRAIGHTEN %s from %s" % (name, tuple(round(c, 2) for c in current)))
        bone.matrix = Matrix.Translation(origin) @ swing @ Matrix.Translation(-origin) @ bone.matrix
bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode="OBJECT")

select_only(mesh_obj)
for mod in [m for m in mesh_obj.modifiers if m.type == "ARMATURE"]:
    bpy.ops.object.modifier_apply(modifier=mod.name)
select_only(arm_obj)
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode="OBJECT")
mesh_obj.modifiers.new("Armature", "ARMATURE").object = arm_obj

select_only(mesh_obj)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
bpy.ops.object.shade_smooth()

select_only(arm_obj, mesh_obj)
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
