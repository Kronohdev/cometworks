"""Writes the rover builder's voxel part scenes (scenes/rover/parts/*.tscn) and their toon
materials (scenes/rover/materials/*.tres).

The .tscn files are the source of truth once written: open them in the editor and tweak them
there. Re-running this script overwrites them, so only run it to start over (or after editing
the shapes below). Run from the repo root:  python tools/gen_rover_parts.py

Frame: forward is -Z, up is +Y, the origin of a chassis is on the ground under its centre.
Chassis carry Marker3D mounts under "Mounts" (Power, Back, Belly, Mast, Front, SideL, SideR,
Deck, Antenna) where RoverDesign.assemble() puts the parts; animated nodes are named Wheel*,
Leg*, Thruster*, Head, Bit, Spinner, Rotor*, Dish, Arm*.
"""
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS = os.path.join(ROOT, "scenes", "rover", "parts")
MATS = os.path.join(ROOT, "scenes", "rover", "materials")

# name -> (albedo hex, emission hex or None, emission energy, roughness, metallic)
MATERIALS = {
    "body": ("#fff6e6", None, 0.0, 0.85, 0.0),
    "accent": ("#ff9a5c", None, 0.0, 0.8, 0.0),
    "ignition": ("#e5651c", None, 0.0, 0.8, 0.0),
    "dark": ("#3b3a6b", None, 0.0, 0.9, 0.0),
    "tire": ("#4a4870", None, 0.0, 0.95, 0.0),
    "metal": ("#c9c4d8", None, 0.0, 0.5, 0.4),
    "gold": ("#ffd25c", None, 0.0, 0.45, 0.5),
    "solar": ("#3550b8", "#2f78cc", 0.25, 0.3, 0.2),
    "lens": ("#7cc8ff", "#7cc8ff", 1.2, 0.2, 0.0),
    "mint": ("#6fe0be", "#6fe0be", 0.9, 0.6, 0.0),
    "lilac": ("#b39cff", None, 0.0, 0.8, 0.0),
    "flame": ("#ffd25c", "#ff9a5c", 3.0, 0.9, 0.0),
}


def rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "x":
        return [[1, 0, 0], [0, c, -s], [0, s, c]]
    if axis == "y":
        return [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def basis(rots):
    m = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    for axis, deg in rots:
        m = mul(m, rot(axis, deg))
    return m


def f(v):
    r = round(v, 4)
    if abs(r) < 1e-6:
        r = 0.0
    s = ("%.4f" % r).rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def xform(pos, rots=()):
    b = basis(rots)
    vals = [b[0][0], b[0][1], b[0][2], b[1][0], b[1][1], b[1][2], b[2][0], b[2][1], b[2][2], pos[0], pos[1], pos[2]]
    return "Transform3D(%s)" % ", ".join(f(v) for v in vals)


class Scene:
    def __init__(self, name, root_type="Node3D"):
        self.name = name
        self.root_type = root_type
        self.meshes = {}
        self.mats = []
        self.nodes = []  # (name, type, parent, props)

    def _mesh(self, kind, dims):
        key = (kind,) + tuple(round(d, 4) for d in dims)
        if key not in self.meshes:
            self.meshes[key] = "%s_%d" % (kind, len(self.meshes) + 1)
        return self.meshes[key]

    def _mat(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return "m_" + m

    def group(self, name, parent=".", pos=(0, 0, 0), rots=()):
        props = {}
        if any(pos) or rots:
            props["transform"] = xform(pos, rots)
        self.nodes.append((name, "Node3D", parent, props))
        return name if parent == "." else parent + "/" + name

    def marker(self, name, parent, pos, rots=()):
        self.nodes.append((name, "Marker3D", parent, {"transform": xform(pos, rots), "gizmo_extents": "0.25"}))

    def box(self, name, size, pos, mat, parent=".", rots=()):
        mid = self._mesh("Box", size)
        props = {"transform": xform(pos, rots), "mesh": 'SubResource("%s")' % mid,
                 "surface_material_override/0": 'ExtResource("%s")' % self._mat(mat)}
        self.nodes.append((name, "MeshInstance3D", parent, props))

    def cyl(self, name, radius, height, pos, mat, parent=".", rots=(), segs=8, top=None):
        mid = self._mesh("Cyl", (radius, height, segs, top if top is not None else radius))
        props = {"transform": xform(pos, rots), "mesh": 'SubResource("%s")' % mid,
                 "surface_material_override/0": 'ExtResource("%s")' % self._mat(mat)}
        self.nodes.append((name, "MeshInstance3D", parent, props))

    def write(self, path):
        out = ["[gd_scene format=3]", ""]
        for m in self.mats:
            out.append('[ext_resource type="Material" path="res://scenes/rover/materials/%s.tres" id="m_%s"]' % (m, m))
        out.append("")
        for key, mid in self.meshes.items():
            if key[0] == "Box":
                out.append('[sub_resource type="BoxMesh" id="%s"]' % mid)
                out.append("size = Vector3(%s, %s, %s)" % (f(key[1]), f(key[2]), f(key[3])))
            else:
                out.append('[sub_resource type="CylinderMesh" id="%s"]' % mid)
                out.append("top_radius = %s" % f(key[4]))
                out.append("bottom_radius = %s" % f(key[1]))
                out.append("height = %s" % f(key[2]))
                out.append("radial_segments = %d" % int(key[3]))
                out.append("rings = 1")
            out.append("")
        out.append('[node name="%s" type="%s"]' % (self.name, self.root_type))
        out.append("")
        for name, typ, parent, props in self.nodes:
            out.append('[node name="%s" type="%s" parent="%s"]' % (name, typ, parent))
            for k, v in props.items():
                out.append("%s = %s" % (k, v))
            out.append("")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(out).rstrip() + "\n")


def write_materials():
    os.makedirs(MATS, exist_ok=True)
    for name, (alb, emi, energy, rough, metal) in MATERIALS.items():
        lines = ['[gd_resource type="ShaderMaterial" format=3]', "",
                 '[ext_resource type="Shader" path="res://shaders/cw_toon_solid.gdshader" id="1_toon"]', "",
                 "[resource]", "render_priority = 0", 'shader = ExtResource("1_toon")',
                 "shader_parameter/albedo = Color(%s)" % col(alb),
                 "shader_parameter/roughness = %s" % f(rough),
                 "shader_parameter/metallic = %s" % f(metal)]
        if emi:
            lines.append("shader_parameter/emission = Color(%s)" % col(emi))
            lines.append("shader_parameter/emission_energy = %s" % f(energy))
        with open(os.path.join(MATS, name + ".tres"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")


def col(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return "%s, %s, %s, 1" % (f(r), f(g), f(b))


# ------------------------------------------------------------ chassis
def mounts(s, top, length, width, mast_x=-0.32):
    g = s.group("Mounts")
    half_l = length / 2.0
    half_w = width / 2.0
    s.marker("Power", g, (0, top, half_l * 0.35))
    s.marker("Back", g, (0, top - 0.2, half_l + 0.02))
    s.marker("Belly", g, (0, top - 0.42, 0.1))
    s.marker("Mast", g, (mast_x, top, -half_l * 0.6))
    s.marker("Front", g, (0, top - 0.25, -half_l - 0.02))
    s.marker("SideL", g, (-half_w - 0.02, top - 0.18, -0.1))
    s.marker("SideR", g, (half_w + 0.02, top - 0.18, -0.1))
    s.marker("Deck", g, (0.3, top, -half_l * 0.15))
    s.marker("Antenna", g, (half_w * 0.6, top, half_l * 0.75))


def wheel(s, name, pos, radius=0.38, width=0.3, side=1):
    g = s.group(name, ".", pos)
    s.cyl("Tire", radius, width, (0, 0, 0), "tire", g, rots=(("z", 90),), segs=10)
    s.cyl("Hub", radius * 0.45, width + 0.04, (0, 0, 0), "metal", g, rots=(("z", 90),), segs=8)
    # voxel treads: little blocks so the spin reads
    for i in range(5):
        a = i * 72.0
        y = math.cos(math.radians(a)) * radius
        z = math.sin(math.radians(a)) * radius
        s.box("Tread%d" % i, (width + 0.02, 0.09, 0.16), (0, y, z), "dark", g, rots=(("x", -a),))


def face(s, top, front_z):
    s.box("Visor", (0.86, 0.2, 0.06), (0, top - 0.17, front_z - 0.01), "dark")
    s.cyl("EyeL", 0.075, 0.05, (-0.2, top - 0.17, front_z - 0.05), "lens", rots=(("x", 90),), segs=8)
    s.cyl("EyeR", 0.075, 0.05, (0.2, top - 0.17, front_z - 0.05), "lens", rots=(("x", 90),), segs=8)


def chassis_wheels(name, n_axles, length, width):
    s = Scene(name)
    body_y = 0.78
    s.box("Body", (width, 0.42, length), (0, body_y, 0), "body")
    s.box("Deck", (width - 0.12, 0.06, length - 0.12), (0, body_y + 0.24, 0), "metal")
    s.box("Stripe", (width + 0.02, 0.08, length * 0.7), (0, body_y + 0.05, 0), "accent")
    s.box("Belly", (width - 0.2, 0.12, length - 0.3), (0, body_y - 0.26, 0), "dark")
    face(s, body_y + 0.21, -length / 2.0)
    tw = width / 2.0 + 0.22
    zs = [(-length / 2.0 + 0.32) + i * (length - 0.64) / max(n_axles - 1, 1) for i in range(n_axles)]
    k = 1
    for z in zs:
        for side in (-1, 1):
            s.box("Strut%d" % k, (0.12, 0.3, 0.12), (side * (width / 2.0 + 0.06), 0.56, z), "metal",
                  rots=(("z", side * -20),))
            wheel(s, "Wheel%d" % k, (side * tw, 0.38, z), side=side)
            k += 1
    if n_axles == 3:
        for side in (-1, 1):
            s.box("Rocker%s" % ("L" if side < 0 else "R"), (0.1, 0.1, length - 0.5), (side * (width / 2.0 + 0.08), 0.66, 0),
                  "accent")
    mounts(s, body_y + 0.27, length, width)
    return s


def chassis_walker():
    s = Scene("ChassisWalker")
    body_y = 1.15
    length, width = 2.0, 1.2
    s.box("Body", (width, 0.46, length), (0, body_y, 0), "body")
    s.box("Deck", (width - 0.12, 0.06, length - 0.12), (0, body_y + 0.26, 0), "metal")
    s.box("Stripe", (width + 0.02, 0.08, length * 0.7), (0, body_y + 0.05, 0), "lilac")
    s.box("Belly", (width - 0.2, 0.12, length - 0.3), (0, body_y - 0.28, 0), "dark")
    face(s, body_y + 0.23, -length / 2.0)
    k = 1
    for z in (-0.7, 0.0, 0.7):
        for side in (-1, 1):
            g = s.group("Leg%d" % k, ".", (side * (width / 2.0 + 0.05), body_y - 0.05, z))
            s.box("Hip", (0.2, 0.2, 0.2), (0, 0, 0), "accent", g)
            s.box("Upper", (0.6, 0.12, 0.14), (side * 0.32, 0.12, 0), "metal", g, rots=(("z", side * 25),))
            s.box("Lower", (0.12, 0.9, 0.14), (side * 0.62, -0.42, 0), "metal", g)
            s.box("Foot", (0.26, 0.1, 0.3), (side * 0.62, -0.92, 0), "tire", g)
            k += 1
    mounts(s, body_y + 0.29, length, width)
    return s


def chassis_hopper():
    s = Scene("ChassisHopper")
    body_y = 0.95
    length, width = 1.6, 1.4
    s.cyl("Body", 0.8, 0.5, (0, body_y, 0), "body", segs=8)
    s.box("Deck", (1.1, 0.06, 1.1), (0, body_y + 0.27, 0), "metal")
    s.cyl("Band", 0.82, 0.1, (0, body_y + 0.05, 0), "gold", segs=8)
    s.cyl("Base", 0.6, 0.14, (0, body_y - 0.3, 0), "dark", segs=8)
    face(s, body_y + 0.2, -0.78)
    for i, (x, z) in enumerate([(-0.75, -0.75), (0.75, -0.75), (-0.75, 0.75), (0.75, 0.75)]):
        s.box("LegStrut%d" % (i + 1), (0.1, 0.9, 0.1), (x * 0.85, 0.5, z * 0.85), "metal",
              rots=(("x", 18 if z > 0 else -18), ("z", -18 if x > 0 else 18)))
        s.cyl("Pad%d" % (i + 1), 0.18, 0.06, (x, 0.05, z), "dark", segs=8)
    for i, (x, z) in enumerate([(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)]):
        g = s.group("Thruster%d" % (i + 1), ".", (x, body_y - 0.42, z))
        s.cyl("Bell", 0.08, 0.2, (0, 0, 0), "dark", g, segs=8, top=0.04)
        s.cyl("Flame", 0.05, 0.6, (0, -0.4, 0), "flame", g, segs=6, top=0.09)
    k = 1
    for x in (-0.55, 0.55):
        for z in (-0.4, 0.4):
            wheel(s, "Wheel%d" % k, (x, 0.18, z), radius=0.18, width=0.12)
            k += 1
    mounts(s, body_y + 0.3, length, width)
    return s


# ------------------------------------------------------------ parts
def part_solar_small():
    s = Scene("SolarSmall")
    s.box("Post", (0.08, 0.2, 0.08), (0, 0.1, 0), "metal")
    s.box("Frame", (1.0, 0.05, 0.8), (0, 0.22, 0), "metal", rots=(("x", -12),))
    s.box("Cells", (0.92, 0.06, 0.72), (0, 0.23, 0), "solar", rots=(("x", -12),))
    return s


def part_solar_wing():
    s = Scene("SolarWing")
    s.box("Post", (0.1, 0.35, 0.1), (0, 0.17, 0), "metal")
    s.box("Spar", (2.6, 0.06, 0.08), (0, 0.36, 0), "metal")
    for side in (-1, 1):
        g = s.group("Wing%s" % ("L" if side < 0 else "R"), ".", (side * 0.75, 0.38, 0))
        s.box("Frame", (1.05, 0.04, 0.9), (0, 0, 0), "metal", g)
        s.box("Cells", (0.97, 0.05, 0.82), (0, 0.005, 0), "solar", g)
    return s


def part_rtg():
    s = Scene("Rtg")
    s.box("Mount", (0.3, 0.1, 0.3), (0, 0.05, 0.12), "gold")
    s.cyl("Core", 0.16, 0.7, (0, 0.3, 0.32), "dark", rots=(("x", 60),), segs=8)
    for i in range(4):
        a = i * 90 + 45
        s.box("Fin%d" % i, (0.05, 0.6, 0.28), (0, 0.3, 0.32), "metal", rots=(("x", 60), ("y", a)))
    s.cyl("Glow", 0.07, 0.72, (0, 0.3, 0.32), "flame", rots=(("x", 60),), segs=6)
    return s


def part_battery(big):
    s = Scene("BatteryL" if big else "Battery")
    w, h, l = (0.8, 0.22, 0.8) if big else (0.55, 0.16, 0.5)
    s.box("Box", (w, h, l), (0, -h / 2.0, 0), "dark")
    s.box("Charge", (w * 0.7, 0.04, 0.06), (0, -h / 2.0, -l / 2.0 - 0.01), "mint")
    return s


def part_camera_mast():
    s = Scene("CameraMast")
    s.box("Pole", (0.09, 0.9, 0.09), (0, 0.45, 0), "metal")
    g = s.group("Head", ".", (0, 0.95, 0))
    s.box("Box", (0.42, 0.22, 0.24), (0, 0, 0), "body", g)
    s.box("Brow", (0.44, 0.05, 0.26), (0, 0.13, 0), "accent", g)
    s.cyl("LensL", 0.065, 0.1, (-0.1, 0, -0.14), "lens", g, rots=(("x", 90),))
    s.cyl("LensR", 0.065, 0.1, (0.1, 0, -0.14), "lens", g, rots=(("x", 90),))
    return s


def part_spectrometer():
    s = Scene("Spectrometer")
    s.box("Box", (0.22, 0.3, 0.4), (0, 0, 0), "gold")
    s.cyl("Tube", 0.07, 0.3, (0, 0.05, -0.32), "dark", rots=(("x", 90),))
    s.cyl("Lens", 0.05, 0.04, (0, 0.05, -0.48), "lens", rots=(("x", 90),))
    return s


def part_drill():
    s = Scene("Drill")
    s.box("Frame", (0.3, 0.5, 0.18), (0, -0.05, -0.1), "metal")
    s.box("Motor", (0.26, 0.2, 0.24), (0, 0.15, -0.12), "ignition")
    g = s.group("Bit", ".", (0, -0.1, -0.12))
    s.cyl("Shaft", 0.05, 0.7, (0, -0.3, 0), "metal", g, segs=6)
    s.cyl("Tip", 0.05, 0.16, (0, -0.72, 0), "dark", g, segs=6, top=0.0)
    return s


def part_arm():
    s = Scene("Arm")
    s.box("Shoulder", (0.22, 0.22, 0.22), (0, 0, 0), "accent")
    g = s.group("ArmUpper", ".", (0, 0, -0.1), rots=(("x", -35),))
    s.box("Bone", (0.1, 0.1, 0.6), (0, 0, -0.3), "metal", g)
    g2 = s.group("ArmLower", g, (0, 0, -0.6), rots=(("x", 80),))
    s.box("Bone", (0.09, 0.09, 0.5), (0, 0, -0.25), "metal", g2)
    s.box("Scoop", (0.2, 0.12, 0.16), (0, 0, -0.55), "dark", g2)
    return s


def part_weather():
    s = Scene("WeatherStation")
    s.box("Pole", (0.05, 0.7, 0.05), (0, 0.35, 0), "metal")
    s.box("Sensor", (0.14, 0.14, 0.14), (0, 0.45, 0), "body")
    g = s.group("Spinner", ".", (0, 0.72, 0))
    for i in range(3):
        a = i * 120
        s.box("Spoke%d" % i, (0.24, 0.03, 0.03), (0, 0, 0), "metal", g, rots=(("y", a),))
        x = math.cos(math.radians(a)) * 0.13
        z = -math.sin(math.radians(a)) * 0.13
        s.box("Cup%d" % i, (0.06, 0.06, 0.06), (x, 0, z), "accent", g)
    return s


def part_sample_cache():
    s = Scene("SampleCache")
    s.box("Box", (0.5, 0.26, 0.3), (0, 0.0, 0.08), "lilac")
    s.box("Lid", (0.52, 0.05, 0.32), (0, 0.15, 0.08), "body")
    for i in range(4):
        s.cyl("Tube%d" % i, 0.035, 0.05, (-0.18 + i * 0.12, 0.19, 0.08), "metal", segs=6)
    return s


def part_drone():
    s = Scene("Drone")
    s.box("Pad", (0.5, 0.03, 0.5), (0, 0.015, 0), "dark")
    g = s.group("Craft", ".", (0, 0.05, 0))
    s.box("Body", (0.18, 0.14, 0.18), (0, 0.12, 0), "gold", g)
    for i, (x, z) in enumerate([(-0.12, -0.12), (0.12, -0.12), (-0.12, 0.12), (0.12, 0.12)]):
        s.box("Leg%d" % i, (0.02, 0.12, 0.02), (x, 0.04, z), "metal", g)
    s.box("Mast", (0.03, 0.22, 0.03), (0, 0.3, 0), "metal", g)
    r1 = s.group("Rotor1", g, (0, 0.34, 0))
    s.box("Blade", (0.7, 0.015, 0.06), (0, 0, 0), "body", r1)
    r2 = s.group("Rotor2", g, (0, 0.4, 0), rots=(("y", 90),))
    s.box("Blade", (0.7, 0.015, 0.06), (0, 0, 0), "body", r2)
    s.box("Panel", (0.16, 0.02, 0.12), (0, 0.42, 0), "solar", g)
    return s


def part_antenna(kind):
    names = {"beacon": "AntennaBeacon", "omni": "AntennaOmni", "hga": "AntennaHga"}
    s = Scene(names[kind])
    if kind == "beacon":
        s.box("Base", (0.1, 0.06, 0.1), (0, 0.03, 0), "dark")
        s.box("Whip", (0.025, 0.6, 0.025), (0, 0.33, 0), "metal")
        s.box("Tip", (0.06, 0.06, 0.06), (0, 0.65, 0), "accent")
    elif kind == "omni":
        s.box("Pole", (0.06, 0.7, 0.06), (0, 0.35, 0), "metal")
        s.cyl("Ball", 0.1, 0.16, (0, 0.76, 0), "body", segs=8)
        s.box("Ring", (0.3, 0.03, 0.03), (0, 0.6, 0), "gold")
    else:
        s.box("Pole", (0.07, 0.5, 0.07), (0, 0.25, 0), "metal")
        g = s.group("Dish", ".", (0, 0.55, 0), rots=(("x", 55),))
        s.cyl("Bowl", 0.36, 0.06, (0, 0, 0), "body", g, segs=10, top=0.4)
        s.cyl("Feed", 0.03, 0.26, (0, 0.14, 0), "gold", g, segs=6)
    return s


def objective_marker():
    s = Scene("ObjectiveMarker")
    s.cyl("Base", 0.5, 0.2, (0, 0.1, 0), "dark", segs=8)
    s.box("Pole", (0.1, 2.6, 0.1), (0, 1.4, 0), "metal")
    s.box("Flag", (0.8, 0.5, 0.05), (0.42, 2.4, 0), "accent")
    s.box("Star", (0.22, 0.22, 0.22), (0, 2.85, 0), "mint", rots=(("y", 45), ("x", 45)))
    s.cyl("Ring", 1.2, 0.06, (0, 0.04, 0), "mint", segs=12)
    return s


def main():
    write_materials()
    os.makedirs(PARTS, exist_ok=True)
    scenes = {
        "chassis_wheels4": chassis_wheels("ChassisWheels4", 2, 2.0, 1.2),
        "chassis_wheels6": chassis_wheels("ChassisWheels6", 3, 2.6, 1.3),
        "chassis_walker": chassis_walker(),
        "chassis_hopper": chassis_hopper(),
        "solar_small": part_solar_small(),
        "solar_wing": part_solar_wing(),
        "rtg": part_rtg(),
        "battery": part_battery(False),
        "battery_l": part_battery(True),
        "camera_mast": part_camera_mast(),
        "spectrometer": part_spectrometer(),
        "drill": part_drill(),
        "arm": part_arm(),
        "weather_station": part_weather(),
        "sample_cache": part_sample_cache(),
        "drone": part_drone(),
        "antenna_beacon": part_antenna("beacon"),
        "antenna_omni": part_antenna("omni"),
        "antenna_hga": part_antenna("hga"),
        "objective_marker_model": objective_marker(),
    }
    for name, sc in scenes.items():
        sc.write(os.path.join(PARTS, name + ".tscn"))
    print("wrote %d part scenes and %d materials" % (len(scenes), len(MATERIALS)))


if __name__ == "__main__":
    main()
