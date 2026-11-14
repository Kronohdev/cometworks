"""Voxel kit for the Cometworks campus buildings (tools/build_campus_buildings.py).

A Grid holds two uint8 volumes at a fixed voxel size (10 cm): `col` (palette index, 0 = empty)
and `tag` (which mesh piece the voxel belongs to: the always-visible base, or one of the
cutaway pieces that src/tycoon/campus_building.gd hides when the camera comes close).
Props are built once into small Stamps and pasted with 90 degree turns.

Meshing ("voxel, but soft", docs/creatures.md): only exposed faces, greedy-merged where the
colour and the baked ambient occlusion are uniform, AO baked into vertex colours (linear).
Vertex alpha < 1 marks emissive voxels (windows, screens, bulbs): the campus shader
(shaders/campus_voxel.gdshader) turns (1 - alpha) * 8 into emission energy.

A face is skipped only when its neighbour is in the same piece or in the base, so hiding a
cutaway piece never opens holes in what stays.
"""
import json
import math
import struct

import numpy as np

VPM = 10                       # voxels per metre
VOX = 1.0 / VPM
AO_LEVEL = np.array([0.52, 0.70, 0.86, 1.0], np.float32)
GLOW_MAX = 8.0
AO_DIAGONAL = True      # corner-only neighbours darken too (softer, but more quads)

# pieces (tags)
BASE, ROOF, CUT_PX, CUT_NX, CUT_PZ, CUT_NZ, UPPER = 1, 2, 3, 4, 5, 6, 7
PIECE_NAME = {BASE: "Base", ROOF: "CutRoof", CUT_PX: "CutPX", CUT_NX: "CutNX", CUT_PZ: "CutPZ",
              CUT_NZ: "CutNZ", UPPER: "CutUpper"}


# ------------------------------------------------------------------ palette
class Palette:
    """Global colour table: index -> (linear rgb, glow energy). Index 0 is empty."""

    def __init__(self):
        self.rgb = [(0.0, 0.0, 0.0)]
        self.glow = [0.0]
        self._idx = {}

    def __call__(self, hexcol, glow=0.0):
        key = (hexcol.lower(), round(glow, 2))
        if key not in self._idx:
            if len(self.rgb) >= 255:
                raise RuntimeError("campus palette full")
            h = hexcol.lstrip("#")
            srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
            self.rgb.append(tuple(c ** 2.2 for c in srgb))
            self.glow.append(glow)
            self._idx[key] = len(self.rgb) - 1
        return self._idx[key]

    def arrays(self):
        return np.array(self.rgb, np.float32), np.array(self.glow, np.float32)


PAL = Palette()


def m2v(x):
    """metres -> voxel boundary index"""
    return int(math.floor(x * VPM + 0.5 + 1e-7))


# ------------------------------------------------------------------ stamps (props)
class Stamp:
    """A small voxel model in its own frame: x right, y up, z towards the viewer (+z = the
    side a person uses: the front of a desk, a screen's face). Origin at the footprint
    centre on the floor."""

    def __init__(self, sx, sy, sz):
        self.nx, self.ny, self.nz = m2v(sx), m2v(sy), m2v(sz)
        self.col = np.zeros((self.nx, self.ny, self.nz), np.uint8)
        self.ox, self.oz = self.nx // 2, self.nz // 2

    def box(self, x0, x1, y0, y1, z0, z1, c):
        """metres in the stamp frame (x/z around the centre, y from the floor)"""
        i0, i1 = max(0, m2v(x0) + self.ox), min(self.nx, m2v(x1) + self.ox)
        j0, j1 = max(0, m2v(y0)), min(self.ny, m2v(y1))
        k0, k1 = max(0, m2v(z0) + self.oz), min(self.nz, m2v(z1) + self.oz)
        if i1 > i0 and j1 > j0 and k1 > k0:
            self.col[i0:i1, j0:j1, k0:k1] = c

    def clear(self, x0, x1, y0, y1, z0, z1):
        self.box(x0, x1, y0, y1, z0, z1, 0)

    def coords(self):
        X = (np.arange(self.nx) - self.ox + 0.5)[:, None, None] / VPM
        Y = (np.arange(self.ny) + 0.5)[None, :, None] / VPM
        Z = (np.arange(self.nz) - self.oz + 0.5)[None, None, :] / VPM
        return X, Y, Z

    def mask(self, m, c):
        self.col[np.broadcast_to(m, self.col.shape)] = c

    def cyl_y(self, cx, cz, r, y0, y1, c, rin=None):
        X, Y, Z = self.coords()
        R = np.sqrt((X - cx) ** 2 + (Z - cz) ** 2)
        m = (R <= r) & (Y >= y0) & (Y <= y1)
        if rin is not None:
            m &= R > rin
        self.mask(m, c)

    def cyl_x(self, cy, cz, r, x0, x1, c, rin=None):
        X, Y, Z = self.coords()
        R = np.sqrt((Y - cy) ** 2 + (Z - cz) ** 2)
        m = (R <= r) & (X >= x0) & (X <= x1)
        if rin is not None:
            m &= R > rin
        self.mask(m, c)

    def cyl_z(self, cx, cy, r, z0, z1, c, rin=None):
        X, Y, Z = self.coords()
        R = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)
        m = (R <= r) & (Z >= z0) & (Z <= z1)
        if rin is not None:
            m &= R > rin
        self.mask(m, c)

    def sphere(self, cx, cy, cz, r, c, rin=None, ymin=None):
        X, Y, Z = self.coords()
        R = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2 + (Z - cz) ** 2)
        m = R <= r
        if rin is not None:
            m &= R > rin
        if ymin is not None:
            m &= Y >= ymin
        self.mask(m, c)


# ------------------------------------------------------------------ grid
class Grid:
    """The voxel volume of one building level, in lot-local metres (x, z around the lot
    centre, y up from the ground; the door side is +z)."""

    def __init__(self, x0, x1, y1, z0, z1):
        self.min = np.array([m2v(x0), 0, m2v(z0)])
        self.nx, self.ny, self.nz = m2v(x1) - m2v(x0), m2v(y1), m2v(z1) - m2v(z0)
        self.col = np.zeros((self.nx, self.ny, self.nz), np.uint8)
        self.tag = np.zeros((self.nx, self.ny, self.nz), np.uint8)
        self.cur = BASE

    # -- index helpers
    def _rng(self, x0, x1, y0, y1, z0, z1):
        i0, i1 = sorted((m2v(x0) - self.min[0], m2v(x1) - self.min[0]))
        j0, j1 = sorted((m2v(y0), m2v(y1)))
        k0, k1 = sorted((m2v(z0) - self.min[2], m2v(z1) - self.min[2]))
        return (slice(max(0, i0), max(0, min(self.nx, i1))), slice(max(0, j0), max(0, min(self.ny, j1))),
                slice(max(0, k0), max(0, min(self.nz, k1))))

    def box(self, x0, x1, y0, y1, z0, z1, c, tag=None):
        s = self._rng(x0, x1, y0, y1, z0, z1)
        self.col[s] = c
        self.tag[s] = self.cur if tag is None else tag

    def clear(self, x0, x1, y0, y1, z0, z1):
        s = self._rng(x0, x1, y0, y1, z0, z1)
        self.col[s] = 0
        self.tag[s] = 0

    def paint(self, x0, x1, y0, y1, z0, z1, c):
        """recolour occupied voxels only"""
        s = self._rng(x0, x1, y0, y1, z0, z1)
        sub = self.col[s]
        sub[sub > 0] = c

    def region(self, x0, x1, y0, y1, z0, z1):
        """(slice, X, Y, Z) with voxel-centre coordinates in metres for a sub-box"""
        s = self._rng(x0, x1, y0, y1, z0, z1)
        X = ((np.arange(s[0].start, s[0].stop) + self.min[0] + 0.5) / VPM)[:, None, None]
        Y = ((np.arange(s[1].start, s[1].stop) + 0.5) / VPM)[None, :, None]
        Z = ((np.arange(s[2].start, s[2].stop) + self.min[2] + 0.5) / VPM)[None, None, :]
        return s, X, Y, Z

    def put_mask(self, s, m, c, tag=None, only_filled=False):
        m = np.broadcast_to(m, self.col[s].shape)
        if only_filled:
            m = m & (self.col[s] > 0)
        sub_c = self.col[s]
        sub_t = self.tag[s]
        sub_c[m] = c
        if c == 0:
            sub_t[m] = 0
        elif not only_filled:
            sub_t[m] = self.cur if tag is None else tag

    def cyl_y(self, cx, cz, r, y0, y1, c, rin=None, tag=None):
        s, X, Y, Z = self.region(cx - r - 0.1, cx + r + 0.1, y0, y1, cz - r - 0.1, cz + r + 0.1)
        R = np.sqrt((X - cx) ** 2 + (Z - cz) ** 2)
        m = R <= r
        if rin is not None:
            m = m & (R > rin)
        self.put_mask(s, m & (Y >= 0), c, tag)

    def sphere(self, cx, cy, cz, r, c, rin=None, ymin=None, tag=None):
        s, X, Y, Z = self.region(cx - r - 0.1, cx + r + 0.1, max(0, cy - r - 0.1), cy + r + 0.1,
                                 cz - r - 0.1, cz + r + 0.1)
        R = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2 + (Z - cz) ** 2)
        m = R <= r
        if rin is not None:
            m = m & (R > rin)
        if ymin is not None:
            m = m & (Y >= ymin)
        self.put_mask(s, m, c, tag)

    def stamp(self, st, x, z, turn=0, y=0.0, tag=None):
        """Paste a Stamp with its origin at (x, y, z), turned `turn` quarter turns
        (0: front faces +z, 1: front faces +x, 2: -z, 3: -x)."""
        a = st.col
        ox, oz = st.ox, st.oz
        nx, nz = st.nx, st.nz
        t = turn % 4
        if t:
            a = np.rot90(a, k=t, axes=(0, 2))   # +z -> +x for one turn
        # origin offset after the turn
        if t == 0:
            o = (ox, oz)
        elif t == 1:
            o = (oz, nx - ox)
        elif t == 2:
            o = (nx - ox, nz - oz)
        else:
            o = (nz - oz, ox)
        i0 = m2v(x) - self.min[0] - o[0]
        k0 = m2v(z) - self.min[2] - o[1]
        j0 = m2v(y)
        ai, aj, ak = a.shape
        si0, sj0, sk0 = max(0, -i0), max(0, -j0), max(0, -k0)
        di0, dj0, dk0 = max(0, i0), max(0, j0), max(0, k0)
        ei = min(ai, self.nx - i0)
        ej = min(aj, self.ny - j0)
        ek = min(ak, self.nz - k0)
        if ei <= si0 or ej <= sj0 or ek <= sk0:
            return
        src = a[si0:ei, sj0:ej, sk0:ek]
        dst = (slice(di0, di0 + src.shape[0]), slice(dj0, dj0 + src.shape[1]), slice(dk0, dk0 + src.shape[2]))
        m = src > 0
        self.col[dst][m] = src[m]
        self.tag[dst][m] = self.cur if tag is None else tag


# ------------------------------------------------------------------ meshing
def _runs(K):
    """1D runs along the last axis of a 2D int array (rows x n), -1 = empty.
    Returns (row, start, length, key)."""
    rows, n = K.shape
    pad = np.full((rows, 1), -1, K.dtype)
    Kp = np.concatenate([pad, K, pad], 1)
    start = (Kp[:, 1:-1] != Kp[:, :-2]) & (Kp[:, 1:-1] >= 0)
    end = (Kp[:, 1:-1] != Kp[:, 2:]) & (Kp[:, 1:-1] >= 0)
    rs, cs = np.nonzero(start)
    re, ce = np.nonzero(end)
    return rs, cs, ce - cs + 1, K[rs, cs]


def mesh_grid(g, origin_y=None):
    """Meshes every piece of a Grid. Returns {tag: (pos, nrm, rgba8, idx, origin)} where
    origin is the node origin (the piece's lowest point for cutaway pieces) and positions
    are relative to it."""
    rgb_tab, glow_tab = PAL.arrays()
    occ = np.pad(g.col > 0, 1)
    tag = np.pad(g.tag, 1)
    col = np.pad(g.col, 1)
    base = np.array([g.min[0] - 1, -1, g.min[2] - 1])  # padded index -> world voxel index
    faces = {t: [] for t in np.unique(g.tag[g.tag > 0])}
    for axis in range(3):
        u_ax, v_ax = (axis + 1) % 3, (axis + 2) % 3
        for s in (1, -1):
            nb_tag = np.roll(tag, -s, axis=axis)
            exposed = (tag > 0) & (nb_tag != tag) & (nb_tag != BASE)
            if axis == 1 and s < 0:
                exposed[:, 1, :] = False          # faces down into the ground are never seen
            p = np.argwhere(exposed)
            if len(p) == 0:
                continue
            n = np.zeros(3, int)
            n[axis] = s
            front = p + n
            corners = [(0, 0), (1, 0), (1, 1), (0, 1)] if s > 0 else [(0, 0), (0, 1), (1, 1), (1, 0)]
            ao = []
            for du, dv in corners:
                e_u = np.zeros(3, int)
                e_v = np.zeros(3, int)
                e_u[u_ax] = 2 * du - 1
                e_v[v_ax] = 2 * dv - 1
                s1 = occ[tuple((front + e_u).T)]
                s2 = occ[tuple((front + e_v).T)]
                cc = occ[tuple((front + e_u + e_v).T)]
                ao.append(np.where(s1 & s2, 0, 3 - (s1.astype(int) + s2 + (cc if AO_DIAGONAL else 0))))
            ao = np.stack(ao, 1)
            ci = col[tuple(p.T)]
            glow = glow_tab[ci] > 0
            ao[glow] = 3
            tg = tag[tuple(p.T)]
            cidx = {c: i for i, c in enumerate(corners)}
            a00, a10, a11, a01 = (ao[:, cidx[c]] for c in ((0, 0), (1, 0), (1, 1), (0, 1)))
            uniform = (ao == ao[:, :1]).all(1)
            const_u = ~uniform & (a00 == a10) & (a01 == a11)       # AO changes along v only
            const_v = ~uniform & ~const_u & (a00 == a01) & (a10 == a11)
            single = ~uniform & ~const_u & ~const_v
            ao_code = ((ao[:, 0] * 4 + ao[:, 1]) * 4 + ao[:, 2]) * 4 + ao[:, 3]
            key = ((tg.astype(np.int64) * 256 + ci) * 256 + ao_code)
            for m, run_ax, merge2 in ((uniform, u_ax, True), (const_u, u_ax, False), (const_v, v_ax, False),
                                      (single, None, False)):
                if not m.any():
                    continue
                _greedy(faces, p[m], key[m], axis, s, u_ax, v_ax, run_ax, merge2, base, corners,
                        rgb_tab, glow_tab, n)
    out = {}
    for t, parts in faces.items():
        if not parts:
            continue
        V = np.concatenate([q[0] for q in parts]) / VPM            # (F,4,3) metres
        N = np.concatenate([q[1] for q in parts])
        C = np.concatenate([q[2] for q in parts])                  # (F,4,4) u8
        A = np.concatenate([q[3] for q in parts])                  # (F,4) ao
        F = len(V)
        oy = 0.0 if t == BASE else float(V[:, :, 1].min())
        org = np.array([0.0, oy, 0.0])
        pos = (V - org).reshape(-1, 3).astype(np.float32)
        nrm = np.repeat(N, 4, 0).astype(np.float32)
        rgba = C.reshape(-1, 4)
        q = np.arange(F)[:, None] * 4
        flip = (A[:, 0] + A[:, 2]) < (A[:, 1] + A[:, 3])
        tri_a = np.concatenate([q + 0, q + 1, q + 2, q + 0, q + 2, q + 3], 1)
        tri_b = np.concatenate([q + 1, q + 2, q + 3, q + 1, q + 3, q + 0], 1)
        idx = np.where(flip[:, None], tri_b, tri_a).reshape(-1).astype(np.uint32)
        # share identical corners (same position, normal and colour) between quads
        q16 = np.round(pos * 20).astype(np.int32)
        key = np.concatenate([q16, np.round(nrm).astype(np.int32), rgba.astype(np.int32)], 1)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        pos, nrm, rgba = pos[first], nrm[first], rgba[first]
        idx = inv.reshape(-1)[idx].astype(np.uint32)
        out[int(t)] = (pos, nrm, rgba, idx, org)
    return out


def _greedy(faces, p, key, axis, s, u_ax, v_ax, run_ax, merge2, base, corners, rgb_tab, glow_tab, n):
    """Merges faces with equal key: runs along run_ax, then (merge2) equal runs on
    consecutive rows of the other in-plane axis. run_ax None: one quad per face."""
    if run_ax is None:
        sl = p[:, axis]
        r0 = p[:, u_ax]
        r1 = p[:, v_ax]
        lu = np.ones(len(p), int)
        lv = np.ones(len(p), int)
        k = key
    else:
        oth = v_ax if run_ax == u_ax else u_ax
        sl_vals, sl_idx = np.unique(p[:, axis], return_inverse=True)
        omin, rmin = p[:, oth].min(), p[:, run_ax].min()
        no = p[:, oth].max() - omin + 1
        nr = p[:, run_ax].max() - rmin + 1
        D = np.full((len(sl_vals), no, nr), -1, np.int64)
        D[sl_idx, p[:, oth] - omin, p[:, run_ax] - rmin] = key
        r, c0, ln, k = _runs(D.reshape(-1, nr))
        sli, oo = r // no, r % no
        cnt = np.ones(len(sli), int)
        if merge2:
            order = np.lexsort((oo, ln, c0, k, sli))
            sli, oo, c0, ln, k = sli[order], oo[order], c0[order], ln[order], k[order]
            brk = np.ones(len(sli), bool)
            brk[1:] = ((sli[1:] != sli[:-1]) | (k[1:] != k[:-1]) | (c0[1:] != c0[:-1]) |
                       (ln[1:] != ln[:-1]) | (oo[1:] != oo[:-1] + 1))
            gid = np.cumsum(brk) - 1
            first = np.nonzero(brk)[0]
            cnt = np.bincount(gid)
            sli, oo, c0, ln, k = sli[first], oo[first], c0[first], ln[first], k[first]
        sl = sl_vals[sli]
        runc = c0 + rmin
        othc = oo + omin
        if run_ax == u_ax:
            r0, r1, lu, lv = runc, othc, ln, cnt
        else:
            r0, r1, lu, lv = othc, runc, cnt, ln
    code = (k % 256).astype(int)
    ao = np.stack([(code >> 6) & 3, (code >> 4) & 3, (code >> 2) & 3, code & 3], 1)
    ci = ((k // 256) % 256).astype(int)
    tg = (k // 65536).astype(int)
    lo = np.zeros((len(k), 3), np.float64)
    lo[:, axis] = sl + base[axis] + (1 if s > 0 else 0)
    lo[:, u_ax] = r0 + base[u_ax]
    lo[:, v_ax] = r1 + base[v_ax]
    V = []
    for du, dv in corners:
        vp = lo.copy()
        vp[:, u_ax] += du * lu
        vp[:, v_ax] += dv * lv
        V.append(vp)
    _collect(faces, tg, np.stack(V, 1), n, ci, ao, rgb_tab, glow_tab)


def _collect(faces, tg, V, n, ci, ao, rgb_tab, glow_tab):
    F = len(V)
    lin = rgb_tab[ci][:, None, :] * AO_LEVEL[ao][:, :, None]          # (F,4,3)
    alpha = 1.0 - np.clip(glow_tab[ci], 0, GLOW_MAX) / GLOW_MAX          # (F,)
    rgba = np.concatenate([lin, np.repeat(alpha[:, None, None], 4, 1)], 2)
    rgba8 = np.round(np.clip(rgba, 0, 1) * 255).astype(np.uint8)
    N = np.repeat(n[None, :].astype(np.float32), F, 0)
    for t in np.unique(tg):
        m = tg == t
        faces[int(t)].append((V[m], N[m], rgba8[m], ao[m]))


# ------------------------------------------------------------------ glb
MATERIAL_NAME = "campus_voxel"


def write_glb(path, nodes):
    """nodes: list of (name, (pos, nrm, rgba8, idx), translation). One mesh per node, all
    sharing the material `campus_voxel` (mapped to an external material on import)."""
    blobs, views, accessors, meshes, gnodes = [], [], [], [], []
    off = 0

    def add(blob, target):
        nonlocal off
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(blob), "target": target})
        blobs.append(blob + b"\0" * (-len(blob) % 4))
        off += len(blob) + (-len(blob) % 4)
        return len(views) - 1

    for name, (pos, nrm, col, idx), tr in nodes:
        a0 = len(accessors)
        small = len(pos) < 65536
        ib = idx.astype(np.uint16 if small else np.uint32).tobytes()
        v = [add(pos.tobytes(), 34962), add(nrm.tobytes(), 34962), add(col.tobytes(), 34962), add(ib, 34963)]
        accessors += [
            {"bufferView": v[0], "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": v[1], "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": v[2], "componentType": 5121, "normalized": True, "count": len(col), "type": "VEC4"},
            {"bufferView": v[3], "componentType": 5123 if small else 5125, "count": len(idx), "type": "SCALAR"},
        ]
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a0, "NORMAL": a0 + 1,
                                                                    "COLOR_0": a0 + 2},
                                                     "indices": a0 + 3, "material": 0}]})
        gnodes.append({"name": name, "mesh": len(meshes) - 1, "translation": [float(t) for t in tr]})
    binary = b"".join(blobs)
    gltf = {
        "asset": {"version": "2.0", "generator": "campus_voxel.py"},
        "scene": 0, "scenes": [{"nodes": list(range(len(gnodes)))}], "nodes": gnodes, "meshes": meshes,
        "materials": [{"name": MATERIAL_NAME, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                                                       "metallicFactor": 0.0, "roughnessFactor": 0.85}}],
        "buffers": [{"byteLength": len(binary)}], "bufferViews": views, "accessors": accessors,
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(binary), b"BIN\0") + binary)


IMPORT_TEMPLATE = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="{src}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=false
nodes/use_node_type_suffixes=false
meshes/ensure_tangents=false
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{
"materials": {{
"{mat}": {{
"use_external/enabled": true,
"use_external/fallback_path": "{matpath}",
"use_external/path": "{matpath}"
}}
}}
}}
gltf/naming_version=2
gltf/embedded_image_handling=1
"""


def write_import(glb_path, res_path, mat_path):
    """Import settings that map the glb material onto the shared campus material."""
    imp = glb_path.with_name(glb_path.name + ".import")
    if imp.exists():
        old = imp.read_text(encoding="utf-8")
        if f'"use_external/path": "{mat_path}"' in old:
            return  # keep Godot's own file (uid, remap) once it has imported
    imp.write_text(IMPORT_TEMPLATE.format(src=res_path, mat=MATERIAL_NAME, matpath=mat_path),
                   encoding="utf-8", newline="\n")
