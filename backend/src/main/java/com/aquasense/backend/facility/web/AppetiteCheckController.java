package com.aquasense.backend.facility.web;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import com.aquasense.backend.facility.model.*;
import com.aquasense.backend.facility.service.AppetiteCheckService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
public class AppetiteCheckController {
    private final AppetiteCheckService service;
    public AppetiteCheckController(AppetiteCheckService service) { this.service = service; }

    @PostMapping("/api/v1/facilities/{facilityId}/tanks/{tankId}/appetite-checks")
    @ResponseStatus(HttpStatus.ACCEPTED)
    CheckResponse request(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID facilityId, @PathVariable UUID tankId) {
        return CheckResponse.from(service.request(UUID.fromString(jwt.getSubject()), facilityId, tankId));
    }

    @GetMapping("/api/v1/facilities/{facilityId}/tanks/{tankId}/appetite-checks/{checkId}")
    CheckResponse get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID facilityId,
            @PathVariable UUID tankId, @PathVariable UUID checkId) {
        return CheckResponse.from(service.get(UUID.fromString(jwt.getSubject()), facilityId, tankId, checkId));
    }

    @GetMapping("/api/v1/device-appetite-checks/next")
    ResponseEntity<CheckResponse> next(@RequestHeader("X-Device-Id") UUID deviceId,
            @RequestHeader("X-Device-Token") String token) {
        return service.next(deviceId, token).map(item -> ResponseEntity.ok(CheckResponse.from(item)))
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    @PostMapping("/api/v1/device-appetite-checks/{checkId}/result")
    CheckResponse result(@RequestHeader("X-Device-Id") UUID deviceId,
            @RequestHeader("X-Device-Token") String token, @PathVariable UUID checkId,
            @Valid @RequestBody ResultRequest request) {
        return CheckResponse.from(service.result(deviceId, token, checkId, request.status(),
                request.appetiteResult(), request.confidence(), request.modelVersion(),
                request.observedAt(), request.message()));
    }

    public record ResultRequest(@NotNull AppetiteCheckStatus status, AppetiteResult appetiteResult,
            @DecimalMin("0.0000") @DecimalMax("1.0000") @Digits(integer = 1, fraction = 4) BigDecimal confidence,
            @Size(max = 120) String modelVersion, Instant observedAt, @Size(max = 500) String message) {}

    public record CheckResponse(UUID id, UUID tankId, AppetiteCheckStatus status, Instant requestedAt,
            Instant expiresAt, Instant startedAt, Instant completedAt, Instant observedAt,
            AppetiteResult appetiteResult, BigDecimal confidence, String modelVersion, String message) {
        static CheckResponse from(AppetiteCheck item) {
            return new CheckResponse(item.getId(), item.getTank().getId(), item.getStatus(), item.getRequestedAt(),
                    item.getExpiresAt(), item.getStartedAt(), item.getCompletedAt(), item.getObservedAt(),
                    item.getAppetiteResult(), item.getConfidence(), item.getModelVersion(), item.getMessage());
        }
    }
}
