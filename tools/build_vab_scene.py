"""Writes the hangar environment scenes:

  scenes/environment/vab.tscn                  the Vehicle Assembly Building (KSP-VAB-like)
  scenes/environment/outside_launch_site.tscn  the planet outside the open door: sky dome,
                                               sun, voxel terrain, coast/ocean, crawlerway,
                                               launch complex, clouds (instanced by vab.tscn)

Both are normal Godot scenes organized in groups (Floor, Walls, Columns, Ceiling,
Catwalks, ServiceTower, Crane, Door, Signage, Props, Lights / Sky, Ground, Terrain,
Crawlerway, LaunchComplex, Clouds) so they can be edited by hand in the editor afterwards;
re-running this script overwrites them. Repeated small pieces (truss members, posts,
lamps, terrain blocks, trees, clouds) are MultiMeshInstance3D nodes: one draw call each.

Colours come from the project palette in tools/make_ui_kit.py (PALETTE / LIGHTS, also
ui/palette.gd and docs/art/palette.md).

Walls are inward-facing quads (back-face culled), so when the camera zooms out past
a wall the building works as a cutaway instead of hiding the rocket. They cast
double-sided shadows, so the sun only enters through the open door.
Interior lights only affect render layer 1; the outside scene lives on layer 2.

Usage: python tools/build_vab_scene.py
"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_ui_kit import LIGHTS, PALETTE, hexrgb  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "scenes" / "environment" / "vab.tscn"
OUT_SITE = ROOT / "scenes" / "environment" / "outside_launch_site.tscn"

HALF = 60.0      # interior half-size (m)
HEIGHT = 120.0   # interior height (m)
PAD_TOP = 0.62
DOOR_X0, DOOR_X1, DOOR_H = -45.0, 15.0, 96.0   # open high-bay door in the back wall (z = -HALF)
DOOR_CX, DOOR_W = (DOOR_X0 + DOOR_X1) / 2, DOOR_X1 - DOOR_X0

# Sun: azimuth measured from -Z toward -X (deg), elevation (deg). It shines in through the
# door and rim-lights the rocket from behind-left.
SUN_AZ, SUN_EL = 14.0, 30.0
TO_SUN = (-math.sin(math.radians(SUN_AZ)) * math.cos(math.radians(SUN_EL)), math.sin(math.radians(SUN_EL)),
          -math.cos(math.radians(SUN_AZ)) * math.cos(math.radians(SUN_EL)))

# Outside layout
PAD_OUT = (-125.0, -745.0)        # launch complex centre (seen through the door, right of the rocket)
PAD_B = (-560.0, -1180.0)         # a second, older pad further away
COAST_P1 = np.array([350.0, -200.0])
_cd = np.array([-650.0, -1300.0])
COAST_D = _cd / np.linalg.norm(_cd)
COAST_N = np.array([-COAST_D[1], COAST_D[0]])   # points to the ocean (+x side)
SKY_R = 2300.0
LAYER_OUT = 2


# ------------------------------------------------------------------ helpers
def pal(name):
    return hexrgb((PALETTE.get(name) or LIGHTS[name])[0])


def col(r, g=None, b=None, a=1.0):
    if g is None:  # palette token name
        r, g, b = pal(r)
    return f"Color({r:.4g}, {g:.4g}, {b:.4g}, {a:.4g})"


def pc(name, mul=1.0, a=1.0):
    r, g, b = pal(name)
    return col(min(r * mul, 1), min(g * mul, 1), min(b * mul, 1), a)


def mix(c1, c2, t):
    return tuple(a + (b - a) * t for a, b in zip(c1, c2))


def v3(x, y, z):
    return f"Vector3({x:.5g}, {y:.5g}, {z:.5g})"


def mat3(yaw=0.0, pitch=0.0, roll=0.0, scale=(1, 1, 1)):
    """Rotation (Euler YXZ, degrees) times per-axis scale, as rows."""
    y, p, r = (math.radians(a) for a in (yaw, pitch, roll))
    cy, sy, cp, sp, cr, sr = math.cos(y), math.sin(y), math.cos(p), math.sin(p), math.cos(r), math.sin(r)
    Ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    Rx = [[1, 0, 0], [0, cp, -sp], [0, sp, cp]]
    Rz = [[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    m = mul(mul(Ry, Rx), Rz)
    return [[m[i][j] * scale[j] for j in range(3)] for i in range(3)]


def xform(pos=(0, 0, 0), yaw=0.0, pitch=0.0, roll=0.0, scale=(1, 1, 1)):
    m = mat3(yaw, pitch, roll, scale)
    vals = [m[i][j] for i in range(3) for j in range(3)] + list(pos)
    return "Transform3D(" + ", ".join(f"{v:.5g}" for v in vals) + ")"


def look_angles(d):
    """yaw, pitch (deg) so that a node's -Z axis points along direction d."""
    x, y, z = d
    n = math.sqrt(x * x + y * y + z * z)
    x, y, z = x / n, y / n, z / n
    pitch = math.degrees(math.asin(y))
    yaw = math.degrees(math.atan2(-x, -z))
    return yaw, pitch


def seg(a, b):
    """yaw/pitch/length/centre for a unit box stretched along Y from a to b."""
    a, b = np.array(a, float), np.array(b, float)
    d = b - a
    L = float(np.linalg.norm(d))
    d /= L
    # rotate +Y onto d: pitch around X then yaw around Y (YXZ order): Y -> (sy*sp... ) use roll/pitch
    pitch = math.degrees(math.acos(max(-1.0, min(1.0, d[1]))))   # tilt from vertical
    yaw = math.degrees(math.atan2(d[0], d[2]))
    return yaw, pitch, L, tuple((a + b) / 2)


class Batch:
    """Many boxes sharing one material -> one MultiMeshInstance3D."""

    def __init__(self):
        self.rows = []

    def add(self, pos, size, yaw=0.0, pitch=0.0, roll=0.0, color=None):
        self.rows.append((mat3(yaw, pitch, roll, size), pos, color))

    def beam(self, a, b, thick, color=None):
        yaw, pitch, L, c = seg(a, b)
        # +Y tilted by `pitch` toward +Z, then yawed
        self.add(c, (thick, L, thick), yaw=yaw, pitch=pitch, color=color)

    def __len__(self):
        return len(self.rows)


class Scene:
    def __init__(self, layers=None):
        self.ext = []
        self.sub = []
        self.nodes = []
        self.layers = layers

    def ext_res(self, type_, path, id_):
        self.ext.append(f'[ext_resource type="{type_}" path="{path}" id="{id_}"]')
        return id_

    def sub_res(self, type_, id_, **props):
        lines = [f'[sub_resource type="{type_}" id="{id_}"]']
        lines += [f"{k} = {v}" for k, v in props.items()]
        self.sub.append("\n".join(lines))
        return id_

    def node(self, name, type_, parent=".", groups=None, **props):
        if self.layers and type_ in ("MeshInstance3D", "MultiMeshInstance3D", "Label3D", "Decal") and "layers" not in props:
            props = {"layers": str(self.layers), **props}
        head = f'[node name="{name}" type="{type_}"' + ("" if parent is None else f' parent="{parent}"')
        if groups:
            head += " groups=[" + ", ".join(f'"{g}"' for g in groups) + "]"
        head += "]"
        lines = [head] + [f"{k} = {v}" for k, v in props.items()]
        self.nodes.append("\n".join(lines))
        return name if parent in (None, ".") else f"{parent}/{name}"

    def instance(self, name, ext_id, parent=".", **props):
        head = f'[node name="{name}" parent="{parent}" instance=ExtResource("{ext_id}")]'
        self.nodes.append("\n".join([head] + [f"{k} = {v}" for k, v in props.items()]))

    def multimesh(self, name, parent, batch, mesh, material, use_colors=False, **props):
        if not len(batch):
            return
        buf = []
        for m, o, c in batch.rows:
            buf += [m[0][0], m[0][1], m[0][2], o[0], m[1][0], m[1][1], m[1][2], o[1], m[2][0], m[2][1], m[2][2], o[2]]
            if use_colors:
                buf += list(c) + [1.0] if len(c) == 3 else list(c)
        mm_id = f"mm_{name}_{len(self.sub)}"
        txt = ", ".join(f"{v:.5g}" for v in buf)
        sub = {"transform_format": "1"}
        if use_colors:
            sub["use_colors"] = "true"
        sub["instance_count"] = str(len(batch))
        sub["mesh"] = f'SubResource("{mesh}")'
        sub["buffer"] = f"PackedFloat32Array({txt})"
        self.sub_res("MultiMesh", mm_id, **sub)
        self.node(name, "MultiMeshInstance3D", parent, multimesh=f'SubResource("{mm_id}")',
                  material_override=f'SubResource("{material}")', **props)

    def write(self, path):
        steps = len(self.ext) + len(self.sub) + 1
        out = [f"[gd_scene load_steps={steps} format=3]", ""]
        out += list(self.ext) + [""]
        for s in self.sub:
            out += [s, ""]
        for n in self.nodes:
            out += [n, ""]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(out), encoding="utf-8")


def std_mat(s, id_, color, rough=0.6, metal=0.0, **extra):
    s.sub_res("StandardMaterial3D", id_, albedo_color=color, metallic=str(metal), roughness=str(rough), **extra)


def glow_mat(s, id_, name_or_rgb, energy, albedo_mul=0.35):
    rgb = pal(name_or_rgb) if isinstance(name_or_rgb, str) else name_or_rgb
    s.sub_res("StandardMaterial3D", id_, albedo_color=col(*[x * albedo_mul for x in rgb]), emission_enabled="true",
              emission=col(*rgb), emission_energy_multiplier=f"{energy:g}")


# =================================================================== the building
def build_vab():
    s = Scene()
    s.ext_res("Shader", "res://shaders/hangar_floor.gdshader", "sh_floor")
    s.ext_res("Shader", "res://shaders/wall_panels.gdshader", "sh_wall")
    s.ext_res("Shader", "res://shaders/hazard_stripes.gdshader", "sh_hazard")
    s.ext_res("Shader", "res://shaders/cutaway_solid.gdshader", "sh_cut")
    s.ext_res("Texture2D", "res://ui/kit/emblem_margin.svg", "tex_emblem")
    s.ext_res("PackedScene", "res://scenes/environment/outside_launch_site.tscn", "outside")

    # ---------------- shared materials (palette)
    s.sub_res("ShaderMaterial", "m_floor", shader='ExtResource("sh_floor")',
              **{"shader_parameter/fade_start": "26.0", "shader_parameter/fade_end": "58.0",
                 "shader_parameter/base_color": col(0.56, 0.565, 0.57)})
    wall_common = {"shader_parameter/base_color": pc("STRUCTURE"), "shader_parameter/seam_color": pc("STRUCTURE", 0.88),
                   "shader_parameter/strip_color": pc("GLASS"), "shader_parameter/dado_color": pc("GUNMETAL"),
                   "shader_parameter/band_color": pc("HAZARD")}
    s.sub_res("ShaderMaterial", "m_wall", shader='ExtResource("sh_wall")',
              **wall_common, **{"shader_parameter/dado_height": "3.5", "shader_parameter/strip_every": "4",
                                "shader_parameter/strip_min_height": "60.0", "shader_parameter/strip_glow": "2.2",
                                "shader_parameter/strip_height": "2.2"})
    s.sub_res("ShaderMaterial", "m_ceiling", shader='ExtResource("sh_wall")',
              **{"shader_parameter/use_xz": "true", "shader_parameter/base_color": pc("STRUCTURE", 0.86),
                 "shader_parameter/seam_color": pc("STRUCTURE", 0.62), "shader_parameter/strip_every": "0",
                 "shader_parameter/panel_size": "Vector2(6, 6)"})
    s.sub_res("ShaderMaterial", "m_door", shader='ExtResource("sh_wall")',
              **{"shader_parameter/base_color": pc("METAL", 1.02), "shader_parameter/seam_color": pc("GUNMETAL", 1.3),
                 "shader_parameter/panel_size": "Vector2(3, 4.5)", "shader_parameter/strip_every": "0",
                 "shader_parameter/seam_width": "0.1", "shader_parameter/metallic_amount": "0.35",
                 "shader_parameter/roughness_base": "0.45"})
    s.sub_res("ShaderMaterial", "m_hazard_stripes", shader='ExtResource("sh_hazard")',
              **{"shader_parameter/color_a": pc("HAZARD"), "shader_parameter/color_b": pc("INK", 1.6)})
    s.sub_res("ShaderMaterial", "m_hazard_ring", shader='ExtResource("sh_hazard")',
              **{"shader_parameter/ring_mode": "true", "shader_parameter/ring_inner": "10.4",
                 "shader_parameter/ring_outer": "11.6", "shader_parameter/ring_segments": "24.0",
                 "shader_parameter/color_a": pc("HAZARD"), "shader_parameter/color_b": pc("INK", 1.6)})
    std_mat(s, "m_structure", pc("STRUCTURE"), rough=0.55, metal=0.05)
    std_mat(s, "m_metal", pc("METAL"), rough=0.38, metal=0.55)
    std_mat(s, "m_gunmetal", pc("GUNMETAL"), rough=0.5, metal=0.45)
    std_mat(s, "m_hazard", pc("HAZARD"), rough=0.45, metal=0.1)
    std_mat(s, "m_accent", pc("ACCENT"), rough=0.5, metal=0.0)
    std_mat(s, "m_accent2", pc("ACCENT_2"), rough=0.55, metal=0.0)
    std_mat(s, "m_panel", pc("PANEL"), rough=0.7, metal=0.0)
    std_mat(s, "m_pad_top", pc("GUNMETAL", 0.8), rough=0.42, metal=0.6)
    glow_mat(s, "m_lamp", "LAMP_WARM", 5.0)
    # wall/ceiling-attached structure: same colours, but cut away when the camera is outside
    for mid, tok, metal, rough, emi, energy in (("m_cut_metal", "METAL", 0.55, 0.38, None, 0.0),
                                                ("m_cut_gunmetal", "GUNMETAL", 0.45, 0.5, None, 0.0),
                                                ("m_cut_hazard", "HAZARD", 0.1, 0.45, None, 0.0),
                                                ("m_cut_lamp", "LAMP_WARM", 0.0, 0.5, "LAMP_WARM", 5.0),
                                                ("m_cut_led", "LAMP_WARM", 0.0, 0.5, "LAMP_WARM", 2.2)):
        rgb = pal(tok) if emi is None else tuple(c * 0.35 for c in pal(tok))
        props = {"shader_parameter/albedo": col(*rgb), "shader_parameter/metallic": str(metal),
                 "shader_parameter/roughness": str(rough), "shader_parameter/half_size": v3(HALF, HEIGHT, HALF)}
        if emi:
            props["shader_parameter/emission_color"] = pc(emi)
            props["shader_parameter/emission_energy"] = str(energy)
        s.sub_res("ShaderMaterial", mid, shader='ExtResource("sh_cut")', **props)
    glow_mat(s, "m_lamp_cool", "GLASS", 3.0)
    glow_mat(s, "m_led_warm", "LAMP_WARM", 2.2)
    glow_mat(s, "m_beacon", "DANGER", 4.0)
    glow_mat(s, "m_signal", "ACCENT", 2.5)
    s.sub_res("StandardMaterial3D", "m_emblem", transparency="2", alpha_scissor_threshold="0.5",
              albedo_texture='ExtResource("tex_emblem")', roughness="0.65", texture_filter="5",
              metallic_specular="0.2", emission_enabled="true", emission_texture='ExtResource("tex_emblem")',
              emission=col(0, 0, 0), emission_energy_multiplier="0.3")
    s.sub_res("SystemFont", "f_sign", font_names='PackedStringArray("Bahnschrift", "Segoe UI", "Arial")',
              font_weight="700")

    # ---------------- meshes
    s.sub_res("PlaneMesh", "q_floor", size=f"Vector2({HALF * 2}, {HALF * 2})")
    s.sub_res("QuadMesh", "q_wall", size=f"Vector2({HALF * 2 + 1}, {HEIGHT + 1})")
    s.sub_res("QuadMesh", "q_wall_back_l", size=f"Vector2({DOOR_X0 + HALF + 0.5}, {HEIGHT + 1})")
    s.sub_res("QuadMesh", "q_wall_back_r", size=f"Vector2({HALF - DOOR_X1 + 0.5}, {HEIGHT + 1})")
    s.sub_res("QuadMesh", "q_wall_header", size=f"Vector2({DOOR_W + 0.2}, {HEIGHT + 1 - DOOR_H})")
    s.sub_res("PlaneMesh", "q_ceiling", size=f"Vector2({HALF * 2 + 2}, {HALF * 2 + 2})", flip_faces="true")
    s.sub_res("PlaneMesh", "q_pad_mark", size="Vector2(26, 26)")
    s.sub_res("QuadMesh", "q_unit", size="Vector2(1, 1)")
    s.sub_res("CylinderMesh", "c_pad", top_radius="9.0", bottom_radius="9.6", height="0.6", radial_segments="96")
    s.sub_res("CylinderMesh", "c_pad_plate", top_radius="5.6", bottom_radius="5.6", height="0.05", radial_segments="96")
    s.sub_res("TorusMesh", "t_ring", inner_radius="9.05", outer_radius="9.3", rings="128", ring_segments="8")
    s.sub_res("TorusMesh", "t_ring_inner", inner_radius="5.6", outer_radius="5.75", rings="128", ring_segments="6")
    s.sub_res("CylinderMesh", "c_disc", top_radius="0.5", bottom_radius="0.5", height="1.0", radial_segments="64")
    s.sub_res("BoxMesh", "b_unit", size="Vector3(1, 1, 1)")
    s.sub_res("CylinderMesh", "c_unit", top_radius="0.5", bottom_radius="0.5", height="1.0", radial_segments="16")

    def box(name, parent, pos, size, mat, yaw=0.0, pitch=0.0, roll=0.0, **kw):
        return s.node(name, "MeshInstance3D", parent, transform=xform(pos, yaw, pitch, roll, size),
                      mesh='SubResource("b_unit")', **{"surface_material_override/0": f'SubResource("{mat}")'}, **kw)

    def cyl(name, parent, pos, radius, height, mat, pitch=0.0, roll=0.0, mesh="c_unit", yaw=0.0):
        return s.node(name, "MeshInstance3D", parent,
                      transform=xform(pos, yaw, pitch, roll, (radius * 2, height, radius * 2)),
                      mesh=f'SubResource("{mesh}")', **{"surface_material_override/0": f'SubResource("{mat}")'})

    def label(name, parent, pos, text, size_m, color, yaw=0.0, pitch=0.0, **kw):
        px = 0.01
        return s.node(name, "Label3D", parent, transform=xform(pos, yaw, pitch), text=f'"{text}"',
                      font='SubResource("f_sign")', font_size=str(int(size_m / px)), pixel_size=str(px),
                      modulate=color, outline_size="0", **kw)

    DOUBLE = {"cast_shadow": "2"}   # double-sided shadow casters: sun never leaks through walls
    INTERIOR = "1"                  # light cull mask for interior lights

    s.node("VAB", "Node3D", None)

    # ---------------- floor + pad
    s.node("Floor", "Node3D")
    s.node("FloorPlane", "MeshInstance3D", "Floor", mesh='SubResource("q_floor")',
           **{"surface_material_override/0": 'SubResource("m_floor")'})
    s.node("PadMarking", "MeshInstance3D", "Floor", transform=xform((0, 0.02, 0)), mesh='SubResource("q_pad_mark")',
           **{"surface_material_override/0": 'SubResource("m_hazard_ring")'})
    s.node("LaunchPad", "MeshInstance3D", "Floor", transform=xform((0, 0.3, 0)), mesh='SubResource("c_pad")',
           **{"surface_material_override/0": 'SubResource("m_gunmetal")'})
    s.node("PadPlate", "MeshInstance3D", "Floor", transform=xform((0, 0.61, 0)), mesh='SubResource("c_pad_plate")',
           **{"surface_material_override/0": 'SubResource("m_pad_top")'})
    s.node("PadRing", "MeshInstance3D", "Floor", transform=xform((0, 0.6, 0)), mesh='SubResource("t_ring")',
           **{"surface_material_override/0": 'SubResource("m_metal")'})
    s.node("PadRingInner", "MeshInstance3D", "Floor", transform=xform((0, 0.64, 0)), mesh='SubResource("t_ring_inner")',
           **{"surface_material_override/0": 'SubResource("m_signal")'})
    studs = Batch()
    for k in range(32):
        a = math.radians(k * 360 / 32)
        studs.add((math.cos(a) * 9.75, 0.08, math.sin(a) * 9.75), (0.45, 0.12, 0.45), yaw=-k * 360 / 32)
    s.multimesh("PadLights", "Floor", studs, "b_unit", "m_led_warm")
    for k in range(4):
        a = math.radians(45 + 90 * k)
        box(f"Clamp{k + 1}", "Floor", (math.cos(a) * 7.2, 1.2, math.sin(a) * 7.2), (1.2, 1.8, 1.2), "m_metal", yaw=-45 - 90 * k)
        box(f"Clamp{k + 1}Cap", "Floor", (math.cos(a) * 7.2, 2.2, math.sin(a) * 7.2), (1.3, 0.25, 1.3), "m_hazard", yaw=-45 - 90 * k)
    # painted floor: roll-out lane from the pad to the door + work-zone border
    paint = Batch()
    for x in (-7.5, 7.5):
        paint.add((x, 0.012, -36.0), (0.35, 0.02, 48.0))
    for z in range(-22, 26, 4):   # dashed border of the pad work zone (x = +-16)
        for x in (-16.0, 16.0):
            paint.add((x, 0.012, z), (0.3, 0.02, 2.2))
    for x in range(-14, 16, 4):
        for z in (-16.0, 24.0):
            if not (z < 0 and -8 < x < 8):
                paint.add((x, 0.012, z), (2.2, 0.02, 0.3))
    s.multimesh("FloorPaint", "Floor", paint, "b_unit", "m_hazard", cast_shadow="0")
    label("PadSign", "Floor", (0, 0.03, 14.0), "PAD A", 1.8, pc("HAZARD", a=0.95), pitch=-90, shaded="true")
    # floor emblem (decal, faces the default camera)
    s.node("FloorEmblem", "Decal", "Floor", transform=xform((-19.0, 0.0, 8.0), 20.0), size=v3(15, 2, 15),
           texture_albedo='ExtResource("tex_emblem")', texture_emission='ExtResource("tex_emblem")',
           emission_energy="0.25", albedo_mix="1.0", normal_fade="0.4",
           upper_fade="0.05", lower_fade="0.05", cull_mask="1")

    # ---------------- walls + ceiling (inward-facing, back-face culled, double-sided shadows)
    s.node("Walls", "Node3D")
    hy = (HEIGHT + 1) / 2
    walls = {"WallFront": ((0, hy, HALF), 180, "q_wall"), "WallLeft": ((-HALF, hy, 0), 90, "q_wall"),
             "WallRight": ((HALF, hy, 0), -90, "q_wall"),
             "WallBackLeft": (((-HALF + DOOR_X0) / 2 - 0.25, hy, -HALF), 0, "q_wall_back_l"),
             "WallBackRight": (((HALF + DOOR_X1) / 2 + 0.25, hy, -HALF), 0, "q_wall_back_r"),
             "WallBackHeader": ((DOOR_CX, DOOR_H + (HEIGHT + 1 - DOOR_H) / 2, -HALF), 0, "q_wall_header")}
    for name, (pos, yaw, mesh) in walls.items():
        s.node(name, "MeshInstance3D", "Walls", transform=xform(pos, yaw), mesh=f'SubResource("{mesh}")',
               **{"surface_material_override/0": 'SubResource("m_wall")'}, **DOUBLE)
    s.node("CeilingPanels", "MeshInstance3D", "Walls", transform=xform((0, HEIGHT, 0)), mesh='SubResource("q_ceiling")',
           **{"surface_material_override/0": 'SubResource("m_ceiling")'}, **DOUBLE)

    # ---------------- structural columns + girders along the walls (light steel)
    s.node("Columns", "Node3D")
    cols = Batch()
    step = 15.0
    n = int(HALF * 2 / step)
    for side, (axis, fixed) in {"Back": ("x", -HALF + 0.8), "Left": ("z", -HALF + 0.8), "Right": ("z", HALF - 0.8)}.items():
        for i in range(n + 1):
            t = -HALF + i * step
            if side == "Back" and DOOR_X0 - 1 <= t <= DOOR_X1 + 1:
                continue
            pos = (t, HEIGHT / 2, fixed) if axis == "x" else (fixed, HEIGHT / 2, t)
            cols.add(pos, (1.4, HEIGHT, 1.4))
            # base plinth
            cols.add((pos[0], 0.6, pos[2]), (2.2, 1.2, 2.2))
        for hgt in (30.0, 60.0, 90.0):
            if axis == "x":
                for x0, x1 in ((-HALF, DOOR_X0), (DOOR_X1, HALF)):
                    cols.add(((x0 + x1) / 2, hgt, fixed), (x1 - x0, 1.2, 1.0))
            else:
                cols.add((fixed, hgt, 0), (1.0, 1.2, HALF * 2))
    s.multimesh("ColumnsAndGirders", "Columns", cols, "b_unit", "m_cut_metal", **DOUBLE)

    # ---------------- ceiling trusses + high-bay lamps
    s.node("Ceiling", "Node3D")
    truss, lamps = Batch(), Batch()
    for i, z in enumerate((-40, -20, 0, 20, 40)):
        truss.add((0, HEIGHT - 2, z), (HALF * 2, 0.8, 0.8))
        truss.add((0, HEIGHT - 7, z), (HALF * 2, 0.6, 0.6))
        for k in range(12):
            x = -HALF + 5 + k * 10
            truss.add((x, HEIGHT - 4.5, z), (0.35, 6.4, 0.35), roll=35 if k % 2 else -35)
        for k in range(6):
            x = -50 + k * 20
            truss.add((x, HEIGHT - 7.5, z), (3.4, 0.5, 1.5))          # lamp housing
            lamps.add((x, HEIGHT - 7.8, z), (3.0, 0.12, 1.2))         # emissive lens
    for x in (-40, -20, 0, 20, 40):   # purlins across the trusses
        truss.add((x, HEIGHT - 1.4, 0), (0.5, 0.5, HALF * 2))
    s.multimesh("Trusses", "Ceiling", truss, "b_unit", "m_cut_metal")
    s.multimesh("HighBayLamps", "Ceiling", lamps, "b_unit", "m_cut_lamp", cast_shadow="0")

    # ---------------- catwalks (gunmetal grating, safety-yellow rails)
    s.node("Catwalks", "Node3D")
    decks, rails, leds = Batch(), Batch(), Batch()
    runs = []   # (axis, fixed, inward, t0, t1, levels)
    runs.append(("z", HALF - 2.5, -1, -HALF + 3, HALF - 3, (20.0, 45.0, 70.0)))       # right wall
    runs.append(("z", -HALF + 2.5, 1, -HALF + 3, HALF - 3, (70.0,)))                  # left wall (emblem below)
    runs.append(("x", -HALF + 2.5, 1, DOOR_X1 + 2, HALF - 3, (20.0, 45.0, 70.0)))     # back wall, right of door
    for axis, fixed, inward, t0, t1, levels in runs:
        span, mid = t1 - t0, (t0 + t1) / 2
        for hgt in levels:
            if axis == "x":
                decks.add((mid, hgt, fixed), (span, 0.25, 3.0))
                rails.add((mid, hgt + 1.1, fixed + 1.45 * inward), (span, 0.12, 0.12))
                rails.add((mid, hgt + 0.55, fixed + 1.45 * inward), (span, 0.08, 0.08))
                leds.add((mid, hgt - 0.1, fixed + 1.5 * inward), (span, 0.08, 0.08))
                for k in range(0, int(span) + 1, 3):
                    rails.add((t0 + k, hgt + 0.55, fixed + 1.45 * inward), (0.1, 1.1, 0.1))
            else:
                decks.add((fixed, hgt, mid), (3.0, 0.25, span))
                rails.add((fixed + 1.45 * inward, hgt + 1.1, mid), (0.12, 0.12, span))
                rails.add((fixed + 1.45 * inward, hgt + 0.55, mid), (0.08, 0.08, span))
                leds.add((fixed + 1.5 * inward, hgt - 0.1, mid), (0.08, 0.08, span))
                for k in range(0, int(span) + 1, 3):
                    rails.add((fixed + 1.45 * inward, hgt + 0.55, t0 + k), (0.1, 1.1, 0.1))
    s.multimesh("Decks", "Catwalks", decks, "b_unit", "m_cut_gunmetal")
    s.multimesh("Handrails", "Catwalks", rails, "b_unit", "m_cut_hazard")
    s.multimesh("EdgeLights", "Catwalks", leds, "b_unit", "m_cut_led", cast_shadow="0")
    for hgt in (20.0, 45.0, 70.0):
        label(f"Level{int(hgt)}", "Catwalks", (HALF - 0.35, hgt + 5.5, -26), f"L{int(hgt)}", 4.0,
              pc("GUNMETAL"), yaw=-90)
        label(f"LevelBack{int(hgt)}", "Catwalks", (DOOR_X1 + 25, hgt + 5.5, -HALF + 0.35), f"L{int(hgt)}", 4.0,
              pc("GUNMETAL"))

    # ---------------- service tower (umbilical gantry) right-front of the pad
    tower_x, tower_z, tower_h, w = 24.0, 2.0, 84.0, 4.0   # outside the default view of the door
    s.node("ServiceTower", "Node3D", ".", transform=xform((tower_x, 0, tower_z)))
    lat = Batch()
    for dx, dz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        lat.add((dx * w / 2, tower_h / 2, dz * w / 2), (0.5, tower_h, 0.5))
    for lvl in range(0, int(tower_h), 6):
        y = lvl + 3.0
        lat.add((0, y, -w / 2), (w, 0.3, 0.3))
        lat.add((0, y, w / 2), (w, 0.3, 0.3))
        lat.add((-w / 2, y, 0), (0.3, 0.3, w))
        lat.add((w / 2, y, 0), (0.3, 0.3, w))
        sgn = 1 if (lvl // 6) % 2 else -1
        for face in (-1, 1):
            lat.beam((-w / 2 * sgn, y, face * w / 2), (w / 2 * sgn, y + 6, face * w / 2), 0.18)
            lat.beam((face * w / 2, y, -w / 2 * sgn), (face * w / 2, y + 6, w / 2 * sgn), 0.18)
    s.multimesh("Lattice", "ServiceTower", lat, "b_unit", "m_metal")
    for k, y in enumerate((18.0, 42.0, 66.0)):
        box(f"AccessArm{k}", "ServiceTower", (-9.5, y, 0), (15.0, 0.5, 1.8), "m_gunmetal")
        box(f"AccessArmRailA{k}", "ServiceTower", (-9.5, y + 1.0, 0.85), (15.0, 0.1, 0.1), "m_hazard")
        box(f"AccessArmRailB{k}", "ServiceTower", (-9.5, y + 1.0, -0.85), (15.0, 0.1, 0.1), "m_hazard")
        box(f"AccessArmTip{k}", "ServiceTower", (-17.1, y, 0), (0.3, 0.7, 2.0), "m_accent")
    box("Cap", "ServiceTower", (0, tower_h + 0.2, 0), (w + 0.6, 0.4, w + 0.6), "m_gunmetal")
    box("Beacon", "ServiceTower", (0, tower_h + 0.9, 0), (0.8, 0.8, 0.8), "m_beacon")
    s.node("BeaconLight", "OmniLight3D", "ServiceTower", transform=xform((0, tower_h + 1.8, 0)),
           light_color=pc("DANGER"), light_energy="1.0", omni_range="14.0", light_cull_mask=INTERIOR)

    # ---------------- overhead bridge crane (safety yellow)
    s.node("Crane", "Node3D", ".", transform=xform((0, 100.0, 6.0)))
    box("GirderA", "Crane", (0, 0, -1.6), (HALF * 2 - 2, 2.2, 1.2), "m_hazard")
    box("GirderB", "Crane", (0, 0, 1.6), (HALF * 2 - 2, 2.2, 1.2), "m_hazard")
    for x in (-(HALF - 3), HALF - 3):
        box(f"EndTruck{'L' if x < 0 else 'R'}", "Crane", (x, 0.6, 0), (2.4, 1.4, 6.0), "m_hazard_stripes")
    box("Trolley", "Crane", (-8.0, -1.6, 0), (5.0, 1.6, 5.0), "m_gunmetal")
    cyl("CableA", "Crane", (-8.6, -14.0, 0), 0.08, 24.0, "m_metal")
    cyl("CableB", "Crane", (-7.4, -14.0, 0), 0.08, 24.0, "m_metal")
    box("HookBlock", "Crane", (-8.0, -26.5, 0), (2.2, 1.6, 1.2), "m_hazard_stripes")
    box("TrolleyLamp", "Crane", (-8.0, -2.5, 0), (2.0, 0.15, 2.0), "m_lamp")

    # ---------------- the open high-bay door in the back wall
    s.node("Door", "Node3D", ".", transform=xform((DOOR_CX, 0, -HALF)))
    jd = 3.2   # reveal depth
    box("JambLeft", "Door", (-DOOR_W / 2 - 1.3, DOOR_H / 2, 0), (2.6, DOOR_H, jd), "m_hazard_stripes", **DOUBLE)
    box("JambRight", "Door", (DOOR_W / 2 + 1.3, DOOR_H / 2, 0), (2.6, DOOR_H, jd), "m_hazard_stripes", **DOUBLE)
    box("Lintel", "Door", (0, DOOR_H + 1.4, 0), (DOOR_W + 5.2, 2.8, jd + 0.4), "m_gunmetal", **DOUBLE)
    box("Threshold", "Door", (0, 0.04, 0), (DOOR_W, 0.08, jd), "m_gunmetal")
    # upper vertical-lift leaves, stacked (raised) in front of the header
    for k in range(5):
        y = DOOR_H + 4.0 + k * 4.0
        box(f"LiftLeaf{k}", "Door", (0, y, 1.0 + 0.55 * (k % 2)), (DOOR_W + 2.0, 4.4, 0.4), "m_door", **DOUBLE)
    # lower sliding leaves, retracted along the outside of the wall
    for side, x0 in (("L", -DOOR_W / 2 - 2.6), ("R", DOOR_W / 2 + 2.6)):
        sgn = -1 if side == "L" else 1
        lw = 6.0 if side == "L" else 7.0
        for k in range(2):
            box(f"SlideLeaf{side}{k}", "Door", (x0 + sgn * (lw / 2 + k * 1.2), 22.0, -1.0 - 0.6 * k),
                (lw, 44.0, 0.4), "m_door", **DOUBLE)
        box(f"Track{side}", "Door", (x0 + sgn * lw / 2, 44.6, -1.3), (lw + 2.0, 0.6, 1.2), "m_gunmetal")
    for k in range(6):
        y = 8 + k * 16
        box(f"DoorLamp{k}L", "Door", (-DOOR_W / 2 - 1.3, y, jd / 2 + 0.05), (0.6, 0.6, 0.15), "m_signal")
        box(f"DoorLamp{k}R", "Door", (DOOR_W / 2 + 1.3, y, jd / 2 + 0.05), (0.6, 0.6, 0.15), "m_signal")

    # ---------------- signage: MARGIN emblem, event banner, building name
    s.node("Signage", "Node3D")
    ez, ey, er = -22.0, 40.0, 16.0
    s.node("WallEmblemBoard", "MeshInstance3D", "Signage",
           transform=xform((-HALF + 1.75, ey, ez), 0, 0, 90, (er * 2 + 1.6, 0.4, er * 2 + 1.6)),
           mesh='SubResource("c_disc")', **{"surface_material_override/0": 'SubResource("m_panel")'})
    s.node("WallEmblem", "MeshInstance3D", "Signage",
           transform=xform((-HALF + 1.98, ey, ez), 90, 0, 0, (er * 2, er * 2, 1)),
           mesh='SubResource("q_unit")', **{"surface_material_override/0": 'SubResource("m_emblem")'})
    s.node("WallEmblemRing", "MeshInstance3D", "Signage",
           transform=xform((-HALF + 1.9, ey, ez), 0, 0, 90, (1, 1, 1)),
           mesh='SubResource("t_emblem_ring")', **{"surface_material_override/0": 'SubResource("m_lamp")'},
           cast_shadow="0")
    s.sub_res("TorusMesh", "t_emblem_ring", inner_radius=f"{er + 0.85}", outer_radius=f"{er + 1.15}", rings="128",
              ring_segments="6")
    label("HangarName", "Signage", (-HALF + 1.95, ey - er - 4.5, ez), "MARGIN  ·  HANGAR 01", 3.2, pc("GUNMETAL"), yaw=90)
    label("HangarNamePT", "Signage", (-HALF + 1.95, ey - er - 7.6, ez), "VEHICLE ASSEMBLY · MONTAGEM DE VEÍCULOS", 1.5,
          pc("GUNMETAL", 1.6), yaw=90)
    # event banner (plain text, no logo artwork) on the wall left of the door
    bx, bw, btop, bh = (-HALF + DOOR_X0) / 2 - 0.8, 10.0, 58.0, 46.0
    s.node("EventBanner", "Node3D", "Signage", transform=xform((bx, 0, -HALF + 1.7)))
    box("Cloth", "Signage/EventBanner", (0, btop - bh / 2, 0), (bw, bh, 0.12), "m_panel")
    box("TopBar", "Signage/EventBanner", (0, btop + 0.3, 0.05), (bw + 1.0, 0.6, 0.35), "m_gunmetal")
    box("BottomBar", "Signage/EventBanner", (0, btop - bh - 0.3, 0.05), (bw + 1.0, 0.6, 0.35), "m_gunmetal")
    box("AccentStripe", "Signage/EventBanner", (0, btop - bh + 3.2, 0.08), (bw, 0.7, 0.05), "m_accent")
    s.node("Emblem", "MeshInstance3D", "Signage/EventBanner", transform=xform((0, btop - 6.2, 0.09), 0, 0, 0, (8.5, 8.5, 1)),
           mesh='SubResource("q_unit")', **{"surface_material_override/0": 'SubResource("m_emblem")'})
    for k, (txt, size, c) in enumerate((("NASA", 2.1, pc("TEXT")), ("SPACE APPS", 1.45, pc("TEXT")),
                                         ("CHALLENGE", 1.45, pc("TEXT")), ("2026", 3.6, pc("ACCENT")))):
        y = btop - 15.5 - k * 4.4 - (1.6 if k == 3 else 0)
        label(f"Line{k}", "Signage/EventBanner", (0, y, 0.1), txt, size, c)
    label("Caption", "Signage/EventBanner", (0, btop - bh + 6.4, 0.1), "MISSION DESIGN GAME", 0.85, pc("TEXT_DIM"))
    label("CaptionPT", "Signage/EventBanner", (0, btop - bh + 5.3, 0.1), "JOGO DE PROJETO DE MISSÕES", 0.7, pc("TEXT_DIM"))
    label("BuildingSign", "Signage", (DOOR_CX, DOOR_H + 8.2, -HALF + 2.1), "VEHICLE ASSEMBLY BUILDING", 5.0, pc("GUNMETAL"))
    label("BuildingSignPT", "Signage", (DOOR_CX, DOOR_H + 4.6, -HALF + 2.1), "MARGIN · HANGAR DE MONTAGEM 01", 2.2,
          pc("ACCENT"))
    label("DoorSign", "Signage", (DOOR_X1 + 3.5, 6.0, -HALF + 0.4), "HIGH BAY DOOR 1", 0.9, pc("GUNMETAL"),
          horizontal_alignment="0")

    # ---------------- props: containers, carts, work platforms (palette colours only)
    s.node("Props", "Node3D")
    crates = [((-46, 30), "m_structure"), ((-46, 36), "m_accent2"), ((-39, 36), "m_structure"),
              ((45, 30), "m_accent2"), ((45, 36), "m_structure"), ((38, 36), "m_gunmetal"),
              ((45, -42), "m_structure"), ((45, -48), "m_accent2")]
    for i, ((x, z), m) in enumerate(crates):
        box(f"Container{i}", "Props", (x, 1.4, z), (6.0, 2.8, 2.6), m, yaw=90 if i % 2 else 0)
        if i % 3 == 0:
            box(f"Container{i}Top", "Props", (x, 4.2, z), (6.0, 2.8, 2.6), "m_structure" if m != "m_structure" else "m_accent2",
                yaw=90 if i % 2 else 0)
    for i, (x, z) in enumerate(((-26, 26), (28, -22), (-30, -16))):
        box(f"Cart{i}", "Props", (x, 0.7, z), (2.4, 1.0, 1.4), "m_hazard")
        box(f"Cart{i}Base", "Props", (x, 0.15, z), (2.2, 0.3, 1.2), "m_gunmetal")
        box(f"Cart{i}Handle", "Props", (x - 1.3, 1.4, z), (0.12, 1.2, 1.2), "m_metal")
    # scissor-lift work platform near the rocket
    s.node("WorkPlatform", "Node3D", "Props", transform=xform((-38.0, 0, -4.0), 25))
    box("Base", "Props/WorkPlatform", (0, 0.5, 0), (3.0, 0.8, 5.0), "m_hazard")
    for k in range(4):
        y = 1.4 + k * 1.6
        box(f"ScissorA{k}", "Props/WorkPlatform", (0, y + 0.8, 0), (0.2, 0.2, 5.2), "m_gunmetal", pitch=17)
        box(f"ScissorB{k}", "Props/WorkPlatform", (0, y + 0.8, 0), (0.2, 0.2, 5.2), "m_gunmetal", pitch=-17)
    box("Deck", "Props/WorkPlatform", (0, 8.0, 0), (3.2, 0.25, 5.4), "m_gunmetal")
    box("Rail", "Props/WorkPlatform", (1.55, 9.0, 0), (0.08, 0.08, 5.4), "m_hazard")
    box("Rail2", "Props/WorkPlatform", (-1.55, 9.0, 0), (0.08, 0.08, 5.4), "m_hazard")

    # ---------------- lights (interior lights only touch layer 1; the sun lives in the outside scene)
    s.node("Lights", "Node3D")
    for i, (x, z) in enumerate(((-30, -30), (30, -30), (-30, 15), (30, 15), (0, 45), (0, -45))):
        # GraphicsQuality turns "optional_light" lights off below HIGH and raises the ambient
        s.node(f"HighBay{i}", "OmniLight3D", "Lights", groups=["optional_light"] if i not in (2, 3) else None,
               transform=xform((x, 98.0, z)),
               light_color=pc("LAMP_WARM"), light_energy="1.3", light_indirect_energy="1.0", omni_range="120.0",
               omni_attenuation="0.55", light_specular="0.25", light_cull_mask=INTERIOR)
    # key + fill floods on the rocket (from the front, warm/cool balance; only the key casts shadows)
    for name, pos, colr, energy, shadow in (("KeyFlood", (40.0, 66.0, 52.0), "LAMP_WARM", 7.0, True),
                                            ("FillFlood", (-44.0, 50.0, 40.0), "LAMP_COOL", 3.2, False)):
        yaw, pitch = look_angles((0 - pos[0], 24 - pos[1], 0 - pos[2]))
        s.node(name, "SpotLight3D", "Lights", transform=xform(pos, yaw, pitch), light_color=pc(colr),
               light_energy=str(energy), spot_range="170.0", spot_angle="24.0", spot_angle_attenuation="0.6",
               spot_attenuation="0.35", light_specular="0.4", shadow_enabled="true" if shadow else "false",
               shadow_blur="1.5", light_cull_mask=INTERIOR)
    for i, (x, z) in enumerate(((-48, -30), (-48, 30), (48, -30), (48, 30))):
        s.node(f"WallWash{i}", "OmniLight3D", "Lights", groups=["optional_light"], transform=xform((x, 34, z)),
               light_color=pc("LAMP_COOL"), light_energy="0.6", omni_range="55.0", omni_attenuation="0.8",
               light_specular="0.1", light_cull_mask=INTERIOR)
    s.node("PadUplight", "OmniLight3D", "Lights", transform=xform((0, 3.0, 12.0)),
           light_color=pc("LAMP_WARM"), light_energy="1.2", omni_range="22.0", omni_attenuation="1.2",
           light_cull_mask=INTERIOR)
    s.node("Reflections", "ReflectionProbe", "Lights", transform=xform((0, HEIGHT / 2, 0)),
           size=v3(HALF * 2, HEIGHT, HALF * 2), box_projection="true", interior="true", intensity="0.7",
           ambient_mode="1", update_mode="0")

    # ---------------- the planet outside the door
    s.instance("Outside", "outside")

    # ---------------- the Cometling ground crew (NPCs, navmesh, workbench; see docs/creatures.md)
    s.ext_res("PackedScene", "res://scenes/npc/hangar_crowd.tscn", "crowd")
    s.instance("HangarCrowd", "crowd")

    s.write(OUT)
    print(f"{len(s.nodes)} nodes, {len(s.sub)} sub-resources -> {OUT}")


# =================================================================== outside: launch site
def hash2(ix, iz, seed=0):
    h = np.sin(ix * 127.1 + iz * 311.7 + seed * 74.7) * 43758.5453
    return h - np.floor(h)


def vnoise(x, z, seed=0):
    ix, iz = np.floor(x), np.floor(z)
    fx, fz = x - ix, z - iz
    fx, fz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
    a, b = hash2(ix, iz, seed), hash2(ix + 1, iz, seed)
    c, d = hash2(ix, iz + 1, seed), hash2(ix + 1, iz + 1, seed)
    return (a + (b - a) * fx) * (1 - fz) + (c + (d - c) * fx) * fz


def fbm(x, z, octaves=5, seed=0):
    v, a, f = 0.0, 0.5, 1.0
    for o in range(octaves):
        v = v + vnoise(x * f, z * f, seed + o) * a
        f *= 2.03
        a *= 0.5
    return v


def coast_s(x, z):
    t = x * COAST_D[0] + z * COAST_D[1]
    return ((x - COAST_P1[0]) * COAST_N[0] + (z - COAST_P1[1]) * COAST_N[1]
            + 40.0 * np.sin(t * 0.004) + 25.0 * np.sin(t * 0.011 + 1.3))


def terrain_height(x, z):
    """Voxel terrain height (m) outside the flat launch-site area."""
    r = np.hypot(x, z)
    s = coast_s(x, z)
    # keep a flat corridor hangar -> pads, and the pads' surroundings
    # (distance to each flat site minus its radius; blend over 300 m)
    d_site = np.minimum.reduce([np.hypot(x, z) - 420.0, np.hypot(x - PAD_OUT[0], z - PAD_OUT[1]) - 330.0,
                                np.hypot(x - PAD_B[0], z - PAD_B[1]) - 220.0,
                                np.hypot(x - (PAD_OUT[0] * 0.5), z - (PAD_OUT[1] * 0.5)) - 300.0])
    flat = np.clip(d_site / 300.0, 0, 1)
    hills = (fbm(x / 520.0, z / 520.0, 4, 3) - 0.42) * 70.0
    ridge = 1.0 - np.abs(2.0 * fbm(x / 900.0 + 5.0, z / 900.0 - 2.0, 5, 11) - 1.0)
    # mountain range on the far north-west (left of the door view) and lower ridges behind
    ang = np.degrees(np.arctan2(-x, -z))               # 0 = straight out the door, + = toward -x
    m_mask = np.clip((r - 1000.0) / 500.0, 0, 1) * np.clip((s * -1.0 - 300.0) / 400.0, 0, 1)
    sector = np.clip(1.0 - np.abs(ang - 60.0) / 75.0, 0.25, 1.0)
    mountains = (ridge ** 2.2) * 360.0 * m_mask * sector
    h = (np.maximum(hills, 0) + mountains) * flat
    h *= np.clip(-s / 220.0, 0, 1)                       # sink toward the coast
    return h


def build_site():
    s = Scene(layers=LAYER_OUT)
    s.ext_res("Shader", "res://shaders/sky_dome.gdshader", "sh_sky")
    s.ext_res("Shader", "res://shaders/outside_ground.gdshader", "sh_ground")
    s.ext_res("Shader", "res://shaders/hangar_floor.gdshader", "sh_floor")

    sky_h = pal("ACCENT_2")
    zen = (0.24, 0.47, 0.78)
    hor = (0.80, 0.87, 0.93)
    s.sub_res("ShaderMaterial", "m_sky", shader='ExtResource("sh_sky")',
              **{"shader_parameter/zenith_color": col(*zen), "shader_parameter/horizon_color": col(*hor),
                 "shader_parameter/ground_color": col(0.72, 0.78, 0.80), "shader_parameter/sun_color": pc("SUN"),
                 "shader_parameter/sun_dir": v3(*TO_SUN)})
    s.sub_res("ShaderMaterial", "m_ground", shader='ExtResource("sh_ground")',
              **{"shader_parameter/coast_origin": f"Vector2({COAST_P1[0]:g}, {COAST_P1[1]:g})",
                 "shader_parameter/coast_normal": f"Vector2({COAST_N[0]:.5f}, {COAST_N[1]:.5f})",
                 "shader_parameter/coast_dir": f"Vector2({COAST_D[0]:.5f}, {COAST_D[1]:.5f})"})
    concrete = mix(pal("METAL"), pal("STRUCTURE"), 0.35)
    s.sub_res("ShaderMaterial", "m_apron", shader='ExtResource("sh_floor")',
              **{"shader_parameter/base_color": col(*[c * 0.92 for c in concrete]),
                 "shader_parameter/joint_color": col(*[c * 0.7 for c in concrete]),
                 "shader_parameter/slab_size": "8.0", "shader_parameter/fade_start": "0.0",
                 "shader_parameter/fade_end": "0.01", "shader_parameter/roughness_base": "0.75"})
    std_mat(s, "m_gravel", col(0.74, 0.71, 0.65), rough=0.95)
    std_mat(s, "m_concrete", col(*[c * 0.95 for c in concrete]), rough=0.85)
    std_mat(s, "m_structure", pc("STRUCTURE"), rough=0.55, metal=0.05)
    std_mat(s, "m_metal", pc("METAL"), rough=0.4, metal=0.5)
    std_mat(s, "m_gunmetal", pc("GUNMETAL"), rough=0.5, metal=0.4)
    std_mat(s, "m_hazard", pc("HAZARD"), rough=0.45)
    std_mat(s, "m_accent", pc("ACCENT"), rough=0.5)
    std_mat(s, "m_ink", pc("INK", 1.6), rough=0.5)
    std_mat(s, "m_vcolor", col(1, 1, 1), rough=0.92, vertex_color_use_as_albedo="true", vertex_color_is_srgb="true")
    s.sub_res("StandardMaterial3D", "m_cloud", albedo_color=col(1, 1, 1), roughness="1.0",
              vertex_color_use_as_albedo="true", vertex_color_is_srgb="true", emission_enabled="true",
              emission=col(0.85, 0.9, 0.96), emission_energy_multiplier="0.8")
    glow_mat(s, "m_lamp", "LAMP_WARM", 3.0)
    glow_mat(s, "m_beacon", "DANGER", 5.0)

    s.sub_res("SphereMesh", "sph_sky", radius=f"{SKY_R}", height=f"{SKY_R * 2}", radial_segments="64", rings="32")
    s.sub_res("PlaneMesh", "q_ground", size=f"Vector2({SKY_R * 2}, {SKY_R * 2})")
    s.sub_res("BoxMesh", "b_unit", size="Vector3(1, 1, 1)")
    s.sub_res("CylinderMesh", "c_unit", top_radius="0.5", bottom_radius="0.5", height="1.0", radial_segments="24")
    s.sub_res("CylinderMesh", "c_cone", top_radius="0.0", bottom_radius="0.5", height="1.0", radial_segments="24")
    s.sub_res("CylinderMesh", "c_oct", top_radius="0.44", bottom_radius="0.5", height="1.0", radial_segments="8")
    s.sub_res("CylinderMesh", "c_mast", top_radius="0.25", bottom_radius="0.5", height="1.0", radial_segments="8")
    s.sub_res("SphereMesh", "sph_unit", radius="0.5", height="1.0", radial_segments="24", rings="12")

    def box(name, parent, pos, size, mat, yaw=0.0, pitch=0.0, roll=0.0, **kw):
        return s.node(name, "MeshInstance3D", parent, transform=xform(pos, yaw, pitch, roll, size),
                      mesh='SubResource("b_unit")', **{"surface_material_override/0": f'SubResource("{mat}")'}, **kw)

    def mesh(name, parent, m, pos, size, mat, yaw=0.0, pitch=0.0, roll=0.0, **kw):
        return s.node(name, "MeshInstance3D", parent, transform=xform(pos, yaw, pitch, roll, size),
                      mesh=f'SubResource("{m}")', **{"surface_material_override/0": f'SubResource("{mat}")'}, **kw)

    NOSHADOW = {"cast_shadow": "0"}
    s.node("OutsideLaunchSite", "Node3D", None)

    # ---------------- sky + sun
    s.node("Sky", "Node3D")
    s.node("SkyDome", "MeshInstance3D", "Sky", mesh='SubResource("sph_sky")',
           **{"surface_material_override/0": 'SubResource("m_sky")'}, **NOSHADOW, extra_cull_margin="16384.0")
    yaw, pitch = look_angles(tuple(-c for c in TO_SUN))
    s.node("Sun", "DirectionalLight3D", "Sky", transform=xform((0, 200, 0), yaw, pitch), light_color=pc("SUN"),
           light_energy="2.1", light_indirect_energy="1.2", light_angular_distance="0.3", shadow_enabled="true",
           shadow_bias="0.04", shadow_normal_bias="1.2", shadow_blur="1.2", directional_shadow_mode="2",
           directional_shadow_split_1="0.06", directional_shadow_split_2="0.18", directional_shadow_split_3="0.45",
           directional_shadow_blend_splits="true", directional_shadow_max_distance="520.0",
           directional_shadow_pancake_size="60.0")

    # ---------------- ground, apron, crawlerway
    s.node("Ground", "Node3D")
    s.node("GroundPlane", "MeshInstance3D", "Ground", transform=xform((0, -0.25, 0)), mesh='SubResource("q_ground")',
           **{"surface_material_override/0": 'SubResource("m_ground")'}, **NOSHADOW)
    # apron slabs around the building (top at y = 0, the hangar floor fills the footprint)
    ap = [("ApronFront", (-15, -0.2, -125), (230, 0.4, 130)), ("ApronBack", (0, -0.2, 75), (200, 0.4, 30)),
          ("ApronLeft", (-95, -0.2, 0), (70, 0.4, 120)), ("ApronRight", (80, -0.2, 0), (40, 0.4, 120))]
    for name, pos, size in ap:
        box(name, "Ground", pos, size, "m_apron", **NOSHADOW)
    # crawlerway: two gravel lanes + grass median, from the door to the launch complex ramp
    s.node("Crawlerway", "Node3D")
    start = np.array([0.0, -190.0])
    end = np.array([PAD_OUT[0], PAD_OUT[1]]) + np.array([0.0, 0.0])
    d = end - start
    L = float(np.linalg.norm(d))
    u = d / L
    nrm = np.array([-u[1], u[0]])
    road_yaw = math.degrees(math.atan2(u[0], u[1]))
    ramp_len = 70.0
    road_end = end - u * (95.0 + ramp_len)
    Lr = float(np.linalg.norm(road_end - start))
    for k, off in enumerate((-11.0, 11.0)):
        c = (start + road_end) / 2 + nrm * off
        box(f"Lane{k}", "Crawlerway", (c[0], -0.12, c[1]), (13.0, 0.3, Lr), "m_gravel", yaw=road_yaw, **NOSHADOW)
    # straight link from the apron to the diagonal crawlerway
    box("ApronLink", "Crawlerway", (0, -0.13, -175), (36, 0.3, 30), "m_gravel", **NOSHADOW)
    posts, heads = Batch(), Batch()
    for t in np.arange(0.0, Lr, 30.0):
        for off in (-19.5, 19.5):
            p = start + u * t + nrm * off
            posts.add((p[0], 4.0, p[1]), (0.35, 8.0, 0.35))
            heads.add((p[0], 8.1, p[1]), (1.1, 0.35, 0.6), yaw=road_yaw)
    s.multimesh("LightPosts", "Crawlerway", posts, "b_unit", "m_metal", **NOSHADOW)
    s.multimesh("LightHeads", "Crawlerway", heads, "b_unit", "m_lamp", **NOSHADOW)

    # ---------------- launch complex A
    def launch_complex(name, center, scale=1.0, with_rocket=True):
        cx, cz = center
        g = s.node(name, "Node3D", ".", transform=xform((cx, 0, cz), road_yaw + 180.0))
        H = 9.0 * scale
        mesh("Hardstand", g, "c_oct", (0, H / 2 - 0.3, 0), (190 * scale, H, 190 * scale), "m_concrete", yaw=22.5, **NOSHADOW)
        # ramp up to the pad (local +z = toward the hangar)
        rl = ramp_len * scale
        ang = math.degrees(math.atan2(H, rl))
        box("Ramp", g, (0, H / 2 - 0.3, 95 * scale + rl / 2 - 6), (42 * scale, 0.6, math.hypot(H, rl)), "m_concrete",
            pitch=ang, **NOSHADOW)
        box("PadDeck", g, (0, H + 0.2, 0), (60 * scale, 0.6, 60 * scale), "m_apron")
        box("FlameTrench", g, (0, H + 0.25, -24 * scale), (14 * scale, 0.6, 40 * scale), "m_ink")
        box("FlameDeflector", g, (0, H + 1.2, -8 * scale), (12 * scale, 2.4, 6 * scale), "m_gunmetal", pitch=-30)
        # fixed service structure (lattice) + access arms
        th, tw = 118.0 * scale, 12.0 * scale
        tx, tz = 22.0 * scale, -4.0 * scale
        lat = Batch()
        for dx, dz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            lat.add((tx + dx * tw / 2, H + th / 2, tz + dz * tw / 2), (1.0 * scale, th, 1.0 * scale))
        lvl_h = 8.0 * scale
        nlv = int(th / lvl_h)
        for k in range(nlv):
            y = H + (k + 1) * lvl_h
            for a, b in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
                pa = (tx + a[0] * tw / 2, y, tz + a[1] * tw / 2)
                pb = (tx + b[0] * tw / 2, y, tz + b[1] * tw / 2)
                lat.beam(pa, pb, 0.55 * scale)
                lo_a, lo_b = (pa[0], y - lvl_h, pa[2]), (pb[0], y - lvl_h, pb[2])
                if k % 2:
                    lat.beam(lo_a, pb, 0.35 * scale)
                else:
                    lat.beam(lo_b, pa, 0.35 * scale)
            if k % 3 == 2:
                lat.add((tx, y, tz), (tw, 0.5 * scale, tw))   # floor
        s.multimesh("TowerLattice", g, lat, "b_unit", "m_metal")
        for k, y in enumerate((0.42, 0.62, 0.8)):
            yy = H + th * y
            box(f"AccessArm{k}", g, (tx - tw / 2 - 7 * scale, yy, tz), (14 * scale, 2.2 * scale, 3.2 * scale), "m_structure")
            box(f"AccessArmRail{k}", g, (tx - tw / 2 - 7 * scale, yy + 1.4 * scale, tz), (14 * scale, 0.3 * scale, 3.4 * scale),
                "m_hazard")
        box("TowerCrane", g, (tx, H + th + 3 * scale, tz), (tw + 6 * scale, 2 * scale, 3 * scale), "m_hazard")
        box("TowerTop", g, (tx, H + th + 0.6 * scale, tz), (tw + 1.0, 1.2 * scale, tw + 1.0), "m_gunmetal")
        box("TowerBeacon", g, (tx, H + th + 5 * scale, tz), (1.6, 1.6, 1.6), "m_beacon", **NOSHADOW)
        # lightning masts (three, with catenary wires) + water tower + spherical propellant tanks
        mh = 175.0 * scale
        masts = [(-52 * scale, 40 * scale), (52 * scale, 40 * scale), (0.0, -70 * scale)]
        for k, (mx, mz) in enumerate(masts):
            mesh(f"LightningMast{k}", g, "c_mast", (mx, mh / 2, mz), (3.2 * scale, mh, 3.2 * scale), "m_metal")
            box(f"MastBeacon{k}", g, (mx, mh + 1.0, mz), (1.4, 1.4, 1.4), "m_beacon", **NOSHADOW)
            box(f"MastBand{k}", g, (mx, mh * 0.75, mz), (2.4 * scale, 6 * scale, 2.4 * scale), "m_accent")
        wires = Batch()
        for i in range(3):
            a, b = masts[i], masts[(i + 1) % 3]
            # sagging catenary in 6 segments
            pts = []
            for k in range(7):
                t = k / 6
                sag = 4 * 0.12 * t * (1 - t)
                pts.append((a[0] + (b[0] - a[0]) * t, mh - sag * math.hypot(b[0] - a[0], b[1] - a[1]),
                            a[1] + (b[1] - a[1]) * t))
            for p0, p1 in zip(pts, pts[1:]):
                wires.beam(p0, p1, 0.22)
            # ground wire from each mast outward
            out = np.array(a) * 1.9
            wires.beam((a[0], mh, a[1]), (out[0], 0.5, out[1]), 0.22)
        s.multimesh("CatenaryWires", g, wires, "b_unit", "m_gunmetal", **NOSHADOW)
        if scale >= 1.0:
            wt = s.node("WaterTower", "Node3D", g, transform=xform((-95.0, 0, -40.0)))
            for k, (dx, dz) in enumerate(((-6, -6), (6, -6), (6, 6), (-6, 6))):
                box(f"Leg{k}", wt, (dx * 0.8, 22.0, dz * 0.8), (1.0, 44.0, 1.0), "m_metal", roll=dx * 0.7, pitch=-dz * 0.7)
            mesh("Tank", wt, "sph_unit", (0, 52.0, 0), (20.0, 17.0, 20.0), "m_structure")
            mesh("Band", wt, "c_unit", (0, 52.0, 0), (20.6, 2.5, 20.6), "m_accent")
            for k, (px, pz, r) in enumerate(((95.0, -30.0, 11.0), (100.0, 10.0, 9.0))):
                mesh(f"PropellantSphere{k}", g, "sph_unit", (px, r + 3.0, pz), (2 * r, 2 * r, 2 * r), "m_structure")
                box(f"PropellantSkirt{k}", g, (px, 1.6, pz), (r * 1.2, 3.2, r * 1.2), "m_gunmetal")
            box("Blockhouse", g, (-70.0, 4.0, 70.0), (28.0, 8.0, 16.0), "m_structure")
            box("BlockhouseBand", g, (-70.0, 7.4, 70.0), (28.4, 1.0, 16.4), "m_accent2_like")
        if with_rocket:
            r_ = s.node("RocketOnPad", "Node3D", g, transform=xform((0, H + 0.5, 0)))
            core_r, core_h = 4.2, 58.0
            mesh("Core", r_, "c_unit", (0, 4 + core_h / 2, 0), (core_r * 2, core_h, core_r * 2), "m_structure")
            mesh("Interstage", r_, "c_unit", (0, 4 + core_h + 2, 0), (core_r * 2, 4, core_r * 2), "m_ink")
            mesh("Upper", r_, "c_unit", (0, 4 + core_h + 4 + 9, 0), (core_r * 2, 18, core_r * 2), "m_structure")
            mesh("BrandBand", r_, "c_unit", (0, 4 + core_h - 10, 0), (core_r * 2 + 0.1, 3, core_r * 2 + 0.1), "m_accent")
            mesh("Fairing", r_, "c_unit", (0, 4 + core_h + 22 + 6, 0), (core_r * 2.3, 12, core_r * 2.3), "m_structure")
            mesh("Nose", r_, "c_cone", (0, 4 + core_h + 22 + 12 + 7, 0), (core_r * 2.3, 14, core_r * 2.3), "m_structure")
            for side in (-1, 1):
                bx = side * (core_r + 2.4)
                mesh(f"Booster{side}", r_, "c_unit", (bx, 4 + 22, 0), (4.0, 40, 4.0), "m_structure")
                mesh(f"BoosterNose{side}", r_, "c_cone", (bx, 4 + 42 + 3, 0), (4.0, 6, 4.0), "m_structure")
                mesh(f"BoosterBand{side}", r_, "c_unit", (bx, 4 + 6, 0), (4.1, 2.0, 4.1), "m_ink")
            mesh("MobileLauncher", r_, "c_oct", (0, 1.6, 0), (26, 3.2, 26), "m_gunmetal", yaw=22.5)
        return g

    # a light-blue painted material for small buildings (ACCENT_2)
    std_mat(s, "m_accent2_like", pc("ACCENT_2"), rough=0.6)
    launch_complex("LaunchComplexA", PAD_OUT, 1.0, True)
    launch_complex("LaunchComplexB", PAD_B, 0.7, False)

    # ---------------- voxel terrain (MultiMesh, vertex colours)
    s.node("Terrain", "Node3D")
    blocks = Batch()

    def color_for(h, x, z, sval):
        j = 0.94 + 0.1 * float(hash2(np.floor(x / 7), np.floor(z / 7), 5))
        if h < 8 and sval > -90:
            c = (0.84, 0.78, 0.62)
        elif h < 30:
            c = (0.47, 0.65, 0.34)
        elif h < 110:
            c = (0.32, 0.50, 0.30) if hash2(np.floor(x / 40), np.floor(z / 40), 2) > 0.3 else (0.42, 0.58, 0.32)
        elif h < 210:
            c = (0.55, 0.52, 0.47)
        else:
            c = (0.94, 0.95, 0.97)
        return tuple(min(1.0, v * j) for v in c)

    def grid(cell, lo, hi, inner, step):
        xs = np.arange(lo + cell / 2, hi, cell)
        X, Z = np.meshgrid(xs, xs)
        X, Z = X.ravel(), Z.ravel()
        keep = (np.maximum(np.abs(X), np.abs(Z)) >= inner) & (np.hypot(X, Z) < SKY_R - 120)
        X, Z = X[keep], Z[keep]
        Hh = terrain_height(X, Z)
        S = coast_s(X, Z)
        for x, z, h, sv in zip(X, Z, Hh, S):
            if sv > -4 or h < step * 0.6:
                continue
            hq = max(step, round(h / step) * step)
            blocks.add((float(x), (hq - 3.0) / 2, float(z)), (cell, hq + 3.0, cell), color=color_for(hq, x, z, sv))

    grid(20.0, -800.0, 800.0, 0.0, 5.0)
    grid(48.0, -2208.0, 2208.0, 800.0, 12.0)
    s.multimesh("VoxelTerrain", "Terrain", blocks, "b_unit", "m_vcolor", use_colors=True, **NOSHADOW)

    # ---------------- voxel trees (groves around the site)
    rng = np.random.default_rng(7)
    trees = Batch()
    groves = [(-260, -260), (-330, -520), (120, -330), (-60, 260), (220, 160), (-280, 120), (40, -560), (-300, -820),
              (60, -900), (-520, -700)]
    for gx, gz in groves:
        for _ in range(int(rng.integers(14, 28))):
            x = gx + rng.normal(0, 38)
            z = gz + rng.normal(0, 38)
            if coast_s(x, z) > -60:
                continue
            if abs(x) < 120 and -230 < z < 100:
                continue
            # keep the crawlerway clear
            rel = np.array([x, z]) - start
            along = rel @ u
            if -20 < along < L + 40 and abs(rel @ nrm) < 45:
                continue
            hgt = float(rng.uniform(6, 12))
            w_ = float(rng.uniform(4, 7))
            green = mix((0.28, 0.48, 0.27), (0.42, 0.6, 0.32), float(rng.uniform()))
            trees.add((x, 1.5, z), (1.0, 3.0, 1.0), color=(0.42, 0.32, 0.24))
            trees.add((x, 3.0 + hgt / 2, z), (w_, hgt, w_), yaw=float(rng.uniform(0, 90)), color=green)
            if rng.uniform() < 0.5:
                trees.add((x, 3.0 + hgt + 1.2, z), (w_ * 0.6, 2.4, w_ * 0.6), color=tuple(v * 1.08 for v in green))
    s.multimesh("VoxelTrees", "Terrain", trees, "b_unit", "m_vcolor", use_colors=True)

    # ---------------- voxel clouds
    s.node("Clouds", "Node3D")
    clouds = Batch()
    for k in range(34):
        a = rng.uniform(0, 2 * math.pi)
        if k < 14:   # bias toward the view through the door
            a = math.radians(rng.uniform(-40, 40)) + math.pi  # around -z
        r = rng.uniform(900, 2050)
        cx, cz = math.sin(a) * r, math.cos(a) * r
        cy = rng.uniform(170, 420)
        n_ = int(rng.integers(5, 11))
        for i in range(n_):
            dx, dz = rng.normal(0, 38), rng.normal(0, 26)
            sw = rng.uniform(40, 90)
            sh = rng.uniform(14, 30)
            top = rng.uniform() < 0.5
            shade = 1.0 if top else 0.96
            clouds.add((cx + dx, cy + (sh * 0.5 if top else 0), cz + dz), (sw, sh, sw * rng.uniform(0.6, 1.0)),
                       yaw=float(rng.uniform(0, 90)), color=(shade, shade, shade))
    s.multimesh("VoxelClouds", "Clouds", clouds, "b_unit", "m_cloud", use_colors=True, **NOSHADOW)

    s.write(OUT_SITE)
    print(f"{len(s.nodes)} nodes, {len(blocks)} terrain blocks, {len(trees)} tree blocks, {len(clouds)} cloud blocks "
          f"-> {OUT_SITE}")


if __name__ == "__main__":
    build_site()
    build_vab()
