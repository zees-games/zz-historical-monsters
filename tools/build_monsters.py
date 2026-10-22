"""Builds the infected monsters from their CC0 / CC-BY base models.

    blender -b --factory-startup --python tools/build_monsters.py -- <species> <base.glb> <out.glb>

species: trex, tiger, bear.  Run `tools/build_monsters.sh` to do all three.

What it does, in order (the glb is a build product of this file, never edited by hand):
 1. imports the base, joins it, turns it to face +Y (exported: -Z, Godot's forward), scales it to a
    monster's size and stands it on the floor;
 2. bakes the base's texture or material colour into a corner colour attribute, so the shipped
    model has no textures;
 3. welds, triangulates and subdivides it so a wound has facets to be ragged with;
 4. cuts wounds (sunk inward, torn rim raised, muscle and bone coloured), stains blood, blotches
    the skin with rot, and wrenches the jaw open and crooked;
 5. adds geometry: ribs through the flank wound, spine spurs, joint spurs, teeth, hanging flesh,
    tumours and glowing eyes;
 6. skins it to a skeleton of a dozen or so bones by distance to the bones (Blender's automatic
    weights fail on an unwelded low-poly mesh), and exports a glb with COLOR_0 and two materials.

Deterministic: every random choice is seeded from the species name.
"""
import math
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:]
SPECIES, BASE, OUT = argv[0], argv[1], argv[2]
RNG = random.Random(SPECIES)

BONE_COL = (0.80, 0.74, 0.58)
MUSCLE = (0.52, 0.035, 0.04)
DEEP = (0.10, 0.008, 0.01)
BLOOD = (0.16, 0.008, 0.01)


def srgb(c):
    """Colour attributes written as FLOAT_COLOR are linear; the palette above is chosen by eye as
    sRGB, so convert once."""
    return tuple(x ** 2.2 for x in c)


# Fractions are (fl along the body tail 0 -> head 1, fh of the height, fw of the half width).
CONFIG = {
    "trex": {
        "length": 11.5,
        "bones": [
            ("pelvis", None, (0.50, 0.52, 0), (0.58, 0.56, 0)),
            ("spine", "pelvis", (0.58, 0.56, 0), (0.68, 0.62, 0)),
            ("neck", "spine", (0.68, 0.62, 0), (0.80, 0.80, 0)),
            ("head", "neck", (0.80, 0.80, 0), (0.97, 0.86, 0)),
            ("jaw", "head", (0.86, 0.80, 0), (1.0, 0.77, 0)),
            ("tail1", "pelvis", (0.50, 0.55, 0), (0.36, 0.60, 0)),
            ("tail2", "tail1", (0.36, 0.60, 0), (0.18, 0.61, 0)),
            ("tail3", "tail2", (0.18, 0.61, 0), (0.0, 0.60, 0)),
            ("legL_up", "pelvis", (0.53, 0.52, -0.55), (0.57, 0.30, -0.6)),
            ("legL_lo", "legL_up", (0.57, 0.30, -0.6), (0.50, 0.12, -0.6)),
            ("legL_ft", "legL_lo", (0.50, 0.12, -0.6), (0.60, 0.0, -0.6)),
            ("legR_up", "pelvis", (0.53, 0.52, 0.55), (0.57, 0.30, 0.6)),
            ("legR_lo", "legR_up", (0.57, 0.30, 0.6), (0.50, 0.12, 0.6)),
            ("legR_ft", "legR_lo", (0.50, 0.12, 0.6), (0.60, 0.0, 0.6)),
            ("armL", "spine", (0.72, 0.64, -0.4), (0.76, 0.40, -0.45)),
            ("armR", "spine", (0.72, 0.64, 0.4), (0.76, 0.40, 0.45)),
        ],
        "skin_dark": 0.55,
        "skin_tint": (0.50, 0.52, 0.38), "skin_tint_amount": 0.8,
        "wounds": [
            (0.58, 0.58, 1.0, 1.25, 0.34, "ribs"),
            (0.64, 0.50, -1.0, 0.8, 0.22, "flesh"),
            (0.90, 0.84, -1.0, 0.55, 0.14, "bone"),
            (0.94, 0.88, 0.0, 0.45, 0.10, "bone"),
            (0.80, 0.78, 1.0, 0.55, 0.14, "flesh"),
            (0.52, 0.42, 1.0, 0.55, 0.14, "flesh"),
            (0.24, 0.61, 0.0, 0.55, 0.18, "flesh"),
            (0.56, 0.86, 0.0, 0.7, 0.12, "rot"),
        ],
        "jaw": {"hinge": (0.86, 0.78), "fh_max": 0.80, "fl_min": 0.86, "open": 20, "yaw": 9},
        "eyes": [(0.93, 0.88, -0.55), (0.93, 0.88, 0.55)],
        "eye_r": 0.11,
        "mouth_up": ((0.90, 0.80, -0.62), (1.0, 0.80, 0.0)),
        "mouth_lo": ((0.90, 0.78, -0.55), (1.0, 0.77, 0.0)),
        "teeth": 15, "tooth": 0.26,
        "spines": ((0.36, 0.64), 11, 0.5),
        "spurs": [(0.57, 0.30, 0.64), (0.57, 0.30, -0.64), (0.72, 0.64, 0.45), (0.72, 0.64, -0.45)],
        "flaps": 7, "tumours": 5,
        "rib_range": (0.52, 0.64),
    },
    "tiger": {
        "length": 3.4,
        "bones": [
            ("pelvis", None, (0.22, 0.62, 0), (0.40, 0.66, 0)),
            ("spine", "pelvis", (0.40, 0.66, 0), (0.62, 0.68, 0)),
            ("neck", "spine", (0.62, 0.68, 0), (0.82, 0.74, 0)),
            ("head", "neck", (0.82, 0.74, 0), (0.98, 0.76, 0)),
            ("jaw", "head", (0.90, 0.70, 0), (1.0, 0.66, 0)),
            ("tail1", "pelvis", (0.18, 0.62, 0), (0.08, 0.56, 0)),
            ("tail2", "tail1", (0.08, 0.56, 0), (0.04, 0.40, 0)),
            ("tail3", "tail2", (0.04, 0.40, 0), (0.0, 0.22, 0)),
            ("legL_up", "pelvis", (0.20, 0.58, -0.5), (0.17, 0.35, -0.55)),
            ("legL_lo", "legL_up", (0.17, 0.35, -0.55), (0.14, 0.12, -0.55)),
            ("legL_ft", "legL_lo", (0.14, 0.12, -0.55), (0.19, 0.0, -0.55)),
            ("legR_up", "pelvis", (0.20, 0.58, 0.5), (0.17, 0.35, 0.55)),
            ("legR_lo", "legR_up", (0.17, 0.35, 0.55), (0.14, 0.12, 0.55)),
            ("legR_ft", "legR_lo", (0.14, 0.12, 0.55), (0.19, 0.0, 0.55)),
            ("armL_up", "spine", (0.72, 0.60, -0.5), (0.73, 0.35, -0.55)),
            ("armL_lo", "armL_up", (0.73, 0.35, -0.55), (0.74, 0.10, -0.55)),
            ("armL_ft", "armL_lo", (0.74, 0.10, -0.55), (0.80, 0.0, -0.55)),
            ("armR_up", "spine", (0.72, 0.60, 0.5), (0.73, 0.35, 0.55)),
            ("armR_lo", "armR_up", (0.73, 0.35, 0.55), (0.74, 0.10, 0.55)),
            ("armR_ft", "armR_lo", (0.74, 0.10, 0.55), (0.80, 0.0, 0.55)),
        ],
        "skin_dark": 0.62,
        "skin_tint": (0.55, 0.38, 0.22), "skin_tint_amount": 0.35,
        "wounds": [
            (0.45, 0.62, 1.0, 0.55, 0.12, "ribs"),
            (0.70, 0.66, -1.0, 0.45, 0.10, "flesh"),
            (0.88, 0.78, 1.0, 0.28, 0.07, "bone"),
            (0.30, 0.66, -1.0, 0.35, 0.08, "flesh"),
            (0.55, 0.78, 0.0, 0.35, 0.07, "rot"),
            (0.74, 0.40, 1.0, 0.25, 0.05, "flesh"),
        ],
        "jaw": {"hinge": (0.88, 0.70), "fh_max": 0.70, "fl_min": 0.88, "open": 24, "yaw": 10},
        "eyes": [(0.95, 0.76, -0.5), (0.95, 0.76, 0.5)],
        "eye_r": 0.04,
        "mouth_up": ((0.93, 0.68, -0.55), (1.0, 0.68, 0.0)),
        "mouth_lo": ((0.93, 0.66, -0.5), (1.0, 0.66, 0.0)),
        "teeth": 14, "tooth": 0.09,
        "spines": ((0.30, 0.75), 9, 0.17),
        "spurs": [(0.73, 0.35, 0.58), (0.73, 0.35, -0.58), (0.17, 0.35, 0.58), (0.17, 0.35, -0.58)],
        "flaps": 6, "tumours": 4,
        "rib_range": (0.36, 0.56),
    },
    "bear": {
        "length": 3.0,
        "bones": [
            ("pelvis", None, (0.22, 0.60, 0), (0.40, 0.66, 0)),
            ("spine", "pelvis", (0.40, 0.66, 0), (0.62, 0.70, 0)),
            ("neck", "spine", (0.62, 0.70, 0), (0.80, 0.72, 0)),
            ("head", "neck", (0.80, 0.72, 0), (0.97, 0.66, 0)),
            ("jaw", "head", (0.88, 0.60, 0), (1.0, 0.54, 0)),
            ("legL_up", "pelvis", (0.20, 0.55, -0.5), (0.20, 0.30, -0.55)),
            ("legL_lo", "legL_up", (0.20, 0.30, -0.55), (0.20, 0.0, -0.55)),
            ("legR_up", "pelvis", (0.20, 0.55, 0.5), (0.20, 0.30, 0.55)),
            ("legR_lo", "legR_up", (0.20, 0.30, 0.55), (0.20, 0.0, 0.55)),
            ("armL_up", "spine", (0.70, 0.55, -0.5), (0.70, 0.30, -0.55)),
            ("armL_lo", "armL_up", (0.70, 0.30, -0.55), (0.72, 0.0, -0.55)),
            ("armR_up", "spine", (0.70, 0.55, 0.5), (0.70, 0.30, 0.55)),
            ("armR_lo", "armR_up", (0.70, 0.30, 0.55), (0.72, 0.0, 0.55)),
        ],
        "skin_dark": 0.9,
        "skin_tint": (0.36, 0.28, 0.24), "skin_tint_amount": 0.55,
        "wounds": [
            (0.40, 0.62, 1.0, 0.60, 0.14, "ribs"),
            (0.52, 0.62, -1.0, 0.50, 0.12, "flesh"),
            (0.88, 0.68, -1.0, 0.30, 0.07, "bone"),
            (0.72, 0.80, 0.0, 0.45, 0.09, "flesh"),
            (0.25, 0.70, 1.0, 0.40, 0.09, "rot"),
            (0.70, 0.35, -1.0, 0.28, 0.06, "flesh"),
        ],
        "jaw": {"hinge": (0.87, 0.56), "fh_max": 0.58, "fl_min": 0.86, "open": 24, "yaw": 11},
        "eyes": [(0.93, 0.68, -0.5), (0.93, 0.68, 0.5)],
        "eye_r": 0.045,
        "mouth_up": ((0.92, 0.56, -0.5), (1.0, 0.55, 0.0)),
        "mouth_lo": ((0.92, 0.54, -0.45), (1.0, 0.52, 0.0)),
        "teeth": 14, "tooth": 0.09,
        "spines": ((0.30, 0.74), 9, 0.17),
        "spurs": [(0.70, 0.30, 0.58), (0.70, 0.30, -0.58), (0.20, 0.30, 0.58), (0.20, 0.30, -0.58)],
        "flaps": 6, "tumours": 5,
        "rib_range": (0.30, 0.52),
    },
}
CFG = CONFIG[SPECIES]


# ---------------------------------------------------------------------------------------------
# import, orient, scale
# ---------------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=BASE)
meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.visible_get() and len(o.data.polygons) > 100]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
obj.name = "Infected"
bpy.context.view_layer.update()
world = obj.matrix_world.copy()
for o in list(bpy.data.objects):
    if o is not obj:
        bpy.data.objects.remove(o)
obj.parent = None
obj.matrix_world = Matrix.Identity(4)
mesh = obj.data
mesh.transform(world)

# The glTF importer puts the base's +Z head toward Blender -Y. Exported, +Y becomes -Z.
rot = Matrix.Rotation(math.pi, 4, "Z")
mesh.transform(rot)


def bounds():
    vs = np.array([v.co[:] for v in mesh.vertices])
    return vs.min(0), vs.max(0)


lo, hi = bounds()
scale = CFG["length"] / (hi[1] - lo[1])
mesh.transform(Matrix.Scale(scale, 4))
lo, hi = bounds()
mesh.transform(Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2])))
mesh.update()
lo, hi = bounds()
X0, Y0, Z0 = 0.0, lo[1], 0.0
HALFW = (hi[0] - lo[0]) / 2
LEN = hi[1] - lo[1]
HEIGHT = hi[2]


def P(fl, fh, fw=0.0):
    return Vector((fw * HALFW, Y0 + fl * LEN, fh * HEIGHT))


# ---------------------------------------------------------------------------------------------
# bake the base colours into a corner colour attribute
# ---------------------------------------------------------------------------------------------
def base_colour_sampler(mat):
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex = next((n for n in nodes if n.type == "TEX_IMAGE" and n.image), None)
    if tex is not None:
        w, h = tex.image.size
        px = np.array(tex.image.pixels[:], dtype=np.float32).reshape(h, w, -1)

        def sample(uv):
            x = int((uv[0] % 1.0) * (w - 1))
            y = int((uv[1] % 1.0) * (h - 1))
            return tuple(px[y, x, :3])

        return sample
    c = tuple(bsdf.inputs["Base Color"].default_value[:3])
    return lambda uv: c


samplers = [base_colour_sampler(m) for m in mesh.materials]
uv = mesh.uv_layers.active
base_cols = {}
for poly in mesh.polygons:
    s = samplers[poly.material_index] if samplers else (lambda _uv: (0.5, 0.5, 0.5))
    for li in poly.loop_indices:
        base_cols[li] = s(uv.data[li].uv if uv else (0, 0))

# ---------------------------------------------------------------------------------------------
# weld, triangulate, subdivide (corner data rides along)
# ---------------------------------------------------------------------------------------------
cl = mesh.attributes.new("Col", "FLOAT_COLOR", "CORNER")
for li, c in base_cols.items():
    cl.data[li].color = (c[0], c[1], c[2], 1.0)
# The base's own UVs and materials are dropped: the model ships vertex colours only.
while mesh.uv_layers:
    mesh.uv_layers.remove(mesh.uv_layers[0])

bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=LEN * 0.0004)
bmesh.ops.triangulate(bm, faces=bm.faces)
cuts = 1 if SPECIES == "trex" else 2
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.normal_update()
col_layer = bm.loops.layers.float_color.get("Col")

# ---------------------------------------------------------------------------------------------
# infection fields
# ---------------------------------------------------------------------------------------------
verts = list(bm.verts)
vco = np.array([v.co[:] for v in verts])


def fbm(p, freq, octaves=3, seed=0.0):
    t = 0.0
    a = 1.0
    f = freq
    norm = 0.0
    for _ in range(octaves):
        t += a * noise.noise(Vector((p[0] * f + seed, p[1] * f - seed, p[2] * f + 2 * seed)))
        norm += a
        a *= 0.5
        f *= 2.1
    return t / norm


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def snap_to_surface(p):
    d = np.linalg.norm(vco - np.array(p[:]), axis=1)
    return Vector(vco[int(d.argmin())])


sites = []
for fl, fh, fw, r, depth, kind in CFG["wounds"]:
    centre = snap_to_surface(P(fl, fh, fw * 0.85))
    sites.append({"c": centre, "r": r, "depth": depth * (LEN / 11.5) ** 0.0 * (r / 1.0) ** 0.0, "kind": kind})

# Per vertex: the strongest wound's mask and its kind.
wmask = np.zeros(len(verts))
wkind = [None] * len(verts)
wdepth = np.zeros(len(verts))
for i, v in enumerate(verts):
    best = 0.0
    for s in sites:
        d = (v.co - s["c"]).length
        n = fbm(v.co, 3.0 / max(s["r"], 0.2), 3, 1.7) * 0.45
        m = 1.0 - d / s["r"] + n
        if m > best:
            best = m
            wkind[i] = s
    wmask[i] = best
    wdepth[i] = best

for i, v in enumerate(verts):
    m = wmask[i]
    s = wkind[i]
    if s is None or m <= 0.0:
        continue
    # Torn rim: a lip raised a little, then the sunken wound with a ragged floor.
    core = smooth(0.18, 0.5, m)
    rim = smooth(0.0, 0.18, m) * (1.0 - core)
    ragged = 0.6 + 0.8 * (fbm(v.co, 14.0, 2, 4.2) * 0.5 + 0.5)
    depth = s["depth"] * core * ragged - 0.12 * s["depth"] * rim
    v.co += v.normal * (-depth)

bm.normal_update()
verts = list(bm.verts)
vco = np.array([v.co[:] for v in verts])

# ---------------------------------------------------------------------------------------------
# a ruined jaw: swung open and crooked about its hinge, blended in over the hinge's reach
# ---------------------------------------------------------------------------------------------
J = CFG["jaw"]
hinge = P(J["hinge"][0], J["hinge"][1], 0.0)
ang = math.radians(J["open"])
yaw = math.radians(J["yaw"])
for v in verts:
    fl = (v.co.y - Y0) / LEN
    fh = v.co.z / HEIGHT
    if fl < J["fl_min"] - 0.02:
        continue
    # below the mouth line only; a soft edge so the cheek tears rather than splits
    w = smooth(J["fh_max"] + 0.012, J["fh_max"] - 0.02, fh) * smooth(J["fl_min"] - 0.02, J["fl_min"] + 0.02, fl)
    if w <= 0:
        continue
    rel = v.co - hinge
    # Opening rotates about the lateral X axis (chin down), then a yaw about Z for the crooked set.
    rx = Matrix.Rotation(ang * w, 3, "X")
    rz = Matrix.Rotation(yaw * w, 3, "Z")
    v.co = hinge + rz @ (rx @ rel)

bm.normal_update()
verts = list(bm.verts)
vco = np.array([v.co[:] for v in verts])

# ---------------------------------------------------------------------------------------------
# colour, per corner, from where the corner is
# ---------------------------------------------------------------------------------------------
vindex = {v.index: i for i, v in enumerate(verts)}
vidx = {id(v): i for i, v in enumerate(verts)}


def mix(a, b, t):
    return tuple(x * (1 - t) + y * t for x, y in zip(a, b))


skin_dark = CFG["skin_dark"]
wound_cols = {}
for f in bm.faces:
    for loop in f.loops:
        v = loop.vert
        i = vidx[id(v)]
        p = v.co
        c = loop[col_layer]
        base = (c[0], c[1], c[2])
        # sick skin: darker, drained, blotched with rot and bruise
        grey = sum(base) / 3
        c1 = mix(base, (grey, grey, grey), 0.35)
        c1 = tuple(x * skin_dark for x in c1)
        # lift the drained hide toward a sickly tone so it reads in a dim room, not as a silhouette
        c1 = mix(c1, srgb(CFG["skin_tint"]), CFG["skin_tint_amount"])
        blot = fbm(p, 2.6 / (LEN / 3.4) ** 0.0 * (3.4 / LEN) ** 0.0 * 1.0 / max(0.5, LEN / 3.0), 3, 9.1)
        rot_t = smooth(0.12, 0.45, blot)
        c1 = mix(c1, srgb((0.22, 0.30, 0.12)), rot_t * 0.75)
        bruise = fbm(p, 5.0 / max(0.5, LEN / 3.0), 2, 3.3)
        c1 = mix(c1, srgb((0.30, 0.10, 0.26)), smooth(0.2, 0.5, bruise) * 0.6)
        pus = fbm(p, 12.0 / max(0.5, LEN / 3.0), 2, 7.7)
        c1 = mix(c1, srgb((0.62, 0.58, 0.28)), smooth(0.5, 0.62, pus) * 0.8)

        m = wmask[i]
        s = wkind[i]
        if s is not None and m > 0.0:
            core = smooth(0.18, 0.5, m)
            rim = smooth(0.0, 0.18, m)
            kind = s["kind"]
            streak = 0.65 + 0.35 * math.sin(p.y * (24.0 / max(0.5, LEN / 3.0)) + fbm(p, 6.0, 2, 1.1) * 6.0)
            muscle = tuple(x * streak for x in srgb(MUSCLE))
            inner = smooth(0.55, 0.9, m)
            floor_c = mix(muscle, srgb(DEEP), inner * 0.85)
            if kind in ("bone", "ribs"):
                floor_c = mix(floor_c, srgb(BONE_COL), smooth(0.45, 0.75, m) * (0.9 if kind == "bone" else 0.25))
            if kind == "rot":
                floor_c = mix(srgb((0.28, 0.36, 0.10)), srgb(DEEP), inner)
            tear = srgb((0.30, 0.04, 0.06))
            c1 = mix(c1, tear, rim * 0.9)
            c1 = mix(c1, floor_c, core)
        # blood: streaks running down from every wound, and a darkening round it
        near = 1e9
        for st in sites:
            d = Vector((p.x - st["c"].x, p.y - st["c"].y, 0.0)).length
            if p.z < st["c"].z + st["r"] * 0.5:
                near = min(near, d / (st["r"] * 1.8))
        streak_n = fbm(Vector((p.x * 9.0, p.y * 9.0, p.z * 1.4)), 1.0 / max(0.4, LEN / 3.0), 2, 5.5)
        blood_t = smooth(1.0, 0.1, near) * smooth(-0.15, 0.25, streak_n)
        # the muzzle and chin are always wet
        fl = (p.y - Y0) / LEN
        if fl > 0.9 and p.z / HEIGHT < J["fh_max"] + 0.02:
            blood_t = max(blood_t, 0.85 * smooth(-0.3, 0.2, fbm(p, 6.0, 2, 2.2)))
        c1 = mix(c1, srgb(BLOOD), blood_t * 0.85)
        loop[col_layer] = (c1[0], c1[1], c1[2], 1.0)

# ---------------------------------------------------------------------------------------------
# added geometry
# ---------------------------------------------------------------------------------------------
BONE_L = srgb(BONE_COL)


def add_tube(points, r0, r1, colour, sides=5, cap=True):
    """A tapering tube along a polyline, written into the same bmesh with a flat colour."""
    rings = []
    n = len(points)
    for k, pt in enumerate(points):
        if k < n - 1:
            tang = (points[k + 1] - pt)
        else:
            tang = (pt - points[k - 1])
        tang.normalize()
        ref = Vector((0, 0, 1)) if abs(tang.z) < 0.9 else Vector((1, 0, 0))
        a = tang.cross(ref).normalized()
        b = tang.cross(a).normalized()
        r = r0 + (r1 - r0) * (k / max(1, n - 1))
        ring = []
        for s in range(sides):
            th = 2 * math.pi * s / sides
            ring.append(bm.verts.new(pt + (a * math.cos(th) + b * math.sin(th)) * r))
        rings.append(ring)
    made = []
    for k in range(n - 1):
        for s in range(sides):
            t = (s + 1) % sides
            made.append(bm.faces.new([rings[k][s], rings[k][t], rings[k + 1][t], rings[k + 1][s]]))
    if cap:
        tip = bm.verts.new(points[-1] + (points[-1] - points[-2]).normalized() * max(r1, r0 * 0.25) * 1.2)
        for s in range(sides):
            t = (s + 1) % sides
            made.append(bm.faces.new([rings[-1][s], rings[-1][t], tip]))
    for f in made:
        for lp in f.loops:
            lp[col_layer] = (colour[0], colour[1], colour[2], 1.0)
    return made


def add_blob(centre, radius, colour, squash=(1, 1, 1), subdiv=1):
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    vs = res["verts"]
    for v in vs:
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2])) + centre
    for f in {f for v in vs for f in v.link_faces}:
        for lp in f.loops:
            lp[col_layer] = (colour[0], colour[1], colour[2], 1.0)
    return vs


def slab_extent(y, tol):
    sel = vco[np.abs(vco[:, 1] - y) < tol]
    if len(sel) == 0:
        return None
    return sel[:, 2].min(), sel[:, 2].max(), np.abs(sel[:, 0]).max()


# ribs through the flank wound: ellipse arcs a little inside the unwounded skin
ribsite = next(s for s in sites if s["kind"] == "ribs")
rib_lo, rib_hi = CFG["rib_range"]
rsign = 1.0 if ribsite["c"].x >= 0 else -1.0
nrib = 6 if SPECIES == "trex" else 5
for k in range(nrib):
    y = Y0 + (rib_lo + (rib_hi - rib_lo) * k / (nrib - 1)) * LEN
    ext = slab_extent(y, LEN * 0.012)
    if ext is None:
        continue
    zmin, zmax, xmax = ext
    zc = (zmin + zmax) / 2
    zr = (zmax - zmin) / 2
    pts = []
    for a in np.linspace(math.radians(35), math.radians(125), 8):
        pts.append(Vector((rsign * xmax * 0.9 * math.sin(a), y, zc + zr * 0.88 * math.cos(a))))
    add_tube(pts, LEN * 0.0085, LEN * 0.004, BONE_L, 5)

# bone spurs through the back's skin
(sfl0, sfl1), sn, sl = CFG["spines"]
for k in range(sn):
    fl = sfl0 + (sfl1 - sfl0) * k / (sn - 1)
    y = Y0 + fl * LEN
    sel = vco[np.abs(vco[:, 1] - y) < LEN * 0.01]
    if len(sel) == 0:
        continue
    top = sel[sel[:, 2].argmax()]
    base = Vector((top[0] * 0.5, y, top[2] - 0.02 * LEN * 0.3))
    lean = Vector((0, -0.25, 1.0)).normalized()
    length = sl * RNG.uniform(0.6, 1.2) * (0.5 + 0.5 * math.sin(math.pi * k / (sn - 1)))
    add_tube([base, base + lean * length * 0.5, base + lean * length + Vector((0.02, 0.1, 0)) * length],
             LEN * 0.0085, LEN * 0.0012, BONE_L, 5)

# bone spurs at the joints, bursting outward
for fl, fh, fw in CFG["spurs"]:
    c = snap_to_surface(P(fl, fh, fw * 0.9))
    out = Vector((1 if fw > 0 else -1, RNG.uniform(-0.3, 0.3), RNG.uniform(-0.1, 0.5))).normalized()
    ln = LEN * 0.05
    add_tube([c - out * 0.02 * LEN, c + out * ln * 0.5, c + out * ln], LEN * 0.0085, LEN * 0.0012, BONE_L, 5)

# teeth, in two ragged rows; the lower row rides the swung-open jaw
def row(a, b, count, lower):
    pa, pb = P(*a), P(*b)
    for k in range(count):
        t = k / max(1, count - 1)
        side = -1 if k % 2 == 0 else 1
        for sgn in (-1, 1):
            p = pa.lerp(pb, t)
            p = Vector((sgn * abs(p.x) * (1.0 - 0.2 * t), p.y, p.z))
            if lower:
                rel = p - hinge
                w = 1.0
                p = hinge + Matrix.Rotation(yaw * w, 3, "Z") @ (Matrix.Rotation(ang * w, 3, "X") @ rel)
            ln = CFG["tooth"] * RNG.uniform(0.5, 1.2) * (1.4 if t > 0.8 else 1.0)
            dirv = Vector((RNG.uniform(-0.25, 0.25), RNG.uniform(0.05, 0.3), 1.0 if lower else -1.0)).normalized()
            add_tube([p, p + dirv * ln * 0.5, p + dirv * ln], ln * 0.16, ln * 0.02, srgb((0.78, 0.72, 0.52)), 4)


half = CFG["teeth"] // 2
row(CFG["mouth_up"][0], CFG["mouth_up"][1], half, False)
row(CFG["mouth_lo"][0], CFG["mouth_lo"][1], half, True)

# hanging strips of flesh from the wound lips
for k in range(CFG["flaps"]):
    s = sites[RNG.randrange(len(sites))]
    ang_k = RNG.uniform(0, 2 * math.pi)
    p = s["c"] + Vector((math.cos(ang_k) * 0.0, 0, 0))
    off = Vector((RNG.uniform(-1, 1), RNG.uniform(-1, 1), RNG.uniform(-0.2, 0.8))).normalized()
    base = snap_to_surface(p + off * s["r"] * 0.55)
    ln = s["r"] * RNG.uniform(0.5, 1.1)
    pts = [base, base + Vector((0, 0.01 * LEN, -ln * 0.4)), base + Vector((RNG.uniform(-0.05, 0.05), 0.03 * LEN, -ln))]
    add_tube(pts, LEN * 0.008, LEN * 0.0025, srgb((0.42, 0.04, 0.07)), 4)

# tumours: swollen, veined growths
for k in range(CFG["tumours"]):
    fl = RNG.uniform(0.25, 0.8)
    y = Y0 + fl * LEN
    sel = vco[np.abs(vco[:, 1] - y) < LEN * 0.02]
    if len(sel) == 0:
        continue
    top = sel[sel[:, 2].argmax()] if RNG.random() < 0.6 else sel[RNG.randrange(len(sel))]
    r = LEN * RNG.uniform(0.012, 0.03)
    add_blob(Vector(top) * 0.98, r, srgb(RNG.choice([(0.52, 0.25, 0.30), (0.42, 0.30, 0.10), (0.35, 0.12, 0.30)])), (1, 1, 0.8), 1)

# eyes: glowing, in their own material (index 1)
eye_faces = []
for fl, fh, fw in CFG["eyes"]:
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=CFG["eye_r"])
    cen = snap_to_surface(P(fl, fh, fw * 0.85))
    out = Vector((1 if fw > 0 else -1, 0.25, 0.1)).normalized()
    for v in res["verts"]:
        v.co = v.co + cen + out * CFG["eye_r"] * 0.2
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = 1
        eye_faces.append(f)
        for lp in f.loops:
            lp[col_layer] = (1.0, 0.85, 0.1, 1.0)

bm.faces.index_update()
eye_idx = [f.index for f in eye_faces]
bm.to_mesh(mesh)
bm.free()
mesh.update()

# materials: 0 vertex-coloured infected body, 1 glowing eyes
mesh.materials.clear()
body = bpy.data.materials.new("Infected")
body.use_nodes = True
bn = body.node_tree.nodes
b_bsdf = next(n for n in bn if n.type == "BSDF_PRINCIPLED")
attr = bn.new("ShaderNodeVertexColor")
attr.layer_name = "Col"
body.node_tree.links.new(attr.outputs["Color"], b_bsdf.inputs["Base Color"])
b_bsdf.inputs["Roughness"].default_value = 0.62
eyem = bpy.data.materials.new("EyesGlow")
eyem.use_nodes = True
e_bsdf = next(n for n in eyem.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
e_bsdf.inputs["Base Color"].default_value = (1.0, 0.85, 0.05, 1)
e_bsdf.inputs["Emission Color"].default_value = (1.0, 0.8, 0.02, 1)
e_bsdf.inputs["Emission Strength"].default_value = 6.0
mesh.materials.append(body)
mesh.materials.append(eyem)
# clear() above reset every face to material 0, so the eyes are assigned here
for i in eye_idx:
    mesh.polygons[i].material_index = 1
mesh.color_attributes.active_color = mesh.color_attributes["Col"]
mesh.color_attributes.render_color_index = mesh.color_attributes.find("Col")
for p in mesh.polygons:
    p.use_smooth = False

# ---------------------------------------------------------------------------------------------
# skeleton and weights
# ---------------------------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("Skeleton")
arm_obj = bpy.data.objects.new("Skeleton", arm_data)
bpy.context.scene.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode="EDIT")
segs = {}
for name, parent, a, b in CFG["bones"]:
    eb = arm_data.edit_bones.new(name)
    eb.head = P(*a)
    eb.tail = P(*b)
    if (eb.tail - eb.head).length < 1e-4:
        eb.tail = eb.head + Vector((0, 0, 0.05))
    if parent:
        eb.parent = arm_data.edit_bones[parent]
    segs[name] = (eb.head.copy(), eb.tail.copy())
bpy.ops.object.mode_set(mode="OBJECT")

names = list(segs.keys())
co = np.array([v.co[:] for v in mesh.vertices])
dist = np.zeros((len(co), len(names)))
for j, n in enumerate(names):
    a = np.array(segs[n][0][:])
    b = np.array(segs[n][1][:])
    ab = b - a
    t = np.clip(((co - a) @ ab) / (ab @ ab), 0.0, 1.0)
    proj = a + t[:, None] * ab
    dist[:, j] = np.linalg.norm(co - proj, axis=1)
w = 1.0 / (dist + LEN * 0.01) ** 3.0
for i in range(len(co)):
    keep = np.argsort(-w[i])[:3]
    mask = np.zeros(len(names))
    mask[keep] = 1.0
    w[i] *= mask
w /= w.sum(axis=1, keepdims=True)
# the jaw bone owns the lower jaw only: a vertex above the mouth line cannot lean on it
for j, n in enumerate(names):
    obj.vertex_groups.new(name=n)
for i in range(len(co)):
    for j, n in enumerate(names):
        if w[i, j] > 0.02:
            obj.vertex_groups[n].add([i], float(w[i, j]), "REPLACE")
obj.parent = arm_obj
mod = obj.modifiers.new("Armature", "ARMATURE")
mod.object = arm_obj
bpy.context.view_layer.update()

print("BUILT", SPECIES, "tris", sum(len(p.vertices) - 2 for p in mesh.polygons), "verts", len(mesh.vertices),
      "size", round(HALFW * 2, 2), round(LEN, 2), round(HEIGHT, 2))

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=False, export_yup=True,
                          export_normals=True, export_materials="EXPORT", export_animations=False,
                          export_skins=True, export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=False)
