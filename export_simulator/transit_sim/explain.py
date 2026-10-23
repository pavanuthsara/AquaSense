"""Plain-language explanation of a simulated shipment."""
from __future__ import annotations

from .config import Shipment, Species


def explain(summary: dict, species: Species, shipment: Shipment) -> str:
    s = summary
    lines = []
    surv = 100 * s["survival_at_arrival"]
    lines.append(f"Predicted survival at arrival: {surv:.1f}% "
                 f"({species.name}, {shipment.fish_count} fish x {shipment.fish_mass_g:g} g "
                 f"in {shipment.water_l:g} L, {shipment.density_g_per_l:.0f} g/L, {shipment.duration_h:g} h).")
    if s.get("survival_after_unpacking") is not None and s["survival_after_unpacking"] < s["survival_at_arrival"] - 1e-3:
        lines.append(f"After unpacking: {100 * s['survival_after_unpacking']:.1f}%.")
    share = s["stress_share"]
    driver = s["main_driver"]
    lines.append(f"Main cause of stress: {driver} ({100 * share[driver]:.0f}% of accumulated toxic load).")
    if s["hours_to_do_crit"] is not None:
        lines.append(f"Oxygen in the water falls below the critical {species.do_crit:g} mg/L after "
                     f"{s['hours_to_do_crit']:.1f} h.")
    else:
        lines.append(f"Oxygen stays above the critical level (lowest {s['min_do_mgL']:.1f} mg/L).")
    lines.append(f"CO2 peaks at {s['max_co2_mgL']:.0f} mg/L (above 20 mg/L reduces blood O2 transport); "
                 f"pH falls to {s['final_ph']:.2f}.")
    lines.append(f"Toxic NH3 during transit stays at or below {s['max_nh3_transit_mgL']:.3f} mg/L because the low pH "
                 f"keeps ammonia ionized.")
    if s.get("peak_nh3_unpacking_mgL") is not None:
        ratio = s["peak_nh3_unpacking_mgL"] / max(s["max_nh3_transit_mgL"], 1e-9)
        warn = " WARNING: above the 0.02 mg/L safe level - acclimate gradually / do not let bag water into the tank." \
            if s["peak_nh3_unpacking_mgL"] > 0.02 else ""
        lines.append(f"When the bag is opened, CO2 escapes and pH rises to {s['peak_ph_unpacking']:.2f}: NH3 jumps to "
                     f"{s['peak_nh3_unpacking_mgL']:.3f} mg/L ({ratio:.0f}x the transit level).{warn}")
    return "\n".join(lines)
