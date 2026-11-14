"""Bakes the textures used by the flight scene (scenes/flight/textures/).

    earth_albedo.png   equirectangular voxel Earth (RGB colour, A = relief height), painted
                       by the SAME procedural painter as the solar-system voxel Earth
                       (tools/planet_gen.py, imported, not copied), so the planet you fly over
                       is the planet you see on the map
    earth_clouds.png   cloud cover mask (same cloud function as the voxel cloud shell)
    moon_albedo.png    the Moon (planet_gen Rocky painter)
    navball.png        navball: sky / ground halves, pitch ladder, heading ring
    earth_site.json    latitude / longitude chosen for the launch site: a coast with the
                       ocean to the east (rockets launch over the sea, like Cape Canaveral)

The textures are sampled with nearest filtering in shaders/flight_sky.gdshader, which turns
each texel into a voxel column (~20 km wide) seen from orbit.

Usage:  python src/flight/gen/make_flight_textures.py [--size 2048]
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import planet_gen as pg  # noqa: E402

OUT = ROOT / "scenes" / "flight" / "textures"


def body(bid):
    data = json.loads((ROOT / "data" / "solar_system.json").read_text(encoding="utf-8"))
    return next(b for b in data["bodies"] if b["id"] == bid)


def equirect_dirs(w, h):
    """Unit directions for texel centres; u = lon from -180 (left) to 180, v = lat 90 (top) to -90.
    Same lat/lon convention as planet_gen.latlon (Y = north pole, lon = atan2(z, x))."""
    lon = (np.arange(w) + 0.5) / w * 2 * math.pi - math.pi
    lat = math.pi / 2 - (np.arange(h) + 0.5) / h * math.pi
    LON, LAT = np.meshgrid(lon, lat)
    P = np.stack([np.cos(LAT) * np.cos(LON), np.sin(LAT), np.cos(LAT) * np.sin(LON)], -1)
    return P.reshape(-1, 3)


# Launch site frame. Must match src/flight/flight_world.gd (SITE_* constants) and the coast
# function of shaders/outside_ground.gdshader (the launch-site ground outside the hangar).
SITE_EAST = np.array([0.894, 0.0, -0.447]) / np.linalg.norm([0.894, 0.0, -0.447])  # render dir of the sea
SITE_UP = np.array([0.0, 1.0, 0.0])
PAD_IN_SITE = np.array([-125.0, -745.0])   # pad A (x, z) in the launch-site scene
COAST_ORIGIN = np.array([350.0, -200.0])
COAST_NORMAL = np.array([0.89443, -0.44721])
COAST_DIR = np.array([-0.44721, -0.89443])
R_M = 6371000.0


def site_matrix(lat, lon):
    """Rotation M (rows) taking render/PCI directions to planet-fixed directions:
    pad up -> pad direction, launch direction (sea) -> increasing longitude."""
    u_p = pg.dir_from(lat, lon)
    lo = math.radians(lon)
    e_p = np.array([-math.sin(lo), 0.0, math.cos(lo)])
    n_p = np.cross(u_p, e_p)
    n_r = np.cross(SITE_UP, SITE_EAST)
    A = np.stack([SITE_EAST, SITE_UP, n_r], 1)   # columns: render basis
    B = np.stack([e_p, u_p, n_p], 1)             # columns: planet basis
    return B @ A.T


def coast(x, z):
    t = x * COAST_DIR[0] + z * COAST_DIR[1]
    return ((x - COAST_ORIGIN[0]) * COAST_NORMAL[0] + (z - COAST_ORIGIN[1]) * COAST_NORMAL[1]
            + 40.0 * np.sin(t * 0.004) + 25.0 * np.sin(t * 0.011 + 1.3))


def carve_site(P, rgb, hgt, site):
    """Repaints the texels around the launch site with the site's own coastline, so the
    voxel planet seen from altitude continues the ground of the launch-site scene."""
    M = site_matrix(site["lat"], site["lon"])
    u_p = pg.dir_from(site["lat"], site["lon"])
    ang = np.degrees(np.arccos(np.clip(P @ u_p, -1, 1)))
    idx = np.nonzero(ang < 3.0)[0]
    D = P[idx] @ M            # planet -> render (M orthonormal: M^T p == p @ M)
    x = D[:, 0] / D[:, 1] * R_M + PAD_IN_SITE[0]
    z = D[:, 2] / D[:, 1] * R_M + PAD_IN_SITE[1]
    s = coast(x, z)
    w = 1.0 - pg.sstep(1.8, 3.0, ang[idx])
    sea = s > 0.0
    deep = np.clip(s / 60000.0, 0, 1)
    ocean = pg.ramp([(0.0, "#3f9ad6"), (0.18, "#2a7cc4"), (0.5, "#1d5fb0"), (1.0, "#0f3d86")], deep)
    land_was = hgt[idx] > 0.01
    # water that was already water keeps its own colour (no visible carve boundary)
    ocean = np.where(land_was[:, None], ocean, rgb[idx])
    land_col = np.where(land_was[:, None], rgb[idx], pg.hexc("#4f9a3c"))
    beach = (s > -2500.0) & ~sea
    land_col = np.where(beach[:, None], pg.mix(land_col, pg.hexc("#d8c890"), np.full(len(idx), 0.45)), land_col)
    carved = np.where(sea[:, None], ocean, land_col)
    # turning water into land only right around the pad (~70 km): further out the
    # original coastline takes over, so no straight carve boundary shows from orbit
    w = np.where(~sea & ~land_was, w * (1.0 - pg.sstep(0.35, 0.65, ang[idx])), w)
    rgb[idx] = rgb[idx] * (1 - w[:, None]) + carved * w[:, None]
    new_h = np.where(sea, 0.0, np.maximum(hgt[idx], 0.4))
    hgt[idx] = np.where(w > 0.5, new_h, hgt[idx])
    print(f"  carved {len(idx)} texels around the launch site")


def bake_earth(w):
    h = w // 2
    painter = pg.Earth(body("earth"))
    P = equirect_dirs(w, h)
    out_rgb = np.zeros((len(P), 3))
    out_h = np.zeros(len(P))
    out_c = np.zeros(len(P), bool)
    step = 262144
    for i in range(0, len(P), step):
        q = P[i:i + step]
        hh = painter.height(q)
        out_h[i:i + step] = hh
        out_rgb[i:i + step] = painter.color(q, hh)
        out_c[i:i + step] = painter.clouds(q)
        print(f"  earth {min(i + step, len(P)) * 100 // len(P)}%", flush=True)
    site = find_site(painter)
    (OUT / "earth_site.json").write_text(json.dumps(site, indent=1))
    carve_site(P, out_rgb, out_h, site)
    rgba = np.concatenate([np.clip(out_rgb, 0, 255), (np.clip(out_h, 0, 1) * 255)[:, None]], 1)
    Image.fromarray(rgba.reshape(h, w, 4).astype(np.uint8), "RGBA").save(OUT / "earth_albedo.png")
    Image.fromarray((out_c.reshape(h, w) * 255).astype(np.uint8), "L").save(OUT / "earth_clouds.png")
    return painter


def find_site(painter):
    """Coastal land at low latitude with open ocean to the east (increasing longitude):
    land at the pad, water 60 km east, deep ocean 300-1200 km east (the ascent ground track)."""
    R = 6371.0
    best = None
    for lat in np.arange(-25, 25.5, 0.5):
        lons = np.arange(-180, 180, 0.25)
        P = np.stack([pg.dir_from(lat, lo) for lo in lons])
        c0 = painter.land(P)
        ok = (c0 > 0.515) & (c0 < 0.57)
        score = np.zeros(len(lons))
        for d_km, lim in ((60, 0.505), (300, 0.48), (700, 0.47), (1200, 0.47)):
            dlon = math.degrees(d_km / (R * math.cos(math.radians(lat))))
            Q = np.stack([pg.dir_from(lat, lo + dlon) for lo in lons])
            c = painter.land(Q)
            ok &= c < lim
            score += lim - c
        dlon = math.degrees(80 / (R * math.cos(math.radians(lat))))
        W = np.stack([pg.dir_from(lat, lo - dlon) for lo in lons])
        ok &= painter.land(W) > 0.53
        s = np.where(ok, score - abs(lat) * 0.002, -1e9)
        k = int(np.argmax(s))
        if best is None or s[k] > best[0]:
            best = (s[k], float(lat), float(lons[k]))
    print(f"  launch site lat {best[1]:.2f} lon {best[2]:.2f} (score {best[0]:.3f})")
    return {"lat": best[1], "lon": best[2]}


def bake_moon(w):
    h = w // 2
    painter = pg.Rocky(body("moon"))
    P = equirect_dirs(w, h)
    hh = painter.height(P)
    rgb = painter.color(P, hh)
    Image.fromarray(np.clip(rgb, 0, 255).reshape(h, w, 3).astype(np.uint8), "RGB").save(OUT / "moon_albedo.png")


def font(size, bold=True):
    for name in (("bahnschrift.ttf",) if bold else ()) + ("segoeuib.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def bake_navball(w=2048):
    """u = 1 - heading/360 (so labels read correctly on the outside of the sphere),
    v = 0.5 - pitch/180. Sky = Mission Blue, ground = warm earth, horizon white."""
    h = w // 2
    img = Image.new("RGB", (w, h))
    px = np.zeros((h, w, 3), np.float64)
    v = (np.arange(h) + 0.5) / h
    pitch = 90 - v * 180
    sky_top, sky_hor = np.array([24, 58, 92]), np.array([78, 150, 196])
    gnd_hor, gnd_bot = np.array([150, 96, 52]), np.array([74, 46, 28])
    for j in range(h):
        t = abs(pitch[j]) / 90.0
        c = sky_hor + (sky_top - sky_hor) * t if pitch[j] >= 0 else gnd_hor + (gnd_bot - gnd_hor) * t
        px[j, :] = c
    img = Image.fromarray(px.astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    white = (238, 242, 246)

    def x_of(hd):
        return (1.0 - (hd % 360) / 360.0) * w

    def y_of(p):
        return (0.5 - p / 180.0) * h
    d.rectangle([0, y_of(0) - 3, w, y_of(0) + 3], fill=white)
    f_small, f_big = font(26), font(40)
    for p in range(-80, 90, 5):
        if p == 0:
            continue
        y = y_of(p)
        major = p % 10 == 0
        for hd in range(0, 360, 90):
            # ladder rungs centred on the cardinal headings (wider near the equator)
            half = (w / 360.0) * (14 if major else 6) / max(math.cos(math.radians(p)), 0.25) ** 0.5
            x = x_of(hd)
            col = white if p > 0 else (240, 214, 180)
            d.rectangle([x - half, y - (2 if major else 1), x + half, y + (2 if major else 1)], fill=col)
            if major and p % 30 == 0:
                for xs in (x - half - 34, x + half + 34):
                    d.text((xs, y), f"{abs(p)}", fill=col, font=f_small, anchor="mm")
    for hd in range(0, 360, 10):
        x = x_of(hd)
        big = hd % 30 == 0
        d.rectangle([x - 2, y_of(0) - (22 if big else 10), x + 2, y_of(0) + (22 if big else 10)], fill=white)
        if big:
            label = {0: "N", 90: "E", 180: "S", 270: "W"}.get(hd, f"{hd // 10:02d}")
            ff = f_big if hd % 90 == 0 else f_small
            col = (245, 154, 54) if hd % 90 == 0 else white
            d.text((x, y_of(0) - 48), label, fill=col, font=ff, anchor="mm")
            d.text((x, y_of(0) + 48), label, fill=col, font=ff, anchor="mm")
    # zenith / nadir marks
    d.ellipse([w * 0.0, -4, w, 6], fill=white)
    img.save(OUT / "navball.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    size = 2048
    if "--size" in sys.argv:
        size = int(sys.argv[sys.argv.index("--size") + 1])
    if "--site-only" in sys.argv:
        site = find_site(pg.Earth(body("earth")))
        (OUT / "earth_site.json").write_text(json.dumps(site, indent=1))
        return
    if "--navball-only" not in sys.argv:
        print("earth...")
        bake_earth(size)
        print("moon...")
        bake_moon(512)
    print("navball...")
    bake_navball()
    print("done ->", OUT)


if __name__ == "__main__":
    main()
