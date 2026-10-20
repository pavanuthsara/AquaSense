package com.aquasense.backend.facility.web;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import com.aquasense.backend.facility.model.FeederCalibration;
import com.aquasense.backend.facility.service.FeederCalibrationService;
import com.aquasense.backend.facility.service.FeederCalibrationService.PortionPreview;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotNull;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@Validated
@RestController
@RequestMapping("/api/v1/facilities/{facilityId}")
public class FeederCalibrationController {
    private final FeederCalibrationService service;

    public FeederCalibrationController(FeederCalibrationService service) {
        this.service = service;
    }

    @GetMapping("/feeder-calibration")
    CalibrationStateResponse get(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId) {
        return service.getActive(userId(jwt), facilityId)
                .map(calibration -> new CalibrationStateResponse(true, CalibrationResponse.from(calibration)))
                .orElseGet(() -> new CalibrationStateResponse(false, null));
    }

    @PostMapping("/feeder-calibration")
    @ResponseStatus(HttpStatus.CREATED)
    CalibrationResponse create(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @Valid @RequestBody CalibrationRequest request) {
        return CalibrationResponse.from(service.createVersion(
                userId(jwt),
                facilityId,
                request.unitsPerFish(),
                request.minimumUnits(),
                request.maximumUnits()));
    }

    @GetMapping("/tanks/{tankId}/portion-preview")
    PortionPreviewResponse preview(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId,
            @RequestParam(required = false) Integer fishCount) {
        return PortionPreviewResponse.from(service.preview(userId(jwt), facilityId, tankId, fishCount));
    }

    private UUID userId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }

    public record CalibrationRequest(
            @NotNull @DecimalMin("0.0001") @Digits(integer = 8, fraction = 4) BigDecimal unitsPerFish,
            @NotNull @DecimalMin("0.0001") @Digits(integer = 8, fraction = 4) BigDecimal minimumUnits,
            @NotNull @DecimalMin("0.0001") @Digits(integer = 8, fraction = 4) BigDecimal maximumUnits) {
    }

    public record CalibrationStateResponse(boolean configured, CalibrationResponse calibration) {
    }

    public record CalibrationResponse(
            UUID id,
            int version,
            BigDecimal unitsPerFish,
            BigDecimal minimumUnits,
            BigDecimal maximumUnits,
            Instant createdAt) {
        static CalibrationResponse from(FeederCalibration calibration) {
            return new CalibrationResponse(
                    calibration.getId(),
                    calibration.getVersion(),
                    calibration.getUnitsPerFish(),
                    calibration.getMinimumUnits(),
                    calibration.getMaximumUnits(),
                    calibration.getCreatedAt());
        }
    }

    public record PortionPreviewResponse(
            boolean configured,
            int fishCount,
            CalibrationResponse calibration,
            BigDecimal rawUnits,
            BigDecimal portionUnits,
            String limitedBy) {
        static PortionPreviewResponse from(PortionPreview preview) {
            return new PortionPreviewResponse(
                    preview.calibration() != null,
                    preview.fishCount(),
                    preview.calibration() == null ? null : CalibrationResponse.from(preview.calibration()),
                    preview.rawUnits(),
                    preview.portionUnits(),
                    preview.limitedBy());
        }
    }
}
