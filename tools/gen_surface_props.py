"""Writes the voxel set pieces of the planet surfaces (scenes/surface/props/*.tscn) and their
toon materials (scenes/surface/props/materials/*.tres).

Every prop is a plain editable scene: a Node3D with one MeshInstance3D per block (BoxMesh,
shared by size) using the Cometworks toon materials. Run it again after changing a shape here,
or edit the scenes in the Godot editor directly (then stop using this script for that prop).
No real logos or text: homages are shapes and colours only.

Run: python tools/gen_surface_props.py
"""
import math
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
PROPS = os.path.join(ROOT, "scenes", "surface", "props")
MATS = os.path.join(PROPS, "materials")

# name: (albedo rgb, roughness, metallic, emission rgb, emission energy, toon_specular)
MATERIALS = {
    "foil_gold": ((0.93, 0.68, 0.22), 0.35, 0.6, (0.25, 0.16, 0.02), 0.6, 1.2),
    "foil_silver": ((0.82, 0.84, 0.88), 0.35, 0.6, (0.0, 0.0, 0.0), 0.0, 1.0),
    "paint_white": ((0.94, 0.93, 0.9), 0.8, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "paint_cream": ((0.98, 0.92, 0.8), 0.8, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "metal_dark": ((0.22, 0.23, 0.27), 0.5, 0.4, (0.0, 0.0, 0.0), 0.0, 0.6),
    "metal_light": ((0.66, 0.68, 0.72), 0.45, 0.5, (0.0, 0.0, 0.0), 0.0, 0.8),
    "solar_blue": ((0.16, 0.26, 0.55), 0.3, 0.2, (0.02, 0.05, 0.14), 0.6, 1.5),
    "lilac": ((0.62, 0.52, 0.86), 0.7, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "butter": ((1.0, 0.82, 0.38), 0.7, 0.0, (0.5, 0.36, 0.08), 0.8, 0.0),
    "mint": ((0.48, 0.86, 0.72), 0.7, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "lens": ((0.08, 0.1, 0.16), 0.15, 0.3, (0.05, 0.1, 0.2), 0.8, 2.0),
    "tire": ((0.15, 0.15, 0.17), 0.9, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "cloth_white": ((0.97, 0.97, 0.95), 0.9, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "cloth_red": ((0.86, 0.28, 0.3), 0.9, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "cloth_blue": ((0.22, 0.32, 0.66), 0.9, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "print_dark": ((0.32, 0.32, 0.33), 1.0, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "rock_grey": ((0.5, 0.49, 0.48), 1.0, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "rock_grey_dark": ((0.36, 0.36, 0.37), 1.0, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "rock_red": ((0.56, 0.32, 0.22), 1.0, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "rock_red_dark": ((0.38, 0.22, 0.17), 1.0, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "berry_blue": ((0.24, 0.28, 0.42), 0.4, 0.3, (0.0, 0.0, 0.0), 0.0, 1.0),
    "meteorite": ((0.2, 0.18, 0.17), 0.35, 0.7, (0.0, 0.0, 0.0), 0.0, 1.6),
    "ice_blue": ((0.72, 0.9, 1.0), 0.2, 0.0, (0.3, 0.6, 0.9), 0.7, 2.0),
    "odd_orange": ((1.0, 0.55, 0.2), 0.4, 0.0, (0.45, 0.18, 0.02), 0.6, 1.0),
    "odd_violet": ((0.55, 0.36, 0.86), 0.4, 0.0, (0.15, 0.05, 0.3), 0.6, 1.0),
    "crumb": ((0.75, 1.0, 0.95), 0.3, 0.0, (0.4, 1.0, 0.9), 1.6, 1.0),
    "glow_ring": ((1.0, 0.86, 0.5), 0.8, 0.0, (1.0, 0.75, 0.3), 1.4, 0.0),
    "salt_red": ((0.74, 0.42, 0.32), 0.6, 0.0, (0.1, 0.03, 0.0), 0.4, 0.6),
    "cone_orange": ((1.0, 0.48, 0.16), 0.7, 0.0, (0.0, 0.0, 0.0), 0.0, 0.0),
    "ice_white": ((0.9, 0.95, 1.0), 0.5, 0.0, (0.05, 0.08, 0.12), 0.6, 0.6),
}


def write_materials():
    os.makedirs(MATS, exist_ok=True)
    for name, (alb, rough, metal, emi, emi_e, spec) in MATERIALS.items():
        with open(os.path.join(MATS, name + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write('[gd_resource type="ShaderMaterial" format=3]\n\n')
            f.write('[ext_resource type="Shader" path="res://shaders/cw_toon_solid.gdshader" id="1_toon"]\n\n')
            f.write("[resource]\n")
            f.write('shader = ExtResource("1_toon")\n')
            f.write("shader_parameter/albedo = Color(%g, %g, %g, 1)\n" % alb)
            f.write("shader_parameter/roughness = %g\n" % rough)
            f.write("shader_parameter/metallic = %g\n" % metal)
            f.write("shader_parameter/emission = Color(%g, %g, %g, 1)\n" % emi)
            f.write("shader_parameter/emission_energy = %g\n" % emi_e)
            f.write("shader_parameter/toon_specular = %g\n" % spec)


def B(name, pos, size, mat, yaw=0.0, pitch=0.0, roll=0.0):
    return {"name": name, "pos": pos, "size": size, "mat": mat, "rot": (pitch, yaw, roll)}


def basis(pitch, yaw, roll):
    # Godot's Basis.from_euler (YXZ order): R = Ry * Rx * Rz
    cx, sx = math.cos(pitch), math.sin(pitch)
    cy, sy = math.cos(yaw), math.sin(yaw)
    cz, sz = math.cos(roll), math.sin(roll)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mul(mul(ry, rx), rz)


def xform(pos, rot):
    m = basis(*rot)
    # a .tscn Transform3D lists the basis row by row, then the origin
    vals = m[0] + m[1] + m[2] + list(pos)
    return "Transform3D(%s)" % ", ".join("%.4g" % (0.0 if abs(v) < 1e-6 else v) for v in vals)


def write_prop(name, doc, blocks, root_type="Node3D", root_script=None, root_props=None, extra_nodes="", extra_ext=None,
               groups=None):
    mats = sorted({b["mat"] for b in blocks})
    sizes = []
    for b in blocks:
        s = tuple(round(v, 3) for v in b["size"])
        if s not in sizes:
            sizes.append(s)
    lines = ["[gd_scene format=3]", ""]
    ext_id = {}
    for i, m in enumerate(mats):
        ext_id[m] = "m%d" % i
        lines.append('[ext_resource type="Material" path="res://scenes/surface/props/materials/%s.tres" id="m%d"]' % (m, i))
    if root_script:
        lines.append('[ext_resource type="Script" path="%s" id="s_root"]' % root_script)
    for e in extra_ext or []:
        lines.append(e)
    lines.append("")
    for i, s in enumerate(sizes):
        lines.append('[sub_resource type="BoxMesh" id="box%d"]' % i)
        lines.append("size = Vector3(%g, %g, %g)" % s)
        lines.append("")
    g = (' groups=[%s]' % ", ".join('"%s"' % x for x in groups)) if groups else ""
    lines.append('[node name="%s" type="%s"%s]' % (name, root_type, g))
    for d in doc:
        lines.append("editor_description = \"%s\"" % d.replace('"', "'"))
    if root_script:
        lines.append('script = ExtResource("s_root")')
    for k, v in (root_props or {}).items():
        lines.append("%s = %s" % (k, v))
    lines.append("")
    groups_of = {}
    for b in blocks:
        parent = b.get("parent", ".")
        s = tuple(round(v, 3) for v in b["size"])
        lines.append('[node name="%s" type="MeshInstance3D" parent="%s"]' % (b["name"], parent))
        lines.append("transform = " + xform(b["pos"], b["rot"]))
        lines.append('mesh = SubResource("box%d")' % sizes.index(s))
        lines.append('surface_material_override/0 = ExtResource("%s")' % ext_id[b["mat"]])
        lines.append("")
    if extra_nodes:
        lines.append(extra_nodes)
    os.makedirs(PROPS, exist_ok=True)
    with open(os.path.join(PROPS, name_to_file(name)), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines).rstrip() + "\n")


def name_to_file(name):
    out = ""
    for i, c in enumerate(name):
        if c.isupper() and i > 0:
            out += "_"
        out += c.lower()
    return out + ".tscn"


def legs4(prefix, half, top, foot_out, mat, pad_mat, h0=0.0):
    out = []
    for i, (sx, sz) in enumerate([(1, 1), (-1, 1), (-1, -1), (1, -1)]):
        x0, z0 = sx * half, sz * half
        x1, z1 = sx * (half + foot_out), sz * (half + foot_out)
        mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
        dx, dz = x1 - x0, z1 - z0
        horiz = math.hypot(dx, dz)
        length = math.hypot(horiz, top - h0)
        yaw = math.atan2(dx, dz)
        tilt = math.atan2(horiz, top - h0)
        out.append(B("%sLeg%d" % (prefix, i), (mx, (top + h0) / 2 + 0.12, mz), (0.12, length, 0.12), mat, yaw=yaw, pitch=-tilt))
        out.append(B("%sPad%d" % (prefix, i), (x1, 0.06, z1), (0.5, 0.12, 0.5), pad_mat))
    return out


def wheel_row(prefix, xs, z, y, r, mat, w=0.18):
    return [B("%s%d" % (prefix, i), (x, y, z), (r * 2, r * 2, w), mat) for i, x in enumerate(xs)]


def props():
    # ---------------------------------------------------------------- our lander
    lander = [
        B("Deck", (0, 1.25, 0), (2.0, 0.7, 2.0), "paint_cream"),
        B("Band", (0, 1.25, 0), (2.08, 0.18, 2.08), "lilac"),
        B("Dome", (0, 1.85, 0), (1.3, 0.5, 1.3), "paint_white"),
        B("Hatch", (0, 1.25, 1.05), (0.6, 0.5, 0.06), "lilac"),
        B("Window", (0, 1.95, 0.66), (0.5, 0.22, 0.04), "lens"),
        B("Engine", (0, 0.72, 0), (0.7, 0.36, 0.7), "metal_dark"),
        B("Mast", (0.55, 2.45, -0.4), (0.08, 0.9, 0.08), "metal_light"),
        B("Bulb", (0.55, 2.95, -0.4), (0.24, 0.24, 0.24), "butter"),
        B("Panel", (-1.55, 1.4, 0), (1.1, 0.06, 0.8), "solar_blue", roll=0.25),
        B("PanelArm", (-1.05, 1.32, 0), (0.3, 0.06, 0.08), "metal_light"),
        B("Dish", (0.5, 2.2, 0.45), (0.5, 0.08, 0.5), "paint_white", pitch=-0.5),
        B("Ladder", (0, 0.65, 1.25), (0.35, 1.0, 0.05), "metal_light", pitch=0.25),
    ] + legs4("", 0.85, 1.0, 0.7, "metal_light", "foil_gold")
    write_prop("LanderCometworks", ["Our lander (Cometworks): the delivery target of the sample challenges."], lander)

    # ---------------------------------------------------------------- Apollo-like descent stage (homage)
    ds = [
        B("Body", (0, 1.35, 0), (2.6, 1.3, 2.6), "foil_gold"),
        B("BodyDiag", (0, 1.35, 0), (2.9, 1.15, 1.6), "foil_gold", yaw=math.pi / 4),
        B("BodyDiag2", (0, 1.35, 0), (2.9, 1.15, 1.6), "foil_gold", yaw=-math.pi / 4),
        B("Deck", (0, 2.04, 0), (2.5, 0.08, 2.5), "foil_silver"),
        B("Nozzle", (0, 0.55, 0), (0.7, 0.4, 0.7), "metal_dark"),
        B("Porch", (0, 1.9, 1.6), (0.8, 0.06, 0.6), "foil_silver"),
        B("Ladder", (0, 1.05, 2.0), (0.4, 1.6, 0.06), "foil_silver", pitch=0.35),
        B("Plaque", (0, 1.25, 1.62), (0.3, 0.3, 0.04), "metal_light"),
    ] + legs4("", 1.25, 1.6, 1.15, "foil_silver", "foil_gold")
    flag = [
        B("FlagPole", (3.2, 1.1, 1.8), (0.06, 2.2, 0.06), "metal_light"),
        B("FlagBar", (3.75, 2.15, 1.8), (1.1, 0.04, 0.04), "metal_light"),
        B("FlagCloth", (3.75, 1.78, 1.81), (1.1, 0.7, 0.03), "cloth_white"),
        B("FlagStripeA", (3.75, 1.98, 1.83), (1.1, 0.1, 0.02), "cloth_red"),
        B("FlagStripeB", (3.75, 1.68, 1.83), (1.1, 0.1, 0.02), "cloth_red"),
        B("FlagCanton", (3.45, 1.98, 1.84), (0.44, 0.3, 0.02), "cloth_blue"),
    ]
    seis = [
        B("SeisBox", (-2.8, 0.25, 1.6), (0.5, 0.5, 0.5), "foil_gold"),
        B("SeisWingL", (-3.45, 0.42, 1.6), (0.8, 0.04, 0.5), "solar_blue"),
        B("SeisWingR", (-2.15, 0.42, 1.6), (0.8, 0.04, 0.5), "solar_blue"),
        B("SeisAnt", (-2.8, 0.75, 1.6), (0.04, 0.5, 0.04), "metal_light"),
        B("Reflector", (-2.4, 0.35, -2.4), (0.6, 0.06, 0.6), "lens", pitch=0.5),
        B("ReflectorLeg", (-2.4, 0.15, -2.4), (0.06, 0.3, 0.06), "metal_light"),
    ]
    write_prop("HomageDescentStage", ["Tribute to a 1969 lunar landing: a gold-foil descent stage, a plain flag (no real emblem), a seismometer and a laser reflector."],
               ds + flag + seis)

    # ---------------------------------------------------------------- footprints trail (each print snaps)
    prints = []
    extra = []
    for i in range(14):
        t = i * 0.75
        x = 1.5 + t * math.cos(0.5) + 0.25 * (1 if i % 2 else -1)
        z = 1.0 + t * math.sin(0.5) + math.sin(t * 0.4) * 0.6
        extra.append(('[node name="Print%d" type="Node3D" parent="."]\n'
                      'transform = %s\n'
                      'script = ExtResource("s_snap")\n'
                      'ground_offset = -0.02\n') % (i, xform((x, 0.0, z), (0.0, -0.5, 0.0))))
        prints.append({"name": "Sole", "parent": "Print%d" % i, "pos": (0, 0.0, 0), "size": (0.32, 0.06, 0.14),
                       "mat": "print_dark", "rot": (0, 0, 0)})
        prints.append({"name": "Heel", "parent": "Print%d" % i, "pos": (-0.2, 0.0, 0), "size": (0.12, 0.06, 0.12),
                       "mat": "print_dark", "rot": (0, 0, 0)})
    write_footprints(prints, extra)

    # ---------------------------------------------------------------- tub rover (Lunokhod-like homage)
    lk = [
        B("Tub", (0, 0.85, 0), (1.6, 0.6, 1.1), "metal_light"),
        B("TubRim", (0, 1.18, 0), (1.7, 0.08, 1.2), "metal_dark"),
        B("Lid", (-0.3, 1.55, 0), (1.6, 0.06, 1.2), "solar_blue", roll=0.8),
        B("Eye1", (0.85, 0.9, 0.25), (0.06, 0.16, 0.16), "lens"),
        B("Eye2", (0.85, 0.9, -0.25), (0.06, 0.16, 0.16), "lens"),
        B("Rod1", (0.4, 1.55, 0.45), (0.03, 0.75, 0.03), "metal_light"),
        B("Rod2", (0.6, 1.4, -0.45), (0.03, 0.5, 0.03), "metal_light"),
        B("Cone", (0.55, 1.45, 0.0), (0.18, 0.3, 0.18), "metal_light", pitch=0.4),
    ] + wheel_row("WheelL", [-0.6, -0.2, 0.2, 0.6], 0.68, 0.32, 0.3, "metal_dark") \
      + wheel_row("WheelR", [-0.6, -0.2, 0.2, 0.6], -0.68, 0.32, 0.3, "metal_dark")
    write_prop("HomageLunokhod", ["Tribute to the first rover driven on another world (1970): a tub on eight wheels with its lid open to the Sun."], lk)

    # ---------------------------------------------------------------- Viking-like lander (homage)
    vk = [
        B("Body", (0, 1.05, 0), (1.5, 0.45, 1.3), "paint_white"),
        B("BodyB", (0, 1.05, 0), (1.5, 0.45, 1.3), "paint_white", yaw=math.pi / 3),
        B("BodyC", (0, 1.05, 0), (1.5, 0.45, 1.3), "paint_white", yaw=-math.pi / 3),
        B("Top", (0, 1.3, 0), (1.3, 0.06, 1.3), "foil_silver"),
        B("Mast", (-0.3, 1.8, -0.2), (0.07, 1.0, 0.07), "metal_light"),
        B("Dish", (-0.3, 2.35, -0.2), (0.9, 0.1, 0.9), "paint_white", pitch=-0.6, yaw=0.5),
        B("RtgA", (0.75, 1.2, 0.45), (0.35, 0.5, 0.2), "metal_dark", yaw=0.5),
        B("RtgB", (0.75, 1.2, -0.45), (0.35, 0.5, 0.2), "metal_dark", yaw=-0.5),
        B("CamA", (0.2, 1.6, 0.55), (0.18, 0.5, 0.18), "metal_light"),
        B("CamB", (0.55, 1.6, 0.2), (0.18, 0.5, 0.18), "metal_light"),
        B("CamAEye", (0.2, 1.78, 0.65), (0.1, 0.1, 0.04), "lens"),
        B("CamBEye", (0.65, 1.78, 0.2), (0.04, 0.1, 0.1), "lens"),
        B("Boom", (1.4, 1.0, -0.2), (1.3, 0.08, 0.08), "metal_light", roll=-0.35),
        B("Scoop", (2.0, 0.62, -0.2), (0.2, 0.14, 0.16), "metal_dark"),
        B("Trench", (2.1, 0.02, -0.2), (0.7, 0.04, 0.25), "rock_red_dark"),
    ]
    for i, a in enumerate([0.0, 2.094, 4.189]):
        x1, z1 = math.sin(a) * 1.55, math.cos(a) * 1.55
        mx, mz = x1 * 0.6, z1 * 0.6
        vk.append(B("Leg%d" % i, (mx, 0.55, mz), (0.1, 1.2, 0.1), "metal_light", yaw=a, pitch=-0.75))
        vk.append(B("Pad%d" % i, (x1, 0.05, z1), (0.45, 0.1, 0.45), "metal_light"))
    write_prop("HomageViking", ["Tribute to the first successful US Mars landing (1976): a three-legged lander with a dish, two power units, two camera towers and a sampler arm."], vk)

    # ---------------------------------------------------------------- Sojourner-sized rover (homage)
    sj = [
        B("Body", (0, 0.32, 0), (0.62, 0.16, 0.46), "metal_light"),
        B("Solar", (0, 0.42, 0), (0.64, 0.03, 0.48), "solar_blue"),
        B("Ant", (-0.22, 0.6, 0.15), (0.02, 0.32, 0.02), "metal_light"),
        B("Eye", (0.33, 0.32, 0.08), (0.03, 0.06, 0.06), "lens"),
        B("Eye2", (0.33, 0.32, -0.08), (0.03, 0.06, 0.06), "lens"),
        B("Apxs", (-0.36, 0.25, 0), (0.1, 0.08, 0.08), "foil_gold"),
        B("RockerL", (0, 0.2, 0.28), (0.6, 0.04, 0.04), "metal_dark", roll=0.1),
        B("RockerR", (0, 0.2, -0.28), (0.6, 0.04, 0.04), "metal_dark", roll=0.1),
        B("Yogi", (-0.75, 0.3, 0.1), (0.6, 0.6, 0.55), "rock_red", yaw=0.4),
        B("YogiTop", (-0.78, 0.62, 0.05), (0.4, 0.15, 0.35), "rock_red_dark", yaw=0.4),
        B("Tracks", (1.1, 0.01, 0.28), (1.4, 0.02, 0.1), "rock_red_dark"),
        B("Tracks2", (1.1, 0.01, -0.28), (1.4, 0.02, 0.1), "rock_red_dark"),
    ] + wheel_row("WheelL", [-0.25, 0.0, 0.25], 0.29, 0.07, 0.07, "metal_dark", 0.06) \
      + wheel_row("WheelR", [-0.25, 0.0, 0.25], -0.29, 0.07, 0.07, "metal_dark", 0.06)
    write_prop("HomageSojourner", ["Tribute to the first rover on Mars (1997): about the size of a microwave oven, next to a big rock it studied."], sj)

    # ---------------------------------------------------------------- probe debris (MESSENGER homage)
    db = [
        B("Bit1", (0.4, 0.05, 0.2), (0.4, 0.06, 0.3), "foil_gold", yaw=0.6, roll=0.3),
        B("Bit2", (-0.6, 0.05, -0.3), (0.3, 0.05, 0.5), "foil_silver", yaw=1.2),
        B("Bit3", (0.1, 0.06, -0.8), (0.5, 0.05, 0.2), "solar_blue", yaw=-0.4, pitch=0.2),
        B("Bit4", (-0.3, 0.08, 0.7), (0.15, 0.15, 0.15), "metal_dark", yaw=0.3),
    ]
    write_prop("HomageDebris", ["Bits of a probe that ended its mission on purpose (Mercury, 2015)."], db)

    # ---------------------------------------------------------------- survey stake (POI readability)
    st = [
        B("Pole", (0, 0.9, 0), (0.08, 1.8, 0.08), "metal_light"),
        B("Pennant", (0.25, 1.62, 0), (0.42, 0.28, 0.03), "lilac"),
        B("Tip", (0, 1.85, 0), (0.14, 0.14, 0.14), "butter"),
    ]
    write_prop("SurveyStake", ["A little survey stake with a lilac pennant: marks a point of interest from afar."], st)

    # ---------------------------------------------------------------- rocks
    br = [
        B("HalfA", (-0.9, 1.4, 0), (1.7, 2.8, 2.6), "rock_grey", yaw=0.1, roll=0.08),
        B("HalfB", (0.95, 1.2, 0.1), (1.6, 2.4, 2.4), "rock_grey", yaw=-0.15, roll=-0.1),
        B("CapA", (-0.95, 2.9, 0), (1.3, 0.4, 2.0), "rock_grey_dark", yaw=0.1),
        B("Chip1", (2.2, 0.25, 1.2), (0.6, 0.5, 0.5), "rock_grey_dark", yaw=0.7),
        B("Chip2", (-2.0, 0.2, -1.3), (0.5, 0.4, 0.6), "rock_grey", yaw=0.3),
    ]
    write_prop("BoulderSplit", ["A big split boulder (a nod to the Apollo 17 one)."], br)

    bb = [
        B("Rock", (0, 0.55, 0), (1.6, 1.1, 1.2), "rock_red", yaw=0.3),
        B("RockTop", (0.1, 1.2, 0), (1.1, 0.3, 0.9), "rock_red_dark", yaw=0.3),
    ]
    for i in range(10):
        a = i * 0.9
        bb.append(B("Berry%d" % i, (math.cos(a) * 0.7, 0.3 + (i % 3) * 0.25, math.sin(a) * 0.55), (0.12, 0.12, 0.12), "berry_blue"))
    for i in range(8):
        a = i * 0.8 + 0.3
        bb.append(B("Loose%d" % i, (math.cos(a) * 1.4, 0.05, math.sin(a) * 1.2), (0.1, 0.1, 0.1), "berry_blue"))
    write_prop("RockBlueberries", ["A Martian rock dotted with hematite 'blueberries'."], bb)

    salt = []
    for i in range(9):
        a = i * 0.7
        r = 0.6 + (i % 3) * 0.5
        salt.append(B("Crystal%d" % i, (math.cos(a) * r, 0.12 + (i % 2) * 0.08, math.sin(a) * r), (0.3, 0.25 + (i % 3) * 0.12, 0.25), "salt_red", yaw=a))
    write_prop("SaltCrust", ["Reddish salty crust along a Europa streak."], salt)

    ice = [
        B("Slab", (0, 0.15, 0), (2.4, 0.3, 1.8), "ice_white", yaw=0.2),
        B("Shard1", (0.3, 0.6, 0.1), (0.3, 0.8, 0.3), "ice_blue", yaw=0.4, roll=0.2),
        B("Shard2", (-0.4, 0.5, -0.2), (0.25, 0.6, 0.25), "ice_blue", yaw=-0.3, roll=-0.25),
        B("Shard3", (0.1, 0.4, -0.5), (0.2, 0.45, 0.2), "ice_blue", pitch=0.3),
    ]
    write_prop("IceClear", ["Clear blue ice: the drill spot above Europa's ocean."], ice)

    cones = []
    for i, (x, z) in enumerate([(-3, -3), (3, -3), (3, 3), (-3, 3), (0, -5), (0, 5)]):
        cones.append(B("Cone%dBase" % i, (x, 0.05, z), (0.6, 0.1, 0.6), "cone_orange"))
        cones.append(B("Cone%dMid" % i, (x, 0.35, z), (0.38, 0.5, 0.38), "cone_orange"))
        cones.append(B("Cone%dBand" % i, (x, 0.42, z), (0.4, 0.1, 0.4), "paint_white"))
        cones.append(B("Cone%dTop" % i, (x, 0.7, z), (0.18, 0.2, 0.18), "cone_orange"))
    cones += [B("Board", (5.5, 1.0, 0), (0.1, 1.2, 1.8), "paint_cream"), B("BoardLeg", (5.5, 0.4, 0), (0.12, 0.8, 0.12), "metal_light")]
    write_prop("TestYard", ["Cones and a board (no text) of the rover test yard at home."], cones)

    # ---------------------------------------------------------------- challenge ring
    ring = []
    for i in range(16):
        a = i * math.tau / 16
        ring.append(B("Stud%d" % i, (math.cos(a) * 3.0, 0.06, math.sin(a) * 3.0), (0.5, 0.12, 0.22), "glow_ring", yaw=-a + math.pi / 2))
    ring += [
        B("Pole", (0, 1.2, -3.4), (0.08, 2.4, 0.08), "metal_light"),
        B("Flag", (0.32, 2.15, -3.4), (0.6, 0.4, 0.03), "butter"),
        B("FlagCheck1", (0.17, 2.25, -3.38), (0.15, 0.1, 0.02), "metal_dark"),
        B("FlagCheck2", (0.47, 2.25, -3.38), (0.15, 0.1, 0.02), "metal_dark"),
        B("FlagCheck3", (0.32, 2.05, -3.38), (0.15, 0.1, 0.02), "metal_dark"),
    ]
    write_prop("ChallengeRing", ["Start ring of a free-play challenge (SurfaceChallenge): the rule lives in data/surface_explore.json."],
               ring, root_script="res://src/world/surface_challenge.gd")

    # ---------------------------------------------------------------- collectible
    col = []
    col += [dict(b, parent="Meteorite") for b in [
        B("A", (0, 0, 0), (0.42, 0.34, 0.38), "meteorite", yaw=0.4, roll=0.2),
        B("B", (0.12, 0.16, 0.05), (0.24, 0.2, 0.22), "meteorite", yaw=0.9),
        B("C", (-0.15, -0.06, 0.1), (0.2, 0.18, 0.2), "meteorite", pitch=0.4)]]
    col += [dict(b, parent="Ice") for b in [
        B("A", (0, 0.1, 0), (0.16, 0.55, 0.16), "ice_blue", roll=0.15),
        B("B", (0.12, 0.0, 0.04), (0.12, 0.38, 0.12), "ice_blue", roll=-0.4),
        B("C", (-0.1, -0.02, -0.06), (0.1, 0.32, 0.1), "ice_blue", pitch=0.4)]]
    col += [dict(b, parent="OddRock") for b in [
        B("A", (0, 0, 0), (0.34, 0.28, 0.3), "odd_violet", yaw=0.3),
        B("B", (0.1, 0.14, 0.02), (0.18, 0.14, 0.18), "odd_orange", yaw=0.8),
        B("C", (-0.12, 0.1, 0.1), (0.12, 0.12, 0.12), "odd_orange")]]
    col += [dict(b, parent="Crumb") for b in [
        B("Core", (0, 0, 0), (0.22, 0.22, 0.22), "crumb", yaw=0.785, pitch=0.6),
        B("TailA", (-0.24, 0.02, 0), (0.24, 0.08, 0.08), "crumb"),
        B("TailB", (-0.4, 0.03, 0), (0.12, 0.05, 0.05), "crumb")]]
    for i in range(8):
        a = i * math.tau / 8
        col.append(B("Glow%d" % i, (math.cos(a) * 0.55, 0.02, math.sin(a) * 0.55), (0.18, 0.03, 0.08), "glow_ring", yaw=-a + math.pi / 2))
    groups = ""
    for n in ["Meteorite", "Ice", "OddRock", "Crumb"]:
        groups += '[node name="%s" type="Node3D" parent="."]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.15, 0)\n\n' % n
    write_collectible(col, groups)


def write_footprints(prints, extra):
    lines = ["[gd_scene format=3]", "",
             '[ext_resource type="Material" path="res://scenes/surface/props/materials/print_dark.tres" id="m0"]',
             '[ext_resource type="Script" path="res://src/world/surface_ground_snap.gd" id="s_snap"]', "",
             '[sub_resource type="BoxMesh" id="sole"]', "size = Vector3(0.32, 0.06, 0.14)", "",
             '[sub_resource type="BoxMesh" id="heel"]', "size = Vector3(0.12, 0.06, 0.12)", "",
             '[node name="HomageFootprints" type="Node3D"]',
             'editor_description = "A trail of bootprints. Each print sits on the ground by itself (SurfaceGroundSnap)."', ""]
    for i, e in enumerate(extra):
        lines.append(e)
        for p in prints[i * 2:i * 2 + 2]:
            lines.append('[node name="%s" type="MeshInstance3D" parent="%s"]' % (p["name"], p["parent"]))
            lines.append("transform = " + xform(p["pos"], p["rot"]))
            lines.append('mesh = SubResource("%s")' % ("sole" if p["name"] == "Sole" else "heel"))
            lines.append('surface_material_override/0 = ExtResource("m0")')
            lines.append("")
    with open(os.path.join(PROPS, "homage_footprints.tscn"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines).rstrip() + "\n")


def write_collectible(blocks, group_nodes):
    # the type nodes must exist before their blocks: write them as extra nodes first
    mats = sorted({b["mat"] for b in blocks})
    sizes = []
    for b in blocks:
        s = tuple(round(v, 3) for v in b["size"])
        if s not in sizes:
            sizes.append(s)
    lines = ["[gd_scene format=3]", ""]
    for i, m in enumerate(mats):
        lines.append('[ext_resource type="Material" path="res://scenes/surface/props/materials/%s.tres" id="m%d"]' % (m, i))
    lines.append('[ext_resource type="Script" path="res://src/world/surface_collectible.gd" id="s_root"]')
    lines.append("")
    for i, s in enumerate(sizes):
        lines += ['[sub_resource type="BoxMesh" id="box%d"]' % i, "size = Vector3(%g, %g, %g)" % s, ""]
    lines += ['[node name="Collectible" type="Node3D"]',
              'editor_description = "A find on a surface (SurfaceCollectible): pick the type, the matching child shows."',
              'script = ExtResource("s_root")', "", group_nodes]
    for b in blocks:
        s = tuple(round(v, 3) for v in b["size"])
        lines.append('[node name="%s" type="MeshInstance3D" parent="%s"]' % (b["name"], b.get("parent", ".")))
        lines.append("transform = " + xform(b["pos"], b["rot"]))
        lines.append('mesh = SubResource("box%d")' % sizes.index(s))
        lines.append('surface_material_override/0 = ExtResource("m%d")' % mats.index(b["mat"]))
        lines.append("cast_shadow = 0" if b["mat"] == "glow_ring" else "")
        lines.append("")
    with open(os.path.join(PROPS, "collectible.tscn"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(l for l in lines).rstrip() + "\n")


if __name__ == "__main__":
    write_materials()
    props()
    print("props written to", PROPS)
