"""Cleans up a generated stadium prop and exports it as a game-ready GLB.

Run from the project root:

    blender -b --factory-startup --python tools/prep_prop.py -- \
        <model.glb or model.fbx> assets/stadium/<prop>.glb \
        [tris=5000] [yaw=0] [texture=1024] [preview=<dir>]
        [clean=1] [level=1] [screen=1]

The meshes are joined into one, the import transform is baked in, the model is
turned by `yaw` degrees about the vertical (so that its front ends up on
Godot's +Z), put with the middle of its footprint on the origin and its
lowest point on the ground, cut down to `tris` triangles and its textures to
`texture` pixels. Its size is left alone: the Stadium script scales every prop
to the height it wants. With `preview`, a front and a three-quarter render are
saved there as PNGs.

For a model that is to be seen close (the jumbotron):

- `clean=1` drops faces without area, loose points and specks, and keeps the
  model's own normals if it is not thinned.
- `level=1` turns it so its front faces exactly forward, stands it upright and
  makes its underside flat.
- `screen=1` finds its screen (the largest flat dark area facing forward),
  makes it one plane and prints a SCREEN line for `Stadium.SCREEN_RECT` and
  `Stadium.SCREEN_DEPTH`.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
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
clean = options.get("clean", "0") == "1"
level = options.get("level", "0") == "1"
screen = options.get("screen", "0") == "1"
## Parts smaller than this share of the model's diagonal are specks.
SPECK = 0.004
## The underside within this share of the height of the ground is made flat.
FLOOR = 0.006
## A lean of more than this many degrees is the model's shape, not a mistake.
LEAN_LIMIT = 6.0
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

front = Vector((0.0, -1.0, 0.0))


def recentre():
    """Middle of the footprint on the origin, lowest point on the ground."""
    low, high = bounds()
    mesh.transform(Matrix.Translation(Vector((-(low.x + high.x) * 0.5, -(low.y + high.y) * 0.5, -low.z))))


def tidy():
    """Drops faces without area, loose edges and points, and specks: parts no
    bigger than SPECK of the model. Small parts above that are detail (a bolt,
    a lamp), since Tripo builds these models from separate pieces."""
    limit = (hi - lo).length * SPECK
    bm = bmesh.new()
    bm.from_mesh(mesh)
    dead = [f for f in bm.faces if f.calc_area() < 1e-12]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    # Parts by position, not by shared points: the points are split along
    # every seam of the texture.
    where = {}
    for v in bm.verts:
        where.setdefault(tuple(round(c, 5) for c in v.co), []).append(v)
    seen = set()
    specks = []
    for start in bm.verts:
        if start in seen:
            continue
        seen.add(start)
        stack = [start]
        part = []
        while stack:
            v = stack.pop()
            part.append(v)
            near = [e.other_vert(v) for e in v.link_edges] + where[tuple(round(c, 5) for c in v.co)]
            for other in near:
                if other not in seen:
                    seen.add(other)
                    stack.append(other)
        low = Vector((min(v.co.x for v in part), min(v.co.y for v in part), min(v.co.z for v in part)))
        high = Vector((max(v.co.x for v in part), max(v.co.y for v in part), max(v.co.z for v in part)))
        if (high - low).length < limit:
            specks.extend(part)
    bmesh.ops.delete(bm, geom=specks, context="VERTS")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    print("TIDIED", "faces without area", len(dead), "points in specks", len(specks), "loose points", len(loose))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def square_up():
    """Turns the model so that its front faces exactly forward and it stands
    upright, and brings its underside to one flat plane."""
    # The front: the mean of everything that faces forward, by area.
    normal = Vector((0.0, 0.0, 0.0))
    for poly in mesh.polygons:
        if poly.normal.dot(front) > 0.97:
            normal += poly.normal * poly.area
    if normal.length > 0.0:
        turn = normal.normalized().rotation_difference(front)
        print("TURNED", round(math.degrees(turn.angle), 3))
        mesh.transform(turn.to_matrix().to_4x4())
        mesh.update()
    # Upright: the lean, about the line of sight, with the smallest outline.
    co = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)

    def outline(degrees):
        c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
        x = co[:, 0] * c + co[:, 2] * s
        z = co[:, 2] * c - co[:, 0] * s
        return (x.max() - x.min()) * (z.max() - z.min())

    best, step = 0.0, 1.0
    while step > 0.005:
        best = min((best - step, best, best + step), key=outline)
        step *= 0.5
    if abs(best) > 0.02 and abs(best) < LEAN_LIMIT:
        print("STRAIGHTENED", round(best, 3))
        mesh.transform(Matrix.Rotation(math.radians(-best), 4, "Y"))
        mesh.update()
    recentre()
    low, high = bounds()
    floor = (high.z - low.z) * FLOOR
    for v in mesh.vertices:
        if v.co.z < floor:
            v.co.z = 0.0
    mesh.update()


def base_colour():
    """The picture on the material's base colour, as an array of rows."""
    for material in mesh.materials:
        if material is None or material.node_tree is None:
            continue
        for node in material.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED" or not node.inputs["Base Color"].is_linked:
                continue
            source = node.inputs["Base Color"].links[0].from_node
            if source.type == "TEX_IMAGE" and source.image is not None:
                image = source.image
                pixels = np.empty(image.size[0] * image.size[1] * 4, dtype=np.float32)
                image.pixels.foreach_get(pixels)
                return pixels.reshape(image.size[1], image.size[0], 4)
    return None


def find_screen():
    """Finds the screen: the largest flat, dark area that faces forward. Makes
    it one plane and prints where it is, for Stadium.SCREEN_RECT and
    SCREEN_DEPTH: its middle across and up, its width and height, and how far
    in front of the model's middle it is, all as shares of the model's size."""
    low, high = bounds()
    extent = high - low
    picture = base_colour()
    uv = mesh.uv_layers.active.data if mesh.uv_layers.active else None
    faces = []
    for poly in mesh.polygons:
        if poly.normal.dot(front) < 0.9:
            continue
        dark = 0.0
        if picture is not None and uv is not None:
            u = sum(uv[i].uv.x for i in poly.loop_indices) / poly.loop_total
            v = sum(uv[i].uv.y for i in poly.loop_indices) / poly.loop_total
            row = min(int((v % 1.0) * picture.shape[0]), picture.shape[0] - 1)
            column = min(int((u % 1.0) * picture.shape[1]), picture.shape[1] - 1)
            dark = float(picture[row, column, :3].max())
        faces.append((poly, dark))
    if not faces:
        print("SCREEN not found: nothing faces forward")
        return
    # The plane that holds the most dark area.
    shades = sorted(shade for _, shade in faces)
    darkest, lightest = shades[len(shades) // 20], shades[len(shades) * 19 // 20]
    limit = (darkest + lightest) * 0.5 if lightest - darkest > 0.04 else 2.0
    slab = extent.y * 0.01
    bins = {}
    for poly, shade in faces:
        if shade <= limit:
            key = round(poly.center.y / slab)
            bins[key] = bins.get(key, 0.0) + poly.area
    key = max(bins, key=bins.get)
    members = [poly for poly, shade in faces if shade <= limit and abs(round(poly.center.y / slab) - key) <= 1]
    # Of those, the largest patch that hangs together: a dark speaker or a
    # shadowed panel at the same depth is not part of the screen.
    patch = {}
    for poly in members:
        for i in poly.vertices:
            patch.setdefault(tuple(round(c, 5) for c in mesh.vertices[i].co), []).append(poly.index)
    by_index = {poly.index: poly for poly in members}
    group = {}
    best = []
    for poly in members:
        if poly.index in group:
            continue
        group[poly.index] = poly.index
        stack = [poly]
        found = []
        while stack:
            face = stack.pop()
            found.append(face)
            for i in face.vertices:
                for other in patch[tuple(round(c, 5) for c in mesh.vertices[i].co)]:
                    if other not in group:
                        group[other] = poly.index
                        stack.append(by_index[other])
        if sum(face.area for face in found) > sum(face.area for face in best):
            best = found
    members = best
    area = sum(poly.area for poly in members)
    depth = sum(poly.center.y * poly.area for poly in members) / area
    points = set()
    for poly in members:
        points.update(poly.vertices)
    xs = sorted(mesh.vertices[i].co.x for i in points)
    zs = sorted(mesh.vertices[i].co.z for i in points)
    for i in points:
        mesh.vertices[i].co.y = depth
    mesh.update()
    left, right, bottom, top = xs[0], xs[-1], zs[0], zs[-1]
    print("SCREEN middle %.4f %.4f size %.4f %.4f depth %.4f (faces %d, filled %.0f%% of its rectangle)" % (
        ((left + right) * 0.5 - low.x) / extent.x, ((bottom + top) * 0.5 - low.z) / extent.z,
        (right - left) / extent.x, (top - bottom) / extent.z,
        -depth / extent.y, len(members), 100.0 * area / max((right - left) * (top - bottom), 1e-9)))


if clean:
    tidy()
if level:
    square_up()
    lo, hi = bounds()
    size = hi - lo
    print("SIZE", tuple(round(c, 3) for c in size))
if screen:
    find_screen()

mesh.calc_loop_triangles()
tris = len(mesh.loop_triangles)
print("TRIS", tris)
decimated = False
if tris > max_tris:
    mod = prop.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = max_tris / tris
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh.calc_loop_triangles()
    decimated = True
    print("DECIMATED", len(mesh.loop_triangles))
# A model that comes with its own normals (hard edges where its maker wanted
# them) keeps them, unless thinning it has just made them wrong.
if decimated or not (clean and mesh.has_custom_normals):
    bpy.ops.object.shade_smooth()
print("NORMALS", "the model's own" if mesh.has_custom_normals else "smooth")

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
