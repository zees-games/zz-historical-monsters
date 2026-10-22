"""Turns a downloaded rigged model into the static, upright base glb build_monsters.py expects.

    blender -b --factory-startup --python tools/prep_base.py -- <in.gltf> <out.glb> [flip] [joints] [pose]

Joins the visible meshes in their bind pose, stands the length axis on Blender's Y with the head toward -Y (the
glTF +Z the other bases use; the head end is the one with more mass), and exports one object with its materials.
`flip` swaps the head end when the mass guess is wrong. The skeleton is dropped: build_monsters.py skins its own.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
flip = "flip" in sys.argv
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
joints = {b.name: (a.matrix_world @ b.head_local, a.matrix_world @ b.tail_local) for a in arms for b in a.data.bones}
meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.visible_get() and len(o.data.polygons) > 100]
bpy.ops.object.select_all(action="DESELECT")
if "pose" in sys.argv:
    # Some sources only look right posed: bake frame 1 of the first action instead of the bind pose.
    for a in arms:
        if bpy.data.actions and a.animation_data is None:
            a.animation_data_create()
        if a.animation_data is not None and a.animation_data.action is None and bpy.data.actions:
            a.animation_data.action = bpy.data.actions[0]
    bpy.context.scene.frame_set(1)
    deps = bpy.context.evaluated_depsgraph_get()
    for o in meshes:
        baked = bpy.data.meshes.new_from_object(o.evaluated_get(deps))
        o.data = baked
for o in meshes:
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
world = obj.matrix_world.copy()
for o in list(bpy.data.objects):
    if o is not obj:
        bpy.data.objects.remove(o)
obj.parent = None
obj.matrix_world = Matrix.Identity(4)
# Only the first UV set carries the colour texture; build_monsters.py samples the active one.
while len(obj.data.uv_layers) > 1:
    obj.data.uv_layers.remove(obj.data.uv_layers[len(obj.data.uv_layers) - 1])
obj.data.transform(world)
vs = np.array([v.co[:] for v in obj.data.vertices])
ext = vs.max(0) - vs.min(0)
# length axis is the longer horizontal one; Z is up (glTF's Y), unless the model lies down
if ext[0] > ext[1]:
    obj.data.transform(Matrix.Rotation(math.pi / 2, 4, "Z"))
    vs = np.array([v.co[:] for v in obj.data.vertices])
# centre across the width: the bone fractions are measured from the middle of the body
obj.data.transform(Matrix.Translation((-(vs.max(0)[0] + vs.min(0)[0]) / 2, 0, 0)))
vs = np.array([v.co[:] for v in obj.data.vertices])
c = vs.mean(0)
mid = (vs.max(0)[1] + vs.min(0)[1]) / 2
head_at_minus_y = c[1] < mid
if head_at_minus_y == flip:
    obj.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
obj.data.update()
# Where the source's own joints fall, as the fractions CONFIG uses (length 0 tail -> 1 head, height, half width),
# to place this species' bones by. Printed, not exported.
if "joints" in sys.argv:
    xf = Matrix.Identity(4)
    if ext[0] > ext[1]:
        xf = Matrix.Rotation(math.pi / 2, 4, "Z") @ xf
    if head_at_minus_y == flip:
        xf = Matrix.Rotation(math.pi, 4, "Z") @ xf
    vs = np.array([v.co[:] for v in obj.data.vertices])
    lo, hi = vs.min(0), vs.max(0)
    for name, (h, t) in joints.items():
        h = xf @ h
        print("JOINT %-22s fl %.3f fh %.3f fw %.3f" % (name, (hi[1] - h[1]) / (hi[1] - lo[1]), (h[2] - lo[2]) / (hi[2] - lo[2]), h[0] / ((hi[0] - lo[0]) / 2)))
print("PREP size", np.round(ext, 2), "head -Y" if not flip else "flipped")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_materials="EXPORT",
                          export_animations=False, export_skins=False)
