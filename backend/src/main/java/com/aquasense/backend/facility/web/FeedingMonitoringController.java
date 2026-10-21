package com.aquasense.backend.facility.web;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.DeviceOperationalState;
import com.aquasense.backend.facility.model.DeviceType;
import com.aquasense.backend.facility.model.FeedingOutcome;
import com.aquasense.backend.facility.model.FeedingSession;
import com.aquasense.backend.facility.model.FeedingSource;
import com.aquasense.backend.facility.service.FeedingMonitoringService;
import com.aquasense.backend.facility.service.FeedingMonitoringService.Dashboard;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.security.oauth2.jwt.Jwt;

@RestController
@Validated
public class FeedingMonitoringController {
    private final FeedingMonitoringService service;

    public FeedingMonitoringController(FeedingMonitoringService service) {
        this.service = service;
    }

    @GetMapping("/api/v1/facilities/{facilityId}/feeding-dashboard")
    DashboardResponse dashboard(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID facilityId) {
        return DashboardResponse.from(service.dashboard(userId(jwt), facilityId));
    }

    @GetMapping("/api/v1/facilities/{facilityId}/feeding-history")
    HistoryPageResponse history(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @RequestParam(required = false) UUID tankId,
            @RequestParam(required = false) UUID groupId,
            @RequestParam(required = false) FeedingSource source,
            @RequestParam(required = false) FeedingOutcome outcome,
            @RequestParam(required = false) Instant from,
            @RequestParam(required = false) Instant to,
            @RequestParam(required = false) String cursor,
            @RequestParam(defaultValue = "25") @Min(1) @Max(100) int size) {
        return HistoryPageResponse.from(service.history(
                userId(jwt), facilityId, tankId, groupId, source, outcome, from, to, cursor, size));
    }

    @GetMapping("/api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-history")
    HistoryPageResponse tankHistory(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId,
            @RequestParam(required = false) FeedingSource source,
            @RequestParam(required = false) FeedingOutcome outcome,
            @RequestParam(required = false) Instant from,
            @RequestParam(required = false) Instant to,
            @RequestParam(required = false) String cursor,
            @RequestParam(defaultValue = "25") @Min(1) @Max(100) int size) {
        return HistoryPageResponse.from(service.history(
                userId(jwt), facilityId, tankId, null, source, outcome, from, to, cursor, size));
    }

    private UUID userId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }

    public record DashboardResponse(
            Instant generatedAt,
            int totalTanks,
            long automatedTanks,
            int upcomingCount,
            long pendingCommands,
            long delivered,
            long skipped,
            long blocked,
            long failed,
            int unhealthyDeviceCount,
            List<UpcomingResponse> upcoming,
            List<UnhealthyDeviceResponse> unhealthyDevices,
            List<HistoryItemResponse> recentSessions) {
        static DashboardResponse from(Dashboard dashboard) {
            return new DashboardResponse(
                    dashboard.generatedAt(),
                    dashboard.totalTanks(),
                    dashboard.automatedTanks(),
                    dashboard.upcomingCount(),
                    dashboard.pendingCommands(),
                    dashboard.delivered(),
                    dashboard.skipped(),
                    dashboard.blocked(),
                    dashboard.failed(),
                    dashboard.unhealthyDeviceCount(),
                    dashboard.upcoming().stream().map(UpcomingResponse::from).toList(),
                    dashboard.unhealthyDevices().stream().map(UnhealthyDeviceResponse::from).toList(),
                    dashboard.recentSessions().stream().map(HistoryItemResponse::from).toList());
        }
    }

    public record UpcomingResponse(
            UUID tankId, String tankName, UUID groupId, String groupName, Instant scheduledFor) {
        static UpcomingResponse from(FeedingMonitoringService.UpcomingSession item) {
            return new UpcomingResponse(
                    item.tankId(), item.tankName(), item.groupId(), item.groupName(), item.scheduledFor());
        }
    }

    public record UnhealthyDeviceResponse(
            UUID tankId,
            String tankName,
            DeviceType type,
            DeviceOperationalState state,
            Instant lastHeartbeatAt) {
        static UnhealthyDeviceResponse from(FeedingMonitoringService.UnhealthyDevice item) {
            return new UnhealthyDeviceResponse(
                    item.tankId(), item.tankName(), item.type(), item.state(), item.lastHeartbeatAt());
        }
    }

    public record HistoryPageResponse(List<HistoryItemResponse> items, String nextCursor) {
        static HistoryPageResponse from(FeedingMonitoringService.HistoryPage page) {
            return new HistoryPageResponse(
                    page.items().stream().map(HistoryItemResponse::from).toList(), page.nextCursor());
        }
    }

    public record HistoryItemResponse(
            UUID id,
            UUID tankId,
            String tankName,
            UUID groupId,
            String groupName,
            Instant scheduledFor,
            FeedingSource source,
            FeedingOutcome outcome,
            BigDecimal portionUnits,
            Instant commandSentAt,
            Instant feedbackAt,
            String reason) {
        static HistoryItemResponse from(FeedingSession session) {
            var group = session.getTank().getGroup();
            return new HistoryItemResponse(
                    session.getId(),
                    session.getTank().getId(),
                    session.getTank().getName(),
                    group == null ? null : group.getId(),
                    group == null ? null : group.getName(),
                    session.getScheduledFor(),
                    session.getSource(),
                    session.getOutcome(),
                    session.getPortionUnits(),
                    session.getCommandSentAt(),
                    session.getFeedbackAt(),
                    session.getFailureReason());
        }
    }
}
