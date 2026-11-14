"""Cometling generator: voxel body parts for the hangar NPCs / rocket crew.

Cometlings (PT: Cometinhos) are the original species of MARGIN: chibi creatures with a
huge round head, a tiny gumdrop body, two long "tail-ears" that stream behind them like a
comet's tail and a glowing antenna bulb (the "coma"). Design notes: docs/creatures.md.

Every animated piece is its own .glb so the rig in scenes/npc/creature.tscn can move it
from its own pivot (no skeleton): feet, body, tail, arms, head, eyes, eyelids, happy
eyes, mouths, ears, antenna stalk + bulb, role accessories and hand-held items.
Each mesh is written with its origin AT ITS PIVOT, and this script also writes
scenes/npc/creature.tscn with the node hierarchy placed at the same pivots (single source
of truth for the proportions). Re-running overwrites that scene: tune the look here.

Colour masks: voxels are authored in true colour, and the vertex-colour ALPHA tells the
creature shader (scenes/npc/creature.gdshader) which voxels take a per-creature tint:
  alpha 0   -> fixed colour (eyes, blush, paws, accessories)
  alpha 1/3 -> body tint   (instance uniform body_tint)
  alpha 2/3 -> spot tint   (ear and tail tips)
  alpha 1   -> glow tint   (antenna bulb, scanner screen; also emissive)
Tinted voxels are authored in light greys (shading baked in), so one shared material
and three instance uniforms give every Cometling its own colours.

Uses Canvas / mesh() / write_glb() from tools/voxel_gen.py (imported, not modified).
Axis convention: Y up, feet on y = 0, the creature faces +Z, natural height ~1.05 m.

Usage: python tools/creature_gen.py            (writes assets/voxel/creatures/*.glb,
                                                 emote + icon textures and creature.tscn)
"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import voxel_gen as vg  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "voxel" / "creatures"
SCENE = ROOT / "scenes" / "npc" / "creature.tscn"

VPM = 48          # body voxels per metre (~2 cm): chunky but round
FACE_VPM = 112    # eyes / mouth / lids (~0.9 cm): soft, readable faces
ACC_VPM = 64      # accessories and items

# ------------------------------------------------------------------ colours
# fixed (untinted) colours: palette-derived plus a few species accents (docs/creatures.md)
FIXED = {
    "cream": (255, 241, 222), "cream_dark": (238, 214, 190), "paw": (255, 226, 214),
    "blush": (255, 140, 164), "eye_ink": (26, 22, 52), "eye_iris": (70, 58, 150),
    "eye_iris2": (110, 96, 205), "sparkle": (255, 255, 255), "mouth": (70, 30, 48),
    "mouth_in": (150, 46, 74), "tongue": (255, 128, 150),
    "p_white": (236, 239, 243), "p_white2": (214, 219, 226), "p_orange": (245, 154, 54),
    "p_orange2": (214, 120, 34), "p_blue": (95, 176, 216), "p_blue2": (64, 130, 175),
    "p_glass": (191, 233, 255), "p_metal": (163, 173, 184), "p_gun": (60, 68, 80),
    "p_gun2": (40, 46, 56), "p_hazard": (242, 183, 5), "p_hazard2": (196, 140, 4),
    "p_ink": (13, 17, 23), "leather": (150, 98, 62), "leather2": (112, 70, 44),
    "gold": (236, 190, 70), "wood": (204, 150, 96), "wood2": (160, 110, 66),
    "paper": (246, 246, 240), "p_green": (126, 224, 138),
}
SHADES = [200, 212, 224, 236, 248]
TINT_A = {f"ta{i}": (v, v, v) for i, v in enumerate(SHADES)}       # body tint
TINT_B = {f"tb{i}": (v, v, v) for i, v in enumerate(SHADES)}       # spot tint
TINT_G = {f"tg{i}": (v, v, v) for i, v in enumerate([215, 235, 255])}  # glow tint (emissive)
MASKS = {"_m0": (0, 0, 0), "_m1": (85, 85, 85), "_m2": (170, 170, 170), "_m3": (255, 255, 255)}


def _install_palette():
    for d in (FIXED, TINT_A, TINT_B, TINT_G, MASKS):
        vg.PALETTE.update(d)
    vg.NAMES = list(vg.PALETTE)
    vg.CI = {n: i + 1 for i, n in enumerate(vg.NAMES)}
    vg.RGB = np.array([(0, 0, 0)] + [vg.PALETTE[n] for n in vg.NAMES], np.float32)


_install_palette()


def mask_of(name):
    if name in TINT_A:
        return 1
    if name in TINT_B:
        return 2
    if name in TINT_G:
        return 3
    return 0


# ------------------------------------------------------------------ canvas helpers
def canvas(lo, hi, vpm=VPM):
    return vg.Canvas(lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], vpm)


def superell(c, cx, cy, cz, rx, ry, rz, p=2.4):
    """Normalized 'radius' of a super-ellipsoid (1 = surface)."""
    return (np.abs((c.X - cx) / rx) ** p + np.abs((c.Y - cy) / ry) ** p + np.abs((c.Z - cz) / rz) ** p) ** (1.0 / p)


def shade_y(c, mask, y0, y1, prefix="ta"):
    """Paint `mask` with the 5 shades of a tint, darker at y0, lighter at y1."""
    t = np.clip((c.Y - y0) / max(y1 - y0, 1e-6), 0, 0.999)
    for i in range(len(SHADES)):
        band = (t >= i / len(SHADES)) & (t < (i + 1) / len(SHADES))
        c.paint(np.broadcast_to(mask, c.a.shape) & np.broadcast_to(band, c.a.shape), f"{prefix}{i}")


def blob_chain(c, pts, radii, color, flat=None):
    """Spheres swept along a polyline (smooth tapered limbs). flat=(sx, sy, sz) squashes them."""
    sx, sy, sz = flat or (1, 1, 1)
    m = np.zeros(c.a.shape, bool)
    pts = np.array(pts, float)
    for k in range(len(pts) - 1):
        for t in np.linspace(0, 1, 10):
            p = pts[k] * (1 - t) + pts[k + 1] * t
            r = radii[k] * (1 - t) + radii[k + 1] * t
            d = ((c.X - p[0]) / sx) ** 2 + ((c.Y - p[1]) / sy) ** 2 + ((c.Z - p[2]) / sz) ** 2
            m |= np.broadcast_to(d <= r * r, c.a.shape)
    c.put(m, color)
    return m


def bezier(p0, p1, p2, n=12):
    p0, p1, p2 = (np.array(p, float) for p in (p0, p1, p2))
    return [((1 - t) ** 2) * p0 + 2 * (1 - t) * t * p1 + t * t * p2 for t in np.linspace(0, 1, n)]


def surface(c, occ_mask=None):
    """Voxels of the canvas that touch empty space (for painting skin details)."""
    occ = c.a > 0 if occ_mask is None else occ_mask
    pad = np.pad(occ, 1)
    inner = pad[2:, 1:-1, 1:-1] & pad[:-2, 1:-1, 1:-1] & pad[1:-1, 2:, 1:-1] & pad[1:-1, :-2, 1:-1] \
        & pad[1:-1, 1:-1, 2:] & pad[1:-1, 1:-1, :-2]
    return occ & ~inner


# ------------------------------------------------------------------ meshing with tint masks
def mesh_masked(c, pivot):
    if not (c.a > 0).any():
        raise ValueError("empty canvas")
    m = vg.mesh(c)
    # second pass on a copy coloured by mask id, AO off: same occupancy -> same vertex order
    ids = np.zeros(len(vg.NAMES) + 1, np.uint8)
    for n in vg.NAMES:
        ids[vg.CI[n]] = vg.CI["_m%d" % mask_of(n)]
    saved_a, saved_ao = c.a, vg.AO_LEVEL
    c.a = ids[saved_a]
    vg.AO_LEVEL = np.ones(4, np.float32)
    try:
        mm = vg.mesh(c)
    finally:
        c.a, vg.AO_LEVEL = saved_a, saved_ao
    srgb = (mm[2][:, 0].astype(np.float32) / 255.0) ** (1 / 2.2) * 255.0
    level = np.digitize(srgb, [40, 128, 212]).astype(np.uint8)   # 0..3
    pos, nrm, col, idx = m
    col = col.copy()
    col[:, 3] = level * 85
    pos = pos - np.array(pivot, np.float32)
    return pos, nrm, col, idx


PARTS = {}      # name -> (mesh, pivot)


def emit(name, c, pivot, scale=1.0, pitch_deg=0.0):
    """Meshes a canvas around `pivot`. Items can be scaled up (chunky, readable props) and
    tilted around X after meshing."""
    pos, nrm, col, idx = mesh_masked(c, pivot)
    if scale != 1.0 or pitch_deg:
        a = math.radians(pitch_deg)
        rx = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]], np.float32)
        pos = (pos * scale) @ rx.T
        nrm = nrm @ rx.T
    m = (pos.astype(np.float32), nrm.astype(np.float32), col, idx)
    PARTS[name] = (m, tuple(pivot))
    return m


# ================================================================== rig (metres, model space)
HEAD_C = (0.0, 0.655, 0.0)
HEAD_R = (0.300, 0.265, 0.275)
HEAD_P = 2.4
BODY_C = (0.0, 0.245, -0.005)
BODY_R = (0.172, 0.200, 0.158)

PIV = {
    "hips": (0.0, 0.07, 0.0),
    "neck": (0.0, 0.40, 0.0),
    "foot_l": (0.085, 0.0, 0.0), "foot_r": (-0.085, 0.0, 0.0),
    "arm_l": (0.160, 0.335, 0.0), "arm_r": (-0.160, 0.335, 0.0),
    "hand_l": (0.246, 0.135, 0.018), "hand_r": (-0.246, 0.135, 0.018),
    "tail": (0.0, 0.15, -0.14),
    "ear_l": (0.235, 0.795, -0.03), "ear_r": (-0.235, 0.795, -0.03),
    "antenna": (0.0, 0.905, 0.02),
    "bulb": (0.0, 1.02, 0.075),
    "eye_l": (0.116, 0.632, 0.0), "eye_r": (-0.116, 0.632, 0.0),   # z filled in below
    "mouth": (0.0, 0.548, 0.0),
    "carry": (0.0, 0.27, 0.25),
    "scan": (0.0, 0.25, 0.2),
    "scarf_tail": (-0.07, 0.405, -0.15),
}
EYE_R = (0.066, 0.084)


def head_f(c):
    return superell(c, *HEAD_C, *HEAD_R, p=HEAD_P)


def head_surface_z(x, y):
    u = abs(x / HEAD_R[0]) ** HEAD_P + abs((y - HEAD_C[1]) / HEAD_R[1]) ** HEAD_P
    return HEAD_C[2] + HEAD_R[2] * max(1 - u, 0) ** (1 / HEAD_P)


for _k in ("eye_l", "eye_r", "mouth"):
    _x, _y, _ = PIV[_k]
    PIV[_k] = (_x, _y, round(head_surface_z(_x, _y), 4))
LID_TOP = {k: (PIV[k][0], PIV[k][1] + EYE_R[1] + 0.012, PIV[k][2] - 0.004) for k in ("eye_l", "eye_r")}


# ------------------------------------------------------------------ body parts
def build_body():
    c = canvas((-0.2, 0.03, -0.19), (0.2, 0.47, 0.19))
    f = superell(c, *BODY_C, *BODY_R, p=2.2)
    body = f <= 1.0
    c.put(body, "ta0")
    shade_y(c, body, 0.06, 0.44)
    # cream belly patch on the front
    belly = (((c.X / 0.112) ** 2 + ((c.Y - 0.215) / 0.13) ** 2) <= 1.0) & (c.Z > 0.03)
    c.paint(belly & surface(c), "cream")
    c.paint(belly & surface(c) & (c.Y < 0.13), "cream_dark")
    return emit("body", c, PIV["hips"])


def build_head():
    c = canvas((-0.31, 0.38, -0.29), (0.31, 0.93, 0.29))
    f = head_f(c)
    head = f <= 1.0
    c.put(head, "ta0")
    shade_y(c, head, HEAD_C[1] - HEAD_R[1], HEAD_C[1] + HEAD_R[1] * 0.85)
    skin = surface(c)
    # rosy cheeks
    for s in (1, -1):
        ch = (((c.X - s * 0.19) / 0.052) ** 2 + ((c.Y - 0.568) / 0.030) ** 2 <= 1.0) & (c.Z > 0.1)
        c.paint(ch & skin, "blush")
    # a soft lighter muzzle around the mouth
    muz = (((c.X / 0.085) ** 2 + ((c.Y - 0.552) / 0.045) ** 2) <= 1.0) & (c.Z > 0.15)
    c.paint(muz & skin, "ta4")
    # three freckle-stars on the forehead (species marking)
    for x, y in ((-0.035, 0.80), (0.0, 0.815), (0.035, 0.80)):
        st = ((np.abs(c.X - x) < 0.011) & (np.abs(c.Y - y) < 0.004)) | ((np.abs(c.X - x) < 0.004) & (np.abs(c.Y - y) < 0.011))
        c.paint(st & skin & (c.Z > 0.1), "tb4")
    return emit("head", c, PIV["neck"])


def face_canvas(cx, cy, w, h):
    zc = head_surface_z(cx, cy)
    return canvas((cx - w, cy - h, zc - 0.09), (cx + w, cy + h, zc + 0.05), FACE_VPM)


def build_eye(side):
    key = "eye_l" if side > 0 else "eye_r"
    ex, ey, _ = PIV[key]
    rx, ry = EYE_R
    c = face_canvas(ex, ey, rx + 0.01, ry + 0.01)
    f = head_f(c)
    oval = (((c.X - ex) / rx) ** 2 + ((c.Y - ey) / ry) ** 2) <= 1.0
    shell = oval & (f >= 0.955) & (f <= 1.05)
    c.put(shell, "eye_ink")
    # iris glow at the bottom of the eye
    low = shell & ((((c.X - ex) / (rx * 0.78)) ** 2 + ((c.Y - ey + ry * 0.42) / (ry * 0.5)) ** 2) <= 1.0)
    c.paint(low, "eye_iris")
    low2 = shell & ((((c.X - ex) / (rx * 0.5)) ** 2 + ((c.Y - ey + ry * 0.62) / (ry * 0.25)) ** 2) <= 1.0)
    c.paint(low2, "eye_iris2")
    # sparkles: big one up-left (same side for both eyes = one light), small one down-right
    big = ((c.X - (ex - rx * 0.32)) ** 2 + (c.Y - (ey + ry * 0.36)) ** 2) <= 0.024 ** 2
    small = ((c.X - (ex + rx * 0.38)) ** 2 + (c.Y - (ey - ry * 0.12)) ** 2) <= 0.010 ** 2
    c.paint(shell & (big | small), "sparkle")
    return emit(key.replace("eye", "eye"), c, PIV[key])


def build_lid(side):
    key = "eye_l" if side > 0 else "eye_r"
    ex, ey, _ = PIV[key]
    rx, ry = EYE_R
    c = face_canvas(ex, ey, rx + 0.02, ry + 0.02)
    f = head_f(c)
    oval = (((c.X - ex) / (rx + 0.012)) ** 2 + ((c.Y - ey) / (ry + 0.012)) ** 2) <= 1.0
    shell = oval & (f >= 1.035) & (f <= 1.075)
    c.put(shell, "ta2")
    lash = (((c.X - ex) / (rx + 0.012)) ** 2 + ((c.Y - ey) / (ry + 0.012)) ** 2) > 0.8
    c.paint(shell & lash & (c.Y < ey - ry * 0.25), "eye_ink")   # lash line along the lower rim
    return emit("lid_" + key[-1], c, LID_TOP[key])


def build_eye_happy(side):
    key = "eye_l" if side > 0 else "eye_r"
    ex, ey, _ = PIV[key]
    c = face_canvas(ex, ey, 0.08, 0.07)
    f = head_f(c)
    d = np.sqrt((c.X - ex) ** 2 + (c.Y - (ey - 0.035)) ** 2)
    arc = (d >= 0.044) & (d <= 0.064) & (c.Y > ey - 0.035 + 0.006)
    c.put(arc & (f >= 0.96) & (f <= 1.05), "eye_ink")
    return emit("eye_happy_" + key[-1], c, PIV[key])


def build_mouths():
    mx, my, _ = PIV["mouth"]
    # "w" cat smile
    c = face_canvas(mx, my, 0.06, 0.04)
    f = head_f(c)
    sh = (f >= 0.96) & (f <= 1.05)
    for s in (1, -1):
        d = np.sqrt((c.X - s * 0.021) ** 2 + (c.Y - (my + 0.012)) ** 2)
        c.put(sh & (d >= 0.014) & (d <= 0.024) & (c.Y < my + 0.008), "mouth")
    emit("mouth_smile", c, PIV["mouth"])
    # open "D" grin: flat top, round bottom, tongue
    c = face_canvas(mx, my, 0.07, 0.06)
    f = head_f(c)
    sh = (f >= 0.94) & (f <= 1.05)
    o = (((c.X - mx) / 0.048) ** 2 + ((c.Y - (my + 0.012)) / 0.05) ** 2 <= 1.0) & (c.Y <= my + 0.014)
    c.put(sh & o, "mouth_in")
    rim = sh & o & ~((((c.X - mx) / 0.040) ** 2 + ((c.Y - (my + 0.012)) / 0.042) ** 2 <= 1.0))
    c.paint(rim, "mouth")
    tg = (((c.X - mx) / 0.026) ** 2 + ((c.Y - (my - 0.026)) / 0.014) ** 2) <= 1.0
    c.paint(sh & o & tg, "tongue")
    emit("mouth_open", c, PIV["mouth"])
    # small round "o" (surprise / wonder)
    c = face_canvas(mx, my, 0.04, 0.04)
    f = head_f(c)
    sh = (f >= 0.94) & (f <= 1.05)
    o = ((c.X - mx) / 0.022) ** 2 + ((c.Y - (my - 0.004)) / 0.026) ** 2 <= 1.0
    c.put(sh & o, "mouth_in")
    c.paint(sh & o & ~(((c.X - mx) / 0.014) ** 2 + ((c.Y - (my - 0.004)) / 0.018) ** 2 <= 1.0), "mouth")
    emit("mouth_o", c, PIV["mouth"])


def build_ear(side):
    key = "ear_l" if side > 0 else "ear_r"
    px, py, pz = PIV[key]
    s = side
    pts = bezier((px - s * 0.04, py - 0.01, pz + 0.01), (px + s * 0.15, py + 0.10, pz - 0.12),
                 (px + s * 0.16, py - 0.17, pz - 0.42), 11)
    radii = [0.055, 0.068, 0.080, 0.086, 0.086, 0.082, 0.074, 0.064, 0.050, 0.034, 0.018]
    lo = np.min(pts, 0) - 0.08
    hi = np.max(pts, 0) + 0.08
    c = canvas(lo, hi)
    m = np.zeros(c.a.shape, bool)
    for k in range(len(pts) - 1):
        for t in np.linspace(0, 1, 8):
            p = pts[k] * (1 - t) + pts[k + 1] * t
            r = radii[k] * (1 - t) + radii[k + 1] * t
            d = ((c.X - p[0]) / 0.8) ** 2 + ((c.Y - p[1]) / 0.6) ** 2 + ((c.Z - p[2]) / 1.0) ** 2
            m |= np.broadcast_to(d <= r * r, c.a.shape)
    c.put(m, "ta2")
    shade_y(c, m, py - 0.12, py + 0.04)
    # comet-tail tip in the spot colour, with a lighter streak
    tip_t = np.zeros(c.a.shape)
    along = (c.Z - pz) / (pts[-1][2] - pz)          # 0 at the root, 1 at the tip
    c.paint(m & np.broadcast_to(along > 0.52, c.a.shape), "tb2")
    c.paint(m & np.broadcast_to(along > 0.7, c.a.shape), "tb4")
    c.paint(m & np.broadcast_to((along > 0.6) & (c.Y > py - 0.05), c.a.shape), "tb3")
    del tip_t
    return emit(key, c, PIV[key])


def build_tail():
    px, py, pz = PIV["tail"]
    pts = bezier((px, py + 0.01, pz + 0.03), (px, py + 0.02, pz - 0.10), (px, py + 0.13, pz - 0.15), 8)
    radii = [0.048, 0.050, 0.046, 0.040, 0.034, 0.030, 0.034, 0.040]
    c = canvas((px - 0.08, py - 0.07, pz - 0.24), (px + 0.08, py + 0.22, pz + 0.08))
    m = blob_chain(c, pts, radii, "ta1")
    along = np.clip((pz - c.Z) / 0.15 + (c.Y - py) / 0.4, 0, 2)
    c.paint(m & np.broadcast_to(along > 0.85, c.a.shape), "tb2")
    c.paint(m & np.broadcast_to(along > 1.05, c.a.shape), "tb4")
    return emit("tail", c, PIV["tail"])


def build_arm(side):
    key = "arm_l" if side > 0 else "arm_r"
    hk = "hand_l" if side > 0 else "hand_r"
    px, py, pz = PIV[key]
    hx, hy, hz = PIV[hk]
    c = canvas((min(px, hx) - 0.09, hy - 0.08, -0.09), (max(px, hx) + 0.09, py + 0.06, 0.1))
    blob_chain(c, [(px - side * 0.01, py, pz), ((px + hx) / 2, (py + hy) / 2 + 0.01, 0.006), (hx, hy + 0.03, hz)],
               [0.046, 0.040, 0.040], "ta1")
    shade_y(c, c.a > 0, hy, py + 0.03)
    hand = ((c.X - hx) / 1.0) ** 2 + ((c.Y - hy) / 0.9) ** 2 + ((c.Z - hz) / 1.0) ** 2 <= 0.062 ** 2
    c.put(hand, "paw")
    thumb = ((c.X - (hx - side * 0.03)) ** 2 + (c.Y - (hy + 0.014)) ** 2 + (c.Z - (hz + 0.046)) ** 2) <= 0.024 ** 2
    c.put(thumb, "paw")
    return emit(key, c, PIV[key])


def build_foot():
    px = PIV["foot_l"][0]
    c = canvas((px - 0.08, 0.0, -0.08), (px + 0.08, 0.10, 0.14))
    f = superell(c, px, 0.035, 0.03, 0.066, 0.05, 0.092, p=2.2)
    m = (f <= 1.0) & (c.Y >= 0.0)
    c.put(m, "ta1")
    shade_y(c, m, 0.0, 0.08)
    c.paint(m & (c.Y < 0.016), "paw")
    for dx in (-0.025, 0.0, 0.025):  # toe beans
        bean = ((c.X - px - dx) ** 2 + (c.Z - 0.112) ** 2) <= 0.012 ** 2
        c.paint(m & bean & (c.Y < 0.04), "paw")
    return emit("foot", c, PIV["foot_l"])


def build_antenna():
    px, py, pz = PIV["antenna"]
    bx, by, bz = PIV["bulb"]
    pts = bezier((px, py - 0.03, pz), (px, py + 0.09, pz - 0.02), (bx, by - 0.03, bz), 10)
    c = canvas((px - 0.05, py - 0.05, pz - 0.06), (px + 0.05, by + 0.01, bz + 0.05), ACC_VPM)
    blob_chain(c, pts, [0.022, 0.016] + [0.0135] * 8, "ta2")
    emit("antenna", c, PIV["antenna"])
    c = canvas((bx - 0.075, by - 0.075, bz - 0.075), (bx + 0.075, by + 0.075, bz + 0.075), ACC_VPM)
    core = c.sphere(bx, by, bz, 0.047, "tg1")
    # four-point star flares (comet head)
    for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0)):
        blob_chain(c, [(bx, by, bz), (bx + d[0] * 0.068, by + d[1] * 0.068, bz)], [0.026, 0.008], "tg0")
    c.paint(core & ((c.Z - bz) > 0.02), "tg2")
    c.paint(((c.X - (bx - 0.016)) ** 2 + (c.Y - (by + 0.018)) ** 2 + (c.Z - (bz + 0.04)) ** 2) <= 0.013 ** 2, "sparkle")
    return emit("bulb", c, PIV["bulb"])


# ------------------------------------------------------------------ accessories
def head_shell(c, grow, thick):
    f = superell(c, HEAD_C[0], HEAD_C[1], HEAD_C[2], HEAD_R[0] + grow, HEAD_R[1] + grow, HEAD_R[2] + grow, p=HEAD_P)
    inner = superell(c, HEAD_C[0], HEAD_C[1], HEAD_C[2], HEAD_R[0] + grow - thick, HEAD_R[1] + grow - thick,
                     HEAD_R[2] + grow - thick, p=HEAD_P)
    return (f <= 1.0) & (inner > 1.0), f


def cut_holes(c, m):
    """Holes for the antenna and the ears."""
    ax, ay, az = PIV["antenna"]
    hole = (((c.X - ax) ** 2 + (c.Z - az) ** 2) <= 0.03 ** 2) & (c.Y > ay - 0.1)
    for k in ("ear_l", "ear_r"):
        ex, ey, ez = PIV[k]
        hole |= ((c.X - ex) ** 2 + (c.Y - ey) ** 2 + (c.Z - ez) ** 2) <= 0.07 ** 2
    return m & ~hole


def build_helmet():
    c = canvas((-0.36, 0.55, -0.34), (0.36, 0.97, 0.36), VPM)
    shell, f = head_shell(c, 0.028, 0.034)
    cap = shell & (c.Y > HEAD_C[1] + 0.035) & ~((c.Z > 0.05) & (c.Y < HEAD_C[1] + 0.135))
    cap = cut_holes(c, cap)
    c.put(cap, "p_white")
    c.paint(cap & (c.Y < HEAD_C[1] + 0.07), "p_white2")
    c.paint(cap & (np.abs(c.X) < 0.032), "p_orange")
    # flipped-up visor across the forehead
    vis, _ = head_shell(c, 0.05, 0.022)
    vis = vis & (c.Z > 0.02) & (c.Y > HEAD_C[1] + 0.12) & (c.Y < HEAD_C[1] + 0.2) & (np.abs(c.X) < 0.25)
    c.put(vis, "p_blue")
    c.paint(vis & (c.Y > HEAD_C[1] + 0.175), "p_glass")
    return emit("acc_helmet", c, PIV["neck"])


def build_hardhat():
    c = canvas((-0.4, 0.6, -0.4), (0.4, 0.99, 0.46), VPM)
    shell, f = head_shell(c, 0.03, 0.04)
    dome = shell & (c.Y > HEAD_C[1] + 0.085)
    dome = cut_holes(c, dome)
    c.put(dome, "p_hazard")
    c.paint(dome & (np.abs(c.X) < 0.03) & (c.Y > HEAD_C[1] + 0.16), "p_hazard2")   # ridge
    # brim: a ring sticking out, bigger at the front
    rr = np.sqrt((c.X / (HEAD_R[0] + 0.07)) ** 2 + ((c.Z - 0.02) / (HEAD_R[2] + 0.09 + 0.05 * (c.Z > 0))) ** 2)
    brim = (rr <= 1.0) & (np.abs(c.Y - (HEAD_C[1] + 0.09)) < 0.012) & (f > 0.96)
    brim = cut_holes(c, brim)
    c.put(brim, "p_hazard2")
    # little lamp on the front
    lamp = ((c.X ** 2 + (c.Y - (HEAD_C[1] + 0.17)) ** 2) <= 0.028 ** 2) & (c.Z > 0.2) & (f > 0.98) & (f < 1.2)
    c.put(lamp & (c.Z < 0.32), "p_gun")
    c.paint(lamp & (c.Z > 0.27), "tg2")
    return emit("acc_hardhat", c, PIV["neck"])


def build_goggles():
    c = canvas((-0.34, 0.68, -0.32), (0.34, 0.9, 0.36), ACC_VPM)
    band, f = head_shell(c, 0.014, 0.024)
    yb = HEAD_C[1] + 0.13
    band = band & (np.abs(c.Y - yb) < 0.02)
    band = cut_holes(c, band)
    c.put(band, "p_gun")
    for s in (1, -1):
        lx = s * 0.095
        lz = head_surface_z(lx, yb + 0.02) + 0.03
        cyl = ((c.X - lx) ** 2 + (c.Y - (yb + 0.02)) ** 2 <= 0.058 ** 2) & (c.Z > lz - 0.06) & (c.Z < lz)
        c.put(cyl, "p_metal")
        lens = ((c.X - lx) ** 2 + (c.Y - (yb + 0.02)) ** 2 <= 0.044 ** 2) & (c.Z > lz - 0.025) & (c.Z < lz)
        c.put(lens, "p_glass")
        glint = ((c.X - (lx - 0.016)) ** 2 + (c.Y - (yb + 0.038)) ** 2 <= 0.011 ** 2) & (c.Z > lz - 0.025) & (c.Z < lz)
        c.paint(glint, "sparkle")
    return emit("acc_goggles", c, PIV["neck"])


def build_scarf():
    c = canvas((-0.22, 0.33, -0.22), (0.22, 0.47, 0.22), ACC_VPM)
    r = np.sqrt((c.X / 0.175) ** 2 + ((c.Z + 0.005) / 0.165) ** 2)
    ring = (r <= 1.0) & (r >= 0.62) & (np.abs(c.Y - 0.405) < 0.034 - 0.01 * np.abs(np.sin(np.arctan2(c.Z, c.X) * 3)))
    c.put(ring, "p_orange")
    c.paint(ring & (np.abs(c.Y - 0.405) < 0.008), "p_orange2")
    c.paint(ring & (c.Y < 0.38), "p_orange2")
    emit("acc_scarf", c, PIV["hips"])
    tx, ty, tz = PIV["scarf_tail"]
    c = canvas((tx - 0.06, ty - 0.2, tz - 0.12), (tx + 0.06, ty + 0.04, tz + 0.04), ACC_VPM)
    strip = blob_chain(c, [(tx, ty, tz), (tx - 0.01, ty - 0.06, tz - 0.05), (tx - 0.015, ty - 0.13, tz - 0.07)],
                       [0.03, 0.032, 0.03], "p_orange", flat=(1.3, 1.0, 0.45))
    c.paint(strip & (c.Y < ty - 0.12), "p_white")
    c.paint(strip & (c.Y < ty - 0.135) & (np.abs(c.X - tx + 0.015) < 0.007), "p_orange2")
    return emit("acc_scarf_tail", c, PIV["scarf_tail"])


def body_shell(c, grow, thick):
    f = superell(c, *BODY_C, BODY_R[0] + grow, BODY_R[1] + grow, BODY_R[2] + grow, p=2.2)
    inner = superell(c, *BODY_C, BODY_R[0] + grow - thick, BODY_R[1] + grow - thick, BODY_R[2] + grow - thick, p=2.2)
    return (f <= 1.0) & (inner > 1.0)


def build_belt():
    c = canvas((-0.24, 0.08, -0.22), (0.24, 0.26, 0.24), ACC_VPM)
    band = body_shell(c, 0.018, 0.03) & (np.abs(c.Y - 0.165) < 0.022)
    c.put(band, "leather")
    c.paint(band & (np.abs(c.Y - 0.165) > 0.015), "leather2")
    buckle = band & (np.abs(c.X) < 0.032) & (c.Z > 0.1)
    c.paint(buckle, "gold")
    for s in (1, -1):   # pouches
        c.box(s * 0.12 - 0.045, s * 0.12 + 0.045, 0.11, 0.19, 0.08, 0.16, "leather")
        c.paint((np.abs(c.X - s * 0.12) < 0.046) & (np.abs(c.Y - 0.18) < 0.012) & (c.Z > 0.08) & (c.Z < 0.165), "leather2")
    # a tiny wrench hanging on the side
    c.box(-0.19, -0.172, 0.06, 0.17, -0.03, -0.012, "p_metal")
    c.box(-0.2, -0.162, 0.04, 0.07, -0.035, -0.008, "p_metal")
    return emit("acc_belt", c, PIV["hips"])


def build_vest():
    c = canvas((-0.23, 0.06, -0.22), (0.23, 0.46, 0.23), VPM)
    v = body_shell(c, 0.014, 0.026) & (c.Y > 0.1) & (c.Y < 0.42)
    v = v & ~((np.abs(c.X) < 0.085) & (c.Z > 0.05) & (c.Y > 0.27))     # V-neck opening
    v = v & ~((np.abs(c.Y - 0.33) < 0.05) & (np.abs(c.X) > 0.14))      # arm holes
    c.put(v, "p_orange")
    c.paint(v & (np.abs(c.Y - 0.2) < 0.016), "p_glass")
    c.paint(v & (np.abs(c.Y - 0.155) < 0.008), "p_white")
    return emit("acc_vest", c, PIV["hips"])


def build_backpack():
    c = canvas((-0.14, 0.12, -0.34), (0.14, 0.52, -0.08), ACC_VPM)
    c.box(-0.1, 0.1, 0.17, 0.38, -0.27, -0.14, "p_white")
    c.box(-0.1, 0.1, 0.22, 0.25, -0.275, -0.14, "p_blue")
    c.box(-0.06, 0.06, 0.28, 0.34, -0.285, -0.27, "p_blue2")
    c.sphere(0.0, 0.31, -0.29, 0.012, "tg2")
    # tiny dish antenna on top
    c.cyl("y", 0.06, -0.2, 0.38, 0.45, 0.008, "p_metal")
    d = superell(c, 0.06, 0.46, -0.2, 0.05, 0.014, 0.05, p=2.0)
    c.put((d <= 1.0) & (c.Y > 0.452), "p_white2")
    return emit("acc_backpack", c, PIV["hips"])


# ------------------------------------------------------------------ hand-held items (origin = grip)
def build_items():
    hx, hy, hz = 0.0, 0.0, 0.0
    # wrench: handle along +Z from the fist
    c = canvas((-0.05, -0.04, -0.05), (0.05, 0.04, 0.26), ACC_VPM)
    c.box(-0.014, 0.014, -0.01, 0.01, -0.03, 0.18, "p_metal")
    jaw = c.cyl("y", 0, 0.205, -0.012, 0.012, 0.042, "p_metal")
    c.put(jaw & (np.abs(c.X) < 0.014) & (c.Z > 0.21), 0 if False else "p_metal")
    c.a[np.broadcast_to((np.abs(c.X) < 0.016) & (c.Z > 0.215), c.a.shape)] = 0
    c.box(-0.016, 0.016, -0.012, 0.012, -0.035, 0.03, "p_orange")
    emit("item_wrench", c, (hx, hy, hz), scale=1.45)
    # hammer: handle +Z, head across Y
    c = canvas((-0.05, -0.08, -0.05), (0.05, 0.08, 0.3), ACC_VPM)
    c.box(-0.013, 0.013, -0.013, 0.013, -0.03, 0.22, "wood")
    c.box(-0.014, 0.014, -0.014, 0.014, -0.035, 0.03, "p_orange")
    c.box(-0.032, 0.032, -0.07, 0.07, 0.2, 0.26, "p_gun")
    c.box(-0.034, 0.034, 0.04, 0.072, 0.198, 0.262, "p_metal")
    emit("item_hammer", c, (hx, hy, hz), scale=1.55)
    # scanner tablet: held in front, screen faces up/back toward the face
    c = canvas((-0.1, -0.03, -0.03), (0.1, 0.03, 0.16), ACC_VPM)
    c.box(-0.085, 0.085, -0.012, 0.012, 0.0, 0.13, "p_white")
    c.box(-0.07, 0.07, 0.008, 0.016, 0.015, 0.115, "tg1")
    c.box(-0.05, 0.02, 0.012, 0.018, 0.03, 0.05, "tg2")
    c.box(-0.02, 0.05, 0.012, 0.018, 0.07, 0.08, "tg2")
    c.box(-0.085, 0.085, -0.014, -0.006, 0.0, 0.01, "p_blue")
    emit("item_scanner", c, (hx, hy, hz), scale=1.5, pitch_deg=-55.0)
    # clipboard
    c = canvas((-0.09, -0.03, -0.03), (0.09, 0.03, 0.22), ACC_VPM)
    c.box(-0.075, 0.075, -0.008, 0.008, 0.0, 0.2, "wood2")
    c.box(-0.062, 0.062, 0.006, 0.012, 0.012, 0.18, "paper")
    c.box(-0.03, 0.03, 0.006, 0.018, 0.17, 0.205, "p_metal")
    for k in range(4):
        z = 0.04 + k * 0.032
        c.box(-0.045, 0.03 - 0.02 * (k % 2), 0.011, 0.014, z, z + 0.008, "p_gun")
    emit("item_clipboard", c, (hx, hy, hz), scale=1.35)
    # parts crate (carried with both hands): mini version of the hangar containers
    c = canvas((-0.17, -0.15, -0.15), (0.17, 0.15, 0.15), ACC_VPM)
    c.box(-0.15, 0.15, -0.12, 0.12, -0.12, 0.12, "p_blue")
    edges = (np.abs(np.abs(c.X) - 0.14) < 0.012) | (np.abs(np.abs(c.Y) - 0.11) < 0.012)
    c.paint(edges, "p_white")
    c.paint((np.abs(c.X) < 0.05) & (np.abs(c.Y) < 0.04), "p_hazard")
    c.paint((np.abs(c.X) < 0.03) & (np.abs(c.Y) < 0.02) & (c.Z > 0.11), "p_ink")
    emit("item_crate", c, (0, 0, 0))


# ================================================================== emote + UI textures
def build_textures():
    from PIL import Image, ImageDraw
    cell, cols, rows = 48, 4, 4
    emotes = ["heart", "star", "exclaim", "question", "note", "wrench", "rocket", "zzz",
              "idea", "sweat", "happy", "sparkle", "chat", "fire", "check", "planet"]
    img = Image.new("RGBA", (cell * cols, cell * rows), (0, 0, 0, 0))
    ink, white = (13, 17, 23, 255), (255, 255, 255, 255)
    col = {"heart": (255, 107, 107), "star": (255, 204, 85), "exclaim": (245, 154, 54), "question": (95, 176, 216),
           "note": (184, 164, 255), "wrench": (163, 173, 184), "rocket": (245, 154, 54), "zzz": (95, 176, 216),
           "idea": (255, 204, 85), "sweat": (95, 176, 216), "happy": (126, 224, 138), "sparkle": (255, 204, 85),
           "chat": (140, 155, 181), "fire": (245, 120, 40), "check": (126, 224, 138), "planet": (95, 176, 216)}
    for i, name in enumerate(emotes):
        ox, oy = (i % cols) * cell, (i // cols) * cell
        layer = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        # bubble with outline and a little tail (pixel art, 1 px = 1 texel)
        d.rounded_rectangle((3, 2, 44, 36), radius=11, fill=white, outline=ink, width=2)
        d.polygon([(17, 35), (29, 35), (21, 44)], fill=ink)
        d.polygon([(19, 34), (27, 34), (21, 41)], fill=white)
        c = col[name] + (255,)
        cx, cy = 24, 19
        if name == "heart":
            d.ellipse((13, 10, 24, 21), fill=c)
            d.ellipse((23, 10, 34, 21), fill=c)
            d.polygon([(13, 17), (34, 17), (24, 29)], fill=c)
            d.rectangle((16, 13, 18, 15), fill=white)
        elif name == "star":
            pts = []
            for k in range(10):
                r = 12 if k % 2 == 0 else 5
                a = -math.pi / 2 + k * math.pi / 5
                pts.append((cx + r * math.cos(a), cy + 1 + r * math.sin(a)))
            d.polygon(pts, fill=c)
        elif name == "exclaim":
            d.rounded_rectangle((21, 7, 27, 23), radius=3, fill=c)
            d.ellipse((21, 25, 27, 31), fill=c)
        elif name == "question":
            d.arc((15, 7, 33, 23), 180, 70, fill=c, width=5)
            d.rectangle((22, 20, 27, 25), fill=c)
            d.ellipse((22, 27, 27, 32), fill=c)
        elif name == "note":
            d.ellipse((12, 22, 21, 30), fill=c)
            d.ellipse((25, 19, 34, 27), fill=c)
            d.rectangle((18, 9, 21, 26), fill=c)
            d.rectangle((31, 7, 34, 23), fill=c)
            d.polygon([(18, 9), (34, 6), (34, 11), (18, 14)], fill=c)
        elif name == "wrench":
            d.line((15, 28, 30, 13), fill=c, width=5)
            d.ellipse((26, 6, 38, 18), fill=c)
            d.rectangle((30, 6, 34, 12), fill=white)
        elif name == "rocket":
            d.polygon([(24, 5), (30, 14), (30, 26), (18, 26), (18, 14)], fill=(236, 239, 243, 255), outline=ink)
            d.polygon([(18, 20), (13, 29), (18, 27)], fill=c)
            d.polygon([(30, 20), (35, 29), (30, 27)], fill=c)
            d.ellipse((21, 13, 27, 19), fill=(95, 176, 216, 255))
            d.polygon([(20, 27), (28, 27), (24, 33)], fill=(255, 204, 85, 255))
        elif name == "zzz":
            for k, (x, y, s) in enumerate(((12, 18, 10), (24, 11, 8), (33, 6, 6))):
                d.line((x, y, x + s, y), fill=c, width=2)
                d.line((x + s, y, x, y + s), fill=c, width=2)
                d.line((x, y + s, x + s, y + s), fill=c, width=2)
        elif name == "idea":
            d.ellipse((16, 6, 32, 22), fill=c)
            d.rectangle((20, 21, 28, 27), fill=(163, 173, 184, 255))
            d.rectangle((21, 28, 27, 30), fill=(60, 68, 80, 255))
            d.rectangle((20, 9, 22, 12), fill=white)
        elif name == "sweat":
            d.polygon([(24, 6), (17, 20), (31, 20)], fill=c)
            d.ellipse((17, 14, 31, 30), fill=c)
            d.ellipse((20, 18, 23, 21), fill=white)
        elif name == "happy":
            d.ellipse((12, 7, 36, 31), fill=c)
            d.arc((16, 13, 22, 19), 200, 340, fill=ink, width=2)
            d.arc((26, 13, 32, 19), 200, 340, fill=ink, width=2)
            d.chord((17, 16, 31, 28), 0, 180, fill=ink)
        elif name == "sparkle":
            for (x, y, r) in ((20, 18, 10), (32, 10, 5), (33, 27, 4)):
                d.polygon([(x, y - r), (x + r * 0.3, y - r * 0.3), (x + r, y), (x + r * 0.3, y + r * 0.3),
                           (x, y + r), (x - r * 0.3, y + r * 0.3), (x - r, y), (x - r * 0.3, y - r * 0.3)], fill=c)
        elif name == "chat":
            for x in (14, 22, 30):
                d.ellipse((x, 16, x + 5, 21), fill=c)
        elif name == "fire":
            d.polygon([(24, 5), (34, 20), (31, 30), (17, 30), (14, 20), (20, 14)], fill=c)
            d.polygon([(24, 16), (29, 24), (27, 30), (21, 30), (19, 24)], fill=(255, 204, 85, 255))
        elif name == "check":
            d.line((14, 19, 21, 27), fill=c, width=5)
            d.line((21, 27, 34, 10), fill=c, width=5)
        elif name == "planet":
            d.ellipse((15, 9, 33, 27), fill=c)
            d.ellipse((9, 15, 39, 22), outline=(245, 154, 54, 255), width=2)
            d.ellipse((15, 9, 33, 18), fill=c)
        img.alpha_composite(layer, (ox, oy))
    (OUT / "ui").mkdir(parents=True, exist_ok=True)
    img.save(OUT / "ui" / "emotes.png")
    (OUT / "ui" / "emotes.txt").write_text("\n".join(f"{i} {n}" for i, n in enumerate(emotes)) + "\n", encoding="utf-8")
    return emotes


def build_icons():
    """Role badges for the crew panel (SVG, crisp at any size)."""
    icons = {
        # pilot: wings around a star
        "role_pilot": '<path d="M32 22l3.5 7.2 8 1.1-5.8 5.6 1.4 7.9L32 40l-7.1 3.8 1.4-7.9-5.8-5.6 8-1.1z" fill="#0d1117"/>'
                      '<path d="M4 26c8 0 13 2 16 6-6 1-10 4-12 8-1-6-3-10-4-14zm56 0c-8 0-13 2-16 6 6 1 10 4 12 8 1-6 3-10 4-14z" fill="#0d1117"/>',
        # engineer: wrench
        "role_engineer": '<path d="M44 8a12 12 0 0 0-11.3 16L12 44.7a4.6 4.6 0 0 0 6.5 6.5L39.2 30.5A12 12 0 0 0 55 19l-7 7-6.5-1.5L40 18l7-7a12 12 0 0 0-3-3z" fill="#0d1117"/>',
        # scientist: flask with bubbles
        "role_scientist": '<path d="M25 8h14v4h-2v12l12 22a5 5 0 0 1-4.4 7.4H19.4A5 5 0 0 1 15 46l12-22V12h-2z" fill="#0d1117"/>'
                          '<circle cx="28" cy="42" r="3" fill="#eef2f6"/><circle cx="36" cy="46" r="2" fill="#eef2f6"/>',
        # ground crew: traffic cone
        "role_ground": '<path d="M27 10h10l11 38H16z" fill="#0d1117"/><rect x="10" y="48" width="44" height="6" rx="2" fill="#0d1117"/>'
                       '<path d="M22 30h20l1.6 6H20.4z" fill="#eef2f6"/>',
        # hire: plus sign in a speech bubble
        "icon_hire": '<path d="M32 10a22 20 0 1 0 9 38l11 6-3-11a22 20 0 0 0-17-33z" fill="#eef2f6"/>'
                     '<path d="M29 18h6v10h10v6H35v10h-6V34H19v-6h10z" fill="#0d1117"/>',
        "icon_rename": '<path d="M42 8l14 14-28 28H14V36z" fill="#eef2f6"/><path d="M38 12l14 14" stroke="#0d1117" stroke-width="3"/>',
        "icon_seat": '<path d="M18 8h28v26H18z" fill="#eef2f6"/><path d="M12 36h40v8H12zM16 44h6v12h-6zM42 44h6v12h-6z" fill="#eef2f6"/>',
        "icon_unseat": '<path d="M16 16l32 32M48 16L16 48" stroke="#eef2f6" stroke-width="7" stroke-linecap="round"/>',
    }
    for name, body in icons.items():
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}</svg>\n'
        (OUT / "ui" / f"{name}.svg").write_text(svg, encoding="utf-8")


# ================================================================== the rig scene
# (node, parent, pivot key or absolute pivot, glb or None, visible)
RIG = [
    ("Rig", ".", (0, 0, 0), None, True),
    ("FootL", "Rig", "foot_l", "foot", True),
    ("FootR", "Rig", "foot_r", "foot", True),
    ("Hips", "Rig", "hips", "body", True),
    ("Belt", "Rig/Hips", "hips", "acc_belt", False),
    ("Vest", "Rig/Hips", "hips", "acc_vest", False),
    ("Backpack", "Rig/Hips", "hips", "acc_backpack", False),
    ("Scarf", "Rig/Hips", "hips", "acc_scarf", False),
    ("ScarfTail", "Rig/Hips/Scarf", "scarf_tail", "acc_scarf_tail", True),
    ("Tail", "Rig/Hips", "tail", "tail", True),
    ("ArmL", "Rig/Hips", "arm_l", "arm_l", True),
    ("HandL", "Rig/Hips/ArmL", "hand_l", None, True),
    ("ArmR", "Rig/Hips", "arm_r", "arm_r", True),
    ("HandR", "Rig/Hips/ArmR", "hand_r", None, True),
    ("Wrench", "Rig/Hips/ArmR/HandR", "hand_r", "item_wrench", False),
    ("Hammer", "Rig/Hips/ArmR/HandR", "hand_r", "item_hammer", False),
    ("Clipboard", "Rig/Hips/ArmL/HandL", "hand_l", "item_clipboard", False),
    ("Carry", "Rig/Hips", "carry", None, True),
    ("Crate", "Rig/Hips/Carry", "carry", "item_crate", False),
    ("ScanHold", "Rig/Hips", "scan", None, True),
    ("Scanner", "Rig/Hips/ScanHold", "scan", "item_scanner", False),
    ("Neck", "Rig/Hips", "neck", "head", True),
    ("EyeL", "Rig/Hips/Neck", "eye_l", "eye_l", True),
    ("EyeR", "Rig/Hips/Neck", "eye_r", "eye_r", True),
    ("LidL", "Rig/Hips/Neck", "lid_l", "lid_l", False),
    ("LidR", "Rig/Hips/Neck", "lid_r", "lid_r", False),
    ("HappyL", "Rig/Hips/Neck", "eye_l", "eye_happy_l", False),
    ("HappyR", "Rig/Hips/Neck", "eye_r", "eye_happy_r", False),
    ("Mouth", "Rig/Hips/Neck", "mouth", None, True),
    ("Smile", "Rig/Hips/Neck/Mouth", "mouth", "mouth_smile", True),
    ("Open", "Rig/Hips/Neck/Mouth", "mouth", "mouth_open", False),
    ("Oh", "Rig/Hips/Neck/Mouth", "mouth", "mouth_o", False),
    ("EarL", "Rig/Hips/Neck", "ear_l", "ear_l", True),
    ("EarR", "Rig/Hips/Neck", "ear_r", "ear_r", True),
    ("Antenna", "Rig/Hips/Neck", "antenna", "antenna", True),
    ("Bulb", "Rig/Hips/Neck/Antenna", "bulb", "bulb", True),
    ("Helmet", "Rig/Hips/Neck", "neck", "acc_helmet", False),
    ("HardHat", "Rig/Hips/Neck", "neck", "acc_hardhat", False),
    ("Goggles", "Rig/Hips/Neck", "neck", "acc_goggles", False),
]


def pivot_of(key):
    if isinstance(key, tuple):
        return key
    if key in ("lid_l", "lid_r"):
        return LID_TOP["eye_" + key[-1]]
    return PIV[key]


def write_scene():
    abs_piv = {".": (0, 0, 0)}
    ext, nodes = [], []
    ext.append('[ext_resource type="Script" path="res://src/npc/creature.gd" id="script"]')
    ext.append('[ext_resource type="Material" path="res://scenes/npc/creature_material.tres" id="mat"]')
    ext.append('[ext_resource type="Material" path="res://scenes/npc/blob_shadow.tres" id="shadow_mat"]')
    ext.append('[ext_resource type="Texture2D" path="res://assets/voxel/creatures/ui/emotes.png" id="emotes"]')
    glbs = sorted({g for _, _, _, g, _ in RIG if g})
    for g in glbs:
        ext.append(f'[ext_resource type="PackedScene" path="res://assets/voxel/creatures/{g}.glb" id="g_{g}"]')
    sub = ['[sub_resource type="QuadMesh" id="shadow_quad"]\nsize = Vector2(0.62, 0.5)\norientation = 1']
    nodes.append('[node name="Creature" type="Node3D"]\nscript = ExtResource("script")\n'
                 'body_material = ExtResource("mat")')
    nodes.append('[node name="Shadow" type="MeshInstance3D" parent="."]\n'
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.012, 0.01)\n'
                 'cast_shadow = 0\nmesh = SubResource("shadow_quad")\n'
                 'surface_material_override/0 = ExtResource("shadow_mat")')
    for name, parent, key, glb, visible in RIG:
        p = pivot_of(key)
        path = name if parent == "." else f"{parent}/{name}"
        pp = abs_piv[parent]
        abs_piv[path] = p
        lx, ly, lz = (p[i] - pp[i] for i in range(3))
        t = f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lx:.4f}, {ly:.4f}, {lz:.4f})"
        head = f'[node name="{name}" type="Node3D" parent="{parent}"]'
        lines = [head, f"transform = {t}"]
        if not visible:
            lines.append("visible = false")
        nodes.append("\n".join(lines))
        if glb:
            nodes.append(f'[node name="Mesh" parent="{path}" instance=ExtResource("g_{glb}")]')
    nodes.append('[node name="Emote" type="Sprite3D" parent="."]\n'
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.38, 0)\nvisible = false\n'
                 'cast_shadow = 0\npixel_size = 0.0115\nbillboard = 1\nshaded = false\nalpha_cut = 1\n'
                 'texture_filter = 0\ntexture = ExtResource("emotes")\nhframes = 4\nvframes = 4\nrender_priority = 1')
    nodes.append('[node name="OnScreen" type="VisibleOnScreenNotifier3D" parent="."]\n'
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.6, 0)\n'
                 'aabb = AABB(-0.5, -0.6, -0.5, 1, 1.4, 1)')
    out = [f"[gd_scene load_steps={len(ext) + len(sub) + 1} format=3]", ""] + ext + [""]
    for s in sub:
        out += [s, ""]
    for n in nodes:
        out += [n, ""]
    SCENE.parent.mkdir(parents=True, exist_ok=True)
    SCENE.write_text("\n".join(out), encoding="utf-8", newline="\n")


# ================================================================== the hangar crowd scene
CROWD_SCENE = ROOT / "scenes" / "npc" / "hangar_crowd.tscn"
NAVMESH = ROOT / "scenes" / "npc" / "hangar_navmesh.tres"
PAD_R = 11.2


def _ring(r, angles):
    return [(r * math.cos(math.radians(a)), r * math.sin(math.radians(a))) for a in angles]


# points of interest (x, z) in hangar coordinates (VAB origin = pad centre). The default
# hangar camera looks toward -Z from the front-right: the floor it shows runs from the
# pad front (z ~ +14) back to the door (z = -60), so most points sit beside / behind the pad.
POINTS = {
    "work": _ring(PAD_R, [25, 62, 100, 138, 172, 205, 240, 282, 318]),
    "look": _ring(16.0, [150, 182, 214, 250, 292, 322, 350]),
    "rest": [(-19.0, 6.5), (-29.0, -13.0), (17.5, -25.0), (-21.0, -27.0)],
    "door": [(-26.0, -53.5), (-12.0, -54.5), (4.0, -54.0)],
    "wave": [(-12.5, 9.5), (8.5, 10.5), (-3.0, 12.6)],
    "dance": [(-14.0, -17.0), (6.0, -21.0)],
    "crate_pickup": [(11.6, -13.4), (15.6, -13.0), (13.6, -17.4)],
    "crate_drop": [(-13.5, 4.0), (-6.5, -13.0), (11.0, -6.5), (-14.5, -6.5)],
    "bench": [(-25.0, -7.6), (-23.0, -7.6)],
}
# NPCs: (name, role, variant, seed, x, z, yaw)
NPCS = [
    ("Npc1", "pilot", 0, 11, -4.0, 12.5, 160), ("Npc2", "engineer", 2, 23, 6.0, -16.0, 200),
    ("Npc3", "scientist", 4, 37, -12.0, -10.0, 150), ("Npc4", "pilot", 5, 41, 14.0, -6.0, 250),
    ("Npc5", "engineer", 8, 53, -22.0, -9.0, 120), ("Npc6", "scientist", 1, 67, -8.0, -22.0, 180),
    ("Npc7", "ground", 3, 71, 12.0, -10.0, 140), ("Npc8", "ground", 7, 83, -16.0, 4.0, 210),
    ("Npc9", "ground", 6, 97, 3.0, -28.0, 100),
]
WORKBENCH = (-24.0, -6.2)      # long axis along X; the crew stands on its far side, facing the camera
CRATES = (13.6, -15.0)
FACE = {"bench": (-24.0, 1.0, -5.0)}


def _xf(x, y, z, yaw=0.0, s=(1, 1, 1)):
    a = math.radians(yaw)
    c, sn = math.cos(a), math.sin(a)
    m = [c * s[0], 0, sn * s[2], 0, s[1], 0, -sn * s[0], 0, c * s[2]]
    return "Transform3D(" + ", ".join(f"{v:.5g}" for v in m + [x, y, z]) + ")"


def write_crowd_scene():
    ext = ['[ext_resource type="Script" path="res://src/npc/hangar_crowd.gd" id="1_crowd"]',
           '[ext_resource type="PackedScene" path="res://scenes/npc/hangar_npc.tscn" id="2_npc"]',
           '[ext_resource type="NavigationMesh" path="res://scenes/npc/hangar_navmesh.tres" id="3_nav"]',
           '[ext_resource type="PackedScene" path="res://assets/voxel/creatures/item_crate.glb" id="4_crate"]']
    sub = []
    mats = {"hazard": "#f2b705", "gunmetal": "#3c4450", "metal": "#a3adb8", "accent2": "#5fb0d8", "accent": "#f59a36",
            "structure": "#dfe3e7"}
    for k, hx in mats.items():
        r, g, b = (int(hx[i:i + 2], 16) / 255 for i in (1, 3, 5))
        sub.append(f'[sub_resource type="StandardMaterial3D" id="m_{k}"]\nalbedo_color = Color({r:.4g}, {g:.4g}, {b:.4g}, 1)\n'
                   f'roughness = 0.55\nmetallic = {0.4 if k in ("gunmetal", "metal") else 0.05}')
    sub.append('[sub_resource type="BoxMesh" id="b_unit"]')
    nodes = ['[node name="HangarCrowd" type="Node3D"]\nscript = ExtResource("1_crowd")',
             '[node name="NavRegion" type="NavigationRegion3D" parent="."]\nnavigation_mesh = ExtResource("3_nav")',
             '[node name="Props" type="Node3D" parent="."]']
    # a small workbench (long axis along Z) with a vise and a toolbox
    wx, wz = WORKBENCH
    nodes.append(f'[node name="Workbench" type="Node3D" parent="Props"]\ntransform = {_xf(wx, 0, wz, 90)}')
    boxes = [("Top", (0, 0.78, 0), (1.1, 0.12, 3.0), "gunmetal"), ("Shelf", (0, 0.25, 0), (1.0, 0.06, 2.8), "gunmetal")]
    for i, (lx, lz) in enumerate(((-0.45, -1.35), (0.45, -1.35), (-0.45, 1.35), (0.45, 1.35))):
        boxes.append((f"Leg{i}", (lx, 0.36, lz), (0.1, 0.72, 0.1), "hazard"))
    boxes += [("Vise", (-0.25, 0.95, -0.9), (0.3, 0.22, 0.24), "metal"), ("Toolbox", (0.05, 0.98, 0.8), (0.42, 0.28, 0.7), "accent"),
              ("ToolboxLid", (0.05, 1.14, 0.8), (0.44, 0.05, 0.72), "gunmetal"), ("Panel", (0.62, 1.3, 0), (0.06, 1.0, 2.6), "structure"),
              ("PanelStripe", (0.585, 1.72, 0), (0.02, 0.1, 2.6), "accent2"),
              ("Bin", (0, 0.42, -0.6), (0.8, 0.3, 0.9), "accent2")]
    for name, (x, y, z), (sx, sy, sz), m in boxes:
        nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="Props/Workbench"]\n'
                     f'transform = {_xf(x, y, z, 0, (sx, sy, sz))}\nmesh = SubResource("b_unit")\n'
                     f'surface_material_override/0 = SubResource("m_{m}")')
    # a stack of mini part crates next to the pad (NPCs carry these)
    nodes.append('[node name="CrateStack" type="Node3D" parent="Props"]\ntransform = ' + _xf(CRATES[0], 0, CRATES[1], 18))
    for i, (x, y, z, yaw) in enumerate(((-0.55, 0.6, 0, 4), (0.55, 0.6, 0.1, -6), (0.05, 1.55, 0.05, 12))):
        nodes.append(f'[node name="Crate{i}" parent="Props/CrateStack" instance=ExtResource("4_crate")]\n'
                     f'transform = {_xf(x, y, z, yaw, (3.2, 3.2, 3.2))}')
    nodes.append('[node name="Points" type="Node3D" parent="."]')
    for kind, pts in POINTS.items():
        for i, (x, z) in enumerate(pts):
            nodes.append(f'[node name="{kind}{i}" type="Marker3D" parent="Points"]\ntransform = {_xf(x, 0, z)}\n'
                         f'gizmo_extents = 0.6\nmetadata/kind = "{kind}"'
                         + (f'\nmetadata/face = Vector3{FACE[kind]}' if kind in FACE else ""))
    nodes.append('[node name="NPCs" type="Node3D" parent="."]')
    for name, role, var, seed, x, z, yaw in NPCS:
        nodes.append(f'[node name="{name}" parent="NPCs" instance=ExtResource("2_npc")]\ntransform = {_xf(x, 0, z, yaw)}\n'
                     f'role = "{role}"\nvariant = {var}\npersonality_seed = {seed}')
    out = [f"[gd_scene load_steps={len(ext) + len(sub) + 1} format=3]", ""] + ext + [""]
    for x in sub:
        out += [x, ""]
    for n in nodes:
        out += [n, ""]
    CROWD_SCENE.write_text("\n".join(out), encoding="utf-8", newline="\n")
    if not NAVMESH.exists():   # placeholder; src/npc/bake_hangar_navmesh.gd fills it
        NAVMESH.write_text('[gd_resource type="NavigationMesh" format=3]\n\n[resource]\nagent_height = 1.8\n'
                           'agent_radius = 0.7\nagent_max_climb = 0.3\n', encoding="utf-8", newline="\n")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    build_body()
    build_head()
    for s in (1, -1):
        build_eye(s)
        build_lid(s)
        build_eye_happy(s)
        build_ear(s)
        build_arm(s)
    build_mouths()
    build_tail()
    build_foot()
    build_antenna()
    build_helmet()
    build_hardhat()
    build_goggles()
    build_scarf()
    build_belt()
    build_vest()
    build_backpack()
    build_items()
    total = 0
    for name, (m, piv) in PARTS.items():
        vg.write_glb(OUT / f"{name}.glb", name, m)
        tris = len(m[3]) // 3
        total += tris
        print(f"{name:18s} tris={tris:6d}")
    print(f"total tris (all parts) = {total}")
    build_textures()
    build_icons()
    write_scene()
    write_crowd_scene()
    print(f"-> {OUT}, {SCENE} and {CROWD_SCENE}")


if __name__ == "__main__":
    main()
