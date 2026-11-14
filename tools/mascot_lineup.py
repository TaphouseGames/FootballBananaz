"""Renders every finished mascot side by side, at the sizes the game gives them.

Run from the project root:

    blender -b --factory-startup --python tools/mascot_lineup.py -- <out.png> [clip=cheer] [frame=14]

The mascots are the assets/stadium/mascot_<team>.glb files of the teams in
tools/mascots.json, in that order. Each is scaled the way Stadium does it:
MASCOT_HEIGHT tall, or less if that would make it wider than MASCOT_WIDTH
(keep the two numbers below in step with scripts/stadium.gd). With `clip`,
all of them are shown in that clip at `frame` instead of the rest pose.
"""

import json
import os
import sys

import bpy
from mathutils import Vector

MASCOT_HEIGHT = 2.8
MASCOT_WIDTH = 2.0
SPACING = 2.6

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 1:
    raise SystemExit("usage: mascot_lineup.py -- <out.png> [clip=name] [frame=N]")
out_path = os.path.abspath(argv[0])
options = dict(arg.split("=", 1) for arg in argv[1:])
clip = options.get("clip")
frame = int(options.get("frame", 0))

with open(os.path.join(ROOT, "tools", "mascots.json"), encoding="utf-8") as handle:
    teams = [key for key in json.load(handle) if not key.startswith("_")]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
placed = []
for team in teams:
    path = os.path.join(ROOT, "assets", "stadium", "mascot_%s.glb" % team)
    if not os.path.exists(path):
        print("SKIPPED (not made yet)", team)
        continue
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    mesh = max((o for o in new if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    # The importer adds a little shape to draw the bones with: not wanted here.
    for extra in [o for o in new if o.type == "MESH" and o is not mesh]:
        new.remove(extra)
        bpy.data.objects.remove(extra)
    tops = [o for o in new if o.parent is None]
    bpy.context.view_layer.update()
    corners = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    width = max(c.x for c in corners) - min(c.x for c in corners)
    height = max(c.z for c in corners) - min(c.z for c in corners)
    scale = min(MASCOT_HEIGHT / height, MASCOT_WIDTH / width)
    placed.append((team, tops, scale, height * scale))
    rig = next((o for o in new if o.type == "ARMATURE"), None)
    if rig is not None and rig.animation_data is not None:
        for track in rig.animation_data.nla_tracks:
            track.mute = track.name != clip
        rig.animation_data.action = None

for index, (team, tops, scale, height) in enumerate(placed):
    x = (index - (len(placed) - 1) * 0.5) * SPACING
    for top in tops:
        top.scale = top.scale * scale
        top.location = top.location * scale + Vector((x, 0.0, 0.0))
    print("PLACED %s: %.2f yards tall" % (team, height))
scene.frame_set(frame)

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.view_settings.view_transform = "Standard"
span = SPACING * max(len(placed), 1) + 0.8
scene.render.resolution_x = 1800
scene.render.resolution_y = max(500, round(1800 * 4.0 / span))
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = span
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
# The front is -Y here, +Z in Godot.
offset = Vector((0.0, -20.0, 3.0))
cam.location = Vector((0.0, 0.0, 1.5)) + offset
cam.rotation_euler = (-offset).to_track_quat("-Z", "Y").to_euler()
world = bpy.data.worlds.new("World")
world.color = (0.16, 0.3, 0.16)
scene.world = world
scene.render.filepath = out_path
bpy.ops.render.render(write_still=True)
print("LINEUP", out_path)
