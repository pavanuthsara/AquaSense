package com.aquasense.backend.facility.web;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import com.aquasense.backend.facility.model.FeedingOutcome;
import com.aquasense.backend.facility.model.FeedingSession;
import com.aquasense.backend.facility.service.FeedingSessionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class FeedingSessionController {
    private final FeedingSessionService service;

    public FeedingSessionController(FeedingSessionService service) {
        this.service = service;
    }

    @GetMapping("/api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-session/latest")
    SessionStateResponse latest(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId) {
        return service.latest(UUID.fromString(jwt.getSubject()), facilityId, tankId)
                .map(session -> new SessionStateResponse(true, SessionResponse.from(session)))
                .orElseGet(() -> new SessionStateResponse(false, null));
    }

    @GetMapping("/api/v1/feeder-commands/next")
    ResponseEntity<SessionResponse> nextCommand(
            @RequestHeader("X-Device-Id") UUID deviceId,
            @RequestHeader("X-Device-Token") String token) {
        return service.nextCommand(deviceId, token)
                .map(SessionResponse::from)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    @PostMapping("/api/v1/feeder-commands/{sessionId}/feedback")
    SessionResponse feedback(
            @RequestHeader("X-Device-Id") UUID deviceId,
            @RequestHeader("X-Device-Token") String token,
            @PathVariable UUID sessionId,
            @Valid @RequestBody FeedbackRequest request) {
        return SessionResponse.from(service.feedback(
                deviceId, token, sessionId, request.delivered(), request.reason()));
    }

    public record FeedbackRequest(@NotNull Boolean delivered, @Size(max = 500) String reason) {
    }

    public record SessionStateResponse(boolean available, SessionResponse session) {
    }

    public record SessionResponse(
            UUID id,
            UUID tankId,
            Instant scheduledFor,
            FeedingOutcome outcome,
            BigDecimal portionUnits,
            Integer calibrationVersion,
            UUID observationId,
            Instant commandSentAt,
            Instant feedbackAt,
            String reason,
            Instant createdAt,
            Instant updatedAt) {
        public static SessionResponse from(FeedingSession session) {
            return new SessionResponse(
                    session.getId(),
                    session.getTank().getId(),
                    session.getScheduledFor(),
                    session.getOutcome(),
                    session.getPortionUnits(),
                    session.getCalibration() == null ? null : session.getCalibration().getVersion(),
                    session.getObservation() == null ? null : session.getObservation().getId(),
                    session.getCommandSentAt(),
                    session.getFeedbackAt(),
                    session.getFailureReason(),
                    session.getCreatedAt(),
                    session.getUpdatedAt());
        }
    }
}
