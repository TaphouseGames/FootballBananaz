"""Normalises the generated football mesh and exports it as a game-ready GLB.

Run from the project root:

    blender -b --factory-startup --python tools/prep_ball.py -- \
        assets/ball/source/tripo/tripo-out/<task>/model.glb assets/ball/football.glb [preview_dir]

The exported ball is 1 unit long, centred on the origin, with its long axis on
Godot's X axis and the laces pointing up (+Y). The ball scene scales it to size.
If preview_dir is given, two renders are saved there as PNGs.
"""

import math
import sys

import bpy
from mathutils import Matrix, Vector

MAX_TRIS = 6000
TEXTURE_SIZE = 1024

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    raise SystemExit("usage: prep_ball.py -- <in.glb> <out.glb> [preview_dir]")
src_path, out_path = argv[0], argv[1]
preview_dir = argv[2] if len(argv) > 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=bpy.path.abspath(src_path))
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
ball = bpy.context.view_layer.objects.active
ball.name = "Football"
ball.data.name = "Football"
for mat in ball.data.materials:
    mat.name = "FootballLeather"

# Bake the import transform and drop any parent empties.
mesh = ball.data
world = ball.matrix_world.copy()
ball.parent = None
mesh.transform(world)
ball.matrix_world = Matrix.Identity(4)
for o in list(bpy.data.objects):
    if o != ball:
        bpy.data.objects.remove(o)


def bounds():
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


# Long axis onto X.
lo, hi = bounds()
size = hi - lo
longest = max(range(3), key=lambda i: size[i])
if longest == 1:
    mesh.transform(Matrix.Rotation(math.radians(-90.0), 4, "Z"))
elif longest == 2:
    mesh.transform(Matrix.Rotation(math.radians(90.0), 4, "Y"))

# Centre on the bounding box and scale to unit length.
lo, hi = bounds()
mesh.transform(Matrix.Translation(-(lo + hi) * 0.5))
mesh.transform(Matrix.Scale(1.0 / (hi.x - lo.x), 4))

# The laces stick out of the leather: find the direction, around the long axis,
# of the vertices furthest from it near the middle, and turn that to +Z.
middle = [v.co for v in mesh.vertices if abs(v.co.x) < 0.25]
middle.sort(key=lambda c: -(c.y * c.y + c.z * c.z))
top = middle[:max(len(middle) // 100, 8)]
lace = sum((Vector((0.0, c.y, c.z)) for c in top), Vector())
angle = math.atan2(lace.y, lace.z)
mesh.transform(Matrix.Rotation(angle, 4, "X"))
lo, hi = bounds()
print("SIZE", tuple(round(c, 3) for c in (hi - lo)), "LACE_ANGLE", round(math.degrees(angle), 1))

mesh.calc_loop_triangles()
tris = len(mesh.loop_triangles)
print("TRIS", tris)
if tris > MAX_TRIS:
    mod = ball.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = MAX_TRIS / tris
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh.calc_loop_triangles()
    print("DECIMATED", len(mesh.loop_triangles))
bpy.ops.object.shade_smooth()

for image in bpy.data.images:
    if image.size[0] > TEXTURE_SIZE or image.size[1] > TEXTURE_SIZE:
        image.scale(TEXTURE_SIZE, TEXTURE_SIZE)
        print("RESIZED", image.name)

bpy.ops.object.select_all(action="DESELECT")
ball.select_set(True)
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
    scene.render.resolution_x = 600
    scene.render.resolution_y = 600
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.4
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for view, pos in (("top", (0.0, 0.0, 4.0)), ("side", (0.6, -4.0, 1.2))):
        cam.location = pos
        cam.rotation_euler = (-Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = "%s/ball_%s.png" % (preview_dir, view)
        bpy.ops.render.render(write_still=True)
    print("PREVIEWS", preview_dir)
