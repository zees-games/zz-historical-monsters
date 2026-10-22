"""Second half of build_monsters.py, executed in its namespace (it shares the bmesh results, fields and config).

UV-unwraps the finished mesh and bakes the infected look into textures: an albedo whose alpha is wetness, and a
tangent-space normal map. Detail lives here instead of in vertices (the mesh is at its triangle budget): muscle
fibres, fat, clotted blood, the bruised rim of a wound, rotted patches, cracks, veins, and the wet gloss.

Every texel is evaluated from the position its surface point had before the wounds sank it (the "rest" vertex
attribute, interpolated), with the same numpy noise and wound field the geometry used, so a wound's outline in
the texture is the outline of its cavity in the mesh. Deterministic.
"""
TEX = CFG.get("tex", 1024)
TEXDIR = os.path.join(os.path.dirname(os.path.abspath(OUT)), "textures")
os.makedirs(TEXDIR, exist_ok=True)

# ---- unwrap
mesh.uv_layers.new(name="UVMap")
mesh.uv_layers.active = mesh.uv_layers["UVMap"]
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(78), island_margin=0.003, scale_to_bounds=True)
bpy.ops.object.mode_set(mode="OBJECT")
# Bone, teeth and tumours are small, flat-coloured and mostly seen from afar: their islands are shrunk so the
# square's texels go to the body, the guts and the strips that carry the detail.
poly_kind0 = np.empty(len(mesh.polygons), np.int32)
mesh.attributes["kind"].data.foreach_get("value", poly_kind0)
KIND_UV_SCALE = {K_BODY: 1.0, K_BONE: 0.3, K_GUT: 0.9, K_STRIP: 0.7, K_TUMOUR: 0.3, K_EYE: 0.1}
_uv = mesh.uv_layers["UVMap"]
_loops = {}
_parent = list(range(len(mesh.polygons)))


def _find(a):
    while _parent[a] != a:
        _parent[a] = _parent[_parent[a]]
        a = _parent[a]
    return a


_seen = {}
for poly in mesh.polygons:
    for li in poly.loop_indices:
        key = (mesh.loops[li].vertex_index, round(_uv.data[li].uv[0], 5), round(_uv.data[li].uv[1], 5))
        if key in _seen:
            _parent[_find(poly.index)] = _find(_seen[key])
        else:
            _seen[key] = poly.index
_islands = {}
for poly in mesh.polygons:
    _islands.setdefault(_find(poly.index), []).append(poly)
for polys in _islands.values():
    f = KIND_UV_SCALE[int(poly_kind0[polys[0].index])]
    if f == 1.0:
        continue
    lis = [li for p_ in polys for li in p_.loop_indices]
    cen = sum((_uv.data[li].uv for li in lis), Vector((0, 0))) / len(lis)
    for li in lis:
        _uv.data[li].uv = cen + (_uv.data[li].uv - cen) * f
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
# smart_project leaves a third of the square used; packing again, rotating, fills it and so raises texel density
bpy.ops.uv.pack_islands(rotate=True, margin=0.0015, shape_method="CONCAVE")
bpy.ops.object.mode_set(mode="OBJECT")

mesh.calc_loop_triangles()
lt = mesh.loop_triangles
T = len(lt)
nloops = len(mesh.loops)
tri_loops = np.empty(T * 3, np.int32)
lt.foreach_get("loops", tri_loops)
tri_loops = tri_loops.reshape(T, 3)
tri_verts = np.empty(T * 3, np.int32)
lt.foreach_get("vertices", tri_verts)
tri_verts = tri_verts.reshape(T, 3)
tri_poly = np.empty(T, np.int32)
lt.foreach_get("polygon_index", tri_poly)

uv_new = np.empty(nloops * 2, np.float32)
mesh.uv_layers["UVMap"].data.foreach_get("uv", uv_new)
uv_new = uv_new.reshape(-1, 2)
uv_old = np.zeros(nloops * 2, np.float32)
if "orig" in mesh.uv_layers:
    mesh.uv_layers["orig"].data.foreach_get("uv", uv_old)
uv_old = uv_old.reshape(-1, 2)
rest = np.empty(len(mesh.vertices) * 3, np.float32)
mesh.attributes["rest"].data.foreach_get("vector", rest)
rest = rest.reshape(-1, 3)
vnorm = np.empty(len(mesh.vertices) * 3, np.float32)
mesh.vertex_normals.foreach_get("vector", vnorm)
vnorm = vnorm.reshape(-1, 3)
cols = np.empty(nloops * 4, np.float32)
mesh.attributes["Col"].data.foreach_get("color", cols)
cols = cols.reshape(-1, 4)
poly_kind = np.empty(len(mesh.polygons), np.int32)
mesh.attributes["kind"].data.foreach_get("value", poly_kind)
poly_mat = np.empty(len(mesh.polygons), np.int32)
mesh.polygons.foreach_get("material_index", poly_mat)

# ---- rasterise the triangles into texel space
tri_id = np.full((TEX, TEX), -1, np.int32)
bary = np.zeros((TEX, TEX, 3), np.float32)
for ti in range(T):
    q = uv_new[tri_loops[ti]] * TEX
    x0, y0 = np.floor(q.min(0) - 1).astype(int)
    x1, y1 = np.ceil(q.max(0) + 1).astype(int)
    x0, y0 = max(x0, 0), max(y0, 0)
    x1, y1 = min(x1, TEX - 1), min(y1, TEX - 1)
    if x1 < x0 or y1 < y0:
        continue
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    (ax, ay), (bx, by), (cx, cy) = q
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-12:
        continue
    w0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
    w1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
    w2 = 1.0 - w0 - w1
    eps = -0.02
    inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
    if not inside.any():
        continue
    yy, xx = np.nonzero(inside)
    tri_id[yy + y0, xx + x0] = ti
    bary[yy + y0, xx + x0] = np.stack([w0[inside], w1[inside], w2[inside]], 1)
valid = tri_id >= 0
print("BAKE texels used", round(valid.mean(), 3))
rows, colsx = np.nonzero(valid)
ti = tri_id[rows, colsx]
bw = bary[rows, colsx]
bw = np.clip(bw, 0.0, 1.0)
bw /= bw.sum(1, keepdims=True)


def interp_v(arr):
    return np.einsum("nk,nkc->nc", bw, arr[tri_verts[ti]])


def interp_l(arr):
    return np.einsum("nk,nkc->nc", bw, arr[tri_loops[ti]])


Pt = interp_v(rest).astype(np.float64)
Nt = interp_v(vnorm).astype(np.float64)
Nt /= np.maximum(np.linalg.norm(Nt, axis=1, keepdims=True), 1e-9)
Ct = interp_l(cols).astype(np.float64)
UVo = interp_l(uv_old).astype(np.float64)
Kt = poly_kind[tri_poly[ti]]
Mt = poly_mat[tri_poly[ti]]
NT = len(Pt)

# ---- shading helpers (all arrays are (N,) or (N, 3), linear colour)
SC = max(0.5, LEN / 3.0)


def mixa(a, b, t):
    t = np.asarray(t)[:, None]
    return np.asarray(a) * (1 - t) + np.asarray(b) * t


def lin(c):
    return np.array([x ** 2.2 for x in c])


def sample_base(uv, mat):
    out = np.zeros((len(uv), 3))
    for mi in np.unique(mat):
        sel = np.nonzero(mat == mi)[0]
        img = BASE_IMGS[min(mi, len(BASE_IMGS) - 1)]
        if img.ndim == 1:
            out[sel] = img
            continue
        h, w = img.shape[:2]
        x = (uv[sel, 0] % 1.0) * (w - 1)
        y = (uv[sel, 1] % 1.0) * (h - 1)
        xi, yi = np.floor(x).astype(int), np.floor(y).astype(int)
        fx, fy = (x - xi)[:, None], (y - yi)[:, None]
        xj, yj = np.minimum(xi + 1, w - 1), np.minimum(yi + 1, h - 1)
        out[sel] = ((img[yi, xi] * (1 - fx) + img[yi, xj] * fx) * (1 - fy)
                    + (img[yj, xi] * (1 - fx) + img[yj, xj] * fx) * fy)
    return out


def fibre_streak(P, seed):
    """Muscle fibres run along the body, so the stripes vary across it; warped so they are not ruled."""
    warp = fbm(P, 8.0 / SC, 2, 1.1 + seed) * 11.0
    f1 = 0.5 + 0.5 * np.sin((P[:, 2] + P[:, 0] * 0.6) * (150.0 / SC) + warp)
    f2 = 0.5 + 0.5 * np.sin((P[:, 2] * 0.6 - P[:, 0]) * (270.0 / SC) + warp * 1.7 + 1.3)
    f3 = 0.5 + 0.5 * np.sin((P[:, 2] + P[:, 1] * 0.15) * (520.0 / SC) + warp * 2.3)
    return 0.55 * f1 + 0.3 * f2 + 0.15 * f3


SK_CODE = {"flesh": 0, "bone": 1, "ribs": 2, "socket": 3, "rot": 4}
site_code = np.array([SK_CODE[st["kind"]] for st in sites])
J = CFG["jaw"]

rgb = np.zeros((NT, 3))
wet = np.zeros(NT)
hgt = np.zeros(NT)


def bake_body(idx):
    P, base = Pt[idx], sample_base(UVo[idx], Mt[idx])
    n = len(P)
    grey = base.mean(1, keepdims=True)
    c1 = base * 0.55 + grey * 0.45
    c1 = c1 * CFG["skin_dark"]
    c1 = mixa(c1, lin(CFG["skin_tint"]), np.full(n, CFG["skin_tint_amount"]))
    # sick skin: drained, then a pallid rotten tone, mottled with rot, bruise, pus and dry cracks
    blot = fbm(P, 2.6 / SC, 3, 9.1)
    c1 = mixa(c1, lin((0.30, 0.38, 0.16)), smooth(0.05, 0.4, blot) * 0.7)
    bruise = fbm(P, 5.0 / SC, 3, 3.3)
    c1 = mixa(c1, lin((0.38, 0.14, 0.32)), smooth(0.2, 0.5, bruise) * 0.6)
    pus = fbm(P, 12.0 / SC, 3, 7.7)
    pusm = smooth(0.45, 0.6, pus)
    c1 = mixa(c1, lin((0.72, 0.66, 0.30)), pusm * 0.85)
    crack = np.abs(fbm(P, 9.0 / SC, 3, 12.5))
    crack2 = np.abs(fbm(P, 26.0 / SC, 2, 4.4))
    crk = np.maximum(smooth(0.035, 0.0, crack), smooth(0.02, 0.0, crack2) * 0.6)
    c1 = mixa(c1, lin((0.05, 0.03, 0.02)), crk * 0.4)
    grain = fbm(P, 110.0 / SC, 2, 2.7)
    c1 = c1 * (1.0 + 0.22 * grain)[:, None]
    cap = lin((CFG["skin_cap"],) * 3)[0]
    c1 = np.minimum(c1, cap)
    fl_ = CFG.get("skin_floor", 0.0)
    if fl_:
        c1 = np.maximum(c1, lin((fl_,) * 3)[0] * np.array([1.2, 0.8, 0.8]))
    h_skin = 0.35 * grain - 1.0 * crk + 0.7 * pusm
    w = np.zeros(n)

    m, own = wound_field(P)
    m = m + 0.07 * fbm(P, 70.0 / SC, 2, 3.1) + 0.16 * fbm(P, 40.0 / SC, 3, 7.3)
    code = np.where(own >= 0, site_code[np.maximum(own, 0)], 0)
    bruise_rim = smooth(-0.4, -0.1, m) * (1.0 - smooth(0.0, 0.16, m))
    lip = smooth(-0.05, 0.05, m) * (1.0 - smooth(0.06, 0.2, m))
    edge = smooth(0.04, 0.26, m)
    core = smooth(0.1, 0.34, m)
    inner = smooth(0.55, 1.05, m)
    fibre = fibre_streak(P, 0.0)
    streak = 0.22 + 0.9 * fibre
    marble = fbm(P, 20.0 / SC, 3, 3.7)
    muscle = np.array(lin((0.74, 0.10, 0.08))) * streak[:, None]
    muscle = mixa(muscle, lin((0.42, 0.04, 0.06)), smooth(-0.1, 0.3, marble) * 0.7)
    fat = smooth(0.1, 0.3, fbm(P, 11.0 / SC, 3, 5.1)) * smooth(0.2, 0.5, m) * (1.0 - inner * 0.6)
    fat_tex = 0.8 + 0.4 * fbm(P, 90.0 / SC, 2, 1.9)
    muscle = mixa(muscle, lin((0.86, 0.68, 0.50)) * fat_tex[:, None], fat * 0.75)
    clot = smooth(0.05, 0.3, fbm(P, 13.0 / SC, 3, 8.8)) * smooth(0.3, 0.7, m)
    muscle = mixa(muscle, lin((0.20, 0.012, 0.018)), clot * 0.65)
    floor_c = mixa(muscle, lin(DEEP), inner * 0.6)
    wet_k = np.ones(n)
    bone_w = smooth(0.25, 0.55, m) * 0.95
    bone_c = lin(BONE_COL)[None, :] * (0.8 + 0.2 * fibre)[:, None]
    floor_c = np.where((code == 1)[:, None], mixa(floor_c, bone_c, bone_w), floor_c)
    wet_k = np.where(code == 1, 0.5, wet_k)
    ribs_c = mixa(mixa(lin((0.50, 0.05, 0.06)), lin((0.84, 0.64, 0.50)), fat * 0.5), lin(DEEP), smooth(0.4, 0.9, m))
    ribs_c = mixa(ribs_c, lin((0.12, 0.005, 0.01)), clot * 0.8)
    floor_c = np.where((code == 2)[:, None], ribs_c, floor_c)
    sock_c = mixa(lin((0.10, 0.02, 0.05)), lin((0.01, 0.0, 0.0)), smooth(0.3, 0.6, m))
    floor_c = np.where((code == 3)[:, None], sock_c, floor_c)
    rot_c = mixa(lin((0.40, 0.45, 0.10)), lin((0.10, 0.10, 0.02)), inner)
    rot_c = rot_c * (0.75 + 0.5 * fbm(P, 40.0 / SC, 2, 6.6))[:, None]
    floor_c = np.where((code == 4)[:, None], rot_c, floor_c)
    wet_k = np.where(code == 4, 0.6, wet_k)
    c1 = mixa(c1, lin((0.22, 0.10, 0.14)), bruise_rim * 0.8)
    c1 = mixa(c1, lin(NECROTIC), lip * 0.55)
    edge_c = np.where((code == 3)[:, None], lin((0.18, 0.02, 0.04))[None, :], lin((0.50, 0.05, 0.06))[None, :])
    c1 = mixa(c1, edge_c, edge * (1.0 - core) * 0.9)
    c1 = mixa(c1, floor_c, core)
    w = smooth(0.1, 0.4, m) * wet_k * (1.0 - 0.45 * clot)
    # relief: fibres ridge the muscle, clots and fat swell, the dead lip is a raised welt
    h_wound = (fibre - 0.5) * 1.8 + clot * 0.9 + fat * 0.4 * fbm(P, 60.0 / SC, 2, 8.1) + 0.3 * fbm(P, 40.0 / SC, 2, 2.2)
    h = h_skin * (1.0 - core) + h_wound * core + 0.8 * lip

    # blood: drips running down from every wound, and a darkening round it
    near = np.full(n, 1e9)
    for st in sites:
        c = st["c"]
        dxy = np.hypot(P[:, 0] - c.x, P[:, 1] - c.y) / (st["r"] * 1.8)
        ok = (P[:, 2] < c.z + st["r"] * 0.5) & (dxy < 1.0)
        near = np.where(ok, np.minimum(near, dxy), near)
    drip = fbm(P * np.array([70.0, 70.0, 6.0]), 1.0 / SC, 2, 5.5)
    blood_t = smooth(1.0, 0.1, near) * smooth(-0.15, 0.25, drip)
    fl = (P[:, 1] - Y0) / LEN
    fhh = P[:, 2] / HEIGHT
    muz = (fl > J["fl_min"]) & (fhh < J["fh_max"] + 0.02)
    muzzle = np.where(muz, 0.85 * smooth(-0.3, 0.2, fbm(P, 6.0, 2, 2.2)), 0.0)
    blood_t = np.maximum(blood_t, muzzle)
    gum_z = (fl > J["fl_min"] - 0.01) & (np.abs(fhh - J["fh_max"]) < 0.035)
    gum = np.where(gum_z, 1.0 - smooth(0.012, 0.035, np.abs(fhh - J["fh_max"])), 0.0)
    c1 = mixa(c1, lin((0.62, 0.08, 0.10)), 0.9 * gum)
    w = np.maximum(w, 0.5 * gum)
    c1 = mixa(c1, lin((0.26, 0.018, 0.026)), blood_t * 0.72)
    w = np.maximum(w, blood_t * 0.5)
    h = h - 0.3 * blood_t
    rgb[idx], wet[idx], hgt[idx] = c1, np.clip(w, 0, 1), h


def bake_other(idx, kind):
    P, col = Pt[idx], Ct[idx]
    base_c, base_w = col[:, :3], col[:, 3]
    n = len(P)
    if kind == K_BONE:
        mott = fbm(P, 50.0 / SC, 3, 1.3)
        stain = smooth(0.0, 0.35, fbm(P, 16.0 / SC, 2, 3.4))
        c = base_c * (0.85 + 0.3 * mott)[:, None]
        c = mixa(c, lin((0.45, 0.32, 0.16)), stain * 0.55)
        c = mixa(c, lin((0.30, 0.03, 0.03)), smooth(0.2, 0.5, fbm(P, 30.0 / SC, 2, 9.9)) * 0.45)
        h = 0.5 * mott
        w = np.full(n, 0.25)
    elif kind == K_GUT:
        vein = np.abs(fbm(P, 38.0 / SC, 3, 6.0))
        vl = smooth(0.07, 0.0, vein)
        mott = fbm(P, 60.0 / SC, 2, 2.4)
        c = base_c * (0.88 + 0.3 * mott)[:, None]
        c = mixa(c, lin((0.40, 0.08, 0.17)), vl * 0.6)
        c = mixa(c, lin((0.70, 0.42, 0.40)), smooth(0.3, 0.55, mott) * 0.2)
        h = -0.4 * vl + 0.2 * mott
        w = np.full(n, 0.95)
    elif kind == K_STRIP:
        fib = fibre_streak(P, 3.0)
        fleshy = base_w > 0.5
        c = base_c * (0.55 + 0.7 * fib)[:, None]
        mott = fbm(P, 40.0 / SC, 3, 5.3)
        c_flesh = mixa(c, lin((0.80, 0.62, 0.46)) * (0.8 + 0.4 * mott)[:, None], smooth(0.1, 0.4, fbm(P, 14.0 / SC, 2, 1.7)) * 0.55)
        c_flesh = mixa(c_flesh, lin((0.18, 0.012, 0.016)), smooth(0.1, 0.35, fbm(P, 22.0 / SC, 2, 8.8)) * 0.6)
        crk = smooth(0.05, 0.0, np.abs(fbm(P, 30.0 / SC, 2, 4.4)))
        c_hide = base_c * (0.8 + 0.4 * mott)[:, None]
        c_hide = mixa(c_hide, lin((0.05, 0.03, 0.02)), crk * 0.6)
        c = np.where(fleshy[:, None], c_flesh, c_hide)
        h = np.where(fleshy, (fib - 0.5) * 1.1 + 0.3 * mott, 0.3 * mott - crk)
        w = base_w * 0.9
    else:  # tumour
        vein = np.abs(fbm(P, 30.0 / SC, 3, 6.0))
        mott = fbm(P, 45.0 / SC, 3, 2.4)
        c = base_c * (0.8 + 0.4 * mott)[:, None]
        c = mixa(c, lin((0.35, 0.05, 0.14)), smooth(0.08, 0.0, vein) * 0.7)
        h = 0.4 * mott - 0.4 * smooth(0.08, 0.0, vein)
        w = np.full(n, 0.6)
    rgb[idx], wet[idx], hgt[idx] = c, w, h


bake_body(np.nonzero(Kt == K_BODY)[0])
for k in (K_BONE, K_GUT, K_STRIP, K_TUMOUR):
    sel = np.nonzero(Kt == k)[0]
    if len(sel):
        bake_other(sel, k)
sel = np.nonzero(Kt == K_EYE)[0]
rgb[sel] = 0.5

# ---- images: scatter, pad outward past the islands' edges so filtering never reads background, write
alb = np.zeros((TEX, TEX, 4), np.float32)
H = np.zeros((TEX, TEX), np.float32)
out = np.clip(rgb, 0.0, 1.0) ** (1.0 / 2.2)
alb[rows, colsx, :3] = out
alb[rows, colsx, 3] = wet
H[rows, colsx] = hgt
mask = valid.copy()
for _ in range(6):
    grow = np.zeros_like(mask)
    acc = np.zeros_like(alb)
    cnt = np.zeros(mask.shape, np.float32)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        sh = np.roll(np.roll(mask, dy, 0), dx, 1)
        src = np.roll(np.roll(alb, dy, 0), dx, 1)
        take = sh & ~mask
        acc += np.where(take[..., None], src, 0)
        cnt += take
    fill = cnt > 0
    alb[fill] = acc[fill] / cnt[fill][:, None]
    mask = mask | fill
alb[..., 3] = np.where(mask, alb[..., 3], 0.0)

# normal map from the height field; heights are not defined across island borders, so the slope there is zeroed
gy, gx = np.gradient(H)
edge_zone = valid & np.roll(valid, 1, 0) & np.roll(valid, -1, 0) & np.roll(valid, 1, 1) & np.roll(valid, -1, 1)
strength = 3.6
nx = np.where(edge_zone, -gx * strength, 0.0)
ny = np.where(edge_zone, -gy * strength, 0.0)
nz = np.ones_like(nx)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
nrm = np.stack([nx / ln, ny / ln, nz / ln, np.ones_like(nx)], -1) * 0.5 + 0.5
nrm[..., 3] = 1.0


def save_png(arr, name):
    img = bpy.data.images.new(name, TEX, TEX, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.alpha_mode = "CHANNEL_PACKED"
    img.pixels.foreach_set(arr.astype(np.float32).ravel())
    img.filepath_raw = os.path.join(TEXDIR, name + ".png")
    img.file_format = "PNG"
    img.save()


save_png(alb, SPECIES + "_albedo")
save_png(nrm, SPECIES + "_normal")

# the glb carries geometry, UVs and skin only: textures ship beside it and the view binds them
for nm in ("orig",):
    if nm in mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[nm])
for nm in ("rest", "kind", "Col"):
    if nm in mesh.attributes:
        mesh.attributes.remove(mesh.attributes[nm])
