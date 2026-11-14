# Solar System map (MARGIN part 2)

Voxel solar-system scene: `res://scenes/solar_system/solar_system.tscn`.
Sun, Mercury, Venus, Earth + Moon, Mars, Jupiter + Europa, Saturn (with rings), Uranus,
Neptune and Pluto, with real NASA data, animated orbits/spin, a map camera and an EN/PT HUD.

## Files

| Path | What |
|---|---|
| `data/solar_system.json` | Real data per body: mean radius, semi-major axis (AU; km for moons), orbital period, rotation period, axial tilt, inclination, gravity, J2000 mean longitude / ascending node, EN/PT names, visual palette + style hints, `src` URL (NASA NSSDCA fact sheets; orbital phases from JPL approximate elements) |
| `tools/planet_gen.py` | Voxel planet generator (imports `tools/voxel_gen.py` for meshing, AO and `.glb` writing). Also the **single source of truth for the visual scale formulas** |
| `tools/build_solar_system_scene.py` | Writes the editor scene from the JSON + scale formulas (hand edits are fine; re-running overwrites) |
| `assets/voxel/planets/` | `<id>_lod0/1/2.glb`, `earth_clouds_lod*.glb`, `saturn_rings_lod*.glb`, `icons/<id>.png` (~69 MB total, largest file ~6 MB) |
| `src/solar_system/orbit_body.gd` | `SolarBody` (`@tool`): orbit + spin animation, `preview_in_editor` toggle, `time_scale` |
| `src/solar_system/space_camera.gd` | `SpaceCamera`: orbit/fly camera with smooth focus tracking |
| `src/solar_system/solar_system.gd` | `SolarSystem`: time, focus, picking, labels, HUD text, locale-aware numbers |
| `shaders/solar_*.gdshader` | planet surface, Sun emission, corona, atmosphere halo, orbit line, rings, star sky |
| `i18n/solar_system_strings.csv` | All `SS_*` keys (EN + PT). Register it in `project.godot` (`internationalization/locale/translations`: add `res://i18n/solar_system_strings.en.translation` and `.pt.translation`). Until then the scene loads them itself |
| `tests/test_solar_system.gd` | Headless checks (data, scene, LOD ordering, motion, i18n) |
| `tests/screenshot_solar_system.gd` | Windowed screenshots + render stats |

## Regenerate

```bash
python tools/planet_gen.py                    # all bodies (~15 s); or: python tools/planet_gen.py earth moon
python tools/planet_gen.py --preview out.png  # + a contact sheet of every LOD (quick look without Godot)
python tools/build_solar_system_scene.py      # rewrite scenes/solar_system/solar_system.tscn
godot --headless --path . --import
godot --headless --path . --script res://tests/test_solar_system.gd
godot --path . --resolution 1600x900 --script res://tests/screenshot_solar_system.gd -- <abs_out_dir> [view ...]
```

`planet_gen.py` seeds a `.glb.import` next to each new model with `generate_lods=false`,
`create_shadow_meshes=false`, `ensure_tangents=false`: the LODs are authored, Godot's
automatic mesh LOD would only decimate the voxel edges.

## Compressed scale

Real sizes and distances cannot share a scale on screen (Neptune is 30 AU away, the Earth
is 1/23 000 AU wide). The map compresses both; the HUD always shows the real numbers.
Scene units (u):

| Quantity | Formula | Examples |
|---|---|---|
| body radius | `r = 0.04 * sqrt(R_km)` | Moon 1.67, Earth 3.19, Jupiter 10.58 |
| Sun radius | `r = 18` (clamped; the law above gives 33) | |
| planet orbit | `d = 36 + 72 * sqrt(a_AU)` | Mercury 80.8, Earth 108, Jupiter 200, Neptune 431.5, Pluto 488 |
| moon orbit | `d = r_parent * (1.4 + 0.15 * sqrt(a_km / R_parent_km))` | Moon 8.2 from Earth, Europa 19.7 from Jupiter |
| Saturn rings | real ratio to Saturn's radius (C ring 1.28 R .. A ring 2.35 R) | Cassini Division, Encke Gap |
| time | `time_scale` simulated days per real second (HUD slider: `10^(-2 + 5 v/100)`, 0.01 .. 1000) | default 8 d/s |

Orbits are circular, in their real inclined planes (inclination about the line of nodes).
On load the orbit angle is the JPL mean longitude at J2000 plus mean motion up to **today's
date**, so planets sit near their real heliocentric longitudes (e.g. late Oct 2026 shows
Mercury, Venus and Earth lined up: Venus is at inferior conjunction).
Axial tilt is a rotation about +X (the vernal-equinox direction), so the Earth's north pole
leans the right way and seasons are correct; the anchor counter-rotates against the orbit
so the spin axis stays fixed in space. Retrograde rotators (Venus, Uranus, Pluto) are
expressed by tilt > 90 deg, as in the fact sheets. Tidally locked moons (Moon, Europa) keep
their near side (-X in the model; the Moon's maria are painted there) toward the parent.

Angular speeds are the real ones times `time_scale`, soft-clamped with
`w_shown = limit * tanh(w / limit)` (orbit limit 2.5 rad/s, spin 1.1 rad/s) so nothing strobes
at high time scales; slow motion stays exact.

## LOD and culling

Every body has three voxel meshes under `Pivot/Anchor/Tilt/Spin` (`LOD0/1/2`), switched by
`GeometryInstance3D.visibility_range_*` (distance camera -> mesh, `r` = visual radius,
fade mode *Self* with 12 % margins):

| Mesh | Range | Voxels across radius |
|---|---|---|
| lod0 | 0 .. 14 r | 26 - 48 |
| lod1 | 14 r .. 46 r | 12 - 21 |
| lod2 | 46 r .. inf (moons: .. 700 u, then culled) | 6 - 9 |

14 r is where a planet is ~155 px tall at 1600x900 / fov 50 (lod1 voxels ~ 4 px), 46 r where
it is ~47 px. Clouds, rings and atmosphere use the same ranges (atmosphere culled past 115 r).

Other ranges: name labels hide when the camera is closer than 3.2 r (close-ups stay clean)
and planet labels fade beyond 5.6 x their orbit radius (inner labels declutter in the wide
view); moon labels end at 120 u and moon orbit lines at 180 u. The only per-frame scripts
are one `_process` per body (two angles + one instance shader parameter) and the camera;
everything else (LOD switching, culling, label fading) is done by the renderer.

Measured at the default overview (1600x900, AMD Radeon integrated, D3D12, Forward+):
34.5 - 58 fps (58 = vsync cap; the lower run had other Godot instances busy on the same
machine), ~48.6 k primitives, ~118 draw calls, ~640 objects, ~229 MB video memory.
lod0 triangle counts: 27 k (Pluto) .. 87 k (Jupiter), 705 k for all lod0 meshes together
(never all visible at once).

## Visual design

- Surfaces are painted per voxel from 3D value-noise fields evaluated on the unit sphere
  (so all LODs agree), quantized to <= 255 colors and meshed by `voxel_gen.mesh()` (AO +
  color jitter). Coarse LODs supersample the paint (4-8 samples) to avoid aliasing.
- Relief is exaggerated (Earth land/mountains, crater bowls and rims, Olympus Mons, Valles
  Marineris, Hellas) - voxel worlds read better with steps.
- `solar_planet` blends voxel face normals with the smooth sphere normal and masks light by
  the smooth terminator (no bright stair-step stripes on the night side); the Earth gets an
  ocean glint. `solar_sun` is unshaded HDR emission with limb darkening whose energy eases
  from close-up (granulation readable) to map view (blazing, feeds the glow). Corona =
  camera-facing additive quad. Orbit lines are a per-pixel anti-aliased ring on a flat
  plane with a fading trail behind the body (`head_angle` instance uniform).
- Sky: procedural stars (3 layers, color temperature), Milky Way band with dust lanes,
  faint nebulae; static, so the radiance map is computed once.

## Controls

RMB drag orbit, wheel / PageUp / PageDown zoom, MMB drag or WASD/arrows + Q/E pan (detaches
from the body), double-click a body or keys 0-9 (Sun .. Pluto) to focus, body list buttons,
Space pause, F / Home overview, PT/EN button.

## Known limitations

- Circular orbits (no eccentricity), Europa's phase is arbitrary, the Moon's orbit uses the
  Earth's inertial frame (no nodal precession).
- No planet shadows / eclipses (the Sun light has shadows off: an omni shadow across 900 u
  would cost a lot and look poor) and no ring shadow on Saturn.
- Labels of far bodies can overlap a near planet when they line up behind it.
- The Encke Gap is only visible on Saturn's lod0 (thinner than a voxel on lod1/lod2).
