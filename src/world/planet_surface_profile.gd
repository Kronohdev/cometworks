@tool
class_name PlanetSurfaceProfile
extends Resource
## Everything that makes one planetary surface look and behave like itself:
## gravity, voxel palette, terrain shape (FastNoiseLite layers + craters, dunes,
## lineae), liquids, ice, sky, sun and fog. One .tres per body lives in
## res://resources/planets/. VoxelTerrain reads the terrain part; PlanetSurface
## applies the sky/light part to the WorldEnvironment and the sun.
## Gravity and other physical values: NASA NSSDC Planetary Fact Sheets
## (https://nssdc.gsfc.nasa.gov/planetary/factsheet/), see docs/planet_surfaces.md.

## Material slots of the voxel palette (each gets SHADES brightness variants).
enum Mat { SURFACE, SURFACE_ALT, SUBSURFACE, ROCK, ROCK_STRATA, SAND, ICE, ACCENT, SEABED, PAD }
const MAT_COUNT := 10
const SHADES := 3

@export_group("Identity")
@export var id: StringName = &"body"
## Translation key of the display name (i18n/surface_strings.csv).
@export var name_key: String = "PLANET_BODY"
## Translation key of the one-line description shown in the HUD.
@export var description_key: String = ""
## Terrain seed. Same seed and settings -> bit-identical chunks.
@export var terrain_seed: int = 1

@export_group("Physics")
## Surface gravity in m/s² (NSSDC fact sheet value).
@export var gravity: float = 9.80
@export var has_atmosphere: bool = true
## Mean surface pressure in kPa (0 for airless bodies).
@export var surface_pressure_kpa: float = 101.4
## Mean radius in km (used for a subtle horizon drop and in the docs).
@export var radius_km: float = 6371.0

@export_group("Palette")
@export var color_surface: Color = Color(0.36, 0.56, 0.25)
@export var color_surface_alt: Color = Color(0.29, 0.47, 0.2)
@export var color_subsurface: Color = Color(0.45, 0.33, 0.22)
@export var color_rock: Color = Color(0.48, 0.47, 0.46)
@export var color_rock_strata: Color = Color(0.4, 0.38, 0.37)
@export var color_sand: Color = Color(0.86, 0.79, 0.58)
@export var color_ice: Color = Color(0.93, 0.96, 1.0)
@export var color_accent: Color = Color(0.25, 0.25, 0.27)
@export var color_seabed: Color = Color(0.62, 0.58, 0.45)
@export var color_pad: Color = Color(0.62, 0.62, 0.6)
## Brightness spread of the 3 patch shades of each material.
@export_range(0.0, 0.3, 0.005) var shade_variation: float = 0.07
## Meters of subsurface material under the top voxel before rock starts.
@export var subsurface_depth: float = 3.0
## Thickness in meters of the rock strata bands seen on cliffs (0 = off).
@export var strata_thickness: float = 3.0
## Rise/run above which the top voxel is bare rock (cliffs).
@export var cliff_slope: float = 1.6

@export_group("Terrain shape")
@export var base_height: float = 0.0
## Very low frequency layer: plains vs highlands (and coastline on Earth).
@export var continents: FastNoiseLite
@export var continent_amplitude: float = 60.0
## Ridged mountains, masked by the continent value.
@export var ridges: FastNoiseLite
@export var ridge_amplitude: float = 90.0
## Continent value where mountains start / reach full height.
@export var ridge_mask_low: float = 0.0
@export var ridge_mask_high: float = 0.6
## Small hills and roughness.
@export var detail: FastNoiseLite
@export var detail_amplitude: float = 4.0
## Regional tilt in meters per km along x/z (e.g. land sloping into the sea).
@export var regional_slope: Vector2 = Vector2.ZERO

@export_group("Surface patches")
## Low frequency noise choosing SURFACE_ALT and ACCENT (maria, basalt, forest...).
@export var patches: FastNoiseLite
@export var alt_threshold: float = 0.15
@export var accent_threshold: float = 0.5
## Accent areas are lowered by this many meters (e.g. flooded mare basalt).
@export var accent_depression: float = 0.0

@export_group("Dunes")
@export var dune_amplitude: float = 0.0
@export var dune_wavelength: float = 40.0
@export var dune_direction_deg: float = 30.0
## How much the crests meander (in wavelengths).
@export var dune_warp: float = 0.6
## Continent value above which dunes fade out (dunes live in basins).
@export var dune_max_continent: float = 0.2

@export_group("Craters")
## Craters per km² with radius >= crater_min_radius (0 = no craters).
@export var crater_density: float = 0.0
@export var crater_min_radius: float = 6.0
@export var crater_max_radius: float = 300.0
## Cumulative size distribution N(>R) ∝ R^-exponent (≈2 for lunar craters).
@export var crater_size_exponent: float = 2.0
@export_range(1, 8) var crater_size_classes: int = 5
## Depth / diameter of a fresh simple crater (≈0.2 on the Moon).
@export var crater_depth_ratio: float = 0.2
## Rim height / diameter (≈0.04).
@export var crater_rim_ratio: float = 0.04
## Brightness of fresh crater ejecta (uses SURFACE_ALT shade 2), 0 = off.
@export_range(0.0, 1.0) var crater_ejecta_bright: float = 0.0

@export_group("Lineae")
## Cellular noise: its cell edges become cracks/ridges (Europa lineae).
@export var lineae: FastNoiseLite
@export var lineae_width: float = 0.06
@export var lineae_height: float = 0.0

@export_group("Liquid")
@export var has_sea: bool = false
@export var sea_level: float = 0.0
@export var water_shallow_color: Color = Color(0.16, 0.55, 0.6)
@export var water_deep_color: Color = Color(0.02, 0.12, 0.24)
## Meters above sea level painted as beach sand.
@export var beach_height: float = 2.0

@export_group("Ice")
## Polar-cap style ice: tops above snow_line (with noise) turn to ICE.
@export var polar_ice: bool = false
@export var snow_line: float = 9999.0
@export var snow_blend: float = 25.0

@export_group("Landing zone")
## Flat area around the origin, ready for a lander (0 = off).
@export var flat_zone_radius: float = 40.0
@export var flat_zone_blend: float = 70.0
## Offset of the flat zone relative to the natural terrain height at the origin.
@export var flat_zone_offset: float = 0.0
## Paved (PAD color) launch/landing pad inside the flat zone.
@export var flat_zone_paved: bool = false

@export_group("Props")
## Voxel props scattered on the ground (VoxelPropLibrary.Kind: 0 none, 1 trees,
## 2 boulders, 3 ice blocks).
@export_enum("None", "Trees", "Boulders", "Ice blocks") var prop_kind: int = 0
## Props per 1000 m² where the ground material weight is 1 (forest for trees).
@export var prop_density: float = 0.0
## Leaves / light rock.
@export var prop_color_a: Color = Color(0.2, 0.36, 0.15)
## Trunk / dark rock.
@export var prop_color_b: Color = Color(0.36, 0.25, 0.16)
## Chunks with a coarser LOD get no props (0-1 full detail, 2 half resolution).
@export_range(0, 2) var prop_max_lod: int = 2

@export_group("Sky")
@export var sky_zenith_color: Color = Color(0.2, 0.42, 0.8)
@export var sky_horizon_color: Color = Color(0.7, 0.82, 0.95)
@export var sky_ground_color: Color = Color(0.25, 0.26, 0.24)
## Exponent of the zenith/horizon gradient (higher = thinner horizon band).
@export var sky_gradient_power: float = 0.5
@export_range(0.0, 2.0) var star_intensity: float = 0.0
## Mie-like glow around the sun.
@export var sun_glow_color: Color = Color(1.0, 0.9, 0.7)
@export_range(0.0, 4.0) var sun_glow_strength: float = 0.6
## Big body in the sky (Earth from the Moon, Jupiter from Europa, Saturn from Titan).
@export var sky_body_enabled: bool = false
@export var sky_body_elevation_deg: float = 30.0
@export var sky_body_azimuth_deg: float = 120.0
@export var sky_body_size_deg: float = 2.0
@export var sky_body_color_a: Color = Color(0.25, 0.45, 0.85)
@export var sky_body_color_b: Color = Color(0.95, 0.95, 0.95)
## 0 = cloudy planet (Earth), >0 = number of belt bands (gas giant).
@export var sky_body_bands: float = 0.0

@export_group("Sun and ambient")
@export var sun_color: Color = Color(1.0, 0.96, 0.9)
@export var sun_energy: float = 1.3
@export var sun_elevation_deg: float = 28.0
@export var sun_azimuth_deg: float = 40.0
## Apparent sun diameter in degrees (0.53 at 1 AU).
@export var sun_size_deg: float = 0.53
@export var ambient_color: Color = Color(0.5, 0.6, 0.75)
@export var ambient_energy: float = 0.6
@export var exposure: float = 1.0

@export_group("Cartoon light")
## Colour the shadow side of the toon light leans to on this body (shader global
## cw_shadow_tint, set while the surface is open; see src/core/cw_look.gd).
@export var shadow_tint: Color = Color(0.5, 0.38, 1.0)
## How much of that colour fills the shadows (cw_shadow_fill): airless bodies have dark,
## crisp shadows, Mars and Titan get the sky's light in them.
@export_range(0.0, 1.0, 0.01) var shadow_fill: float = 0.12

@export_group("Fog")
@export var fog_enabled: bool = true
@export var fog_color: Color = Color(0.68, 0.78, 0.9)
@export var fog_density: float = 0.0004
@export_range(0.0, 1.0) var fog_aerial_perspective: float = 0.6
@export_range(0.0, 1.0) var fog_sun_scatter: float = 0.2
@export var fog_height: float = 200.0
@export var fog_height_density: float = 0.0


## Linear-space palette: index = mat * SHADES + shade.
func build_palette() -> PackedColorArray:
	var base: Array[Color] = [color_surface, color_surface_alt, color_subsurface, color_rock,
		color_rock_strata, color_sand, color_ice, color_accent, color_seabed, color_pad]
	var out := PackedColorArray()
	out.resize(MAT_COUNT * SHADES)
	for m in MAT_COUNT:
		for s in SHADES:
			var f := 1.0 + (float(s) - 1.0) * shade_variation
			var c: Color = base[m]
			out[m * SHADES + s] = Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0)).srgb_to_linear()
	return out


## Direction pointing TO the sun (world space, y up).
func sun_direction() -> Vector3:
	return _dir(sun_elevation_deg, sun_azimuth_deg)


func sky_body_direction() -> Vector3:
	return _dir(sky_body_elevation_deg, sky_body_azimuth_deg)


static func _dir(elev_deg: float, azim_deg: float) -> Vector3:
	var e := deg_to_rad(elev_deg)
	var a := deg_to_rad(azim_deg)
	return Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a)).normalized()
