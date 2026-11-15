"""Renders a flat picture of each mascot, to be painted on the turf at midfield.

Run from the project root:

    blender -b --factory-startup --python tools/mascot_decal.py -- [team ...]

With no team named, every team in tools/mascots.json that has a model
(assets/stadium/mascot_<team>.glb) is done. Each picture is a square PNG with
a clear background, assets/field/mascot_<team>.png: the mascot in its rest
pose, evenly lit, filling the square, turned a little to its left so that it
looks toward the right of the picture. Field (scripts/field.gd) hands the two
teams' pictures to the turf shader, which mirrors the right-hand one, so the
two face each other across the 50.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

SIZE = 512
# How far the mascot is turned away from the camera, toward the picture's right.
TURN = math.radians(35.0)
# Clear space round the mascot, as a share of the picture.
PAD = 0.04

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
with open(os.path.join(ROOT, "tools", "mascots.json"), encoding="utf-8") as handle:
    known = [key for key in json.load(handle) if not key.startswith("_")]
teams = argv or known

for team in teams:
    path = os.path.join(ROOT, "assets", "stadium", "mascot_%s.glb" % team)
    if not os.path.exists(path):
        print("SKIPPED (not made yet)", team)
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    mesh = max(meshes, key=lambda o: len(o.data.vertices))
    # The importer adds a little shape to draw the bones with: not wanted here.
    for extra in [o for o in meshes if o is not mesh]:
        bpy.data.objects.remove(extra)
    # The rest pose (arms up), not whatever clip the file opens on.
    for rig in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
        rig.data.pose_position = "REST"
    bpy.context.view_layer.update()

    # The front is -Y. The camera goes round to the mascot's right instead of
    # the mascot turning: `right` and +Z are the picture's two axes.
    right = Vector((math.cos(TURN), -math.sin(TURN), 0.0))
    back = Vector((-math.sin(TURN), -math.cos(TURN), 0.0))
    points = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    across = [p.dot(right) for p in points]
    up = [p.z for p in points]
    centre = right * ((min(across) + max(across)) * 0.5) + Vector((0.0, 0.0, (min(up) + max(up)) * 0.5))
    span = max(max(across) - min(across), max(up) - min(up))

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span / (1.0 - PAD * 2.0)
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = centre + back * 50.0
    cam.rotation_euler = (-back).to_track_quat("-Z", "Y").to_euler()
    cam_data.clip_end = 200.0

    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (0.03, 0.03, 0.03)
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = os.path.join(ROOT, "assets", "field", "mascot_%s.png" % team)
    bpy.ops.render.render(write_still=True)
    print("DECAL", team, scene.render.filepath)
