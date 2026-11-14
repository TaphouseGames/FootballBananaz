"""Cleans up a generated stadium prop and exports it as a game-ready GLB.

Run from the project root:

    blender -b --factory-startup --python tools/prep_prop.py -- \
        <model.glb or model.fbx> assets/stadium/<prop>.glb \
        [tris=5000] [yaw=0] [texture=1024] [preview=<dir>]

The meshes are joined into one, the import transform is baked in, the model is
turned by `yaw` degrees about the vertical (so that its front ends up on
Godot's +Z), put with the middle of its footprint on the origin and its
lowest point on the ground, cut down to `tris` triangles and its textures to
`texture` pixels. Its size is left alone: the Stadium script scales every prop
to the height it wants. With `preview`, a front and a three-quarter render are
saved there as PNGs.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    raise SystemExit("usage: prep_prop.py -- <in.glb> <out.glb> [tris=N] [yaw=deg] [texture=px] [preview=dir]")
src_path, out_path = argv[0], argv[1]
options = dict(arg.split("=", 1) for arg in argv[2:])
max_tris = int(options.get("tris", 5000))
yaw = float(options.get("yaw", 0.0))
texture_size = int(options.get("texture", 1024))
preview_dir = options.get("preview")
name = os.path.splitext(os.path.basename(out_path))[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
if src_path.lower().endswith(".fbx"):
    # Its textures are looked for next to the file (the .fbm folder).
    if hasattr(bpy.ops.wm, "fbx_import"):
        bpy.ops.wm.fbx_import(filepath=os.path.abspath(src_path))
    else:
        bpy.ops.import_scene.fbx(filepath=os.path.abspath(src_path))
else:
    bpy.ops.import_scene.gltf(filepath=bpy.path.abspath(src_path))
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
prop = bpy.context.view_layer.objects.active
prop.name = name
prop.data.name = name

# Bake the import transform and drop any parent empties.
mesh = prop.data
world = prop.matrix_world.copy()
prop.parent = None
mesh.transform(world)
prop.matrix_world = Matrix.Identity(4)
for o in list(bpy.data.objects):
    if o != prop:
        bpy.data.objects.remove(o)

if yaw != 0.0:
    mesh.transform(Matrix.Rotation(math.radians(yaw), 4, "Z"))


def bounds():
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


lo, hi = bounds()
mesh.transform(Matrix.Translation(Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))))
lo, hi = bounds()
size = hi - lo
print("SIZE", tuple(round(c, 3) for c in size))

mesh.calc_loop_triangles()
tris = len(mesh.loop_triangles)
print("TRIS", tris)
if tris > max_tris:
    mod = prop.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = max_tris / tris
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh.calc_loop_triangles()
    print("DECIMATED", len(mesh.loop_triangles))
bpy.ops.object.shade_smooth()

for image in bpy.data.images:
    if image.size[0] > texture_size or image.size[1] > texture_size:
        image.scale(texture_size, texture_size)
        print("RESIZED", image.name)

bpy.ops.object.select_all(action="DESELECT")
prop.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=bpy.path.abspath(out_path),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_image_format="JPEG",
    export_animations=False,
    export_apply=True,
)
print("EXPORTED", out_path)

if preview_dir:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 500
    scene.render.resolution_y = 500
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(size) * 1.25
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    aim = Vector((0.0, 0.0, size.z * 0.5))
    reach = max(size) * 4.0
    # The front is -Y here, +Z in Godot.
    for view, offset in (("front", Vector((0.0, -reach, 0.0))), ("angle", Vector((reach * 0.6, -reach, reach * 0.4)))):
        cam.location = aim + offset
        cam.rotation_euler = (-offset).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = "%s/%s_%s.png" % (preview_dir, name, view)
        bpy.ops.render.render(write_still=True)
    print("PREVIEWS", preview_dir)
