"""Writes scenes/solar_system/solar_system.tscn: the voxel solar-system map, as a normal
Godot editor scene (open it in the editor and tweak anything by hand afterwards;
re-running this script overwrites it).

Inputs: data/solar_system.json (real data) + the visual scale formulas and LOD table in
tools/planet_gen.py (run that first so assets/voxel/planets/*.glb exist).

Scene layout:
    SolarSystem (solar_system.gd)
      WorldEnvironment (procedural star sky, glow)   SunLight (OmniLight3D at the origin)
      Bodies/<Body> (orbit_body.gd: orbit plane) /Pivot/Anchor/Tilt/Spin/LOD0..2
        moons are SolarBody children of their parent's Anchor
      CameraRig (space_camera.gd)/Camera3D
      UI (CanvasLayer, theme res://ui/margin_theme.tres): top bar with time controls,
         body list, info card, help footer

LOD: each body has 3 voxel meshes switched by GeometryInstance3D visibility ranges
(distance from the camera, scene units, r = visual radius):
    lod0  [0, LOD0_K*r]       lod1 [LOD0_K*r, LOD1_K*r]      lod2 [LOD1_K*r, inf)
with fade margins of FADE*range. See docs/solar_system.md.

Usage: python tools/build_solar_system_scene.py
"""
import json
import math
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import planet_gen as pg  # noqa: E402  (scale formulas + LOD table, single source of truth)

OUT = ROOT / "scenes" / "solar_system" / "solar_system.tscn"
DATA = ROOT / "data" / "solar_system.json"

LOD0_K = 14.0     # lod0 -> lod1 at 14 radii (planet ~155 px tall at 1600x900, fov 50)
LOD1_K = 46.0     # lod1 -> lod2 at 46 radii (~47 px)
FADE = 0.12       # fade margin, fraction of the switch distance
MOON_FAR = 700.0  # moons are culled entirely beyond this camera distance
MOON_UI_FAR = 120.0   # moon labels / orbit lines only near their parent
EDITOR_DAYS = 9797.0  # 2026-10-28 (days after J2000), same constant as orbit_body.gd
CAMERA_FOV = 50.0
SKIP_LABEL_K = 3.2    # labels hide when the camera is closer than this many radii
LABEL_FAR_K = 5.6     # planet labels hide beyond this many orbit radii (declutter)

ORBIT_COLORS = {
    "mercury": (0.75, 0.72, 0.68), "venus": (0.98, 0.84, 0.55), "earth": (0.4, 0.72, 1.0),
    "mars": (1.0, 0.5, 0.32), "jupiter": (0.95, 0.75, 0.52), "saturn": (0.98, 0.88, 0.6),
    "uranus": (0.55, 0.92, 0.95), "neptune": (0.45, 0.6, 1.0), "pluto": (0.85, 0.75, 0.65),
    "moon": (0.75, 0.78, 0.85), "europa": (0.9, 0.82, 0.7),
}
ATMOSPHERE = {  # id -> (shell scale, intensity, power)
    "earth": (1.09, 1.9, 2.2), "venus": (1.08, 1.4, 2.0), "mars": (1.06, 0.8, 2.6),
    "uranus": (1.05, 0.9, 2.6), "neptune": (1.05, 1.1, 2.6),
}
FOCUS_KEYS = ["sun", "mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune", "pluto"]


class Scene:
    def __init__(self):
        self.ext, self.sub, self.nodes, self.conns, self.editable = [], [], [], [], []

    def ext_res(self, type_, path, id_):
        self.ext.append(f'[ext_resource type="{type_}" path="{path}" id="{id_}"]')
        return id_

    def sub_res(self, type_, id_, **props):
        lines = [f'[sub_resource type="{type_}" id="{id_}"]'] + [f"{k} = {v}" for k, v in props.items()]
        self.sub.append("\n".join(lines))
        return id_

    def node(self, name, type_=None, parent=".", instance=None, index=None, **props):
        head = f'[node name="{name}"' + (f' type="{type_}"' if type_ else "")
        if parent is not None:
            head += f' parent="{parent}"'
        if instance:
            head += f' instance=ExtResource("{instance}")'
        if index is not None:
            head += f' index="{index}"'
        lines = [head + "]"] + [f"{k} = {v}" for k, v in props.items()]
        self.nodes.append("\n".join(lines))
        return name if parent in (None, ".") else f"{parent}/{name}"

    def connect(self, signal, from_, method, to="."):
        self.conns.append(f'[connection signal="{signal}" from="{from_}" to="{to}" method="{method}"]')

    def write(self, path):
        steps = len(self.ext) + len(self.sub) + 1
        out = [f"[gd_scene load_steps={steps} format=3]", ""] + self.ext + [""]
        for s in self.sub:
            out += [s, ""]
        for n in self.nodes:
            out += [n, ""]
        out += self.conns + [""] if self.conns else []
        out += [f'[editable path="{e}"]' for e in self.editable] + [""]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(out), encoding="utf-8")


def f(x):
    return f"{x:.6g}"


def col(r, g, b, a=1.0):
    return f"Color({f(r)}, {f(g)}, {f(b)}, {f(a)})"


def hexcol(h, a=1.0):
    return col(int(h[1:3], 16) / 255, int(h[3:5], 16) / 255, int(h[5:7], 16) / 255, a)


def s(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def basis_axis_angle(axis, ang):
    x, y, z = axis
    n = math.sqrt(x * x + y * y + z * z)
    x, y, z = x / n, y / n, z / n
    c, si, t = math.cos(ang), math.sin(ang), 1 - math.cos(ang)
    return [[t * x * x + c, t * x * y - si * z, t * x * z + si * y],
            [t * x * y + si * z, t * y * y + c, t * y * z - si * x],
            [t * x * z - si * y, t * y * z + si * x, t * z * z + c]]


def xform(m=None, pos=(0, 0, 0), scale=1.0):
    m = m or [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    vals = [m[i][j] * scale for i in range(3) for j in range(3)] + list(pos)
    return "Transform3D(" + ", ".join(f(v) for v in vals) + ")"


def rot_y(a):
    return basis_axis_angle((0, 1, 0), a)


def rot_x(a):
    return basis_axis_angle((1, 0, 0), a)


def vis(begin=0.0, end=0.0, fade=True):
    p = {}
    if begin > 0:
        p["visibility_range_begin"] = f(begin)
        p["visibility_range_begin_margin"] = f(begin * FADE)
    if end > 0:
        p["visibility_range_end"] = f(end)
        p["visibility_range_end_margin"] = f(end * FADE)
    if fade and p:
        p["visibility_range_fade_mode"] = "1"
    return p


def lod_ranges(r, is_moon):
    far = MOON_FAR if is_moon else 0.0
    return [(0.0, r * LOD0_K), (r * LOD0_K, r * LOD1_K), (r * LOD1_K, far)]


def title(bid):
    return bid.capitalize()


def build():
    data = json.loads(DATA.read_text(encoding="utf-8"))
    bodies = data["bodies"]
    by_id = {b["id"]: b for b in bodies}
    sc = Scene()

    # ---------------- external resources
    sc.ext_res("Script", "res://src/solar_system/solar_system.gd", "s_system")
    sc.ext_res("Script", "res://src/solar_system/orbit_body.gd", "s_body")
    sc.ext_res("Script", "res://src/solar_system/space_camera.gd", "s_camera")
    sc.ext_res("Theme", "res://ui/margin_theme.tres", "theme")
    for sh in ("planet", "sun", "corona", "atmosphere", "orbit", "rings", "sky"):
        sc.ext_res("Shader", f"res://shaders/solar_{sh}.gdshader", f"sh_{sh}")
    for b in bodies:
        bid = b["id"]
        sc.ext_res("Texture2D", f"res://assets/voxel/planets/icons/{bid}.png", f"icon_{bid}")
        for k in range(3):
            sc.ext_res("PackedScene", f"res://assets/voxel/planets/{bid}_lod{k}.glb", f"g_{bid}{k}")
            if bid == "earth":
                sc.ext_res("PackedScene", f"res://assets/voxel/planets/earth_clouds_lod{k}.glb", f"g_clouds{k}")
            if "rings" in b:
                sc.ext_res("PackedScene", f"res://assets/voxel/planets/{bid}_rings_lod{k}.glb", f"g_{bid}_rings{k}")

    # ---------------- environment
    sc.sub_res("ShaderMaterial", "sky_mat", shader='ExtResource("sh_sky")')
    sc.sub_res("Sky", "sky", sky_material='SubResource("sky_mat")', radiance_size="1")
    sc.sub_res("Environment", "env", background_mode="2", sky='SubResource("sky")',
               ambient_light_source="2", ambient_light_color=col(0.42, 0.5, 0.72), ambient_light_energy="0.14",
               reflected_light_source="1", tonemap_mode="3", tonemap_exposure="1.05",
               glow_enabled="true", **{"glow_levels/1": "0.0", "glow_levels/2": "0.3", "glow_levels/3": "1.0",
                                       "glow_levels/4": "0.8", "glow_levels/5": "1.0", "glow_levels/6": "0.6",
                                       "glow_levels/7": "0.35"},
               glow_intensity="0.85", glow_strength="1.0", glow_bloom="0.0", glow_blend_mode="1",
               glow_hdr_threshold="1.1", glow_hdr_scale="2.0",
               adjustment_enabled="true", adjustment_contrast="1.05", adjustment_saturation="1.12")

    # ---------------- materials + meshes
    sc.sub_res("ShaderMaterial", "mat_planet", shader='ExtResource("sh_planet")')
    sc.sub_res("ShaderMaterial", "mat_gas", shader='ExtResource("sh_planet")',
               **{"shader_parameter/normal_blend": "0.75", "shader_parameter/roughness": "0.85"})
    sc.sub_res("ShaderMaterial", "mat_clouds", shader='ExtResource("sh_planet")',
               **{"shader_parameter/normal_blend": "0.7", "shader_parameter/night_floor": "0.012",
                  "shader_parameter/specular_amount": "0.05"})
    sc.sub_res("ShaderMaterial", "mat_sun", shader='ExtResource("sh_sun")')
    sc.sub_res("ShaderMaterial", "mat_rings", shader='ExtResource("sh_rings")',
               **{"shader_parameter/brightness": "1.5", "shader_parameter/two_sided_wrap": "0.8"})
    sc.sub_res("ShaderMaterial", "mat_earth", shader='ExtResource("sh_planet")',
               **{"shader_parameter/ocean_glint": "0.7"})
    sc.sub_res("ShaderMaterial", "mat_orbit", shader='ExtResource("sh_orbit")')
    sun_ratio = 0.26
    sc.sub_res("ShaderMaterial", "mat_corona", shader='ExtResource("sh_corona")',
               **{"shader_parameter/sun_ratio": f(sun_ratio)})
    for bid, (_sc, inten, power) in ATMOSPHERE.items():
        sc.sub_res("ShaderMaterial", f"mat_atmo_{bid}", shader='ExtResource("sh_atmosphere")',
                   **{"shader_parameter/atmo_color": hexcol(by_id[bid]["visual"]["atmosphere"]),
                      "shader_parameter/intensity": f(inten), "shader_parameter/power": f(power)})
    sc.sub_res("PlaneMesh", "orbit_plane", size="Vector2(2, 2)")
    sc.sub_res("SphereMesh", "atmo_sphere", radius="1.0", height="2.0", radial_segments="64", rings="32")
    corona_size = 2 * pg.SUN_RADIUS / sun_ratio
    sc.sub_res("QuadMesh", "corona_quad", size=f"Vector2({f(corona_size)}, {f(corona_size)})")
    sc.sub_res("SystemFont", "font_label", font_names='PackedStringArray("Bahnschrift", "Segoe UI", "Arial")',
               font_weight="600")

    # ---------------- root, environment, light
    sc.node("SolarSystem", "Node3D", None, script='ExtResource("s_system")')
    sc.node("WorldEnvironment", "WorldEnvironment", environment='SubResource("env")')
    sc.node("SunLight", "OmniLight3D", light_color=col(1.0, 0.96, 0.9), light_energy="3.2",
            light_specular="0.35", omni_range="4096.0", omni_attenuation="0.25", shadow_enabled="false")
    sc.node("Bodies", "Node3D")

    def glb_instance(parent, name, ext, mesh_node, scale, rng, mat):
        path = sc.node(name, None, parent, instance=ext, transform=xform(scale=scale))
        props = {"material_override": f'SubResource("{mat}")', "cast_shadow": "0"}
        props.update(vis(rng[0], rng[1]))
        sc.node(mesh_node, None, path, index="0", **props)
        sc.editable.append(path)

    def add_body(b, parent):
        bid = b["id"]
        r = pg.visual_radius(b)
        d = pg.visual_distance(b, by_id)
        is_moon = "semi_major_axis_km" in b
        locked = bool(b.get("tidally_locked", False))
        incl = math.radians(b.get("orbital_inclination_deg", 0.0))
        node_lon = math.radians(b.get("longitude_ascending_node_deg", 0.0))
        plane = basis_axis_angle((math.cos(node_lon), 0, -math.sin(node_lon)), incl) if incl else None
        period = b.get("orbital_period_days", 0.0)
        phase = b.get("mean_longitude_j2000_deg", 0.0)
        theta = math.radians(phase) + (2 * math.pi * ((EDITOR_DAYS / period) % 1.0) if period else 0.0)
        root = sc.node(title(bid), "Node3D", parent, transform=xform(plane), script='ExtResource("s_body")',
                       body_id=s(bid), name_key=s(f"SS_NAME_{bid.upper()}"), orbit_radius=f(d),
                       orbital_period_days=f(period), phase_deg=f(phase),
                       tidally_locked="true" if locked else "false", visual_radius=f(r),
                       rotation_period_hours=f(b["rotation_period_hours"]),
                       **{"metadata/focus_key": str(FOCUS_KEYS.index(bid)) if bid in FOCUS_KEYS else "-1"})
        if d > 0:
            oc = ORBIT_COLORS.get(bid, (0.6, 0.7, 0.9))
            sc.node("OrbitLine", "MeshInstance3D", root, transform=xform(None, scale=d), mesh='SubResource("orbit_plane")',
                    material_override='SubResource("mat_orbit")', cast_shadow="0",
                    **{"instance_shader_parameters/line_color": col(*oc, 0.9 if not is_moon else 0.7),
                       "instance_shader_parameters/head_angle": f(theta)},
                    **(vis(0, MOON_UI_FAR * 1.5) if is_moon else {}))
        pivot = sc.node("Pivot", "Node3D", root, transform=xform(rot_y(theta)))
        anchor = sc.node("Anchor", "Node3D", pivot, transform=xform(None if locked else rot_y(-theta), pos=(d, 0, 0)))
        tilt = sc.node("Tilt", "Node3D", anchor, transform=xform(rot_x(-math.radians(b["axial_tilt_deg"]))))
        spin = sc.node("Spin", "Node3D", tilt)
        mat = {"sun": "mat_sun", "earth": "mat_earth", "jupiter": "mat_gas", "saturn": "mat_gas", "uranus": "mat_gas",
               "neptune": "mat_gas", "venus": "mat_gas"}.get(bid, "mat_planet")
        rngs = lod_ranges(r, is_moon)
        for k in range(3):
            glb_instance(spin, f"LOD{k}", f"g_{bid}{k}", f"{bid}_lod{k}", r, rngs[k], mat)
        if bid == "earth":
            cs = sc.node("CloudSpin", "Node3D", tilt)
            for k in range(3):
                glb_instance(cs, f"Clouds{k}", f"g_clouds{k}", f"earth_clouds_lod{k}", r, rngs[k], "mat_clouds")
        if "rings" in b:
            rg = sc.node("Rings", "Node3D", tilt)
            for k in range(3):
                glb_instance(rg, f"Rings{k}", f"g_{bid}_rings{k}", f"{bid}_rings_lod{k}", r, rngs[k], "mat_rings")
        if bid in ATMOSPHERE:
            a_scale = ATMOSPHERE[bid][0]
            sc.node("Atmosphere", "MeshInstance3D", tilt, transform=xform(scale=r * a_scale),
                    mesh='SubResource("atmo_sphere")', material_override=f'SubResource("mat_atmo_{bid}")',
                    cast_shadow="0", **vis(0, r * LOD1_K * 2.5))
        if bid == "sun":
            sc.node("Corona", "MeshInstance3D", anchor, mesh='SubResource("corona_quad")',
                    material_override='SubResource("mat_corona")', cast_shadow="0",
                    custom_aabb=f"AABB({f(-corona_size / 2)}, {f(-corona_size / 2)}, {f(-corona_size / 2)}, "
                                f"{f(corona_size)}, {f(corona_size)}, {f(corona_size)})")
        # name tag
        tint = {"sun": col(1.0, 0.86, 0.56)}.get(bid, col(0.74, 0.8, 0.9) if is_moon else col(0.92, 0.95, 1.0))
        # declutter: planet labels fade out once the camera is ~LABEL_FAR_K orbit radii away
        label_end = MOON_UI_FAR if is_moon else (d * LABEL_FAR_K if d > 0 else 0.0)
        top = r * (1.12 if "rings" not in b else 1.05)
        if bid == "sun":
            top = -r * 1.1  # under the Sun, so it never sits on the Mercury/Venus tags
        sc.node("Label", "Label3D", anchor, transform=xform(pos=(0, top, 0)), auto_translate_mode="2",
                cast_shadow="0", pixel_size="0.00052", billboard="1", fixed_size="true",
                render_priority="10", outline_render_priority="9", modulate=tint,
                outline_modulate=col(0.01, 0.02, 0.05, 0.85), text=s(b["name"]["en"]),
                font='SubResource("font_label")', font_size="40" if not is_moon else "32", outline_size="12",
                vertical_alignment="0" if bid == "sun" else "2", no_depth_test="true" if bid == "sun" else "false", **vis(r * SKIP_LABEL_K, label_end))
        for child in bodies:
            if child.get("parent") == bid and "semi_major_axis_km" in child:
                add_body(child, anchor)

    for b in bodies:
        if not b.get("parent") or b["parent"] == "sun" and "semi_major_axis_au" in b:
            add_body(b, "Bodies")

    # ---------------- camera
    sc.node("CameraRig", "Node3D", script='ExtResource("s_camera")', distance="560.0")
    sc.node("Camera3D", "Camera3D", "CameraRig", fov=f(CAMERA_FOV), near="0.05", far="6000.0")

    # ---------------- HUD
    build_hud(sc, bodies, by_id)
    sc.write(OUT)
    print(f"{len(sc.nodes)} nodes -> {OUT}")


def build_hud(sc, bodies, by_id):
    sc.node("UI", "CanvasLayer")
    sc.node("Root", "Control", "UI", layout_mode="3", anchors_preset="15", anchor_right="1.0", anchor_bottom="1.0",
            grow_horizontal="2", grow_vertical="2", mouse_filter="2", theme='ExtResource("theme")')
    R = "UI/Root"
    # top bar
    sc.node("TopBar", "PanelContainer", R, layout_mode="1", anchors_preset="10", anchor_right="1.0",
            offset_left="16.0", offset_top="12.0", offset_right="-16.0", offset_bottom="66.0", grow_horizontal="2",
            theme_type_variation='&"TopBarPanel"')
    hb = sc.node("HBox", "HBoxContainer", f"{R}/TopBar", layout_mode="2", **{"theme_override_constants/separation": "10"})
    sc.node("Logo", "Label", hb, layout_mode="2", theme_type_variation='&"LogoLabel"', text='"MARGIN"')
    sc.node("Title", "Label", hb, layout_mode="2", size_flags_vertical="4", theme_type_variation='&"TitleLabel"',
            text='"SS_TITLE"')
    sc.node("Subtitle", "Label", hb, layout_mode="2", size_flags_vertical="4", theme_type_variation='&"DimLabel"',
            text='"SS_SUBTITLE"')
    sc.node("Spacer", "Control", hb, layout_mode="2", size_flags_horizontal="3", mouse_filter="2")
    sc.node("DateLabel", "Label", hb, unique_name_in_owner="true", custom_minimum_size="Vector2(110, 0)",
            layout_mode="2", size_flags_vertical="4", theme_type_variation='&"MonoLabel"', auto_translate_mode="2",
            horizontal_alignment="1", text='"2026-10-28"')
    sc.node("Sep1", "VSeparator", hb, layout_mode="2")
    sc.node("TimeLabel", "Label", hb, layout_mode="2", size_flags_vertical="4", theme_type_variation='&"DimLabel"',
            text='"SS_TIME"')
    sc.node("TimeSlider", "HSlider", hb, unique_name_in_owner="true", custom_minimum_size="Vector2(220, 0)",
            layout_mode="2", size_flags_vertical="4", focus_mode="0", max_value="100.0", step="0.1",
            value=f(time_slider_value(8.0)), tooltip_text='"SS_TIME"')
    sc.node("RateLabel", "Label", hb, unique_name_in_owner="true", custom_minimum_size="Vector2(128, 0)",
            layout_mode="2", size_flags_vertical="4", theme_type_variation='&"MonoLabel"', auto_translate_mode="2",
            text='"1 s = 8 days"')
    sc.node("BtnPause", "Button", hb, unique_name_in_owner="true", custom_minimum_size="Vector2(96, 0)",
            layout_mode="2", focus_mode="0", toggle_mode="true", text='"SS_PAUSE"')
    sc.node("Sep2", "VSeparator", hb, layout_mode="2")
    sc.node("BtnOverview", "Button", hb, unique_name_in_owner="true", layout_mode="2", focus_mode="0",
            text='"SS_OVERVIEW"')
    sc.node("BtnLang", "Button", hb, unique_name_in_owner="true", custom_minimum_size="Vector2(52, 0)",
            layout_mode="2", focus_mode="0", text='"SS_LANG"')
    sc.connect("value_changed", f"{hb}/TimeSlider", "_on_time_slider_changed")
    sc.connect("toggled", f"{hb}/BtnPause", "_on_pause_toggled")
    sc.connect("pressed", f"{hb}/BtnOverview", "overview")
    sc.connect("pressed", f"{hb}/BtnLang", "toggle_language")

    # body list
    sc.node("BodiesPanel", "PanelContainer", R, layout_mode="1", offset_left="16.0", offset_top="82.0",
            offset_right="226.0", offset_bottom="400.0")
    vb = sc.node("VBox", "VBoxContainer", f"{R}/BodiesPanel", layout_mode="2",
                 **{"theme_override_constants/separation": "4"})
    sc.node("Header", "Label", vb, layout_mode="2", theme_type_variation='&"SectionLabel"', text='"SS_BODIES"')
    sc.node("HSep", "HSeparator", vb, layout_mode="2")
    order = ["sun", "mercury", "venus", "earth", "moon", "mars", "jupiter", "europa", "saturn", "uranus",
             "neptune", "pluto"]
    for bid in order:
        is_moon = "semi_major_axis_km" in by_id[bid]
        row = sc.node(f"Row{title(bid)}", "HBoxContainer", vb, layout_mode="2",
                      **{"theme_override_constants/separation": "0"})
        if is_moon:
            sc.node("Indent", "Control", row, custom_minimum_size="Vector2(22, 0)", layout_mode="2", mouse_filter="2")
        key = str(FOCUS_KEYS.index(bid)) if bid in FOCUS_KEYS else ""
        sc.node("Btn", "Button", row, layout_mode="2", size_flags_horizontal="3", focus_mode="0",
                tooltip_text=s(f"SS_KIND_{bid.upper()}"), text=s(f"SS_NAME_{bid.upper()}"),
                icon=f'ExtResource("icon_{bid}")', alignment="0", expand_icon="false",
                **{"metadata/body_id": s(bid), "theme_override_constants/icon_max_width": "22" if is_moon else "26"})
        sc.node("Key", "Label", row, custom_minimum_size="Vector2(18, 0)", layout_mode="2", size_flags_vertical="4",
                theme_type_variation='&"DimLabel"', auto_translate_mode="2", horizontal_alignment="2", text=s(key))

    # info card
    sc.node("InfoPanel", "PanelContainer", R, unique_name_in_owner="true", layout_mode="1", anchors_preset="1",
            anchor_left="1.0", anchor_right="1.0", offset_left="-392.0", offset_top="82.0", offset_right="-16.0",
            offset_bottom="300.0", grow_horizontal="0")
    iv = sc.node("VBox", "VBoxContainer", f"{R}/InfoPanel", layout_mode="2",
                 **{"theme_override_constants/separation": "8"})
    head = sc.node("Head", "HBoxContainer", iv, layout_mode="2", **{"theme_override_constants/separation": "12"})
    sc.node("Icon", "TextureRect", head, unique_name_in_owner="true", custom_minimum_size="Vector2(64, 64)",
            layout_mode="2", texture='ExtResource("icon_earth")', expand_mode="1", stretch_mode="5")
    names = sc.node("Names", "VBoxContainer", head, layout_mode="2", size_flags_horizontal="3",
                    alignment="1", **{"theme_override_constants/separation": "0"})
    sc.node("BodyName", "Label", names, unique_name_in_owner="true", layout_mode="2", auto_translate_mode="2",
            theme_type_variation='&"TitleLabel"', text='"Earth"')
    sc.node("BodyKind", "Label", names, unique_name_in_owner="true", layout_mode="2", auto_translate_mode="2",
            theme_type_variation='&"DimLabel"', text='"Planet · 3rd from the Sun"')
    sc.node("HSep", "HSeparator", iv, layout_mode="2")
    grid = sc.node("Stats", "GridContainer", iv, layout_mode="2", columns="2",
                   **{"theme_override_constants/h_separation": "14", "theme_override_constants/v_separation": "6"})
    for key in ("RADIUS", "DISTANCE", "PERIOD", "DAY", "TILT", "GRAVITY"):
        sc.node(f"K{key.title()}", "Label", grid, layout_mode="2", theme_type_variation='&"DimLabel"',
                text=s(f"SS_{key}"))
        sc.node(f"V{key.title()}", "Label", grid, unique_name_in_owner="true", layout_mode="2",
                size_flags_horizontal="3", theme_type_variation='&"MonoLabel"', auto_translate_mode="2",
                text='"-"')
    sc.node("HSep2", "HSeparator", iv, layout_mode="2")
    sc.node("Desc", "Label", iv, unique_name_in_owner="true", custom_minimum_size="Vector2(340, 0)", layout_mode="2",
            auto_translate_mode="2", autowrap_mode="3", text='"-"')
    sc.node("Source", "Label", iv, layout_mode="2", theme_type_variation='&"DimLabel"',
            **{"theme_override_font_sizes/font_size": "11"}, autowrap_mode="3", text='"SS_SOURCE"')

    # footer help
    sc.node("Footer", "VBoxContainer", R, layout_mode="1", anchors_preset="7", anchor_left="0.5", anchor_top="1.0",
            anchor_right="0.5", anchor_bottom="1.0", offset_left="-520.0", offset_top="-62.0", offset_right="520.0",
            offset_bottom="-14.0", grow_horizontal="2", grow_vertical="0", mouse_filter="2",
            **{"theme_override_constants/separation": "2"})
    sc.node("Help", "Label", f"{R}/Footer", layout_mode="2", theme_type_variation='&"DimLabel"',
            horizontal_alignment="1", text='"SS_HELP"')
    sc.node("ScaleNote", "Label", f"{R}/Footer", layout_mode="2", theme_type_variation='&"DimLabel"',
            **{"theme_override_font_sizes/font_size": "11", "theme_override_colors/font_color": col(0.94, 0.66, 0.23, 0.8)},
            horizontal_alignment="1", text='"SS_SCALE_NOTE"')


def time_slider_value(days_per_s):
    """Slider 0..100 maps to 10^(-2 + 5 v / 100) days per second (0.01 .. 1000)."""
    return (math.log10(days_per_s) + 2) / 5 * 100


if __name__ == "__main__":
    build()
