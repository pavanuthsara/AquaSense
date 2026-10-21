package com.aquasense.backend.export.service;

import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import com.aquasense.backend.export.client.ExportSimulator;
import com.aquasense.backend.export.client.ExportSimulator.AdvisoryResult;
import com.aquasense.backend.export.client.ExportSimulatorException;
import com.aquasense.backend.export.model.ExportAdvisory;
import com.aquasense.backend.export.repository.ExportAdvisoryRepository;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.service.FacilityException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Plans export shipments with the transit simulator and keeps the resulting advisories per aquarium.
 * Any member of the aquarium (owner or worker) can plan and view shipments.
 */
@Service
public class ExportAdvisoryService {
    private final FacilityMembershipRepository memberships;
    private final ExportAdvisoryRepository advisories;
    private final ExportSimulator simulator;

    public ExportAdvisoryService(
            FacilityMembershipRepository memberships,
            ExportAdvisoryRepository advisories,
            ExportSimulator simulator) {
        this.memberships = memberships;
        this.advisories = advisories;
        this.simulator = simulator;
    }

    /** Not transactional on purpose: the simulator call takes seconds and must not hold a DB connection. */
    public ExportAdvisory create(UUID userId, UUID facilityId, AdvisoryInput input) {
        requireMembership(userId, facilityId);
        if (input.tempHighC() < input.tempLowC()) {
            throw new FacilityException(
                    HttpStatus.BAD_REQUEST,
                    "invalid_temperature_range",
                    "The highest temperature must not be lower than the lowest temperature");
        }
        String requestJson = input.toSimulatorJson();
        AdvisoryResult result;
        try {
            result = simulator.advise(requestJson);
        } catch (ExportSimulatorException exception) {
            if (exception.isInvalidInput()) {
                throw new FacilityException(HttpStatus.BAD_REQUEST, "invalid_shipment", exception.getMessage());
            }
            throw new FacilityException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "export_simulator_unavailable",
                    "The transit simulator is not available right now. Try again shortly.");
        }
        return advisories.save(new ExportAdvisory(
                facilityId,
                userId,
                cleanLabel(input.label()),
                input.species(),
                input.durationH(),
                result.feasible(),
                result.fishPerBag(),
                result.bagsNeeded(),
                result.survivalPct(),
                result.worstSurvivalPct(),
                requestJson,
                result.json(),
                Instant.now()));
    }

    @Transactional(readOnly = true)
    public List<ExportAdvisory> list(UUID userId, UUID facilityId) {
        requireMembership(userId, facilityId);
        return advisories.findTop50ByFacilityIdOrderByCreatedAtDesc(facilityId);
    }

    @Transactional(readOnly = true)
    public ExportAdvisory get(UUID userId, UUID facilityId, UUID advisoryId) {
        requireMembership(userId, facilityId);
        return advisories.findByIdAndFacilityId(advisoryId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND,
                        "export_advisory_not_found",
                        "The shipment plan was not found"));
    }

    private void requireMembership(UUID userId, UUID facilityId) {
        memberships.findByUser_IdAndFacility_Id(userId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND,
                        "facility_not_found",
                        "The aquarium was not found or is not accessible"));
    }

    private static String cleanLabel(String label) {
        if (label == null) {
            return null;
        }
        String trimmed = label.trim().replaceAll("\\s+", " ");
        return trimmed.isEmpty() ? null : trimmed;
    }

    /** Validated shipment details, in the units the exporter enters them. */
    public record AdvisoryInput(
            String label,
            String species,
            double fishMassG,
            Integer totalFish,
            double waterL,
            double gasL,
            double durationH,
            double tempLowC,
            double tempHighC,
            double targetSurvivalPct,
            boolean allowAnaesthetic,
            boolean allowZeolite,
            double maxFastingH) {

        /** JSON for the Python simulator. Only numbers, booleans and a pattern-validated species key. */
        String toSimulatorJson() {
            StringBuilder json = new StringBuilder("{");
            json.append("\"species\":\"").append(species).append('"');
            json.append(",\"fish_mass_g\":").append(number(fishMassG));
            json.append(",\"total_fish\":").append(totalFish == null ? "null" : totalFish.toString());
            json.append(",\"water_l\":").append(number(waterL));
            json.append(",\"gas_l\":").append(number(gasL));
            json.append(",\"duration_h\":").append(number(durationH));
            json.append(",\"temp_low_c\":").append(number(tempLowC));
            json.append(",\"temp_high_c\":").append(number(tempHighC));
            json.append(",\"target_survival\":").append(number(targetSurvivalPct / 100.0));
            json.append(",\"allow_anaesthetic\":").append(allowAnaesthetic);
            json.append(",\"allow_zeolite\":").append(allowZeolite);
            json.append(",\"max_fasting_h\":").append(number(maxFastingH));
            return json.append('}').toString();
        }

        private static String number(double value) {
            return String.format(Locale.ROOT, "%.6f", value);
        }
    }
}
