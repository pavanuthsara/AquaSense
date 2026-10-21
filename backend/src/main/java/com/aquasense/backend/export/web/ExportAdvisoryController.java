package com.aquasense.backend.export.web;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.export.model.ExportAdvisory;
import com.aquasense.backend.export.service.ExportAdvisoryService;
import com.aquasense.backend.export.service.ExportAdvisoryService.AdvisoryInput;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Export shipment planning (AquaSense component 4).
 *
 * <p>POST runs the transit simulator and stores the advisory: packing plan, chemicals and doses, oxygen
 * use over time, survival timeline, water chemistry, temperature limits and unpacking advice.
 */
@RestController
@RequestMapping("/api/v1/facilities/{facilityId}/export-advisories")
public class ExportAdvisoryController {
    private final ExportAdvisoryService service;

    public ExportAdvisoryController(ExportAdvisoryService service) {
        this.service = service;
    }

    @PostMapping
    ResponseEntity<String> create(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @Valid @RequestBody AdvisoryRequest request) {
        ExportAdvisory advisory = service.create(userId(jwt), facilityId, request.toInput());
        return ResponseEntity.status(HttpStatus.CREATED)
                .contentType(MediaType.APPLICATION_JSON)
                .body(detailJson(advisory));
    }

    @GetMapping
    List<AdvisorySummary> list(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId) {
        return service.list(userId(jwt), facilityId).stream()
                .map(AdvisorySummary::from)
                .toList();
    }

    @GetMapping("/{advisoryId}")
    ResponseEntity<String> get(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID advisoryId) {
        ExportAdvisory advisory = service.get(userId(jwt), facilityId, advisoryId);
        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .body(detailJson(advisory));
    }

    private UUID userId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }

    /** The stored request and advisory are already JSON; wrap them without re-parsing. */
    static String detailJson(ExportAdvisory advisory) {
        return "{\"id\":\"" + advisory.getId() + "\""
                + ",\"facilityId\":\"" + advisory.getFacilityId() + "\""
                + ",\"label\":" + jsonString(advisory.getLabel())
                + ",\"createdAt\":\"" + advisory.getCreatedAt() + "\""
                + ",\"request\":" + advisory.getRequestJson()
                + ",\"advisory\":" + advisory.getAdvisoryJson()
                + "}";
    }

    static String jsonString(String value) {
        if (value == null) {
            return "null";
        }
        StringBuilder out = new StringBuilder("\"");
        for (char c : value.toCharArray()) {
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> {
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
                }
            }
        }
        return out.append('"').toString();
    }

    public record AdvisoryRequest(
            @Size(max = 120) String label,
            @NotBlank @Pattern(regexp = "[a-z_]{1,40}") String species,
            @NotNull @DecimalMin(value = "0.01") @DecimalMax("500") Double fishMassG,
            @Min(1) @Max(10_000_000) Integer totalFish,
            @NotNull @DecimalMin(value = "0.05") @DecimalMax("50") Double waterL,
            @NotNull @DecimalMin(value = "0.05") @DecimalMax("100") Double gasL,
            @NotNull @DecimalMin(value = "1") @DecimalMax("120") Double durationH,
            @NotNull @DecimalMin("0") @DecimalMax("40") Double tempLowC,
            @NotNull @DecimalMin("0") @DecimalMax("40") Double tempHighC,
            @DecimalMin("50") @DecimalMax("99.5") Double targetSurvivalPct,
            Boolean allowAnaesthetic,
            Boolean allowZeolite,
            @DecimalMin("0") @DecimalMax("96") Double maxFastingH) {

        AdvisoryInput toInput() {
            return new AdvisoryInput(
                    label,
                    species,
                    fishMassG,
                    totalFish,
                    waterL,
                    gasL,
                    durationH,
                    tempLowC,
                    tempHighC,
                    targetSurvivalPct == null ? 95.0 : targetSurvivalPct,
                    allowAnaesthetic == null || allowAnaesthetic,
                    allowZeolite == null || allowZeolite,
                    maxFastingH == null ? 48.0 : maxFastingH);
        }
    }

    public record AdvisorySummary(
            UUID id,
            String label,
            String species,
            double durationHours,
            boolean feasible,
            Integer fishPerBag,
            Integer bagsNeeded,
            Double survivalPct,
            Double worstSurvivalPct,
            Instant createdAt) {
        static AdvisorySummary from(ExportAdvisory advisory) {
            return new AdvisorySummary(
                    advisory.getId(),
                    advisory.getLabel(),
                    advisory.getSpecies(),
                    advisory.getDurationHours(),
                    advisory.isFeasible(),
                    advisory.getFishPerBag(),
                    advisory.getBagsNeeded(),
                    advisory.getSurvivalPct(),
                    advisory.getWorstSurvivalPct(),
                    advisory.getCreatedAt());
        }
    }
}
