# Parts catalog expansion (v2) / Expansão do catálogo de peças (v2)

The v2 pass added **80 parts** (catalog total: 174). Every value lives in [`tools/parts_catalog.py`](../tools/parts_catalog.py) (section *catalog expansion (v2)*), which writes [`data/parts.json`](../data/parts.json). New parts carry `"added": "v2"`; existing ids and values are unchanged, so `tools/hangar_calc.py` still prints Andorinha 9302 m/s, Condor 9741 m/s, Garça 10282 m/s.

A expansão v2 acrescentou **80 peças** (total do catálogo: 174). Os valores ficam em `tools/parts_catalog.py`; as peças novas têm `"added": "v2"` e as peças antigas não mudaram.

## Conventions / convenções

- `src`: **ref** = published value of the reference hardware; **approx** = public figures that vary or were rounded/scaled; **derived** = geometry × density; **game** = balance value in the real order of magnitude.
- Names and descriptions are bilingual (`name.en/pt`, `desc.en/pt`); `ref` (bilingual) names the hardware; URLs are in `REFERENCES` (also §7 of the PDF).
- **Crew:** every crewed part has an integer `crew_seats` (capsules 1/2/4, cabin 4, habitat 2, cupola 1; the original `crew_capsule` now has `crew_seats: 3`). Capsules also have `life_support_days` and `heat_shield`.
- Crew capsules are in category `command` (they count as the vessel's flight computer, like the avionics cores); cabin, habitat, cupola, escape tower, chutes, lander legs and wheels stay in `future` (phase 2).
- Stack decouplers keep the `decoupler_` id prefix and fairings the `fairing_` prefix, because staging (`PartDB.is_stack_decoupler`, `is_fairing`) is keyed on those prefixes. No new radial decoupler was added (only `decoupler_radial` is treated as one).
- New propellant **`lh2`** (pure liquid hydrogen, 71 kg/m³) feeds only the nuclear thermal engine, with two LH2 tanks (M-8 m, L-8 m). Solid kick motors (`eng_kick_48`, `eng_kick_37`) have top/bottom stack nodes so they stack under a spacecraft; their propellant is integrated (`prop_mass_kg`).
- New optional fields: `crew_seats`, `life_support_days`, `pressurized_m3`, `momentum_nms`, `torque_nm`, `power_gen_w` + `power_source` (fuel cell / fission; `power_gen_w_1au` also set like the RTG), `reactant_kg_per_kwh`, `relay`/`relay_rate_mbps`, `pointing_urad`, `canopy_diameter_m`, `deploy_alt_km`, `abort_thrust_kn`/`abort_burn_s`, `max_entry_kms`, `docking_class`, `separation_speed_ms`, `surface_only`, `nuclear` + `flag`, `steering`, `cyl_length_m`/`nose_length_m` (fairings). New science capability keys: `seismic`, `organics`, `atmosphere`, `sample_return`.
- No XL (5 m) size class was added: the four node sizes and their adapters stay coherent.

## Models, renders and icons / modelos, renders e ícones

Each new model has a builder in [`tools/voxel_gen.py`](../tools/voxel_gen.py) (`V2_BUILDERS`, plus `V2_PART_BUILDERS` for per-id dimensions), the per-part `.glb` in `assets/voxel/parts/<id>.glb`, a render in `docs/hangar_renders/<model>.png` (made with [`tests/render_parts.gd`](../tests/render_parts.gd)) and a palette icon in `ui/part_icons/<model>.png` (`tools/make_part_icons.py`). Parts that reuse an existing model (tank families, fairings, nose cones, decoupler, adapters, thrust plates, spheres, xenon bottle, battery) reuse its icon, like the original families.

```
python tools/parts_catalog.py
python tools/voxel_gen.py assets/voxel <new ids...>
godot --path . --resolution 1600x900 --script res://tests/render_parts.gd -- docs/hangar_renders <model=part_id ...>
python tools/make_part_icons.py && python tools/build_hangar_pdf.py
```

## Command & Avionics / Comando e Aviônica

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `capsule_1` | Crew Capsule (1 seat) / Cápsula Tripulada (1 lugar) *(phase 2)* | 1,400 kg, 1 seats, 1.5 days life support, 250 W draw | top XS / bottom S | approx | Inspired by Mercury (1 astronaut, ~1,355 kg in orbit, 1.89 m base; scaled to S) |
| `capsule_2` | Crew Capsule (2 seats) / Cápsula Tripulada (2 lugares) *(phase 2)* | 3,200 kg, 2 seats, 14 days life support, 500 W draw | top S / bottom M | approx | Inspired by Gemini (2 crew, 3,850 kg with adapter, 2.3 m base, up to 14 days) |
| `capsule_4` | Crew Capsule (4 seats) / Cápsula Tripulada (4 lugares) *(phase 2)* | 9,500 kg, 4 seats, 7 days life support, 2,000 W draw | top S / bottom L | approx | Inspired by Crew Dragon (4 crew, 3.7 m diameter, integrated abort motors; mass approx.) |

## Propellant Tanks / Tanques de Propelente

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `tank_kerolox_xs1` | Kerosene / LOX Tank XS-1m / Tanque Querosene / LOX XS-1m | 284 kg kerolox, dry 17 kg, 0.28 m³ | top XS / bottom XS / radial | derived | — |
| `tank_kerolox_xs2` | Kerosene / LOX Tank XS-2m / Tanque Querosene / LOX XS-2m | 569 kg kerolox, dry 34 kg, 0.55 m³ | top XS / bottom XS / radial | derived | — |
| `tank_methalox_xs2` | Methane / LOX Tank XS-2m / Tanque Metano / LOX XS-2m | 442 kg methalox, dry 29 kg, 0.55 m³ | top XS / bottom XS / radial | derived | — |
| `tank_hydrolox_xs2` | Hydrogen / LOX Tank XS-2m / Tanque Hidrogênio / LOX XS-2m | 199 kg hydrolox, dry 22 kg, 0.55 m³ | top XS / bottom XS / radial | derived | — |
| `tank_lh2_m8` | Liquid Hydrogen Tank M-8m / Tanque de Hidrogênio Líquido M-8m *(phase 2)* | 2,509 kg lh2, dry 452 kg, 35.34 m³ | top M / bottom M / radial | derived | LH2 density 70.8 kg/m3 at 20 K; dry fraction is a game value |
| `tank_lh2_l8` | Liquid Hydrogen Tank L-8m / Tanque de Hidrogênio Líquido L-8m *(phase 2)* | 5,646 kg lh2, dry 1,016 kg, 79.52 m³ | top L / bottom L / radial | derived | LH2 density 70.8 kg/m3 at 20 K; dry fraction is a game value |
| `tank_hypergolic_14` | Hypergolic Sphere 1.4 m / Esfera Hipergólica 1,4 m | 1,573 kg hypergolic, dry 125.8 kg, 1.32 m³ | top XS / bottom XS / radial | derived | — |
| `tank_hydrazine_12` | Hydrazine Sphere 1.2 m / Esfera de Hidrazina 1,2 m | 840.7 kg hydrazine, dry 100.9 kg, 0.83 m³ | top XS / bottom XS / radial | derived | — |
| `tank_toroid_hyp` | Toroidal Hypergolic Tank / Tanque Toroidal Hipergólico | 281 kg hypergolic, dry 28.1 kg, 0.24 m³ | top S / bottom S / radial | derived | Torus volume 2*pi^2*R*r^2 (R 0.45 m, r 0.17 m, 92% fill); dry fraction 0.10 (game) |
| `tank_xenon_08` | Xenon Tank 0.8 m (COPV) / Tanque de Xenônio 0,8 m (COPV) | 838.6 kg xenon, dry 125.8 kg, 0.52 m³ | top XS / bottom XS / radial | derived | Psyche carried ~1,085 kg of xenon; capsule volume x 1,600 kg/m3 (supercritical) |

## Engines & Thrusters / Motores e Propulsores

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `eng_hidra_5` | Hidra-5 (vacuum) / Hidra-5 (vácuo) | vac 137 kN, Isp 447 s, 285 kg, gimbal 4°, throttle ≥60%, restarts 15 | top S / bottom S | approx | Based on JAXA/MHI LE-5B (137 kN vac, Isp ~447 s, ~285 kg; up to 16 starts) |
| `eng_hidra_j2` | Hidra-100 (upper stage) / Hidra-100 (estágio superior) | SL 486 / vac 1,033 kN, Isp 200/421 s, 1,788 kg, gimbal 7°, throttle ≥80%, restarts 1 | top M / bottom M | ref | Based on Rocketdyne J-2 (486.2 kN SL / 1,033.1 kN vac, Isp 200/421 s, 1,788 kg) |
| `eng_hidra_68` | Hidra-68 (booster) / Hidra-68 (primeiro estágio) | SL 3,137 / vac 3,560 kN, Isp 362/411 s, 6,740 kg, gimbal 6°, throttle ≥58%, restarts 0 | top L / bottom L | ref | Based on Aerojet Rocketdyne RS-68A (3,137 kN SL / 3,560 kN vac, Isp 362/411 s, ~6.7 t) |
| `eng_harpia` | Harpia-2 (dual chamber) / Harpia-2 (câmara dupla) | SL 3,830 / vac 4,152 kN, Isp 311/338 s, 5,480 kg, gimbal 8°, throttle ≥47%, restarts 0 | top L / bottom L | ref | Based on NPO Energomash RD-180 (3,830 kN SL / 4,152 kN vac, Isp 311/338 s, 5,480 kg) |
| `eng_falcao_4v` | Falcão-4V (four chambers, vacuum) / Falcão-4V (quatro câmaras, vácuo) | vac 294 kN, Isp 359 s, 480 kg, gimbal 8°, throttle ≥60%, restarts 2 | top S / bottom S | ref | Based on KBKhA RD-0124 (294.3 kN vac, Isp 359 s, 480 kg) |
| `eng_metano_v` | Metano-V (vacuum) / Metano-V (vácuo) | vac 2,500 kN, Isp 378 s, 1,800 kg, gimbal 0°, throttle ≥40%, restarts 10 | top M / bottom M | approx | Inspired by SpaceX Raptor Vacuum (public figures vary: ~2.5 MN, Isp ~378-380 s; mass approx.) |
| `eng_apogee_490n` | Apogee Thruster 490 N / Propulsor de Apogeu 490 N | vac 490 N, Isp 312 s, 3.6 kg, gimbal 0°, throttle ≥100%, restarts ∞ | top XS / bottom XS / radial | ref | Based on Aerojet R-4D-11 (490 N, Isp 312 s, 3.63 kg) |
| `eng_descent` | Descent Engine DE-45 (throttleable) / Motor de Descida DE-45 (acelerável) | vac 45.0 kN, Isp 311 s, 179 kg, gimbal 6°, throttle ≥10%, restarts 20 | top S / bottom S | ref | Based on the Apollo LM Descent Propulsion System (45.04 kN, Isp 311 s, 179 kg, 10-100% throttle) |
| `eng_mono_lander` | Throttleable Monoprop 3 kN / Monopropelente Acelerável 3 kN | vac 3.1 kN, Isp 225 s, 8.0 kg, gimbal 0°, throttle ≥10%, restarts ∞ | top XS / bottom XS / radial | approx | Inspired by Aerojet MR-80B (MSL / Mars 2020 descent stage, ~3.1 kN, Isp ~225 s; mass approx.) |
| `eng_hall_s` | Hall Thruster HT-100 / Propulsor Hall HT-100 | vac 0.080 N, Isp 1,600 s, 12 kg, gimbal 0°, throttle ≥50%, restarts ∞, 1,350 W | top XS / bottom XS / radial | ref | Based on OKB Fakel SPT-100 (80 mN, Isp 1,600 s, 1.35 kW); mass incl. PPU is a game value |
| `eng_hall_l` | Hall Thruster HT-12k / Propulsor Hall HT-12k | vac 0.600 N, Isp 2,800 s, 100 kg, gimbal 0°, throttle ≥50%, restarts ∞, 12,500 W | top XS / bottom XS / radial | approx | Based on NASA/Aerojet AEPS (600 mN, Isp ~2,800 s, 12.5 kW, ~100 kg per string) |
| `eng_kick_48` | Kick Motor KM-48 (solid) / Motor de Chute KM-48 (sólido) | vac 68.6 kN, Isp 292 s, 131 kg, gimbal 0°, throttle ≥100%, restarts 0, 2,011 kg solid prop. | top S / bottom S | ref | Based on Northrop Grumman Star 48B (2,011 kg propellant, 2,141 kg total, Isp 292.1 s, ~84 s burn) |
| `eng_kick_37` | Kick Motor KM-37 (solid) / Motor de Chute KM-37 (sólido) | vac 47.3 kN, Isp 290 s, 82 kg, gimbal 0°, throttle ≥100%, restarts 0, 1,066 kg solid prop. | top XS / bottom XS | approx | Based on Northrop Grumman Star 37FM (~1,066 kg propellant, Isp ~290 s; approx.) |
| `eng_sep_motor` | Separation Motor (solid) / Motor de Separação (sólido) | SL 98 / vac 102 kN, Isp 236/250 s, 42 kg, gimbal 0°, throttle ≥100%, restarts 0, 34 kg solid prop. | radial | approx | Inspired by the Space Shuttle booster separation motor (~98 kN for ~1 s; values approx.) |
| `eng_aerospike` | Aerospike AS-9 (altitude compensating) / Aerospike AS-9 (compensa a altitude) *(phase 2)* | SL 909 / vac 1,184 kN, Isp 339/439 s, 3,200 kg, gimbal 0°, throttle ≥60%, restarts 3 | top M / bottom M | approx | Based on Rocketdyne XRS-2200 linear aerospike (909 kN SL / 1,184 kN vac, Isp 339/439 s); annular shape and mass are game values |
| `eng_ntr` | Nuclear Thermal NT-75 (vacuum) / Térmico Nuclear NT-75 (vácuo) *(phase 2)* | vac 73.0 kN, Isp 900 s, 2,500 kg, gimbal 4°, throttle ≥60%, restarts 10 | top M / bottom M | approx | Based on the Los Alamos Small Nuclear Rocket Engine study (~16.4-16.7 klbf / 73 kN, Isp ~875-900 s, T/W ~3) |

## Structure & Staging / Estrutura e Estágios

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `decoupler_xs` | Stack Decoupler XS / Desacoplador de Pilha XS | 10 kg | top XS / bottom XS | game | — |
| `decoupler_clamp_s` | Clamp-Band Separation System S / Sistema de Separação por Cinta S | 18 kg | top S / bottom S | approx | Inspired by Beyond Gravity (RUAG) PAS 1194 clamp-band systems (mass approx.) |
| `decoupler_clamp_m` | Clamp-Band Separation System M / Sistema de Separação por Cinta M | 45 kg | top M / bottom M | approx | Inspired by Beyond Gravity (RUAG) PAS 2624 clamp-band systems (mass approx.) |
| `interstage_s` | Interstage S / Interestágio S | 120 kg | top S / bottom S | game | — |
| `adapter_xss` | Adapter XS-S / Adaptador XS-S | 40 kg | top XS / bottom S | game | — |
| `adapter_sl` | Adapter S-L / Adaptador S-L | 350 kg | top S / bottom L | game | — |
| `adapter_rev_ms` | Inverted Adapter M-S / Adaptador Invertido M-S | 180 kg | top M / bottom S | game | — |
| `truss_xs` | Girder Segment XS / Segmento de Viga XS | 25 kg | top XS / bottom XS / radial | game | — |
| `truss_m` | Open Truss Adapter M / Treliça Aberta M | 220 kg | top M / bottom M | game | Like the open truss of Soyuz/R-7 hot staging |
| `strut_radial` | Radial Strut Beam / Viga de Escora Radial | 8.0 kg | radial | game | — |
| `docking_port_xs` | Docking Port XS / Porta de Acoplamento XS *(phase 2)* | 60 kg, 10 W draw | top XS / bottom XS | game | Small probe-and-drogue port (game values) |
| `docking_port_s` | Docking Port S / Porta de Acoplamento S *(phase 2)* | 340 kg, 50 W draw | top S / bottom S | approx | Inspired by the NASA Docking System / IDSS (androgynous, 0.8 m passage; mass approx.) |
| `thrust_plate_l5` | Thrust Plate L x5 / Placa de Empuxo L x5 | 900 kg, 5 engine slots | top L / bottom engines | game | — |
| `thrust_plate_m7` | Thrust Plate M x7 / Placa de Empuxo M x7 | 450 kg, 7 engine slots | top M / bottom engines | game | — |

## Aerodynamics / Aerodinâmica

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `fairing_xs` | Payload Fairing XS / Coifa de Carga XS | 25 kg, 0.500 m inner Ø | bottom XS | game | — |
| `fairing_s_long` | Payload Fairing S (long) / Coifa de Carga S (longa) | 90 kg, 1.1 m inner Ø | bottom S | game | — |
| `fairing_m_long` | Payload Fairing M (long) / Coifa de Carga M (longa) | 750 kg, 2.3 m inner Ø | bottom M | game | — |
| `fairing_l_long` | Payload Fairing L (long) / Coifa de Carga L (longa) | 1,900 kg, 3.5 m inner Ø | bottom L | game | — |
| `nose_cone_xs` | Nose Cone XS / Ogiva XS | 6.0 kg | bottom XS | game | — |
| `nose_cone_l` | Nose Cone L / Ogiva L | 200 kg | bottom L | game | — |
| `fin_large` | Large Stabilizer Fin / Aleta Estabilizadora Grande | 40 kg | radial | game | — |
| `fin_swept` | Swept Fin / Aleta Enflechada | 18 kg | radial | game | — |

## Attitude Control / Controle de Atitude

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `reaction_wheel_s` | Micro Reaction Wheel / Micro Roda de Reação | 0.2 kg, 1 W draw, 0.050 N·m·s, 0.007 N·m | radial | approx | Class of Blue Canyon RWP050 (0.05 Nms, ~0.24 kg) |
| `reaction_wheels_l` | Heavy Reaction Wheel Set / Conjunto Pesado de Rodas de Reação | 52 kg, 100 W draw, 100 N·m·s, 0.200 N·m | — | approx | Class of Honeywell HR16 (up to 100-150 Nms, ~0.2 Nm, ~12 kg each) |
| `cmg` | Control Moment Gyroscope / Giroscópio de Momento de Controle | 272 kg, 150 W draw, 4,760 N·m·s, 258 N·m | radial | ref | Based on the ISS double-gimbal CMG (4,760 Nms, 272 kg, 6,600 rpm) |
| `rcs_block_heavy` | RCS Quad 22 N / RCS Quádruplo 22 N | 3.5 kg, 0.088 kN, 232 s Isp | radial | ref | Based on Aerojet MR-106L (22 N, Isp ~232 s, 0.6 kg each) |
| `rcs_biprop` | Bipropellant RCS Pod 400 N / Módulo RCS Bipropelente 400 N | 9.0 kg, 1.6 kN, 300 s Isp | radial | approx | Inspired by SpaceX Draco (400 N, Isp ~300 s) |

## Power / Energia

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `fuel_cell` | Fuel Cell 7 kW / Célula a Combustível 7 kW | 118 kg, 7,000 W | radial | approx | Based on the Space Shuttle orbiter fuel cell (7 kW continuous, 12 kW peak, ~118 kg; approx.) |
| `solar_wing_l` | Large Solar Wing / Asa Solar Grande | 57.6 kg, 2,591 W | radial | approx | Triple-junction cells ~27-30% efficient |
| `solar_ultraflex` | Circular Fan Array / Painel Solar Circular em Leque | 11.4 kg, 1,372 W | radial | approx | Inspired by Northrop Grumman UltraFlex (InSight, Cygnus): ~100-150 W/kg, 2.15 m fans on InSight |
| `battery_xs` | Battery Pack 100 Wh / Bateria 100 Wh | 0.8 kg, 100 Wh | — | approx | Battery-level ~100-150 Wh/kg (approx.) |
| `fission_reactor` | Fission Power Unit 10 kWe / Unidade de Fissão 10 kWe *(phase 2)* | 1,500 kg, 10,000 W, 30,000 W rejected | bottom XS / radial | approx | Based on NASA Kilopower / KRUSTY (1-10 kWe designs; 10 kWe ~1.5 t, approx.) |

## Communications / Comunicação

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `antenna_relay` | UHF Relay Antenna / Antena de Retransmissão UHF | 5.0 kg, 18 W draw, 0.500 Mbps @Moon, 2 Mbps relay | radial | approx | Inspired by the JPL Electra UHF proximity radio (up to ~2 Mbps; mass approx.) |
| `antenna_optical` | Laser Comm Terminal / Terminal de Comunicação a Laser | 30 kg, 90 W draw, 600 Mbps @Moon | radial | approx | Inspired by NASA DSOC on Psyche (22 cm aperture, up to 267 Mbps from ~0.2 AU) and LLCD (622 Mbps from the Moon) |

## Thermal / Térmica

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `radiator_deploy` | Deployable Radiator / Radiador Desdobrável | 35 kg, 20 W draw, 2,000 W rejected | radial | game | ~100-350 W/m2 rejected by spacecraft radiators near Earth (game values) |
| `heat_shield_m` | Ablative Heat Shield M / Escudo Térmico Ablativo M *(phase 2)* | 450 kg | top M / bottom M | approx | PICA / PICA-X ablators (Stardust, Crew Dragon); masses are game values |
| `heat_shield_l` | Ablative Heat Shield L / Escudo Térmico Ablativo L *(phase 2)* | 900 kg | top L / bottom L | approx | PICA / PICA-X ablators (Stardust, Crew Dragon); masses are game values |

## Science Instruments / Instrumentos Científicos

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `inst_mag_s` | Fluxgate Magnetometer (short boom) / Magnetômetro Fluxgate (haste curta) | 1.2 kg, 1 W draw, 0.050 Gbit/day, fields 0.4 | radial | game | Class of CubeSat fluxgates on ~0.6 m booms |
| `inst_seismo` | Seismometer + Wind Shield / Sismômetro + Escudo de Vento | 30 kg, 9 W draw, 0.300 Gbit/day, seismic 0.9 | radial | approx | Inspired by InSight SEIS (~30 kg with its wind and thermal shield; approx.) |
| `inst_mass_spec` | Mass Spectrometer Suite / Conjunto de Espectrômetro de Massa | 40 kg, 70 W draw, 0.500 Gbit/day, organics 0.9, composition 0.5 | radial | approx | Inspired by Curiosity SAM (40 kg; mass spectrometer, gas chromatograph, laser spectrometer) |
| `inst_weather` | Weather Station / Estação Meteorológica | 5.5 kg, 17 W draw, 0.050 Gbit/day, atmosphere 0.8 | radial | approx | Inspired by Perseverance MEDA (~5.5 kg: wind, pressure, humidity, dust, radiation) |
| `inst_gpr` | Ground-Penetrating Radar / Radar de Penetração no Solo | 3.0 kg, 10 W draw, 0.200 Gbit/day, subsurface 0.6 | radial | approx | Inspired by Perseverance RIMFAX (~3 kg, 150-1,200 MHz, >10 m depth) |
| `inst_src` | Sample Return Capsule / Cápsula de Retorno de Amostras | 46 kg, sample_return 1.0 | bottom XS / radial | ref | Based on the Stardust sample return capsule (45.7 kg, 0.81 m, PICA heat shield, 12.9 km/s entry) |

## Phase 2 (crew & recovery) / Fase 2 (tripulação e recuperação)

| id | name (EN / PT) | key specs | attach | src | based on |
|---|---|---|---|---|---|
| `crew_cabin_m` | Crew Cabin M (4 seats) / Cabine Tripulada M (4 lugares) *(phase 2)* | 2,800 kg, 4 seats, 10 days life support, 400 W draw, 20 m³ pressurized | top M / bottom M | game | — |
| `hab_inflatable` | Inflatable Habitat (2 crew) / Habitat Inflável (2 tripulantes) *(phase 2)* | 1,413 kg, 2 seats, 150 W draw, 16 m³ pressurized | top M / bottom M | ref | Based on Bigelow BEAM on the ISS (1,413 kg, 16 m3 expanded, 4.0 m x 3.2 m); 2-crew rating is a game value |
| `cupola` | Observation Cupola / Cúpula de Observação *(phase 2)* | 1,880 kg, 1 seats, 100 W draw | bottom M | ref | Based on the ISS Cupola (1,880 kg, 2.95 m wide, 1.5 m tall, 7 windows) |
| `les_tower` | Launch Escape Tower / Torre de Escape *(phase 2)* | 4,200 kg, 650 kN abort | bottom S | approx | Based on the Apollo Launch Escape System (~650 kN for ~4 s, ~4.2 t) |
| `parachute_drogue` | Drogue Chute / Paraquedas de Frenagem *(phase 2)* | 40 kg, 7 m canopy | radial | approx | Orion drogues ~7 m, mains ~35 m (116 ft); masses are game values |
| `parachute_radial` | Radial Main Chute / Paraquedas Principal Radial *(phase 2)* | 120 kg, 35 m canopy | radial | approx | Orion drogues ~7 m, mains ~35 m (116 ft); masses are game values |
| `landing_leg_lander` | Lander Leg / Perna de Módulo de Pouso *(phase 2)* | 60 kg | radial | approx | Inspired by the Apollo LM landing gear (honeycomb struts, 0.94 m footpads) |
| `rover_wheel` | Rover Wheel / Roda de Rover *(phase 2)* | 25 kg, 20 W draw | radial | approx | Inspired by Curiosity / Perseverance wheels (0.5 m diameter, 0.4 m wide) |

## Sources / fontes

- LE-5 (JAXA/MHI) — overview: <https://en.wikipedia.org/wiki/LE-5>
- J-2 (Rocketdyne) — overview: <https://en.wikipedia.org/wiki/Rocketdyne_J-2>
- RS-68 / RS-68A — overview: <https://en.wikipedia.org/wiki/RS-68>
- RD-180 — overview: <https://en.wikipedia.org/wiki/RD-180>
- RD-0124 — overview: <https://en.wikipedia.org/wiki/RD-0124>
- SpaceX Raptor (incl. Raptor Vacuum) — overview: <https://en.wikipedia.org/wiki/SpaceX_Raptor>
- R-4D bipropellant thruster — overview: <https://en.wikipedia.org/wiki/R-4D>
- Apollo LM Descent Propulsion System: <https://en.wikipedia.org/wiki/Descent_propulsion_system>
- L3Harris (Aerojet) monopropellant engines incl. MR-80B / MR-106L: <https://www.l3harris.com/sites/default/files/2025-10/l3harris-ar-monopropellant-rocket-engines.pdf>
- SPT-100 Hall thruster (OKB Fakel) — overview: <https://en.wikipedia.org/wiki/SPT-100>
- Advanced Electric Propulsion System (AEPS) — overview: <https://en.wikipedia.org/wiki/Advanced_Electric_Propulsion_System>
- Star 48 solid motor family (Star 48B): <https://en.wikipedia.org/wiki/Star_48>
- Star 37 solid motor family: <https://en.wikipedia.org/wiki/Star_37>
- Space Shuttle Solid Rocket Booster (separation motors): <https://en.wikipedia.org/wiki/Space_Shuttle_Solid_Rocket_Booster>
- XRS-2200 linear aerospike — overview: <https://en.wikipedia.org/wiki/XRS-2200>
- NASA NTRS — Small Nuclear Rocket Engine (SNRE) performance (Borowski et al.): <https://ntrs.nasa.gov/api/citations/20150004421/downloads/20150004421.pdf>
- Liquid hydrogen — properties (density 70.8 kg/m3): <https://en.wikipedia.org/wiki/Liquid_hydrogen>
- Psyche spacecraft (xenon load, DSOC): <https://en.wikipedia.org/wiki/Psyche_(spacecraft)>
- Marman clamp band separation: <https://en.wikipedia.org/wiki/Marman_clamp>
- NASA Docking System / International Docking System Standard: <https://en.wikipedia.org/wiki/NASA_Docking_System>
- Project Mercury spacecraft: <https://en.wikipedia.org/wiki/Mercury_spacecraft>
- Project Gemini spacecraft: <https://en.wikipedia.org/wiki/Gemini_spacecraft>
- SpaceX Dragon 2 (Crew Dragon): <https://en.wikipedia.org/wiki/SpaceX_Dragon_2>
- Bigelow Expandable Activity Module (BEAM): <https://en.wikipedia.org/wiki/Bigelow_Expandable_Activity_Module>
- ISS Cupola: <https://en.wikipedia.org/wiki/Cupola_(ISS_module)>
- Apollo Launch Escape System: <https://en.wikipedia.org/wiki/Launch_escape_system>
- Orion parachute system (NASA): <https://www.nasa.gov/humans-in-space/orion-spacecraft/>
- Apollo Lunar Module landing gear: <https://en.wikipedia.org/wiki/Apollo_Lunar_Module>
- Curiosity rover (wheels, SAM, REMS): <https://en.wikipedia.org/wiki/Curiosity_(rover)>
- Space Shuttle orbiter fuel cells: <https://en.wikipedia.org/wiki/Space_Shuttle_orbiter>
- UltraFlex solar arrays (InSight): <https://en.wikipedia.org/wiki/InSight>
- Kilopower / KRUSTY fission reactor: <https://en.wikipedia.org/wiki/Kilopower>
- Electra UHF proximity radio (JPL): <https://en.wikipedia.org/wiki/Mars_Reconnaissance_Orbiter>
- Deep Space Optical Communications (DSOC): <https://www.jpl.nasa.gov/missions/deep-space-optical-communications-dsoc/>
- Lunar Laser Communication Demonstration (LLCD): <https://en.wikipedia.org/wiki/Lunar_Laser_Communication_Demonstration>
- Control moment gyroscope (ISS CMG figures): <https://en.wikipedia.org/wiki/Control_moment_gyroscope>
- Reaction wheel — overview (HR16 class): <https://en.wikipedia.org/wiki/Reaction_wheel>
- SEIS seismometer (InSight): <https://en.wikipedia.org/wiki/Seismic_Experiment_for_Interior_Structure>
- Perseverance rover instruments (MEDA, RIMFAX): <https://en.wikipedia.org/wiki/Perseverance_(rover)>
- Stardust sample return capsule: <https://en.wikipedia.org/wiki/Stardust_(spacecraft)>
- PICA heat shield material: <https://en.wikipedia.org/wiki/Phenolic-impregnated_carbon_ablator>

Values marked *approx* vary between sources; check the primary source before quoting them publicly.
