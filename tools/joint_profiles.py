"""Joint profiles of the voxel part models -> data/part_joints.json.

A part's top/bottom attach node sits on its bounding box, but many models only reach
their full body there with pegs, antennas, feed lines or a dome; the solid body face is
lower. For each end this finds the outermost horizontal face that covers at least
COVER of the part's footprint (cumulative from the end inwards) and records:

    top_gap / bottom_gap   distance from the node plane to that solid face (m)
    top_r / bottom_r       radius of that face (m)
    top_detail / ...       footprint share covered by the faces beyond it (small for
                           pegs and antennas, large for cones, domes and nozzles)

The hangar's JointDecor fills the gap between two stacked parts with a junction block,
so stacks look solid instead of resting on the tips of their details.

Usage: python tools/joint_profiles.py
"""
import json
import math
import os
import struct
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS_DIR = os.path.join(ROOT, "assets", "voxel", "parts")
OUT = os.path.join(ROOT, "data", "part_joints.json")
COVER = 0.5      # fraction of the footprint the solid face must cover
MIN_GAP = 0.02   # smaller gaps are recorded as 0

_CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
_NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    """Positions and triangle indices of every mesh primitive in a GLB (model space)."""
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jlen])
    bin_off = 20 + jlen + 8
    blob = data[bin_off:]

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        dt = _CT[a["componentType"]]
        n = a["count"] * _NC[a["type"]]
        start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        arr = np.frombuffer(blob, dt, n, start)
        return arr.reshape(a["count"], _NC[a["type"]]) if _NC[a["type"]] > 1 else arr

    pos_all, idx_all, base = [], [], 0
    for m in j["meshes"]:
        for pr in m["primitives"]:
            p = acc(pr["attributes"]["POSITION"]).astype(np.float64)
            ix = acc(pr["indices"]).astype(np.int64) if "indices" in pr else np.arange(len(p))
            pos_all.append(p)
            idx_all.append(ix + base)
            base += len(p)
    return np.concatenate(pos_all), np.concatenate(idx_all).reshape(-1, 3)


def end_profile(pos, tris, top):
    v0, v1, v2 = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    cr = np.cross(v1 - v0, v2 - v0)
    area = np.linalg.norm(cr, axis=1) * 0.5
    ny = cr[:, 1] / np.maximum(area * 2.0, 1e-12)
    face = ny > 0.9 if top else ny < -0.9
    lo, hi = pos.min(0), pos.max(0)
    footprint = math.pi * 0.25 * (hi[0] - lo[0]) * (hi[2] - lo[2])
    ys = np.round(v0[face, 1], 3)
    a = area[face]
    levels = np.unique(ys)[::-1] if top else np.unique(ys)
    acc = 0.0
    end_y = hi[1] if top else lo[1]
    for y in levels:
        level_area = a[ys == y].sum()
        if acc + level_area >= COVER * footprint:
            sel = tris[face][ys == y].ravel()
            r = float(np.sqrt(pos[sel, 0] ** 2 + pos[sel, 2] ** 2).max())
            gap = float(abs(end_y - y))
            # detail: footprint share of the faces beyond the solid face. Pegs and antennas
            # are small (< ~0.15); a tapering body (cone, dome, nozzle) is large.
            return (0.0 if gap < MIN_GAP else round(gap, 3)), round(r, 3), round(acc / footprint, 3)
        acc += level_area
    return 0.0, round(float(min(hi[0] - lo[0], hi[2] - lo[2]) * 0.5), 3), 0.0


def main():
    out = {}
    for f in sorted(os.listdir(PARTS_DIR)):
        if not f.endswith(".glb"):
            continue
        pos, tris = read_glb(os.path.join(PARTS_DIR, f))
        tg, tr, td = end_profile(pos, tris, True)
        bg, br, bd = end_profile(pos, tris, False)
        out[f[:-4]] = {"top_gap": tg, "top_r": tr, "top_detail": td,
                       "bottom_gap": bg, "bottom_r": br, "bottom_detail": bd}
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
    gaps = {k: v for k, v in out.items() if v["top_gap"] or v["bottom_gap"]}
    print(f"{len(out)} parts, {len(gaps)} with gaps -> {OUT}")
    if "-v" in sys.argv:
        for k, v in gaps.items():
            print(f"  {k:32s} top {v['top_gap']:.3f} (r {v['top_r']:.2f} d {v['top_detail']:.2f})"
                  f"  bottom {v['bottom_gap']:.3f} (r {v['bottom_r']:.2f} d {v['bottom_detail']:.2f})")


if __name__ == "__main__":
    main()
