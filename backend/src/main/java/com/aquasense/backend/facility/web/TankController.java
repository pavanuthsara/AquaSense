package com.aquasense.backend.facility.web;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.model.TankGroup;
import com.aquasense.backend.facility.model.TankScheduleMode;
import com.aquasense.backend.facility.model.TankStatus;
import com.aquasense.backend.facility.service.TankService;
import com.aquasense.backend.facility.service.DeviceHealthService;
import com.aquasense.backend.facility.service.DeviceHealthService.DeviceHealth;
import com.aquasense.backend.facility.service.TankService.TankInput;
import com.aquasense.backend.facility.service.TankService.TankPage;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.validation.constraints.Pattern;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/facilities/{facilityId}")
public class TankController {
    private static final DateTimeFormatter FEEDING_TIME_FORMAT = DateTimeFormatter.ofPattern("HH:mm");
    private final TankService tankService;
    private final DeviceHealthService deviceHealthService;

    public TankController(TankService tankService, DeviceHealthService deviceHealthService) {
        this.tankService = tankService;
        this.deviceHealthService = deviceHealthService;
    }

    @GetMapping("/tanks")
    TankPageResponse list(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size,
            @RequestParam(required = false) String query,
            @RequestParam(required = false) TankStatus status,
            @RequestParam(required = false) UUID groupId,
            @RequestParam(defaultValue = "false") boolean unassigned,
            @RequestParam(required = false) String tag) {
        TankPage result = tankService.list(
                userId(jwt), facilityId, page, size, query, status, groupId, unassigned, tag);
        return TankPageResponse.from(result);
    }

    @GetMapping("/tanks/{tankId}")
    TankDetailResponse get(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId) {
        Tank tank = tankService.get(userId(jwt), facilityId, tankId);
        return TankDetailResponse.from(tank, deviceHealthService.healthForTank(tankId));
    }

    @GetMapping("/tank-tags")
    List<String> listTags(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId) {
        return tankService.listTags(userId(jwt), facilityId);
    }

    @PostMapping("/tanks")
    @ResponseStatus(HttpStatus.CREATED)
    TankResponse create(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @Valid @RequestBody TankRequest request) {
        return TankResponse.from(tankService.create(userId(jwt), facilityId, request.toInput()));
    }

    @PatchMapping("/tanks/{tankId}")
    TankResponse update(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId,
            @Valid @RequestBody TankRequest request) {
        return TankResponse.from(tankService.update(userId(jwt), facilityId, tankId, request.toInput()));
    }

    @PostMapping("/tanks/{tankId}/archive")
    TankResponse archive(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId) {
        return TankResponse.from(tankService.archive(userId(jwt), facilityId, tankId));
    }

    @PutMapping("/tanks/{tankId}/feeding-schedule")
    TankDetailResponse configureFeedingSchedule(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId,
            @Valid @RequestBody TankScheduleRequest request) {
        Tank tank = tankService.configureFeedingSchedule(
                userId(jwt), facilityId, tankId, request.mode(), request.times());
        return TankDetailResponse.from(tank, deviceHealthService.healthForTank(tankId));
    }

    private UUID userId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }

    public record TankRequest(
            @NotBlank @Size(max = 120) String name,
            @NotBlank @Size(max = 64) String code,
            @Min(0) @Max(1_000_000) int expectedGuppyCount,
            UUID groupId,
            @NotNull @Size(max = 20) List<@NotBlank @Size(max = 40) String> tags,
            boolean automationEnabled,
            @Size(max = 2000) String notes) {
        TankInput toInput() {
            return new TankInput(name, code, expectedGuppyCount, groupId, tags, automationEnabled, notes);
        }
    }

    public record TankScheduleRequest(
            @NotNull TankScheduleMode mode,
            @NotNull @Size(max = 24)
            List<@NotBlank @Pattern(regexp = "(?:[01]\\d|2[0-3]):[0-5]\\d") String> times) {
    }

    public record TankResponse(
            UUID id,
            UUID facilityId,
            String name,
            String code,
            int expectedGuppyCount,
            Integer detectedGuppyCount,
            BigDecimal detectionConfidence,
            Instant countObservedAt,
            UUID groupId,
            String groupName,
            List<String> tags,
            boolean automationEnabled,
            TankScheduleMode scheduleMode,
            TankStatus status,
            String notes,
            Instant createdAt,
            Instant updatedAt,
            Instant archivedAt) {
        static TankResponse from(Tank tank) {
            TankGroup group = tank.getGroup();
            return new TankResponse(
                    tank.getId(),
                    tank.getFacility().getId(),
                    tank.getName(),
                    tank.getCode(),
                    tank.getExpectedGuppyCount(),
                    tank.getDetectedGuppyCount(),
                    tank.getDetectionConfidence(),
                    tank.getCountObservedAt(),
                    group == null ? null : group.getId(),
                    group == null ? null : group.getName(),
                    tank.getTags().stream().sorted().toList(),
                    tank.isAutomationEnabled(),
                    tank.getScheduleMode(),
                    status(tank),
                    tank.getNotes(),
                    tank.getCreatedAt(),
                    tank.getUpdatedAt(),
                    tank.getArchivedAt());
        }

        private static TankStatus status(Tank tank) {
            if (tank.isArchived()) {
                return TankStatus.ARCHIVED;
            }
            return tank.isAutomationEnabled() ? TankStatus.ACTIVE : TankStatus.PAUSED;
        }
    }

    public record TankPageResponse(
            List<TankResponse> items,
            int page,
            int size,
            long totalItems,
            int totalPages) {
        static TankPageResponse from(TankPage page) {
            return new TankPageResponse(
                    page.items().stream().map(TankResponse::from).toList(),
                    page.page(),
                    page.size(),
                    page.totalItems(),
                    page.totalPages());
        }
    }

    public record TankActivityResponse(String type, String title, Instant occurredAt) {
    }

    public record TankDetailResponse(
            TankResponse tank,
            String observationState,
            String deviceStatus,
            DeviceHealthController.DeviceHealthResponse deviceHealth,
            TankScheduleMode scheduleMode,
            List<String> inheritedFeedingTimes,
            List<String> feedingTimes,
            Instant lastFeedingAt,
            Instant nextFeedingAt,
            List<TankActivityResponse> recentActivity) {
        static TankDetailResponse from(Tank tank, DeviceHealth deviceHealth) {
            List<TankActivityResponse> activity = new ArrayList<>();
            if (!tank.getUpdatedAt().equals(tank.getCreatedAt())) {
                activity.add(new TankActivityResponse("SETTINGS_UPDATED", "Tank settings updated", tank.getUpdatedAt()));
            }
            activity.add(new TankActivityResponse("TANK_CREATED", "Tank created", tank.getCreatedAt()));
            String observationState;
            if (tank.getCountObservedAt() == null) {
                observationState = "NO_DATA";
            } else if (tank.getCountObservedAt().isBefore(Instant.now().minus(Duration.ofHours(1)))) {
                observationState = "STALE";
            } else {
                observationState = "CURRENT";
            }
            boolean override = tank.getScheduleMode() == TankScheduleMode.OVERRIDE;
            List<String> inheritedTimes = tank.getGroup() == null
                    ? List.of()
                    : tank.getGroup().getFeedingTimes().stream()
                            .map(item -> item.getLocalTime())
                            .map(FEEDING_TIME_FORMAT::format)
                            .toList();
            List<String> effectiveTimes = override
                    ? tank.getFeedingTimes().stream()
                            .map(item -> item.getLocalTime())
                            .map(FEEDING_TIME_FORMAT::format)
                            .toList()
                    : inheritedTimes;
            Instant nextFeedingAt = null;
            if (tank.isAutomationEnabled()) {
                nextFeedingAt = (override
                        ? tank.getFeedingTimes().stream().map(item -> item.getNextExecutionAt())
                        : tank.getGroup() == null || !tank.getGroup().isFeedingAutomationEnabled()
                                ? java.util.stream.Stream.<Instant>empty()
                                : tank.getGroup().getFeedingTimes().stream()
                                        .map(item -> item.getNextExecutionAt()))
                        .filter(java.util.Objects::nonNull)
                        .min(Instant::compareTo)
                        .orElse(null);
            }
            return new TankDetailResponse(
                    TankResponse.from(tank),
                    observationState,
                    deviceHealth.overallState().name(),
                    DeviceHealthController.DeviceHealthResponse.from(deviceHealth),
                    tank.getScheduleMode(),
                    inheritedTimes,
                    effectiveTimes,
                    null,
                    nextFeedingAt,
                    activity);
        }
    }
}
