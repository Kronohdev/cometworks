# The Solar System: real orbits, one map

Cometworks has one solar-system map, on real ephemerides, shown in three places:

- the **campus' Solar System map** (M): the flight scene in its map-only mode with the tracked
  missions on top (`scenes/tycoon/tracking/space_map_overlay.tscn`, `SpaceMapOverlay`);
- the **standalone Solar System** (main menu > Sistema Solar, `scenes/solar_system/solar_system.tscn`):
  the same map with today's date and its own panels (`solar_system_overlay.tscn`, `SolarSystemOverlay`);
- the **flight's map** (M during a flight), where the vessel and its patched conics are drawn.

All three are `FlightMap` (`src/flight/flight_map.gd`, `scenes/flight/flight_map.tscn`) on
`FlightSolar` (`src/flight/flight_solar.gd`), which is built on `Ephemeris` (`src/flight/ephemeris.gd`)
and the data in `data/solar_system.json`.

## Calendar

| | |
|---|---|
| Campaign start (week 0, FlightSolar t = 0) | **2026-10-28 12:00 TT** (JD 2461342.0, `FlightSolar.EPOCH_DAYS` = 9797 days after J2000) |
| Campaign end (week 1300 = 25 years of 52 weeks = 9100 days) | **2051-09-27** (JD 2470442.0): the comet Mãe-Gelo's closest approach to the Earth |
| Game clock | `t` seconds after the start; `FlightSolar.date_at(t)`, `days_at(t)`, `jd_at(t)`, `t_of_date(y, m, d, h)` |

The flight's frame at t = 0: the pad (latitude 3° S, the voxel Earth's launch site) is "up" (+Y),
its east is `FlightWorld.EAST`, and the local apparent solar time is 08:00 (the Sun ~30° up in the
east-south-east), which fixes the Earth's real orientation (sidereal angle) in that frame.
TT - UTC (~70 s) is ignored by the calendar.

## Data and sources

`data/solar_system.json` (version 2): one block per body.

| Field | Source |
|---|---|
| `radius_km`, `rotation_period_hours`, `axial_tilt_deg`, `surface_gravity_ms2` | NASA NSSDCA planetary fact sheets (`src` per body) |
| `gm_km3_s2` | JPL SSD / DE440 GM values (Earth = `FlightOrbit.MU` = 398 600.4418 km³/s²) |
| `pole_ra_deg`, `pole_dec_deg` | IAU WGCCRE 2015 spin poles (ICRF): the bodies' axes on the map, Saturn's ring tilt |
| `orbit` (planets) | E. M. Standish & J. G. Williams, *Keplerian elements for approximate positions of the major planets* (JPL, https://ssd.jpl.nasa.gov/planets/approx_pos.html): Table 1 (1800-2050) and Table 2a + 2b (3000 BC - 3000 AD, with the b, c, s, f terms for Jupiter-Neptune), blended over 2049-2051 since the campaign runs to 2051. Pluto: the original 1992 Table 1 row. The table's Earth-Moon barycentre minus the Moon's share (1/82.30057) is the Earth. |
| `orbit` (Moon) | the truncated ELP-2000/82 series of J. Meeus, *Astronomical Algorithms* ch. 47 (tables 47.A and 47.B, 60 + 30 terms), longitude brought back to the J2000 equinox |
| `orbit` (Phobos, Deimos, Io, Europa, Ganymede, Callisto, Titan) | JPL SSD planetary satellite mean elements (https://ssd.jpl.nasa.gov/sats/elem/, epoch 2000-01-01.5, Laplace planes, apsidal and nodal precession), mean longitude rates from the sidereal periods (Galilean moons: Meeus ch. 44) |
| `orbit` (Mãe-Gelo) | fictional, see below |
| `semi_major_axis_*`, `orbital_period_days`, `eccentricity`... | the mean values shown in the info cards |

The flat `mean_longitude_j2000_deg` / `longitude_ascending_node_deg` are kept for older readers.

## Accuracy (tests/test_ephemeris.gd)

| Check | Result |
|---|---|
| Moon, Meeus example 47.a (1992-04-12) | longitude exact to 1e-6°, latitude 0.0006° (truncated latitude series), distance 0.0 km |
| Moon, supermoon perigee 2016-11-14 11:21 UTC (356 509 km) | 356 512 km, 4 min off |
| Moon distance 2025-2035 | 356 450 .. 406 690 km (real extremes ~356 400 .. 406 700) |
| Moon's orbit | inclination 5.0 .. 5.3° to the ecliptic, nodes regress in 18.61 yr, sidereal month 27.3216 d; 18-29° to the Earth's equator |
| Venus 1992-12-20 (Meeus 32.a, VSOP87) | 0.006° in longitude, 0.0003° in latitude, 7e-6 AU in distance |
| Earth perihelion 2026 (Jan 3, 0.98330 AU) | 0.98327 AU, on time |
| March equinox 2024-03-20 03:06 UTC | the Sun is 0.008° (12 min) from the equinox |
| Mars close approaches 2003 / 2018 / 2020 | 0.37297 / 0.38487 / 0.41488 AU (published 0.37272 / 0.38496 / 0.41492), on the right day |
| Periods | Mercury .. Pluto within 0.3 % (inner) / 2 % (outer, osculating) of the fact sheets |
| Satellites | sidereal periods within 0.02 %, Io in Jupiter's equator (3.1° from its orbit), Titan in Saturn's (26.4°) |
| FlightSolar cache (Hermite) vs the series | Moon 0.03 m, Earth 5 m, Mercury 17 m, the moons < 1 m; velocity = d(position)/dt exactly |

## Mãe-Gelo's orbit

A Halley-type comet (fictional, scientifically consistent): perihelion q = 0.90 AU, e = 0.9478
(a = 17.24 AU, aphelion 33.6 AU beyond Neptune, period 71.6 years), i = 18° (prograde, so a
rendezvous is conceivable), Ω = 0°, ω = 0°, perihelion on 2051-09-25 12:00 TT (JD 2470440.0).
It starts the campaign inbound at 31.6 AU, is 7.6 AU from the Sun when it comes within reach
(the last 104 weeks, `missions.json` `approach_weeks`) and passes **0.103 AU (15.5 million km)
from the Earth half a day after week 1300**, the race's last day (`TycoonState.comet_weeks_left`).
On the map its coma and tails grow inside ~5 AU (activity ~ 1/r²): the ion tail straight away
from the Sun, the dust tail bent back along its path, ~0.3 AU long at 1 AU. The campus sky's
comet (cutscenes, `historia-lendas`) is a separate look and is untouched.

## FlightSolar API (the facade)

Unchanged: `get_system()`, `ids`, `names`, `kinds`, `parent`, `children`, `mu`, `radius`, `soi`,
`sma` (mean), `rate` (mean motion), `phase` (mean argument of latitude at t = 0), `plane_p` /
`plane_q` (osculating plane at t = 0, P = ascending node on the ecliptic), `atmo_top`, `colors`,
`sun` / `earth` / `moon`, `ecliptic_normal`, `pos_rel_parent`, `state_rel_parent`, `state_helio`,
`state_rel`, `pos_rel`, `is_ancestor`, `orbit_normal`, `period`, `index_of`, `display_name`,
`build(sun_dir, launch_normal)` (arguments now unused), `EPOCH_DAYS`, `LAUNCH_NORMAL`, `SUN_DIR`
(now a static var: the real Sun direction at t = 0, filled by `build`).

New: `eph` (the Ephemeris), `comet`, `earth_pole`, `ecl_to_pci`, `to_pci()` / `to_ecl()`,
`exact_state_rel_parent()` (uncached), `angle_at(i, t)` (true angle in the plane_p / plane_q basis,
use it instead of `phase + rate * t` to aim at the Moon), `distance_at(i, t)`, `orbit_normal_at(i, t)`,
`orbit_shape(i, t)` (the osculating ellipse for drawing), `pole(i)` (IAU spin axis in PCI),
`days_at`, `jd_at`, `date_at`, `t_of_date`, `PAD_LAT_DEG`, `PAD_EAST`, `PAD_SOLAR_HOUR`.

Consequences for the game: the Moon is no longer in the launch plane (an eastward parking orbit
from 3° S is 18-29° off the Moon's orbit). `SpaceTracking.lunar_injection()` waits in the parking
orbit for the arrival when the Moon crosses its plane (the node), leaves 170° before that place and
tilts the transfer slightly to meet it exactly (~2.7 days, Apollo-like); the launch watch's
`departure()` uses the same rule.

## The map

`FlightMap` draws each orbit as the body's osculating ellipse now (`orbit_shape`), each body on its
IAU axis (tidally locked moons face their parent every frame), the Earth as the flight draws it.
Two size modes: **true scale**, or **readable** (the map bar's *Tamanho legível*; on by default in
the campus map and the standalone view): every body at least 8 px across, never so big that a moon
leaves its orbit; the visibility ranges of its LOD meshes scale with it. The asteroid belt (2600
dots, 2.1-3.3 AU, Kirkwood gaps at 2.50 / 2.82 / 2.96 AU, real eccentricities and inclinations)
and Jupiter's Trojans (700 dots around L4 / L5) are MultiMesh dot clouds (`shaders/map_dots.gdshader`,
constant pixel size, faded out close to a planet); the comet's tails are `shaders/map_comet_tail.gdshader`
ribbons. Colours, widths and counts are in the scene (`scenes/flight/flight_map.tscn`) and the
shared `scenes/flight/map_style.tres`.

New bodies' voxel models: `python tools/planet_gen.py io ganymede callisto titan phobos deimos mae_gelo`
(painters `Io`, `Titan`, `Rocky`), then `godot --headless --path . --import`.

## Tests and screenshots

```bash
godot --headless --path . --script res://tests/test_ephemeris.gd      # real values (above)
godot --headless --path . --script res://tests/test_solar_system.gd   # data, the view, the map
godot --path . --resolution 1600x900 --script res://tests/screenshot_solar_system.gd -- <abs_out_dir> [view ...]
```

## Known limitations

- Satellite phases drift ~1-2° after decades (mean elements); fine for a map, not for a flyby.
- The Earth does not turn in the flight (the pad stays under the same sky).
- No planet shadows or eclipses on the map.
