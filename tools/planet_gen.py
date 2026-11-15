"""Voxel planet generator for MARGIN part 2 (solar system map).

Every body in data/solar_system.json becomes a voxelized unit-radius sphere (radius 1.0;
the scene scales it to its visual radius) with a procedural surface painted per voxel:
continents/oceans/ice for Earth, craters + maria for the Moon, rust + caps for Mars,
cloud swirls for Venus, latitude bands + Great Red Spot for Jupiter, and so on.
Meshing, ambient occlusion, color jitter and .glb writing come from tools/voxel_gen.py
(imported, not copied). Its palette-indexed Canvas is fed a per-body palette of up to
255 colors obtained by quantizing the painted surface colors with Pillow.

Outputs (assets/voxel/planets/):
    <id>_lod0.glb  high      (radius LOD_VOXELS[id][0] voxels)
    <id>_lod1.glb  medium
    <id>_lod2.glb  very low
    earth_clouds_lod{0,1,2}.glb   floating voxel cloud shell
    saturn_rings_lod{0,1,2}.glb   flat voxel rings with Cassini division + Encke gap
                                  (units: Saturn radii, ring plane = XZ)

Deterministic: every random choice derives from the body's `visual.seed`.

Usage:
    python tools/planet_gen.py                 # all bodies
    python tools/planet_gen.py earth moon      # only some ids
    python tools/planet_gen.py --preview out.png [ids]   # also writes a contact-sheet preview
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import voxel_gen as vg  # noqa: E402  (meshing + glb writer)

DATA = ROOT / "data" / "solar_system.json"
OUT = ROOT / "assets" / "voxel" / "planets"

# =================================================================== visual scale
# Real sizes/distances cannot share one scale on screen (Neptune is ~30 AU away while the
# Earth is 1/23000 AU wide), so the map uses compressed formulas (scene units, 1 u ~ 1 m in
# the editor). They are documented in docs/solar_system.md and in src/solar_system/solar_system.gd.
RADIUS_K = 0.04        # planet/moon radius  r = RADIUS_K * sqrt(R_km)    (Earth 3.19, Jupiter 10.6)
SUN_RADIUS = 18.0      # the Sun would be 33 u with the same law; clamped so it does not swallow Mercury
DIST_OFFSET = 36.0     # planet orbit  d = DIST_OFFSET + DIST_K * sqrt(a_AU)   (Earth 108, Neptune 431)
DIST_K = 72.0
MOON_BASE = 1.4        # moon orbit  d = r_parent * (MOON_BASE + MOON_K * sqrt(a_km / R_parent_km))
MOON_K = 0.15


def visual_radius(b):
    if b["type"] == "star":
        return SUN_RADIUS
    return RADIUS_K * math.sqrt(b["radius_km"])


def visual_distance(b, by_id):
    if not b.get("parent"):
        return 0.0
    if "semi_major_axis_km" in b:
        p = by_id[b["parent"]]
        return visual_radius(p) * (MOON_BASE + MOON_K * math.sqrt(b["semi_major_axis_km"] / p["radius_km"]))
    return DIST_OFFSET + DIST_K * math.sqrt(b["semi_major_axis_au"])


# voxels across the RADIUS for lod0 / lod1 / lod2 (file size ~ radius^2)
LOD_VOXELS = {
    "sun": (46, 20, 9), "mercury": (32, 15, 7), "venus": (38, 17, 8), "earth": (46, 20, 9),
    "moon": (32, 15, 7), "mars": (40, 18, 8), "jupiter": (48, 21, 9), "europa": (30, 14, 7),
    "saturn": (46, 20, 9), "uranus": (38, 17, 8), "neptune": (38, 17, 8), "pluto": (26, 12, 6),
    "io": (30, 14, 7), "ganymede": (32, 15, 7), "callisto": (30, 14, 7), "titan": (32, 15, 7),
    "phobos": (20, 10, 5), "deimos": (18, 9, 5), "mae_gelo": (24, 11, 6),
}
RING_VOXELS = (88, 40, 18)   # voxels across the ring OUTER radius
# voxel_gen's per-vertex AO levels (0..3 occluders), overridden per body kind: smooth
# gas/ice giants and the Sun get a soft AO so the stair-steps do not read as stripes.
AO_ROCKY = np.array([0.56, 0.72, 0.87, 1.0], np.float32)
AO_SOFT = np.array([0.80, 0.88, 0.95, 1.0], np.float32)
AO_BY_KIND = {"sun": AO_SOFT, "jupiter": AO_SOFT, "saturn": AO_SOFT, "uranus": AO_SOFT, "neptune": AO_SOFT,
              "venus": AO_SOFT, "europa": AO_SOFT, "titan": AO_SOFT, "io": AO_SOFT}
# relief as a fraction of the radius (exaggerated: voxel worlds read better with steps)
RELIEF = {"earth": 0.045, "moon": 0.06, "mercury": 0.06, "mars": 0.06, "europa": 0.02, "pluto": 0.05,
          "io": 0.03, "ganymede": 0.05, "callisto": 0.06, "phobos": 0.12, "deimos": 0.1, "mae_gelo": 0.14}


# =================================================================== noise (vectorized)
def _hash(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 1440662683 + seed * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float64) / 65535.0


def vnoise(p, seed=0):
    """3D value noise in [0,1] for points p (N,3)."""
    i = np.floor(p).astype(np.int64)
    f = p - i
    u = f * f * (3.0 - 2.0 * f)
    out = np.zeros(len(p))
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1 - u[:, 2]
                out += wx * wy * wz * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(p, freq=1.0, octaves=5, seed=0, gain=0.5, lac=2.03):
    amp, tot, norm = 1.0, np.zeros(len(p)), 0.0
    for o in range(octaves):
        tot += amp * vnoise(p * freq + o * 17.31, seed + o * 101)
        norm += amp
        amp *= gain
        freq *= lac
    return tot / norm


def ridged(p, freq=1.0, octaves=4, seed=0):
    amp, tot, norm = 1.0, np.zeros(len(p)), 0.0
    for o in range(octaves):
        n = 1.0 - np.abs(vnoise(p * freq + o * 9.7, seed + o * 37) * 2 - 1)
        tot += amp * n * n
        norm += amp
        amp *= 0.5
        freq *= 2.1
    return tot / norm


def warp(p, amt, freq, seed):
    return p + amt * np.stack([fbm(p, freq, 3, seed + k * 7) - 0.5 for k in range(3)], 1)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def hexc(h):
    return np.array([int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)], np.float64)


def mix(a, b, t):
    a = np.broadcast_to(np.asarray(a, np.float64), (len(t), 3)) if np.ndim(a) == 1 else a
    b = np.broadcast_to(np.asarray(b, np.float64), (len(t), 3)) if np.ndim(b) == 1 else b
    return a + (b - a) * np.clip(t, 0, 1)[:, None]


def ramp(stops, t):
    """stops: [(pos, '#hex'), ...] ascending; t (N,) -> (N,3)."""
    xs = [s[0] for s in stops]
    cols = np.array([hexc(s[1]) for s in stops])
    return np.stack([np.interp(t, xs, cols[:, k]) for k in range(3)], 1)


def latlon(P):
    return np.arcsin(np.clip(P[:, 1], -1, 1)), np.arctan2(P[:, 2], P[:, 0])


def ang_dist(P, c):
    c = np.asarray(c, np.float64)
    c = c / np.linalg.norm(c)
    return np.arccos(np.clip(P @ c, -1, 1))


def dir_from(lat_deg, lon_deg):
    la, lo = math.radians(lat_deg), math.radians(lon_deg)
    return np.array([math.cos(la) * math.cos(lo), math.sin(la), math.cos(la) * math.sin(lo)])


def random_dirs(rng, n):
    v = rng.normal(size=(n, 3))
    return v / np.linalg.norm(v, axis=1, keepdims=True)


# =================================================================== craters
class Craters:
    """A deterministic crater population (power-law sizes) usable for height and color."""

    def __init__(self, seed, n, rmin, rmax, rays=0, avoid=None):
        rng = np.random.default_rng(seed)
        self.c = random_dirs(rng, n)
        u = rng.random(n)
        self.r = rmin * (rmax / rmin) ** (u ** 2.2)  # many small, few big
        self.age = rng.random(n)
        self.rays = set(np.argsort(-self.r * (self.age > 0.6))[:rays].tolist()) if rays else set()

    def field(self, P):
        """Returns (height delta in [-1, 0.5], ejecta brightness, floor mask)."""
        h = np.zeros(len(P))
        bright = np.zeros(len(P))
        floor = np.zeros(len(P))
        for k in range(len(self.r)):
            r = self.r[k]
            d = np.arccos(np.clip(P @ self.c[k], -1, 1))
            near = d < r * 3.2
            if not near.any():
                continue
            x = d[near] / r
            bowl = np.where(x < 1, -(1 - x * x), 0.0)
            rim = 0.45 * np.exp(-((x - 1.0) / 0.22) ** 2)
            h[near] += (bowl + rim) * min(1.0, r * 14)
            floor[near] = np.maximum(floor[near], (x < 0.85) * 1.0)
            if k in self.rays:
                # bright ejecta rays (Tycho/Copernicus style): radial streaks fading with distance
                e1 = np.cross(self.c[k], [0.3, 1.0, 0.2])
                e1 /= np.linalg.norm(e1)
                e2 = np.cross(self.c[k], e1)
                ang = np.arctan2(P[near] @ e2, P[near] @ e1)
                streak = (np.sin(ang * 11 + k) * 0.5 + 0.5) ** 6
                bright[near] = np.maximum(bright[near], streak * np.exp(-(x - 1) * 0.9) * (x > 0.9))
        return h, bright, floor


# =================================================================== surfaces
# Each painter: (P unit dirs (N,3)) -> height in [0,1] (relief) and (P, height) -> sRGB (N,3)


class Surface:
    relief = 0.0

    def __init__(self, body):
        self.b = body
        self.seed = body["visual"].get("seed", 1)
        self.pal = [hexc(h) for h in body["visual"]["palette"]]

    def height(self, P):
        return np.zeros(len(P))

    def color(self, P, h):
        raise NotImplementedError


class Sun(Surface):
    def color(self, P, h):
        s = self.seed
        gran = vnoise(P * 22.0, s) * 0.55 + vnoise(P * 47.0, s + 1) * 0.30 + fbm(P, 3.0, 3, s + 2) * 0.45
        t = sstep(0.25, 1.05, gran)
        c = ramp([(0.0, "#d9541a"), (0.35, "#f6861f"), (0.6, "#ffb22e"), (0.82, "#ffd862"), (1.0, "#fff3c0")], t)
        lat, lon = latlon(P)
        rng = np.random.default_rng(s)
        for _ in range(9):  # sunspot groups in the activity belts
            la = rng.choice([-1, 1]) * rng.uniform(8, 28)
            lo = rng.uniform(-180, 180)
            for _k in range(rng.integers(1, 4)):
                cdir = dir_from(la + rng.uniform(-3, 3), lo + rng.uniform(-6, 6))
                rr = math.radians(rng.uniform(1.6, 3.6))
                d = ang_dist(P, cdir) / rr
                c = mix(c, hexc("#c8641c"), sstep(1.6, 1.0, d) * 0.85)   # penumbra
                c = mix(c, hexc("#5a1c08"), sstep(0.75, 0.35, d))         # umbra
        fac = sstep(0.72, 0.9, fbm(P, 6.0, 3, s + 9)) * sstep(40, 10, np.abs(np.degrees(lat)))
        return mix(c, hexc("#fff8d8"), fac * 0.5)


class Rocky(Surface):
    """Mercury / Moon / Pluto base: craters, optional maria, rays."""

    def __init__(self, body):
        super().__init__(body)
        self.relief = RELIEF.get(body["id"], 0.05)
        st = body["visual"]["style"]
        n = {"mercury": 170, "moon": 140, "pluto": 45, "callisto": 190, "ganymede": 120, "phobos": 40,
             "deimos": 25, "mae_gelo": 30}.get(body["id"], 100)
        self.cr = Craters(self.seed, n, 0.035, 0.33, rays=3 if "rays" in st else 0)
        self._cache = None

    def _fields(self, P):
        key = (len(P), float(P[:7].sum()))
        if self._cache is None or self._cache[0] != key:
            self._cache = (key, self.cr.field(P))
        return self._cache[1]

    def maria(self, P):
        if "maria" not in self.b["visual"]["style"]:
            return np.zeros(len(P))
        # lunar maria crowd the near side; the near side faces the parent (-X in model space)
        near = sstep(0.1, -0.7, P[:, 0])
        m = fbm(warp(P, 0.5, 1.4, self.seed + 3), 1.7, 5, self.seed + 4)
        return sstep(0.5, 0.58, m * 0.75 + near * 0.33)

    def height(self, P):
        ch, _, _ = self._fields(P)
        base = fbm(P, 3.0, 4, self.seed + 1) * 0.35
        mar = self.maria(P)
        return np.clip(0.45 + base + ch * 0.38 - mar * 0.25, 0, 1)

    def color(self, P, h):
        ch, bright, floor = self._fields(P)
        p = self.pal
        t = fbm(P, 4.0, 5, self.seed + 5)
        c = ramp([(0.2, self.b["visual"]["palette"][2]), (0.5, self.b["visual"]["palette"][1]),
                  (0.8, self.b["visual"]["palette"][0])], t)
        c = mix(c, p[3] if len(p) > 3 else p[0], sstep(0.62, 0.8, fbm(P, 9.0, 3, self.seed + 6)) * 0.5)
        c = mix(c, p[2] * 0.82, floor * 0.35)                     # darker crater floors
        c = mix(c, p[-1] if self.b["id"] != "pluto" else p[0], np.clip(bright, 0, 1) * 0.7)
        c = mix(c, p[0] * 1.08, sstep(0.25, 0.5, ch) * 0.5)        # bright rims
        mar = self.maria(P)
        if mar.any():
            mc = ramp([(0.0, "#4a4a4c"), (1.0, "#6a6966")], fbm(P, 6.0, 3, self.seed + 7))
            c = mix(c, mc, mar * 0.92)
        if self.b["id"] == "pluto":
            lat, lon = latlon(P)
            # Tombaugh Regio "heart": two bright lobes on the anti-Charon side (+X)
            heart = np.maximum(sstep(0.42, 0.30, ang_dist(P, dir_from(25, -10))),
                               sstep(0.36, 0.24, ang_dist(P, dir_from(10, 22))))
            dark = sstep(0.22, 0.05, np.abs(lat + 0.12 * np.sin(lon * 3))) * (1 - heart)
            c = mix(c, hexc("#5a3a28"), dark * sstep(0.35, 0.6, fbm(P, 3, 3, self.seed + 8)) * 0.9 + dark * 0.25)
            c = mix(c, hexc("#f6efe4"), heart * 0.95)
            c = mix(c, hexc("#e8d8c0"), sstep(0.75, 1.1, np.abs(np.sin(lat))) * 0.6)
        return c


class Earth(Surface):
    relief = RELIEF["earth"]

    def land(self, P):
        q = warp(P, 0.55, 1.2, self.seed)
        return fbm(q, 1.35, 6, self.seed + 1)

    def height(self, P):
        c = self.land(P)
        land = sstep(0.503, 0.518, c)
        mtn = ridged(P, 3.2, 4, self.seed + 2) * sstep(0.55, 0.65, c)
        return land * (0.38 + 0.62 * np.clip(mtn * 1.4, 0, 1))

    def color(self, P, h):
        lat, lon = latlon(P)
        alat = np.abs(np.degrees(lat))
        c = self.land(P)
        coast = np.clip((0.51 - c) / 0.09, 0, 1)
        ocean = ramp([(0.0, "#3f9ad6"), (0.18, "#2a7cc4"), (0.5, "#1d5fb0"), (1.0, "#0f3d86")], coast)
        moist = fbm(P, 2.4, 4, self.seed + 3) + 0.25 * np.cos(np.radians(alat) * 3.0)
        desert = sstep(0.52, 0.66, 1 - moist) * sstep(8, 18, alat) * sstep(42, 30, alat)
        green = ramp([(0.0, "#2f7a32"), (0.5, "#4f9a3c"), (1.0, "#86ad52")], fbm(P, 5.0, 3, self.seed + 4))
        green = mix(green, hexc("#2d5e34"), sstep(45, 62, alat) * 0.7)          # boreal forest
        green = mix(green, hexc("#256d2a"), sstep(14, 0, alat) * 0.6)            # tropical
        landc = mix(green, ramp([(0, "#c9a868"), (1, "#e3cf98")], fbm(P, 7, 3, self.seed + 5)), desert)
        landc = mix(landc, hexc("#8a7350"), sstep(0.62, 0.8, h))                  # highlands
        landc = mix(landc, hexc("#f2f5fa"), sstep(0.86, 0.95, h))                 # snowy peaks
        isl = sstep(0.503, 0.518, c)
        out = mix(ocean, landc, isl)
        beach = sstep(0.0, 0.02, c - 0.498) * sstep(0.04, 0.015, c - 0.498) * (1 - desert)
        out = mix(out, hexc("#d8c890"), beach * 0.35)
        ice = sstep(68, 76, alat + (fbm(P, 4.0, 3, self.seed + 6) - 0.5) * 18)
        return mix(out, hexc("#f4f8ff"), ice)

    def clouds(self, P):
        q = warp(P * np.array([1, 2.2, 1]), 0.7, 1.6, self.seed + 10)
        lat, _ = latlon(P)
        alat = np.abs(np.degrees(lat))
        f = fbm(q, 3.3, 5, self.seed + 11)
        belt = 0.06 * np.cos(np.radians(alat) * 4.0)  # ITCZ + mid-latitude storm tracks
        return (f + belt) > 0.625


class Mars(Surface):
    relief = RELIEF["mars"]

    def __init__(self, body):
        super().__init__(body)
        self.cr = Craters(self.seed, 60, 0.03, 0.2)
        self._f = None

    def _cf(self, P):
        key = (len(P), float(P[:7].sum()))
        if self._f is None or self._f[0] != key:
            self._f = (key, self.cr.field(P))
        return self._f[1]

    def height(self, P):
        lat, lon = latlon(P)
        ch, _, _ = self._cf(P)
        base = fbm(P, 2.0, 5, self.seed) * 0.5
        olympus = sstep(0.32, 0.0, ang_dist(P, dir_from(18, -134))) * 0.55
        tharsis = sstep(0.9, 0.2, ang_dist(P, dir_from(0, -110))) * 0.18
        # Valles Marineris: a long trench just south of the equator
        dl = np.degrees(lat) + 8 + 2.5 * np.sin(lon * 5)
        lo = np.degrees(lon)
        canyon = sstep(3.2, 0.8, np.abs(dl)) * sstep(-95, -80, lo) * sstep(-25, -40, lo)
        hellas = sstep(0.38, 0.1, ang_dist(P, dir_from(-42, 70))) * 0.35
        return np.clip(0.35 + base + ch * 0.25 + olympus + tharsis - canyon * 0.45 - hellas, 0, 1)

    def color(self, P, h):
        lat, lon = latlon(P)
        alat = np.abs(np.degrees(lat))
        t = fbm(warp(P, 0.3, 2.0, self.seed + 1), 2.2, 6, self.seed + 2)
        c = ramp([(0.25, "#9a3a14"), (0.45, "#c1440e"), (0.6, "#d9692c"), (0.78, "#e8915a")], t)
        dark = sstep(0.52, 0.6, fbm(warp(P, 0.4, 1.2, self.seed + 3), 1.6, 5, self.seed + 4))
        dark = dark * sstep(65, 40, alat)
        c = mix(c, ramp([(0, "#5c2614"), (1, "#7a3418")], fbm(P, 6, 3, self.seed + 5)), dark * 0.85)
        _, _, floor = self._cf(P)
        c = mix(c, c * 0.82, floor * 0.4)
        c = mix(c, hexc("#6b2a12"), sstep(0.25, 0.12, h) * 0.6)       # canyon floors / Hellas
        c = mix(c, hexc("#e9a070"), sstep(0.7, 0.85, h) * 0.4)        # dusty volcano flanks
        n_cap = sstep(74, 80, np.degrees(lat) + (fbm(P, 5.0, 3, self.seed + 6) - 0.5) * 14)
        s_cap = sstep(-79, -84, np.degrees(lat) + (fbm(P, 5.0, 3, self.seed + 7) - 0.5) * 10)
        return mix(c, hexc("#f4efe8"), np.maximum(n_cap, s_cap))


class Venus(Surface):
    def color(self, P, h):
        lat, lon = latlon(P)
        q = warp(P, 0.9, 1.3, self.seed)
        swirl = fbm(q * np.array([1.0, 2.6, 1.0]), 2.0, 6, self.seed + 1)
        chevron = 0.5 + 0.5 * np.sin(lon * 1.0 + np.abs(lat) * 4.5 + swirl * 4.0)   # the "Y" feature
        t = swirl * 0.7 + chevron * 0.3
        c = ramp([(0.3, "#b98a45"), (0.45, "#d4a55a"), (0.58, "#e6c27a"), (0.72, "#f3dfa6"), (0.9, "#fbf0cf")], t)
        return mix(c, hexc("#f8ecc8"), sstep(55, 80, np.abs(np.degrees(lat))) * 0.5)


class Banded(Surface):
    """Gas/ice giants: latitude bands with turbulent edges."""

    BANDS = {
        # (lat_deg_edge, color) piecewise from south pole to north pole
        "jupiter": [(-90, "#8c7d70"), (-62, "#a08872"), (-45, "#d9c3a0"), (-36, "#b98a5e"), (-29, "#efe0c4"),
                    (-20, "#b06f45"), (-9, "#d6b48a"), (-3, "#f3e6cd"), (5, "#e8d2a8"), (8, "#9a5c3a"),
                    (17, "#b47a50"), (21, "#f1e3c8"), (29, "#c49468"), (36, "#ead7b2"), (46, "#b99b7a"),
                    (62, "#9a8676"), (90, "#857668")],
        "saturn": [(-90, "#9f9070"), (-70, "#c2a876"), (-50, "#d9bf8a"), (-35, "#e9d3a0"), (-22, "#d2b27a"),
                   (-10, "#f2e2b6"), (8, "#f7ecca"), (20, "#e3c98f"), (32, "#ecd8a6"), (48, "#cfae6e"),
                   (66, "#c4ab80"), (78, "#b7b09a"), (90, "#a9aaa0")],
        "uranus": [(-90, "#bfe8ea"), (-60, "#a9dde2"), (-30, "#8fd0d9"), (0, "#82c7d2"), (30, "#78bfcb"),
                   (60, "#6db4c2"), (90, "#64abb9")],
        "neptune": [(-90, "#2a4db0"), (-65, "#3a64d4"), (-45, "#4f80ea"), (-28, "#2f56c4"), (-12, "#3d6fe0"),
                    (10, "#4676e6"), (30, "#355fd0"), (50, "#4a7ae6"), (70, "#2e52bc"), (90, "#2a4aa8")],
    }
    TURB = {"jupiter": 0.09, "saturn": 0.035, "uranus": 0.012, "neptune": 0.05}

    def color(self, P, h):
        bid = self.b["id"]
        lat, lon = latlon(P)
        q = warp(P * np.array([1.0, 3.5, 1.0]), 0.8, 1.6, self.seed)
        turb = (fbm(q, 2.5, 5, self.seed + 1) - 0.5) * self.TURB[bid]
        la = np.degrees(np.arcsin(np.clip(P[:, 1] + turb, -1, 1)))
        stops = self.BANDS[bid]
        c = np.stack([np.interp(la, [s[0] for s in stops], [hexc(s[1])[k] for s in stops]) for k in range(3)], 1)
        fine = fbm(P * np.array([0.7, 9.0, 0.7]) + turb[:, None] * 6, 1.4, 4, self.seed + 2)
        c = c * (0.9 + 0.2 * fine)[:, None]
        if bid == "jupiter":
            c = self._jupiter(P, lat, lon, c)
        elif bid == "saturn":
            c = self._saturn_hex(P, lat, lon, c)
        elif bid == "neptune":
            c = self._neptune(P, lat, lon, c)
        elif bid == "uranus":
            c = mix(c, hexc("#e6fbfa"), sstep(-55, -80, np.degrees(lat)) * 0.4)
        return np.clip(c, 0, 255)

    def _jupiter(self, P, lat, lon, c):
        # Great Red Spot: ellipse 2:1 at 22 deg S, surrounded by a pale collar and swirls
        la, lo = np.degrees(lat), np.degrees(lon)
        dlo = (lo - 30 + 180) % 360 - 180
        e = np.sqrt((dlo / 13.0) ** 2 + ((la + 22) / 6.4) ** 2)
        swirl = fbm(P * 9 + np.stack([np.sin(e * 6)] * 3, 1) * 0.3, 1, 3, self.seed + 3)
        c = mix(c, hexc("#efe2c8"), sstep(1.5, 1.05, e) * 0.85)
        spot = ramp([(0, "#a8432c"), (0.6, "#c4553a"), (1, "#d97a52")], np.clip(e + (swirl - 0.5) * 0.6, 0, 1))
        c = mix(c, spot, sstep(1.05, 0.8, e))
        rng = np.random.default_rng(self.seed + 4)
        for _ in range(9):  # white ovals (BA-like) and small storms
            la0 = rng.choice([-33, -40, 18, 24, -15]) + rng.uniform(-2, 2)
            lo0 = rng.uniform(-180, 180)
            d = np.sqrt((((lo - lo0 + 180) % 360 - 180) / rng.uniform(3, 5.5)) ** 2 + ((la - la0) / 2.2) ** 2)
            c = mix(c, hexc("#f7efe0"), sstep(1.0, 0.5, d) * 0.9)
        return c

    def _saturn_hex(self, P, lat, lon, c):
        colat = 90 - np.degrees(lat)  # deg from north pole
        a = lon % (math.pi / 3) - math.pi / 6
        hexr = colat * np.cos(a) / math.cos(math.pi / 6)
        edge = sstep(1.6, 0.4, np.abs(hexr - 13.5))
        c = mix(c, hexc("#a9ada2"), sstep(13.5, 12.0, hexr) * 0.3)
        return mix(c, hexc("#d6c08e"), edge * 0.5)

    def _neptune(self, P, lat, lon, c):
        la, lo = np.degrees(lat), np.degrees(lon)
        dlo = (lo + 60 + 180) % 360 - 180
        e = np.sqrt((dlo / 11) ** 2 + ((la + 20) / 6) ** 2)
        c = mix(c, hexc("#16256a"), sstep(1.0, 0.55, e))
        streak = sstep(0.62, 0.72, fbm(P * np.array([0.5, 7.0, 0.5]), 2.0, 4, self.seed + 5))
        near = sstep(2.6, 1.2, np.sqrt((dlo / 16) ** 2 + ((la + 13) / 3) ** 2))
        c = mix(c, hexc("#e8f0ff"), np.maximum(near, streak * 0.55) * 0.85)
        return c


class Europa(Surface):
    relief = RELIEF["europa"]

    def __init__(self, body):
        super().__init__(body)
        rng = np.random.default_rng(self.seed)
        self.lines = random_dirs(rng, 46)
        self.widths = rng.uniform(0.006, 0.02, 46)

    def color(self, P, h):
        t = fbm(P, 3.0, 5, self.seed + 1)
        c = ramp([(0.3, "#cdbfa6"), (0.55, "#e3d9c6"), (0.8, "#f4efe4")], t)
        chaos = sstep(0.6, 0.68, fbm(warp(P, 0.4, 2.0, self.seed + 2), 2.5, 4, self.seed + 3))
        c = mix(c, ramp([(0, "#a07656"), (1, "#c9a582")], fbm(P, 9, 3, self.seed + 4)), chaos * 0.75)
        wob = (fbm(P, 3.0, 3, self.seed + 5) - 0.5) * 0.05
        lin = np.zeros(len(P))
        for k in range(len(self.lines)):
            d = np.abs(P @ self.lines[k] + wob)
            seg = sstep(0.45, 0.7, vnoise(P * 2.2 + k * 3.1, self.seed + 50 + k))  # lineae are arcs, not full circles
            lin = np.maximum(lin, sstep(self.widths[k], self.widths[k] * 0.35, d) * seg)
        c = mix(c, hexc("#8a5236"), lin * 0.85)
        return c


class Io(Surface):
    """Sulfur plains, dark volcanic calderas with red plume rings (Pele), white SO2 frost."""
    relief = 0.03

    def __init__(self, body):
        super().__init__(body)
        rng = np.random.default_rng(self.seed)
        self.vents = random_dirs(rng, 34)
        self.sizes = rng.uniform(0.025, 0.07, 34)

    def color(self, P, h):
        t = fbm(warp(P, 0.5, 1.8, self.seed + 1), 2.6, 5, self.seed + 2)
        c = ramp([(0.25, "#c9a13a"), (0.45, "#e9c443"), (0.62, "#f3e27a"), (0.8, "#f7f1c8")], t)
        lat, _lon = latlon(P)
        c = mix(c, hexc("#a8743c"), sstep(50, 75, np.abs(np.degrees(lat))) * 0.6)   # darker poles
        frost = sstep(0.62, 0.72, fbm(P, 5.0, 3, self.seed + 3))
        c = mix(c, hexc("#f4f0dc"), frost * 0.5)
        for k in range(len(self.vents)):
            d = np.arccos(np.clip(P @ self.vents[k], -1, 1)) / self.sizes[k]
            if k % 5 == 0:   # big plume deposit rings (red sulfur, Pele-like)
                c = mix(c, hexc("#c4553a"), sstep(3.6, 3.0, d) * sstep(1.6, 2.4, d) * 0.75)
            c = mix(c, hexc("#3a2a1c"), sstep(1.0, 0.55, d))
            c = mix(c, hexc("#d98b2b"), sstep(1.5, 1.0, d) * sstep(0.5, 0.9, d) * 0.7)
        return c


class Titan(Surface):
    """Thick orange haze: soft latitude bands, a darker north polar hood."""

    def color(self, P, h):
        lat, _lon = latlon(P)
        la = np.degrees(lat)
        q = warp(P * np.array([1.0, 2.2, 1.0]), 0.5, 1.2, self.seed)
        t = fbm(q, 1.6, 4, self.seed + 1) * 0.35 + (la + 90) / 180 * 0.4
        c = ramp([(0.2, "#b0732e"), (0.4, "#c98a3a"), (0.55, "#e0a24a"), (0.75, "#efbd6a")], t)
        c = mix(c, hexc("#8c5a24"), sstep(55, 80, la) * 0.55)
        return mix(c, hexc("#f3cf86"), sstep(-10, 10, la) * sstep(25, 10, la) * 0.2)


PAINTERS = {"sun": Sun, "mercury": Rocky, "moon": Rocky, "pluto": Rocky, "earth": Earth, "mars": Mars,
            "venus": Venus, "jupiter": Banded, "saturn": Banded, "uranus": Banded, "neptune": Banded,
            "europa": Europa, "io": Io, "titan": Titan, "ganymede": Rocky, "callisto": Rocky,
            "phobos": Rocky, "deimos": Rocky, "mae_gelo": Rocky}


# =================================================================== voxelization
def set_palette(rgb_surface):
    """Quantize painted colors to <=255 entries, install them as voxel_gen's palette and
    return per-point palette indices (1-based, 0 = empty)."""
    n = len(rgb_surface)
    img = Image.fromarray(np.clip(rgb_surface, 0, 255).astype(np.uint8).reshape(1, n, 3), "RGB")
    q = img.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.array(q.getpalette()[: 255 * 3], np.float32).reshape(-1, 3)
    full = np.zeros((256, 3), np.float32)
    full[1: 1 + len(pal)] = pal
    vg.RGB = full  # mesh() reads the module-level palette
    return np.asarray(q, np.uint8).reshape(-1).astype(np.int32) + 1


def surface_mask(solid):
    occ = np.pad(solid, 1)
    exposed = np.zeros_like(occ)
    for ax in range(3):
        for s in (1, -1):
            exposed |= occ & ~np.roll(occ, s, ax)
    return exposed[1:-1, 1:-1, 1:-1]


def voxel_sphere(painter, rvox):
    relief = getattr(painter, "relief", 0.0)
    pad = relief + 2.0 / rvox
    c = vg.Canvas(-1 - pad, 1 + pad, -1 - pad, 1 + pad, -1 - pad, 1 + pad, rvox)
    X, Y, Z = np.broadcast_arrays(c.X, c.Y, c.Z)
    d = np.sqrt(X ** 2 + Y ** 2 + Z ** 2)
    solid = d <= 1.0
    if relief > 0:
        shell = (d > 1.0 - 1.5 / rvox) & (d <= 1.0 + relief + 1.0 / rvox)
        idx = np.nonzero(shell)
        P = np.stack([X[idx], Y[idx], Z[idx]], 1) / d[idx][:, None]
        h = painter.height(P)
        solid[idx] = d[idx] <= 1.0 + h * relief
    surf = solid & surface_mask(solid)
    idx = np.nonzero(surf)
    pts = np.stack([X[idx], Y[idx], Z[idx]], 1)
    P = pts / np.linalg.norm(pts, axis=1, keepdims=True)
    h = painter.height(P)
    # supersample the paint on coarse LODs so thin features (lineae, coasts, bands) average
    # into blended voxels instead of aliasing into random dots
    ss = 1 if rvox >= 30 else (4 if rvox >= 14 else 8)
    if ss == 1:
        rgb = painter.color(P, h)
    else:
        rng = np.random.default_rng(1234)
        rgb = np.zeros((len(P), 3))
        for _ in range(ss):
            q = pts + (rng.random(pts.shape) - 0.5) / rvox
            Q = q / np.linalg.norm(q, axis=1, keepdims=True)
            rgb += painter.color(Q, painter.height(Q))
        rgb /= ss
    c.a[solid] = 1
    c.a[idx] = set_palette(rgb)
    return c


def voxel_clouds(painter, rvox):
    relief = painter.relief
    r0 = 1.0 + relief * 0.75 + 1.0 / rvox
    r1 = r0 + 1.0 / rvox
    pad = r1 + 1.0 / rvox
    c = vg.Canvas(-pad, pad, -pad, pad, -pad, pad, rvox)
    X, Y, Z = np.broadcast_arrays(c.X, c.Y, c.Z)
    d = np.sqrt(X ** 2 + Y ** 2 + Z ** 2)
    shell = (d > r0) & (d <= r1 + 0.5 / rvox)
    idx = np.nonzero(shell)
    P = np.stack([X[idx], Y[idx], Z[idx]], 1) / d[idx][:, None]
    keep = painter.clouds(P)
    sel = tuple(a[keep] for a in idx)
    shade = 0.93 + 0.07 * fbm(P[keep], 8.0, 2, painter.seed + 20)
    rgb = np.outer(shade, hexc("#ffffff"))
    c.a[sel] = set_palette(rgb)
    return c


def voxel_rings(body, rvox):
    """Flat ring in Saturn radii: outer radius = rvox voxels, one voxel thick (two for B)."""
    rg = body["rings"]
    R = body["radius_km"]
    rin, rout = rg["inner_km"] / R, rg["outer_km"] / R
    vpm = rvox / rout
    t = 1.0 / vpm
    c = vg.Canvas(-rout - t, rout + t, -0.5 * t, 0.5 * t, -rout - t, rout + t, vpm)
    X, Y, Z = np.broadcast_arrays(c.X, c.Y, c.Z)
    r = np.sqrt(X ** 2 + Z ** 2)
    rk = r * R  # km
    m = (r >= rin) & (r <= rout)
    vox_km = R / vpm
    for a, b, _n in rg["gaps_km"]:
        if b - a < 0.15 * vox_km:
            continue  # too thin to show at this LOD
        w = max(b - a, 0.9 * vox_km)  # keep thin gaps (Encke) at least ~1 voxel wide
        mid = (a + b) / 2
        m &= ~((rk > mid - w / 2) & (rk < mid + w / 2))
    zone_c = (rk < 92000)
    rng_seed = body["visual"]["seed"]
    hsh = vg.Canvas.hash(c, rng_seed) / 255.0
    m &= ~(zone_c & (hsh < 0.35))           # dusty, translucent-looking C ring
    m &= ~((rk > 122170) & (hsh < 0.12))    # slightly grainy A ring
    idx = np.nonzero(m)
    rr = rk[idx]
    P = np.stack([X[idx], np.zeros_like(rr), Z[idx]], 1)
    ringlets = 0.5 + 0.5 * np.sin(rr / 900.0) * np.sin(rr / 2300.0 + 1.3)
    fine = fbm(np.stack([rr / 1500.0, np.zeros_like(rr), np.zeros_like(rr)], 1), 1.0, 4, rng_seed)
    tt = np.clip(ringlets * 0.45 + fine * 0.55, 0, 1)
    col_c = ramp([(0, "#6f655a"), (1, "#9a8c78")], tt)
    col_b = ramp([(0, "#cdb98f"), (0.5, "#e6d4a8"), (1, "#f6ead0")], tt)
    col_a = ramp([(0, "#a8956f"), (1, "#cbb68e")], tt)
    col = np.where((rr < 92000)[:, None], col_c, np.where((rr < 117580)[:, None], col_b, col_a))
    # soften the C/B boundary
    col = mix(col, col_c, sstep(95000, 90000, rr) * (rr >= 92000))
    c.a[idx] = set_palette(col)
    del P
    return c


# =================================================================== output
def write_import(path):
    """Seed a .import next to the .glb (only if missing) so Godot imports planets without
    auto mesh-LOD/shadow meshes; we author our own LODs. Godot fills in uid/paths."""
    imp = path.with_suffix(".glb.import")
    if imp.exists():
        return
    imp.write_text(
        '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
        'nodes/root_type=""\nnodes/root_name=""\nnodes/apply_root_scale=true\nnodes/root_scale=1.0\n'
        'nodes/import_as_skeleton_bones=false\nnodes/use_name_suffixes=true\nnodes/use_node_type_suffixes=true\n'
        'meshes/ensure_tangents=false\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=false\n'
        'meshes/light_baking=0\nmeshes/lightmap_texel_size=0.2\nmeshes/force_disable_compression=false\n'
        'skins/use_named_skins=true\nanimation/import=false\nanimation/fps=30\nanimation/trimming=false\n'
        'animation/remove_immutable_tracks=true\nanimation/import_rest_as_RESET=false\nimport_script/path=""\n'
        'materials/extract=0\nmaterials/extract_format=0\nmaterials/extract_path=""\n_subresources={}\n'
        'gltf/naming_version=2\ngltf/embedded_image_handling=1\n', encoding="utf-8")


def emit(canvas, name, previews):
    m = vg.mesh(canvas)
    path = OUT / f"{name}.glb"
    vg.write_glb(path, name, m)
    write_import(path)
    size = path.stat().st_size
    print(f"  {name:22s} {len(m[3]) // 3:7d} tris  {size / 1e6:5.2f} MB")
    if previews is not None:
        previews.append((name, render_preview(canvas)))
    return size


def render_preview(c, px=180):
    """Quick orthographic look along -Z with lambert light from upper-left (for iteration)."""
    a = c.a
    if a.shape[1] <= 2:  # flat ring: look down -Y
        top = a.max(1)
        col = vg.RGB[top]
        im = Image.fromarray(np.clip(col.transpose(1, 0, 2), 0, 255).astype(np.uint8))
        return im.resize((px, px), Image.NEAREST)
    occ = a > 0
    nx, ny, nz = a.shape
    zi = np.where(occ.any(2), nz - 1 - np.argmax(occ[:, :, ::-1], axis=2), -1)
    img = np.zeros((ny, nx, 3), np.float32)
    ii, jj = np.nonzero(zi >= 0)
    kk = zi[ii, jj]
    col = vg.RGB[a[ii, jj, kk]]
    p = np.stack([c.X[ii, 0, 0], c.Y[0, jj, 0], c.Z[0, 0, kk]], 1)
    n = p / np.maximum(np.linalg.norm(p, axis=1, keepdims=True), 1e-6)
    lam = np.clip(n @ np.array([-0.5, 0.5, 0.7]) / 0.98, 0.05, 1) * 0.9 + 0.1
    img[ny - 1 - jj, ii] = col * lam[:, None]
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((px, int(px * ny / nx)), Image.NEAREST)
    return im


def render_icon(c, px=64, emissive=False):
    """Round RGBA thumbnail for the HUD body list (lit from the upper left, like the map)."""
    a = c.a
    occ = a > 0
    nx, ny, nz = a.shape
    zi = np.where(occ.any(2), nz - 1 - np.argmax(occ[:, :, ::-1], axis=2), -1)
    img = np.zeros((ny, nx, 4), np.float32)
    ii, jj = np.nonzero(zi >= 0)
    kk = zi[ii, jj]
    rgb = vg.RGB[a[ii, jj, kk]]
    p = np.stack([c.X[ii, 0, 0], c.Y[0, jj, 0], c.Z[0, 0, kk]], 1)
    n = p / np.maximum(np.linalg.norm(p, axis=1, keepdims=True), 1e-6)
    if emissive:
        lam = 0.75 + 0.35 * np.clip(n[:, 2], 0, 1) ** 0.5
    else:
        lam = np.clip(n @ np.array([-0.55, 0.45, 0.7]), 0, 1) ** 0.9 * 1.05 + 0.08
    img[ny - 1 - jj, ii, :3] = np.clip(rgb * lam[:, None], 0, 255)
    img[ny - 1 - jj, ii, 3] = 255
    im = Image.fromarray(img.astype(np.uint8), "RGBA")
    return im.resize((px, px), Image.LANCZOS)


def main(argv):
    preview = None
    if argv and argv[0] == "--preview":
        preview = argv[1]
        argv = argv[2:]
    only = set(argv)
    data = json.loads(DATA.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    shots = [] if preview else None
    for b in data["bodies"]:
        bid = b["id"]
        if only and bid not in only:
            continue
        painter = PAINTERS[bid](b)
        vg.AO_LEVEL = AO_BY_KIND.get(bid, AO_ROCKY)
        print(f"{bid}: visual radius {visual_radius(b):.2f}")
        for lod, rv in enumerate(LOD_VOXELS[bid]):
            canvas = voxel_sphere(painter, rv)
            if lod == 0:
                (OUT / "icons").mkdir(exist_ok=True)
                render_icon(canvas, emissive=bid == "sun").save(OUT / "icons" / f"{bid}.png")
            total += emit(canvas, f"{bid}_lod{lod}", shots)
            if bid == "earth":
                total += emit(voxel_clouds(painter, rv), f"earth_clouds_lod{lod}", shots)
        if "rings" in b:
            for lod, rv in enumerate(RING_VOXELS):
                total += emit(voxel_rings(b, rv), f"{bid}_rings_lod{lod}", shots)
    print(f"total {total / 1e6:.1f} MB -> {OUT}")
    if shots:
        cols = 6
        rows = (len(shots) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 190, rows * 210), (8, 10, 16))
        for k, (name, im) in enumerate(shots):
            x, y = (k % cols) * 190 + 5, (k // cols) * 210 + 5
            sheet.paste(im, (x, y + (180 - im.height) // 2))
        sheet.save(preview)
        print("preview ->", preview)


if __name__ == "__main__":
    main(sys.argv[1:])
