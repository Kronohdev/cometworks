"""Writes ui/cometworks_theme.tres, the Cometworks UI theme ("Aurora de observatorio",
docs/GDD_Cometworks.pdf section 22), once. After that the .tres is the source of truth: tune it
in the Godot theme editor. Re-running this script overwrites hand edits.

NOTE: the .tres has since been restyled by hand (cozy night-sky palette, CwButtonStyle
keys with a lip, calm rounded CwPanelStyle panels, CwSegment / CwStat / CwHintPill / CwDot
variations). This generator still writes the older flat-instrument look: do not re-run it
unless you port those changes first.

Fonts (OFL, bundled under ui/fonts/ with their licences):
  Bricolage Grotesque (variable: wght / opsz / wdth)  titles, logo, headlines
  Atkinson Hyperlegible                              body, buttons, labels (caps +8 %)
  IBM Plex Mono                                       numbers, telemetry, money, dates
Size scale at 1600x900: 12 / 14 / 16 / 20 / 28 / 40.

Variation names other screens rely on (keep them): CwPanel, CwPanelTop, CwStrip, CwRail,
CwRailButton, CwPrimary, CwKey, CwCaps, CwDim, CwMono, CwMonoSmall, CwTitle. Added here:
CwPanelInset, CwPanelRaised, CwCard, CwSecondary, CwDanger, CwLink, CwHeading, CwDisplay,
CwMonoLarge, CwBody, CwCapsAccent, CwBarEng / CwBarSci / CwBarOps / CwBarRel / CwBarWarn /
CwBarDanger (LED progress bars), CwThrottle (vertical phase lever), CwToggle (lever switch),
CwTabsUnderline (flat tabs), CwListPlain.

Usage: python tools/build_cw_theme.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "ui" / "cometworks_theme.tres"


def rgba(h, a=1.0):
    h = h.lstrip("#")
    return "Color(%.4f, %.4f, %.4f, %.4g)" % (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


SPACE, WELL, PANEL, RAISED, HOVER = "#070b14", "#0a1120", "#0e1524", "#152036", "#1d2a44"
LINE, HAIR, TEXT, DIM = "#24324d", "#3a4d72", "#e9eef7", "#8c9ab5"
TEAL, VIOLET, IGN, IGN_HI, ICE = "#3fe0c5", "#8e7cff", "#ff8a3d", "#ffa766", "#bfe8ff"
WARN, DANGER = "#ffc547", "#ff5c6c"

WGHT, OPSZ, WDTH = 2003265652, 1869640570, 2003072104   # OpenType axis tags as ints


class Theme:
    def __init__(self):
        self.ext = []
        self.subs = []
        self.items = []
        self._ext_ids = {}

    def ext_res(self, kind, path):
        if path in self._ext_ids:
            return self._ext_ids[path]
        rid = f"{len(self.ext) + 1}_{Path(path).stem[:10].lower().replace('-', '_')}"
        self.ext.append(f'[ext_resource type="{kind}" path="{path}" id="{rid}"]')
        self._ext_ids[path] = rid
        return rid

    def tex(self, name):
        return f'ExtResource("{self.ext_res("Texture2D", f"res://ui/cometworks/theme/{name}.svg")}")'

    def sub(self, kind, sid, **props):
        lines = [f'[sub_resource type="{kind}" id="{sid}"]']
        for k, v in props.items():
            lines.append(f"{k} = {v}")
        self.subs.append("\n".join(lines))
        return f'SubResource("{sid}")'

    def set(self, type_name, kind, name, value):
        key = f"{type_name}/{kind}/{name}" if kind else f"{type_name}/{name}"
        self.items.append(f"{key} = {value}")

    def write(self, extra_head):
        steps = len(self.ext) + len(self.subs) + 1
        text = f"[gd_resource type=\"Theme\" load_steps={steps} format=3]\n\n" + "\n".join(self.ext) + "\n\n" + \
            "\n\n".join(self.subs) + "\n\n[resource]\n" + extra_head + "\n".join(sorted(self.items, key=_order)) + "\n"
        OUT.write_text(text, encoding="utf-8", newline="\n")


def _order(line):
    # base_type first inside each type, then alphabetical (like Godot saves it)
    t, rest = line.split("/", 1)
    return (t, 0 if rest.startswith("base_type") else 1, rest)


def flat(th, sid, bg=None, border=None, bw=(0, 0, 0, 0), radius=3, margins=None, shadow=None, expand=None,
         draw_center=True, skew=None):
    p = {}
    if margins:
        p["content_margin_left"], p["content_margin_top"], p["content_margin_right"], p["content_margin_bottom"] = \
            [f"{float(m)}" for m in margins]
    if not draw_center:
        p["draw_center"] = "false"
    if bg:
        p["bg_color"] = rgba(*bg) if isinstance(bg, tuple) else rgba(bg)
    for side, w in zip(("left", "top", "right", "bottom"), bw):
        if w:
            p[f"border_width_{side}"] = str(w)
    if border:
        p["border_color"] = rgba(*border) if isinstance(border, tuple) else rgba(border)
    if radius:
        for c in ("top_left", "top_right", "bottom_right", "bottom_left"):
            p[f"corner_radius_{c}"] = str(radius)
    if expand:
        for side, e in zip(("left", "top", "right", "bottom"), expand):
            if e:
                p[f"expand_margin_{side}"] = f"{float(e)}"
    if shadow:
        p["shadow_color"] = rgba("#000000", 0.45)
        p["shadow_offset"] = f"Vector2({shadow}, {shadow})"
    return th.sub("StyleBoxFlat", sid, **p)


def build():
    th = Theme()
    panel_script = th.ext_res("Script", "res://src/tycoon/ui/cw_panel_style.gd")
    led_script = th.ext_res("Script", "res://src/tycoon/ui/cw_led_style.gd")
    focus_script = th.ext_res("Script", "res://src/tycoon/ui/cw_focus_style.gd")
    f_atk = th.ext_res("FontFile", "res://ui/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Regular.ttf")
    f_atk_b = th.ext_res("FontFile", "res://ui/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Bold.ttf")
    f_atk_i = th.ext_res("FontFile", "res://ui/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Italic.ttf")
    f_bri = th.ext_res("FontFile", "res://ui/fonts/bricolage_grotesque/BricolageGrotesque-Variable.ttf")
    f_plex = th.ext_res("FontFile", "res://ui/fonts/ibm_plex_mono/IBMPlexMono-Regular.ttf")
    f_plex_m = th.ext_res("FontFile", "res://ui/fonts/ibm_plex_mono/IBMPlexMono-Medium.ttf")
    f_plex_sb = th.ext_res("FontFile", "res://ui/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf")

    # ------------------------------------------------------------------ fonts
    sym = th.sub("SystemFont", "f_symbols",
                 font_names='PackedStringArray("Segoe UI Symbol", "Segoe UI Emoji", "Noto Sans Symbols 2", '
                            '"Noto Sans Symbols", "DejaVu Sans", "Arial Unicode MS")')
    fb = f"Array[Font]([{sym}])"

    def var(sid, base, spacing=0, axes=None, emb=None, fallback=True):
        p = {"base_font": f'ExtResource("{base}")'}
        if fallback:
            p["fallbacks"] = fb
        if axes:
            p["variation_opentype"] = "{\n" + ",\n".join(f"{k}: {v}" for k, v in axes.items()) + "\n}"
        if spacing:
            p["spacing_glyph"] = str(spacing)
        if emb:
            p["variation_embolden"] = str(emb)
        return th.sub("FontVariation", sid, **p)

    body = var("f_body", f_atk)
    body_b = var("f_body_b", f_atk_b)
    body_i = var("f_body_i", f_atk_i)
    caps = var("f_caps", f_atk_b, spacing=1)
    caps_wide = var("f_caps_wide", f_atk_b, spacing=2)
    title = var("f_title", f_bri, axes={WGHT: 600, OPSZ: 24, WDTH: 100})
    heading = var("f_heading", f_bri, axes={WGHT: 650, OPSZ: 36, WDTH: 96})
    display = var("f_display", f_bri, axes={WGHT: 700, OPSZ: 72, WDTH: 88}, spacing=0)
    mono = var("f_mono", f_plex)
    mono_m = var("f_mono_m", f_plex_m)
    mono_sb = var("f_mono_sb", f_plex_sb)

    # ------------------------------------------------------------------ panels
    def panel(sid, **kw):
        p = {"script": f'ExtResource("{panel_script}")'}
        p.update(kw)
        return th.sub("StyleBox", sid, **p)

    sb_panel = panel("sb_panel")
    sb_panel_top = panel("sb_panel_top", aurora_top="true", padding="Vector4(14, 8, 14, 6)")
    sb_strip = panel("sb_strip", chamfer="7.0", tick_length="0.0", padding="Vector4(12, 7, 10, 7)")
    sb_rail = panel("sb_rail", padding="Vector4(7, 10, 7, 10)")
    sb_inset = panel("sb_inset", bg_color=rgba(WELL), border_color=rgba(LINE), chamfer="0.0", tick_length="0.0",
                     shadow_offset="0.0", grain="0.0", bevel_color=rgba("#000000", 0.35),
                     padding="Vector4(10, 8, 10, 8)")
    sb_raised = panel("sb_raised", bg_color=rgba(RAISED), border_color=rgba(LINE), chamfer="6.0", tick_length="0.0",
                      shadow_offset="0.0", grain="0.04", padding="Vector4(10, 8, 10, 8)")
    sb_card = panel("sb_card", bg_color=rgba(PANEL), border_color=rgba(HAIR, 0.8), chamfer="8.0",
                    tick_length="4.0", shadow_offset="2.0", padding="Vector4(12, 10, 12, 10)")
    sb_window = panel("sb_window", bg_color=rgba(PANEL), border_color=rgba(HAIR), aurora_top="true",
                      padding="Vector4(14, 12, 14, 12)")
    sb_tooltip = panel("sb_tooltip", bg_color=rgba(SPACE), border_color=rgba(HAIR), chamfer="6.0",
                       tick_length="0.0", shadow_offset="0.0", grain="0.0", padding="Vector4(10, 6, 10, 7)")
    sb_popup = panel("sb_popup", bg_color=rgba(PANEL), border_color=rgba(HAIR), chamfer="6.0", tick_length="0.0",
                     shadow_offset="0.0", padding="Vector4(4, 5, 4, 5)")
    sb_tab_panel = panel("sb_tab_panel", chamfer="10.0", tick_length="6.0", shadow_offset="2.0",
                         padding="Vector4(12, 12, 12, 12)")

    # ------------------------------------------------------------------ focus
    focus_ring = th.sub("StyleBox", "sb_focus", script=f'ExtResource("{focus_script}")')
    focus_field = th.sub("StyleBox", "sb_focus_field", script=f'ExtResource("{focus_script}")',
                         ring_color=rgba(TEAL, 0.0), aurora="true")
    focus_inner = th.sub("StyleBox", "sb_focus_inner", script=f'ExtResource("{focus_script}")',
                         ring_offset="-1.0")
    empty = th.sub("StyleBoxEmpty", "sb_empty")

    # ------------------------------------------------------------------ buttons (secondary)
    m_btn = (12, 6, 12, 7)
    m_btn_p = (12, 7, 12, 6)
    btn = flat(th, "sb_btn", RAISED, LINE, (1, 1, 1, 1), 3, m_btn)
    btn_h = flat(th, "sb_btn_hover", HOVER, (ICE, 0.75), (1, 1, 1, 1), 3, m_btn)
    btn_p = flat(th, "sb_btn_pressed", SPACE, TEAL, (1, 1, 1, 1), 3, m_btn_p)
    btn_d = flat(th, "sb_btn_disabled", PANEL, (LINE, 0.7), (1, 1, 1, 1), 3, m_btn)
    T = "Button"
    for k, v in (("normal", btn), ("hover", btn_h), ("pressed", btn_p), ("hover_pressed", btn_p),
                 ("disabled", btn_d), ("focus", focus_ring)):
        th.set(T, "styles", k, v)
    for k, v in (("font_color", rgba(TEXT)), ("font_hover_color", rgba("#ffffff")), ("font_pressed_color", rgba(TEAL)),
                 ("font_hover_pressed_color", rgba(TEAL)), ("font_focus_color", rgba(TEXT)),
                 ("font_disabled_color", rgba(DIM, 0.5)), ("icon_normal_color", rgba(ICE)),
                 ("icon_hover_color", rgba("#ffffff")), ("icon_pressed_color", rgba(TEAL)),
                 ("icon_hover_pressed_color", rgba(TEAL)), ("icon_focus_color", rgba(ICE)),
                 ("icon_disabled_color", rgba(DIM, 0.4)), ("font_outline_color", rgba(SPACE))):
        th.set(T, "colors", k, v)
    th.set(T, "fonts", "font", body_b)
    th.set(T, "font_sizes", "font_size", "14")
    th.set(T, "constants", "h_separation", "8")

    # secondary: outline only (GDD 22.4 "Secundario: contorno hairline")
    sec = flat(th, "sb_sec", (PANEL, 0.0), HAIR, (1, 1, 1, 1), 3, m_btn)
    sec_h = flat(th, "sb_sec_hover", (RAISED, 0.85), ICE, (1, 1, 1, 1), 3, m_btn)
    sec_p = flat(th, "sb_sec_pressed", (SPACE, 0.9), TEAL, (1, 1, 1, 1), 3, m_btn_p)
    sec_d = flat(th, "sb_sec_disabled", (PANEL, 0.0), (LINE, 0.8), (1, 1, 1, 1), 3, m_btn)
    T = "CwSecondary"
    th.set(T, "", "base_type", '&"Button"')
    for k, v in (("normal", sec), ("hover", sec_h), ("pressed", sec_p), ("hover_pressed", sec_p), ("disabled", sec_d)):
        th.set(T, "styles", k, v)
    th.set(T, "colors", "font_color", rgba(ICE))
    th.set(T, "fonts", "font", caps)
    th.set(T, "font_sizes", "font_size", "13")

    dan = flat(th, "sb_danger", (DANGER, 0.06), (DANGER, 0.7), (1, 1, 1, 1), 3, m_btn)
    dan_h = flat(th, "sb_danger_hover", (DANGER, 0.16), DANGER, (1, 1, 1, 1), 3, m_btn)
    dan_p = flat(th, "sb_danger_pressed", (DANGER, 0.28), DANGER, (1, 1, 1, 1), 3, m_btn_p)
    T = "CwDanger"
    th.set(T, "", "base_type", '&"Button"')
    for k, v in (("normal", dan), ("hover", dan_h), ("pressed", dan_p), ("hover_pressed", dan_p)):
        th.set(T, "styles", k, v)
    for k in ("font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"):
        th.set(T, "colors", k, rgba("#ffb3ba") if k == "font_color" else rgba("#ffffff"))
    th.set(T, "fonts", "font", caps)
    th.set(T, "font_sizes", "font_size", "13")

    T = "CwLink"
    th.set(T, "", "base_type", '&"Button"')
    for k in ("normal", "hover", "pressed", "hover_pressed", "disabled"):
        th.set(T, "styles", k, empty)
    th.set(T, "colors", "font_color", rgba(TEAL))
    th.set(T, "colors", "font_hover_color", rgba("#9ff5e6"))
    th.set(T, "colors", "font_pressed_color", rgba(ICE))
    th.set(T, "colors", "font_hover_pressed_color", rgba(ICE))
    th.set(T, "fonts", "font", body_b)
    th.set(T, "font_sizes", "font_size", "14")

    # primary: one per screen, ignition block, dark caps, hard 2 px shadow
    m_pri = (20, 10, 20, 10)
    pri = flat(th, "sb_primary", IGN, None, (0, 0, 0, 0), 3, m_pri, shadow=2)
    pri_h = flat(th, "sb_primary_hover", IGN_HI, None, (0, 0, 0, 0), 3, m_pri, shadow=2)
    pri_p = flat(th, "sb_primary_pressed", "#d9722f", None, (0, 0, 0, 0), 3, (20, 11, 20, 9))
    pri_d = flat(th, "sb_primary_disabled", (IGN, 0.07), (IGN, 0.3), (1, 1, 1, 1), 3, m_pri)
    T = "CwPrimary"
    th.set(T, "", "base_type", '&"Button"')
    for k, v in (("normal", pri), ("hover", pri_h), ("pressed", pri_p), ("hover_pressed", pri_p), ("disabled", pri_d),
                 ("focus", focus_ring)):
        th.set(T, "styles", k, v)
    for k in ("font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"):
        th.set(T, "colors", k, rgba(SPACE))
    th.set(T, "colors", "font_disabled_color", rgba(IGN, 0.42))
    th.set(T, "colors", "icon_normal_color", rgba(SPACE))
    th.set(T, "colors", "icon_hover_color", rgba(SPACE))
    th.set(T, "colors", "icon_pressed_color", rgba(SPACE))
    th.set(T, "fonts", "font", caps_wide)
    th.set(T, "font_sizes", "font_size", "15")

    # physical keys (time speed): keycap with a darker lip
    key = flat(th, "sb_key", RAISED, LINE, (1, 1, 1, 2), 2, (9, 4, 9, 4))
    key_h = flat(th, "sb_key_hover", HOVER, (ICE, 0.7), (1, 1, 1, 2), 2, (9, 4, 9, 4))
    key_on = flat(th, "sb_key_on", (TEAL, 0.16), TEAL, (1, 1, 1, 1), 2, (9, 5, 9, 4))
    T = "CwKey"
    th.set(T, "", "base_type", '&"Button"')
    for k, v in (("normal", key), ("hover", key_h), ("pressed", key_on), ("hover_pressed", key_on),
                 ("focus", focus_ring), ("disabled", btn_d)):
        th.set(T, "styles", k, v)
    th.set(T, "colors", "font_color", rgba(DIM))
    th.set(T, "colors", "font_hover_color", rgba(TEXT))
    th.set(T, "colors", "font_pressed_color", rgba(TEAL))
    th.set(T, "colors", "font_hover_pressed_color", rgba(TEAL))
    th.set(T, "fonts", "font", mono_m)
    th.set(T, "font_sizes", "font_size", "13")

    # rail buttons: icon-only, teal tab on the left when hovered / open
    rail_h = flat(th, "sb_rail_hover", RAISED, (ICE, 0.35), (2, 0, 0, 0), 2, (6, 6, 6, 6))
    rail_p = flat(th, "sb_rail_pressed", (TEAL, 0.12), TEAL, (2, 0, 0, 0), 2, (6, 6, 6, 6))
    rail_n = flat(th, "sb_rail_normal", (PANEL, 0.0), None, (0, 0, 0, 0), 0, (6, 6, 6, 6))
    T = "CwRailButton"
    th.set(T, "", "base_type", '&"Button"')
    th.set(T, "constants", "icon_max_width", "26")
    for k, v in (("normal", rail_n), ("hover", rail_h), ("pressed", rail_p), ("hover_pressed", rail_p),
                 ("focus", focus_inner), ("disabled", rail_n)):
        th.set(T, "styles", k, v)
    th.set(T, "colors", "icon_normal_color", rgba(ICE, 0.85))
    th.set(T, "colors", "icon_hover_color", rgba("#ffffff"))
    th.set(T, "colors", "icon_pressed_color", rgba(TEAL))
    th.set(T, "colors", "icon_hover_pressed_color", rgba(TEAL))

    # ------------------------------------------------------------------ panels as variations
    for name, sb in (("CwPanel", sb_panel), ("CwPanelTop", sb_panel_top), ("CwStrip", sb_strip), ("CwRail", sb_rail),
                     ("CwPanelInset", sb_inset), ("CwPanelRaised", sb_raised), ("CwCard", sb_card)):
        th.set(name, "", "base_type", '&"PanelContainer"')
        th.set(name, "styles", "panel", sb)
    th.set("PanelContainer", "styles", "panel", sb_panel)
    th.set("Panel", "styles", "panel", sb_panel)

    # ------------------------------------------------------------------ labels
    th.set("Label", "colors", "font_color", rgba(TEXT))
    th.set("Label", "colors", "font_shadow_color", rgba("#000000", 0.0))
    th.set("Label", "colors", "font_outline_color", rgba(SPACE))
    th.set("Label", "fonts", "font", body)
    th.set("Label", "font_sizes", "font_size", "14")
    th.set("Label", "constants", "line_spacing", "2")
    labels = {
        "CwCaps": (caps, "11", DIM), "CwCapsAccent": (caps, "11", TEAL), "CwDim": (body, "13", DIM),
        "CwMono": (mono_m, "17", ICE), "CwMonoSmall": (mono, "13", ICE), "CwMonoLarge": (mono_sb, "28", ICE),
        "CwTitle": (title, "20", TEXT), "CwHeading": (heading, "28", TEXT), "CwDisplay": (display, "40", TEXT),
        "CwBody": (body, "16", TEXT),
    }
    for name, (font, size, col) in labels.items():
        th.set(name, "", "base_type", '&"Label"')
        th.set(name, "colors", "font_color", rgba(col))
        th.set(name, "fonts", "font", font)
        th.set(name, "font_sizes", "font_size", size)
    th.set("CwDisplay", "constants", "line_spacing", "-4")
    th.set("CwHeading", "constants", "line_spacing", "-2")

    T = "RichTextLabel"
    th.set(T, "colors", "default_color", rgba(TEXT))
    th.set(T, "colors", "font_selected_color", rgba("#ffffff"))
    th.set(T, "colors", "selection_color", rgba(VIOLET, 0.35))
    th.set(T, "fonts", "normal_font", body)
    th.set(T, "fonts", "bold_font", body_b)
    th.set(T, "fonts", "italics_font", body_i)
    th.set(T, "fonts", "bold_italics_font", body_b)
    th.set(T, "fonts", "mono_font", mono)
    for k in ("normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"):
        th.set(T, "font_sizes", k, "14")
    th.set(T, "font_sizes", "mono_font_size", "13")
    th.set(T, "constants", "line_separation", "3")
    th.set(T, "styles", "normal", empty)
    th.set(T, "styles", "focus", empty)

    # ------------------------------------------------------------------ separators
    sep = th.sub("StyleBoxLine", "sb_sep", color=rgba(LINE), thickness="1")
    vsep = th.sub("StyleBoxLine", "sb_vsep", color=rgba(LINE), thickness="1", vertical="true")
    th.set("HSeparator", "styles", "separator", sep)
    th.set("HSeparator", "constants", "separation", "9")
    th.set("VSeparator", "styles", "separator", vsep)
    th.set("VSeparator", "constants", "separation", "9")

    # ------------------------------------------------------------------ text fields
    field = flat(th, "sb_field", WELL, LINE, (1, 1, 1, 1), 3, (10, 6, 10, 6))
    field_ro = flat(th, "sb_field_ro", (WELL, 0.6), (LINE, 0.6), (1, 1, 1, 1), 3, (10, 6, 10, 6))
    for T in ("LineEdit", "TextEdit"):
        th.set(T, "styles", "normal", field)
        th.set(T, "styles", "focus", focus_field)
        th.set(T, "styles", "read_only", field_ro)
        th.set(T, "fonts", "font", body)
        th.set(T, "font_sizes", "font_size", "14")
        th.set(T, "colors", "font_color", rgba(TEXT))
        th.set(T, "colors", "font_placeholder_color", rgba(DIM, 0.6))
        th.set(T, "colors", "font_readonly_color", rgba(DIM))
        th.set(T, "colors", "font_selected_color", rgba("#ffffff"))
        th.set(T, "colors", "selection_color", rgba(VIOLET, 0.38))
        th.set(T, "colors", "caret_color", rgba(TEAL))
        th.set(T, "colors", "clear_button_color", rgba(DIM))
        th.set(T, "colors", "clear_button_color_pressed", rgba(TEAL))
        th.set(T, "constants", "caret_width", "2")
    th.set("LineEdit", "icons", "clear", th.tex("close"))
    th.set("TextEdit", "colors", "current_line_color", rgba(RAISED, 0.5))
    th.set("SpinBox", "icons", "updown", th.tex("updown"))

    # ------------------------------------------------------------------ check boxes, toggles
    for T in ("CheckBox", "CheckButton"):
        th.set(T, "styles", "normal", empty)
        th.set(T, "styles", "hover", empty)
        th.set(T, "styles", "pressed", empty)
        th.set(T, "styles", "hover_pressed", empty)
        th.set(T, "styles", "disabled", empty)
        th.set(T, "styles", "focus", focus_ring)
        th.set(T, "colors", "font_color", rgba(TEXT))
        th.set(T, "colors", "font_hover_color", rgba("#ffffff"))
        th.set(T, "colors", "font_pressed_color", rgba(TEXT))
        th.set(T, "colors", "font_hover_pressed_color", rgba("#ffffff"))
        th.set(T, "colors", "font_focus_color", rgba(TEXT))
        th.set(T, "colors", "font_disabled_color", rgba(DIM, 0.5))
        th.set(T, "fonts", "font", body)
        th.set(T, "font_sizes", "font_size", "14")
        th.set(T, "constants", "h_separation", "9")
    for k, f in (("checked", "check_on"), ("unchecked", "check_off"), ("checked_disabled", "check_on_disabled"),
                 ("unchecked_disabled", "check_off_disabled"), ("radio_checked", "radio_on"),
                 ("radio_unchecked", "radio_off"), ("radio_checked_disabled", "radio_on_disabled"),
                 ("radio_unchecked_disabled", "radio_off_disabled")):
        th.set("CheckBox", "icons", k, th.tex(f))
    for k, f in (("checked", "lever_on"), ("unchecked", "lever_off"), ("checked_disabled", "lever_on_disabled"),
                 ("unchecked_disabled", "lever_off_disabled"), ("checked_mirrored", "lever_on"),
                 ("unchecked_mirrored", "lever_off"), ("checked_disabled_mirrored", "lever_on_disabled"),
                 ("unchecked_disabled_mirrored", "lever_off_disabled")):
        th.set("CheckButton", "icons", k, th.tex(f))
    th.set("CwToggle", "", "base_type", '&"CheckButton"')
    th.set("CwToggle", "fonts", "font", caps)
    th.set("CwToggle", "font_sizes", "font_size", "12")
    th.set("CwToggle", "colors", "font_color", rgba(DIM))
    th.set("CwToggle", "colors", "font_pressed_color", rgba(TEAL))
    th.set("CwToggle", "colors", "font_hover_pressed_color", rgba(TEAL))

    # ------------------------------------------------------------------ option button / menus
    T = "OptionButton"
    for k, v in (("normal", flat(th, "sb_opt", RAISED, LINE, (1, 1, 1, 1), 3, (10, 6, 10, 6))),
                 ("hover", flat(th, "sb_opt_h", HOVER, (ICE, 0.6), (1, 1, 1, 1), 3, (10, 6, 10, 6))),
                 ("pressed", flat(th, "sb_opt_p", SPACE, TEAL, (1, 1, 1, 1), 3, (10, 6, 10, 6))),
                 ("disabled", btn_d), ("focus", focus_ring)):
        th.set(T, "styles", k, v)
    th.set(T, "icons", "arrow", th.tex("chevron_down"))
    th.set(T, "constants", "arrow_margin", "8")
    th.set(T, "fonts", "font", body)
    th.set(T, "colors", "font_color", rgba(TEXT))
    th.set(T, "colors", "font_pressed_color", rgba(TEAL))

    T = "PopupMenu"
    th.set(T, "styles", "panel", sb_popup)
    th.set(T, "styles", "hover", flat(th, "sb_menu_hover", RAISED, TEAL, (2, 0, 0, 0), 0, (8, 4, 8, 4)))
    th.set(T, "styles", "separator", sep)
    th.set(T, "styles", "labeled_separator_left", sep)
    th.set(T, "styles", "labeled_separator_right", sep)
    th.set(T, "fonts", "font", body)
    th.set(T, "fonts", "font_separator", caps)
    th.set(T, "font_sizes", "font_size", "14")
    th.set(T, "font_sizes", "font_separator_size", "11")
    th.set(T, "colors", "font_color", rgba(TEXT))
    th.set(T, "colors", "font_hover_color", rgba("#ffffff"))
    th.set(T, "colors", "font_disabled_color", rgba(DIM, 0.5))
    th.set(T, "colors", "font_accelerator_color", rgba(DIM))
    th.set(T, "colors", "font_separator_color", rgba(DIM))
    th.set(T, "constants", "v_separation", "8")
    th.set(T, "constants", "h_separation", "8")
    th.set(T, "constants", "item_start_padding", "10")
    th.set(T, "constants", "item_end_padding", "12")
    for k, f in (("checked", "check_on"), ("unchecked", "check_off"), ("radio_checked", "radio_on"),
                 ("radio_unchecked", "radio_off"), ("submenu", "chevron_right")):
        th.set(T, "icons", k, th.tex(f))

    # ------------------------------------------------------------------ sliders
    track = flat(th, "sb_slider_track", SPACE, LINE, (1, 1, 1, 1), 2, (0, 3, 0, 3))
    fill_teal = flat(th, "sb_slider_fill", (TEAL, 0.85), None, (0, 0, 0, 0), 2, (0, 3, 0, 3))
    fill_teal_hi = flat(th, "sb_slider_fill_hi", TEAL, None, (0, 0, 0, 0), 2, (0, 3, 0, 3))
    T = "HSlider"
    th.set(T, "styles", "slider", track)
    th.set(T, "styles", "grabber_area", fill_teal)
    th.set(T, "styles", "grabber_area_highlight", fill_teal_hi)
    th.set(T, "styles", "focus", focus_ring)
    th.set(T, "icons", "grabber", th.tex("hslider_grabber"))
    th.set(T, "icons", "grabber_highlight", th.tex("hslider_grabber_hl"))
    th.set(T, "icons", "grabber_disabled", th.tex("hslider_grabber_disabled"))
    th.set(T, "icons", "tick", th.tex("slider_tick"))
    th.set(T, "constants", "center_grabber", "0")
    th.set(T, "constants", "grabber_offset", "0")
    vtrack = flat(th, "sb_vslider_track", SPACE, LINE, (1, 1, 1, 1), 2, (3, 0, 3, 0))
    vfill = flat(th, "sb_vslider_fill", (IGN, 0.85), None, (0, 0, 0, 0), 2, (3, 0, 3, 0))
    vfill_hi = flat(th, "sb_vslider_fill_hi", IGN, None, (0, 0, 0, 0), 2, (3, 0, 3, 0))
    T = "VSlider"
    th.set(T, "styles", "slider", vtrack)
    th.set(T, "styles", "grabber_area", vfill)
    th.set(T, "styles", "grabber_area_highlight", vfill_hi)
    th.set(T, "styles", "focus", focus_ring)
    th.set(T, "icons", "grabber", th.tex("vslider_grabber"))
    th.set(T, "icons", "grabber_highlight", th.tex("vslider_grabber_hl"))
    th.set(T, "icons", "grabber_disabled", th.tex("vslider_grabber_disabled"))
    th.set(T, "icons", "tick", th.tex("vslider_tick"))
    # the phase lever: wide slot, engraved notches (set tick_count = 11 on the node)
    slot = flat(th, "sb_throttle_slot", SPACE, HAIR, (1, 1, 1, 1), 2, (7, 0, 7, 0))
    slot_fill = flat(th, "sb_throttle_fill", (IGN, 0.30), (IGN, 0.85), (1, 0, 1, 0), 2, (7, 0, 7, 0))
    slot_fill_hi = flat(th, "sb_throttle_fill_hi", (IGN, 0.45), IGN, (1, 0, 1, 0), 2, (7, 0, 7, 0))
    T = "CwThrottle"
    th.set(T, "", "base_type", '&"VSlider"')
    th.set(T, "styles", "slider", slot)
    th.set(T, "styles", "grabber_area", slot_fill)
    th.set(T, "styles", "grabber_area_highlight", slot_fill_hi)

    # ------------------------------------------------------------------ progress bars (LED)
    def led(sid, col, hl=0.0, frame=None):
        p = {"script": f'ExtResource("{led_script}")', "color": rgba(*col) if isinstance(col, tuple) else rgba(col)}
        if hl:
            p["highlight"] = rgba("#ffffff", hl)
        if frame:
            p["frame_color"] = rgba(frame)
        return th.sub("StyleBox", sid, **p)

    led_track = led("sb_led_track", LINE)
    T = "ProgressBar"
    th.set(T, "styles", "background", led_track)
    th.set(T, "styles", "fill", led("sb_led_teal", TEAL, 0.25))
    th.set(T, "fonts", "font", mono)
    th.set(T, "font_sizes", "font_size", "11")
    th.set(T, "colors", "font_color", rgba(TEXT))
    th.set(T, "colors", "font_outline_color", rgba(SPACE))
    th.set(T, "constants", "outline_size", "3")
    for name, col in (("CwBarEng", IGN), ("CwBarSci", ICE), ("CwBarOps", TEAL), ("CwBarRel", VIOLET),
                      ("CwBarWarn", WARN), ("CwBarDanger", DANGER)):
        th.set(name, "", "base_type", '&"ProgressBar"')
        th.set(name, "styles", "fill", led(f"sb_led_{name[5:].lower()}", col, 0.25))

    # ------------------------------------------------------------------ scroll bars
    sc_track = flat(th, "sb_scroll", (SPACE, 0.55), None, (0, 0, 0, 0), 3, (4, 4, 4, 4))
    sc_grab = flat(th, "sb_scroll_grab", HAIR, None, (0, 0, 0, 0), 3, (4, 4, 4, 4))
    sc_grab_h = flat(th, "sb_scroll_grab_h", DIM, None, (0, 0, 0, 0), 3, (4, 4, 4, 4))
    sc_grab_p = flat(th, "sb_scroll_grab_p", TEAL, None, (0, 0, 0, 0), 3, (4, 4, 4, 4))
    for T in ("VScrollBar", "HScrollBar"):
        th.set(T, "styles", "scroll", sc_track)
        th.set(T, "styles", "scroll_focus", sc_track)
        th.set(T, "styles", "grabber", sc_grab)
        th.set(T, "styles", "grabber_highlight", sc_grab_h)
        th.set(T, "styles", "grabber_pressed", sc_grab_p)
    th.set("ScrollContainer", "styles", "panel", empty)
    th.set("ScrollContainer", "styles", "focus", empty)

    # ------------------------------------------------------------------ tabs
    m_tab = (14, 7, 14, 8)
    tab_sel = panel("sb_tab_sel", bg_color=rgba(PANEL), border_color=rgba(LINE), chamfer="6.0", tick_length="0.0",
                    shadow_offset="0.0", aurora_top="true", padding="Vector4(14, 8, 14, 7)", bevel_color=rgba("#000000", 0))
    tab_un = flat(th, "sb_tab_un", (SPACE, 0.0), None, (0, 0, 0, 1), 0, m_tab)
    tab_hov = flat(th, "sb_tab_hov", (RAISED, 0.6), (ICE, 0.45), (0, 0, 0, 1), 0, m_tab)
    tab_dis = flat(th, "sb_tab_dis", (SPACE, 0.0), None, (0, 0, 0, 0), 0, m_tab)
    for T in ("TabContainer", "TabBar"):
        th.set(T, "styles", "tab_selected", tab_sel)
        th.set(T, "styles", "tab_unselected", tab_un)
        th.set(T, "styles", "tab_hovered", tab_hov)
        th.set(T, "styles", "tab_disabled", tab_dis)
        th.set(T, "styles", "tab_focus", focus_inner)
        th.set(T, "fonts", "font", caps)
        th.set(T, "font_sizes", "font_size", "12")
        th.set(T, "colors", "font_selected_color", rgba(TEXT))
        th.set(T, "colors", "font_unselected_color", rgba(DIM))
        th.set(T, "colors", "font_hovered_color", rgba(TEXT))
        th.set(T, "colors", "font_disabled_color", rgba(DIM, 0.4))
        th.set(T, "colors", "font_outline_color", rgba(SPACE))
        th.set(T, "colors", "drop_mark_color", rgba(TEAL))
        th.set(T, "constants", "h_separation", "6")
        th.set(T, "icons", "increment", th.tex("chevron_right"))
        th.set(T, "icons", "increment_highlight", th.tex("chevron_right_hl"))
        th.set(T, "icons", "decrement", th.tex("chevron_left"))
        th.set(T, "icons", "decrement_highlight", th.tex("chevron_left"))
        th.set(T, "icons", "close", th.tex("close"))
    th.set("TabContainer", "styles", "panel", sb_tab_panel)
    th.set("TabContainer", "styles", "tabbar_background", empty)
    th.set("TabContainer", "constants", "side_margin", "0")
    th.set("TabContainer", "icons", "menu", th.tex("chevron_down"))
    th.set("TabContainer", "icons", "menu_highlight", th.tex("chevron_down_hl"))
    th.set("TabBar", "styles", "button_pressed", btn_p)
    th.set("TabBar", "styles", "button_highlight", btn_h)
    # flat underline tabs (inside panels)
    ul_sel = flat(th, "sb_tab_ul_sel", (SPACE, 0.0), TEAL, (0, 0, 0, 2), 0, (10, 6, 10, 6))
    ul_un = flat(th, "sb_tab_ul_un", (SPACE, 0.0), LINE, (0, 0, 0, 1), 0, (10, 6, 10, 7))
    ul_hov = flat(th, "sb_tab_ul_hov", (SPACE, 0.0), (ICE, 0.6), (0, 0, 0, 1), 0, (10, 6, 10, 7))
    for T, base in (("CwTabsUnderline", "TabContainer"), ("CwTabBarUnderline", "TabBar")):
        th.set(T, "", "base_type", f'&"{base}"')
        th.set(T, "styles", "tab_selected", ul_sel)
        th.set(T, "styles", "tab_unselected", ul_un)
        th.set(T, "styles", "tab_hovered", ul_hov)
    th.set("CwTabsUnderline", "styles", "panel", empty)

    # ------------------------------------------------------------------ item lists and trees
    list_panel = flat(th, "sb_list", WELL, LINE, (1, 1, 1, 1), 3, (4, 4, 4, 4))
    row_sel = flat(th, "sb_row_sel", RAISED, TEAL, (2, 0, 0, 0), 0, (8, 4, 8, 4))
    row_sel_unf = flat(th, "sb_row_sel_unfocused", RAISED, (TEAL, 0.5), (2, 0, 0, 0), 0, (8, 4, 8, 4))
    row_hov = flat(th, "sb_row_hover", (RAISED, 0.55), None, (0, 0, 0, 0), 0, (8, 4, 8, 4))
    cursor = th.sub("StyleBox", "sb_cursor", script=f'ExtResource("{focus_script}")', ring_offset="-1.0",
                    ring_color=rgba(ICE, 0.5))
    T = "ItemList"
    th.set(T, "styles", "panel", list_panel)
    th.set(T, "styles", "focus", empty)
    th.set(T, "styles", "selected", row_sel_unf)
    th.set(T, "styles", "selected_focus", row_sel)
    th.set(T, "styles", "hovered", row_hov)
    th.set(T, "styles", "hovered_selected", row_sel)
    th.set(T, "styles", "hovered_selected_focus", row_sel)
    th.set(T, "styles", "cursor", cursor)
    th.set(T, "styles", "cursor_unfocused", empty)
    th.set(T, "fonts", "font", body)
    th.set(T, "font_sizes", "font_size", "14")
    th.set(T, "colors", "font_color", rgba(TEXT, 0.92))
    th.set(T, "colors", "font_hovered_color", rgba("#ffffff"))
    th.set(T, "colors", "font_selected_color", rgba("#ffffff"))
    th.set(T, "colors", "font_hovered_selected_color", rgba("#ffffff"))
    th.set(T, "colors", "guide_color", rgba(LINE, 0.6))
    th.set(T, "constants", "v_separation", "6")
    th.set(T, "constants", "h_separation", "8")
    th.set(T, "constants", "line_separation", "2")
    th.set(T, "constants", "icon_margin", "8")
    th.set("CwListPlain", "", "base_type", '&"ItemList"')
    th.set("CwListPlain", "styles", "panel", empty)

    T = "Tree"
    th.set(T, "styles", "panel", list_panel)
    th.set(T, "styles", "focus", empty)
    th.set(T, "styles", "selected", row_sel_unf)
    th.set(T, "styles", "selected_focus", row_sel)
    th.set(T, "styles", "hovered", row_hov)
    th.set(T, "styles", "hovered_dimmed", row_hov)
    th.set(T, "styles", "cursor", cursor)
    th.set(T, "styles", "cursor_unfocused", empty)
    th.set(T, "styles", "title_button_normal", flat(th, "sb_tree_title", PANEL, LINE, (0, 0, 0, 1), 0, (8, 5, 8, 5)))
    th.set(T, "styles", "title_button_hover", flat(th, "sb_tree_title_h", RAISED, LINE, (0, 0, 0, 1), 0, (8, 5, 8, 5)))
    th.set(T, "styles", "title_button_pressed", flat(th, "sb_tree_title_p", SPACE, TEAL, (0, 0, 0, 1), 0, (8, 5, 8, 5)))
    th.set(T, "fonts", "font", body)
    th.set(T, "fonts", "title_button_font", caps)
    th.set(T, "font_sizes", "font_size", "14")
    th.set(T, "font_sizes", "title_button_font_size", "11")
    th.set(T, "colors", "font_color", rgba(TEXT, 0.92))
    th.set(T, "colors", "font_selected_color", rgba("#ffffff"))
    th.set(T, "colors", "font_hovered_color", rgba("#ffffff"))
    th.set(T, "colors", "title_button_color", rgba(DIM))
    th.set(T, "colors", "guide_color", rgba(LINE, 0.6))
    th.set(T, "colors", "relationship_line_color", rgba(LINE))
    th.set(T, "colors", "parent_hl_line_color", rgba(HAIR))
    th.set(T, "colors", "children_hl_line_color", rgba(HAIR))
    th.set(T, "colors", "drop_position_color", rgba(TEAL))
    th.set(T, "constants", "v_separation", "6")
    th.set(T, "constants", "h_separation", "6")
    th.set(T, "constants", "item_margin", "14")
    th.set(T, "icons", "arrow", th.tex("chevron_down"))
    th.set(T, "icons", "arrow_collapsed", th.tex("chevron_right"))
    th.set(T, "icons", "checked", th.tex("check_on"))
    th.set(T, "icons", "unchecked", th.tex("check_off"))
    th.set(T, "icons", "updown", th.tex("updown"))

    # ------------------------------------------------------------------ tooltips, windows
    th.set("TooltipPanel", "styles", "panel", sb_tooltip)
    th.set("TooltipLabel", "colors", "font_color", rgba(TEXT))
    th.set("TooltipLabel", "fonts", "font", body)
    th.set("TooltipLabel", "font_sizes", "font_size", "13")
    T = "Window"
    th.set(T, "styles", "embedded_border", sb_window)
    th.set(T, "styles", "embedded_unfocused_border", sb_window)
    th.set(T, "fonts", "title_font", title)
    th.set(T, "font_sizes", "title_font_size", "16")
    th.set(T, "colors", "title_color", rgba(TEXT))
    th.set(T, "colors", "title_outline_modulate", rgba(SPACE))
    th.set(T, "constants", "title_height", "34")
    th.set(T, "constants", "resize_margin", "6")
    th.set(T, "icons", "close", th.tex("close"))
    th.set(T, "icons", "close_pressed", th.tex("close_hl"))
    th.set("AcceptDialog", "styles", "panel", sb_window)
    th.set("AcceptDialog", "constants", "buttons_separation", "10")

    head = (f"default_base_scale = 1.0\ndefault_font = {body}\ndefault_font_size = 14\n")
    th.write(head)
    print(f"wrote {OUT} ({len(th.subs)} sub-resources, {len(th.items)} items)")


if __name__ == "__main__":
    build()
