package com.aquasense.backend.export.client;

/**
 * The transit simulator. Takes the advisory request as JSON (snake_case, see AdvisoryIn in
 * export_simulator/transit_sim/api.py) and returns the advisory JSON unchanged, plus the headline
 * numbers the simulator also sends as X-Advisory-* headers (so the backend never has to parse the JSON).
 */
public interface ExportSimulator {
    AdvisoryResult advise(String requestJson);

    record AdvisoryResult(
            String json,
            boolean feasible,
            Integer fishPerBag,
            Integer bagsNeeded,
            Double survivalPct,
            Double worstSurvivalPct) {
    }
}
