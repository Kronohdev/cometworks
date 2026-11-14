"""Procedural voxel part generator (v2) for the Space Mission Design Game.

Every catalog `model` id (tools/parts_catalog.py) has a builder here. Builders work
in meters on a Canvas at a fixed voxel density, so all parts share one voxel size:
  - launcher parts:   LAUNCHER_VPM voxels per meter (5 cm voxels)
  - spacecraft parts: CRAFT_VPM voxels per meter (~1.6 cm voxels)
Meshing keeps only exposed faces and bakes per-vertex ambient occlusion and a
subtle per-voxel color jitter into vertex colors. Output is binary glTF (.glb).

Usage: python tools/voxel_gen.py <glb_out_dir> [only_id ...] [--naive]
Writes <out>/parts/<part_id>.glb for every catalog part and <out>/showcase/*.glb.
Axis convention: Y up, base of the part at y=0, X/Z centered on the part axis.
"""
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

LAUNCHER_VPM = 20
CRAFT_VPM = 64

PALETTE = {
    "white": (236, 238, 242), "offwhite": (212, 215, 222), "grey": (150, 158, 170),
    "darkgrey": (72, 76, 86), "black": (24, 24, 30), "steel": (190, 194, 201),
    "steel_dark": (138, 144, 153), "foam": (208, 116, 52), "foam_dark": (170, 88, 38),
    "orange": (242, 115, 30), "red": (205, 45, 45), "yellow": (240, 200, 40),
    "gold": (226, 178, 60), "gold_dark": (170, 124, 36), "copper": (186, 108, 62),
    "copper_dark": (122, 70, 44), "nozzle": (52, 54, 62), "carbon": (38, 40, 46),
    "silver": (206, 209, 216), "cell": (30, 54, 150), "cell_dark": (18, 30, 92),
    "glass": (90, 190, 242), "lens": (16, 26, 56), "blue": (40, 90, 200),
}
NAMES = list(PALETTE)
CI = {n: i + 1 for i, n in enumerate(NAMES)}
RGB = np.array([(0, 0, 0)] + [PALETTE[n] for n in NAMES], np.float32)


class Canvas:
    def __init__(self, xmin, xmax, ymin, ymax, zmin, zmax, vpm):
        self.vpm = vpm
        self.min = np.array([xmin, ymin, zmin], np.float64)
        nx, ny, nz = (max(1, int(math.ceil((b - a) * vpm))) for a, b in ((xmin, xmax), (ymin, ymax), (zmin, zmax)))
        self.a = np.zeros((nx, ny, nz), np.uint8)
        self.X = ((np.arange(nx) + 0.5) / vpm + xmin).reshape(nx, 1, 1)
        self.Y = ((np.arange(ny) + 0.5) / vpm + ymin).reshape(1, ny, 1)
        self.Z = ((np.arange(nz) + 0.5) / vpm + zmin).reshape(1, 1, nz)

    # ---- helpers
    @property
    def vox(self):
        return 1.0 / self.vpm

    def R(self, cx=0.0, cz=0.0):
        return np.sqrt((self.X - cx) ** 2 + (self.Z - cz) ** 2)

    def theta(self, cx=0.0, cz=0.0):
        return np.arctan2(self.Z - cz, self.X - cx)

    def put(self, mask, color):
        self.a[np.broadcast_to(mask, self.a.shape)] = CI[color]

    def paint(self, mask, color):
        m = np.broadcast_to(mask, self.a.shape) & (self.a > 0)
        self.a[m] = CI[color]

    def paint_where(self, mask, src, dst):
        m = np.broadcast_to(mask, self.a.shape) & (self.a == CI[src])
        self.a[m] = CI[dst]

    def hash(self, salt=0, block=3):
        """Per-voxel pseudo-random 0..255 used for speckles/mottling. Evaluated on blocks
        of `block` voxels so speckles form small patches: keeps the look while letting
        mesh_greedy() merge faces (single-voxel speckles defeat merging)."""
        i = (np.arange(self.a.shape[0]) // block).reshape(-1, 1, 1).astype(np.int64)
        j = (np.arange(self.a.shape[1]) // block).reshape(1, -1, 1).astype(np.int64)
        k = (np.arange(self.a.shape[2]) // block).reshape(1, 1, -1).astype(np.int64)
        return ((i * 73856093) ^ (j * 19349663) ^ (k * 83492791) ^ (salt * 2654435761)) & 255

    # ---- primitives (meters)
    def revolve(self, y0, y1, rout, color, rin=None, cx=0.0, cz=0.0):
        Y = self.Y
        R = self.R(cx, cz)
        ro = rout(Y) if callable(rout) else rout
        m = (Y >= y0) & (Y <= y1) & (R <= ro)
        if rin is not None:
            ri = rin(Y) if callable(rin) else rin
            m = m & (R >= ri)
        self.put(m, color)
        return m

    def box(self, x0, x1, y0, y1, z0, z1, color):
        m = (self.X >= x0) & (self.X <= x1) & (self.Y >= y0) & (self.Y <= y1) & (self.Z >= z0) & (self.Z <= z1)
        self.put(m, color)
        return m

    def cyl(self, axis, c1, c2, a0, a1, r, color, rin=None):
        if axis == "x":
            R, A = np.sqrt((self.Y - c1) ** 2 + (self.Z - c2) ** 2), self.X
        elif axis == "z":
            R, A = np.sqrt((self.X - c1) ** 2 + (self.Y - c2) ** 2), self.Z
        else:
            R, A = np.sqrt((self.X - c1) ** 2 + (self.Z - c2) ** 2), self.Y
        m = (A >= a0) & (A <= a1) & (R <= r)
        if rin is not None:
            m = m & (R >= rin)
        self.put(m, color)
        return m

    def sphere(self, cx, cy, cz, r, color, rin=None):
        d = np.sqrt((self.X - cx) ** 2 + (self.Y - cy) ** 2 + (self.Z - cz) ** 2)
        m = d <= r
        if rin is not None:
            m = m & (d >= rin)
        self.put(m, color)
        return m

    def segment(self, p0, p1, r, color):
        """Strut between two points."""
        p0, p1 = np.array(p0, float), np.array(p1, float)
        d = p1 - p0
        L2 = float(d @ d)
        t = ((self.X - p0[0]) * d[0] + (self.Y - p0[1]) * d[1] + (self.Z - p0[2]) * d[2]) / L2
        t = np.clip(t, 0, 1)
        dist2 = (self.X - p0[0] - t * d[0]) ** 2 + (self.Y - p0[1] - t * d[1]) ** 2 + (self.Z - p0[2] - t * d[2]) ** 2
        m = dist2 <= r * r
        self.put(m, color)
        return m


def canvas_r(radius, y0, y1, vpm, pad=0.0):
    r = radius + pad
    return Canvas(-r, r, y0, y1, -r, r, vpm)


def bell(y_exit, y_throat, r_exit, r_throat, power=0.55):
    def f(Y):
        t = np.clip((y_throat - Y) / (y_throat - y_exit), 0, 1)
        return r_throat + (r_exit - r_throat) * t ** power
    return f


def nozzle(c, y_exit, y_throat, r_exit, r_throat, color, inner="black", thick=None, power=0.55):
    th = thick or max(2 * c.vox, r_exit * 0.06)
    f = bell(y_exit, y_throat, r_exit, r_throat, power)
    v = c.vox
    # inner radius uses the narrower neighbor layer so steep flares stay watertight
    rin = lambda Y: np.minimum(f(Y - v), f(Y + v)) - th
    c.revolve(y_exit, y_throat, f, color, rin=rin)
    c.paint(((c.Y >= y_exit) & (c.Y <= y_throat)) & (c.R() <= rin(c.Y) + th * 0.55), inner)


def ring_bands(c, y_list, h, color):
    for y in y_list:
        c.paint((c.Y >= y) & (c.Y <= y + h), color)


def ogive(R, Lo):
    rho = (R * R + Lo * Lo) / (2 * R)

    def f(x):  # x from ogive base, 0..Lo
        x = np.clip(x, 0, Lo)
        return np.sqrt(np.maximum(rho * rho - x * x, 0)) + R - rho
    return f


# =================================================================== builders
def b_tank(kind="kerolox", d=2.5, length=4.0, vpm=LAUNCHER_VPM):
    r = d / 2
    c = canvas_r(r, 0, length, vpm, pad=0.12)
    body = {"kerolox": "white", "methalox": "steel", "hydrolox": "foam"}[kind]
    c.revolve(0, length, r, body)
    if kind == "kerolox":
        ring_bands(c, [0, length - 0.16], 0.16, "darkgrey")
        ring_bands(c, [length * 0.5 - 0.08], 0.16, "black")
    elif kind == "methalox":
        for y in np.arange(0.5, length, 0.5):  # weld seams
            c.paint((c.Y >= y) & (c.Y < y + c.vox), "steel_dark")
        h = c.hash(3)
        c.paint_where(h > 238, "steel", "silver")
    else:
        h = c.hash(5)
        c.paint_where(h > 175, "foam", "foam_dark")
        ring_bands(c, [0, length - 0.12], 0.12, "grey")
    # cable raceway on +X
    c.box(r - c.vox, r + 0.10, 0.12, length - 0.12, -0.09, 0.09, "grey")
    c.box(r + 0.04, r + 0.10, 0.12, length - 0.12, -0.05, 0.05, "darkgrey")
    return c


def b_tank_sphere(d=0.8, vpm=CRAFT_VPM):
    r = d / 2
    c = Canvas(-r - 0.1, r + 0.1, 0, d + 0.1, -r - 0.1, r + 0.1, vpm)
    c.sphere(0, r + 0.05, 0, r, "silver")
    c.paint((np.abs(c.Y - (r + 0.05)) < c.vox * 1.2), "steel_dark")  # girth weld
    for s in (-1, 1):  # mounting tabs
        c.box(s * r - 0.04, s * r + 0.06, r, r + 0.1, -0.03, 0.03, "grey")
    c.cyl("y", 0, 0, d + 0.02, d + 0.1, 0.025, "grey")  # outlet pipe
    return c


def b_tank_xenon(d=0.5, length=0.9, vpm=CRAFT_VPM):
    r = d / 2
    c = Canvas(-r - 0.05, r + 0.05, 0, length + 0.12, -r - 0.05, r + 0.05, vpm)
    c.revolve(r, length - r, r, "carbon")
    c.sphere(0, r, 0, r, "carbon")
    c.sphere(0, length - r, 0, r, "carbon")
    h = c.hash(9)
    c.paint_where(h > 200, "carbon", "darkgrey")
    ring_bands(c, [length * 0.35, length * 0.62], 0.03, "gold")
    c.cyl("y", 0, 0, length - 0.02, length + 0.12, 0.03, "silver")
    return c


def _pump(c, x, y, z, r, h, color="silver"):
    c.cyl("y", x, z, y, y + h, r, color)
    c.cyl("y", x, z, y + h, y + h + 0.06, r * 0.6, "steel_dark")


def b_engine(kind="kerolox"):
    vpm = LAUNCHER_VPM
    spec = {
        # exit_r, nozzle_len, throat_r, chamber_r, chamber_len, nozzle_color, extension
        "small": (0.20, 0.55, 0.06, 0.11, 0.22, "nozzle", None),
        "small_vac": (0.42, 1.05, 0.06, 0.11, 0.22, "darkgrey", None),
        "kerolox": (0.46, 1.45, 0.15, 0.27, 0.45, "nozzle", None),
        "kerolox_vac": (1.62, 3.9, 0.15, 0.27, 0.45, "darkgrey", 1.3),
        "hydrolox_upper": (1.07, 2.4, 0.13, 0.22, 0.40, "carbon", 1.0),
        "hydrolox_main": (1.20, 2.7, 0.28, 0.45, 0.55, "offwhite", None),
        "methalox": (0.65, 1.5, 0.18, 0.32, 0.45, "steel", None),
        "hypergolic": (0.58, 1.3, 0.10, 0.18, 0.35, "copper_dark", None),
    }[kind]
    r_e, n_len, r_t, r_c, c_len, ncol, ext = spec
    y_throat = n_len
    top = y_throat + c_len + 0.55 + r_c
    pad = 0.6 if kind in ("hydrolox_main", "methalox", "kerolox") else 0.35
    c = canvas_r(max(r_e, r_c + pad), 0, top + 0.25, vpm, pad=0.1)
    if ext:  # radiatively cooled extension below a regen section
        y_split = n_len * (1 - ext / n_len * 0.9) if ext < n_len else n_len * 0.35
        nozzle(c, 0, y_throat, r_e, r_t, ncol, power=0.5)
        f = bell(0, y_throat, r_e, r_t, 0.5)
        c.paint((c.Y >= y_split) & (c.R() >= f(c.Y) - 0.2), "silver")
        c.paint((c.Y >= y_split) & (c.Y <= y_split + 0.06), "steel_dark")
    else:
        nozzle(c, 0, y_throat, r_e, r_t, ncol, power=0.55)
    if kind == "hydrolox_main":  # coolant tubes on the bell
        th = c.theta()
        c.paint_where(((np.floor((th + math.pi) / (2 * math.pi) * 96) % 2) == 0) & (c.Y < y_throat), "offwhite", "silver")
    # converging section + chamber + injector dome
    yc0 = y_throat
    c.revolve(yc0, yc0 + c_len * 0.4, lambda Y: r_t + (r_c - r_t) * np.clip((Y - yc0) / (c_len * 0.4), 0, 1),
              "copper")
    c.revolve(yc0 + c_len * 0.4, yc0 + c_len, r_c, "copper" if kind != "methalox" else "steel")
    yd = yc0 + c_len
    c.revolve(yd, yd + r_c, lambda Y: np.sqrt(np.maximum(r_c ** 2 - (Y - yd) ** 2, 0)), "silver")
    # gimbal block + thrust frame
    yg = yd + r_c * 0.7
    c.box(-0.12, 0.12, yg, top, -0.12, 0.12, "steel_dark")
    c.revolve(top - 0.08, top, r_c + 0.15, "darkgrey")
    for a in range(4):  # thrust struts
        ang = a * math.pi / 2 + math.pi / 4
        c.segment((math.cos(ang) * r_c * 0.9, yd, math.sin(ang) * r_c * 0.9),
                  (math.cos(ang) * (r_c + 0.12), top, math.sin(ang) * (r_c + 0.12)), 0.035, "grey")
    # turbomachinery
    if kind in ("kerolox", "kerolox_vac", "hydrolox_upper", "hypergolic"):
        _pump(c, r_c + 0.2, yd - 0.15, 0.0, 0.14 if kind != "hypergolic" else 0.08, 0.45, "silver")
        c.segment((r_c + 0.2, yd - 0.1, 0.0), (r_c * 0.9, yd + 0.1, 0.0), 0.05, "steel_dark")
    if kind in ("kerolox",):  # gas generator exhaust pipe running down the side
        c.segment((r_c + 0.2, yd - 0.1, 0.12), (r_e + 0.08, 0.15, 0.12), 0.06, "black")
    if kind == "kerolox_vac":  # GG exhaust manifold ring
        f = bell(0, y_throat, r_e, r_t, 0.5)
        ym = n_len * 0.62
        c.revolve(ym, ym + 0.12, lambda Y: f(Y) + 0.08, "steel_dark", rin=lambda Y: f(Y) - 0.02)
    if kind in ("hydrolox_main", "methalox"):
        for sx in (-1, 1):
            _pump(c, sx * (r_c + 0.28), yd - 0.35, 0.05 * sx, 0.2, 0.6, "silver")
            c.segment((sx * (r_c + 0.28), yd + 0.3, 0.0), (0.0, yd + r_c, 0.0), 0.07, "steel_dark")
        c.cyl("x", yd + 0.2, -0.35, -r_c - 0.3, r_c + 0.3, 0.06, "grey")
    if kind in ("small", "small_vac"):
        c.box(-0.16, 0.16, yd - 0.05, yd + 0.18, 0.13, 0.30, "darkgrey")  # electric pump + battery pack
        c.box(-0.12, 0.12, yd, yd + 0.14, 0.30, 0.34, "yellow")
    return c


def b_srb(d=1.6, length=17.0):
    vpm = LAUNCHER_VPM
    r = d / 2
    c = canvas_r(r * 1.35, 0, length, vpm, pad=0.15)
    noz_h, skirt_h, nose_h = 1.3, 1.4, 2.6
    nozzle(c, 0, noz_h + 0.2, r * 0.62, r * 0.28, "nozzle", power=0.7)
    c.revolve(noz_h * 0.6, noz_h * 0.6 + skirt_h, lambda Y: r * 1.3 - (r * 0.3) * np.clip((Y - noz_h * 0.6) / skirt_h, 0, 1),
              "grey", rin=lambda Y: r * 1.3 - (r * 0.3) * np.clip((Y - noz_h * 0.6) / skirt_h, 0, 1) - 0.12)
    y0, y1 = noz_h * 0.6 + skirt_h, length - nose_h
    c.revolve(y0, y1, r, "white")
    ring_bands(c, list(np.arange(y0 + 3.0, y1 - 0.5, 3.0)), 0.12, "grey")
    f = ogive(r, nose_h)
    c.revolve(y1, length, lambda Y: f(Y - y1), "white")
    c.paint(c.Y > length - nose_h * 0.25, "grey")
    c.box(r - c.vox, r + 0.12, y0 + 0.5, y1 - 0.5, -0.08, 0.08, "grey")  # attach strut fairing
    return c


def b_thruster_mono():
    c = Canvas(-0.1, 0.1, 0, 0.26, -0.1, 0.1, CRAFT_VPM)
    nozzle(c, 0, 0.09, 0.045, 0.015, "copper_dark", thick=0.012, power=0.6)
    c.revolve(0.09, 0.16, 0.03, "silver")
    c.box(-0.05, 0.05, 0.16, 0.24, -0.05, 0.05, "grey")
    c.box(-0.03, 0.03, 0.24, 0.26, -0.03, 0.03, "black")
    return c


def b_thruster_ion():
    c = Canvas(-0.36, 0.36, 0, 0.42, -0.36, 0.36, CRAFT_VPM)
    c.revolve(0.0, 0.05, 0.34, "steel_dark")  # grid face (at bottom, thrust down)
    holes = ((np.floor(c.X * 40) + np.floor(c.Z * 40)) % 2 == 0) & (c.R() < 0.29)
    c.paint(holes & (c.Y < 0.05), "black")
    c.revolve(0.05, 0.30, 0.33, "gold")
    h = c.hash(2)
    c.paint_where(h > 180, "gold", "gold_dark")
    c.revolve(0.30, 0.36, 0.22, "silver")
    c.box(-0.08, 0.08, 0.36, 0.42, -0.08, 0.08, "grey")
    return c


def b_decoupler(d=2.5, h=0.32):
    c = canvas_r(d / 2, 0, h, LAUNCHER_VPM, pad=0.1)
    r = d / 2
    c.revolve(0, h, r, "darkgrey")
    stripes = (np.floor(((c.theta() + math.pi) * r + c.Y) / 0.18) % 2) == 0
    band = (c.Y > h * 0.3) & (c.Y < h * 0.7)
    c.paint(band & stripes, "yellow")
    c.paint(band & ~stripes, "black")
    for a in range(16):  # separation bolts
        ang = a * 2 * math.pi / 16
        c.box(math.cos(ang) * r - 0.05, math.cos(ang) * r + 0.07, h * 0.75, h, math.sin(ang) * r - 0.05,
              math.sin(ang) * r + 0.05, "silver")
    return c


def b_decoupler_radial():
    c = Canvas(-0.1, 0.6, 0, 1.0, -0.3, 0.3, LAUNCHER_VPM)
    c.box(0, 0.12, 0, 1.0, -0.25, 0.25, "darkgrey")
    c.paint((np.floor((c.Y + c.Z) / 0.12) % 2) == 0, "yellow")
    for y in (0.15, 0.85):
        c.segment((0.1, y, 0), (0.55, y, 0), 0.06, "steel")
    c.box(0.5, 0.6, 0.05, 0.95, -0.15, 0.15, "grey")
    return c


def b_interstage(d=3.75, h=3.0):
    r = d / 2
    c = canvas_r(r, 0, h, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, h, r, "carbon", rin=r - 0.12)
    h2 = c.hash(4)
    c.paint_where(h2 > 210, "carbon", "darkgrey")
    ring_bands(c, [0, h - 0.1], 0.1, "grey")
    return c


def b_adapter(d0=2.5, d1=3.75, h=1.6):
    r0, r1 = d0 / 2, d1 / 2
    c = canvas_r(r1, 0, h, LAUNCHER_VPM, pad=0.05)
    f = lambda Y: r1 + (r0 - r1) * np.clip(Y / h, 0, 1)
    c.revolve(0, h, f, "white", rin=lambda Y: f(Y) - 0.12)
    ring_bands(c, [0, h - 0.08], 0.08, "grey")
    return c


def b_thrust_plate(d=3.75, h=0.7, slots=9, hole_r=0.42):
    r = d / 2
    c = canvas_r(r, 0, h, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, h, r, "darkgrey")
    c.revolve(0, 0.1, r, "grey")
    ring = slots - 1
    centers = [(0.0, 0.0)] + [(math.cos(a * 2 * math.pi / ring) * r * 0.66, math.sin(a * 2 * math.pi / ring) * r * 0.66)
                              for a in range(ring)]
    for x, z in centers:
        m = c.R(x, z) <= hole_r
        c.a[np.broadcast_to(m & (c.Y < h - 0.15), c.a.shape)] = 0
        c.paint(m & (c.Y >= h - 0.15), "black")
    return c


def b_fairing(d=3.75, cyl_h=6.0, nose_h=5.5):
    r = d / 2
    c = canvas_r(r, 0, cyl_h + nose_h, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, cyl_h, r, "white")
    f = ogive(r, nose_h)
    c.revolve(cyl_h, cyl_h + nose_h, lambda Y: f(Y - cyl_h), "white")
    c.paint(np.abs(c.X) < c.vox * 0.8, "darkgrey")  # separation seam
    ring_bands(c, [0], 0.14, "grey")
    c.paint((c.Y > cyl_h * 0.55) & (c.Y < cyl_h * 0.62), "blue")
    return c


def b_nose_cone(d=1.25, h=2.0):
    r = d / 2
    c = canvas_r(r, 0, h, LAUNCHER_VPM, pad=0.05)
    f = ogive(r, h)
    c.revolve(0, h, lambda Y: f(Y), "white")
    c.paint(c.Y > h * 0.8, "red")
    ring_bands(c, [0], 0.08, "grey")
    return c


def b_fin(span=1.1, root=1.8, tip=0.7, t=0.10):
    c = Canvas(0, span, 0, root, -t, t, LAUNCHER_VPM)
    x = c.X
    top =root - (root - tip) * (x / span)
    m = (c.Y <= top) & (c.Y >= 0) & (np.abs(c.Z) <= t * (1 - 0.5 * x / span))
    c.put(m, "red")
    c.paint(c.X < 0.12, "darkgrey")
    c.paint((c.Y > top - 0.12), "white")
    return c


def b_payload_adapter(d0=2.5, d1=1.2, h=1.0):
    r0, r1 = d0 / 2, d1 / 2
    c = canvas_r(r0, 0, h + 0.12, LAUNCHER_VPM, pad=0.05)
    f = lambda Y: r0 + (r1 - r0) * np.clip(Y / h, 0, 1)
    c.revolve(0, h, f, "grey", rin=lambda Y: f(Y) - 0.1)
    c.revolve(h, h + 0.12, r1 + 0.05, "silver", rin=r1 - 0.1)  # clamp band
    return c


def b_avionics_core(d=1.25, h=0.55):
    r = d / 2
    c = canvas_r(r, 0, h + 0.3, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, h, r, "darkgrey")
    for a in range(8):
        ang = a * math.pi / 4
        cx, cz = math.cos(ang) * r * 0.92, math.sin(ang) * r * 0.92
        c.box(cx - 0.12, cx + 0.12, 0.12, h - 0.12, cz - 0.12, cz + 0.12, "silver" if a % 2 else "gold")
    ring_bands(c, [0, h - 0.06], 0.06, "grey")
    c.cyl("y", r * 0.5, 0, h, h + 0.3, 0.02, "black")  # GPS/telemetry whips
    c.cyl("y", -r * 0.5, 0, h, h + 0.22, 0.02, "black")
    c.box(-0.1, 0.1, h, h + 0.04, r * 0.4, r * 0.6, "white")  # GPS patch
    return c


def b_crew_capsule(d=2.5, h=2.4):
    r = d / 2
    c = canvas_r(r, 0, h + 0.4, LAUNCHER_VPM, pad=0.08)
    c.revolve(0, 0.22, r, "black")  # heat shield
    f = lambda Y: r - (r - 0.55) * np.clip((Y - 0.22) / (h - 0.22), 0, 1)
    c.revolve(0.22, h, f, "white")
    for a in range(4):  # windows
        ang = a * math.pi / 2 + math.pi / 4
        wx, wz = math.cos(ang), math.sin(ang)
        c.paint((np.abs(c.Y - h * 0.55) < 0.14) & (((c.X * wx + c.Z * wz) / np.maximum(c.R(), 1e-6)) > 0.985), "glass")
    c.revolve(h, h + 0.4, 0.45, "silver", rin=0.3)  # docking ring
    for a in range(4):  # RCS pods
        ang = a * math.pi / 2
        px, pz = math.cos(ang) * (f(np.array(h * 0.8)) + 0.02), math.sin(ang) * (f(np.array(h * 0.8)) + 0.02)
        c.box(px - 0.08, px + 0.08, h * 0.75, h * 0.88, pz - 0.08, pz + 0.08, "darkgrey")
    return c


def b_parachute(d=1.25, h=0.7):
    r = d / 2
    c = canvas_r(r, 0, h, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, h * 0.7, r, "grey")
    c.revolve(h * 0.7, h, lambda Y: r * (1 - 0.35 * np.clip((Y - h * 0.7) / (h * 0.3), 0, 1)), "orange")
    c.paint((np.floor((c.theta() + math.pi) / (math.pi / 4)) % 2 == 0) & (c.Y > h * 0.7), "white")
    return c


def b_landing_legs(length=6.0):
    c = Canvas(-0.5, 0.6, 0, length, -0.5, 0.5, LAUNCHER_VPM)
    c.box(0, 0.22, 0.4, length, -0.25, 0.25, "carbon")
    c.box(0.04, 0.18, 0.4, length * 0.9, -0.12, 0.12, "black")
    c.box(-0.45, 0.55, 0, 0.4, -0.45, 0.45, "darkgrey")  # foot pad
    c.box(0, 0.22, length - 0.2, length, -0.25, 0.25, "silver")
    return c


def b_grid_fins(w=1.2, h=1.5, t=0.18):
    c = Canvas(-0.2, w + 0.1, 0, h, -t, t, LAUNCHER_VPM)
    frame = (c.X >= 0) & (c.X <= w) & (c.Y >= 0) & (c.Y <= h) & (np.abs(c.Z) <= t)
    edge = (c.X < 0.08) | (c.X > w - 0.08) | (c.Y < 0.08) | (c.Y > h - 0.08)
    lattice = ((np.abs(((c.X + c.Y) / 0.2) % 1 - 0.5) < 0.18) | (np.abs(((c.X - c.Y) / 0.2) % 1 - 0.5) < 0.18))
    c.put(frame & (edge | lattice), "steel_dark")
    c.box(-0.2, 0, h * 0.4, h * 0.6, -0.1, 0.1, "grey")
    return c


# ----------------------------------------------------------- spacecraft parts
def b_reaction_wheels():
    c = Canvas(-0.2, 0.2, 0, 0.22, -0.2, 0.2, CRAFT_VPM)
    c.box(-0.19, 0.19, 0, 0.04, -0.19, 0.19, "grey")
    for x, z in ((-0.1, -0.1), (0.1, -0.1), (-0.1, 0.1), (0.1, 0.1)):
        c.cyl("y", x, z, 0.04, 0.2, 0.08, "darkgrey")
        c.cyl("y", x, z, 0.2, 0.22, 0.05, "silver")
    return c


def b_rcs_block():
    c = Canvas(-0.16, 0.16, 0, 0.2, -0.16, 0.16, CRAFT_VPM)
    c.box(-0.07, 0.07, 0, 0.14, -0.07, 0.07, "silver")
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        c.segment((dx * 0.07, 0.07, dz * 0.07), (dx * 0.15, 0.07, dz * 0.15), 0.025, "copper_dark")
    c.cyl("y", 0, 0, 0.14, 0.2, 0.03, "nozzle")
    return c


def b_star_tracker():
    c = Canvas(-0.1, 0.1, 0, 0.3, -0.1, 0.1, CRAFT_VPM)
    c.box(-0.07, 0.07, 0, 0.1, -0.07, 0.07, "darkgrey")
    c.cyl("y", 0, 0, 0.1, 0.3, 0.075, "silver", rin=0.05)
    c.cyl("y", 0, 0, 0.1, 0.13, 0.05, "lens")
    return c


def _cells(c, mask_panel, pitch=0.1):
    c.put(mask_panel, "cell")
    lines = (np.abs(((c.X / pitch) % 1)) < 0.12) | (np.abs(((c.Z / pitch) % 1)) < 0.12)
    c.paint(mask_panel & lines, "cell_dark")


def b_solar_body(w=0.7, d=0.7):
    c = Canvas(-w / 2, w / 2, 0, 0.05, -d / 2, d / 2, CRAFT_VPM)
    c.box(-w / 2, w / 2, 0, 0.025, -d / 2, d / 2, "white")
    _cells(c, (c.Y > 0.025) & (np.abs(c.X) < w / 2 - 0.02) & (np.abs(c.Z) < d / 2 - 0.02), 0.08)
    return c


def b_solar_wing(panels=3, pw=1.2, pd=1.1):
    total = panels * pw + 0.08 * (panels - 1)
    c = Canvas(-0.3, total + 0.5, -0.1, 0.1, -pd / 2 - 0.05, pd / 2 + 0.05, CRAFT_VPM)
    c.segment((-0.3, 0, 0), (0.4, 0, 0), 0.04, "silver")  # yoke
    c.box(-0.3, -0.18, -0.08, 0.08, -0.08, 0.08, "darkgrey")  # gimbal drive
    for i in range(panels):
        x0 = 0.4 + i * (pw + 0.08)
        c.box(x0, x0 + pw, -0.02, 0.0, -pd / 2, pd / 2, "white")
        _cells(c, (c.X >= x0 + 0.03) & (c.X <= x0 + pw - 0.03) & (c.Y > 0.0) & (c.Y <= 0.03)
               & (np.abs(c.Z) <= pd / 2 - 0.03), 0.1)
        c.box(x0, x0 + pw, 0.0, 0.03, -pd / 2, -pd / 2 + 0.025, "silver")
        c.box(x0, x0 + pw, 0.0, 0.03, pd / 2 - 0.025, pd / 2, "silver")
    return c


def b_solar_rollout(w=1.6, length=5.0):
    c = Canvas(-0.3, length + 0.3, -0.1, 0.12, -w / 2 - 0.12, w / 2 + 0.12, CRAFT_VPM)
    for s in (-1, 1):
        c.cyl("x", 0.02, s * (w / 2 + 0.04), 0, length, 0.04, "silver")  # booms
    c.cyl("z", 0.0, 0.02, -w / 2 - 0.08, w / 2 + 0.08, 0.09, "darkgrey")  # root canister
    c.cyl("z", length, 0.02, -w / 2 - 0.08, w / 2 + 0.08, 0.07, "silver")  # tip mandrel
    _cells(c, (c.X > 0.1) & (c.X < length - 0.08) & (np.abs(c.Z) < w / 2) & (c.Y >= 0.0) & (c.Y < 0.025), 0.2)
    return c


def b_battery():
    c = Canvas(-0.18, 0.18, 0, 0.2, -0.13, 0.13, CRAFT_VPM)
    c.box(-0.17, 0.17, 0, 0.16, -0.12, 0.12, "darkgrey")
    c.paint((c.Y > 0.14) & ((np.floor(c.X / 0.06) + np.floor(c.Z / 0.06)) % 2 == 0), "black")
    c.box(-0.04, 0.04, 0.16, 0.2, -0.03, 0.03, "red")
    c.box(0.06, 0.12, 0.16, 0.2, -0.03, 0.03, "black")
    return c


def b_rtg(d=0.64, h=0.66):
    c = Canvas(-d / 2 - 0.05, d / 2 + 0.05, 0, h + 0.05, -d / 2 - 0.05, d / 2 + 0.05, CRAFT_VPM)
    c.cyl("y", 0, 0, 0.0, h, 0.15, "darkgrey")
    for a in range(8):
        ang = a * math.pi / 4
        c.segment((math.cos(ang) * 0.12, 0.03, math.sin(ang) * 0.12),
                  (math.cos(ang) * d / 2, 0.03, math.sin(ang) * d / 2), 0.02, "black")
        c.segment((math.cos(ang) * 0.12, h - 0.03, math.sin(ang) * 0.12),
                  (math.cos(ang) * d / 2, h - 0.03, math.sin(ang) * d / 2), 0.02, "black")
        m =(np.abs((c.X * math.sin(ang) - c.Z * math.cos(ang))) < 0.015) & \
            ((c.X * math.cos(ang) + c.Z * math.sin(ang)) > 0.12) & ((c.X * math.cos(ang) + c.Z * math.sin(ang)) < d / 2) & \
            (c.Y > 0.03) & (c.Y < h - 0.03)
        c.put(m, "black")
    c.cyl("y", 0, 0, h, h + 0.05, 0.08, "silver")
    return c


def b_antenna_omni():
    c = Canvas(-0.06, 0.06, 0, 0.6, -0.06, 0.06, CRAFT_VPM)
    c.cyl("y", 0, 0, 0, 0.06, 0.05, "grey")
    c.cyl("y", 0, 0, 0.06, 0.5, 0.012, "silver")
    c.revolve(0.5, 0.6, lambda Y: 0.045 * (1 - np.clip((Y - 0.5) / 0.1, 0, 1)), "white")
    return c


def b_dish(dia=1.5, vpm=CRAFT_VPM):
    r = dia / 2
    f = dia * 0.45  # focal length
    depth = r * r / (4 * f)
    hbase = 0.35
    c = Canvas(-r - 0.02, r + 0.02, 0, hbase + depth + f + 0.1, -r - 0.02, r + 0.02, vpm)
    c.cyl("y", 0, 0, 0, 0.12, 0.14, "darkgrey")  # gimbal base
    c.cyl("y", 0, 0, 0.12, hbase, 0.05, "silver")
    p = hbase + c.R() ** 2 / (4 * f)
    slope = c.R() / (2 * f)  # dp/dR: thicken vertically where the dish is steep so it stays watertight
    t = np.maximum(2 * c.vox, c.vox * (1.5 + 1.5 * slope))
    m = (c.R() <= r) & (c.Y >= p) & (c.Y <= p + t)
    c.put(m, "white")
    c.paint(m & (c.R() > r - 0.03), "grey")
    yf = hbase + f
    for a in range(3):  # feed support struts
        ang = a * 2 * math.pi / 3
        c.segment((math.cos(ang) * r * 0.85, hbase + (r * 0.85) ** 2 / (4 * f), math.sin(ang) * r * 0.85),
                  (0, yf, 0), 0.012, "grey")
    c.sphere(0, yf, 0, 0.05, "gold")
    return c


def b_radiator(w=0.8, h=1.0):
    c = Canvas(-w / 2, w / 2, 0, h, -0.03, 0.03, CRAFT_VPM)
    c.box(-w / 2, w / 2, 0, h, -0.015, 0.015, "white")
    c.paint(np.abs(((c.X / 0.1) % 1) - 0.5) < 0.12, "grey")  # coolant loops
    c.paint((c.Y < 0.04) | (c.Y > h - 0.04), "grey")
    return c


def b_mli(w=0.6):
    c = Canvas(-w / 2, w / 2, 0, w, -w / 2, w / 2, CRAFT_VPM)
    c.box(-w / 2, w / 2, 0, w, -w / 2, w / 2, "gold")
    h = c.hash(11)
    c.paint_where(h > 150, "gold", "gold_dark")
    return c


def b_bus(w=1.5, h=1.4):
    c = Canvas(-w / 2, w / 2, 0, h, -w / 2, w / 2, CRAFT_VPM)
    c.box(-w / 2, w / 2, 0, h, -w / 2, w / 2, "gold")
    hh = c.hash(7)
    c.paint_where(hh > 160, "gold", "gold_dark")
    e = 0.05
    edges = ((np.abs(c.X) > w / 2 - e).astype(int) + (np.abs(c.Z) > w / 2 - e) + ((c.Y < e) | (c.Y > h - e))) >= 2
    c.paint(edges, "grey")
    c.paint((c.Z > w / 2 - 0.03) & (np.abs(c.X) < w * 0.35) & (c.Y > h * 0.2) & (c.Y < h * 0.8), "white")  # radiator face
    c.paint((c.Z > w / 2 - 0.03) & (np.abs(((c.X / 0.08) % 1) - 0.5) < 0.1) & (np.abs(c.X) < w * 0.35)
            & (c.Y > h * 0.2) & (c.Y < h * 0.8), "silver")
    c.cyl("y", 0, 0, 0, 0.06, 0.4, "silver")  # launch adapter ring at the bottom
    return c


def b_camera(hr=False):
    if hr:
        c = Canvas(-0.2, 0.2, 0, 0.75, -0.2, 0.2, CRAFT_VPM)
        c.box(-0.16, 0.16, 0, 0.14, -0.16, 0.16, "darkgrey")
        c.cyl("y", 0, 0, 0.14, 0.72, 0.13, "white", rin=0.1)
        c.cyl("y", 0, 0, 0.14, 0.18, 0.1, "lens")
        c.paint(c.Y > 0.68, "black")
        c.cyl("y", 0, 0, 0.30, 0.32, 0.14, "silver")
    else:
        c = Canvas(-0.12, 0.12, 0, 0.32, -0.12, 0.12, CRAFT_VPM)
        c.box(-0.1, 0.1, 0, 0.14, -0.1, 0.1, "darkgrey")
        c.cyl("y", 0, 0, 0.14, 0.26, 0.06, "silver")
        c.cyl("y", 0, 0, 0.26, 0.32, 0.075, "black", rin=0.06)  # sunshade hood
        c.cyl("y", 0, 0, 0.255, 0.27, 0.06, "lens")
    return c


def b_neutron_spec():
    c = Canvas(-0.16, 0.16, 0, 0.42, -0.16, 0.16, CRAFT_VPM)
    c.box(-0.15, 0.15, 0, 0.12, -0.12, 0.12, "darkgrey")
    c.cyl("y", 0, 0, 0.12, 0.42, 0.09, "silver")
    ring_bands(c, [0.2, 0.32], 0.02, "gold")
    return c


def b_spectrometer():
    c = Canvas(-0.25, 0.25, 0, 0.36, -0.2, 0.2, CRAFT_VPM)
    c.box(-0.22, 0.22, 0, 0.26, -0.16, 0.16, "offwhite")
    c.box(-0.1, 0.1, 0.26, 0.3, -0.1, 0.1, "black")  # aperture
    c.segment((-0.12, 0.3, -0.12), (0.12, 0.36, -0.12), 0.012, "grey")  # cover hinge
    c.box(-0.12, 0.12, 0.3, 0.32, -0.16, -0.1, "silver")
    for i in range(5):  # cooler fins
        x = -0.2 + i * 0.08
        c.box(x, x + 0.015, 0.05, 0.22, 0.16, 0.2, "silver")
    return c


def b_radar(w=1.6, h=0.9):
    c = Canvas(-w / 2, w / 2, 0, h + 0.3, -0.12, 0.12, CRAFT_VPM)
    c.box(-0.05, 0.05, 0, 0.3, -0.05, 0.05, "silver")
    c.box(-w / 2, w / 2, 0.3, 0.3 + h, -0.03, 0.02, "offwhite")
    patches = (np.abs(((c.X / 0.1) % 1) - 0.5) < 0.25) & (np.abs((((c.Y - 0.3) / 0.1) % 1) - 0.5) < 0.25)
    c.paint(patches & (c.Z > 0.0) & (c.Y > 0.32), "gold")
    return c


def b_lidar():
    c = Canvas(-0.2, 0.2, 0, 0.32, -0.2, 0.2, CRAFT_VPM)
    c.box(-0.18, 0.18, 0, 0.18, -0.18, 0.18, "offwhite")
    c.cyl("y", -0.04, 0, 0.18, 0.3, 0.12, "silver", rin=0.1)
    c.cyl("y", -0.04, 0, 0.18, 0.2, 0.1, "lens")
    c.box(0.1, 0.17, 0.18, 0.32, -0.04, 0.04, "darkgrey")  # laser
    c.cyl("y", 0.135, 0, 0.32, 0.33, 0.02, "red")
    return c


def b_magnetometer(length=2.0):
    c = Canvas(-0.1, length + 0.1, -0.06, 0.12, -0.06, 0.06, CRAFT_VPM)
    c.box(-0.08, 0.04, -0.05, 0.08, -0.05, 0.05, "darkgrey")  # hinge
    c.cyl("x", 0.0, 0.0, 0.04, length, 0.018, "carbon")
    for x in (length * 0.33, length * 0.66):
        c.cyl("x", 0.0, 0.0, x, x + 0.03, 0.028, "silver")
    c.box(length - 0.06, length + 0.06, -0.05, 0.07, -0.05, 0.05, "white")
    return c


# =================================================================== v2 catalog expansion builders
# Same conventions as above (meters, Y up, base at y=0, radial parts grow toward +X from x=0).
# Launcher-scale parts use LAUNCHER_VPM, small spacecraft hardware CRAFT_VPM.
def _bell_at(c, cx, cz, y0, y1, r_e, r_t, color, inner="black", power=0.55, thick=None):
    """Bell nozzle like nozzle(), but on an arbitrary vertical axis (cx, cz) and base height y0."""
    th = thick or max(2 * c.vox, r_e * 0.06)
    f = bell(y0, y1, r_e, r_t, power)
    v = c.vox
    rin = lambda Y: np.minimum(f(Y - v), f(Y + v)) - th
    c.revolve(y0, y1, f, color, rin=rin, cx=cx, cz=cz)
    c.paint((c.Y >= y0) & (c.Y <= y1) & (c.R(cx, cz) <= rin(c.Y) + th * 0.55), inner)
    return f


def _chamber_at(c, cx, cz, y_t, r_t, r_c, c_len, col="copper", dome="silver"):
    k = c_len * 0.4
    c.revolve(y_t, y_t + k, lambda Y: r_t + (r_c - r_t) * np.clip((Y - y_t) / k, 0, 1), col, cx=cx, cz=cz)
    c.revolve(y_t + k, y_t + c_len, r_c, col, cx=cx, cz=cz)
    yd = y_t + c_len
    c.revolve(yd, yd + r_c, lambda Y: np.sqrt(np.maximum(r_c ** 2 - (Y - yd) ** 2, 0)), dome, cx=cx, cz=cz)
    return yd


def _stripes(c, cx, cz, n):
    return (np.floor((c.theta(cx, cz) + math.pi) / (2 * math.pi) * n) % 2) == 0


def b_engine_v2(r_e, n_len, r_t, r_c, c_len, ncol="nozzle", ccol="copper", chambers=1, spacing=0.0, pumps=1,
                ext=None, ext_col="silver", tubes=None, power=0.55, frame_h=0.55, gg=False, valves=False,
                vpm=LAUNCHER_VPM):
    """Parametric liquid engine: 1, 2 or 4 bell chambers under a common thrust frame."""
    if chambers == 1:
        offs = [(0.0, 0.0)]
    else:
        a0 = math.pi / 4 if chambers == 4 else 0.0
        offs = [(math.cos(a0 + k * 2 * math.pi / chambers) * spacing, math.sin(a0 + k * 2 * math.pi / chambers) * spacing)
                for k in range(chambers)]
    yd = n_len + c_len
    top = yd + r_c + frame_h
    rp = spacing + r_c + 0.26  # side pump radius
    half = max(spacing + r_e, rp + 0.24 if pumps and chambers == 1 else spacing + r_c + 0.2)
    c = canvas_r(half, 0, top + 0.05, vpm, pad=0.1)
    for cx, cz in offs:
        f = _bell_at(c, cx, cz, 0, n_len, r_e, r_t, ncol, power=power)
        if tubes:  # regenerative coolant tubes
            n = max(24, int(2 * math.pi * r_e * vpm / 3) // 2 * 2)
            c.paint_where(_stripes(c, cx, cz, n) & (c.Y < n_len), ncol, tubes)
        if ext:  # regen section above a radiatively cooled extension
            ys = n_len * ext
            c.paint_where((c.Y >= ys) & (c.R(cx, cz) >= f(c.Y) - 0.25), ncol, ext_col)
            if tubes:
                c.paint_where((c.Y >= ys) & (c.R(cx, cz) >= f(c.Y) - 0.25), tubes, ext_col)
            c.paint((c.Y >= ys) & (c.Y < ys + 2 * c.vox) & (c.R(cx, cz) >= f(c.Y) - 0.25), "steel_dark")
        _chamber_at(c, cx, cz, n_len, r_t, r_c, c_len, ccol)
        for a in range(4):  # thrust struts from each dome to the frame
            ang = a * math.pi / 2 + math.pi / 4
            c.segment((cx + math.cos(ang) * r_c * 0.8, yd + r_c * 0.3, cz + math.sin(ang) * r_c * 0.8),
                      (cx * 0.7 + math.cos(ang) * (r_c + 0.1), top, cz * 0.7 + math.sin(ang) * (r_c + 0.1)),
                      max(0.035, c.vox * 0.8), "grey")
    plate_r = spacing + r_c + 0.15
    c.revolve(top - 0.08, top, plate_r, "darkgrey")
    c.box(-0.12, 0.12, yd + r_c * 0.6, top, -0.12, 0.12, "steel_dark")  # gimbal block
    if chambers > 1:  # one central turbopump feeding every chamber
        c.cyl("y", 0, 0, yd - 0.25, top - 0.08, min(spacing * 0.55, 0.45), "silver")
        ring_bands(c, [yd + 0.1], 0.06, "steel_dark")
        for cx, cz in offs:
            c.segment((0, yd + 0.1, 0), (cx, yd + r_c * 0.8, cz), max(0.06, r_c * 0.3), "steel_dark")
    elif pumps:
        for k in range(pumps):
            ang = k * math.pi
            px, pz = math.cos(ang) * rp, math.sin(ang) * rp
            _pump(c, px, yd - 0.2, pz, 0.12 + 0.04 * (r_c > 0.3), 0.5, "silver")
            c.segment((px, yd - 0.05, pz), (math.cos(ang) * r_c * 0.8, yd + 0.15, math.sin(ang) * r_c * 0.8),
                      0.05, "steel_dark")
        if gg:  # gas-generator exhaust duct running down the side
            c.segment((rp, yd - 0.15, 0.14), (r_e + 0.06, 0.2, 0.14), 0.07, "black")
    if valves:  # pressure-fed: propellant valves and lines instead of pumps
        for s in (-1, 1):
            c.box(s * r_c - 0.09, s * r_c + 0.09, yd + 0.05, yd + 0.25, -0.09, 0.09, "gold" if s > 0 else "silver")
            c.segment((s * r_c, yd + 0.25, 0), (s * 0.12, top - 0.08, 0), 0.04, "steel_dark")
        c.revolve(yd + r_c * 0.5, yd + r_c * 0.5 + 0.06, r_c + 0.12, "steel_dark", rin=r_c + 0.04)  # gimbal ring
    return c


def b_apogee():
    """490 N bipropellant apogee engine (R-4D class)."""
    c = Canvas(-0.16, 0.16, 0, 0.66, -0.16, 0.16, CRAFT_VPM)
    _bell_at(c, 0, 0, 0, 0.44, 0.14, 0.024, "steel_dark", power=0.6, thick=0.024)
    c.paint_where(c.Y < 0.24, "steel_dark", "darkgrey")
    ring_bands(c, [0.24], 0.012, "copper_dark")
    _chamber_at(c, 0, 0, 0.44, 0.024, 0.042, 0.08, "steel_dark", "silver")
    c.box(-0.07, 0.07, 0.54, 0.6, -0.07, 0.07, "grey")  # injector / valve plate
    c.cyl("y", -0.05, 0, 0.6, 0.66, 0.025, "silver")  # fuel valve
    c.cyl("y", 0.05, 0, 0.6, 0.66, 0.025, "gold")  # oxidizer valve
    c.box(-0.14, 0.14, 0.52, 0.54, -0.03, 0.03, "darkgrey")  # mounting flange
    return c


def b_mono_lander():
    """Throttleable 3 kN hydrazine thruster (MR-80B class)."""
    c = Canvas(-0.14, 0.14, 0, 0.5, -0.14, 0.14, CRAFT_VPM)
    _bell_at(c, 0, 0, 0, 0.24, 0.1, 0.022, "copper_dark", power=0.6, thick=0.022)
    _chamber_at(c, 0, 0, 0.24, 0.022, 0.045, 0.1, "silver", "silver")
    c.box(-0.07, 0.07, 0.36, 0.44, -0.06, 0.06, "grey")  # throttle valve body
    c.cyl("x", 0.4, 0.0, 0.07, 0.13, 0.03, "black")  # valve actuator
    c.box(-0.13, 0.13, 0.44, 0.47, -0.05, 0.05, "darkgrey")  # bracket
    c.cyl("y", 0, 0, 0.47, 0.5, 0.02, "silver")  # feed line
    return c


def b_hall(d=0.24):
    """Hall-effect thruster: annular discharge channel facing down (-Y)."""
    r = d / 2
    h = d * 0.55
    c = Canvas(-r - 0.06, r + 0.08, 0, h + d * 0.12, -r - 0.06, r + 0.06, CRAFT_VPM)
    c.cyl("y", 0, 0, 0, h, r, "steel_dark")
    c.cyl("y", 0, 0, 0, 2 * c.vox, r * 0.78, "black", rin=r * 0.5)  # channel
    c.paint((c.Y < 2.2 * c.vox) & (c.R() <= r * 0.72) & (c.R() >= r * 0.56), "blue")  # plasma glow
    c.cyl("y", 0, 0, 0, h, r * 0.4, "silver")  # inner magnetic pole
    for a in range(8 if d > 0.4 else 4):  # outer coils
        ang = a * 2 * math.pi / (8 if d > 0.4 else 4) + math.pi / 8
        c.cyl("y", math.cos(ang) * r * 0.9, math.sin(ang) * r * 0.9, h * 0.15, h * 0.85, r * 0.16, "copper")
    c.cyl("y", 0, 0, h, h + d * 0.12, r * 0.55, "grey")  # mount
    c.cyl("y", r + 0.03, 0, 0.0, h * 0.6, 0.022 + d * 0.03, "silver")  # hollow cathode
    c.cyl("y", r + 0.03, 0, 0.0, 0.012, 0.012 + d * 0.015, "black")
    c.box(r * 0.3, r + 0.03, h * 0.45, h * 0.6, -0.012, 0.012, "grey")
    return c


def b_kick_motor(d=1.24, length=2.03):
    """Spherical-case solid kick motor (Star 48 / Star 37 class), nozzle down."""
    r = d / 2
    vpm = LAUNCHER_VPM if d > 1.0 else 32
    c = canvas_r(r, 0, length, vpm, pad=0.08)
    noz_h = length * 0.3
    case0, case1 = noz_h * 0.55, length - 0.1
    yc, a = (case0 + case1) / 2, (case1 - case0) / 2
    c.revolve(case0, case1, lambda Y: r * np.sqrt(np.clip(1 - ((Y - yc) / a) ** 2, 0, 1)) ** 0.55, "offwhite")
    hh = c.hash(13)
    c.paint_where(hh > 215, "offwhite", "white")
    ring_bands(c, [yc - c.vox], 2 * c.vox, "grey")  # girth weld
    _bell_at(c, 0, 0, 0, noz_h + 0.05, r * 0.42, r * 0.13, "carbon", power=0.75)
    c.revolve(case1 - 0.02, length, r * 0.42, "silver", rin=r * 0.3)  # forward attach ring
    c.revolve(case0 + 0.05, case0 + 0.15, r * 0.62, "silver", rin=r * 0.45)  # aft attach ring
    return c


def b_sep_motor():
    """Small solid separation / ullage motor with a canted nozzle, mounted on its -X side."""
    c = Canvas(0, 0.36, 0, 0.82, -0.14, 0.14, CRAFT_VPM)
    cx = 0.16
    c.cyl("y", cx, 0, 0.14, 0.66, 0.11, "white")
    ring_bands(c, [0.28, 0.5], 0.03, "darkgrey")
    c.paint((c.Y > 0.31) & (c.Y < 0.47) & ((np.floor((c.theta(cx, 0) + math.pi) * 3) % 2) == 0) & (c.R(cx, 0) > 0.09),
            "yellow")
    nose = lambda Y: 0.11 * np.sqrt(np.clip(1 - ((Y - 0.66) / 0.16) ** 2, 0, 1))
    c.revolve(0.66, 0.82, nose, "white", cx=cx)
    c.paint(c.Y > 0.78, "red")
    for i in range(9):  # canted nozzle (down and outward)
        t = i / 8
        p = (cx + 0.1 * t, 0.14 - 0.12 * t, 0)
        c.segment(p, (p[0] + 0.012, p[1] - 0.015, 0), 0.035 + 0.035 * t, "nozzle")
    c.segment((cx + 0.1, 0.02, 0), (cx + 0.115, 0.0, 0), 0.06, "black")
    c.box(0, 0.05, 0.18, 0.62, -0.06, 0.06, "darkgrey")  # mounting rail
    return c


def b_aerospike(d=2.5):
    """Annular plug-nozzle aerospike: ring of thrust cells firing onto a truncated spike."""
    r = d / 2 * 0.92
    c = canvas_r(d / 2, 0, 2.9, LAUNCHER_VPM, pad=0.05)
    hp = 1.7
    plug = lambda Y: r * (0.32 + 0.6 * np.clip(Y / hp, 0, 1) ** 1.7)
    c.revolve(0, hp, plug, "copper")
    c.paint_where(_stripes(c, 0, 0, 72) & (c.Y < hp), "copper", "copper_dark")
    c.paint(c.Y < 2 * c.vox, "nozzle")  # base-bleed face
    c.revolve(hp, hp + 0.45, r, "steel", rin=r * 0.72)  # combustor ring
    for k in range(16):  # thrust cells
        ang = k * 2 * math.pi / 16
        x, z = math.cos(ang) * r * 0.97, math.sin(ang) * r * 0.97
        c.box(x - 0.09, x + 0.09, hp - 0.12, hp + 0.3, z - 0.09, z + 0.09, "steel_dark")
        c.box(x - 0.06, x + 0.06, hp - 0.14, hp - 0.1, z - 0.06, z + 0.06, "black")
    c.revolve(hp + 0.45, hp + 0.55, r * 1.02, "darkgrey")  # thrust structure
    for sx in (-1, 1):  # turbopumps above the plate
        _pump(c, sx * r * 0.45, hp + 0.55, 0, 0.2, 0.45, "silver")
    c.revolve(2.8, 2.9, r * 0.85, "darkgrey")
    for a in range(6):
        ang = a * math.pi / 3
        c.segment((math.cos(ang) * r * 0.9, hp + 0.55, math.sin(ang) * r * 0.9),
                  (math.cos(ang) * r * 0.8, 2.85, math.sin(ang) * r * 0.8), 0.045, "grey")
    return c


def b_ntr():
    """Nuclear thermal rocket: big regen nozzle, reactor vessel, radiation shield, pumps."""
    r_e, n_len, r_t = 1.12, 3.3, 0.15
    c = canvas_r(1.15, 0, 5.9, LAUNCHER_VPM, pad=0.08)
    f = _bell_at(c, 0, 0, 0, n_len, r_e, r_t, "darkgrey", power=0.5)
    c.paint_where((c.Y >= n_len * 0.45) & (c.R() >= f(c.Y) - 0.25), "darkgrey", "steel_dark")
    c.paint_where(_stripes(c, 0, 0, 96) & (c.Y >= n_len * 0.45), "steel_dark", "grey")
    yr0, yr1 = n_len + 0.25, n_len + 1.75
    c.revolve(n_len, yr0, lambda Y: r_t + (0.55 - r_t) * np.clip((Y - n_len) / 0.25, 0, 1), "silver")
    c.revolve(yr0, yr1, 0.55, "silver")  # reactor pressure vessel
    band = (c.Y > yr0 + 0.55) & (c.Y < yr0 + 0.85)
    chev = (np.floor(((c.theta() + math.pi) * 0.55 + c.Y) / 0.22) % 2) == 0
    c.paint(band & chev, "yellow")
    c.paint(band & ~chev, "black")
    ring_bands(c, [yr0 + 0.1, yr1 - 0.18], 0.08, "steel_dark")
    c.revolve(yr1, yr1 + 0.32, 0.62, "darkgrey")  # radiation shield
    c.revolve(yr1 + 0.32, yr1 + 0.4, 0.5, "grey")
    for sx in (-1, 1):  # hydrogen turbopumps
        _pump(c, sx * 0.4, yr1 + 0.4, 0.0, 0.16, 0.45, "silver")
        c.segment((sx * 0.4, yr1 + 0.5, 0.15), (sx * 0.62, n_len + 0.3, 0.3), 0.05, "steel_dark")  # feed to nozzle manifold
    c.revolve(n_len * 0.42, n_len * 0.42 + 0.1, lambda Y: f(Y) + 0.06, "steel_dark", rin=lambda Y: f(Y) - 0.02)
    c.revolve(5.8, 5.9, 0.75, "darkgrey")
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        c.segment((math.cos(ang) * 0.55, yr1 + 0.35, math.sin(ang) * 0.55),
                  (math.cos(ang) * 0.7, 5.85, math.sin(ang) * 0.7), 0.045, "grey")
    return c


# ---- tanks
def b_tank_lh2(d=2.5, length=8.0):
    r = d / 2
    c = canvas_r(r, 0, length, LAUNCHER_VPM, pad=0.12)
    c.revolve(0, length, r, "silver")
    h = c.hash(17)
    c.paint_where(h > 200, "silver", "steel")
    for y in np.arange(0.6, length - 0.3, 0.6):  # MLI blanket seams
        c.paint((c.Y >= y) & (c.Y < y + c.vox), "steel_dark")
    ring_bands(c, [length / 3 - 0.1, 2 * length / 3 - 0.1], 0.2, "gold")
    ring_bands(c, [0, length - 0.14], 0.14, "darkgrey")
    c.box(r - c.vox, r + 0.10, 0.14, length - 0.14, -0.09, 0.09, "grey")
    c.box(r + 0.04, r + 0.10, 0.14, length - 0.14, -0.05, 0.05, "darkgrey")
    return c


def b_tank_toroid(R=0.45, r=0.17):
    out = R + r
    h = 2 * r + 0.08
    c = Canvas(-out - 0.04, out + 0.04, 0, h, -out - 0.04, out + 0.04, CRAFT_VPM)
    yc = h / 2
    d = np.sqrt((c.R() - R) ** 2 + (c.Y - yc) ** 2)
    c.put(d <= r, "silver")
    c.paint(np.abs(c.Y - yc) < c.vox * 1.1, "steel_dark")  # girth weld
    for y in (0.0, h - 0.03):  # stack interface rings
        c.revolve(y, y + 0.03, out, "darkgrey", rin=out - 0.06)
        c.revolve(y, y + 0.03, R - r * 0.7, "darkgrey", rin=R - r * 0.7 - 0.05)
    for a in range(8):
        ang = a * math.pi / 4 + math.pi / 8
        x, z = math.cos(ang) * (out - 0.03), math.sin(ang) * (out - 0.03)
        c.segment((x, 0.02, z), (x, h - 0.02, z), 0.016, "grey")
        xi, zi = math.cos(ang) * (R - r * 0.7 - 0.02), math.sin(ang) * (R - r * 0.7 - 0.02)
        c.segment((xi, 0.02, zi), (xi, h - 0.02, zi), 0.014, "grey")
    c.cyl("y", R, 0, h - 0.05, h, 0.025, "gold")  # fill / drain valve
    return c


# ---- structure
def b_clamp_band(d=1.25, h=0.34):
    r = d / 2
    c = canvas_r(r, 0, h, LAUNCHER_VPM if d > 2 else 40, pad=0.08)
    c.revolve(0, h * 0.45, lambda Y: r * (1.0 - 0.08 * np.clip(Y / (h * 0.45), 0, 1)), "grey", rin=r - 0.1)
    c.revolve(h * 0.55, h, r * 0.92, "silver", rin=r * 0.92 - 0.08)
    c.revolve(h * 0.38, h * 0.62, r * 0.96, "steel_dark", rin=r * 0.8)  # V-band
    n = 12 if d < 2 else 20
    for k in range(n):  # clamp shoes
        ang = k * 2 * math.pi / n
        x, z = math.cos(ang) * r * 0.96, math.sin(ang) * r * 0.96
        c.box(x - 0.04, x + 0.04, h * 0.35, h * 0.65, z - 0.04, z + 0.04, "silver")
    for s in (-1, 1):  # bolt cutters
        c.box(s * r * 0.96 - 0.06, s * r * 0.96 + 0.06, h * 0.3, h * 0.7, -0.08, 0.08, "red")
    for k in range(4):  # separation springs
        ang = k * math.pi / 2 + math.pi / 4
        c.cyl("y", math.cos(ang) * r * 0.82, math.sin(ang) * r * 0.82, h * 0.45, h * 0.85, 0.03 + d * 0.01, "yellow")
    return c


def b_adapter_rev(d_top=2.5, d_bot=1.25, h=1.2):
    rt, rb = d_top / 2, d_bot / 2
    c = canvas_r(rt, 0, h, LAUNCHER_VPM, pad=0.05)
    f = lambda Y: rb + (rt - rb) * np.clip(Y / h, 0, 1) ** 1.3
    c.revolve(0, h, f, "white", rin=lambda Y: f(Y) - 0.12)
    ring_bands(c, [0, h - 0.1], 0.1, "grey")
    c.paint((c.Y > h * 0.45) & (c.Y < h * 0.55), "blue")
    return c


def b_truss_xs(length=2.0, w=0.44):
    c = Canvas(-0.32, 0.32, 0, length, -0.32, 0.32, LAUNCHER_VPM)
    for y in (0, length - 0.08):
        c.cyl("y", 0, 0, y, y + 0.08, 0.31, "darkgrey", rin=0.12)
    s = w / 2
    corners = [(s, s), (-s, s), (-s, -s), (s, -s)]
    for x, z in corners:
        c.box(x - 0.04, x + 0.04, 0.08, length - 0.08, z - 0.04, z + 0.04, "steel")
    bay = (length - 0.16) / 4
    for i in range(4):
        y0, y1 = 0.08 + i * bay, 0.08 + (i + 1) * bay
        for k in range(4):
            (x0, z0), (x1, z1) = corners[k], corners[(k + 1) % 4]
            if i % 2:
                c.segment((x0, y0, z0), (x1, y1, z1), 0.035, "grey")
            else:
                c.segment((x1, y0, z1), (x0, y1, z0), 0.035, "grey")
        if i < 3:  # bay frame
            c.box(-s, s, y1 - 0.03, y1 + 0.03, -s, s, "steel_dark")
    # hollow out the bay floors so it reads as a lattice
    m = (np.abs(c.X) < s - 0.05) & (np.abs(c.Z) < s - 0.05) & (c.Y > 0.08) & (c.Y < length - 0.08)
    c.a[np.broadcast_to(m, c.a.shape)] = 0
    return c


def b_truss_m(d=2.5, h=2.0):
    r = d / 2
    c = canvas_r(r, 0, h, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, 0.14, r, "darkgrey", rin=r - 0.16)
    c.revolve(h - 0.14, h, r, "darkgrey", rin=r - 0.16)
    n = 8
    rr = r - 0.08
    for k in range(n):
        a0, a1 = k * 2 * math.pi / n, (k + 1) * 2 * math.pi / n
        p0 = (math.cos(a0) * rr, 0.12, math.sin(a0) * rr)
        p1 = (math.cos(a1) * rr, h - 0.12, math.sin(a1) * rr)
        p2 = (math.cos(a1) * rr, 0.12, math.sin(a1) * rr)
        p3 = (math.cos(a0) * rr, h - 0.12, math.sin(a0) * rr)
        c.segment(p0, p1, 0.06, "grey")
        c.segment(p2, p3, 0.06, "grey")
        c.box(p0[0] - 0.07, p0[0] + 0.07, 0.1, 0.24, p0[2] - 0.07, p0[2] + 0.07, "steel_dark")
        c.box(p3[0] - 0.07, p3[0] + 0.07, h - 0.24, h - 0.1, p3[2] - 0.07, p3[2] + 0.07, "steel_dark")
    return c


def b_strut_radial(length=1.0):
    c = Canvas(0, length, 0, 0.36, -0.16, 0.16, CRAFT_VPM)
    c.box(0.03, length - 0.03, 0.03, 0.07, -0.1, 0.1, "steel")
    c.box(0.03, length - 0.03, 0.29, 0.33, -0.1, 0.1, "steel")
    c.box(0.03, length - 0.03, 0.07, 0.29, -0.02, 0.02, "steel_dark")
    for x in (0.0, length - 0.04):
        c.box(x, x + 0.04, 0.0, 0.36, -0.15, 0.15, "darkgrey")
    for x in np.arange(0.15, length - 0.1, 0.2):  # lightening stiffeners
        c.box(x, x + 0.02, 0.07, 0.29, -0.1, 0.1, "grey")
    return c


def b_docking_port(d=1.25):
    R = d / 2
    vpm = CRAFT_VPM if d < 1.0 else 40
    h = 0.42 * d
    c = canvas_r(R, 0, h, vpm, pad=0.04)
    c.revolve(0, h * 0.28, R, "grey", rin=R * 0.6)  # base flange / structure
    ring_bands(c, [h * 0.22], h * 0.06, "darkgrey")
    c.revolve(h * 0.28, h * 0.72, R * 0.78, "silver", rin=R * 0.62)  # tunnel
    c.revolve(h * 0.72, h * 0.84, R * 0.86, "white", rin=R * 0.62)  # soft-capture ring
    for k in range(3):  # guide petals
        ang = k * 2 * math.pi / 3
        t = c.theta()
        da = np.angle(np.exp(1j * (t - ang)))
        y = c.Y
        petal = (y > h * 0.84) & (y < h) & (np.abs(da) < 0.42 * (1 - (y - h * 0.84) / (h * 0.16)) + 0.08) \
            & (c.R() < R * 0.86) & (c.R() > R * 0.86 - 0.05 - (y - h * 0.84) * 0.6)
        c.put(petal, "white")
    for k in range(6):  # latches
        ang = k * math.pi / 3 + math.pi / 6
        x, z = math.cos(ang) * R * 0.82, math.sin(ang) * R * 0.82
        c.box(x - 0.03, x + 0.03, h * 0.72, h * 0.88, z - 0.03, z + 0.03, "yellow")
    c.paint((c.R() < R * 0.65) & (c.Y > h * 0.2), "darkgrey")  # tunnel inner wall
    if d < 1.0:  # probe
        c.cyl("y", 0, 0, h * 0.25, h, 0.03, "silver")
        c.sphere(0, h, 0, 0.04, "darkgrey")
        for k in range(3):
            ang = k * 2 * math.pi / 3
            c.segment((math.cos(ang) * R * 0.6, h * 0.3, math.sin(ang) * R * 0.6), (0, h * 0.75, 0), 0.015, "grey")
    return c


# ---- aero
def b_fin_large(span=1.7, root=3.0, tip=1.1, t=0.14):
    c = Canvas(0, span, 0, root, -t, t, LAUNCHER_VPM)
    top = root - (root - tip) * (c.X / span) ** 0.9
    m = (c.Y <= top) & (np.abs(c.Z) <= t * (1 - 0.55 * c.X / span))
    c.put(m, "white")
    c.paint(c.X < 0.15, "darkgrey")
    c.paint((c.Y > top - 0.15), "black")
    c.paint((c.X > span - 0.25), "black")
    c.paint((np.abs(c.Y - root * 0.35) < 0.07) & (c.X > 0.15), "black")
    return c


def b_fin_swept(span=1.3, root=2.2, tip=0.6, sweep=1.1, t=0.1):
    c = Canvas(0, span, 0, root + 0.05, -t, t, LAUNCHER_VPM)
    x = c.X / span
    bot = sweep * x
    top = root + (sweep + tip - root) * x
    m = (c.Y >= bot) & (c.Y <= top) & (np.abs(c.Z) <= t * (1 - 0.5 * x))
    c.put(m, "carbon")
    hh = c.hash(19)
    c.paint_where(hh > 215, "carbon", "darkgrey")
    c.paint(c.Y > top - 0.1, "silver")  # leading edge
    c.paint(c.X > span - 0.12, "red")
    c.paint(c.X < 0.1, "darkgrey")
    return c


# ---- crew & command
def _windows(c, y0, y1, angles, half_w, color="glass"):
    for ang in angles:
        da = np.angle(np.exp(1j * (c.theta() - ang)))
        c.paint((c.Y > y0) & (c.Y < y1) & (np.abs(da) * c.R() < half_w), color)


def b_capsule_1():
    """One-seat capsule (Mercury class): retro pack, shingled cone, neck and canister."""
    c = canvas_r(0.66, 0, 2.05, LAUNCHER_VPM, pad=0.05)
    c.cyl("y", 0, 0, 0, 0.14, 0.32, "silver")  # retro pack
    for k in range(3):
        ang = k * 2 * math.pi / 3
        c.box(math.cos(ang) * 0.16 - 0.05, math.cos(ang) * 0.16 + 0.05, 0, 0.05,
              math.sin(ang) * 0.16 - 0.05, math.sin(ang) * 0.16 + 0.05, "nozzle")
    c.revolve(0.14, 0.24, 0.63, "black")  # heat shield
    f = lambda Y: 0.6 - 0.3 * np.clip((Y - 0.24) / 1.05, 0, 1)
    c.revolve(0.24, 1.29, f, "darkgrey")
    c.paint_where(_stripes(c, 0, 0, 40) & (c.Y > 0.26) & (c.Y < 1.29), "darkgrey", "black")
    _windows(c, 0.7, 0.95, [0.0], 0.13)
    c.revolve(1.29, 1.7, 0.3, "darkgrey")
    ring_bands(c, [1.29], 0.05, "grey")
    c.revolve(1.7, 1.95, 0.22, "black")  # antenna / parachute canister
    c.revolve(1.95, 2.05, 0.15, "silver")
    return c


def b_capsule_2():
    """Two-seat capsule (Gemini class): broad cone, twin windows, RCS section, docking nose."""
    c = canvas_r(1.18, 0, 2.95, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, 0.18, 1.17, "black")
    f = lambda Y: 1.14 - 0.6 * np.clip((Y - 0.18) / 1.75, 0, 1)
    c.revolve(0.18, 1.93, f, "carbon")
    c.paint_where(_stripes(c, 0, 0, 72) & (c.Y > 0.2) & (c.Y < 1.93), "carbon", "black")
    _windows(c, 1.25, 1.6, [-0.32, 0.32], 0.17)
    c.revolve(1.93, 2.5, 0.5, "carbon")
    ring_bands(c, [1.93, 2.45], 0.05, "grey")
    for k in range(8):  # RCS ports
        ang = k * math.pi / 4
        x, z = math.cos(ang) * 0.5, math.sin(ang) * 0.5
        c.box(x - 0.05, x + 0.05, 2.12, 2.24, z - 0.05, z + 0.05, "darkgrey")
    c.revolve(2.5, 2.95, lambda Y: 0.42 - 0.22 * np.clip((Y - 2.5) / 0.45, 0, 1), "offwhite")
    c.paint(c.Y > 2.88, "silver")
    return c


def b_capsule_4():
    """Four-seat capsule (Crew Dragon class): white body, side abort engine pods, hinged nose cap."""
    R = 1.85
    c = canvas_r(R, 0, 3.15, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, 0.26, lambda Y: R - 0.05 * np.clip((0.26 - Y) / 0.26, 0, 1) * 2, "black")
    f = lambda Y: R - (R - 1.08) * np.clip((Y - 0.26) / 2.3, 0, 1) ** 1.1
    c.revolve(0.26, 2.56, f, "white")
    hh = c.hash(23)
    c.paint_where(hh > 236, "white", "offwhite")
    cap = lambda Y: 1.08 * np.sqrt(np.clip(1 - ((Y - 2.56) / 0.55) ** 2, 0, 1)) ** 0.8
    c.revolve(2.56, 3.11, cap, "white")
    ring_bands(c, [2.56], 0.05, "grey")
    c.box(-0.2, 0.2, 2.6, 3.0, -1.12, -0.9, "darkgrey")  # nose cap hinge
    _windows(c, 1.35, 1.75, [0.0, math.pi / 2, math.pi, 3 * math.pi / 2], 0.2)
    for k in range(4):  # side abort engine pods (pairs)
        ang = k * math.pi / 2 + math.pi / 4
        da = np.angle(np.exp(1j * (c.theta() - ang)))
        pod = (c.Y > 0.45) & (c.Y < 1.15) & (np.abs(da) * c.R() < 0.38)
        c.paint(pod, "darkgrey")
        c.paint(pod & (np.abs(np.abs(da) * c.R() - 0.17) < 0.09) & (c.Y < 0.75), "black")
    c.revolve(0.26, 0.34, R + 0.02, "grey")  # trunk interface
    return c


def b_crew_cabin(d=2.5, h=2.6):
    r = d / 2
    c = canvas_r(r, 0, h, LAUNCHER_VPM, pad=0.08)
    c.revolve(0, h, r, "white")
    ring_bands(c, [0, h - 0.14], 0.14, "darkgrey")
    ring_bands(c, [h * 0.5 - 0.5, h * 0.5 + 0.45], 0.05, "offwhite")
    _windows(c, h * 0.5 - 0.22, h * 0.5 + 0.22, [k * math.pi / 3 for k in range(6)], 0.2)
    for k in range(6):  # yellow EVA handrails
        ang = k * math.pi / 3 + math.pi / 6
        x, z = math.cos(ang) * (r + 0.04), math.sin(ang) * (r + 0.04)
        c.segment((x, 0.4, z), (x, h - 0.4, z), 0.04, "yellow")
    c.box(r - 0.05, r + 0.04, h * 0.2, h * 0.32, -0.35, 0.35, "grey")  # utility panel
    return c


def b_hab_inflatable(d_ring=2.36, d_body=3.2, h=4.0):
    rr, rb = d_ring / 2, d_body / 2
    c = canvas_r(rb, 0, h, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, 0.3, rr, "silver")
    c.revolve(h - 0.3, h, rr, "silver")
    yc, a = h / 2, h / 2 - 0.2
    prof = lambda Y: rr * 0.9 + (rb - rr * 0.9) * np.sqrt(np.clip(1 - ((Y - yc) / a) ** 2, 0, 1))
    c.revolve(0.2, h - 0.2, prof, "offwhite")
    hh = c.hash(29)
    c.paint_where(hh > 200, "offwhite", "white")
    for y in np.arange(0.55, h - 0.4, 0.45):  # restraint straps
        c.paint_where((c.Y >= y) & (c.Y < y + c.vox), "offwhite", "grey")
        c.paint_where((c.Y >= y) & (c.Y < y + c.vox), "white", "grey")
    c.paint_where(_stripes(c, 0, 0, 24) & (np.abs(((c.theta() + math.pi) / (2 * math.pi) * 24) % 1 - 0.5) < 0.06),
                  "offwhite", "grey")
    ring_bands(c, [0.22, h - 0.3], 0.08, "darkgrey")
    return c


def b_cupola(d_base=2.5, h=1.5):
    rb = d_base / 2
    c = canvas_r(rb + 0.1, 0, h, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, 0.3, rb, "silver")
    ring_bands(c, [0.0], 0.06, "darkgrey")
    n = 6
    t = c.theta()
    a = np.mod(t + math.pi / n, 2 * math.pi / n) - math.pi / n
    apo = lambda Y: (rb + 0.1) - (rb + 0.1 - 0.62) * np.clip((Y - 0.3) / 0.95, 0, 1)
    perp = c.R() * np.cos(a)
    tang = c.R() * np.sin(a)
    body = (c.Y >= 0.3) & (c.Y <= 1.25) & (perp <= apo(c.Y))
    c.put(body, "offwhite")
    win = body & (c.Y > 0.42) & (c.Y < 1.14) & (np.abs(tang) < apo(c.Y) * math.tan(math.pi / n) * 0.7)
    c.paint(win, "glass")
    c.paint(body & (np.abs(a) < 0.02 + c.vox / np.maximum(c.R(), 0.1)), "grey")  # frames between faces
    c.revolve(1.25, h, 0.62, "offwhite")
    c.paint((c.Y > h - c.vox * 1.5) & (c.R() < 0.42), "glass")  # top window
    for k in range(n):  # shutter hinges
        ang = k * 2 * math.pi / n
        x, z = math.cos(ang) * (rb + 0.06), math.sin(ang) * (rb + 0.06)
        c.box(x - 0.08, x + 0.08, 0.3, 0.4, z - 0.08, z + 0.08, "grey")
    return c


def b_les_tower():
    c = canvas_r(0.66, 0, 7.1, LAUNCHER_VPM, pad=0.05)
    c.revolve(0, 0.12, 0.62, "darkgrey", rin=0.45)
    legs = [(math.cos(a) * 0.55, math.sin(a) * 0.55) for a in (math.pi / 4, 3 * math.pi / 4, 5 * math.pi / 4, 7 * math.pi / 4)]
    tops = [(x * 0.5, z * 0.5) for x, z in legs]
    for i, ((x0, z0), (x1, z1)) in enumerate(zip(legs, tops)):
        c.segment((x0, 0.1, z0), (x1, 2.3, z1), 0.06, "steel_dark")
        (x2, z2), (x3, z3) = legs[(i + 1) % 4], tops[(i + 1) % 4]
        c.segment((x0, 0.1, z0), (x3, 2.3, z3), 0.04, "grey")
        c.segment((x2, 0.1, z2), (x1, 2.3, z1), 0.04, "grey")
    c.revolve(2.3, 2.7, 0.34, "darkgrey")
    for k in range(4):  # canted abort nozzles
        ang = k * math.pi / 2
        for i in range(5):
            tt = i / 4
            p = (math.cos(ang) * (0.18 + 0.16 * tt), 2.55 - 0.22 * tt, math.sin(ang) * (0.18 + 0.16 * tt))
            c.segment(p, (p[0], p[1] - 0.02, p[2]), 0.06 + 0.06 * tt, "nozzle")
    c.revolve(2.7, 5.6, 0.33, "white")
    ring_bands(c, [3.2, 4.6], 0.06, "grey")
    c.revolve(5.6, 6.3, 0.22, "white")
    ring_bands(c, [5.9], 0.12, "red")
    f = ogive(0.22, 0.75)
    c.revolve(6.3, 7.05, lambda Y: f(Y - 6.3), "red")
    c.revolve(7.0, 7.1, 0.05, "silver")
    return c


def b_parachute_radial(r=0.3, h=0.85, drogue=False):
    cx = r + 0.05
    c = Canvas(0, 2 * r + 0.1, 0, h + 0.08, -r - 0.04, r + 0.04, CRAFT_VPM)
    c.box(0, 0.06, h * 0.1, h * 0.8, -r * 0.5, r * 0.5, "grey")  # mounting bracket
    c.cyl("y", cx, 0, 0, h, r, "white")
    ring_bands(c, [0.0, h * 0.45], 0.03, "darkgrey")
    cap = lambda Y: r * np.sqrt(np.clip(1 - ((Y - h) / 0.08) ** 2, 0, 1))
    c.revolve(h, h + 0.08, cap, "orange", cx=cx)
    c.paint((c.Y > h - 0.06) & (c.Y < h), "orange")
    if not drogue:  # retention straps
        for ang in (0.6, -0.6):
            da = np.angle(np.exp(1j * (c.theta(cx, 0) - ang)))
            c.paint((np.abs(da) * c.R(cx, 0) < 0.025) & (c.Y > h * 0.1), "orange")
    c.box(cx - 0.04, cx + 0.04, h - 0.02, h + 0.08, -0.04, 0.04, "yellow")  # riser attach / mortar cap
    return c


def b_landing_leg_lander():
    c = Canvas(-0.02, 1.52, 0, 1.95, -0.36, 0.36, CRAFT_VPM)
    c.box(0, 0.12, 1.5, 1.92, -0.14, 0.14, "darkgrey")  # upper mount
    c.box(0, 0.08, 0.5, 0.72, -0.3, 0.3, "darkgrey")  # lower mount
    foot = (1.18, 0.16, 0.0)
    c.segment((0.08, 1.72, 0), (0.7, 0.86, 0), 0.085, "gold")  # primary strut (upper)
    c.segment((0.7, 0.86, 0), foot, 0.06, "silver")  # piston (lower)
    for s in (-1, 1):  # secondary struts
        c.segment((0.06, 0.62, s * 0.26), (0.62, 0.95, 0), 0.038, "gold")
    c.segment((0.08, 1.2, 0), (0.62, 0.95, 0), 0.03, "steel_dark")  # deployment truss
    c.revolve(0.06, 0.16, lambda Y: 0.24 + 0.08 * np.clip((Y - 0.06) / 0.1, 0, 1), "gold", cx=foot[0])
    c.revolve(0.0, 0.06, lambda Y: 0.16 + 0.08 * np.clip(Y / 0.06, 0, 1), "gold", cx=foot[0])
    c.paint_where((c.Y > 0.12) & (c.R(foot[0], 0) < 0.26), "gold", "gold_dark")
    c.sphere(foot[0], 0.2, 0, 0.06, "silver")  # ball joint
    hh = c.hash(31)
    c.paint_where(hh > 190, "gold", "gold_dark")
    return c


def b_rover_wheel(r=0.25, w=0.4):
    c = Canvas(0, 0.72, 0, 0.78, -0.3, 0.3, CRAFT_VPM)
    yc, x0, x1 = 0.27, 0.28, 0.28 + w
    xm = (x0 + x1) / 2
    c.cyl("x", yc, 0, x0, x1, r, "silver", rin=r - 0.03)
    tt = np.arctan2(c.Z, c.Y - yc)
    chev = (np.mod(tt * 14 / (2 * math.pi) + np.abs(c.X - xm) * 2.2, 1) < 0.16)
    Rw = np.sqrt((c.Y - yc) ** 2 + c.Z ** 2)
    c.put(chev & (Rw > r - 0.01) & (Rw <= r + 0.022) & (c.X >= x0) & (c.X <= x1), "steel_dark")
    c.cyl("x", yc, 0, x1 - 0.03, x1, r - 0.02, "steel_dark", rin=r - 0.05)  # outer lip
    for k in range(6):  # curved spokes (flexures)
        ang = k * math.pi / 3
        p0 = (x1 - 0.06, yc + math.cos(ang) * 0.06, math.sin(ang) * 0.06)
        p1 = (x1 - 0.04, yc + math.cos(ang + 0.5) * (r - 0.03), math.sin(ang + 0.5) * (r - 0.03))
        c.segment(p0, p1, 0.016, "steel_dark")
    c.cyl("x", yc, 0, x0 + 0.05, x1 - 0.02, 0.07, "darkgrey")  # hub motor
    c.cyl("x", yc, 0, x1 - 0.04, x1 + 0.02, 0.05, "silver")
    c.segment((x0 + 0.05, yc, 0), (0.06, 0.66, 0), 0.04, "white")  # rocker arm
    c.box(0, 0.08, 0.56, 0.76, -0.1, 0.1, "grey")
    return c


# ---- power
def b_fuel_cell():
    c = Canvas(0, 0.46, 0, 0.42, -0.5, 0.5, CRAFT_VPM)
    c.box(0.02, 0.38, 0, 0.34, -0.46, 0.46, "offwhite")
    c.paint((c.X > 0.36) & ((np.floor(c.Z / 0.04) % 2) == 0) & (c.Y > 0.04) & (c.Y < 0.3), "grey")  # cell stack
    for z in (-0.46, 0.44):
        c.box(0.02, 0.38, 0, 0.34, z, z + 0.02, "darkgrey")  # end plates
    for x, col in ((0.1, "blue"), (0.2, "red"), (0.3, "silver")):  # O2, H2, water manifolds
        c.cyl("z", x, 0.36, -0.44, 0.44, 0.022, col)
    for z in np.arange(-0.38, 0.4, 0.08):  # radiator fins (front)
        c.box(0.38, 0.45, 0.06, 0.28, z, z + 0.015, "silver")
    c.box(0.15, 0.3, 0.34, 0.42, -0.1, 0.1, "black")  # controller
    c.box(0, 0.03, 0.02, 0.32, -0.4, 0.4, "darkgrey")
    return c


def b_solar_ultraflex(rad=1.05, gores=10):
    cxp = rad + 0.4
    c = Canvas(-0.05, cxp + rad + 0.05, -0.06, 0.08, -rad - 0.05, rad + 0.05, CRAFT_VPM)
    c.segment((0.0, 0.0, 0), (cxp - 0.1, 0.0, 0), 0.035, "silver")  # yoke
    c.box(-0.05, 0.1, -0.06, 0.06, -0.06, 0.06, "darkgrey")  # drive
    t = np.arctan2(c.Z, c.X - cxp)
    Rc = np.sqrt((c.X - cxp) ** 2 + c.Z ** 2)
    a = np.mod(t + math.pi / gores, 2 * math.pi / gores) - math.pi / gores
    inside = Rc * np.cos(a) <= rad * math.cos(math.pi / gores)
    c.put(inside & (c.Y >= -0.02) & (c.Y < 0.0), "white")
    cells = inside & (c.Y >= 0.0) & (c.Y < 0.02) & (Rc > 0.1)
    c.put(cells, "cell")
    c.paint(cells & (np.mod(Rc, 0.12) < 0.02), "cell_dark")
    c.paint(cells & (np.abs(a) * Rc < 0.012), "cell_dark")
    ribs = inside & (np.abs(np.abs(a) - math.pi / gores) * Rc < 0.018) & (c.Y >= -0.02) & (c.Y < 0.035)
    c.put(ribs, "silver")
    c.cyl("y", cxp, 0, -0.04, 0.06, 0.1, "darkgrey")  # hub
    return c


def b_fission_reactor():
    c = Canvas(-1.08, 1.08, 0, 3.3, -1.08, 1.08, CRAFT_VPM)
    c.cyl("y", 0, 0, 0, 0.55, 0.22, "silver")  # reactor core
    band = (c.Y > 0.3) & (c.Y < 0.4)
    chev = (np.floor(((c.theta() + math.pi) * 0.22 + c.Y) / 0.05) % 2) == 0
    c.paint(band & chev, "yellow")
    c.paint(band & ~chev, "black")
    c.revolve(0.55, 0.9, lambda Y: 0.25 + 0.17 * np.clip((Y - 0.55) / 0.35, 0, 1), "darkgrey")  # shadow shield
    c.cyl("y", 0, 0, 0.9, 2.0, 0.07, "grey")  # boom
    for k in range(4):  # heat pipes
        ang = k * math.pi / 2 + math.pi / 4
        c.segment((math.cos(ang) * 0.15, 0.6, math.sin(ang) * 0.15), (math.cos(ang) * 0.22, 2.0, math.sin(ang) * 0.22),
                  0.025, "copper")
    c.cyl("y", 0, 0, 1.95, 2.15, 0.26, "silver")  # converter hub
    for k in range(8):  # Stirling converters
        ang = k * math.pi / 4
        c.cyl("y", math.cos(ang) * 0.34, math.sin(ang) * 0.34, 1.97, 2.13, 0.07, "gold")
    f = lambda Y: 0.3 + 0.72 * np.clip((Y - 2.15) / 1.1, 0, 1)
    v = c.vox
    c.revolve(2.15, 3.25, f, "white", rin=lambda Y: np.minimum(f(Y - v), f(Y + v)) - 0.05)  # conical radiator
    c.paint_where(_stripes(c, 0, 0, 32) & (np.abs(((c.theta() + math.pi) / (2 * math.pi) * 32) % 1 - 0.5) < 0.12),
                  "white", "grey")
    c.revolve(3.22, 3.28, 1.03, "darkgrey", rin=0.98)
    return c


# ---- comms
def b_antenna_helix(h=0.48, r=0.06):
    c = Canvas(-0.12, 0.12, 0, h + 0.05, -0.12, 0.12, CRAFT_VPM)
    c.box(-0.1, 0.1, 0, 0.06, -0.1, 0.1, "darkgrey")
    c.cyl("y", 0, 0, 0.06, 0.08, 0.11, "silver")  # ground plane
    c.cyl("y", 0, 0, 0.08, h, 0.018, "white")  # support mast
    turns = 1.25
    for k in range(4):
        pts = []
        for i in range(41):
            tt = i / 40
            ang = k * math.pi / 2 + tt * turns * 2 * math.pi
            pts.append((math.cos(ang) * r, 0.09 + tt * (h - 0.11), math.sin(ang) * r))
        for p0, p1 in zip(pts[:-1], pts[1:]):
            c.segment(p0, p1, 0.013, "gold")
    c.cyl("y", 0, 0, h - 0.02, h + 0.05, 0.07, "white")  # top cap
    return c


def b_optical_terminal():
    c = Canvas(-0.26, 0.26, 0, 0.82, -0.26, 0.26, CRAFT_VPM)
    c.box(-0.22, 0.22, 0, 0.14, -0.22, 0.22, "gold")  # electronics under MLI
    hh = c.hash(37)
    c.paint_where(hh > 160, "gold", "gold_dark")
    c.cyl("y", 0, 0, 0.14, 0.2, 0.16, "darkgrey")  # azimuth bearing
    for s in (-1, 1):  # elevation yoke
        c.box(-0.05, 0.05, 0.2, 0.5, s * 0.2 - 0.03, s * 0.2 + 0.03, "silver")
    c.cyl("z", 0.0, 0.44, -0.2, 0.2, 0.04, "darkgrey")  # elevation axle
    p0, p1 = np.array((-0.08, 0.3, 0)), np.array((0.12, 0.78, 0))
    c.segment(p0, p1, 0.14, "white")  # telescope tube
    d = (p1 - p0) / np.linalg.norm(p1 - p0)
    c.segment(p1 - d * 0.02, p1 + d * 0.02, 0.115, "black")  # sunshade opening
    c.segment(p1 - d * 0.06, p1 - d * 0.03, 0.11, "lens")
    return c


# ---- thermal
def b_radiator_deploy(panels=3, pw=1.0, ph=0.8):
    total = 0.12 + panels * (pw + 0.04)
    c = Canvas(0, total, 0, ph, -0.05, 0.05, CRAFT_VPM)
    c.box(0, 0.1, 0.1, ph - 0.1, -0.05, 0.05, "darkgrey")  # root hinge / pump
    for i in range(panels):
        x0 = 0.12 + i * (pw + 0.04)
        c.box(x0, x0 + pw, 0, ph, -0.014, 0.014, "white")
        c.paint((c.X >= x0) & (c.X <= x0 + pw) & (np.abs((((c.Y - 0.05) / 0.1) % 1) - 0.5) < 0.12), "grey")
        c.paint((c.X >= x0) & (c.X <= x0 + pw) & ((c.Y < 0.035) | (c.Y > ph - 0.035)), "silver")
        for y in (0.15, ph - 0.15):  # hinges
            c.box(x0 - 0.05, x0 + 0.02, y - 0.05, y + 0.05, -0.03, 0.03, "darkgrey")
    c.segment((0.08, ph * 0.5, 0.03), (0.2, ph * 0.5, 0.03), 0.012, "silver")  # flex hose
    return c


def b_heat_shield(d=2.5, h=0.34):
    R = d / 2
    c = canvas_r(R, 0, h, LAUNCHER_VPM, pad=0.05)
    sag = h * 0.6
    low = lambda Rr: sag * (Rr / R) ** 2
    m = (c.R() <= R) & (c.Y >= low(c.R())) & (c.Y <= h * 0.72)
    c.put(m, "copper_dark")
    hh = c.hash(41)
    c.paint_where(hh > 205, "copper_dark", "black")
    tile = 0.45 if d > 3 else 0.36
    seams = (np.abs(np.mod(c.X, tile)) < c.vox) | (np.abs(np.mod(c.Z, tile)) < c.vox)
    c.paint_where(seams, "copper_dark", "black")
    c.revolve(h * 0.62, h, R, "carbon", rin=R - 0.2)  # carrier structure ring
    c.revolve(h * 0.62, h * 0.78, R - 0.2, "carbon")
    for k in range(24):
        ang = k * 2 * math.pi / 24
        x, z = math.cos(ang) * (R - 0.1), math.sin(ang) * (R - 0.1)
        c.box(x - 0.04, x + 0.04, h - 0.04, h, z - 0.04, z + 0.04, "silver")
    return c


# ---- control
def b_reaction_wheel_s():
    c = Canvas(-0.07, 0.07, 0, 0.06, -0.07, 0.07, CRAFT_VPM)
    c.box(-0.062, 0.062, 0, 0.016, -0.062, 0.062, "grey")  # flange
    c.cyl("y", 0, 0, 0.016, 0.05, 0.055, "darkgrey")
    c.cyl("y", 0, 0, 0.05, 0.06, 0.04, "silver")
    c.box(0.04, 0.07, 0.016, 0.04, -0.015, 0.015, "gold")  # connector
    return c


def b_reaction_wheels_l():
    c = Canvas(-0.38, 0.38, 0, 0.46, -0.38, 0.38, CRAFT_VPM)
    c.box(-0.36, 0.36, 0, 0.04, -0.36, 0.36, "grey")
    c.box(-0.1, 0.1, 0.04, 0.22, -0.1, 0.1, "gold")  # wheel drive electronics
    for (x, z, ax) in ((0.2, 0.2, "x"), (-0.2, -0.2, "x"), (0.2, -0.2, "z"), (-0.2, 0.2, "z")):
        yc = 0.24
        if ax == "x":
            c.cyl("x", yc, z, x - 0.07, x + 0.07, 0.17, "darkgrey")
            c.cyl("x", yc, z, x + 0.07, x + 0.09, 0.1, "silver")
        else:
            c.cyl("z", x, yc, z - 0.07, z + 0.07, 0.17, "darkgrey")
            c.cyl("z", x, yc, z + 0.07, z + 0.09, 0.1, "silver")
        c.box(x - 0.08, x + 0.08, 0.04, 0.1, z - 0.08, z + 0.08, "steel_dark")  # bracket
    return c


def b_cmg():
    c = Canvas(-0.58, 0.58, 0, 1.0, -0.5, 0.5, CRAFT_VPM)
    c.box(-0.56, 0.56, 0, 0.06, -0.48, 0.48, "grey")
    yc = 0.52
    for s in (-1, 1):  # outer gimbal posts and torquer motors
        c.box(s * 0.5 - 0.04, s * 0.5 + 0.04, 0.06, yc + 0.08, -0.08, 0.08, "silver")
        x0, x1 = sorted((s * 0.42, s * 0.56))
        c.cyl("x", yc, 0, x0, x1, 0.08, "darkgrey")
    c.cyl("z", 0, yc, -0.04, 0.04, 0.44, "steel_dark", rin=0.39)  # outer gimbal ring (XY plane)
    c.cyl("x", yc, 0, -0.035, 0.035, 0.37, "darkgrey", rin=0.32)  # inner gimbal ring (YZ plane)
    m = c.sphere(0, yc, 0, 0.29, "silver")  # rotor housing
    c.paint(m & (np.abs(c.Y - yc) < 0.02), "black")
    for s in (-1, 1):  # spin motor caps
        z0, z1 = sorted((s * 0.26, s * 0.34))
        c.cyl("z", 0, yc, z0, z1, 0.08, "gold")
    return c


def _bell_axis(c, axis, o, sign, length, r0, r1, color, inner="black"):
    """Small bell nozzle along +/- X or Z from point o (spacecraft RCS)."""
    if axis == "x":
        A, R = (c.X - o[0]) * sign, np.sqrt((c.Y - o[1]) ** 2 + (c.Z - o[2]) ** 2)
    elif axis == "z":
        A, R = (c.Z - o[2]) * sign, np.sqrt((c.X - o[0]) ** 2 + (c.Y - o[1]) ** 2)
    else:
        A, R = (c.Y - o[1]) * sign, np.sqrt((c.X - o[0]) ** 2 + (c.Z - o[2]) ** 2)
    f = r0 + (r1 - r0) * np.clip(A / length, 0, 1) ** 0.7
    m = (A >= 0) & (A <= length) & (R <= f)
    c.put(m, color)
    c.put(m & (R <= f - 1.5 * c.vox) & (A > length * 0.3), inner)


def b_rcs_heavy():
    c = Canvas(0, 0.24, -0.14, 0.34, -0.2, 0.2, CRAFT_VPM)
    c.box(0, 0.16, 0, 0.2, -0.09, 0.09, "offwhite")
    c.box(0, 0.03, -0.02, 0.22, -0.11, 0.11, "darkgrey")
    o = (0.11, 0.1, 0.0)
    _bell_axis(c, "y", (o[0], 0.2, 0), 1, 0.12, 0.018, 0.045, "copper_dark")
    _bell_axis(c, "y", (o[0], 0.0, 0), -1, 0.12, 0.018, 0.045, "copper_dark")
    _bell_axis(c, "z", (o[0], o[1], 0.09), 1, 0.1, 0.018, 0.045, "copper_dark")
    _bell_axis(c, "z", (o[0], o[1], -0.09), -1, 0.1, 0.018, 0.045, "copper_dark")
    c.box(0.04, 0.1, 0.06, 0.14, 0.09, 0.1, "gold")
    return c


def b_rcs_biprop():
    c = Canvas(0, 0.3, -0.18, 0.5, -0.3, 0.3, CRAFT_VPM)
    prof = lambda Y: 0.2 - 0.06 * np.clip((Y - 0.0) / 0.32, 0, 1)
    m = (c.X >= 0) & (c.X <= prof(c.Y)) & (c.Y >= 0) & (c.Y <= 0.32) & (np.abs(c.Z) <= 0.17)
    c.put(m, "white")
    c.paint(m & (c.X > 0.12) & (np.abs(c.Z) < 0.1) & (c.Y > 0.1) & (c.Y < 0.22), "black")  # heat shield tile
    _bell_axis(c, "y", (0.1, 0.32, 0), 1, 0.15, 0.025, 0.06, "nozzle")
    _bell_axis(c, "y", (0.1, 0.0, 0), -1, 0.15, 0.025, 0.06, "nozzle")
    _bell_axis(c, "z", (0.1, 0.16, 0.17), 1, 0.12, 0.025, 0.06, "nozzle")
    _bell_axis(c, "z", (0.1, 0.16, -0.17), -1, 0.12, 0.025, 0.06, "nozzle")
    c.box(0, 0.03, 0.02, 0.3, -0.15, 0.15, "darkgrey")
    return c


# ---- instruments
def b_seismometer():
    c = Canvas(-0.4, 0.4, 0, 0.5, -0.4, 0.4, CRAFT_VPM)
    yc = 0.08
    c.sphere(0, yc, 0, 0.34, "gold", rin=0.31)
    c.a[np.broadcast_to(c.Y < yc, c.a.shape)] = 0
    hh = c.hash(43)
    c.paint_where(hh > 170, "gold", "gold_dark")
    c.revolve(0, yc, 0.37, "grey", rin=0.33)  # chain-mail skirt
    c.paint_where((c.hash(47) > 150) & (c.Y < yc), "grey", "darkgrey")
    c.cyl("y", 0, 0, yc + 0.33, yc + 0.38, 0.05, "darkgrey")  # grapple point
    c.sphere(0, yc + 0.4, 0, 0.03, "darkgrey")
    c.box(0.3, 0.4, 0, 0.06, -0.04, 0.04, "darkgrey")  # tether exit
    return c


def b_mass_spec():
    c = Canvas(-0.27, 0.27, 0, 0.44, -0.22, 0.22, CRAFT_VPM)
    c.box(-0.25, 0.25, 0, 0.3, -0.2, 0.2, "offwhite")
    c.paint(np.abs(c.Z) > 0.18, "gold")
    hh = c.hash(53)
    c.paint_where(hh > 170, "gold", "gold_dark")
    for x in (-0.13, 0.0):  # sample inlet funnels
        f = lambda Y: 0.035 + 0.035 * np.clip((Y - 0.3) / 0.08, 0, 1)
        c.revolve(0.3, 0.38, f, "silver", rin=lambda Y: f(Y) - 0.015, cx=x)
        c.cyl("y", x, 0, 0.3, 0.31, 0.03, "black")
    c.box(0.08, 0.23, 0.3, 0.38, -0.12, 0.08, "darkgrey")  # laser spectrometer
    c.segment((0.1, 0.38, 0.1), (-0.2, 0.36, 0.14), 0.012, "copper")  # gas lines
    c.segment((0.2, 0.32, 0.15), (0.2, 0.42, 0.15), 0.015, "silver")  # vent
    return c


def b_weather_station():
    c = Canvas(-0.26, 0.26, 0, 0.7, -0.26, 0.26, CRAFT_VPM)
    c.box(-0.07, 0.07, 0, 0.08, -0.06, 0.06, "darkgrey")
    c.cyl("y", 0, 0, 0.08, 0.64, 0.016, "white")  # mast
    for ang in (0.0, 2 * math.pi / 3):  # wind-sensor booms
        x, z = math.cos(ang) * 0.2, math.sin(ang) * 0.2
        c.segment((0, 0.5, 0), (x, 0.5, z), 0.012, "white")
        c.cyl("y", x, z, 0.47, 0.56, 0.025, "darkgrey")
        for k in range(3):  # sensor boards (fins)
            a2 = k * 2 * math.pi / 3
            c.segment((x, 0.56, z), (x + math.cos(a2) * 0.05, 0.6, z + math.sin(a2) * 0.05), 0.008, "white")
    c.segment((0, 0.32, 0), (-0.18, 0.3, 0.05), 0.012, "white")  # air-temperature boom
    c.cyl("x", 0.3, 0.05, -0.24, -0.17, 0.012, "silver")
    c.cyl("y", 0, 0, 0.64, 0.67, 0.045, "black")  # radiation & dust sensor
    c.cyl("y", 0, 0, 0.67, 0.68, 0.03, "lens")
    return c


def b_gpr():
    c = Canvas(-0.27, 0.27, 0, 0.16, -0.14, 0.14, CRAFT_VPM)
    c.box(-0.25, 0.25, 0, 0.06, -0.12, 0.12, "offwhite")  # radome
    x = np.abs(c.X)
    bow = (x > 0.02) & (x < 0.22) & (np.abs(c.Z) < 0.02 + 0.45 * x * 0.45)
    c.paint(bow & (c.Y > 0.05), "gold")
    c.box(-0.08, 0.08, 0.06, 0.13, -0.06, 0.06, "darkgrey")  # electronics
    c.cyl("y", 0.05, 0, 0.13, 0.16, 0.012, "gold")
    return c


def b_sample_capsule(d=0.81):
    R = d / 2
    c = Canvas(-R - 0.03, R + 0.03, 0, 0.6, -R - 0.03, R + 0.03, CRAFT_VPM)
    fore = lambda Y: R * np.clip(Y / 0.22, 0, 1) ** 0.5
    c.revolve(0, 0.22, fore, "copper_dark")
    hh = c.hash(59)
    c.paint_where(hh > 190, "copper_dark", "black")
    c.revolve(0.22, 0.25, R, "silver")
    back = lambda Y: R - (R - 0.17) * np.clip((Y - 0.25) / 0.26, 0, 1)
    c.revolve(0.25, 0.51, back, "darkgrey")
    c.paint_where(c.hash(61) > 215, "darkgrey", "grey")
    c.revolve(0.51, 0.56, 0.17, "silver")
    c.revolve(0.56, 0.6, 0.12, "gold")  # sample canister lid
    c.box(R * 0.6, R * 0.8, 0.3, 0.38, -0.05, 0.05, "grey")  # hinge / latch
    return c


V2_BUILDERS = {
    "engine_hydrolox_s": lambda: b_engine_v2(0.62, 1.6, 0.1, 0.19, 0.36, ncol="copper_dark", tubes="copper",
                                             pumps=2, frame_h=0.45),
    "engine_hydrolox_j2": lambda: b_engine_v2(0.98, 2.1, 0.2, 0.36, 0.5, ncol="darkgrey", tubes="grey", pumps=2,
                                              gg=True),
    "engine_hydrolox_rs68": lambda: b_engine_v2(1.22, 3.2, 0.33, 0.5, 0.6, ncol="copper_dark", ccol="silver",
                                                pumps=2, gg=True, power=0.6),
    "engine_kerolox_dual": lambda: b_engine_v2(0.68, 2.3, 0.17, 0.3, 0.5, ncol="nozzle", chambers=2, spacing=0.72),
    "engine_kerolox_quad": lambda: b_engine_v2(0.27, 0.95, 0.06, 0.11, 0.25, ncol="darkgrey", chambers=4,
                                               spacing=0.33, frame_h=0.4),
    "engine_methalox_vac": lambda: b_engine_v2(1.15, 2.9, 0.17, 0.32, 0.45, ncol="darkgrey", ccol="steel", pumps=2,
                                               ext=0.55, power=0.5),
    "engine_apogee": b_apogee,
    "engine_descent": lambda: b_engine_v2(0.75, 1.5, 0.12, 0.24, 0.4, ncol="darkgrey", pumps=0, ext=0.62,
                                          ext_col="steel_dark", valves=True, frame_h=0.45),
    "thruster_mono_lander": b_mono_lander,
    "thruster_hall_s": lambda: b_hall(0.24),
    "thruster_hall_l": lambda: b_hall(0.56),
    "kick_motor": lambda: b_kick_motor(1.24, 2.03),
    "sep_motor": b_sep_motor,
    "engine_aerospike": lambda: b_aerospike(2.5),
    "engine_ntr": b_ntr,
    "tank_lh2": lambda: b_tank_lh2(2.5, 8.0),
    "tank_toroid": lambda: b_tank_toroid(),
    "clamp_band": lambda: b_clamp_band(1.25),
    "adapter_rev": lambda: b_adapter_rev(),
    "truss_xs": lambda: b_truss_xs(),
    "truss_m": lambda: b_truss_m(),
    "strut_radial": lambda: b_strut_radial(),
    "docking_port": lambda: b_docking_port(1.25),
    "fin_large": lambda: b_fin_large(),
    "fin_swept": lambda: b_fin_swept(),
    "capsule_1": b_capsule_1,
    "capsule_2": b_capsule_2,
    "capsule_4": b_capsule_4,
    "crew_cabin": lambda: b_crew_cabin(),
    "hab_inflatable": lambda: b_hab_inflatable(),
    "cupola": lambda: b_cupola(),
    "les_tower": b_les_tower,
    "parachute_drogue": lambda: b_parachute_radial(0.17, 0.5, drogue=True),
    "parachute_radial": lambda: b_parachute_radial(0.3, 0.85),
    "landing_leg_lander": b_landing_leg_lander,
    "rover_wheel": lambda: b_rover_wheel(),
    "fuel_cell": b_fuel_cell,
    "solar_wing_l": lambda: b_solar_wing(panels=4, pw=1.3, pd=1.3),
    "solar_ultraflex": lambda: b_solar_ultraflex(),
    "fission_reactor": b_fission_reactor,
    "antenna_helix": lambda: b_antenna_helix(),
    "optical_terminal": b_optical_terminal,
    "radiator_deploy": lambda: b_radiator_deploy(),
    "heat_shield": lambda: b_heat_shield(2.5),
    "reaction_wheel_s": b_reaction_wheel_s,
    "reaction_wheels_l": b_reaction_wheels_l,
    "cmg": b_cmg,
    "rcs_heavy": b_rcs_heavy,
    "rcs_biprop": b_rcs_biprop,
    "magnetometer_s": lambda: b_magnetometer(0.6),
    "seismometer": b_seismometer,
    "mass_spec": b_mass_spec,
    "weather_station": b_weather_station,
    "gpr": b_gpr,
    "sample_capsule": lambda: b_sample_capsule(),
}

# v2 part ids whose model needs catalog-specific dimensions (checked first in build_for_part)
V2_PART_BUILDERS = {
    "eng_kick_37": lambda p: b_kick_motor(0.93, 1.69),
    "tank_lh2_m8": lambda p: b_tank_lh2(2.5, 8.0),
    "tank_lh2_l8": lambda p: b_tank_lh2(3.75, 8.0),
    "tank_xenon_08": lambda p: b_tank_xenon(0.8, 1.4),
    "decoupler_xs": lambda p: b_decoupler(0.625, 0.16),
    "decoupler_clamp_s": lambda p: b_clamp_band(1.25, 0.34),
    "decoupler_clamp_m": lambda p: b_clamp_band(2.5, 0.45),
    "interstage_s": lambda p: b_interstage(1.25, 2.0),
    "adapter_xss": lambda p: b_adapter(0.625, 1.25, 0.8),
    "adapter_sl": lambda p: b_adapter(1.25, 3.75, 2.5),
    "adapter_rev_ms": lambda p: b_adapter_rev(2.5, 1.25, 1.2),
    "docking_port_xs": lambda p: b_docking_port(0.625),
    "docking_port_s": lambda p: b_docking_port(1.25),
    "thrust_plate_l5": lambda p: b_thrust_plate(3.75, 0.7, 5, 0.55),
    "thrust_plate_m7": lambda p: b_thrust_plate(2.5, 0.6, 7, 0.3),
    "fairing_xs": lambda p: b_fairing(0.625, p["cyl_length_m"], p["nose_length_m"]),
    "fairing_s_long": lambda p: b_fairing(1.25, p["cyl_length_m"], p["nose_length_m"]),
    "fairing_m_long": lambda p: b_fairing(2.5, p["cyl_length_m"], p["nose_length_m"]),
    "fairing_l_long": lambda p: b_fairing(3.75, p["cyl_length_m"], p["nose_length_m"]),
    "nose_cone_xs": lambda p: b_nose_cone(0.625, 1.0),
    "nose_cone_l": lambda p: b_nose_cone(3.75, 6.0),
    "heat_shield_m": lambda p: b_heat_shield(2.5, 0.34),
    "heat_shield_l": lambda p: b_heat_shield(3.75, 0.42),
}


BUILDERS = {
    "tank_kerolox": lambda: b_tank("kerolox"),
    "tank_methalox": lambda: b_tank("methalox"),
    "tank_hydrolox": lambda: b_tank("hydrolox"),
    "tank_sphere": lambda: b_tank_sphere(),
    "tank_xenon": lambda: b_tank_xenon(),
    "engine_small": lambda: b_engine("small"),
    "engine_small_vac": lambda: b_engine("small_vac"),
    "engine_kerolox": lambda: b_engine("kerolox"),
    "engine_kerolox_vac": lambda: b_engine("kerolox_vac"),
    "engine_hydrolox_upper": lambda: b_engine("hydrolox_upper"),
    "engine_hydrolox_main": lambda: b_engine("hydrolox_main"),
    "engine_methalox": lambda: b_engine("methalox"),
    "engine_hypergolic": lambda: b_engine("hypergolic"),
    "srb": lambda: b_srb(),
    "thruster_mono": b_thruster_mono,
    "thruster_ion": b_thruster_ion,
    "decoupler": lambda: b_decoupler(),
    "decoupler_radial": b_decoupler_radial,
    "interstage": lambda: b_interstage(),
    "adapter": lambda: b_adapter(),
    "thrust_plate": lambda: b_thrust_plate(),
    "fairing": lambda: b_fairing(),
    "nose_cone": lambda: b_nose_cone(),
    "fin": lambda: b_fin(),
    "payload_adapter": lambda: b_payload_adapter(),
    "avionics_core": lambda: b_avionics_core(),
    "reaction_wheels": b_reaction_wheels,
    "rcs_block": b_rcs_block,
    "star_tracker": b_star_tracker,
    "solar_body": lambda: b_solar_body(),
    "solar_wing": lambda: b_solar_wing(),
    "solar_rollout": lambda: b_solar_rollout(),
    "battery": b_battery,
    "rtg": lambda: b_rtg(),
    "antenna_omni": b_antenna_omni,
    "antenna_dish_s": lambda: b_dish(0.5),
    "antenna_dish_l": lambda: b_dish(1.5),
    "radiator": lambda: b_radiator(),
    "mli": lambda: b_mli(),
    "bus_box": lambda: b_bus(),
    "camera": lambda: b_camera(False),
    "camera_hr": lambda: b_camera(True),
    "neutron_spec": b_neutron_spec,
    "spectrometer": b_spectrometer,
    "radar": lambda: b_radar(),
    "lidar": b_lidar,
    "magnetometer": lambda: b_magnetometer(),
    "crew_capsule": lambda: b_crew_capsule(),
    "parachute": lambda: b_parachute(),
    "landing_legs": lambda: b_landing_legs(),
    "grid_fins": lambda: b_grid_fins(),
}
BUILDERS.update(V2_BUILDERS)


# =================================================================== meshing
AO_LEVEL = np.array([0.50, 0.68, 0.84, 1.0], np.float32)


def mesh(c):
    occ = np.pad(c.a > 0, 1)
    col = np.pad(c.a, 1)
    pos_l, nrm_l, col_l, idx_l = [], [], [], []
    base_i = 0
    i_all = np.arange(occ.shape[0]).reshape(-1, 1, 1)
    j_all = np.arange(occ.shape[1]).reshape(1, -1, 1)
    k_all = np.arange(occ.shape[2]).reshape(1, 1, -1)
    hashv = ((i_all * 73856093) ^ (j_all * 19349663) ^ (k_all * 83492791)) & 255
    for axis in range(3):
        u_ax, v_ax = (axis + 1) % 3, (axis + 2) % 3
        for s in (1, -1):
            nb = np.roll(occ, -s, axis=axis)
            exposed = occ & ~nb
            p = np.argwhere(exposed)
            if len(p) == 0:
                continue
            n = np.zeros(3, int)
            n[axis] = s
            front = p + n
            corners = [(0, 0), (1, 0), (1, 1), (0, 1)] if s > 0 else [(0, 0), (0, 1), (1, 1), (1, 0)]
            ao = []
            verts = []
            for du, dv in corners:
                su, sv = 2 * du - 1, 2 * dv - 1
                e_u = np.zeros(3, int)
                e_v = np.zeros(3, int)
                e_u[u_ax] = su
                e_v[v_ax] = sv
                s1 = occ[tuple((front + e_u).T)]
                s2 = occ[tuple((front + e_v).T)]
                cc = occ[tuple((front + e_u + e_v).T)]
                a = np.where(s1 & s2, 0, 3 - (s1.astype(int) + s2 + cc))
                ao.append(a)
                vp = (p - 1).astype(np.float64)
                vp[:, axis] += 1 if s > 0 else 0
                vp[:, u_ax] += du
                vp[:, v_ax] += dv
                verts.append(vp / c.vpm + c.min)
            ao = np.stack(ao, 1)  # (F,4)
            V = np.stack(verts, 1)  # (F,4,3)
            F = len(p)
            base_rgb = RGB[col[tuple(p.T)]]  # (F,3)
            jitter = 1.0 + ((hashv[tuple(p.T)] / 255.0) - 0.5) * 0.07
            rgb = np.clip(base_rgb * jitter[:, None], 0, 255)[:, None, :] * AO_LEVEL[ao][:, :, None]
            lin = (rgb / 255.0) ** 2.2
            flip = (ao[:, 0] + ao[:, 2]) < (ao[:, 1] + ao[:, 3])
            q = base_i + np.arange(F)[:, None] * 4
            tri_a = np.concatenate([q + 0, q + 1, q + 2, q + 0, q + 2, q + 3], 1)
            tri_b = np.concatenate([q + 1, q + 2, q + 3, q + 1, q + 3, q + 0], 1)
            idx_l.append(np.where(flip[:, None], tri_b, tri_a).reshape(-1))
            pos_l.append(V.reshape(-1, 3))
            nrm_l.append(np.repeat(n[None, :], F * 4, 0))
            col_l.append(lin.reshape(-1, 3))
            base_i += F * 4
    pos = np.concatenate(pos_l).astype(np.float32)
    nrm = np.concatenate(nrm_l).astype(np.float32)
    colr = np.concatenate(col_l)
    rgba8 = np.concatenate([np.round(colr * 255), np.full((len(colr), 1), 255)], 1).astype(np.uint8)
    idx = np.concatenate(idx_l).astype(np.uint32)
    return pos, nrm, rgba8, idx


def mesh_greedy(c, with_cidx=False):
    """Like mesh(), but merges coplanar faces that share color and a uniform AO level
    into larger quads (greedy meshing), which cuts triangle counts several times over.
    The per-voxel color jitter moves to the shader (shaders/voxel_part.gdshader): each
    vertex gets UV = voxel coordinates on the face plane and UV2 = (slice, face id), so
    the shader can hash the voxel cell under every fragment. Returns
    (pos, nrm, rgba8, idx, uv, uv2), plus a per-vertex palette index array when with_cidx."""
    occ = np.pad(c.a > 0, 1)
    col = np.pad(c.a, 1)
    out_pos, out_nrm, out_col, out_uv, out_uv2, out_idx, out_cid = [], [], [], [], [], [], []
    base_i = 0

    def emit(axis, s, u_ax, v_ax, slab, u0, v0, du_len, dv_len, ao4, ci, face_id):
        """One quad: slab = voxel-space plane coordinate along axis; (u0, v0) min corner."""
        nonlocal base_i
        rgb_lin = lin_table[ci]
        n = [0.0, 0.0, 0.0]
        n[axis] = float(s)
        corners = [(0, 0), (1, 0), (1, 1), (0, 1)] if s > 0 else [(0, 0), (0, 1), (1, 1), (1, 0)]
        for k, (du, dv) in enumerate(corners):
            vp = [0.0, 0.0, 0.0]
            vp[axis] = slab
            vp[u_ax] = u0 + du * du_len
            vp[v_ax] = v0 + dv * dv_len
            out_pos.append([vp[0] / c.vpm + c.min[0], vp[1] / c.vpm + c.min[1], vp[2] / c.vpm + c.min[2]])
            out_nrm.append(n)
            out_col.append(rgb_lin * AO_LEVEL[ao4[k]])
            out_uv.append([u0 + du * du_len, v0 + dv * dv_len])
            out_uv2.append([slab, face_id])
            out_cid.append(ci)
        q = base_i
        if (ao4[0] + ao4[2]) < (ao4[1] + ao4[3]):
            out_idx.extend([q + 1, q + 2, q + 3, q + 1, q + 3, q + 0])
        else:
            out_idx.extend([q + 0, q + 1, q + 2, q + 0, q + 2, q + 3])
        base_i += 4

    lin_table = (RGB / 255.0) ** 2.2
    for axis in range(3):
        u_ax, v_ax = (axis + 1) % 3, (axis + 2) % 3
        for s in (1, -1):
            face_id = axis * 2 + (1 if s > 0 else 0)
            nb = np.roll(occ, -s, axis=axis)
            exposed = occ & ~nb
            p = np.argwhere(exposed)
            if len(p) == 0:
                continue
            front = p.copy()
            front[:, axis] += s
            ao = []
            for du, dv in ((0, 0), (1, 0), (1, 1), (0, 1)):
                e_u = np.zeros(3, int)
                e_v = np.zeros(3, int)
                e_u[u_ax] = 2 * du - 1
                e_v[v_ax] = 2 * dv - 1
                s1 = occ[tuple((front + e_u).T)]
                s2 = occ[tuple((front + e_v).T)]
                cc = occ[tuple((front + e_u + e_v).T)]
                ao.append(np.where(s1 & s2, 0, 3 - (s1.astype(int) + s2 + cc)))
            ao = np.stack(ao, 1)  # corner order (0,0),(1,0),(1,1),(0,1) in (u, v)
            cidx = col[tuple(p.T)]
            uniform = (ao == ao[:, :1]).all(1)
            # ---- non-uniform AO faces: merge into strips along the direction in which
            # the AO does not change (typical for voxelized cylinders: steps run the full
            # height), otherwise one quad each. Corner order: 0=(0,0) 1=(1,0) 2=(1,1) 3=(0,1).
            const_u = (ao[:, 0] == ao[:, 1]) & (ao[:, 3] == ao[:, 2]) & ~uniform  # AO varies only along v
            const_v = (ao[:, 0] == ao[:, 3]) & (ao[:, 1] == ao[:, 2]) & ~uniform & ~const_u
            single = ~uniform & ~const_u & ~const_v
            for strip_mask, run_ax, fixed_ax in ((const_u, u_ax, v_ax), (const_v, v_ax, u_ax)):
                idxs = np.nonzero(strip_mask)[0]
                if len(idxs) == 0:
                    continue
                pf = p[idxs]
                # key: color + the two AO values on the fixed-axis sides
                if run_ax == u_ax:
                    k1, k2 = ao[idxs, 0], ao[idxs, 3]
                else:
                    k1, k2 = ao[idxs, 0], ao[idxs, 1]
                keys2 = (cidx[idxs].astype(np.int64) * 4 + k1) * 4 + k2
                order = np.lexsort((pf[:, run_ax], pf[:, fixed_ax], keys2, pf[:, axis]))
                pf, keys2, src = pf[order], keys2[order], idxs[order]
                i = 0
                total = len(pf)
                while i < total:
                    j = i + 1
                    while (j < total and keys2[j] == keys2[i] and pf[j, axis] == pf[i, axis]
                           and pf[j, fixed_ax] == pf[i, fixed_ax] and pf[j, run_ax] == pf[j - 1, run_ax] + 1):
                        j += 1
                    pv = pf[i] - 1
                    slab = pv[axis] + (1 if s > 0 else 0)
                    length = j - i
                    a = ao[src[i]]
                    a4 = a if s > 0 else a[[0, 3, 2, 1]]
                    du_len = length if run_ax == u_ax else 1
                    dv_len = length if run_ax == v_ax else 1
                    emit(axis, s, u_ax, v_ax, slab, pv[u_ax], pv[v_ax], du_len, dv_len, a4,
                         int(cidx[src[i]]), face_id)
                    i = j
            for f in np.nonzero(single)[0]:
                pv = p[f] - 1
                slab = pv[axis] + (1 if s > 0 else 0)
                a4 = ao[f] if s > 0 else ao[f][[0, 3, 2, 1]]
                emit(axis, s, u_ax, v_ax, slab, pv[u_ax], pv[v_ax], 1, 1, a4, int(cidx[f]), face_id)
            # ---- uniform faces: greedy rectangles per slice, keyed by (color, ao)
            pu = p[uniform]
            if len(pu) == 0:
                continue
            keys = cidx[uniform].astype(np.int64) * 4 + ao[uniform][:, 0]
            order = np.lexsort((pu[:, v_ax], pu[:, u_ax], pu[:, axis]))
            pu, keys = pu[order], keys[order]
            slices = np.unique(pu[:, axis])
            for sl in slices:
                m = pu[:, axis] == sl
                ps, ks = pu[m], keys[m]
                umin, vmin = ps[:, u_ax].min(), ps[:, v_ax].min()
                g = np.full((ps[:, u_ax].max() - umin + 1, ps[:, v_ax].max() - vmin + 1), -1, np.int64)
                g[ps[:, u_ax] - umin, ps[:, v_ax] - vmin] = ks
                H, W = g.shape
                for a in range(H):
                    row = g[a]
                    b = 0
                    while b < W:
                        k = row[b]
                        if k < 0:
                            b += 1
                            continue
                        w = 1
                        while b + w < W and row[b + w] == k:
                            w += 1
                        h = 1
                        while a + h < H and (g[a + h, b:b + w] == k).all():
                            h += 1
                        g[a:a + h, b:b + w] = -1
                        aol = int(k % 4)
                        slab = (sl - 1) + (1 if s > 0 else 0)
                        emit(axis, s, u_ax, v_ax, slab, a + umin - 1, b + vmin - 1, h, w, [aol] * 4,
                             int(k // 4), face_id)
                        b += w
    pos = np.array(out_pos, np.float32)
    nrm = np.array(out_nrm, np.float32)
    colr = np.array(out_col)
    rgba8 = np.concatenate([np.round(np.clip(colr, 0, 1) * 255), np.full((len(colr), 1), 255)], 1).astype(np.uint8)
    out = (pos, nrm, rgba8, np.array(out_idx, np.uint32), np.array(out_uv, np.float32), np.array(out_uv2, np.float32))
    return out + (np.array(out_cid, np.int32),) if with_cidx else out


def write_glb_uv(path, name, m):
    """write_glb() for mesh_greedy() output: adds TEXCOORD_0/1 (voxel cell coordinates)."""
    pos, nrm, col, idx, uv, uv2 = m
    blobs = [pos.astype(np.float32).tobytes(), nrm.astype(np.float32).tobytes(), col.tobytes(),
             uv.astype(np.float32).tobytes(), uv2.astype(np.float32).tobytes(), idx.tobytes()]
    offs, o = [], 0
    for b in blobs:
        offs.append(o)
        o += len(b) + (-len(b) % 4)
    binary = b"".join(b + b"\0" * (-len(b) % 4) for b in blobs)
    gltf = {
        "asset": {"version": "2.0", "generator": "voxel_gen.py greedy"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2,
                                                                 "TEXCOORD_0": 3, "TEXCOORD_1": 4},
                                                  "indices": 5, "material": 0}]}],
        "materials": [{"name": "voxel", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                                                  "metallicFactor": 0.0, "roughnessFactor": 0.8}}],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [{"buffer": 0, "byteOffset": offs[i], "byteLength": len(blobs[i]),
                         "target": 34963 if i == 5 else 34962} for i in range(6)],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5121, "normalized": True, "count": len(col), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5126, "count": len(uv), "type": "VEC2"},
            {"bufferView": 4, "componentType": 5126, "count": len(uv2), "type": "VEC2"},
            {"bufferView": 5, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(binary), b"BIN\0") + binary)


def transform(m, angle_deg=0.0, offset=(0, 0, 0)):
    pos, nrm, col, idx = m
    a = math.radians(angle_deg)
    rot = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]], np.float32)
    return (pos @ rot.T + np.array(offset, np.float32), nrm @ rot.T, col, idx)


def merge_meshes(ms):
    pos, nrm, col, idx, base = [], [], [], [], 0
    for p, n, c, i in ms:
        pos.append(p)
        nrm.append(n)
        col.append(c)
        idx.append(i + base)
        base += len(p)
    return np.concatenate(pos), np.concatenate(nrm), np.concatenate(col), np.concatenate(idx).astype(np.uint32)


def write_glb(path, name, m):
    pos, nrm, col, idx = m
    blobs = [pos.astype(np.float32).tobytes(), nrm.astype(np.float32).tobytes(), col.tobytes(), idx.tobytes()]
    offs, o = [], 0
    for b in blobs:
        offs.append(o)
        o += len(b) + (-len(b) % 4)
    binary = b"".join(b + b"\0" * (-len(b) % 4) for b in blobs)
    gltf = {
        "asset": {"version": "2.0", "generator": "voxel_gen.py v2"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2},
                                                   "indices": 3, "material": 0}]}],
        "materials": [{"name": "voxel", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                                                  "metallicFactor": 0.0, "roughnessFactor": 0.8}}],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [{"buffer": 0, "byteOffset": offs[i], "byteLength": len(blobs[i]),
                         "target": 34963 if i == 3 else 34962} for i in range(4)],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5121, "normalized": True, "count": len(col), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(binary), b"BIN\0") + binary)


# =================================================================== assemblies
def top_of(m):
    return float(m[0][:, 1].max())


def stack_meshes(items):
    """items bottom->top: (mesh, y_overlap). Returns merged mesh and list of y offsets."""
    out, y, ys = [], 0.0, []
    for m, overlap in items:
        y -= overlap
        out.append(transform(m, 0, (0, y, 0)))
        ys.append(y)
        y += top_of(m)
    return out, ys


def assembled_andorinha():
    d = 1.25
    eng = mesh(b_engine("small"))
    plate = mesh(b_thrust_plate(d=d, h=0.35, slots=9, hole_r=0.12))
    t1 = mesh(b_tank("kerolox", d, 8.0))
    dec = mesh(b_decoupler(d, 0.22))
    ist = mesh(b_interstage(d, 1.2))
    t2 = mesh(b_tank("kerolox", d, 2.0))
    core = mesh(b_avionics_core(d, 0.4))
    fair = mesh(b_fairing(d, 1.6, 1.9))
    eh = top_of(eng)
    parts, ys = stack_meshes([(plate, 0), (t1, 0), (dec, 0), (ist, 0), (t2, 0), (core, 0), (fair, 0)])
    parts = [transform(p, 0, (0, eh - 0.25, 0)) for p in parts]
    r = d / 2 * 0.66
    for a in range(8):
        ang = a * 360 / 8
        parts.append(transform(eng, 0, (math.cos(math.radians(ang)) * r, 0, math.sin(math.radians(ang)) * r)))
    parts.append(eng)
    return merge_meshes(parts)


def assembled_condor():
    d = 3.75
    eng = mesh(b_engine("kerolox"))
    mvac = mesh(b_engine("kerolox_vac"))
    plate = mesh(b_thrust_plate(d=d))
    t8 = mesh(b_tank("kerolox", d, 8.0))
    t4 = mesh(b_tank("kerolox", d, 4.0))
    ist = mesh(b_interstage(d, 5.5))
    dec = mesh(b_decoupler(d))
    fair = mesh(b_fairing(d, 6.5, 6.0))
    eh = top_of(eng) - 0.3
    seq = [(plate, 0)] + [(t8, 0)] * 5 + [(dec, 0), (ist, 0)]
    lower, ys = stack_meshes(seq)
    lower = [transform(p, 0, (0, eh, 0)) for p in lower]
    y_ist_top = eh + ys[-1] + top_of(ist)
    mvac_h = top_of(mvac)
    y_s2 = y_ist_top
    upper, _ = stack_meshes([(t8, 0), (t4, 0), (mesh(b_avionics_core(d, 0.6)), 0), (fair, 0)])
    upper = [transform(p, 0, (0, y_s2, 0)) for p in upper]
    parts = lower + upper + [transform(mvac, 0, (0, y_s2 - mvac_h + 0.3, 0))]
    r = d / 2 * 0.66
    for a in range(8):
        ang = math.radians(a * 45)
        parts.append(transform(eng, 0, (math.cos(ang) * r, 0, math.sin(ang) * r)))
    parts.append(eng)
    return merge_meshes(parts)


def assembled_satellite():
    bus = mesh(b_bus())
    wing = mesh(b_solar_wing())
    dish = mesh(b_dish(1.5))
    cam = mesh(b_camera(True))
    rtg = mesh(b_rtg())
    omni = mesh(b_antenna_omni())
    st = mesh(b_star_tracker())
    mag = mesh(b_magnetometer(1.6))
    parts = [bus,
             transform(wing, 0, (0.75, 0.75, 0)),
             transform(wing, 180, (-0.75, 0.75, 0)),
             transform(dish, 0, (0, 1.4, 0)),
             transform(cam, 0, (0.4, -0.75, 0.3)),
             transform(omni, 0, (-0.55, 1.4, 0.55)),
             transform(st, 0, (0.55, 1.4, -0.55)),
             transform(mag, 90, (0.2, 1.2, -0.75)),
             transform(rtg, 0, (-0.4, -0.7, -0.35))]
    return merge_meshes(parts)


ASSEMBLIES = {
    "andorinha_assembled": assembled_andorinha,
    "condor_assembled": assembled_condor,
    "satellite_assembled": assembled_satellite,
}


SIZE_D = {"XS": 0.625, "S": 1.25, "M": 2.5, "L": 3.75}
FAIRING_DIMS = {"S": (1.6, 1.9), "M": (4.0, 4.0), "L": (6.5, 6.0)}  # cylinder, nose height (m)
BUS_DIMS = {"bus_cubesat": (0.24, 0.36), "bus_small": (0.8, 0.8), "bus_medium": (1.5, 1.4), "bus_large": (2.2, 2.0)}
DISH_D = {"antenna_mga": 0.5, "antenna_hga": 1.5, "antenna_hga_xl": 3.0}


def build_for_part(p):
    """Canvas for one catalog part, sized from the catalog (one .glb per part id)."""
    pid, model, sz = p["id"], p["model"], p.get("size")
    if pid in V2_PART_BUILDERS:
        return V2_PART_BUILDERS[pid](p)
    d = SIZE_D.get(sz, 1.25)
    if pid.startswith("tank_") and p.get("length_m"):
        return b_tank(p["propellant"], d, p["length_m"])
    if model == "tank_sphere":
        return b_tank_sphere(float(pid.split("_")[-1]) / 10)
    if model == "tank_xenon":
        return b_tank_xenon(0.5)
    if pid == "eng_srb_s":
        return b_srb(1.0, 9.0)
    if pid == "eng_srb_m":
        return b_srb(1.6, 17.0)
    if pid.startswith("decoupler_") and pid != "decoupler_radial":
        return b_decoupler(d, {"S": 0.22, "M": 0.32, "L": 0.4}[sz])
    if pid.startswith("interstage_"):
        return b_interstage(d, 3.0)
    if pid == "adapter_sm":
        return b_adapter(1.25, 2.5, 1.2)
    if pid == "adapter_ml":
        return b_adapter(2.5, 3.75, 1.6)
    if pid.startswith("thrust_plate_"):
        return b_thrust_plate(d, {"S": 0.35, "M": 0.6, "L": 0.7}[sz], p["engine_slots"],
                              {"S": 0.12, "M": 0.5, "L": 0.42}[sz])
    if pid.startswith("fairing_"):
        return b_fairing(d, *FAIRING_DIMS[sz])
    if pid.startswith("nose_cone_"):
        return b_nose_cone(d, d * 1.6)
    if pid.startswith("avionics_core_"):
        return b_avionics_core(d, 0.55 if sz == "S" else 0.6)
    if pid in BUS_DIMS:
        return b_bus(*BUS_DIMS[pid])
    if pid in DISH_D:
        return b_dish(DISH_D[pid])
    return BUILDERS[model]()


def main():
    import parts_catalog
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    naive = "--naive" in sys.argv  # old per-face meshing (for comparisons)
    out = Path(args[0])
    only = set(args[1:])
    (out / "parts").mkdir(parents=True, exist_ok=True)
    (out / "showcase").mkdir(parents=True, exist_ok=True)
    jobs = [(out / "parts" / f"{p['id']}.glb", p["id"], lambda p=p: build_for_part(p)) for p in parts_catalog.PARTS]
    jobs += [(out / "showcase" / f"{n}.glb", n, b) for n, b in ASSEMBLIES.items()]
    for path, name, build in jobs:
        if only and name not in only:
            continue
        res = build()
        nvox = int((res.a > 0).sum()) if isinstance(res, Canvas) else 0
        if isinstance(res, Canvas) and not naive:
            m = mesh_greedy(res)
            write_glb_uv(path, name, m)
        else:
            m = mesh(res) if isinstance(res, Canvas) else res
            write_glb(path, name, m)
        print(f"{name:24s} voxels={nvox:8d} tris={len(m[3]) // 3:8d}  {path.stat().st_size / 1e6:6.1f} MB")


if __name__ == "__main__":
    main()
