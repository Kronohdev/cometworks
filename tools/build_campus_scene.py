"""Writes the Cometworks campus (GDD section 11): a modular map that grows as the player
buys lots and buildings, and changes look with each era.

  scenes/tycoon/campus.tscn                 terrain (plateau, terraces, sea, distant hills),
                                            sky with the comet Mãe-Gelo, roads + plaza, the
                                            lots (Lots/<lot id>, Marker3D with metadata), trees,
                                            lamps, plaza walk spots. src/tycoon/campus.gd places
                                            the buildings on the lots from TycoonState.
  scenes/tycoon/buildings/<type>.tscn       one scene per building type, written by
                                            tools/build_campus_buildings.py (voxel models with
                                            decorated interiors and a cutaway; see there).

1 unit = 1 m.

Usage: python tools/build_campus_scene.py
"""
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_CAMPUS = ROOT / "scenes" / "tycoon" / "campus.tscn"
OUT_BUILD = ROOT / "scenes" / "tycoon" / "buildings"

# --------------------------------------------------------------- materials
BASE_COL = {
    "ground": "#34503f", "ground_lo": "#29402f", "cliff": "#161f27", "sand": "#4a4a46",
    "lot": "#3a4d72", "lamp_pole": "#2b3445", "leaf": "#2f5a4a", "leaf2": "#3c6b55", "leaf3": "#25493f",
    "trunk": "#5a4636", "rock": "#4a5462", "rock2": "#3b4452", "hill": "#121a28", "hill2": "#0e1522",
    "steel": "#55607a", "concrete": "#7d8696", "door": "#141b29", "rocket": "#e9eef7", "nose": "#ff8a3d",
    "scaffold": "#c9a227", "tarp": "#3f6f9a", "crate": "#6b5440", "dark": "#1b2433",
}
EMIT = {
    "lamp": ("#ffd29a", 3.0), "beacon": ("#ff5c6c", 3.0), "lot_led": ("#3fe0c5", 1.6),
    "sign": ("#bfe8ff", 1.5), "win_warm": ("#ffb46b", 2.4), "win_cool": ("#bfe8ff", 1.8),
    "led_teal": ("#3fe0c5", 2.6), "led_violet": ("#8e7cff", 2.6), "green": ("#7ee08a", 1.4),
    "screen": ("#3fe0c5", 1.4),
}


def hexc(h, a=1.0):
    h = h.lstrip("#")
    return "Color(%.4f, %.4f, %.4f, %.3f)" % (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


def xform(x, y, z, yaw=0.0, s=1.0):
    c, sn = math.cos(yaw) * s, math.sin(yaw) * s
    return f"Transform3D({c:.5f}, 0, {-sn:.5f}, 0, {s}, 0, {sn:.5f}, 0, {c:.5f}, {x:.3f}, {y:.3f}, {z:.3f})"


class SceneWriter:
    """Accumulates sub-resources and nodes of one .tscn."""

    def __init__(self):
        self.ext = []
        self.subs = []
        self.nodes = []
        self._box = {}
        self._mat = {}
        self._cyl = {}
        self._names = {}

    def mat(self, key):
        """key: a BASE_COL / EMIT name, or a '#rrggbb' colour."""
        if key in self._mat:
            return self._mat[key]
        mid = f"m{len(self._mat)}"
        if key in EMIT:
            c, e = EMIT[key]
            self.subs.append(f'[sub_resource type="StandardMaterial3D" id="{mid}"]\nalbedo_color = {hexc(c)}\n'
                             f'emission_enabled = true\nemission = {hexc(c)}\nemission_energy_multiplier = {e}')
        else:
            col = key if key.startswith("#") else BASE_COL[key]
            rough, metal = 0.9, 0.0
            if key in ("steel", "rocket"):
                rough, metal = 0.5, 0.35
            self.subs.append(f'[sub_resource type="StandardMaterial3D" id="{mid}"]\nalbedo_color = {hexc(col)}\n'
                             f'roughness = {rough}\nmetallic = {metal}')
        self._mat[key] = mid
        return mid

    def uniq(self, parent, name):
        k = (parent, name)
        self._names[k] = self._names.get(k, 0) + 1
        return name if self._names[k] == 1 else f"{name}{self._names[k]}"

    def group(self, name, parent=".", pos=None, yaw=0.0, extra=""):
        n = self.uniq(parent, name)
        line = f'[node name="{n}" type="Node3D" parent="{parent}"]'
        if pos is not None:
            line += f"\ntransform = {xform(*pos, yaw)}"
        if extra:
            line += "\n" + extra
        self.nodes.append(line)
        return n if parent == "." else f"{parent}/{n}"

    def box(self, parent, name, size, pos, material, yaw=0.0, shadow=True):
        sx, sy, sz = (round(v, 3) for v in size)
        key = (sx, sy, sz)
        if key not in self._box:
            bid = f"b{len(self._box)}"
            self.subs.append(f'[sub_resource type="BoxMesh" id="{bid}"]\nsize = Vector3({sx}, {sy}, {sz})')
            self._box[key] = bid
        x, y, z = pos
        lines = [f'[node name="{self.uniq(parent, name)}" type="MeshInstance3D" parent="{parent}"]',
                 f"transform = {xform(x, y + sy / 2, z, yaw)}", f'mesh = SubResource("{self._box[key]}")',
                 f'surface_material_override/0 = SubResource("{self.mat(material)}")']
        if not shadow:
            lines.append("cast_shadow = 0")
        self.nodes.append("\n".join(lines))

    def cyl(self, parent, name, radius, height, pos, material, top=None, sides=12):
        top = radius if top is None else top
        key = (radius, top, height, sides)
        if key not in self._cyl:
            cid = f"c{len(self._cyl)}"
            self.subs.append(f'[sub_resource type="CylinderMesh" id="{cid}"]\ntop_radius = {top}\nbottom_radius = {radius}\n'
                             f'height = {height}\nradial_segments = {sides}\nrings = 1')
            self._cyl[key] = cid
        x, y, z = pos
        self.nodes.append(f'[node name="{self.uniq(parent, name)}" type="MeshInstance3D" parent="{parent}"]\n'
                          f"transform = {xform(x, y + height / 2, z)}\nmesh = SubResource(\"{self._cyl[key]}\")\n"
                          f'surface_material_override/0 = SubResource("{self.mat(material)}")')

    def omni(self, parent, name, pos, color, energy, rng, shadow=False):
        self.nodes.append(f'[node name="{self.uniq(parent, name)}" type="OmniLight3D" parent="{parent}"]\n'
                          f"transform = {xform(*pos)}\nlight_color = {hexc(color)}\nlight_energy = {energy}\n"
                          f"omni_range = {rng}\nomni_attenuation = 1.4" + ("\nshadow_enabled = true" if shadow else ""))

    def marker(self, parent, name, pos, meta, yaw=0.0):
        lines = [f'[node name="{self.uniq(parent, name)}" type="Marker3D" parent="{parent}"]',
                 f"transform = {xform(*pos, yaw)}"]
        for k, v in meta.items():
            lines.append(f"metadata/{k} = {v}")
        self.nodes.append("\n".join(lines))

    def write(self, path, root_line):
        head = f"[gd_scene load_steps={len(self.ext) + len(self.subs) + 1} format=3]\n\n"
        body = "\n".join(self.ext) + ("\n\n" if self.ext else "") + "\n\n".join(self.subs) + "\n\n" + root_line + \
            "\n\n" + "\n\n".join(self.nodes) + "\n"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(head + body, encoding="utf-8", newline="\n")


# --------------------------------------------------------------- walk spots
def spot(w, g, name, pos, action, door_pos, yaw=0.0):
    w.marker(g, name, pos, {"action": f'"{action}"', "door": f"Vector3({door_pos[0]}, 0, {door_pos[1]})"}, yaw)


# --------------------------------------------------------------- campus
# lots: id, centre (x, z), size (w, d), building type, facing (0 = door +z towards the road at
# z = 2 from the north side; pi = south side). Lots with "start" hold a level-1 building.
LOTS = [
    ("hq", (-16, -13), (18, 13), "hq", 0.0, True),
    ("workshop", (16, -14), (26, 17), "workshop", 0.0, True),
    ("pad", (38, 20), (17, 17), "pad", math.pi, True),
    ("lab", (-17, 17), (20, 13), "lab", math.pi, False),
    ("control", (14, 17), (16, 12), "control", math.pi, False),
    ("antenna", (-43, -13), (15, 15), "antenna", 0.0, False),
    ("factory", (-43, 17), (22, 13), "factory", math.pi, False),
    ("training", (43, -13), (16, 13), "training", 0.0, False),
    ("pad2", (60, 20), (17, 17), "pad", math.pi, False),
]


def tree(w, g, x, z, rng):
    h = rng.uniform(2.6, 4.6)
    w.box(g, "Trunk", (0.45, h * 0.4, 0.45), (x, 0, z), "trunk")
    leaf = rng.choice(("leaf", "leaf2", "leaf3"))
    s = rng.uniform(1.8, 2.8)
    w.box(g, "Leaves", (s, h * 0.45, s), (x, h * 0.35, z), leaf, yaw=rng.uniform(0, 1.5))
    w.box(g, "Leaves", (s * 0.6, h * 0.35, s * 0.6), (x, h * 0.78, z), leaf, yaw=rng.uniform(0, 1.5))


def lamp(w, g, x, z):
    w.box(g, "LampPole", (0.18, 4.2, 0.18), (x, 0, z), "lamp_pole")
    w.box(g, "LampHead", (0.7, 0.18, 0.4), (x, 4.2, z), "lamp", shadow=False)
    w.omni(g, "LampLight", (x, 3.9, z), "#ffd29a", 1.2, 9)


def in_lot(x, z, margin):
    return any(abs(x - cx) < lw / 2 + margin and abs(z - cz) < ld / 2 + margin for _, (cx, cz), (lw, ld), *_ in LOTS)


def build_campus():
    w = SceneWriter()
    w.ext.append('[ext_resource type="Script" path="res://src/tycoon/campus.gd" id="1_campus"]')
    w.ext.append('[ext_resource type="PackedScene" path="res://scenes/tycoon/campus_cometling.tscn" id="2_cl"]')
    # environment: dusk sky, ssao, glow, light fog
    w.subs.append('[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]\n'
                  f'sky_top_color = {hexc("#0a1530")}\nsky_horizon_color = {hexc("#4a5a8a")}\nsky_curve = 0.12\n'
                  f'ground_bottom_color = {hexc("#05080f")}\nground_horizon_color = {hexc("#24304c")}\n'
                  'sun_angle_max = 14.0\nsun_curve = 0.06')
    w.subs.append('[sub_resource type="Sky" id="sky"]\nsky_material = SubResource("sky_mat")')
    w.subs.append('[sub_resource type="Environment" id="env"]\nbackground_mode = 2\nsky = SubResource("sky")\n'
                  'ambient_light_source = 3\nambient_light_color = Color(0.5, 0.58, 0.74, 1)\n'
                  'ambient_light_sky_contribution = 0.3\nambient_light_energy = 0.62\ntonemap_mode = 4\n'
                  'tonemap_white = 6.0\nssao_enabled = true\nssao_radius = 1.6\nssao_intensity = 1.5\n'
                  'glow_enabled = true\nglow_intensity = 0.6\nglow_bloom = 0.05\nglow_hdr_threshold = 1.1\n'
                  'fog_enabled = true\nfog_light_color = Color(0.3, 0.36, 0.52, 1)\nfog_density = 0.0018\n'
                  'fog_sky_affect = 0.15\nadjustment_enabled = true\nadjustment_saturation = 1.1')
    w.nodes.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("env")')
    lights = w.group("Lights")
    w.nodes.append(f'[node name="Dusk" type="DirectionalLight3D" parent="{lights}"]\n'
                   "transform = Transform3D(-0.766, -0.366, 0.528, 0, 0.822, 0.570, -0.643, 0.436, -0.629, 0, 30, 0)\n"
                   f"light_color = {hexc('#ffb682')}\nlight_energy = 2.3\nshadow_enabled = true\nshadow_blur = 1.5\n"
                   "directional_shadow_max_distance = 180.0")
    w.nodes.append(f'[node name="Moon" type="DirectionalLight3D" parent="{lights}"]\n'
                   "transform = Transform3D(0.707, 0.5, -0.5, 0, 0.707, 0.707, 0.707, -0.5, 0.5, 0, 30, 0)\n"
                   f"light_color = {hexc('#9fbcff')}\nlight_energy = 0.5")
    # comet Mãe-Gelo: additive quad with a gradient tail and a bright head
    w.subs.append('[sub_resource type="Gradient" id="tail_grad"]\noffsets = PackedFloat32Array(0, 0.06, 0.4, 1)\n'
                  'colors = PackedColorArray(1, 1, 1, 1, 0.75, 0.91, 1, 0.85, 0.25, 0.88, 0.77, 0.3, 0.56, 0.49, 1, 0)')
    w.subs.append('[sub_resource type="GradientTexture2D" id="tail_tex"]\ngradient = SubResource("tail_grad")\n'
                  'fill_from = Vector2(0, 0.5)\nfill_to = Vector2(1, 0.5)\nwidth = 256\nheight = 8')
    w.subs.append('[sub_resource type="StandardMaterial3D" id="tail_mat"]\ntransparency = 1\nblend_mode = 1\n'
                  'shading_mode = 0\ncull_mode = 2\nalbedo_texture = SubResource("tail_tex")\nfog_enabled = false')
    w.subs.append('[sub_resource type="QuadMesh" id="tail_quad"]\nsize = Vector2(150, 8)\ncenter_offset = Vector3(75, 0, 0)')
    sky = w.group("Sky")
    w.nodes.append(f'[node name="Comet" type="MeshInstance3D" parent="{sky}"]\n'
                   "transform = Transform3D(0.94, -0.34, 0, 0.34, 0.94, 0, 0, 0, 1, -190, 105, -360)\n"
                   'mesh = SubResource("tail_quad")\nsurface_material_override/0 = SubResource("tail_mat")\ncast_shadow = 0')
    # sea + distant hills
    w.subs.append('[sub_resource type="PlaneMesh" id="sea_mesh"]\nsize = Vector2(1400, 1400)')
    w.subs.append('[sub_resource type="StandardMaterial3D" id="sea_mat"]\nalbedo_color = Color(0.04, 0.09, 0.16, 1)\n'
                  'metallic = 0.4\nroughness = 0.12')
    terr = w.group("Terrain")
    w.nodes.append(f'[node name="Sea" type="MeshInstance3D" parent="{terr}"]\ntransform = {xform(0, -9, 0)}\n'
                   'mesh = SubResource("sea_mesh")\nsurface_material_override/0 = SubResource("sea_mat")\ncast_shadow = 0')
    w.box(terr, "Plateau", (150, 3, 104), (6, -3, 2), "ground")
    w.box(terr, "Terrace", (162, 3, 116), (6, -6, 2), "ground_lo")
    w.box(terr, "Cliff", (172, 10, 126), (6, -16, 2), "cliff")
    w.box(terr, "Beach", (180, 1, 134), (6, -9.4, 2), "sand")
    rng = random.Random(11)
    for k in range(34):
        side = rng.choice((-1, 1))
        x = rng.uniform(-72, 84)
        z = side * rng.uniform(50, 56) + 2
        w.box(terr, "Step", (rng.uniform(4, 13), 1.0, rng.uniform(3, 8)), (x, -0.95, z), "ground_lo",
              yaw=rng.choice((0, math.pi / 2)))
    for k in range(18):  # distant voxel hills on the horizon
        a = -0.9 + k * 0.11
        r = rng.uniform(320, 420)
        x, z = r * math.sin(a) - 40, -r * math.cos(a)
        h = rng.uniform(18, 46)
        w.box(terr, "Hill", (rng.uniform(40, 80), h, rng.uniform(30, 50)), (x, -9, z), rng.choice(("hill", "hill2")),
              yaw=rng.uniform(-0.4, 0.4), shadow=False)

    # roads (src/tycoon/campus.gd recolours them per era: dirt -> asphalt -> lit paths)
    roads = w.group("Roads")
    w.box(roads, "RoadEW", (128, 0.06, 5), (8, 0, 2), "#5b4a3a", shadow=False)
    w.box(roads, "RoadNS", (5, 0.06, 76), (0, 0, -4), "#5b4a3a", shadow=False)
    w.box(roads, "Plaza", (14, 0.08, 14), (0, 0, 2), "#6a5846", shadow=False)
    for (lid, (cx, cz), (lw, ld), *_r) in LOTS:  # driveways from each lot to the main road
        z0, z1 = (cz + ld / 2, 0) if cz < 0 else (4, cz - ld / 2)
        if z1 > z0:
            w.box(roads, "Drive", (4, 0.05, z1 - z0), (cx, 0, (z0 + z1) / 2), "#5b4a3a", shadow=False)
    edges = w.group("PathLights", roads, extra="visible = false")
    for k in range(-12, 15):
        for zz in (-0.7, 4.7):
            w.box(edges, "Edge", (0.25, 0.08, 0.25), (k * 5.0 + 2, 0.02, zz), "led_teal", shadow=False)

    lots = w.group("Lots")
    for lid, (cx, cz), (lw, ld), kind, yaw, start in LOTS:
        lg = w.group(lid, lots, (cx, 0, cz), extra=f'metadata/kind = "{kind}"\nmetadata/size = Vector2({lw}, {ld})\n'
                                                     f"metadata/face = {yaw:.5f}\nmetadata/start = {str(start).lower()}")
        fr = w.group("Frame", lg)
        t = 0.18
        for (sx, sz, x, z) in ((lw, t, 0, -ld / 2), (lw, t, 0, ld / 2), (t, ld, -lw / 2, 0), (t, ld, lw / 2, 0)):
            w.box(fr, "Edge", (sx, 0.05, sz), (x, 0.03, z), "lot", shadow=False)
        for (x, z) in ((-lw / 2, -ld / 2), (lw / 2, -ld / 2), (-lw / 2, ld / 2), (lw / 2, ld / 2)):
            w.box(fr, "Post", (0.25, 0.6, 0.25), (x, 0, z), "lamp_pole")
            w.box(fr, "Led", (0.27, 0.12, 0.27), (x, 0.6, z), "lot_led", shadow=False)
        w.box(fr, "Stake", (0.15, 1.6, 0.15), (lw / 2 - 1.2, 0, ld / 2 - 1.2 if cz < 0 else -ld / 2 + 1.2), "trunk")
        w.box(fr, "SignBoard", (1.4, 0.8, 0.08), (lw / 2 - 1.2, 1.2, ld / 2 - 1.2 if cz < 0 else -ld / 2 + 1.2),
              "sign", shadow=False)

    props = w.group("Props")
    for (x, z) in ((-7, -2.5), (7, -2.5), (-7, 6.5), (7, 6.5), (26, -2.2), (-26, -2.2), (26, 6.2), (-26, 6.2),
                   (52, -2.2), (-52, 6.2)):
        lamp(w, props, x, z)
    trees = w.group("Trees", props)
    for k in range(90):
        x, z = rng.uniform(-72, 84), rng.uniform(-48, 50)
        if abs(z - 2) < 6 or abs(x) < 6 or in_lot(x, z, 2.5):
            continue
        tree(w, trees, x, z, rng)
    for k in range(18):
        x, z = rng.uniform(-72, 84), rng.uniform(-48, 50)
        if abs(z - 2) < 6 or abs(x) < 5 or in_lot(x, z, 1.0):
            continue
        w.box(props, "Rock", (rng.uniform(0.8, 2.2), rng.uniform(0.5, 1.3), rng.uniform(0.8, 1.9)), (x, 0, z),
              rng.choice(("rock", "rock2")), yaw=rng.uniform(0, 3))
    bench = w.group("PlazaBench", props)
    w.box(bench, "Seat", (2.4, 0.5, 0.7), (-3.5, 0, -1.2), "crate")
    w.box(bench, "Seat", (2.4, 0.5, 0.7), (3.5, 0, 5.2), "crate")
    w.box(props, "Statue", (1.2, 1.0, 1.2), (0, 0.08, 2), "concrete")
    w.box(props, "StatueStar", (0.7, 0.7, 0.7), (0, 1.1, 2), "lot_led", yaw=math.pi / 4, shadow=False)

    # plaza walk spots (buildings bring their own)
    spots = w.group("Spots")
    spot(w, spots, "Plaza", (2.5, 0, 4.2), "talk", (2.5, 2))
    spot(w, spots, "Bench", (-3.5, 0, -0.6), "sit", (-3.5, 2))
    spot(w, spots, "Statue", (1.6, 0, 0.4), "look_up", (1.6, 2))
    spot(w, spots, "Lookout", (-4, 0, -36), "look_up", (0, -36), math.pi)

    # the campus crowd: editable instances; src/tycoon/campus.gd shows one per staff member
    crowd = w.group("Crowd")
    roles = ["engineer", "scientist", "pilot", "ground"]
    for k in range(12):
        ang = k / 12 * math.tau
        x, z = 4.5 * math.cos(ang), 2 + 3.5 * math.sin(ang)
        w.nodes.append(f'[node name="Cometling{k + 1}" parent="{crowd}" instance=ExtResource("2_cl")]\n'
                       f"transform = {xform(x, 0, z, ang)}\nvariant = {k % 9}\nrole = \"{roles[k % 4]}\"")

    w.write(OUT_CAMPUS, '[node name="Campus" type="Node3D"]\nscript = ExtResource("1_campus")')
    return len(w.nodes)


def main():
    # the buildings are voxel models with interiors: tools/build_campus_buildings.py
    import build_campus_buildings
    build_campus_buildings.main()
    print(f"wrote campus.tscn ({build_campus()} nodes)")


if __name__ == "__main__":
    main()
