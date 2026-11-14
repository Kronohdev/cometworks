"""Writes scenes/flight/flight_map.tscn (the flight's solar-system map view) from
data/solar_system.json. The scene is ordinary editor data: hand edits are fine, re-running
overwrites them.

Map space: 1 unit = 1 km, the focus (vessel or body) at the origin, real sizes and
distances. Every body reuses the voxel planets of the solar-system scene
(assets/voxel/planets/<id>_lod0/1/2.glb, unit spheres scaled to the real radius) with the
same visibility-range LOD rule (docs/solar_system.md): lod0 up to 14 r, lod1 to 46 r, lod2
to 400 r (~2.5 px tall at 1600x900, fov 50); beyond that only the 2D icon is drawn.
Run: python src/flight/gen/make_flight_map.py
"""
import json
import math
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "scenes", "flight", "flight_map.tscn")
GAS = {"jupiter", "saturn", "uranus", "neptune"}
ATMO = {  # colour, intensity, power (as the solar-system scene)
    "earth": ((0.435294, 0.705882, 1.0), 1.9, 2.2),
    "venus": ((1.0, 0.886275, 0.658824), 1.4, 2.0),
    "mars": ((1.0, 0.690196, 0.541176), 0.8, 2.6),
    "uranus": ((0.65098, 0.941176, 1.0), 0.9, 2.6),
    "neptune": ((0.435294, 0.611765, 1.0), 1.1, 2.6),
}
# orbit line colours (map): soft versions of the body palettes
LOD = [(0.0, 14.0), (14.0, 46.0), (46.0, 400.0)]
# outermost voxel (relief / cloud tops) of each lod0 model, in units of its radius: the map
# scales the models so that this outer shell sits at the real radius, keeping low orbits
# (200 km = 1.03 R) above the exaggerated voxel relief
MAX_R = {"sun": 1.0185, "mercury": 1.0845, "venus": 1.0223, "earth": 1.1063, "moon": 1.0819, "mars": 1.0805,
         "jupiter": 1.0174, "europa": 1.0285, "saturn": 1.0185, "uranus": 1.0223, "neptune": 1.0223, "pluto": 1.0752}


def f(x):
    return ("%.6g" % x) if abs(x) < 1e6 else ("%.1f" % x)


def xf(basis, origin=(0.0, 0.0, 0.0)):
    (a, b, c), (d, e, g), (h, i, j) = basis
    return "Transform3D(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % tuple(
        f(v) for v in (a, d, h, b, e, i, c, g, j, *origin))


def scale(s):
    return xf(((s, 0, 0), (0, s, 0), (0, 0, s)))


def tilt(deg, s=1.0):
    t = math.radians(deg)
    return xf(((s, 0, 0), (0, s * math.cos(t), -s * math.sin(t)), (0, s * math.sin(t), s * math.cos(t))))


def main():
    data = json.load(open(os.path.join(ROOT, "data", "solar_system.json"), encoding="utf-8"))
    bodies = data["bodies"]
    ext = []
    sub = []
    nodes = []

    def add_ext(kind, path, rid):
        ext.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))

    add_ext("Script", "res://src/flight/flight_map.gd", "s_map")
    add_ext("Theme", "res://ui/margin_theme.tres", "theme")
    for sh in ("solar_planet", "solar_sun", "solar_atmosphere", "solar_rings", "flight_map_sky", "flight_map_line",
               "flight_map_glow"):
        add_ext("Shader", "res://shaders/%s.gdshader" % sh, "sh_" + sh)
    add_ext("PackedScene", "res://scenes/flight/map_node_gizmo.tscn", "p_gizmo")
    add_ext("Texture2D", "res://scenes/flight/ui/marker_vessel.svg", "t_vessel")
    add_ext("Texture2D", "res://scenes/flight/ui/map_add.svg", "t_add")
    for b in bodies:
        bid = b["id"]
        for k in range(3):
            add_ext("PackedScene", "res://assets/voxel/planets/%s_lod%d.glb" % (bid, k), "g_%s%d" % (bid, k))
        if bid == "earth":
            for k in range(3):
                add_ext("PackedScene", "res://assets/voxel/planets/earth_clouds_lod%d.glb" % k, "g_clouds%d" % k)
        if bid == "saturn":
            for k in range(3):
                add_ext("PackedScene", "res://assets/voxel/planets/saturn_rings_lod%d.glb" % k, "g_rings%d" % k)

    sub.append('''[sub_resource type="ShaderMaterial" id="sky_mat"]
shader = ExtResource("sh_flight_map_sky")

[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_mat")
radiance_size = 0

[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 2
ambient_light_color = Color(0.42, 0.5, 0.72, 1)
ambient_light_energy = 0.16
reflected_light_source = 1
tonemap_mode = 3
tonemap_exposure = 1.05
adjustment_enabled = true
adjustment_contrast = 1.04
adjustment_saturation = 1.1

[sub_resource type="ShaderMaterial" id="mat_planet"]
shader = ExtResource("sh_solar_planet")

[sub_resource type="ShaderMaterial" id="mat_gas"]
shader = ExtResource("sh_solar_planet")
shader_parameter/normal_blend = 0.75
shader_parameter/roughness = 0.85

[sub_resource type="ShaderMaterial" id="mat_earth"]
shader = ExtResource("sh_solar_planet")
shader_parameter/ocean_glint = 0.7

[sub_resource type="ShaderMaterial" id="mat_clouds"]
shader = ExtResource("sh_solar_planet")
shader_parameter/normal_blend = 0.7
shader_parameter/night_floor = 0.012
shader_parameter/specular_amount = 0.05

[sub_resource type="ShaderMaterial" id="mat_sun"]
shader = ExtResource("sh_solar_sun")
shader_parameter/energy_near = 1.1
shader_parameter/energy_far = 3.0
shader_parameter/energy_distance = Vector2(2.7e+06, 1.6e+07)

[sub_resource type="ShaderMaterial" id="mat_rings"]
shader = ExtResource("sh_solar_rings")
shader_parameter/brightness = 1.5
shader_parameter/two_sided_wrap = 0.8

[sub_resource type="ShaderMaterial" id="mat_line"]
render_priority = 1
shader = ExtResource("sh_flight_map_line")

[sub_resource type="ShaderMaterial" id="mat_glow"]
render_priority = 2
shader = ExtResource("sh_flight_map_glow")

[sub_resource type="QuadMesh" id="quad2"]
size = Vector2(2, 2)

[sub_resource type="SphereMesh" id="atmo_sphere"]
radius = 1.0
height = 2.0
radial_segments = 64
rings = 32''')
    for bid, (col, inten, pw) in ATMO.items():
        sub.append('''[sub_resource type="ShaderMaterial" id="mat_atmo_%s"]
shader = ExtResource("sh_solar_atmosphere")
shader_parameter/atmo_color = Color(%s, %s, %s, 1)
shader_parameter/intensity = %s
shader_parameter/power = %s''' % (bid, col[0], col[1], col[2], inten, pw))

    nodes.append('''[node name="MapView" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme = ExtResource("theme")
script = ExtResource("s_map")

[node name="Container" type="SubViewportContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
stretch = true

[node name="MapViewport" type="SubViewport" parent="Container"]
unique_name_in_owner = true
own_world_3d = true
handle_input_locally = false
size = Vector2i(1600, 900)
render_target_update_mode = 0

[node name="World" type="Node3D" parent="Container/MapViewport"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="Container/MapViewport/World"]
unique_name_in_owner = true
environment = SubResource("env")

[node name="SunLight" type="OmniLight3D" parent="Container/MapViewport/World"]
unique_name_in_owner = true
light_color = Color(1, 0.96, 0.9, 1)
light_energy = 2.4
light_specular = 0.35
omni_range = 1e+11
omni_attenuation = 0.0

[node name="MapCamera" type="Camera3D" parent="Container/MapViewport/World"]
unique_name_in_owner = true
transform = Transform3D(1, 0, 0, 0, 0.877583, 0.479426, 0, -0.479426, 0.877583, 0, 12000, 22000)
fov = 50.0
near = 1.0
far = 1e+08

[node name="Bodies" type="Node3D" parent="Container/MapViewport/World"]
unique_name_in_owner = true''')
    W = "Container/MapViewport/World"
    for b in bodies:
        bid = b["id"]
        name = bid.capitalize()
        r_true = float(b["radius_km"])
        r = r_true / MAX_R.get(bid, 1.0)
        base = "%s/Bodies/%s" % (W, name)
        nodes.append('[node name="%s" type="Node3D" parent="%s/Bodies"]\nmetadata/body_id = "%s"' % (name, W, bid))
        nodes.append('[node name="Tilt" type="Node3D" parent="%s"]\ntransform = %s' % (base, tilt(float(b.get("axial_tilt_deg", 0.0)))))
        mat = "mat_sun" if bid == "sun" else ("mat_earth" if bid == "earth" else ("mat_gas" if bid in GAS else "mat_planet"))
        layers = [("LOD", "g_%s" % bid, "%s_lod" % bid, mat)]
        if bid == "earth":
            layers.append(("Clouds", "g_clouds", "earth_clouds_lod", "mat_clouds"))
        if bid == "saturn":
            layers.append(("Rings", "g_rings", "saturn_rings_lod", "mat_rings"))
        for prefix, gid, inner, m in layers:
            for k in range(3):
                lo, hi = LOD[k]
                nodes.append('[node name="%s%d" parent="%s/Tilt" instance=ExtResource("%s%d")]\ntransform = %s' % (
                    prefix, k, base, gid, k, scale(r)))
                lines = ['[node name="%s%d" parent="%s/Tilt/%s%d" index="0"]' % (inner, k, base, prefix, k),
                         'material_override = SubResource("%s")' % m, "cast_shadow = 0"]
                if lo > 0:
                    lines += ["visibility_range_begin = %s" % f(lo * r), "visibility_range_begin_margin = %s" % f(lo * r * 0.12)]
                lines += ["visibility_range_end = %s" % f(hi * r), "visibility_range_end_margin = %s" % f(hi * r * 0.12),
                          "visibility_range_fade_mode = 1"]
                nodes.append("\n".join(lines))
        if bid in ATMO:
            nodes.append('''[node name="Atmosphere" type="MeshInstance3D" parent="%s/Tilt"]
transform = %s
cast_shadow = 0
mesh = SubResource("atmo_sphere")
surface_material_override/0 = SubResource("mat_atmo_%s")
visibility_range_end = %s
visibility_range_end_margin = %s
visibility_range_fade_mode = 1''' % (base, scale(r_true * 1.04), bid, f(115 * r), f(115 * r * 0.12)))
        if bid == "sun":
            nodes.append('''[node name="Halo" type="MeshInstance3D" parent="%s"]
transform = %s
cast_shadow = 0
extra_cull_margin = 16384.0
mesh = SubResource("quad2")
surface_material_override/0 = SubResource("mat_glow")
instance_shader_parameters/glow_color = Color(1, 0.72, 0.38, 1)
instance_shader_parameters/min_px = 70.0
instance_shader_parameters/intensity = 1.6
instance_shader_parameters/core = 0.26''' % (base, scale(r_true * 3.85)))
    # orbit lines (one per orbiting body), trajectory pool, SOI rings
    nodes.append('[node name="Orbits" type="Node3D" parent="%s"]\nunique_name_in_owner = true' % W)
    for b in bodies:
        if not b["parent"]:
            continue
        pal = b["visual"]["palette"]
        h = pal[min(1, len(pal) - 1)].lstrip("#")
        c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
        c = [x * 0.55 + 0.45 * 0.75 for x in c]
        nodes.append('''[node name="%s" type="MeshInstance3D" parent="%s/Orbits"]
cast_shadow = 0
extra_cull_margin = 16384.0
material_override = SubResource("mat_line")
instance_shader_parameters/line_color = Color(%.3f, %.3f, %.3f, 0.5)
instance_shader_parameters/line_width = 1.4
metadata/body_id = "%s"''' % (b["id"].capitalize(), W, c[0], c[1], c[2], b["id"]))
    nodes.append('[node name="Trajectory" type="Node3D" parent="%s"]\nunique_name_in_owner = true' % W)
    for i in range(14):
        nodes.append('''[node name="Seg%d" type="MeshInstance3D" parent="%s/Trajectory"]
visible = false
cast_shadow = 0
extra_cull_margin = 16384.0
material_override = SubResource("mat_line")
instance_shader_parameters/line_width = 2.6''' % (i, W))
    nodes.append('''[node name="Detail" type="MeshInstance3D" parent="%s/Trajectory"]
visible = false
cast_shadow = 0
extra_cull_margin = 16384.0
material_override = SubResource("mat_line")
instance_shader_parameters/line_width = 2.6''' % W)
    nodes.append('[node name="SoiRings" type="Node3D" parent="%s"]\nunique_name_in_owner = true' % W)
    for i in range(3):
        nodes.append('''[node name="Ring%d" type="MeshInstance3D" parent="%s/SoiRings"]
visible = false
cast_shadow = 0
extra_cull_margin = 16384.0
material_override = SubResource("mat_line")
instance_shader_parameters/line_color = Color(0.576, 0.639, 0.722, 0.22)
instance_shader_parameters/line_width = 1.0''' % (i, W))
    # 2D overlay
    nodes.append('''[node name="Overlay" type="Control" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="Labels" type="Control" parent="Overlay"]
unique_name_in_owner = true
anchors_preset = 0
mouse_filter = 2

[node name="Markers" type="Control" parent="Overlay"]
unique_name_in_owner = true
anchors_preset = 0
mouse_filter = 2

[node name="VesselMarker" type="TextureRect" parent="Overlay"]
unique_name_in_owner = true
layout_mode = 0
offset_right = 36.0
offset_bottom = 18.0
mouse_filter = 2
texture = ExtResource("t_vessel")
expand_mode = 1
stretch_mode = 5

[node name="Hover" type="Control" parent="Overlay"]
unique_name_in_owner = true
visible = false
anchors_preset = 0
mouse_filter = 2

[node name="Icon" type="TextureRect" parent="Overlay/Hover"]
self_modulate = Color(1, 0.6039, 0.2392, 1)
layout_mode = 0
offset_left = -11.0
offset_top = -11.0
offset_right = 11.0
offset_bottom = 11.0
mouse_filter = 2
texture = ExtResource("t_add")
expand_mode = 1
stretch_mode = 5

[node name="Label" type="Label" parent="Overlay/Hover"]
unique_name_in_owner = true
layout_mode = 0
offset_left = 14.0
offset_top = -26.0
offset_right = 260.0
offset_bottom = -8.0
theme_type_variation = &"MonoLabel"
theme_override_colors/font_color = Color(1, 0.7412, 0.4784, 1)
theme_override_colors/font_outline_color = Color(0.0392, 0.0549, 0.0745, 0.9)
theme_override_constants/outline_size = 5
theme_override_font_sizes/font_size = 12
text = "+ node  T- 12:00"

[node name="Gizmo" parent="Overlay" instance=ExtResource("p_gizmo")]
unique_name_in_owner = true
visible = false

[node name="MapBar" type="PanelContainer" parent="Overlay"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 16.0
offset_top = -116.0
offset_right = 548.0
offset_bottom = -48.0
grow_vertical = 0
mouse_filter = 2

[node name="VBox" type="VBoxContainer" parent="Overlay/MapBar"]
layout_mode = 2
theme_override_constants/separation = 6

[node name="Head" type="HBoxContainer" parent="Overlay/MapBar/VBox"]
layout_mode = 2
theme_override_constants/separation = 8

[node name="Title" type="Label" parent="Overlay/MapBar/VBox/Head"]
layout_mode = 2
theme_type_variation = &"SectionLabel"
text = "FL_MAP_TITLE"

[node name="BtnPrev" type="Button" parent="Overlay/MapBar/VBox/Head"]
unique_name_in_owner = true
custom_minimum_size = Vector2(26, 26)
layout_mode = 2
tooltip_text = "FL_MAP_FOCUS_TIP"
focus_mode = 0
text = "‹"

[node name="Focus" type="Label" parent="Overlay/MapBar/VBox/Head"]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 0)
layout_mode = 2
theme_type_variation = &"ValueLabel"
theme_override_font_sizes/font_size = 16
text = "Earth"
horizontal_alignment = 1

[node name="BtnNext" type="Button" parent="Overlay/MapBar/VBox/Head"]
unique_name_in_owner = true
custom_minimum_size = Vector2(26, 26)
layout_mode = 2
tooltip_text = "FL_MAP_FOCUS_TIP"
focus_mode = 0
text = "›"

[node name="Sep" type="VSeparator" parent="Overlay/MapBar/VBox/Head"]
layout_mode = 2

[node name="BtnVessel" type="Button" parent="Overlay/MapBar/VBox/Head"]
unique_name_in_owner = true
layout_mode = 2
tooltip_text = "FL_MAP_SCALE_VESSEL_TIP"
focus_mode = 0
theme_type_variation = &"SegmentButton"
toggle_mode = true
text = "FL_MAP_SCALE_VESSEL"

[node name="BtnSystem" type="Button" parent="Overlay/MapBar/VBox/Head"]
unique_name_in_owner = true
layout_mode = 2
tooltip_text = "FL_MAP_SCALE_SYSTEM_TIP"
focus_mode = 0
theme_type_variation = &"SegmentButton"
toggle_mode = true
text = "FL_MAP_SCALE_SYSTEM"

[node name="BtnSolar" type="Button" parent="Overlay/MapBar/VBox/Head"]
unique_name_in_owner = true
layout_mode = 2
tooltip_text = "FL_MAP_SCALE_SOLAR_TIP"
focus_mode = 0
theme_type_variation = &"SegmentButton"
toggle_mode = true
text = "FL_MAP_SCALE_SOLAR"

[node name="Info" type="Label" parent="Overlay/MapBar/VBox"]
unique_name_in_owner = true
layout_mode = 2
theme_type_variation = &"DimLabel"
theme_override_font_sizes/font_size = 13
text = "Target: Moon"

[node name="Hint" type="Label" parent="Overlay"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 20.0
offset_top = -40.0
offset_right = 548.0
offset_bottom = -6.0
grow_vertical = 0
theme_type_variation = &"DimLabel"
theme_override_font_sizes/font_size = 12
text = "FL_MAP_HINT"
autowrap_mode = 3''')
    n_load = len(ext) + len(sub) + 1
    with open(OUT, "w", encoding="utf-8", newline="\n") as fo:
        fo.write("[gd_scene load_steps=%d format=3]\n\n" % n_load)
        fo.write("\n".join(ext) + "\n\n")
        fo.write("\n\n".join(sub) + "\n\n")
        fo.write("\n\n".join(nodes) + "\n")
    print("wrote", OUT, len(nodes), "node blocks")


if __name__ == "__main__":
    main()
