"""Adds the Cometworks ink outline (scenes/fx/cw_outline.tscn) as a child of every Camera3D of
the given .tscn scenes (or only the cameras named with --only Name,Name). Cameras that already
have a CwOutline child are skipped, so re-running is harmless.

Usage: python tools/add_outline_to_cameras.py [--only ShotCam,CrewCam] scenes/menu/shots/*.tscn
"""
import re
import sys

SCENE_PATH = "res://scenes/fx/cw_outline.tscn"
SCENE_ID = "cw_outline"
CAM = re.compile(r'^\[node name="([^"]+)" type="Camera3D"(?: parent="([^"]*)")?', re.M)


def add(path, only=None):
    s = open(path, encoding="utf-8").read()
    added = []
    for m in CAM.finditer(s):
        name, parent = m.group(1), m.group(2)
        if only and name not in only:
            continue
        if parent is None:
            cam_path = "."
        elif parent == ".":
            cam_path = name
        else:
            cam_path = parent + "/" + name
        if '[node name="CwOutline" parent="%s"' % cam_path in s:
            continue
        added.append(cam_path)
    if not added:
        return []
    if 'id="%s"' % SCENE_ID not in s:
        lines = s.split("\n")
        idx = max([i for i, l in enumerate(lines) if l.startswith("[ext_resource")] or [0])
        lines.insert(idx + 1, '[ext_resource type="PackedScene" path="%s" id="%s"]' % (SCENE_PATH, SCENE_ID))
        s = "\n".join(lines)
    s = s.rstrip("\n") + "\n"
    for cam_path in added:
        s += '\n[node name="CwOutline" parent="%s" instance=ExtResource("%s")]\n' % (cam_path, SCENE_ID)
    open(path, "w", encoding="utf-8", newline="\n").write(s)
    return added


if __name__ == "__main__":
    args = sys.argv[1:]
    only = None
    if args and args[0] == "--only":
        only = set(args[1].split(","))
        args = args[2:]
    for p in args:
        for c in add(p, only):
            print("%s: %s" % (p, c))
