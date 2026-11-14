"""Converts the plain StandardMaterial3D sub-resources of .tscn scenes to the Cometworks toon
material (shaders/cw_toon_solid.gdshader, which uses shaders/include/cw_toon.gdshaderinc).

Only opaque, lit, flat-colour materials are converted (albedo colour, roughness, metallic,
emission, vertex colour); transparent, unshaded, billboard, textured or particle materials are
left alone. Re-running is harmless: converted materials are no longer StandardMaterial3D.

Usage: python tools/convert_toon_materials.py scenes/menu/shots/shot_launch.tscn [...]
"""
import re
import sys

SHADER_PATH = "res://shaders/cw_toon_solid.gdshader"
SHADER_ID = "cw_toon_solid"
ALLOWED = {"albedo_color", "roughness", "metallic", "metallic_specular", "emission_enabled",
           "emission", "emission_energy_multiplier", "vertex_color_use_as_albedo",
           "resource_name", "rim_enabled", "rim", "rim_tint"}
BLOCK = re.compile(r'\[sub_resource type="StandardMaterial3D" id="([^"]+)"\]\n(.*?)(?=\n\n|\n\[|\Z)', re.S)


def convert_block(mid, body):
    props = {}
    for line in body.strip().split("\n"):
        if " = " not in line:
            return None
        k, v = line.split(" = ", 1)
        props[k] = v
    if not set(props) <= ALLOWED:
        return None
    out = ['[sub_resource type="ShaderMaterial" id="%s"]' % mid]
    if "resource_name" in props:
        out.append("resource_name = " + props["resource_name"])
    out.append('shader = ExtResource("%s")' % SHADER_ID)
    out.append("shader_parameter/albedo = " + props.get("albedo_color", "Color(1, 1, 1, 1)"))
    if props.get("vertex_color_use_as_albedo") == "true":
        out.append("shader_parameter/use_vertex_color = true")
    out.append("shader_parameter/roughness = " + props.get("roughness", "1.0"))
    if "metallic" in props:
        out.append("shader_parameter/metallic = " + props["metallic"])
        if float(props["metallic"]) >= 0.3:
            # metal gets the crisp toon highlight
            out.append("shader_parameter/toon_specular = 1.0")
    if "metallic_specular" in props:
        out.append("shader_parameter/specular = " + props["metallic_specular"])
    if props.get("emission_enabled") == "true":
        out.append("shader_parameter/emission = " + props.get("emission", "Color(0, 0, 0, 1)"))
        out.append("shader_parameter/emission_energy = " + props.get("emission_energy_multiplier", "1.0"))
    return "\n".join(out)


def convert(path):
    s = open(path, encoding="utf-8").read()
    count = 0

    def repl(m):
        nonlocal count
        new = convert_block(m.group(1), m.group(2))
        if new is None:
            return m.group(0)
        count += 1
        return new

    s2 = BLOCK.sub(repl, s)
    if count == 0:
        return 0
    if 'id="%s"' % SHADER_ID not in s2:
        # after the last ext_resource (or the header)
        lines = s2.split("\n")
        idx = max([i for i, l in enumerate(lines) if l.startswith("[ext_resource")] or [0])
        lines.insert(idx + 1, '[ext_resource type="Shader" path="%s" id="%s"]' % (SHADER_PATH, SHADER_ID))
        if idx == 0:
            lines.insert(1, "")
        s2 = "\n".join(lines)
    open(path, "w", encoding="utf-8", newline="\n").write(s2)
    return count


if __name__ == "__main__":
    for p in sys.argv[1:]:
        n = convert(p)
        if n:
            print("%s: %d materials" % (p, n))
