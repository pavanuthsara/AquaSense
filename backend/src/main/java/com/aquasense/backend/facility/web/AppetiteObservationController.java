package com.aquasense.backend.facility.web;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.AppetiteObservation;
import com.aquasense.backend.facility.model.AppetiteResult;
import com.aquasense.backend.facility.service.AppetiteObservationService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AppetiteObservationController {
    private final AppetiteObservationService service;

    public AppetiteObservationController(AppetiteObservationService service) {
        this.service = service;
    }

    @PostMapping("/api/v1/device-observations")
    @ResponseStatus(HttpStatus.CREATED)
    ObservationResponse ingest(
            @RequestHeader("X-Device-Id") UUID deviceId,
            @RequestHeader("X-Device-Token") String deviceToken,
            @Valid @RequestBody ObservationRequest request) {
        return ObservationResponse.from(service.ingest(
                deviceId,
                deviceToken,
                request.tankId(),
                request.detectedGuppyCount(),
                request.confidence(),
                request.appetiteResult(),
                request.modelVersion(),
                request.observedAt()));
    }

    @GetMapping("/api/v1/facilities/{facilityId}/tanks/{tankId}/appetite-observation")
    ObservationStateResponse latest(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId) {
        return service.latest(UUID.fromString(jwt.getSubject()), facilityId, tankId)
                .map(observation -> new ObservationStateResponse(true, ObservationResponse.from(observation)))
                .orElseGet(() -> new ObservationStateResponse(false, null));
    }

    public record ObservationRequest(
            @NotNull UUID tankId,
            @Min(0) @Max(1_000_000) int detectedGuppyCount,
            @NotNull @DecimalMin("0.0000") @DecimalMax("1.0000") @Digits(integer = 1, fraction = 4)
            BigDecimal confidence,
            @NotNull AppetiteResult appetiteResult,
            @NotBlank @Size(max = 120) String modelVersion,
            @NotNull Instant observedAt) {
    }

    public record ObservationStateResponse(boolean available, ObservationResponse observation) {
    }

    public record ObservationResponse(
            UUID id,
            UUID tankId,
            int detectedGuppyCount,
            BigDecimal confidence,
            AppetiteResult appetiteResult,
            String modelVersion,
            Instant observedAt,
            Instant receivedAt,
            boolean stale,
            boolean lowConfidence,
            boolean countInconsistent,
            boolean validForFeedingDecision,
            boolean ownerReviewRequired,
            List<String> reviewReasons) {
        static ObservationResponse from(AppetiteObservation observation) {
            List<String> reasons = new ArrayList<>();
            if (observation.isStale()) reasons.add("STALE");
            if (observation.isLowConfidence()) reasons.add("LOW_CONFIDENCE");
            if (observation.isCountInconsistent()) reasons.add("COUNT_INCONSISTENT");
            return new ObservationResponse(
                    observation.getId(),
                    observation.getTank().getId(),
                    observation.getDetectedGuppyCount(),
                    observation.getConfidence(),
                    observation.getAppetiteResult(),
                    observation.getModelVersion(),
                    observation.getObservedAt(),
                    observation.getReceivedAt(),
                    observation.isStale(),
                    observation.isLowConfidence(),
                    observation.isCountInconsistent(),
                    observation.isValidForFeedingDecision(),
                    !reasons.isEmpty(),
                    List.copyOf(reasons));
        }
    }
}
