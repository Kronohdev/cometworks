"""Hangar engineering readouts: per-stage mass, Δv (sea level / vacuum), TWR and burn time.

This is the reference implementation of the hangar math; the Godot version must
reproduce these numbers (use the EXAMPLES below as regression tests).

The EXAMPLES are buildable in the hangar part-for-part (tests/test_vessel_math.gd
assembles the same trees). A vessel is a list of stages in firing order (stage 1 = first to ignite).
Each stage lists the parts that belong to it (they are jettisoned when the stage
ends) and optional radial booster groups that fire with the stage and drop when
empty. Fairings marked jettison_at_stage are dropped when that stage ignites.
"""
import math

from parts_catalog import G0, by_id

P = by_id()


def _mass_and_prop(items):
    dry, prop = 0.0, 0.0
    for pid, n in items:
        p = P[pid]
        dry += p["mass_kg"] * n
        if p["category"] == "tank" or p.get("propellant") == "solid":
            prop += p.get("prop_mass_kg", 0.0) * n
    return dry, prop


def _engines(items):
    return [(P[pid], n) for pid, n in items if P[pid]["category"] == "engine"]


def _thrust_isp(engines, vacuum):
    """Total thrust (N) and combined Isp: Isp_eff = ΣF / Σ(F/Isp)."""
    f_tot, flow = 0.0, 0.0
    for e, n in engines:
        f = (e["thrust_vac_kn"] if vacuum else e["thrust_sl_kn"]) * 1000 * n
        isp = e["isp_vac_s"] if vacuum else e["isp_sl_s"]
        if f <= 0 or isp <= 0:
            continue
        f_tot += f
        flow += f / isp
    return f_tot, (f_tot / flow if flow else 0.0)


def analyze(vessel, payload_kg, dt=0.25):
    stages = vessel["stages"]
    results = []
    for mode_vacuum in (False, True):
        remaining = [dict(s) for s in stages]
        fairing_kg = sum(P[pid]["mass_kg"] * n for pid, n in vessel.get("fairing", []))
        fairing_drop = vessel.get("fairing_jettison_stage", 2)
        rows = []
        for i, st in enumerate(remaining):
            stage_no = i + 1
            if stage_no >= fairing_drop:
                fairing_kg = 0.0
            upper_mass = payload_kg + fairing_kg
            for later in remaining[i + 1:]:
                d, pr = _mass_and_prop(later["parts"])
                upper_mass += d + pr
                for grp in later.get("boosters", []):
                    gd, gp = _mass_and_prop(grp["parts"])
                    upper_mass += (gd + gp) * grp["count"]
            core_dry, core_prop = _mass_and_prop(st["parts"])
            core_eng = _engines(st["parts"])
            boosters = []
            for grp in st.get("boosters", []):
                gd, gp = _mass_and_prop(grp["parts"])
                ge = _engines(grp["parts"])
                boosters.append({"dry": gd * grp["count"], "prop": gp * grp["count"],
                                 "eng": [(e, n * grp["count"]) for e, n in ge]})
            vac = mode_vacuum or stage_no > 1
            m = upper_mass + core_dry + core_prop + sum(b["dry"] + b["prop"] for b in boosters)
            m0 = m
            f0 = _thrust_isp(core_eng + [x for b in boosters for x in b["eng"]], vac)[0]
            twr0 = f0 / (m0 * G0)
            dv, t = 0.0, 0.0
            while core_prop > 1e-6 or any(b["prop"] > 1e-6 for b in boosters):
                active = []
                if core_prop > 1e-6:
                    active.append(("core", core_eng))
                for b in boosters:
                    if b["prop"] > 1e-6:
                        active.append((b, b["eng"]))
                f_tot = 0.0
                for owner, eng in active:
                    f, isp = _thrust_isp(eng, vac)
                    if f <= 0:
                        continue
                    mdot = f / (isp * G0)
                    burn = mdot * dt
                    if owner == "core":
                        burn = min(burn, core_prop)
                        core_prop -= burn
                    else:
                        burn = min(burn, owner["prop"])
                        owner["prop"] -= burn
                    m -= burn
                    f_tot += f * (burn / (mdot * dt))
                if f_tot <= 0:
                    break
                dv += f_tot / m * dt
                t += dt
                for b in boosters:  # drop empty boosters immediately
                    if b["prop"] <= 1e-6 and b["dry"] > 0:
                        m -= b["dry"]
                        b["dry"] = 0.0
            rows.append({"stage": stage_no, "m0_t": m0 / 1000, "dv_ms": dv, "twr0": twr0, "burn_s": t})
        results.append(rows)
    asl, vacr = results
    out = []
    for a, v in zip(asl, vacr):
        out.append({**v, "dv_asl_ms": a["dv_ms"], "dv_vac_ms": v["dv_ms"], "twr_asl": a["twr0"]})
    ascent = (out[0]["dv_asl_ms"] + out[0]["dv_vac_ms"]) / 2 + sum(r["dv_vac_ms"] for r in out[1:])
    return {"stages": out, "ascent_dv_ms": ascent, "liftoff_mass_t": out[0]["m0_t"],
            "liftoff_twr": out[0]["twr_asl"]}


EXAMPLES = [
    {
        "id": "andorinha", "name": "Andorinha (small launcher)", "name_pt": "Andorinha (lançador pequeno)",
        "inspired": "Electron-class", "payload_kg": 300,
        "fairing": [("fairing_s", 1)], "fairing_jettison_stage": 2,
        "stages": [
            {"parts": [("tank_kerolox_s8", 1), ("thrust_plate_s9", 1), ("eng_kestrel", 9), ("decoupler_s", 1)]},
            {"parts": [("tank_kerolox_s2", 1), ("eng_kestrel_v", 1), ("avionics_core_s", 1)]},
        ],
    },
    {
        "id": "condor", "name": "Condor (medium launcher)", "name_pt": "Condor (lançador médio)",
        "inspired": "Falcon 9-class (expendable)", "payload_kg": 15000,
        "fairing": [], "fairing_jettison_stage": 2,
        "stages": [
            {"parts": [("tank_kerolox_l8", 5), ("thrust_plate_l9", 1), ("eng_falcao", 9),
                       ("interstage_l", 1), ("decoupler_l", 1)]},
            {"parts": [("tank_kerolox_l8", 1), ("tank_kerolox_l4", 1), ("eng_falcao_v", 1),
                       ("avionics_core_m", 1), ("adapter_ml", 1), ("payload_adapter", 1)]},
        ],
    },
    {
        "id": "garca", "name": "Garça (hydrolox + solid boosters)", "name_pt": "Garça (hidrolox + boosters sólidos)",
        "inspired": "Atlas V / Delta IV-class", "payload_kg": 9000,
        "fairing": [], "fairing_jettison_stage": 2,
        "stages": [
            {"parts": [("tank_hydrolox_l8", 4), ("eng_hidra_25", 1), ("adapter_ml", 1), ("decoupler_m", 1)],
             "boosters": [{"count": 2, "parts": [("eng_srb_m", 1), ("decoupler_radial", 1)]}]},
            {"parts": [("tank_hydrolox_m8", 1), ("tank_hydrolox_m4", 1), ("eng_hidra_rl", 1),
                       ("avionics_core_m", 1), ("payload_adapter", 1)]},
        ],
    },
]


def main():
    for ex in EXAMPLES:
        r = analyze(ex, ex["payload_kg"])
        print(f"\n{ex['name']}  payload={ex['payload_kg']} kg  liftoff={r['liftoff_mass_t']:.1f} t  "
              f"TWR={r['liftoff_twr']:.2f}  ascent Δv≈{r['ascent_dv_ms']:.0f} m/s")
        for s in r["stages"]:
            print(f"  S{s['stage']}: m0={s['m0_t']:8.1f} t  Δv asl={s['dv_asl_ms']:6.0f}  vac={s['dv_vac_ms']:6.0f} "
                  f"TWR={s['twr0']:.2f}  burn={s['burn_s']:.0f} s")


if __name__ == "__main__":
    main()
