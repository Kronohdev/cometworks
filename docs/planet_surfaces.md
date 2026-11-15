# Planet surfaces: voxel terrain (Part 2)

Chunked, streamed, LOD'd voxel terrain for the bodies the spacecraft will land on:
**Earth** (coastal launch site), **Moon**, **Mars**, **Mercury**, **Europa** and **Titan**.
It uses the same look as the hangar models (`tools/voxel_gen.py`): voxels with
per-vertex ambient occlusion, a subtle per-voxel color jitter, vertex colors and a single material.

## Running it

| What | How |
|---|---|
| Demo (every planet, HUD, stats) | open `scenes/surface/surface_demo.tscn` and press F6 |
| One planet, ready for landing gameplay | `scenes/surface/<id>_surface.tscn` (`earth`, `moon`, `mars`, `mercury`, `europa`, `titan`) |
| Headless tests | `godot --headless --path . --script res://tests/test_voxel_terrain.gd` |
| Screenshots + benchmark (opens a window) | `godot --path . --resolution 1600x900 --script res://tests/screenshot_surfaces.gd -- <out_dir> [ids\|all] [jobs=N]` |
| Top-down 2 km maps for tuning a profile (headless works) | `godot --headless --path . --script res://tests/screenshot_surfaces.gd -- <out_dir> all maps` |

Demo controls: **WASD** fly · **Q/E** down/up · **right mouse** look (left click locks the
mouse, **Esc** frees it) · **Shift** fast · **wheel** speed · **PgUp/PgDn** planet ·
**F1** LOD colors · **F2** hide HUD · **L** language (EN/PT).

The texts live in `i18n/surface_strings.csv` (`keys,en,pt`). `SurfaceHUD.ensure_translations()`
loads the imported `.translation` files at runtime if the project does not list them yet,
so the demo is bilingual even before the CSV is registered in Project Settings.

## What is in the editor

Everything visual is a scene or a resource, and the scripts only fill in data:

- `scenes/surface/planet_surface.tscn`: `PlanetSurface` root with a `WorldEnvironment`
  (sky shader, fog, glow, tonemap), the `Sun` (DirectionalLight3D with shadows), `Terrain`
  (`VoxelTerrain`), `Water` (a large plane with the water material) and `LandingSite` (Marker3D).
  Setting `profile` in the inspector re-skins everything: sky, sun angle and color, ambient,
  fog, liquids and terrain. It works in the editor too (`@tool`).
- `scenes/surface/<id>_surface.tscn`: one scene per body. Each instances `planet_surface.tscn`
  with its profile, plus a fly camera (`fly_camera.tscn`) as the streaming focus. To land,
  replace the camera with the lander and point `focus_path` at it.
- `scenes/surface/surface_demo.tscn`: the demo, with its HUD `CanvasLayer` authored in the
  scene (theme `res://ui/margin_theme.tres`).
- `scenes/surface/materials/`: `terrain_material.tres`, `sky_material.tres`, `water_material.tres`.
- `resources/planets/*.tres`: one `PlanetSurfaceProfile` per body. Every value is in the
  inspector, grouped as Physics, Palette, Terrain shape (three FastNoiseLite layers:
  continents, ridges, detail), Surface patches, Dunes, Craters, Lineae, Liquid, Ice,
  Landing zone, Props, Sky, Sun and ambient, and Fog.
- **Editor preview**: `VoxelTerrain` has `editor_preview` (on by default),
  `editor_preview_distance`, `editor_max_lod`, `editor_follow_camera` (streams around the
  editor camera) and a **Rebuild terrain** button. Preview chunks are internal children,
  so they are never saved into the scene.

## Architecture

```
PlanetSurfaceProfile (.tres) ──► VoxelTerrainGenerator (read-only copy, shared by threads)
                                   │  height_at / sample_chunk: noise layers + craters + flat zone
                                   ▼
VoxelTerrain (Node3D) ── quadtree around the focus ──► queue (nearest first)
     │                                                   │ WorkerThreadPool
     │                                                   ▼
     │      sample_chunk (34×34 columns) → VoxelGreedyMesher.build → VoxelPropLibrary.append_chunk
     │                                                   │ results (mutex)
     ▼                                                   ▼
main thread, ≤ upload_budget_ms per frame: ArrayMesh → pooled MeshInstance3D (+ collision bodies)
```

- **Chunks**: 32×32 columns. A chunk at LOD *L* has voxels of 2^L m and covers 32·2^L m.
  Columns are heightmap-based (the vertical size is the column height). Each chunk samples
  one extra ring of columns so that it can mesh its neighbor faces and AO without seams.
- **Terrain field** (`src/world/voxel_terrain_generator.gd`): continents + ridged mountains
  (masked by continents) + detail + regional tilt, plus dunes (asymmetric, with a steep slip
  face), Europa lineae (three families of stretched noise zero-crossings, made into double
  ridges with a gradient-normalized width in meters), and darker "accent" patches (maria,
  basalt, forest) that can be lowered. Craters follow a cumulative power law
  N(>R) ∝ R^-e in log-spaced size classes, are placed by hashed cells, and are rasterized per
  crater (bowl, raised rim, ejecta, central peak above 150 m, random degradation, bright
  fresh ejecta). Craters below 0.7 voxel are skipped at coarse LODs. A flat landing zone is
  blended around the origin; Earth gets a paved 46 m square pad.
- **Materials**: per column, from height, slope, sea level, snow line, patches, lineae,
  dunes and ejecta. There are 10 material slots × 3 shades. Shades come from a medium-scale
  noise, and only for voxels of 4 m or less so that far chunks still merge. Sides show
  layers: top voxel, then subsurface (`subsurface_depth`), then rock with strata bands
  (`strata_thickness`).
- **Greedy meshing** (`src/world/voxel_greedy_mesher.gd`):
  - Top faces get a full 2D greedy merge, keyed by height, color and the 4 corner AO values,
    so the baked AO stays exact.
  - Side faces get a vertical run-length merge per column side, then the runs are merged
    along the slice.
  - Underground faces are never generated, only the exposed shell.
  - AO uses the voxel_gen.py curve (0.50/0.68/0.84/1.0 in sRGB, ×`ao_strength`), and quads
    are split along the brighter diagonal.
  - The per-voxel jitter (±3.5%) and the thin voxel edge lines are added in
    `shaders/surface_terrain.gdshader` by hashing the world voxel cell, so merged quads still
    look per-voxel. The edge lines fade by pixel footprint, which avoids moiré.
- **LOD**: a quadtree walked every `update_interval`. A node of size S splits while its
  distance to the focus (horizontal distance to the node square, plus the height above the
  ground) is below `lod_factor`·S. It merges back only beyond `lod_factor`·`lod_hysteresis`·S.
  There are levels 0 to `max_lod` (1 m to 128 m voxels, 6 km view distance).
  - **No holes while LOD changes**: an old chunk is removed only when the area it covers is
    fully drawn by wanted, ready chunks (`_covered`).
  - **Cracks**: border columns get skirts that extend `skirt_voxels` down; voxel steps hide
    the remaining discontinuities.
- **Streaming**: missing leaves are queued nearest-first. At most `max_jobs_in_flight` jobs
  run at once (default: CPU threads − 2, which leaves room for the main and render threads).
  Results of an old profile or of chunks that are no longer wanted are dropped by epoch and
  key. MeshInstance3D nodes are pooled.
- **Culling**:
  - every chunk is its own MeshInstance3D, so Godot frustum-culls per chunk with tight AABBs;
  - nothing is generated beyond `view_distance`;
  - buried faces are never meshed;
  - chunks with lod > `shadow_max_lod` (2) do not cast shadows;
  - props exist only on LOD 0–2 (LOD 2 uses half-resolution templates).
  - Heightmap column chunks have no empty or fully-buried case, so there are no "empty
    chunk" skips.
- **Props** (`src/world/voxel_props.gd`): voxel trees (round and conifer) on Earth, boulders
  on Moon/Mars/Mercury/Titan, and tilted ice blocks on Europa. They are 1 m-voxel templates
  with the same AO, placed on a 4 m world grid with hashed jitter (LOD-independent) and kept
  away from the landing zone, water and steep spots. They are appended as a second
  (non-indexed) surface of the chunk mesh, so they are culled with the chunk and are part of
  the collision.
- **Collision**: separate 1 m trimesh chunks (`ConcavePolygonShape3D`, both faces) within
  `collision_radius` (56 m) of the focus, rebuilt as it moves, with a 1.5-chunk hysteresis.
  The test checks that a ray hits exactly the voxel top.
  - `VoxelTerrain.get_height(x, z)` and `is_collision_ready(pos, r)` are there for spawning
    and landing.
  - `PlanetSurface` sets the world's default gravity to the profile's value at runtime.

## Profiles and sources

Physical values are from the NASA NSSDC Planetary Fact Sheets,
<https://nssdc.gsfc.nasa.gov/planetary/factsheet/>.

| Body | Gravity (m/s²) | Mean radius (km) | Surface pressure | Source |
|---|---|---|---|---|
| Earth | 9.80 | 6371.0 | 1014 mb = 101.4 kPa | [earthfact](https://nssdc.gsfc.nasa.gov/planetary/factsheet/earthfact.html) |
| Moon | 1.62 | 1737.4 | ~0 (exosphere) | [moonfact](https://nssdc.gsfc.nasa.gov/planetary/factsheet/moonfact.html) |
| Mars | 3.71 | 3389.5 | 6.36 mb = 0.636 kPa | [marsfact](https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html) |
| Mercury | 3.70 | 2439.7 | ~0 (exosphere) | [mercuryfact](https://nssdc.gsfc.nasa.gov/planetary/factsheet/mercuryfact.html) |
| Europa | 1.315 (GM/R² = 3202.7 km³/s² / 1560.8²) | 1560.8 | ~0 | [joviansatfact](https://nssdc.gsfc.nasa.gov/planetary/factsheet/joviansatfact.html) |
| Titan | 1.354 (GM/R² = 8978.1 km³/s² / 2574.7²) | 2574.7 | ~1.5 bar = 146.7 kPa (Huygens) | [saturniansatfact](https://nssdc.gsfc.nasa.gov/planetary/factsheet/saturniansatfact.html) |

Visual choices that follow reality:

- Black skies with stars on the airless bodies.
- Earth seen from the Moon at its real ~1.9°, and Jupiter from Europa at ~12° with belts.
- The Sun's size scales with distance: 0.53° at 1 AU, 1.36° from Mercury, 0.35° from Mars,
  0.12° from Europa.
- Blue-ish glow around the Sun on Mars, and a thick orange haze with dim sunlight on Titan.
- Lunar crater density follows a power law with depth/diameter ≈ 0.19, and Mars craters are
  more degraded.
- Europa has reddish-brown lineae as double ridges. Titan has hydrocarbon dunes, dark
  methane lakes and water-ice bedrock.

The amplitudes are scaled for a ~6 km playable region, not to planetary relief.

## Measured performance (this machine: AMD Radeon integrated GPU, D3D12, 16 CPU threads, 1600×900)

Two Godot editor instances were also open on the same GPU, so the FPS numbers vary between
runs by about ±10 FPS.

| Measure | Value |
|---|---|
| Chunk cost, one thread, 32×32 columns (sampling + greedy meshing) | 2.7–6 ms + 6–9 ms, so ~9–15 ms (Europa's lineae are the slowest to sample) |
| Same, in the streaming pipeline (14 parallel jobs, includes contention) | 16–24 ms per chunk per thread |
| Greedy vs naive faces (6 bodies, LOD 0/2/4/6 samples) | **−63 % to −70 %** quads. Without AO it would be ~−80 %: AO needs identical corners to merge |
| In the full view (~400 chunks, 6 km) | 0.48–0.76 M triangles vs 1.4–1.7 M naive (−55 to −68 %) |
| Full initial load (≈400 chunks) | 1.8–2.6 s |
| Draw calls | ~400–450 |
| Static view (no streaming) | Moon ~85 FPS, Earth (water + trees) ~67 FPS |
| Flying at 40 m/s, 30 m up, streaming continuously (~40 chunks/s), vsync off | Moon 60–71 FPS, Earth 55–63 FPS. 1 % lows ~30–40 FPS while big LOD rings are replaced |
| Terrain main-thread cost | ~1–2 ms/frame on average (upload budget 2.5 ms) |
| Memory | ~94 MB static RAM, ~320 MB VRAM (whole process) |

The frame time is GPU-bound: shadows cost ~15 % and glow ~20 %. If more headroom is needed,
lower `lod_factor`, `shadow_max_lod`, the Sun's `directional_shadow_max_distance`, or turn
glow off on the weakest GPUs.

## Known limitations

- Heightmap columns only: no overhangs or caves yet. The mesher API is column-based.
- LOD transitions still show small vertical steps where a fine chunk meets a coarser one.
  Skirts hide the holes, but not the steps, which look like extra voxel ledges.
- Props pop in and out at the LOD 2 → 3 ring (~250 m). Prop placement is deterministic, but
  at LOD 1/2 the base height snaps to the coarser column.
- Earth's flight benchmark is right at the 60 FPS target on this iGPU (55–63 FPS measured).
  The Moon and the others are above it.
- The headless tests print harmless `Parameter "material" is null` messages when planet
  scenes are freed under the dummy renderer.
- ArrayMesh creation is on the main thread: creating RenderingServer meshes from worker
  threads produced RID errors on this Godot build.

## Free play on the surfaces (Cometworks)

Each `scenes/surface/<body>_surface.tscn` (Moon, Mars, Europa, Mercury, Earth) is now a playable
world on top of the procedural terrain. Everything is placed in the editor; scripts only read data
and put things on the ground.

- **Landforms** (`Features`, `SurfaceTerrainFeature`, `src/world/surface_terrain_feature.gd`): a
  named crater with bright rays, a sinuous rille, layered buttes, a terraced mound, dune fields,
  Europa double ridges and chaos terrain, flattened sites and jump ramps. Move one in the editor and
  the terrain rebuilds around it. They are stamped after the landing zone in
  `VoxelTerrainGenerator._apply_features` (bounding-circle test per sample, a few per world), so
  collision, `get_height` and the rover's ground all see them. The scattered boulders keep out of
  flattened sites, ramps and every point of interest (`PlanetSurface.collect_prop_exclusions`).
- **Look**: the terrain uses the Cometworks toon light (`cw_toon.gdshaderinc`); each profile sets
  its shadow tint and fill (cool and dark on airless bodies, warm on Mars). The Moon's Earth hangs
  as a gibbous disc (drawn about twice its real 1.9° so it reads on screen), Jupiter is 12° wide
  over Europa, Mars keeps its butterscotch sky with a blue glow round the Sun. Mars has drifting dust
  devils, Europa a faint plume over a crack (particle scenes in `scenes/surface/props/`).
- **Content** (`Content`): `SurfacePoi` points of interest with their set pieces (tributes with no
  real logos or text: a gold-foil descent stage with footprints, a tub rover on eight wheels, a
  three-legged lander, a microwave-sized six-wheeled rover, probe debris; plus boulders, ice and
  salt), `collectible.tscn` finds (meteorites, ice, odd rocks, comet crumbs with lore) and
  `challenge_ring.tscn` start rings. All of them are `SurfaceInteractable`s, so the rover reaches
  them and uses its tools on them through the `SurfaceSession` contract.
- **Data** (`data/surface_explore.json`, texts in `i18n/surface_explore_strings.csv`): per body the
  career unlock, every POI's kind, name, fact, official source, science and rover actions, the
  finds' facts and the challenges (`reach_before`, `jump`, `deliver`, `find_all`, `collect_all`).
- **Explore layer** (`Explore`, `scenes/surface/explore/surface_explore.tscn`, `SurfaceExplore`): the
  discovery cards, the challenge card, the field log (J) and photo mode (P, pictures in
  `user://photos/`; places in the frame count as photographed). Without a rover the fly camera is a
  little drone (F investigates the nearest place, Esc goes back).
- **Field log** (`SurfaceLog`): in a career it lives in `TycoonState.discovery["surfaces"]` (saved
  with the career), writes a journal note per place found and turns science into research points
  (`research_per_science`), once per thing; the main menu's free play keeps `user://surface_log.json`.
- **Getting there**: the main menu's *Superfícies* (every world) and the campus HUD button (shown
  once a lander / rover mission reached a surface; `SurfaceLog.is_unlocked`). With the rover side
  present (`scenes/surface/rover_drive.tscn`) the sandbox rover drives (`SurfaceFreePlay`); without
  it the body's scene opens with the drone (`surface_viewer.tscn` over the sleeping campus).

Tests: `tests/test_surface_explore.gd` (data, placement on the ground, gravity, discoveries, finds,
challenges including a ballistic ramp jump per body, the log in free play and in a career, photo
mode, the entry points). Shots: `tests/screenshot_surface_worlds.gd` (each world, `perf` for a
drone flight with FPS) and `tests/screenshot_surface_free_play.gd` (cards, log, photo mode, menu,
campus). Props: `tools/gen_surface_props.py` writes the set-piece scenes and their toon materials.
