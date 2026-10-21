package com.aquasense.backend.facility.web;

import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.GroupFeedingTime;
import com.aquasense.backend.facility.model.TankGroup;
import com.aquasense.backend.facility.service.TankGroupService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/facilities/{facilityId}/tank-groups")
public class TankGroupController {
    private static final DateTimeFormatter FEEDING_TIME_FORMAT = DateTimeFormatter.ofPattern("HH:mm");
    private final TankGroupService groupService;

    public TankGroupController(TankGroupService groupService) {
        this.groupService = groupService;
    }

    @GetMapping
    List<TankGroupResponse> list(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId) {
        return groupService.list(userId(jwt), facilityId).stream()
                .map(TankGroupResponse::from)
                .toList();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    TankGroupResponse create(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @Valid @RequestBody TankGroupRequest request) {
        return TankGroupResponse.from(groupService.create(userId(jwt), facilityId, request.name()));
    }

    @PatchMapping("/{groupId}")
    TankGroupResponse rename(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID groupId,
            @Valid @RequestBody TankGroupRequest request) {
        return TankGroupResponse.from(groupService.rename(userId(jwt), facilityId, groupId, request.name()));
    }

    @PostMapping("/{groupId}/archive")
    TankGroupResponse archive(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID groupId) {
        return TankGroupResponse.from(groupService.archive(userId(jwt), facilityId, groupId));
    }

    @PutMapping("/{groupId}/feeding-schedule")
    TankGroupResponse configureFeedingSchedule(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID groupId,
            @Valid @RequestBody FeedingScheduleRequest request) {
        return TankGroupResponse.from(groupService.configureFeedingSchedule(
                userId(jwt),
                facilityId,
                groupId,
                request.times(),
                request.automationEnabled()));
    }

    private UUID userId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }

    public record TankGroupRequest(
            @NotBlank @Size(max = 80) String name) {
    }

    public record FeedingScheduleRequest(
            @NotNull @Size(min = 1, max = 24)
            List<@NotBlank @Pattern(regexp = "(?:[01]\\d|2[0-3]):[0-5]\\d") String> times,
            boolean automationEnabled) {
    }

    public record TankGroupResponse(
            UUID id,
            UUID facilityId,
            String name,
            int tankCount,
            List<String> feedingTimes,
            boolean feedingAutomationEnabled,
            Instant nextSessionAt,
            boolean archived,
            Instant createdAt,
            Instant updatedAt,
            Instant archivedAt) {
        static TankGroupResponse from(TankGroup group) {
            return new TankGroupResponse(
                    group.getId(),
                    group.getFacility().getId(),
                    group.getName(),
                    group.getTankCount(),
                    group.getFeedingTimes().stream()
                            .map(GroupFeedingTime::getLocalTime)
                            .map(FEEDING_TIME_FORMAT::format)
                            .toList(),
                    group.isFeedingAutomationEnabled(),
                    group.getFeedingTimes().stream()
                            .map(GroupFeedingTime::getNextExecutionAt)
                            .filter(java.util.Objects::nonNull)
                            .min(Instant::compareTo)
                            .orElse(null),
                    group.isArchived(),
                    group.getCreatedAt(),
                    group.getUpdatedAt(),
                    group.getArchivedAt());
        }
    }
}
