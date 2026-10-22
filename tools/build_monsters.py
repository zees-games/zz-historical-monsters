"""Builds the infected monsters from their CC0 / CC-BY base models.

    blender -b --factory-startup --python tools/build_monsters.py -- <species> <base.glb> <out.glb>

species: trex, tiger, bear.  Run `tools/build_monsters.sh` to do all three.

The glb is a build product of this file, never edited by hand. Order: import, orient and scale; bake colour into a
corner colour attribute (no textures ship); weld, triangulate and subdivide so wounds have facets; cut wounds, stain
and rot the skin, wrench the jaw; add ribs, spurs, teeth, hanging flesh, tumours and eyes; skin to a dozen bones by
distance (Blender's automatic weights fail on an unwelded low-poly mesh). COLOR_0's alpha is wetness, which
view/zhm_view.gd's shader turns into gloss.

Deterministic: every random choice is seeded from the species name.
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:]
SPECIES, BASE, OUT = argv[0], argv[1], argv[2]
RNG = random.Random(SPECIES)

BONE_COL = (0.72, 0.64, 0.48)
MUSCLE = (0.78, 0.07, 0.06)
DEEP = (0.16, 0.012, 0.02)
NECROTIC = (0.60, 0.55, 0.40)
GUT = (0.50, 0.20, 0.28)
BLOOD = (0.16, 0.008, 0.01)


def srgb(c):
    """Colour attributes written as FLOAT_COLOR are linear; the palette above is chosen by eye as
    sRGB, so convert once."""
    return tuple(x ** 2.2 for x in c)


def mix(a, b, t):
    return tuple(x * (1 - t) + y * t for x, y in zip(a, b))


# Face kinds, written per face and read by the bake: what texture detail a face gets.
K_BODY, K_BONE, K_GUT, K_STRIP, K_TUMOUR, K_EYE = range(6)
KIND = K_BONE


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
        "skin_dark": 0.9,
        "skin_tint": (0.62, 0.64, 0.46), "skin_tint_amount": 0.8,
        "skin_cap": 0.8,
        "wounds": [
            (0.58, 0.58, 1.0, 1.25, 0.42, "ribs"),
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
        "flaps": 7, "tumours": 5, "sores": 9,
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
        "skin_cap": 0.52,
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
        "skin_dark": 1.0,
        "skin_tint": (0.50, 0.40, 0.33), "skin_tint_amount": 0.8,
        "skin_floor": 0.32,
        "skin_cap": 0.62,
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
PASSES = (1.2, 0.6) if SPECIES == "trex" else (1.1, 0.65)


# import, orient, scale
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


# The base's own colour texture is kept as arrays: the bake samples it per texel through the base UVs
# (kept on the mesh as the "orig" layer through every weld and subdivision), so the stripes and fur of the
# source survive at the texture's resolution instead of at the vertices'.
def base_image(mat):
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex = next((n for n in nodes if n.type == "TEX_IMAGE" and n.image), None)
    if tex is not None:
        w, h = tex.image.size
        return np.array(tex.image.pixels[:], dtype=np.float32).reshape(h, w, -1)[:, :, :3]
    return np.array(bsdf.inputs["Base Color"].default_value[:3], dtype=np.float32)


BASE_IMGS = [base_image(m) for m in mesh.materials] or [np.array((0.5, 0.5, 0.5), dtype=np.float32)]
if mesh.uv_layers:
    mesh.uv_layers.active.name = "orig"
# Corner colour carries the flat colour and wetness (alpha) of everything ADDED to the body (bone, gut, strips);
# the body's own colour is baked per texel.
mesh.attributes.new("Col", "FLOAT_COLOR", "CORNER")

# weld, triangulate, subdivide (corner data rides along)
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=LEN * 0.0004)
bmesh.ops.triangulate(bm, faces=bm.faces)
cuts = 0 if SPECIES == "trex" else 1
if cuts:
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.normal_update()
col_layer = bm.loops.layers.float_color.get("Col")
rest_layer = bm.verts.layers.float_vector.new("rest")
rest_set = bm.verts.layers.float.new("rest_set")
kind_layer = bm.faces.layers.int.new("kind")

# infection fields
verts = list(bm.verts)
vco = np.array([v.co[:] for v in verts])


def _hash(ix, iy, iz, seed):
    h = ((ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h ^= h >> 16
    return (h & 0xFFFF) / 32767.5 - 1.0


def vnoise(P, seed):
    """Value noise in [-1, 1] over an (N, 3) array. Numpy rather than mathutils.noise: the bake evaluates
    it for a million texels and the geometry for the vertices, and both must agree to the digit so a
    wound's outline in the texture is the outline of its cavity in the mesh."""
    f = np.floor(P)
    t = P - f
    i = f.astype(np.int64)
    u = t * t * t * (t * (t * 6 - 15) + 10)
    x0, y0, z0 = i[:, 0], i[:, 1], i[:, 2]

    def c(dx, dy, dz):
        return _hash(x0 + dx, y0 + dy, z0 + dz, seed)

    def lerp(a, b, k):
        return a + (b - a) * k

    ux, uy, uz = u[:, 0], u[:, 1], u[:, 2]
    x00 = lerp(c(0, 0, 0), c(1, 0, 0), ux)
    x10 = lerp(c(0, 1, 0), c(1, 1, 0), ux)
    x01 = lerp(c(0, 0, 1), c(1, 0, 1), ux)
    x11 = lerp(c(0, 1, 1), c(1, 1, 1), ux)
    return lerp(lerp(x00, x10, uy), lerp(x01, x11, uy), uz)


_ROT = np.array(Matrix.Rotation(0.9, 3, (0.3, 0.8, 0.5)))


def fbm(P, freq, octaves=3, seed=0.0):
    """Fractal noise over an (N, 3) array (or one Vector), about [-0.7, 0.7]."""
    single = not isinstance(P, np.ndarray)
    Q = np.atleast_2d(np.array(P[:], dtype=np.float64) if single else P) * freq + seed * np.array([1.0, -1.0, 2.0])
    t = np.zeros(len(Q))
    a = 1.0
    norm = 0.0
    for o in range(octaves):
        t += a * vnoise(Q, int(seed * 7) + o * 131)
        norm += a
        a *= 0.5
        Q = (Q @ _ROT) * 2.1
    # value noise swings wider than the gradient noise these thresholds were tuned on
    t *= 0.55 / norm
    return float(t[0]) if single else t


def smooth(a, b, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - a) / (b - a), 0.0, 1.0)
    t = t * t * (3 - 2 * t)
    return float(t) if t.ndim == 0 else t


def snap_to_surface(p):
    d = np.linalg.norm(vco - np.array(p[:]), axis=1)
    return Vector(vco[int(d.argmin())])


sites = []
for fl, fh, fw, r, depth, kind in CFG["wounds"]:
    centre = snap_to_surface(P(fl, fh, fw * 0.85))
    sites.append({"c": centre, "r": r, "depth": depth, "kind": kind, "major": True})
# Ruined eye sockets: a deep dark pit the eye sits sunk in.
for fl, fh, fw in CFG["eyes"]:
    sites.append({"c": snap_to_surface(P(fl, fh, fw * 0.85)), "r": CFG["eye_r"] * 3.2, "depth": CFG["eye_r"] * 1.4,
                  "kind": "socket", "major": False})
# Many smaller bites and sores across the body, so the whole hide reads as torn, not one patch.
_sites_main_r = max(s["r"] for s in sites)
for k in range(CFG.get("sores", 14)):
    for _try in range(30):
        c = snap_to_surface(Vector((RNG.uniform(-HALFW, HALFW), Y0 + RNG.uniform(0.12, 0.88) * LEN,
                                    RNG.uniform(0.15, 1.0) * HEIGHT)))
        if all((c - s["c"]).length > s["r"] * 0.9 for s in sites):
            break
    r = _sites_main_r * RNG.uniform(0.14, 0.3)
    sites.append({"c": c, "r": r, "depth": r * RNG.uniform(0.2, 0.35), "kind": RNG.choice(["flesh", "flesh", "rot", "bone"]),
                  "major": False})

# Refine the mesh where a wound is, so its ragged rim and cavity have facets to be made of.
for pass_r in PASSES:
    near = []
    for e in bm.edges:
        mid = (e.verts[0].co + e.verts[1].co) * 0.5
        if any((mid - s["c"]).length < s["r"] * pass_r for s in sites):
            near.append(e)
    bmesh.ops.subdivide_edges(bm, edges=near, cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    vco = np.array([v.co[:] for v in bm.verts])
bm.normal_update()
verts = list(bm.verts)
vco = np.array([v.co[:] for v in verts])

def wound_field(Pa):
    """The strongest wound's noisy mask at each point of an (N, 3) array, and which site owns it. The bands of
    wound colour are ramps of this one number, in the mesh (cavity depth) and in the texture (colour)."""
    best = np.full(len(Pa), -9.0)
    own = np.full(len(Pa), -1, dtype=np.int64)
    for si, s in enumerate(sites):
        c = np.array(s["c"][:])
        d = np.linalg.norm(Pa - c, axis=1)
        sel = np.nonzero(d < s["r"] * 2.4)[0]
        if len(sel) == 0:
            continue
        rr = max(s["r"], 0.2)
        n = fbm(Pa[sel], 3.0 / rr, 3, 1.7) * 0.75 + fbm(Pa[sel], 11.0 / rr, 2, 6.3) * 0.22
        m = 1.0 - d[sel] / s["r"] + n
        up = m > best[sel]
        best[sel[up]] = m[up]
        own[sel[up]] = si
    return best, own


# Per vertex: the strongest wound's mask and its kind.
for v in verts:
    v[rest_layer] = v.co
    v[rest_set] = 1.0
wmask, wown = wound_field(vco)
rag_all = 0.85 + 0.3 * (fbm(vco, 14.0, 2, 4.2) * 0.5 + 0.5)
for i, v in enumerate(verts):
    m = wmask[i]
    s = sites[wown[i]] if wown[i] >= 0 else None
    if s is None or m <= 0.0:
        continue
    # Torn rim: a lip raised a little, then the sunken wound with a ragged floor.
    core = smooth(0.18, 0.5, m)
    rim = smooth(0.0, 0.18, m) * (1.0 - core)
    depth = 1.7 * s["depth"] * core * rag_all[i] - 0.15 * s["depth"] * rim
    v.co += v.normal * (-depth)

# Relax the torn ground a little: the refined grid leaves long sliver triangles that the noise
# turns into a sunburst of shards. Two passes of averaging keep the cavity but lose the spikes.
for _pass in range(4):
    new = {}
    for i, v in enumerate(verts):
        if wmask[i] > -0.1 and v.link_edges:
            avg = sum((e.other_vert(v).co for e in v.link_edges), Vector()) / len(v.link_edges)
            new[v] = v.co.lerp(avg, 0.5)
    for v, c in new.items():
        v.co = c

bm.normal_update()
verts = list(bm.verts)
vco = np.array([v.co[:] for v in verts])

# a ruined jaw: swung open and crooked about its hinge, blended in over the hinge's reach
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

# added geometry
BONE_L = srgb(BONE_COL)


def add_tube(points, r0, r1, colour, sides=5, cap=True, wet=0.0, radii=None, seg_cols=None):
    """A tapering tube along a polyline, written into the same bmesh with a flat colour. `wet` is
    the glossiness written to the colour's alpha; `radii` (one per point) and `seg_cols` (one per
    point) override the linear taper and the single colour, and blend smoothly along the tube."""
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
        r = radii[k] if radii else r0 + (r1 - r0) * (k / max(1, n - 1))
        ring = []
        for s in range(sides):
            th = 2 * math.pi * s / sides
            ring.append(bm.verts.new(pt + (a * math.cos(th) + b * math.sin(th)) * r))
        rings.append(ring)
    made = []
    for k in range(n - 1):
        for s in range(sides):
            t = (s + 1) % sides
            f = bm.faces.new([rings[k][s], rings[k][t], rings[k + 1][t], rings[k + 1][s]])
            made.append((f, k, (k, k, k + 1, k + 1)))
    if cap:
        rl = radii[-1] if radii else r1
        tip = bm.verts.new(points[-1] + (points[-1] - points[-2]).normalized() * max(rl, r0 * 0.25) * 1.2)
        for s in range(sides):
            t = (s + 1) % sides
            made.append((bm.faces.new([rings[-1][s], rings[-1][t], tip]), n - 1, (n - 1, n - 1, n - 1)))
    for f, k, ks in made:
        f[kind_layer] = KIND
        for lp, kk in zip(f.loops, ks):
            c = seg_cols[kk] if seg_cols else colour
            lp[col_layer] = (c[0], c[1], c[2], wet)
    return [f for f, _, _ in made]


def surface_normal(p):
    """Outward normal of the nearest body vertex (the body only: nothing added yet is in vco)."""
    d = np.linalg.norm(vco - np.array(p[:]), axis=1)
    return verts[int(d.argmin())].normal.copy()


def add_ribbon(points, w0, w1, side, outer, inner):
    """A strip of torn hide with thickness: dull skin outside, wet flesh inside and along the cut edges. It is
    cupped across its width (a flat plank seen edge-on is a red shard; a trough is a lump from every side),
    its width wanders and tapers to a point, and it twists along its length. Three columns across and
    both faces, so the curl is in the mesh and the fibre and the soft rim are in the texture."""
    n = len(points)
    twist = RNG.uniform(-1.1, 1.1)
    half = 0.0055 * LEN
    cup = RNG.uniform(0.3, 0.55)
    wob = [RNG.uniform(0.8, 1.2) for _ in range(n)]
    out, inn = [], []
    for k, pt in enumerate(points):
        t = k / max(1, n - 1)
        tang = (points[min(k + 1, n - 1)] - points[max(k - 1, 0)]).normalized()
        d = Matrix.Rotation(twist * k, 3, tang) @ (side - tang * side.dot(tang))
        d.normalize()
        nrm = tang.cross(d).normalized()
        w = (w0 + (w1 - w0) * t) * (1.0 - 0.75 * t ** 1.5) * wob[k]
        if k == n - 1:
            w = 0.0
        orow, irow = [], []
        for j in (-1, 0, 1):
            c = pt + d * (w * j) + nrm * (cup * w * (j * j) - cup * w * 0.4)
            orow.append(bm.verts.new(c + nrm * half))
            irow.append(bm.verts.new(c - nrm * half))
        out.append(orow)
        inn.append(irow)

    def quad(vs, cols, wet):
        # the tip collapses to a point: drop the repeated corner rather than make a sliver face
        uniq = []
        for v, c in zip(vs, cols):
            if all((u[0].co - v.co).length > 1e-6 for u in uniq):
                uniq.append((v, c))
        if len(uniq) < 3:
            return
        try:
            f = bm.faces.new([u[0] for u in uniq])
        except ValueError:
            return
        f[kind_layer] = K_STRIP
        for lp, (_, c) in zip(f.loops, uniq):
            lp[col_layer] = (c[0], c[1], c[2], wet)

    dark = srgb((0.22, 0.03, 0.035))
    edge_col = srgb((0.36, 0.06, 0.055))
    for k in range(n - 1):
        t0, t1 = k / (n - 1), (k + 1) / (n - 1)
        in0, in1 = mix(inner, dark, t0 * 0.6), mix(inner, dark, t1 * 0.6)
        ed0, ed1 = mix(edge_col, dark, t0 * 0.5), mix(edge_col, dark, t1 * 0.5)
        for j in range(2):
            quad([out[k][j], out[k][j + 1], out[k + 1][j + 1], out[k + 1][j]], [outer] * 4, 0.0)
            quad([inn[k][j], inn[k + 1][j], inn[k + 1][j + 1], inn[k][j + 1]], [in0, in1, in1, in0], 0.8)
        quad([out[k][0], out[k + 1][0], inn[k + 1][0], inn[k][0]], [ed0, ed1, ed1, ed0], 0.8)
        quad([out[k][2], inn[k][2], inn[k + 1][2], out[k + 1][2]], [ed0, ed0, ed1, ed1], 0.8)


def add_blob(centre, radius, colour, squash=(1, 1, 1), subdiv=1):
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    vs = res["verts"]
    for v in vs:
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2])) + centre
    for f in {f for v in vs for f in v.link_faces}:
        f[kind_layer] = KIND
        for lp in f.loops:
            lp[col_layer] = (colour[0], colour[1], colour[2], 0.0)
    return vs


def slab_extent(y, tol):
    sel = vco[np.abs(vco[:, 1] - y) < tol]
    if len(sel) == 0:
        return None
    return sel[:, 2].min(), sel[:, 2].max(), np.abs(sel[:, 0]).max()


# ribs through the flank wound: thick curved bones rooted in a spine knuckle, over a dark cavity,
# with the guts spilling out below
ribsite = next(s for s in sites if s["kind"] == "ribs")
rib_lo, rib_hi = CFG["rib_range"]
rsign = 1.0 if ribsite["c"].x >= 0 else -1.0
nrib = 7 if SPECIES == "trex" else 6
rr = ribsite["r"] * 0.11
zspine = None
for k in range(nrib):
    y = Y0 + (rib_lo + (rib_hi - rib_lo) * k / (nrib - 1)) * LEN
    ext = slab_extent(y, LEN * 0.012)
    if ext is None:
        continue
    zmin, zmax, xmax = ext
    zc = (zmin + zmax) / 2
    zr = (zmax - zmin) / 2
    pts = []
    for a in np.linspace(math.radians(8), math.radians(135), 10):
        pts.append(Vector((rsign * xmax * 0.86 * math.sin(a), y, zc + zr * 0.86 * math.cos(a))))
    add_tube(pts, rr, rr * 0.4, BONE_L, 6)
    zspine = pts[0].z
    # a vertebra knuckle where the rib roots
    add_blob(pts[0] + Vector((-rsign * rr * 0.4, 0, 0)), rr * 1.5, BONE_L, (1, 0.8, 1), 1)
if zspine is not None:
    y0 = Y0 + rib_lo * LEN
    y1 = Y0 + rib_hi * LEN
    add_tube([Vector((rsign * ribsite["r"] * 0.0 + rsign * 0.02, y0, zspine)), Vector((rsign * 0.02, (y0 + y1) / 2, zspine)),
              Vector((rsign * 0.02, y1, zspine))], rr * 1.1, rr * 1.1, BONE_L, 6, cap=False)
KIND = K_GUT
# intestines: thin, glossy, tapering coils with a few bulging segments, looping out of the opened
# belly and down the flank
gut_r = ribsite["r"] * 0.1
GUT_TONES = [srgb(GUT), srgb((0.60, 0.28, 0.32)), srgb((0.40, 0.15, 0.26)), srgb((0.56, 0.26, 0.22))]
for coil in range(3):
    c0 = ribsite["c"] + Vector((0, RNG.uniform(-0.3, 0.3) * ribsite["r"], -ribsite["r"] * (0.1 + 0.2 * coil)))
    ph = RNG.uniform(0, 6.0)
    pts, radii, cols = [], [], []
    N = 16
    for k in range(N):
        t = k / (N - 1)
        pts.append(c0 + Vector((rsign * (gut_r * 1.6 + ribsite["r"] * (0.16 * math.sin(t * math.pi) + 0.05 * math.sin(t * 9.0 + ph))),
                                 math.sin(t * 6.0 + ph) * ribsite["r"] * 0.3 * (0.4 + t),
                                 -t * ribsite["r"] * (0.7 + 0.2 * coil) + math.sin(t * 11.0 + ph) * gut_r * 0.8)))
        # segments bulge between pinches, and the whole thing tapers toward its torn end
        radii.append(gut_r * (1.0 - 0.55 * t) * (0.78 + 0.32 * abs(math.sin(t * math.pi * 3.5 + ph))))
        cols.append(mix(GUT_TONES[(k // 3 + coil) % 4], GUT_TONES[(k // 3 + coil + 1) % 4], (k % 3) / 3.0))
    add_tube(pts, 0, 0, None, 10, wet=1.0, radii=radii, seg_cols=cols)

KIND = K_BONE
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
            ln = CFG["tooth"] * RNG.uniform(0.5, 1.2) * (1.1 if t > 0.8 else 1.0)
            dirv = Vector((RNG.uniform(-0.25, 0.25), RNG.uniform(0.05, 0.3), 1.0 if lower else -1.0)).normalized()
            add_tube([p, p + dirv * ln * 0.5, p + dirv * ln], ln * 0.2, ln * 0.03, srgb((0.9, 0.85, 0.66)), 5)


half = CFG["teeth"] // 2
row(CFG["mouth_up"][0], CFG["mouth_up"][1], half, False)
row(CFG["mouth_lo"][0], CFG["mouth_lo"][1], half, True)

KIND = K_STRIP
# hanging strips of torn hide, rooted on the rim of every wound and drooping under their own weight
for si, st in enumerate(sites):
    if st["kind"] == "socket":
        continue
    nflap = 2 if st.get("major") else 1
    n = surface_normal(st["c"])
    t1 = n.cross(Vector((0, 0, 1)))
    if t1.length < 0.1:
        t1 = n.cross(Vector((0, 1, 0)))
    t1.normalize()
    t2 = n.cross(t1).normalized()
    for k in range(nflap):
        th = RNG.uniform(0, 2 * math.pi)
        rim = st["c"] + (t1 * math.cos(th) + t2 * math.sin(th)) * st["r"] * 0.62
        base = snap_to_surface(rim)
        nn = surface_normal(base)
        L = st["r"] * RNG.uniform(0.6, 1.1)
        down = Vector((0, 0, -1))
        sway = Vector((RNG.uniform(-1, 1), RNG.uniform(-1, 1), 0)).normalized()
        ph = RNG.uniform(0, 6.0)
        path = []
        for kk in range(7):
            t = kk / 6
            # roots under the rim, arcs out of the wound, then hangs, curling a little at the end
            path.append(base - nn * 0.01 * LEN + nn * L * (0.22 * math.sin(t * 2.4)) + down * L * (t * 0.95)
                        + sway * L * 0.1 * math.sin(t * 3.0 + ph) * t)
        side = (path[-1] - path[0]).cross(nn)
        if side.length < 1e-4:
            side = t2
        side.normalize()
        add_ribbon(path, st["r"] * RNG.uniform(0.1, 0.18), st["r"] * 0.015, side,
                   srgb((0.36, 0.36, 0.24)), srgb((0.52, 0.07, 0.07)))
# the lower jaw's cheek hangs in tatters
for k in range(4):
    fl = RNG.uniform(J["fl_min"] + 0.02, 0.97)
    sgn = -1 if k % 2 == 0 else 1
    base = snap_to_surface(P(fl, J["fh_max"] - 0.02, sgn * 0.5))
    L = HEIGHT * RNG.uniform(0.07, 0.12)
    path = [base + Vector((sgn * L * 0.06 * math.sin(t * 3.0), 0.02 * LEN * t, -L * 1.2 * t)) for t in (0.0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1.0)]
    add_ribbon(path, L * 0.17, L * 0.02, Vector((0, 1, 0)), srgb((0.45, 0.38, 0.28)), srgb((0.52, 0.07, 0.07)))

KIND = K_TUMOUR
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
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=CFG["eye_r"] * 0.75)
    cen = snap_to_surface(P(fl, fh, fw * 0.85))
    out = Vector((1 if fw > 0 else -1, 0.25, 0.1)).normalized()
    for v in res["verts"]:
        v.co = v.co + cen + out * CFG["eye_r"] * 0.2
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = 1
        f[kind_layer] = K_EYE
        eye_faces.append(f)
        for lp in f.loops:
            lp[col_layer] = (1.0, 0.85, 0.1, 1.0)

# Everything added after the wound pass rests where it is built; the body's verts rest where they were
# before the wounds sank them (that is where the bake's fields are evaluated).
for v in bm.verts:
    if v[rest_set] == 0.0:
        v[rest_layer] = v.co
bm.faces.index_update()
eye_idx = [f.index for f in eye_faces]
bm.to_mesh(mesh)
bm.free()
mesh.update()

# materials: 0 the infected body (the game draws it with view/zhm_view.gd's shader and the baked
# textures; this one only names it), 1 glowing eyes
mesh.materials.clear()
body = bpy.data.materials.new("Infected")
body.use_nodes = True
b_bsdf = next(n for n in body.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
b_bsdf.inputs["Roughness"].default_value = 0.85
eyem = bpy.data.materials.new("EyesGlow")
eyem.use_nodes = True
e_bsdf = next(n for n in eyem.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
e_bsdf.inputs["Base Color"].default_value = (0.9, 0.9, 0.2, 1)
e_bsdf.inputs["Emission Color"].default_value = (1.0, 0.8, 0.02, 1)
e_bsdf.inputs["Emission Strength"].default_value = 3.5
mesh.materials.append(body)
mesh.materials.append(eyem)
# clear() above reset every face to material 0, so the eyes are assigned here
for i in eye_idx:
    mesh.polygons[i].material_index = 1
for p in mesh.polygons:
    p.use_smooth = True

exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "bake_monsters.py")).read())

# skeleton and weights
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
                          export_skins=True, export_vertex_color="NONE")
