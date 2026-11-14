"""Single source of truth for the hangar parts catalog.

Writes data/parts.json (consumed by the Godot project later) and is imported by
tools/hangar_calc.py and tools/build_hangar_pdf.py.

Every user-facing string is bilingual: {"en": ..., "pt": ...}.
Values marked "ref" come from public sources listed in REFERENCES; values marked
"game" are balance values chosen to stay in the real order of magnitude.
"""
import json
import math
from pathlib import Path

G0 = 9.80665

SIZE_CLASSES = {  # node diameter in meters
    "XS": 0.625,
    "S": 1.25,
    "M": 2.5,
    "L": 3.75,
}

# bulk density at a typical mixture ratio, kg/m^3; boil-off is a game value (%/day in space)
PROPELLANTS = {
    "kerolox": {"name": {"en": "Kerosene / LOX", "pt": "Querosene / LOX"}, "density": 1030,
                "density_src": "ref", "boiloff_pct_day": 0.2, "tank_dry_fraction": 0.060,
                "color": "white", "storable": False},
    "methalox": {"name": {"en": "Methane / LOX", "pt": "Metano / LOX"}, "density": 800,
                 "density_src": "ref", "boiloff_pct_day": 0.2, "tank_dry_fraction": 0.065,
                 "color": "steel", "storable": False},
    "hydrolox": {"name": {"en": "Hydrogen / LOX", "pt": "Hidrogênio / LOX"}, "density": 360,
                 "density_src": "ref", "boiloff_pct_day": 1.0, "tank_dry_fraction": 0.110,
                 "color": "foam", "storable": False},
    "hypergolic": {"name": {"en": "MMH / NTO (hypergolic)", "pt": "MMH / NTO (hipergólico)"},
                   "density": 1190, "density_src": "approx", "boiloff_pct_day": 0.0,
                   "tank_dry_fraction": 0.080, "color": "grey", "storable": True},
    "hydrazine": {"name": {"en": "Hydrazine (monoprop)", "pt": "Hidrazina (monopropelente)"},
                  "density": 1010, "density_src": "approx", "boiloff_pct_day": 0.0,
                  "tank_dry_fraction": 0.120, "color": "silver", "storable": True},
    "xenon": {"name": {"en": "Xenon (electric)", "pt": "Xenônio (elétrica)"}, "density": 1600,
              "density_src": "approx", "boiloff_pct_day": 0.0, "tank_dry_fraction": 0.150,
              "color": "gold", "storable": True},
    "solid": {"name": {"en": "Solid (APCP)", "pt": "Sólido (APCP)"}, "density": 1780,
              "density_src": "approx", "boiloff_pct_day": 0.0, "tank_dry_fraction": None,
              "color": "white", "storable": True},
}

CATEGORIES = {
    "command": {"en": "Command & Avionics", "pt": "Comando e Aviônica"},
    "tank": {"en": "Propellant Tanks", "pt": "Tanques de Propelente"},
    "engine": {"en": "Engines & Thrusters", "pt": "Motores e Propulsores"},
    "structure": {"en": "Structure & Staging", "pt": "Estrutura e Estágios"},
    "aero": {"en": "Aerodynamics", "pt": "Aerodinâmica"},
    "control": {"en": "Attitude Control", "pt": "Controle de Atitude"},
    "power": {"en": "Power", "pt": "Energia"},
    "comms": {"en": "Communications", "pt": "Comunicação"},
    "thermal": {"en": "Thermal", "pt": "Térmica"},
    "bus": {"en": "Spacecraft Bus", "pt": "Plataforma (Bus)"},
    "instrument": {"en": "Science Instruments", "pt": "Instrumentos Científicos"},
    "future": {"en": "Phase 2 (crew & recovery)", "pt": "Fase 2 (tripulação e recuperação)"},
}


def L(en, pt):
    return {"en": en, "pt": pt}


PARTS = []


def part(**kw):
    kw.setdefault("attach", {})
    kw.setdefault("cost_musd", 0.0)
    kw.setdefault("power_w", 0.0)
    kw.setdefault("phase", 1)
    PARTS.append(kw)
    return kw


# ------------------------------------------------------------------ command
part(id="avionics_core_s", category="command", model="avionics_core",
     name=L("Avionics Core S", "Núcleo de Aviônica S"),
     desc=L("Flight computer, IMU and guidance. Every vessel needs exactly one root core.",
            "Computador de voo, IMU e guiagem. Todo veículo precisa de exatamente um núcleo raiz."),
     size="S", mass_kg=40, power_w=40, cost_musd=3.0, reliability=0.995,
     attach={"top": "S", "bottom": "S", "radial": False}, src="game")
part(id="avionics_core_m", category="command", model="avionics_core",
     name=L("Avionics Core M", "Núcleo de Aviônica M"),
     desc=L("Redundant flight computer (dual string). Higher reliability, heavier.",
            "Computador de voo redundante (duas cadeias). Mais confiável, mais pesado."),
     size="M", mass_kg=110, power_w=90, cost_musd=8.0, reliability=0.999,
     attach={"top": "M", "bottom": "M", "radial": False}, src="game")

# ------------------------------------------------------------------ tanks
TANK_LENGTHS = [2.0, 4.0, 8.0]
TANK_COST_PER_T = {"kerolox": 0.010, "methalox": 0.012, "hydrolox": 0.030}


def tank_values(prop, d, length, fill=0.90):
    vol = math.pi * d * d / 4.0 * length * fill
    m_prop = vol * PROPELLANTS[prop]["density"]
    m_dry = m_prop * PROPELLANTS[prop]["tank_dry_fraction"]
    return vol, m_prop, m_dry


for prop, model in (("kerolox", "tank_kerolox"), ("methalox", "tank_methalox"), ("hydrolox", "tank_hydrolox")):
    for sz in ("S", "M", "L"):
        for ln in TANK_LENGTHS:
            if sz == "S" and ln == 8.0 and prop != "kerolox":
                continue
            vol, mp, md = tank_values(prop, SIZE_CLASSES[sz], ln)
            pname = PROPELLANTS[prop]["name"]
            part(id=f"tank_{prop}_{sz.lower()}{int(ln)}", category="tank", model=model,
                 name=L(f"{pname['en']} Tank {sz}-{int(ln)}m", f"Tanque {pname['pt']} {sz}-{int(ln)}m"),
                 desc=L(f"Stackable {SIZE_CLASSES[sz]} m tank, {ln:.0f} m long.",
                        f"Tanque empilhável de {SIZE_CLASSES[sz]} m, {ln:.0f} m de comprimento."),
                 size=sz, length_m=ln, propellant=prop, volume_m3=round(vol, 2),
                 prop_mass_kg=round(mp), mass_kg=round(md),
                 cost_musd=round(0.15 + TANK_COST_PER_T[prop] * mp / 1000 * 10, 2),
                 attach={"top": sz, "bottom": sz, "radial": True}, src="derived", family=f"tank_{prop}")

for pid, prop, d, model, nm in (
        ("tank_hypergolic_06", "hypergolic", 0.6, "tank_sphere", L("Hypergolic Sphere 0.6 m", "Esfera Hipergólica 0,6 m")),
        ("tank_hypergolic_10", "hypergolic", 1.0, "tank_sphere", L("Hypergolic Sphere 1.0 m", "Esfera Hipergólica 1,0 m")),
        ("tank_hydrazine_04", "hydrazine", 0.4, "tank_sphere", L("Hydrazine Sphere 0.4 m", "Esfera de Hidrazina 0,4 m")),
        ("tank_hydrazine_08", "hydrazine", 0.8, "tank_sphere", L("Hydrazine Sphere 0.8 m", "Esfera de Hidrazina 0,8 m")),
        ("tank_xenon_05", "xenon", 0.5, "tank_xenon", L("Xenon Tank 0.5 m", "Tanque de Xenônio 0,5 m"))):
    vol = 4 / 3 * math.pi * (d / 2) ** 3 * 0.92
    mp = vol * PROPELLANTS[prop]["density"]
    part(id=pid, category="tank", model=model, name=nm,
         desc=L("Pressurized spacecraft tank. Storable: no boil-off.",
                "Tanque pressurizado de espaçonave. Armazenável: sem evaporação."),
         size="XS", propellant=prop, volume_m3=round(vol, 3), prop_mass_kg=round(mp, 1),
         mass_kg=round(mp * PROPELLANTS[prop]["tank_dry_fraction"], 1),
         cost_musd=round(0.4 + mp / 1000 * 2, 2), attach={"top": "XS", "bottom": "XS", "radial": True},
         src="derived", family=f"tank_{prop}")


# ------------------------------------------------------------------ engines
def engine(pid, model, name, desc, prop, size, t_sl, t_vac, isp_sl, isp_vac, mass, gimbal, throttle_min,
           restarts, cost, rel, ref, src, power_w=0.0, phase=1, attach=None, **extra):
    return part(id=pid, category="engine", model=model, name=name, desc=desc, propellant=prop, size=size,
                thrust_sl_kn=t_sl, thrust_vac_kn=t_vac, isp_sl_s=isp_sl, isp_vac_s=isp_vac, mass_kg=mass,
                gimbal_deg=gimbal, throttle_min=throttle_min, restarts=restarts, cost_musd=cost,
                reliability=rel, ref=ref, src=src, power_w=power_w, phase=phase,
                # solid boosters have an integrated nose and mount sideways on a radial decoupler
                attach=attach or {"top": None if prop == "solid" else size,
                                  "bottom": None if prop == "solid" else size, "radial": size in ("XS",)},
                **extra)


engine("eng_kestrel", "engine_small", L("Kestrel-1 (sea level)", "Kestrel-1 (nível do mar)"),
       L("Small kerolox engine with electric pumps. Cluster 9 under an S tank.",
         "Motor pequeno a querosene com bombas elétricas. Use 9 em cluster sob um tanque S."),
       "kerolox", "XS", 24, 26, 295, 311, 35, 5, 0.7, 0, 0.6, 0.990,
       L("Inspired by Rocket Lab Rutherford (~25 kN, Isp ~311 s, ~35 kg; approx.)",
         "Inspirado no Rutherford da Rocket Lab (~25 kN, Isp ~311 s, ~35 kg; aprox.)"), "approx")
engine("eng_kestrel_v", "engine_small_vac", L("Kestrel-1V (vacuum)", "Kestrel-1V (vácuo)"),
       L("Vacuum-optimized Kestrel with a large nozzle. Upper stages only.",
         "Kestrel otimizado para vácuo, bocal grande. Só em estágios superiores."),
       "kerolox", "XS", 0, 26, 0, 343, 42, 3, 0.7, 3, 0.8, 0.990,
       L("Inspired by Rutherford Vacuum (Isp ~343 s; approx.)", "Inspirado no Rutherford Vacuum (Isp ~343 s; aprox.)"),
       "approx")
engine("eng_falcao", "engine_kerolox", L("Falcão-1 (sea level)", "Falcão-1 (nível do mar)"),
       L("Workhorse gas-generator kerolox engine. Cluster 9 under an L stage.",
         "Motor a querosene de gerador de gás, o 'burro de carga'. Use 9 sob um estágio L."),
       "kerolox", "S", 845, 914, 282, 311, 470, 5, 0.4, 3, 1.0, 0.995,
       L("Inspired by SpaceX Merlin 1D (~845 kN SL, Isp 282/311 s, ~470 kg)",
         "Inspirado no Merlin 1D da SpaceX (~845 kN NM, Isp 282/311 s, ~470 kg)"), "approx")
engine("eng_falcao_v", "engine_kerolox_vac", L("Falcão-1V (vacuum)", "Falcão-1V (vácuo)"),
       L("Kerolox upper-stage engine with a huge radiatively cooled nozzle.",
         "Motor a querosene para estágio superior, bocal enorme resfriado por radiação."),
       "kerolox", "S", 0, 981, 0, 348, 550, 5, 0.4, 4, 1.4, 0.995,
       L("Inspired by Merlin Vacuum (~981 kN, Isp ~348 s; mass is a game value)",
         "Inspirado no Merlin Vacuum (~981 kN, Isp ~348 s; massa é valor de jogo)"), "approx")
engine("eng_hidra_rl", "engine_hydrolox_upper", L("Hidra-10 (vacuum)", "Hidra-10 (vácuo)"),
       L("High-efficiency hydrolox upper-stage engine. Low thrust, superb Isp.",
         "Motor hidrolox de alta eficiência para estágio superior. Pouco empuxo, Isp excelente."),
       "hydrolox", "S", 0, 110, 0, 465, 301, 4, 0.3, 15, 3.0, 0.998,
       L("Based on Aerojet Rocketdyne RL10B-2 (110.1 kN, Isp 465.5 s, 301 kg)",
         "Baseado no RL10B-2 da Aerojet Rocketdyne (110,1 kN, Isp 465,5 s, 301 kg)"), "ref")
engine("eng_hidra_25", "engine_hydrolox_main", L("Hidra-25 (main)", "Hidra-25 (principal)"),
       L("Staged-combustion hydrolox main engine. Expensive, powerful, efficient.",
         "Motor principal hidrolox de combustão em estágios. Caro, potente e eficiente."),
       "hydrolox", "M", 1860, 2279, 366, 452, 3500, 10, 0.67, 0, 20.0, 0.997,
       L("Based on RS-25 (1,860 kN SL / 2,279 kN vac, Isp 366/452 s, ~3.5 t)",
         "Baseado no RS-25 (1.860 kN NM / 2.279 kN vácuo, Isp 366/452 s, ~3,5 t)"), "ref")
engine("eng_metano_r", "engine_methalox", L("Metano-R (sea level)", "Metano-R (nível do mar)"),
       L("Full-flow methalox engine. High thrust, reusable, clean burning.",
         "Motor metalox de fluxo total. Alto empuxo, reutilizável e queima limpa."),
       "methalox", "M", 2260, 2450, 327, 350, 1600, 15, 0.4, 5, 2.0, 0.993,
       L("Inspired by SpaceX Raptor (public figures vary; ~2.3 MN, Isp ~327 s SL; approx.)",
         "Inspirado no Raptor da SpaceX (números públicos variam; ~2,3 MN, Isp ~327 s NM; aprox.)"), "approx")
engine("eng_omega", "engine_hypergolic", L("Ômega-27 (hypergolic)", "Ômega-27 (hipergólico)"),
       L("Pressure-fed hypergolic engine. Ignites on contact, unlimited restarts, storable for years.",
         "Motor hipergólico alimentado por pressão. Acende por contato, reignições ilimitadas, armazenável por anos."),
       "hypergolic", "XS", 0, 26.7, 0, 316, 118, 6, 1.0, 999, 2.5, 0.999,
       L("Inspired by the Shuttle OMS engine AJ10-190 (26.7 kN, Isp ~316 s; mass approx.)",
         "Inspirado no motor OMS do Shuttle AJ10-190 (26,7 kN, Isp ~316 s; massa aprox.)"), "approx")
engine("eng_srb_s", "srb", L("Booster SRB-S", "Propulsor Sólido SRB-S"),
       L("Small solid booster with integrated propellant. Cannot throttle or shut down.",
         "Propulsor sólido pequeno com propelente integrado. Não acelera nem desliga."),
       "solid", "S", 420, 460, 242, 268, 1300, 0, 1.0, 0, 3.0, 0.995,
       L("Isp follows the Shuttle SRB (242 s SL / 268 s vac); size is a game value",
         "Isp segue o SRB do Shuttle (242 s NM / 268 s vácuo); tamanho é valor de jogo"), "approx",
       prop_mass_kg=10000, length_m=9.0)
engine("eng_srb_m", "srb", L("Booster SRB-M", "Propulsor Sólido SRB-M"),
       L("Medium solid booster strapped radially to a core stage.",
         "Propulsor sólido médio fixado radialmente ao estágio central."),
       "solid", "M", 1600, 1750, 242, 268, 6000, 3, 1.0, 0, 9.0, 0.995,
       L("Isp follows the Shuttle SRB (242 s SL / 268 s vac); size is a game value",
         "Isp segue o SRB do Shuttle (242 s NM / 268 s vácuo); tamanho é valor de jogo"), "approx",
       prop_mass_kg=45000, length_m=17.0)
engine("eng_mono_22n", "thruster_mono", L("Monoprop Thruster 22 N", "Propulsor Monopropelente 22 N"),
       L("Catalytic hydrazine thruster for orbit corrections.",
         "Propulsor catalítico de hidrazina para correções de órbita."),
       "hydrazine", "XS", 0, 0.022, 0, 232, 0.6, 0, 1.0, 9999, 0.3, 0.999,
       L("Based on Aerojet MR-106L (10-34 N, Isp 228-236 s, 0.6 kg)",
         "Baseado no MR-106L da Aerojet (10-34 N, Isp 228-236 s, 0,6 kg)"), "ref")
engine("eng_ion", "thruster_ion", L("Ion Thruster NX-7", "Propulsor Iônico NX-7"),
       L("Gridded ion engine. Tiny thrust, enormous Isp, needs ~6.9 kW of power.",
         "Motor iônico de grades. Empuxo minúsculo, Isp enorme, precisa de ~6,9 kW de energia."),
       "xenon", "XS", 0, 0.000236, 0, 4190, 60, 0, 0.1, 9999, 8.0, 0.995,
       L("Based on NASA NEXT-C (236 mN, Isp ~4,190 s, 6.9 kW); mass incl. PPU is a game value",
         "Baseado no NEXT-C da NASA (236 mN, Isp ~4.190 s, 6,9 kW); massa com PPU é valor de jogo"), "ref",
       power_w=6900)

# ------------------------------------------------------------------ structure
for sz, m, c in (("S", 30, 0.3), ("M", 120, 0.8), ("L", 250, 1.5)):
    part(id=f"decoupler_{sz.lower()}", category="structure", model="decoupler",
         name=L(f"Stack Decoupler {sz}", f"Desacoplador de Pilha {sz}"),
         desc=L("Pyrotechnic separation ring. Defines where one stage ends and the next begins.",
                "Anel de separação pirotécnico. Define onde um estágio termina e o próximo começa."),
         size=sz, mass_kg=m, cost_musd=c, reliability=0.999, attach={"top": sz, "bottom": sz, "radial": False},
         src="game", ejection_impulse_kns=round(m * 0.02, 2))
part(id="decoupler_radial", category="structure", model="decoupler_radial",
     name=L("Radial Decoupler", "Desacoplador Radial"),
     desc=L("Holds side boosters; releases them when they burn out.",
            "Segura propulsores laterais e os solta quando se esgotam."),
     size="XS", mass_kg=40, cost_musd=0.2, reliability=0.999, attach={"top": None, "bottom": None, "radial": True},
     src="game")
for sz, m in (("M", 400), ("L", 700)):
    part(id=f"interstage_{sz.lower()}", category="structure", model="interstage",
         name=L(f"Interstage {sz}", f"Interestágio {sz}"),
         desc=L("Hollow shell that covers the upper-stage engine nozzle.",
                "Casca oca que cobre o bocal do motor do estágio superior."),
         size=sz, length_m=3.0, mass_kg=m, cost_musd=0.6, attach={"top": sz, "bottom": sz, "radial": False}, src="game")
for a, b, m in (("S", "M", 150), ("M", "L", 300)):
    part(id=f"adapter_{a.lower()}{b.lower()}", category="structure", model="adapter",
         name=L(f"Adapter {a}-{b}", f"Adaptador {a}-{b}"),
         desc=L("Conical adapter between two diameter classes.", "Adaptador cônico entre duas classes de diâmetro."),
         size=b, mass_kg=m, cost_musd=0.3, attach={"top": a, "bottom": b, "radial": False}, src="game")
for sz, slots, m in (("S", 9, 60), ("L", 9, 1200), ("M", 3, 300)):
    part(id=f"thrust_plate_{sz.lower()}{slots}", category="structure", model="thrust_plate",
         name=L(f"Thrust Plate {sz} x{slots}", f"Placa de Empuxo {sz} x{slots}"),
         desc=L(f"Engine mount with {slots} engine slots in a ring+center pattern.",
                f"Suporte de motores com {slots} posições (anel + centro)."),
         size=sz, mass_kg=m, cost_musd=0.4, engine_slots=slots, attach={"top": sz, "bottom": "engines", "radial": False},
         src="game")
for sz, m, inner in (("S", 60, 1.1), ("M", 500, 2.3), ("L", 1300, 3.5)):
    part(id=f"fairing_{sz.lower()}", category="aero", model="fairing",
         name=L(f"Payload Fairing {sz}", f"Coifa de Carga {sz}"),
         desc=L("Aerodynamic shell protecting the spacecraft through max-Q; jettisoned above ~110 km.",
                "Casca aerodinâmica que protege a espaçonave no Max-Q; descartada acima de ~110 km."),
         size=sz, mass_kg=m, cost_musd=round(m / 300, 2), inner_diameter_m=inner,
         attach={"top": None, "bottom": sz, "radial": False}, src="game")
for sz, m in (("S", 20), ("M", 80)):
    part(id=f"nose_cone_{sz.lower()}", category="aero", model="nose_cone",
         name=L(f"Nose Cone {sz}", f"Ogiva {sz}"),
         desc=L("Reduces drag on boosters and sounding rockets.", "Reduz o arrasto de boosters e foguetes de sondagem."),
         size=sz, mass_kg=m, cost_musd=0.05, attach={"top": None, "bottom": sz, "radial": False}, src="game")
part(id="fin_basic", category="aero", model="fin", name=L("Stabilizer Fin", "Aleta Estabilizadora"),
     desc=L("Moves the center of pressure aft. Useful on small rockets without gimbal.",
            "Move o centro de pressão para trás. Útil em foguetes pequenos sem gimbal."),
     size="XS", mass_kg=15, cost_musd=0.02, attach={"top": None, "bottom": None, "radial": True}, src="game")
part(id="payload_adapter", category="structure", model="payload_adapter",
     name=L("Payload Adapter", "Adaptador de Carga"),
     desc=L("Separation interface between the launcher and the spacecraft.",
            "Interface de separação entre o lançador e a espaçonave."),
     size="M", mass_kg=90, cost_musd=0.5, attach={"top": "XS", "bottom": "M", "radial": False}, src="game")

# ------------------------------------------------------------------ control
part(id="reaction_wheels", category="control", model="reaction_wheels",
     name=L("Reaction Wheel Set", "Conjunto de Rodas de Reação"),
     desc=L("Four wheels for fine pointing without propellant. Saturate over time.",
            "Quatro rodas para apontamento fino sem propelente. Saturam com o tempo."),
     size="XS", mass_kg=12, power_w=25, cost_musd=1.5, reliability=0.990, src="game")
part(id="rcs_block", category="control", model="rcs_block", name=L("RCS Quad Block", "Bloco RCS Quádruplo"),
     desc=L("Four 1 N hydrazine thrusters for attitude control and wheel desaturation.",
            "Quatro propulsores de hidrazina de 1 N para atitude e dessaturação das rodas."),
     size="XS", mass_kg=1.5, cost_musd=0.4, propellant="hydrazine", thrust_vac_kn=0.004, isp_vac_s=215,
     attach={"radial": True}, ref=L("Based on Aerojet MR-103 (~1 N, Isp 202-224 s, 0.37 kg each)",
                                    "Baseado no MR-103 da Aerojet (~1 N, Isp 202-224 s, 0,37 kg cada)"), src="ref")
part(id="star_tracker", category="control", model="star_tracker", name=L("Star Tracker", "Rastreador de Estrelas"),
     desc=L("Camera that recognizes star patterns. Enables arcsecond-level pointing.",
            "Câmera que reconhece padrões de estrelas. Permite apontamento de segundos de arco."),
     size="XS", mass_kg=3, power_w=8, cost_musd=1.0, attach={"radial": True}, src="game")

# ------------------------------------------------------------------ power
SOLAR_1AU = 1361  # W/m^2
for pid, model, nm, area, wkg, cost, d in (
        ("solar_body", "solar_body", L("Body-Mounted Solar Panel", "Painel Solar de Corpo"), 0.5, 25, 0.5,
         L("Fixed to the bus. No deployment risk, poor sun angle.", "Fixo no bus. Sem risco de abertura, ângulo ruim.")),
        ("solar_wing", "solar_wing", L("Deployable Solar Wing", "Asa Solar Desdobrável"), 4.0, 40, 3.0,
         L("Rigid folding wing on a gimbal. Tracks the Sun.", "Asa rígida dobrável com gimbal. Segue o Sol.")),
        ("solar_rollout", "solar_rollout", L("Roll-Out Solar Array", "Painel Solar Enrolável"), 8.0, 110, 6.0,
         L("Flexible blanket unrolled from two booms. Very light per watt.",
           "Manta flexível desenrolada por duas hastes. Muito leve por watt."))):
    p_bol = area * SOLAR_1AU * 0.28
    part(id=pid, category="power", model=model, name=nm, desc=d, size="XS", area_m2=area,
         power_gen_w_1au=round(p_bol), mass_kg=round(p_bol / wkg, 1), specific_power_w_kg=wkg,
         cost_musd=cost, reliability=0.985 if pid != "solar_body" else 0.998, attach={"radial": True},
         ref=L("ROSA: 100-120 W/kg (Redwire); triple-junction cells ~27-30% efficient",
               "ROSA: 100-120 W/kg (Redwire); células de tripla junção ~27-30% de eficiência")
         if pid == "solar_rollout" else L("Triple-junction cells ~27-30% efficient", "Células de tripla junção ~27-30% de eficiência"),
         src="ref" if pid == "solar_rollout" else "approx")
for pid, wh, nm in (("battery_s", 400, L("Battery Pack 400 Wh", "Bateria 400 Wh")),
                    ("battery_m", 2000, L("Battery Pack 2 kWh", "Bateria 2 kWh"))):
    part(id=pid, category="power", model="battery", name=nm,
         desc=L("Li-ion pack. Carries the spacecraft through eclipses.", "Pacote de íons de lítio. Sustenta a nave durante eclipses."),
         size="XS", capacity_wh=wh, mass_kg=round(wh / 120, 1), cost_musd=round(wh / 1000 * 0.8 + 0.2, 2),
         reliability=0.995, ref=L("Battery-level ~100-150 Wh/kg (approx.)", "Nível de bateria ~100-150 Wh/kg (aprox.)"),
         src="approx")
part(id="rtg", category="power", model="rtg", name=L("Radioisotope Generator (RTG)", "Gerador Radioisotópico (RTG)"),
     desc=L("Plutonium-238 decay heat to electricity. Works anywhere, decays ~4%/year.",
            "Calor do decaimento de plutônio-238 vira eletricidade. Funciona em qualquer lugar, perde ~4%/ano."),
     size="XS", mass_kg=45, power_w=0, power_gen_w_1au=110, cost_musd=80.0, reliability=0.999,
     attach={"radial": True}, ref=L("Based on NASA MMRTG (~110 W at start, ~45 kg)",
                                    "Baseado no MMRTG da NASA (~110 W no início, ~45 kg)"), src="ref", phase=1)

# ------------------------------------------------------------------ comms
for pid, model, nm, m, p, rate, c, d in (
        ("antenna_omni", "antenna_omni", L("Omni Antenna", "Antena Omni"), 1.0, 5, 0.01, 0.2,
         L("Works in any orientation. Emergency link, very low data rate.",
           "Funciona em qualquer orientação. Link de emergência, taxa muito baixa.")),
        ("antenna_mga", "antenna_dish_s", L("Medium-Gain Dish 0.5 m", "Antena Média 0,5 m"), 6.0, 30, 2.0, 1.5,
         L("Must point roughly at Earth. Good for the Moon.", "Precisa apontar para a Terra. Boa para a Lua.")),
        ("antenna_hga", "antenna_dish_l", L("High-Gain Dish 1.5 m", "Antena de Alto Ganho 1,5 m"), 20.0, 60, 20.0, 5.0,
         L("X/Ka-band workhorse for deep space. Needs precise pointing.",
           "Antena X/Ka para espaço profundo. Exige apontamento preciso.")),
        ("antenna_hga_xl", "antenna_dish_l", L("High-Gain Dish 3 m", "Antena de Alto Ganho 3 m"), 50.0, 100, 80.0, 12.0,
         L("Large reflector for planetary orbiters with heavy data loads.",
           "Refletor grande para orbitadores planetários com muitos dados."))):
    part(id=pid, category="comms", model=model, name=nm, desc=d, size="XS", mass_kg=m, power_w=p,
         rate_ref_mbps_moon=rate, cost_musd=c, reliability=0.995, attach={"radial": True}, src="game")

# ------------------------------------------------------------------ thermal
part(id="radiator", category="thermal", model="radiator", name=L("Radiator Panel", "Painel Radiador"),
     desc=L("Rejects waste heat to space. Needed for high-power payloads.",
            "Rejeita calor para o espaço. Necessário para cargas de alta potência."),
     size="XS", mass_kg=8, cost_musd=0.4, heat_reject_w=400, attach={"radial": True}, src="game")
part(id="mli_heaters", category="thermal", model="mli", name=L("MLI Blankets + Heaters", "Mantas MLI + Aquecedores"),
     desc=L("Gold multi-layer insulation and heaters. Keeps electronics alive far from the Sun.",
            "Isolamento multicamadas dourado e aquecedores. Mantém a eletrônica viva longe do Sol."),
     size="XS", mass_kg=10, power_w=30, cost_musd=0.5, src="game")

# ------------------------------------------------------------------ bus
for pid, nm, m, cap, slots, c in (
        ("bus_cubesat", L("CubeSat 6U Bus", "Bus CubeSat 6U"), 3, 6, 3, 1.0),
        ("bus_small", L("Small Bus (150 kg class)", "Bus Pequeno (classe 150 kg)"), 90, 60, 4, 15.0),
        ("bus_medium", L("Medium Bus (600 kg class)", "Bus Médio (classe 600 kg)"), 350, 250, 6, 60.0),
        ("bus_large", L("Large Bus (1500 kg class)", "Bus Grande (classe 1500 kg)"), 900, 600, 8, 150.0)):
    part(id=pid, category="bus", model="bus_box", name=nm,
         desc=L("Primary structure, harness and wiring. Defines payload capacity and instrument slots.",
                "Estrutura primária e cabeamento. Define capacidade de carga e posições de instrumentos."),
         size="XS" if pid == "bus_cubesat" else "S", mass_kg=m, payload_capacity_kg=cap, instrument_slots=slots,
         cost_musd=c, attach={"top": "XS", "bottom": "XS", "radial": True}, src="game")

# ------------------------------------------------------------------ instruments (from the GDD)
for pid, model, nm, m, p, data, c, cap in (
        ("inst_wac", "camera", L("Wide-Angle Camera", "Câmera Grande-Angular"), 6, 12, 8, 12, "imaging:0.5"),
        ("inst_nac", "camera_hr", L("High-Resolution Camera", "Câmera de Alta Resolução"), 18, 25, 20, 30, "imaging:0.9"),
        ("inst_neutron", "neutron_spec", L("Neutron Spectrometer", "Espectrômetro de Nêutrons"), 12, 14, 0.5, 22, "hydrogen:0.9"),
        ("inst_ir", "spectrometer", L("IR Spectrometer", "Espectrômetro IR"), 25, 30, 6, 40, "composition:0.9"),
        ("inst_radar", "radar", L("Radar Sounder / SAR", "Radar Sondador / SAR"), 20, 90, 40, 55, "subsurface:0.9"),
        ("inst_lidar", "lidar", L("Laser Altimeter", "Altímetro Laser"), 15, 25, 1, 35, "topography:0.9"),
        ("inst_thermal", "spectrometer", L("Thermal Radiometer", "Radiômetro Térmico"), 10, 15, 2, 20, "thermal:0.9"),
        ("inst_mag", "magnetometer", L("Magnetometer + Boom", "Magnetômetro + Haste"), 3, 2, 0.1, 8, "fields:0.6"),
        ("inst_multispectral", "camera", L("Multispectral Imager (Earth)", "Imageador Multiespectral (Terra)"), 15, 20, 15, 28, "vegetation:0.9")):
    k, v = cap.split(":")
    part(id=pid, category="instrument", model=model, name=nm,
         desc=L("Science payload. Value depends on orbit, pointing and data actually downlinked.",
                "Carga científica. O valor depende da órbita, do apontamento e dos dados realmente baixados."),
         size="XS", mass_kg=m, power_w=p, data_gbit_day=data, cost_musd=c, capabilities={k: float(v)},
         reliability=0.990, attach={"radial": True}, src="game")

# ------------------------------------------------------------------ phase 2
part(id="crew_capsule", category="future", model="crew_capsule", name=L("Crew Capsule (3 seats)", "Cápsula Tripulada (3 lugares)"),
     desc=L("Pressurized capsule with heat shield and docking port. Phase 2.",
            "Cápsula pressurizada com escudo térmico e porta de acoplamento. Fase 2."),
     size="M", mass_kg=8500, power_w=800, cost_musd=300, attach={"top": "S", "bottom": "M", "radial": False},
     src="game", phase=2, crew_seats=3)
part(id="parachute", category="future", model="parachute", name=L("Parachute Pack", "Pacote de Paraquedas"),
     desc=L("Main parachutes for splashdown. Phase 2.", "Paraquedas principais para amerissagem. Fase 2."),
     size="S", mass_kg=150, cost_musd=1.0, src="game", phase=2)
part(id="landing_legs", category="future", model="landing_legs", name=L("Landing Legs", "Pernas de Pouso"),
     desc=L("Deployable legs for propulsive booster landing. Phase 2.",
            "Pernas desdobráveis para pouso propulsivo do booster. Fase 2."),
     size="XS", mass_kg=600, cost_musd=2.0, attach={"radial": True}, src="game", phase=2)
part(id="grid_fins", category="future", model="grid_fins", name=L("Grid Fins", "Aletas em Grade"),
     desc=L("Steer the booster during re-entry. Phase 2.", "Guiam o booster na reentrada. Fase 2."),
     size="XS", mass_kg=150, cost_musd=1.0, attach={"radial": True}, src="game", phase=2)

# =================================================================== catalog expansion (v2)
# Everything below was added in the "more parts with specifications" pass. Existing ids above
# keep their values; new parts follow the same field conventions. `ref` names the real hardware
# a part is based on and REFERENCES lists the URLs. src: "ref" = published value, "approx" =
# rounded / sources vary, "game" = balance value in the real order of magnitude.
# Crewed parts carry an integer `crew_seats` (read by the crew system).
PROPELLANTS["lh2"] = {"name": {"en": "Liquid hydrogen (nuclear)", "pt": "Hidrogênio líquido (nuclear)"},
                      "density": 71, "density_src": "ref", "boiloff_pct_day": 1.5, "tank_dry_fraction": 0.180,
                      "color": "silver", "storable": False}
EXPANSION_IDS = []


def new(fn, *a, **kw):
    p = fn(*a, **kw)
    p["added"] = "v2"
    EXPANSION_IDS.append(p["id"])
    return p


# ------------------------------------------------------------------ v2 engines
_E = engine
new(_E, "eng_hidra_5", "engine_hydrolox_s", L("Hidra-5 (vacuum)", "Hidra-5 (vácuo)"),
    L("Compact expander-bleed hydrolox upper-stage engine. Deep throttling and many restarts.",
      "Motor hidrolox compacto de ciclo expansor (sangria) para estágio superior. Aceleração profunda e muitas reignições."),
    "hydrolox", "S", 0, 137, 0, 447, 285, 4, 0.6, 15, 2.5, 0.997,
    L("Based on JAXA/MHI LE-5B (137 kN vac, Isp ~447 s, ~285 kg; up to 16 starts)",
      "Baseado no LE-5B da JAXA/MHI (137 kN vácuo, Isp ~447 s, ~285 kg; até 16 partidas)"), "approx")
new(_E, "eng_hidra_j2", "engine_hydrolox_j2", L("Hidra-100 (upper stage)", "Hidra-100 (estágio superior)"),
    L("Gas-generator hydrolox engine for heavy upper stages. Restartable once for trans-lunar injection.",
      "Motor hidrolox de gerador de gás para estágios superiores pesados. Reacende uma vez para a injeção translunar."),
    "hydrolox", "M", 486, 1033, 200, 421, 1788, 7, 0.8, 1, 9.0, 0.996,
    L("Based on Rocketdyne J-2 (486.2 kN SL / 1,033.1 kN vac, Isp 200/421 s, 1,788 kg)",
      "Baseado no J-2 da Rocketdyne (486,2 kN NM / 1.033,1 kN vácuo, Isp 200/421 s, 1.788 kg)"), "ref")
new(_E, "eng_hidra_68", "engine_hydrolox_rs68", L("Hidra-68 (booster)", "Hidra-68 (primeiro estágio)"),
    L("Simple, cheap gas-generator hydrolox booster engine with an ablative nozzle. Very high thrust.",
      "Motor hidrolox de primeiro estágio, simples e barato, de gerador de gás com bocal ablativo. Empuxo muito alto."),
    "hydrolox", "L", 3137, 3560, 362, 411, 6740, 6, 0.58, 0, 15.0, 0.995,
    L("Based on Aerojet Rocketdyne RS-68A (3,137 kN SL / 3,560 kN vac, Isp 362/411 s, ~6.7 t)",
      "Baseado no RS-68A da Aerojet Rocketdyne (3.137 kN NM / 3.560 kN vácuo, Isp 362/411 s, ~6,7 t)"), "ref")
new(_E, "eng_harpia", "engine_kerolox_dual", L("Harpia-2 (dual chamber)", "Harpia-2 (câmara dupla)"),
    L("Oxygen-rich staged-combustion kerolox engine: one turbopump feeding two gimballed chambers.",
      "Motor a querosene de combustão em estágios rica em oxigênio: uma turbobomba alimenta duas câmaras com gimbal."),
    "kerolox", "L", 3830, 4152, 311, 338, 5480, 8, 0.47, 0, 12.0, 0.996,
    L("Based on NPO Energomash RD-180 (3,830 kN SL / 4,152 kN vac, Isp 311/338 s, 5,480 kg)",
      "Baseado no RD-180 da NPO Energomash (3.830 kN NM / 4.152 kN vácuo, Isp 311/338 s, 5.480 kg)"), "ref")
new(_E, "eng_falcao_4v", "engine_kerolox_quad", L("Falcão-4V (four chambers, vacuum)", "Falcão-4V (quatro câmaras, vácuo)"),
    L("Staged-combustion kerolox upper-stage engine with four small gimballed chambers.",
      "Motor a querosene de combustão em estágios para estágio superior, com quatro pequenas câmaras com gimbal."),
    "kerolox", "S", 0, 294, 0, 359, 480, 8, 0.6, 2, 3.0, 0.995,
    L("Based on KBKhA RD-0124 (294.3 kN vac, Isp 359 s, 480 kg)",
      "Baseado no RD-0124 da KBKhA (294,3 kN vácuo, Isp 359 s, 480 kg)"), "ref")
new(_E, "eng_metano_v", "engine_methalox_vac", L("Metano-V (vacuum)", "Metano-V (vácuo)"),
    L("Full-flow methalox engine with a large fixed vacuum nozzle. Reusable upper stages.",
      "Motor metalox de fluxo total com bocal de vácuo grande e fixo. Estágios superiores reutilizáveis."),
    "methalox", "M", 0, 2500, 0, 378, 1800, 0, 0.4, 10, 3.0, 0.992,
    L("Inspired by SpaceX Raptor Vacuum (public figures vary: ~2.5 MN, Isp ~378-380 s; mass approx.)",
      "Inspirado no Raptor Vacuum da SpaceX (números públicos variam: ~2,5 MN, Isp ~378-380 s; massa aprox.)"), "approx")
new(_E, "eng_apogee_490n", "engine_apogee", L("Apogee Thruster 490 N", "Propulsor de Apogeu 490 N"),
    L("Bipropellant spacecraft main engine for orbit insertion. Radiatively cooled niobium nozzle.",
      "Motor bipropelente principal de espaçonave para inserção orbital. Bocal de nióbio resfriado por radiação."),
    "hypergolic", "XS", 0, 0.49, 0, 312, 3.6, 0, 1.0, 999, 0.8, 0.999,
    L("Based on Aerojet R-4D-11 (490 N, Isp 312 s, 3.63 kg)",
      "Baseado no R-4D-11 da Aerojet (490 N, Isp 312 s, 3,63 kg)"), "ref")
new(_E, "eng_descent", "engine_descent", L("Descent Engine DE-45 (throttleable)", "Motor de Descida DE-45 (acelerável)"),
    L("Pressure-fed hypergolic lander engine that throttles down to 10% for a soft touchdown.",
      "Motor hipergólico de pouso alimentado por pressão que reduz até 10% para um toque suave."),
    "hypergolic", "S", 0, 45, 0, 311, 179, 6, 0.10, 20, 4.0, 0.997,
    L("Based on the Apollo LM Descent Propulsion System (45.04 kN, Isp 311 s, 179 kg, 10-100% throttle)",
      "Baseado no Sistema de Propulsão de Descida do LM Apollo (45,04 kN, Isp 311 s, 179 kg, 10-100%)"), "ref")
new(_E, "eng_mono_lander", "thruster_mono_lander", L("Throttleable Monoprop 3 kN", "Monopropelente Acelerável 3 kN"),
    L("Large throttleable hydrazine thruster. Cluster 8 on a sky-crane or lander descent stage.",
      "Propulsor grande de hidrazina, acelerável. Use 8 em um guindaste aéreo ou estágio de descida."),
    "hydrazine", "XS", 0, 3.1, 0, 225, 8.0, 0, 0.1, 999, 0.9, 0.998,
    L("Inspired by Aerojet MR-80B (MSL / Mars 2020 descent stage, ~3.1 kN, Isp ~225 s; mass approx.)",
      "Inspirado no MR-80B da Aerojet (estágio de descida MSL / Mars 2020, ~3,1 kN, Isp ~225 s; massa aprox.)"), "approx")
new(_E, "eng_hall_s", "thruster_hall_s", L("Hall Thruster HT-100", "Propulsor Hall HT-100"),
    L("Stationary plasma (Hall-effect) thruster. Higher thrust per watt than a gridded ion engine, lower Isp.",
      "Propulsor de plasma estacionário (efeito Hall). Mais empuxo por watt que o iônico de grades, Isp menor."),
    "xenon", "XS", 0, 0.00008, 0, 1600, 12, 0, 0.5, 9999, 1.5, 0.997,
    L("Based on OKB Fakel SPT-100 (80 mN, Isp 1,600 s, 1.35 kW); mass incl. PPU is a game value",
      "Baseado no SPT-100 da OKB Fakel (80 mN, Isp 1.600 s, 1,35 kW); massa com PPU é valor de jogo"), "ref",
    power_w=1350)
new(_E, "eng_hall_l", "thruster_hall_l", L("Hall Thruster HT-12k", "Propulsor Hall HT-12k"),
    L("High-power magnetically shielded Hall thruster for cargo tugs and lunar gateways. Needs 12.5 kW.",
      "Propulsor Hall de alta potência com blindagem magnética, para rebocadores e estações lunares. Precisa de 12,5 kW."),
    "xenon", "XS", 0, 0.0006, 0, 2800, 100, 0, 0.5, 9999, 12.0, 0.995,
    L("Based on NASA/Aerojet AEPS (600 mN, Isp ~2,800 s, 12.5 kW, ~100 kg per string)",
      "Baseado no AEPS da NASA/Aerojet (600 mN, Isp ~2.800 s, 12,5 kW, ~100 kg por conjunto)"), "approx",
    power_w=12500)
new(_E, "eng_kick_48", "kick_motor", L("Kick Motor KM-48 (solid)", "Motor de Chute KM-48 (sólido)"),
    L("Spin-stabilized solid upper stage that stacks under a spacecraft for the final escape burn.",
      "Estágio superior sólido estabilizado por rotação, empilhado sob a espaçonave para a queima final de escape."),
    "solid", "S", 0, 68.6, 0, 292, 131, 0, 1.0, 0, 4.0, 0.997,
    L("Based on Northrop Grumman Star 48B (2,011 kg propellant, 2,141 kg total, Isp 292.1 s, ~84 s burn)",
      "Baseado no Star 48B da Northrop Grumman (2.011 kg de propelente, 2.141 kg total, Isp 292,1 s, ~84 s)"), "ref",
    attach={"top": "S", "bottom": "S", "radial": False}, prop_mass_kg=2011, length_m=2.03)
new(_E, "eng_kick_37", "kick_motor", L("Kick Motor KM-37 (solid)", "Motor de Chute KM-37 (sólido)"),
    L("Smaller solid kick motor for apogee and escape burns of small spacecraft.",
      "Motor de chute sólido menor para queimas de apogeu e de escape de espaçonaves pequenas."),
    "solid", "XS", 0, 47.3, 0, 290, 82, 0, 1.0, 0, 2.5, 0.997,
    L("Based on Northrop Grumman Star 37FM (~1,066 kg propellant, Isp ~290 s; approx.)",
      "Baseado no Star 37FM da Northrop Grumman (~1.066 kg de propelente, Isp ~290 s; aprox.)"), "approx",
    attach={"top": "XS", "bottom": "XS", "radial": False}, prop_mass_kg=1066, length_m=1.69)
new(_E, "eng_sep_motor", "sep_motor", L("Separation Motor (solid)", "Motor de Separação (sólido)"),
    L("Tiny one-second solid motor that pushes a spent booster away (or settles propellant as an ullage motor).",
      "Motor sólido minúsculo de um segundo que afasta um booster gasto (ou assenta o propelente, como motor de ulagem)."),
    "solid", "XS", 98, 102, 236, 250, 42, 0, 1.0, 0, 0.15, 0.999,
    L("Inspired by the Space Shuttle booster separation motor (~98 kN for ~1 s; values approx.)",
      "Inspirado no motor de separação do booster do Space Shuttle (~98 kN por ~1 s; valores aprox.)"), "approx",
    prop_mass_kg=34, length_m=0.8)
new(_E, "eng_aerospike", "engine_aerospike", L("Aerospike AS-9 (altitude compensating)", "Aerospike AS-9 (compensa a altitude)"),
    L("Plug-nozzle hydrolox engine: the open exhaust adapts to air pressure, so Isp stays high from sea level to vacuum. Phase 2.",
      "Motor hidrolox de bocal tampão: o jato aberto se adapta à pressão do ar e o Isp fica alto do nível do mar ao vácuo. Fase 2."),
    "hydrolox", "M", 909, 1184, 339, 439, 3200, 0, 0.6, 3, 25.0, 0.990,
    L("Based on Rocketdyne XRS-2200 linear aerospike (909 kN SL / 1,184 kN vac, Isp 339/439 s); annular shape and mass are game values",
      "Baseado no aerospike linear XRS-2200 da Rocketdyne (909 kN NM / 1.184 kN vácuo, Isp 339/439 s); forma anular e massa são valores de jogo"),
    "approx", phase=2, steering="differential_throttle")
new(_E, "eng_ntr", "engine_ntr", L("Nuclear Thermal NT-75 (vacuum)", "Térmico Nuclear NT-75 (vácuo)"),
    L("A fission reactor heats pure hydrogen to ~2,500 K: twice the Isp of chemical engines, but heavy and vacuum-only. Phase 2, flagged.",
      "Um reator de fissão aquece hidrogênio puro a ~2.500 K: o dobro do Isp dos motores químicos, mas pesado e só no vácuo. Fase 2, sinalizado."),
    "lh2", "M", 0, 73, 0, 900, 2500, 4, 0.6, 10, 120.0, 0.985,
    L("Based on the Los Alamos Small Nuclear Rocket Engine study (~16.4-16.7 klbf / 73 kN, Isp ~875-900 s, T/W ~3)",
      "Baseado no estudo Small Nuclear Rocket Engine de Los Alamos (~16,4-16,7 klbf / 73 kN, Isp ~875-900 s, T/P ~3)"),
    "approx", phase=2, nuclear=True,
    flag=L("Nuclear: start the reactor only in a high, disposal-safe orbit (above ~800 km).",
           "Nuclear: ligue o reator só em órbita alta e segura para descarte (acima de ~800 km)."))

# ------------------------------------------------------------------ v2 tanks
for prop, ln in (("kerolox", 1.0), ("kerolox", 2.0), ("methalox", 2.0), ("hydrolox", 2.0)):
    vol, mp, md = tank_values(prop, SIZE_CLASSES["XS"], ln)
    pname = PROPELLANTS[prop]["name"]
    new(part, id=f"tank_{prop}_xs{int(ln)}", category="tank", model=f"tank_{prop}",
        name=L(f"{pname['en']} Tank XS-{int(ln)}m", f"Tanque {pname['pt']} XS-{int(ln)}m"),
        desc=L(f"Stackable {SIZE_CLASSES['XS']} m tank, {ln:.0f} m long. Sounding rockets, kick stages, landers.",
               f"Tanque empilhável de {SIZE_CLASSES['XS']} m, {ln:.0f} m de comprimento. Foguetes de sondagem, "
               f"estágios de chute, módulos de pouso."),
        size="XS", length_m=ln, propellant=prop, volume_m3=round(vol, 3), prop_mass_kg=round(mp), mass_kg=round(md),
        cost_musd=round(0.15 + TANK_COST_PER_T[prop] * mp / 1000 * 10, 2),
        attach={"top": "XS", "bottom": "XS", "radial": True}, src="derived", family=f"tank_{prop}")
for sz, ln in (("M", 8.0), ("L", 8.0)):
    vol, mp, md = tank_values("lh2", SIZE_CLASSES[sz], ln)
    new(part, id=f"tank_lh2_{sz.lower()}{int(ln)}", category="tank", model="tank_lh2",
        name=L(f"Liquid Hydrogen Tank {sz}-{int(ln)}m", f"Tanque de Hidrogênio Líquido {sz}-{int(ln)}m"),
        desc=L("Foil-wrapped, heavily insulated pure-LH2 tank for nuclear thermal engines. No oxidizer.",
               "Tanque de LH2 puro, envolto em isolamento metalizado, para motores térmicos nucleares. Sem oxidante."),
        size=sz, length_m=ln, propellant="lh2", volume_m3=round(vol, 2), prop_mass_kg=round(mp), mass_kg=round(md),
        cost_musd=round(0.3 + 0.05 * mp / 1000 * 10, 2), attach={"top": sz, "bottom": sz, "radial": True},
        ref=L("LH2 density 70.8 kg/m3 at 20 K; dry fraction is a game value",
              "Densidade do LH2 70,8 kg/m3 a 20 K; fração seca é valor de jogo"), src="derived", family="tank_lh2",
        phase=2)
for pid, prop, d, nm in (("tank_hypergolic_14", "hypergolic", 1.4, L("Hypergolic Sphere 1.4 m", "Esfera Hipergólica 1,4 m")),
                         ("tank_hydrazine_12", "hydrazine", 1.2, L("Hydrazine Sphere 1.2 m", "Esfera de Hidrazina 1,2 m"))):
    vol = 4 / 3 * math.pi * (d / 2) ** 3 * 0.92
    mp = vol * PROPELLANTS[prop]["density"]
    new(part, id=pid, category="tank", model="tank_sphere", name=nm,
        desc=L("Large pressurized spacecraft tank for planetary orbiters. Storable: no boil-off.",
               "Tanque pressurizado grande para orbitadores planetários. Armazenável: sem evaporação."),
        size="XS", propellant=prop, volume_m3=round(vol, 3), prop_mass_kg=round(mp, 1),
        mass_kg=round(mp * PROPELLANTS[prop]["tank_dry_fraction"], 1), cost_musd=round(0.4 + mp / 1000 * 2, 2),
        attach={"top": "XS", "bottom": "XS", "radial": True}, src="derived", family=f"tank_{prop}")
_R, _r = 0.45, 0.17  # torus major / minor radius (m)
_vol = 2 * math.pi ** 2 * _R * _r ** 2 * 0.92
_mp = _vol * PROPELLANTS["hypergolic"]["density"]
new(part, id="tank_toroid_hyp", category="tank", model="tank_toroid",
    name=L("Toroidal Hypergolic Tank", "Tanque Toroidal Hipergólico"),
    desc=L("Doughnut tank that wraps around an engine nozzle: short stacks for landers and kick stages.",
           "Tanque em forma de rosca que envolve o bocal do motor: pilhas curtas para módulos de pouso e estágios."),
    size="S", propellant="hypergolic", volume_m3=round(_vol, 3), prop_mass_kg=round(_mp, 1),
    mass_kg=round(_mp * 0.10, 1), cost_musd=round(0.6 + _mp / 1000 * 2, 2),
    attach={"top": "S", "bottom": "S", "radial": True},
    ref=L("Torus volume 2*pi^2*R*r^2 (R 0.45 m, r 0.17 m, 92% fill); dry fraction 0.10 (game)",
          "Volume do toro 2*pi^2*R*r^2 (R 0,45 m, r 0,17 m, 92% cheio); fração seca 0,10 (jogo)"),
    src="derived", family="tank_hypergolic")
_d, _l = 0.8, 1.4
_vol = (math.pi * (_d / 2) ** 2 * (_l - _d) + 4 / 3 * math.pi * (_d / 2) ** 3) * 0.92
_mp = _vol * PROPELLANTS["xenon"]["density"]
new(part, id="tank_xenon_08", category="tank", model="tank_xenon",
    name=L("Xenon Tank 0.8 m (COPV)", "Tanque de Xenônio 0,8 m (COPV)"),
    desc=L("Carbon-overwrapped xenon bottle sized for asteroid-belt missions with electric propulsion.",
           "Garrafa de xenônio revestida de carbono, dimensionada para missões ao cinturão de asteroides com propulsão elétrica."),
    size="XS", propellant="xenon", volume_m3=round(_vol, 3), prop_mass_kg=round(_mp, 1),
    mass_kg=round(_mp * PROPELLANTS["xenon"]["tank_dry_fraction"], 1), cost_musd=round(0.4 + _mp / 1000 * 2, 2),
    attach={"top": "XS", "bottom": "XS", "radial": True},
    ref=L("Psyche carried ~1,085 kg of xenon; capsule volume x 1,600 kg/m3 (supercritical)",
          "A Psyche levou ~1.085 kg de xenônio; volume da cápsula x 1.600 kg/m3 (supercrítico)"),
    src="derived", family="tank_xenon")

# ------------------------------------------------------------------ v2 structure
new(part, id="decoupler_xs", category="structure", model="decoupler", name=L("Stack Decoupler XS", "Desacoplador de Pilha XS"),
    desc=L("Small pyrotechnic separation ring for sounding rockets and kick stages.",
           "Anel de separação pirotécnico pequeno para foguetes de sondagem e estágios de chute."),
    size="XS", mass_kg=10, cost_musd=0.1, reliability=0.999, attach={"top": "XS", "bottom": "XS", "radial": False},
    src="game", ejection_impulse_kns=0.2)
for sz, m, c, dia in (("S", 18, 0.6, 1194), ("M", 45, 1.0, 2624)):
    new(part, id=f"decoupler_clamp_{sz.lower()}", category="structure", model="clamp_band",
        name=L(f"Clamp-Band Separation System {sz}", f"Sistema de Separação por Cinta {sz}"),
        desc=L("Marman clamp band released by bolt cutters; springs push the spacecraft away gently (low shock).",
               "Cinta Marman liberada por cortadores de parafuso; molas afastam a espaçonave suavemente (baixo choque)."),
        size=sz, mass_kg=m, cost_musd=c, reliability=0.9995, attach={"top": sz, "bottom": sz, "radial": False},
        ejection_impulse_kns=round(m * 0.01, 2), separation_speed_ms=0.5,
        ref=L(f"Inspired by Beyond Gravity (RUAG) PAS {dia} clamp-band systems (mass approx.)",
              f"Inspirado nos sistemas de cinta PAS {dia} da Beyond Gravity (RUAG) (massa aprox.)"), src="approx")
new(part, id="interstage_s", category="structure", model="interstage", name=L("Interstage S", "Interestágio S"),
    desc=L("Hollow 1.25 m shell that covers a small vacuum engine nozzle.",
           "Casca oca de 1,25 m que cobre o bocal de um motor de vácuo pequeno."),
    size="S", length_m=2.0, mass_kg=120, cost_musd=0.3, attach={"top": "S", "bottom": "S", "radial": False}, src="game")
for a, b, m, h in (("XS", "S", 40, 0.8), ("S", "L", 350, 2.5)):
    new(part, id=f"adapter_{a.lower()}{b.lower()}", category="structure", model="adapter",
        name=L(f"Adapter {a}-{b}", f"Adaptador {a}-{b}"),
        desc=L("Conical adapter between two diameter classes.", "Adaptador cônico entre duas classes de diâmetro."),
        size=b, length_m=h, mass_kg=m, cost_musd=0.3, attach={"top": a, "bottom": b, "radial": False}, src="game")
new(part, id="adapter_rev_ms", category="structure", model="adapter_rev", name=L("Inverted Adapter M-S", "Adaptador Invertido M-S"),
    desc=L("Wider on top: carries a 2.5 m payload or fairing on a 1.25 m stage (\"hammerhead\").",
           "Mais largo em cima: leva uma carga ou coifa de 2,5 m sobre um estágio de 1,25 m (\"cabeça de martelo\")."),
    size="M", length_m=1.2, mass_kg=180, cost_musd=0.4, attach={"top": "M", "bottom": "S", "radial": False}, src="game")
new(part, id="truss_xs", category="structure", model="truss_xs", name=L("Girder Segment XS", "Segmento de Viga XS"),
    desc=L("2 m square lattice girder. Spaces out instruments, booms and radiators; also mounts radially.",
           "Viga treliçada quadrada de 2 m. Afasta instrumentos, hastes e radiadores; também encaixa radialmente."),
    size="XS", length_m=2.0, mass_kg=25, cost_musd=0.05, attach={"top": "XS", "bottom": "XS", "radial": True},
    src="game")
new(part, id="truss_m", category="structure", model="truss_m", name=L("Open Truss Adapter M", "Treliça Aberta M"),
    desc=L("Open octagonal truss between two 2.5 m stages: lighter than a shell, lets hot-staging exhaust escape.",
           "Treliça octogonal aberta entre dois estágios de 2,5 m: mais leve que uma casca e deixa sair o jato na separação a quente."),
    size="M", length_m=2.0, mass_kg=220, cost_musd=0.5, attach={"top": "M", "bottom": "M", "radial": False},
    ref=L("Like the open truss of Soyuz/R-7 hot staging", "Como a treliça aberta da separação a quente do Soyuz/R-7"),
    src="game")
new(part, id="strut_radial", category="structure", model="strut_radial", name=L("Radial Strut Beam", "Viga de Escora Radial"),
    desc=L("Stiff I-beam strut for side mounts and booster attach points.",
           "Escora rígida em perfil I para montagens laterais e pontos de fixação de boosters."),
    size="XS", mass_kg=8, cost_musd=0.02, attach={"top": None, "bottom": None, "radial": True}, src="game")
for sz, m, c, cls, ref in (
        ("XS", 60, 2.0, "probe_drogue", L("Small probe-and-drogue port (game values)", "Porta pequena sonda-cone (valores de jogo)")),
        ("S", 340, 8.0, "idss", L("Inspired by the NASA Docking System / IDSS (androgynous, 0.8 m passage; mass approx.)",
                                  "Inspirado no NASA Docking System / IDSS (andrógino, passagem de 0,8 m; massa aprox.)"))):
    new(part, id=f"docking_port_{sz.lower()}", category="structure", model="docking_port",
        name=L(f"Docking Port {sz}", f"Porta de Acoplamento {sz}"),
        desc=L("Joins two vessels in orbit and lets crew and cargo pass through. Phase 2.",
               "Une dois veículos em órbita e deixa passar tripulação e carga. Fase 2."),
        size=sz, mass_kg=m, power_w=50 if sz == "S" else 10, cost_musd=c, reliability=0.998,
        attach={"top": sz, "bottom": sz, "radial": False}, docking_class=cls, ref=ref,
        src="approx" if sz == "S" else "game", phase=2)
for sz, slots, m in (("L", 5, 900), ("M", 7, 450)):
    new(part, id=f"thrust_plate_{sz.lower()}{slots}", category="structure", model="thrust_plate",
        name=L(f"Thrust Plate {sz} x{slots}", f"Placa de Empuxo {sz} x{slots}"),
        desc=L(f"Engine mount with {slots} engine slots in a ring+center pattern.",
               f"Suporte de motores com {slots} posições (anel + centro)."),
        size=sz, mass_kg=m, cost_musd=0.4, engine_slots=slots, attach={"top": sz, "bottom": "engines", "radial": False},
        src="game")

# ------------------------------------------------------------------ v2 aero
for pid, sz, m, inner, cyl, nose, nm in (
        ("fairing_xs", "XS", 25, 0.5, 0.8, 1.0, L("Payload Fairing XS", "Coifa de Carga XS")),
        ("fairing_s_long", "S", 90, 1.1, 3.2, 1.9, L("Payload Fairing S (long)", "Coifa de Carga S (longa)")),
        ("fairing_m_long", "M", 750, 2.3, 7.0, 4.0, L("Payload Fairing M (long)", "Coifa de Carga M (longa)")),
        ("fairing_l_long", "L", 1900, 3.5, 10.0, 6.0, L("Payload Fairing L (long)", "Coifa de Carga L (longa)"))):
    new(part, id=pid, category="aero", model="fairing", name=nm,
        desc=L(f"Two-half composite fairing, {cyl:.1f} m cylinder + {nose:.1f} m ogive. Jettisoned above ~110 km.",
               f"Coifa de compósito em duas metades, cilindro de {cyl:.1f} m + ogiva de {nose:.1f} m. Descartada acima de ~110 km."),
        size=sz, mass_kg=m, cost_musd=round(m / 300, 2), inner_diameter_m=inner, cyl_length_m=cyl, nose_length_m=nose,
        attach={"top": None, "bottom": sz, "radial": False}, src="game")
for sz, m in (("XS", 6), ("L", 200)):
    new(part, id=f"nose_cone_{sz.lower()}", category="aero", model="nose_cone", name=L(f"Nose Cone {sz}", f"Ogiva {sz}"),
        desc=L("Reduces drag on boosters and sounding rockets.", "Reduz o arrasto de boosters e foguetes de sondagem."),
        size=sz, mass_kg=m, cost_musd=0.05, attach={"top": None, "bottom": sz, "radial": False}, src="game")
new(part, id="fin_large", category="aero", model="fin_large", name=L("Large Stabilizer Fin", "Aleta Estabilizadora Grande"),
    desc=L("Big trapezoidal fin for heavy unguided rockets. Lots of stability, lots of drag.",
           "Aleta trapezoidal grande para foguetes pesados sem guiagem. Muita estabilidade e muito arrasto."),
    size="XS", mass_kg=40, cost_musd=0.04, attach={"top": None, "bottom": None, "radial": True}, src="game")
new(part, id="fin_swept", category="aero", model="fin_swept", name=L("Swept Fin", "Aleta Enflechada"),
    desc=L("Clipped-delta fin with a swept trailing edge. Less drag at supersonic speed.",
           "Aleta delta truncada com bordo de fuga enflechado. Menos arrasto em velocidade supersônica."),
    size="XS", mass_kg=18, cost_musd=0.03, attach={"top": None, "bottom": None, "radial": True}, src="game")

# ------------------------------------------------------------------ v2 crew & command
for pid, nm, sz, top, m, pw, c, seats, days, ref, d in (
        ("capsule_1", L("Crew Capsule (1 seat)", "Cápsula Tripulada (1 lugar)"), "S", "XS", 1400, 250, 60, 1, 1.5,
         L("Inspired by Mercury (1 astronaut, ~1,355 kg in orbit, 1.89 m base; scaled to S)",
           "Inspirada na Mercury (1 astronauta, ~1.355 kg em órbita, base de 1,89 m; reduzida para S)"),
         L("Tiny conical capsule for one astronaut. Short suborbital or orbital flights only.",
           "Cápsula cônica minúscula para um astronauta. Só voos suborbitais ou orbitais curtos.")),
        ("capsule_2", L("Crew Capsule (2 seats)", "Cápsula Tripulada (2 lugares)"), "M", "S", 3200, 500, 150, 2, 14,
         L("Inspired by Gemini (2 crew, 3,850 kg with adapter, 2.3 m base, up to 14 days)",
           "Inspirada na Gemini (2 tripulantes, 3.850 kg com adaptador, base de 2,3 m, até 14 dias)"),
         L("Two-seat capsule with a docking nose. Long-duration orbital flights and rendezvous practice.",
           "Cápsula de dois lugares com nariz de acoplamento. Voos orbitais longos e treino de encontro orbital.")),
        ("capsule_4", L("Crew Capsule (4 seats)", "Cápsula Tripulada (4 lugares)"), "L", "S", 9500, 2000, 400, 4, 7,
         L("Inspired by Crew Dragon (4 crew, 3.7 m diameter, integrated abort motors; mass approx.)",
           "Inspirada na Crew Dragon (4 tripulantes, 3,7 m de diâmetro, motores de abortagem integrados; massa aprox.)"),
         L("Modern capsule with a hinged nose cap over the docking port and integrated abort thrusters.",
           "Cápsula moderna com tampa de nariz articulada sobre a porta de acoplamento e propulsores de abortagem integrados."))):
    new(part, id=pid, category="command", model=pid, name=nm, desc=d, size=sz, mass_kg=m, power_w=pw, cost_musd=c,
        reliability=0.995, attach={"top": top, "bottom": sz, "radial": False}, crew_seats=seats,
        life_support_days=days, heat_shield=True, ref=ref, src="approx", phase=2)
new(part, id="crew_cabin_m", category="future", model="crew_cabin", name=L("Crew Cabin M (4 seats)", "Cabine Tripulada M (4 lugares)"),
    desc=L("Pressurized passenger cabin without flight controls. Needs a capsule or core to fly. Phase 2.",
           "Cabine pressurizada de passageiros sem controles de voo. Precisa de uma cápsula ou núcleo. Fase 2."),
    size="M", length_m=2.6, mass_kg=2800, power_w=400, cost_musd=80, reliability=0.995,
    attach={"top": "M", "bottom": "M", "radial": False}, crew_seats=4, pressurized_m3=20, life_support_days=10,
    src="game", phase=2)
new(part, id="hab_inflatable", category="future", model="hab_inflatable",
    name=L("Inflatable Habitat (2 crew)", "Habitat Inflável (2 tripulantes)"),
    desc=L("Folded soft-goods module that expands in orbit to ~16 m3. Living space for long missions. Phase 2.",
           "Módulo de tecido dobrado que se expande em órbita para ~16 m3. Espaço habitável para missões longas. Fase 2."),
    size="M", length_m=4.0, mass_kg=1413, power_w=150, cost_musd=40, reliability=0.99,
    attach={"top": "M", "bottom": "M", "radial": False}, crew_seats=2, pressurized_m3=16,
    ref=L("Based on Bigelow BEAM on the ISS (1,413 kg, 16 m3 expanded, 4.0 m x 3.2 m); 2-crew rating is a game value",
          "Baseado no BEAM da Bigelow na ISS (1.413 kg, 16 m3 expandido, 4,0 m x 3,2 m); capacidade de 2 é valor de jogo"),
    src="ref", phase=2)
new(part, id="cupola", category="future", model="cupola", name=L("Observation Cupola", "Cúpula de Observação"),
    desc=L("Seven-window dome with shutters for robotic-arm work and Earth observation. Phase 2.",
           "Cúpula de sete janelas com persianas, para operar o braço robótico e observar a Terra. Fase 2."),
    size="M", mass_kg=1880, power_w=100, cost_musd=30, reliability=0.998,
    attach={"top": None, "bottom": "M", "radial": False}, crew_seats=1,
    ref=L("Based on the ISS Cupola (1,880 kg, 2.95 m wide, 1.5 m tall, 7 windows)",
          "Baseado na Cupola da ISS (1.880 kg, 2,95 m de largura, 1,5 m de altura, 7 janelas)"), src="ref", phase=2)
new(part, id="les_tower", category="future", model="les_tower", name=L("Launch Escape Tower", "Torre de Escape"),
    desc=L("Solid rocket tower that pulls the capsule away from a failing launcher. Jettisoned after max-Q. Phase 2.",
           "Torre com foguete sólido que arranca a cápsula de um lançador em falha. Descartada depois do Max-Q. Fase 2."),
    size="S", mass_kg=4200, cost_musd=6.0, reliability=0.995, attach={"top": None, "bottom": "S", "radial": False},
    abort_thrust_kn=650, abort_burn_s=4.0,
    ref=L("Based on the Apollo Launch Escape System (~650 kN for ~4 s, ~4.2 t)",
          "Baseado no Launch Escape System da Apollo (~650 kN por ~4 s, ~4,2 t)"), src="approx", phase=2)
for pid, nm, m, dia, alt, d in (
        ("parachute_drogue", L("Drogue Chute", "Paraquedas de Frenagem"), 40, 7.0, 7.0,
         L("Small radial drogue that stabilizes and slows a capsule before the mains open. Phase 2.",
           "Paraquedas radial pequeno que estabiliza e freia a cápsula antes dos principais. Fase 2.")),
        ("parachute_radial", L("Radial Main Chute", "Paraquedas Principal Radial"), 120, 35.0, 2.5,
         L("Side-mounted main parachute. Use 3 for a capsule (one can fail). Phase 2.",
           "Paraquedas principal lateral. Use 3 em uma cápsula (um pode falhar). Fase 2."))):
    new(part, id=pid, category="future", model=pid, name=nm, desc=d, size="XS", mass_kg=m, cost_musd=0.5,
        reliability=0.995, attach={"top": None, "bottom": None, "radial": True}, canopy_diameter_m=dia,
        deploy_alt_km=alt, ref=L("Orion drogues ~7 m, mains ~35 m (116 ft); masses are game values",
                                 "Frenagem da Orion ~7 m, principais ~35 m (116 pés); massas são valores de jogo"),
        src="approx", phase=2)
new(part, id="landing_leg_lander", category="future", model="landing_leg_lander", name=L("Lander Leg", "Perna de Módulo de Pouso"),
    desc=L("Crushable-honeycomb lander leg with a wide footpad for soft regolith. Use 4. Phase 2.",
           "Perna com colmeia amassável e sapata larga para regolito fofo. Use 4. Fase 2."),
    size="XS", mass_kg=60, cost_musd=0.8, reliability=0.998, attach={"top": None, "bottom": None, "radial": True},
    ref=L("Inspired by the Apollo LM landing gear (honeycomb struts, 0.94 m footpads)",
          "Inspirada no trem de pouso do LM Apollo (escoras de colmeia, sapatas de 0,94 m)"), src="approx", phase=2)
new(part, id="rover_wheel", category="future", model="rover_wheel", name=L("Rover Wheel", "Roda de Rover"),
    desc=L("Machined aluminium wheel with chevron grousers and a rocker mount. Use 6 for a rover. Phase 2.",
           "Roda de alumínio usinado com garras em V e suporte de balancim. Use 6 em um rover. Fase 2."),
    size="XS", mass_kg=25, power_w=20, cost_musd=0.6, reliability=0.995, attach={"top": None, "bottom": None, "radial": True},
    ref=L("Inspired by Curiosity / Perseverance wheels (0.5 m diameter, 0.4 m wide)",
          "Inspirada nas rodas de Curiosity / Perseverance (0,5 m de diâmetro, 0,4 m de largura)"), src="approx", phase=2)

# ------------------------------------------------------------------ v2 power
new(part, id="fuel_cell", category="power", model="fuel_cell", name=L("Fuel Cell 7 kW", "Célula a Combustível 7 kW"),
    desc=L("Hydrogen-oxygen fuel cell: steady power for crewed flights and drinkable water as a by-product.",
           "Célula a combustível de hidrogênio e oxigênio: energia constante para voos tripulados e água potável de subproduto."),
    size="XS", mass_kg=118, power_gen_w_1au=7000, power_gen_w=7000, power_source="fuel_cell",
    reactant_kg_per_kwh=0.36, cost_musd=6.0, reliability=0.995, attach={"radial": True},
    ref=L("Based on the Space Shuttle orbiter fuel cell (7 kW continuous, 12 kW peak, ~118 kg; approx.)",
          "Baseado na célula a combustível do orbitador do Space Shuttle (7 kW contínuos, 12 kW de pico, ~118 kg; aprox.)"),
    src="approx")
for pid, nm, area, wkg, cost, rel, ref, d in (
        ("solar_wing_l", L("Large Solar Wing", "Asa Solar Grande"), 6.8, 45, 6.0, 0.985,
         L("Triple-junction cells ~27-30% efficient", "Células de tripla junção ~27-30% de eficiência"),
         L("Four-panel rigid wing on a gimbal for GEO satellites and planetary orbiters.",
           "Asa rígida de quatro painéis com gimbal, para satélites GEO e orbitadores planetários.")),
        ("solar_ultraflex", L("Circular Fan Array", "Painel Solar Circular em Leque"), 3.6, 120, 4.0, 0.99,
         L("Inspired by Northrop Grumman UltraFlex (InSight, Cygnus): ~100-150 W/kg, 2.15 m fans on InSight",
           "Inspirado no UltraFlex da Northrop Grumman (InSight, Cygnus): ~100-150 W/kg, leques de 2,15 m na InSight"),
         L("Fan-folded circular blanket that opens like a paper fan. Very light per watt.",
           "Manta circular dobrada que abre como um leque. Muito leve por watt."))):
    p_bol = area * SOLAR_1AU * 0.28
    new(part, id=pid, category="power", model=pid, name=nm, desc=d, size="XS", area_m2=area,
        power_gen_w_1au=round(p_bol), mass_kg=round(p_bol / wkg, 1), specific_power_w_kg=wkg,
        cost_musd=cost, reliability=rel, attach={"radial": True}, ref=ref, src="approx")
new(part, id="battery_xs", category="power", model="battery", name=L("Battery Pack 100 Wh", "Bateria 100 Wh"),
    desc=L("CubeSat-class Li-ion pack.", "Pacote de íons de lítio da classe CubeSat."),
    size="XS", capacity_wh=100, mass_kg=round(100 / 120, 1), cost_musd=0.1, reliability=0.995,
    ref=L("Battery-level ~100-150 Wh/kg (approx.)", "Nível de bateria ~100-150 Wh/kg (aprox.)"), src="approx")
new(part, id="fission_reactor", category="power", model="fission_reactor",
    name=L("Fission Power Unit 10 kWe", "Unidade de Fissão 10 kWe"),
    desc=L("Small uranium reactor with Stirling converters and a conical radiator. Night-proof power on the Moon or Mars. Phase 2.",
           "Pequeno reator de urânio com conversores Stirling e radiador cônico. Energia mesmo à noite na Lua ou em Marte. Fase 2."),
    size="XS", mass_kg=1500, power_gen_w_1au=10000, power_gen_w=10000, power_source="fission",
    heat_reject_w=30000, cost_musd=150.0, reliability=0.995, attach={"top": None, "bottom": "XS", "radial": True},
    ref=L("Based on NASA Kilopower / KRUSTY (1-10 kWe designs; 10 kWe ~1.5 t, approx.)",
          "Baseado no Kilopower / KRUSTY da NASA (projetos de 1-10 kWe; 10 kWe ~1,5 t, aprox.)"), src="approx", phase=2)

# ------------------------------------------------------------------ v2 comms
new(part, id="antenna_relay", category="comms", model="antenna_helix", name=L("UHF Relay Antenna", "Antena de Retransmissão UHF"),
    desc=L("Quadrifilar helix for proximity links: relays data from landers and rovers to Earth.",
           "Hélice quadrifilar para enlaces de proximidade: retransmite dados de módulos de pouso e rovers para a Terra."),
    size="XS", mass_kg=5, power_w=18, rate_ref_mbps_moon=0.5, relay=True, relay_rate_mbps=2.0, cost_musd=2.5,
    reliability=0.995, attach={"radial": True},
    ref=L("Inspired by the JPL Electra UHF proximity radio (up to ~2 Mbps; mass approx.)",
          "Inspirada no rádio de proximidade UHF Electra do JPL (até ~2 Mbps; massa aprox.)"), src="approx")
new(part, id="antenna_optical", category="comms", model="optical_terminal", name=L("Laser Comm Terminal", "Terminal de Comunicação a Laser"),
    desc=L("22 cm gimballed telescope that sends data by laser: 10-100x a radio dish, but needs very precise pointing and clear skies at the ground station.",
           "Telescópio de 22 cm com gimbal que envia dados por laser: 10-100x uma antena de rádio, mas exige apontamento muito preciso e céu limpo na estação."),
    size="XS", mass_kg=30, power_w=90, rate_ref_mbps_moon=600, pointing_urad=1.0, cost_musd=25.0,
    reliability=0.985, attach={"radial": True},
    ref=L("Inspired by NASA DSOC on Psyche (22 cm aperture, up to 267 Mbps from ~0.2 AU) and LLCD (622 Mbps from the Moon)",
          "Inspirado no DSOC da NASA na Psyche (abertura de 22 cm, até 267 Mbps de ~0,2 UA) e no LLCD (622 Mbps da Lua)"),
    src="approx")

# ------------------------------------------------------------------ v2 thermal
new(part, id="radiator_deploy", category="thermal", model="radiator_deploy", name=L("Deployable Radiator", "Radiador Desdobrável"),
    desc=L("Three hinged panels with an ammonia loop. Unfolds after launch to dump the heat of big payloads.",
           "Três painéis articulados com circuito de amônia. Abre depois do lançamento para rejeitar o calor de cargas grandes."),
    size="XS", mass_kg=35, power_w=20, cost_musd=1.5, heat_reject_w=2000, reliability=0.99, attach={"radial": True},
    ref=L("~100-350 W/m2 rejected by spacecraft radiators near Earth (game values)",
          "~100-350 W/m2 rejeitados por radiadores perto da Terra (valores de jogo)"), src="game")
for sz, m, c in (("M", 450, 6.0), ("L", 900, 10.0)):
    new(part, id=f"heat_shield_{sz.lower()}", category="thermal", model="heat_shield",
        name=L(f"Ablative Heat Shield {sz}", f"Escudo Térmico Ablativo {sz}"),
        desc=L("PICA ablator tiles on a carbon carrier. Survives lunar-return re-entry (~11 km/s). Phase 2.",
               "Placas ablativas PICA sobre estrutura de carbono. Aguenta a reentrada vinda da Lua (~11 km/s). Fase 2."),
        size=sz, mass_kg=m, cost_musd=c, reliability=0.998, attach={"top": sz, "bottom": sz, "radial": False},
        max_entry_kms=11.0, ref=L("PICA / PICA-X ablators (Stardust, Crew Dragon); masses are game values",
                                  "Ablativos PICA / PICA-X (Stardust, Crew Dragon); massas são valores de jogo"),
        src="approx", phase=2)

# ------------------------------------------------------------------ v2 control
new(part, id="reaction_wheel_s", category="control", model="reaction_wheel_s", name=L("Micro Reaction Wheel", "Micro Roda de Reação"),
    desc=L("Single CubeSat wheel. Use three on orthogonal axes.", "Roda única para CubeSat. Use três em eixos ortogonais."),
    size="XS", mass_kg=0.25, power_w=1, cost_musd=0.05, reliability=0.99, momentum_nms=0.05, torque_nm=0.007,
    attach={"radial": True}, ref=L("Class of Blue Canyon RWP050 (0.05 Nms, ~0.24 kg)",
                                   "Classe da Blue Canyon RWP050 (0,05 Nms, ~0,24 kg)"), src="approx")
new(part, id="reaction_wheels_l", category="control", model="reaction_wheels_l", name=L("Heavy Reaction Wheel Set", "Conjunto Pesado de Rodas de Reação"),
    desc=L("Four large wheels in a pyramid: fine pointing for big telescopes and orbiters.",
           "Quatro rodas grandes em pirâmide: apontamento fino para grandes telescópios e orbitadores."),
    size="XS", mass_kg=52, power_w=100, cost_musd=6.0, reliability=0.99, momentum_nms=100, torque_nm=0.2,
    ref=L("Class of Honeywell HR16 (up to 100-150 Nms, ~0.2 Nm, ~12 kg each)",
          "Classe da Honeywell HR16 (até 100-150 Nms, ~0,2 Nm, ~12 kg cada)"), src="approx")
new(part, id="cmg", category="control", model="cmg", name=L("Control Moment Gyroscope", "Giroscópio de Momento de Controle"),
    desc=L("Gimballed flywheel with huge torque for space stations. No propellant, but very heavy.",
           "Volante com gimbal e torque enorme para estações espaciais. Sem propelente, mas muito pesado."),
    size="XS", mass_kg=272, power_w=150, cost_musd=15.0, reliability=0.98, momentum_nms=4760, torque_nm=258,
    attach={"radial": True}, ref=L("Based on the ISS double-gimbal CMG (4,760 Nms, 272 kg, 6,600 rpm)",
                                   "Baseado no CMG de gimbal duplo da ISS (4.760 Nms, 272 kg, 6.600 rpm)"), src="ref")
new(part, id="rcs_block_heavy", category="control", model="rcs_heavy", name=L("RCS Quad 22 N", "RCS Quádruplo 22 N"),
    desc=L("Four 22 N hydrazine thrusters on a pod for medium spacecraft and stage attitude control.",
           "Quatro propulsores de hidrazina de 22 N em um módulo, para espaçonaves médias e controle de atitude de estágios."),
    size="XS", mass_kg=3.5, cost_musd=0.8, propellant="hydrazine", thrust_vac_kn=0.088, isp_vac_s=232,
    attach={"radial": True}, ref=L("Based on Aerojet MR-106L (22 N, Isp ~232 s, 0.6 kg each)",
                                   "Baseado no MR-106L da Aerojet (22 N, Isp ~232 s, 0,6 kg cada)"), src="ref")
new(part, id="rcs_biprop", category="control", model="rcs_biprop", name=L("Bipropellant RCS Pod 400 N", "Módulo RCS Bipropelente 400 N"),
    desc=L("Four 400 N hypergolic thrusters for capsules and docking. Strong, fast and storable.",
           "Quatro propulsores hipergólicos de 400 N para cápsulas e acoplamento. Fortes, rápidos e armazenáveis."),
    size="XS", mass_kg=9, cost_musd=1.5, propellant="hypergolic", thrust_vac_kn=1.6, isp_vac_s=300,
    attach={"radial": True}, ref=L("Inspired by SpaceX Draco (400 N, Isp ~300 s)", "Inspirado no Draco da SpaceX (400 N, Isp ~300 s)"),
    src="approx")

# ------------------------------------------------------------------ v2 instruments
for pid, model, nm, m, p, data, c, caps, ref, src in (
        ("inst_mag_s", "magnetometer_s", L("Fluxgate Magnetometer (short boom)", "Magnetômetro Fluxgate (haste curta)"),
         1.2, 1, 0.05, 3, {"fields": 0.4},
         L("Class of CubeSat fluxgates on ~0.6 m booms", "Classe dos fluxgates de CubeSat em hastes de ~0,6 m"), "game"),
        ("inst_seismo", "seismometer", L("Seismometer + Wind Shield", "Sismômetro + Escudo de Vento"),
         30, 9, 0.3, 45, {"seismic": 0.9},
         L("Inspired by InSight SEIS (~30 kg with its wind and thermal shield; approx.)",
           "Inspirado no SEIS da InSight (~30 kg com escudo de vento e térmico; aprox.)"), "approx"),
        ("inst_mass_spec", "mass_spec", L("Mass Spectrometer Suite", "Conjunto de Espectrômetro de Massa"),
         40, 70, 0.5, 60, {"organics": 0.9, "composition": 0.5},
         L("Inspired by Curiosity SAM (40 kg; mass spectrometer, gas chromatograph, laser spectrometer)",
           "Inspirado no SAM do Curiosity (40 kg; espectrômetro de massa, cromatógrafo a gás e espectrômetro a laser)"), "approx"),
        ("inst_weather", "weather_station", L("Weather Station", "Estação Meteorológica"),
         5.5, 17, 0.05, 8, {"atmosphere": 0.8},
         L("Inspired by Perseverance MEDA (~5.5 kg: wind, pressure, humidity, dust, radiation)",
           "Inspirado no MEDA do Perseverance (~5,5 kg: vento, pressão, umidade, poeira, radiação)"), "approx"),
        ("inst_gpr", "gpr", L("Ground-Penetrating Radar", "Radar de Penetração no Solo"),
         3, 10, 0.2, 10, {"subsurface": 0.6},
         L("Inspired by Perseverance RIMFAX (~3 kg, 150-1,200 MHz, >10 m depth)",
           "Inspirado no RIMFAX do Perseverance (~3 kg, 150-1.200 MHz, >10 m de profundidade)"), "approx"),
        ("inst_src", "sample_capsule", L("Sample Return Capsule", "Cápsula de Retorno de Amostras"),
         46, 0, 0, 35, {"sample_return": 1.0},
         L("Based on the Stardust sample return capsule (45.7 kg, 0.81 m, PICA heat shield, 12.9 km/s entry)",
           "Baseado na cápsula de retorno da Stardust (45,7 kg, 0,81 m, escudo PICA, reentrada a 12,9 km/s)"), "ref")):
    surface = pid in ("inst_seismo", "inst_weather", "inst_gpr")
    desc = L("Science payload. Value depends on orbit, pointing and data actually downlinked.",
             "Carga científica. O valor depende da órbita, do apontamento e dos dados realmente baixados.")
    if pid == "inst_src":
        desc = L("Seals collected samples and brings them back through Earth re-entry by parachute. Science value is earned on landing.",
                 "Lacra as amostras coletadas e as traz de volta pela reentrada na Terra com paraquedas. O valor científico vem no pouso.")
    elif surface:
        desc = L("Surface science payload: only works on a lander or rover.",
                 "Carga científica de superfície: só funciona em módulo de pouso ou rover.")
    new(part, id=pid, category="instrument", model=model, name=nm, desc=desc, size="XS", mass_kg=m, power_w=p,
        data_gbit_day=data, cost_musd=c, capabilities=caps, reliability=0.990,
        attach={"top": None, "bottom": "XS", "radial": True} if pid == "inst_src" else {"radial": True},
        ref=ref, src=src, surface_only=surface)

# ------------------------------------------------------------------ Δv map (approx. public delta-v maps)
DELTA_V_MAP = [
    ("surface_earth", "leo", 9.4, L("Earth surface -> LEO (incl. ~1.5-2 km/s gravity/drag losses)",
                                    "Superfície da Terra -> LEO (inclui ~1,5-2 km/s de perdas)")),
    ("leo", "gto", 2.44, L("LEO -> Geostationary transfer orbit", "LEO -> órbita de transferência geoestacionária")),
    ("gto", "geo", 1.5, L("GTO -> GEO (circularization + plane change)", "GTO -> GEO (circularização + troca de plano)")),
    ("leo", "tli", 3.1, L("LEO -> Trans-lunar injection", "LEO -> injeção translunar")),
    ("tli", "llo", 0.9, L("Lunar orbit insertion (low lunar orbit)", "Inserção em órbita lunar baixa")),
    ("llo", "moon_surface", 1.7, L("Low lunar orbit -> lunar surface", "Órbita lunar baixa -> superfície")),
    ("leo", "tmi", 3.6, L("LEO -> Trans-Mars injection (window-dependent)", "LEO -> injeção trans-Marte (depende da janela)")),
    ("tmi", "mars_capture", 1.0, L("Mars capture into an elliptical orbit", "Captura em órbita elíptica de Marte")),
    ("mars_capture", "mars_low", 1.4, L("Elliptical -> low Mars orbit (or aerobraking)", "Elíptica -> órbita baixa de Marte (ou aerofrenagem)")),
    ("leo", "escape", 3.2, L("LEO -> Earth escape (C3 = 0)", "LEO -> escape da Terra (C3 = 0)")),
]

REFERENCES = [
    ("NASA Glenn — Ideal Rocket Equation", "https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/ideal-rocket-equation"),
    ("NASA Glenn — Specific Impulse", "https://www.grc.nasa.gov/www/BGH/specimp.html"),
    ("RL10 (Aerojet Rocketdyne) — overview", "https://en.wikipedia.org/wiki/RL10"),
    ("RS-25 — overview", "https://en.wikipedia.org/wiki/RS-25"),
    ("NEXT ion thruster — NASA TM (NTRS 20080012602)", "https://ntrs.nasa.gov/api/citations/20080012602/downloads/20080012602.pdf"),
    ("NEXT-C — overview", "https://en.wikipedia.org/wiki/NEXT_(ion_thruster)"),
    ("L3Harris (Aerojet) Monopropellant Rocket Engines spec sheet", "https://www.l3harris.com/sites/default/files/2025-10/l3harris-ar-monopropellant-rocket-engines.pdf"),
    ("Bruce Dunn — Liquid fuels bulk density table (NSS)", "https://nss.org/settlement/nasa/Nowicki/SPBI1LF.HTM"),
    ("Redwire Roll-Out Solar Array (ROSA)", "https://satnow.com/products/solar-panels/redwire-space/102-1191-roll-out-solar-array-rosa-"),
    ("High-temperature PV / array specific power (arXiv 2608.11113)", "https://arxiv.org/pdf/2608.11113"),
    ("Gravity loss — delta-v to LEO 9-10 km/s", "https://en.wikipedia.org/wiki/Gravity_loss"),
    ("Tsiolkovsky rocket equation", "https://en.wikipedia.org/wiki/Tsiolkovsky_rocket_equation"),
    ("NASA 3D Resources (reference models)", "https://nasa3d.arc.nasa.gov/"),
]
REFERENCES += [  # v2 expansion
    ("LE-5 (JAXA/MHI) — overview", "https://en.wikipedia.org/wiki/LE-5"),
    ("J-2 (Rocketdyne) — overview", "https://en.wikipedia.org/wiki/Rocketdyne_J-2"),
    ("RS-68 / RS-68A — overview", "https://en.wikipedia.org/wiki/RS-68"),
    ("RD-180 — overview", "https://en.wikipedia.org/wiki/RD-180"),
    ("RD-0124 — overview", "https://en.wikipedia.org/wiki/RD-0124"),
    ("SpaceX Raptor (incl. Raptor Vacuum) — overview", "https://en.wikipedia.org/wiki/SpaceX_Raptor"),
    ("R-4D bipropellant thruster — overview", "https://en.wikipedia.org/wiki/R-4D"),
    ("Apollo LM Descent Propulsion System", "https://en.wikipedia.org/wiki/Descent_propulsion_system"),
    ("L3Harris (Aerojet) monopropellant engines incl. MR-80B / MR-106L", "https://www.l3harris.com/sites/default/files/2025-10/l3harris-ar-monopropellant-rocket-engines.pdf"),
    ("SPT-100 Hall thruster (OKB Fakel) — overview", "https://en.wikipedia.org/wiki/SPT-100"),
    ("Advanced Electric Propulsion System (AEPS) — overview", "https://en.wikipedia.org/wiki/Advanced_Electric_Propulsion_System"),
    ("Star 48 solid motor family (Star 48B)", "https://en.wikipedia.org/wiki/Star_48"),
    ("Star 37 solid motor family", "https://en.wikipedia.org/wiki/Star_37"),
    ("Space Shuttle Solid Rocket Booster (separation motors)", "https://en.wikipedia.org/wiki/Space_Shuttle_Solid_Rocket_Booster"),
    ("XRS-2200 linear aerospike — overview", "https://en.wikipedia.org/wiki/XRS-2200"),
    ("NASA NTRS — Small Nuclear Rocket Engine (SNRE) performance (Borowski et al.)", "https://ntrs.nasa.gov/api/citations/20150004421/downloads/20150004421.pdf"),
    ("Liquid hydrogen — properties (density 70.8 kg/m3)", "https://en.wikipedia.org/wiki/Liquid_hydrogen"),
    ("Psyche spacecraft (xenon load, DSOC)", "https://en.wikipedia.org/wiki/Psyche_(spacecraft)"),
    ("Marman clamp band separation", "https://en.wikipedia.org/wiki/Marman_clamp"),
    ("NASA Docking System / International Docking System Standard", "https://en.wikipedia.org/wiki/NASA_Docking_System"),
    ("Project Mercury spacecraft", "https://en.wikipedia.org/wiki/Mercury_spacecraft"),
    ("Project Gemini spacecraft", "https://en.wikipedia.org/wiki/Gemini_spacecraft"),
    ("SpaceX Dragon 2 (Crew Dragon)", "https://en.wikipedia.org/wiki/SpaceX_Dragon_2"),
    ("Bigelow Expandable Activity Module (BEAM)", "https://en.wikipedia.org/wiki/Bigelow_Expandable_Activity_Module"),
    ("ISS Cupola", "https://en.wikipedia.org/wiki/Cupola_(ISS_module)"),
    ("Apollo Launch Escape System", "https://en.wikipedia.org/wiki/Launch_escape_system"),
    ("Orion parachute system (NASA)", "https://www.nasa.gov/humans-in-space/orion-spacecraft/"),
    ("Apollo Lunar Module landing gear", "https://en.wikipedia.org/wiki/Apollo_Lunar_Module"),
    ("Curiosity rover (wheels, SAM, REMS)", "https://en.wikipedia.org/wiki/Curiosity_(rover)"),
    ("Space Shuttle orbiter fuel cells", "https://en.wikipedia.org/wiki/Space_Shuttle_orbiter"),
    ("UltraFlex solar arrays (InSight)", "https://en.wikipedia.org/wiki/InSight"),
    ("Kilopower / KRUSTY fission reactor", "https://en.wikipedia.org/wiki/Kilopower"),
    ("Electra UHF proximity radio (JPL)", "https://en.wikipedia.org/wiki/Mars_Reconnaissance_Orbiter"),
    ("Deep Space Optical Communications (DSOC)", "https://www.jpl.nasa.gov/missions/deep-space-optical-communications-dsoc/"),
    ("Lunar Laser Communication Demonstration (LLCD)", "https://en.wikipedia.org/wiki/Lunar_Laser_Communication_Demonstration"),
    ("Control moment gyroscope (ISS CMG figures)", "https://en.wikipedia.org/wiki/Control_moment_gyroscope"),
    ("Reaction wheel — overview (HR16 class)", "https://en.wikipedia.org/wiki/Reaction_wheel"),
    ("SEIS seismometer (InSight)", "https://en.wikipedia.org/wiki/Seismic_Experiment_for_Interior_Structure"),
    ("Perseverance rover instruments (MEDA, RIMFAX)", "https://en.wikipedia.org/wiki/Perseverance_(rover)"),
    ("Stardust sample return capsule", "https://en.wikipedia.org/wiki/Stardust_(spacecraft)"),
    ("PICA heat shield material", "https://en.wikipedia.org/wiki/Phenolic-impregnated_carbon_ablator"),
]


def by_id():
    return {p["id"]: p for p in PARTS}


def export(path):
    data = {
        "version": 1,
        "g0": G0,
        "size_classes": SIZE_CLASSES,
        "propellants": PROPELLANTS,
        "categories": CATEGORIES,
        "parts": PARTS,
        "delta_v_map": [{"from": a, "to": b, "dv_kms": v, "label": lbl} for a, b, v, lbl in DELTA_V_MAP],
    }
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "data" / "parts.json"
    export(out)
    cats = {}
    for p in PARTS:
        cats[p["category"]] = cats.get(p["category"], 0) + 1
    print(f"{len(PARTS)} parts -> {out}")
    for k, v in cats.items():
        print(f"  {k:11s} {v}")
