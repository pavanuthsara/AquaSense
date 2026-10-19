package com.aquasense.backend.facility.web;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.model.TankGroup;
import com.aquasense.backend.facility.model.TankStatus;
import com.aquasense.backend.facility.service.TankService;
import com.aquasense.backend.facility.service.TankService.TankInput;
import com.aquasense.backend.facility.service.TankService.TankPage;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/facilities/{facilityId}")
public class TankController {
    private final TankService tankService;

    public TankController(TankService tankService) {
        this.tankService = tankService;
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
        return TankDetailResponse.from(tankService.get(userId(jwt), facilityId, tankId));
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
            List<String> feedingTimes,
            Instant lastFeedingAt,
            Instant nextFeedingAt,
            List<TankActivityResponse> recentActivity) {
        static TankDetailResponse from(Tank tank) {
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
            return new TankDetailResponse(
                    TankResponse.from(tank),
                    observationState,
                    "NOT_CONFIGURED",
                    List.of(),
                    null,
                    null,
                    activity);
        }
    }
}
