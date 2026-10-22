package com.aquasense.backend.facility.service;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.aquasense.backend.facility.model.DeviceOperationalState;
import com.aquasense.backend.facility.model.DeviceType;
import com.aquasense.backend.facility.model.FeedingOutcome;
import com.aquasense.backend.facility.model.FeedingSession;
import com.aquasense.backend.facility.model.FeedingSource;
import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.model.TankDevice;
import com.aquasense.backend.facility.model.TankScheduleMode;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FeedingSessionRepository;
import com.aquasense.backend.facility.repository.FeedingSessionSpecifications;
import com.aquasense.backend.facility.repository.GroupFeedingTimeRepository;
import com.aquasense.backend.facility.repository.TankDeviceRepository;
import com.aquasense.backend.facility.repository.TankFeedingTimeRepository;
import com.aquasense.backend.facility.repository.TankRepository;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FeedingMonitoringService {
    private static final Duration DASHBOARD_WINDOW = Duration.ofHours(24);

    private final FacilityMembershipRepository memberships;
    private final FeedingSessionRepository sessions;
    private final TankRepository tanks;
    private final TankDeviceRepository devices;
    private final TankFeedingTimeRepository tankTimes;
    private final GroupFeedingTimeRepository groupTimes;

    public FeedingMonitoringService(
            FacilityMembershipRepository memberships,
            FeedingSessionRepository sessions,
            TankRepository tanks,
            TankDeviceRepository devices,
            TankFeedingTimeRepository tankTimes,
            GroupFeedingTimeRepository groupTimes) {
        this.memberships = memberships;
        this.sessions = sessions;
        this.tanks = tanks;
        this.devices = devices;
        this.tankTimes = tankTimes;
        this.groupTimes = groupTimes;
    }

    @Transactional(readOnly = true)
    public Dashboard dashboard(UUID userId, UUID facilityId) {
        requireAccess(userId, facilityId);
        Instant now = Instant.now();
        Instant until = now.plus(DASHBOARD_WINDOW);
        List<Tank> activeTanks = tanks.findByFacility_IdAndArchivedAtIsNull(facilityId);

        List<UpcomingSession> upcoming = new ArrayList<>();
        tankTimes.findByTank_Facility_IdAndNextExecutionAtBetween(facilityId, now, until)
                .forEach(time -> {
                    Tank tank = time.getTank();
                    if (tank.isAutomationEnabled() && tank.getScheduleMode() == TankScheduleMode.OVERRIDE) {
                        upcoming.add(UpcomingSession.from(tank, time.getNextExecutionAt()));
                    }
                });
        groupTimes.findByTankGroup_Facility_IdAndNextExecutionAtBetween(facilityId, now, until)
                .forEach(time -> activeTanks.stream()
                        .filter(Tank::isAutomationEnabled)
                        .filter(tank -> tank.getScheduleMode() == TankScheduleMode.INHERITED)
                        .filter(tank -> tank.getGroup() != null
                                && tank.getGroup().getId().equals(time.getTankGroup().getId()))
                        .forEach(tank -> upcoming.add(UpcomingSession.from(tank, time.getNextExecutionAt()))));
        upcoming.sort(Comparator.comparing(UpcomingSession::scheduledFor)
                .thenComparing(item -> item.tankId().toString()));

        Map<FeedingOutcome, Long> counts = new EnumMap<>(FeedingOutcome.class);
        sessions.countOutcomesSince(facilityId, now.minus(DASHBOARD_WINDOW))
                .forEach(item -> counts.put(item.getOutcome(), item.getCount()));

        List<UnhealthyDevice> unhealthy = devices
                .findByTank_Facility_IdAndTank_ArchivedAtIsNull(facilityId).stream()
                .map(device -> UnhealthyDevice.from(device, now))
                .filter(item -> item.state() != DeviceOperationalState.ONLINE)
                .sorted(Comparator.comparing(UnhealthyDevice::tankName)
                        .thenComparing(item -> item.type().name()))
                .toList();

        List<FeedingSession> recent = queryHistory(
                facilityId, null, null, null, null, null, null, null, 5).items();
        long skipped = counts.entrySet().stream()
                .filter(entry -> entry.getKey().name().startsWith("SKIPPED_"))
                .mapToLong(Map.Entry::getValue)
                .sum();
        long blocked = counts.entrySet().stream()
                .filter(entry -> entry.getKey().name().startsWith("BLOCKED_"))
                .mapToLong(Map.Entry::getValue)
                .sum();
        return new Dashboard(
                now,
                activeTanks.size(),
                activeTanks.stream().filter(Tank::isAutomationEnabled).count(),
                upcoming.size(),
                counts.getOrDefault(FeedingOutcome.COMMAND_SENT, 0L),
                counts.getOrDefault(FeedingOutcome.DELIVERED, 0L),
                skipped,
                blocked,
                counts.getOrDefault(FeedingOutcome.FAILED, 0L),
                unhealthy.size(),
                List.copyOf(upcoming.subList(0, Math.min(10, upcoming.size()))),
                unhealthy.subList(0, Math.min(10, unhealthy.size())),
                recent);
    }

    @Transactional(readOnly = true)
    public HistoryPage history(
            UUID userId,
            UUID facilityId,
            UUID tankId,
            UUID groupId,
            FeedingSource source,
            FeedingOutcome outcome,
            Instant from,
            Instant to,
            String cursor,
            int size) {
        requireAccess(userId, facilityId);
        if (from != null && to != null && !from.isBefore(to)) {
            throw new FacilityException(HttpStatus.BAD_REQUEST, "invalid_date_range", "From must be before to");
        }
        return queryHistory(facilityId, tankId, groupId, source, outcome, from, to, cursor, size);
    }

    private HistoryPage queryHistory(
            UUID facilityId,
            UUID tankId,
            UUID groupId,
            FeedingSource source,
            FeedingOutcome outcome,
            Instant from,
            Instant to,
            String cursor,
            int size) {
        Cursor decoded = decodeCursor(cursor);
        var specification = FeedingSessionSpecifications.history(
                facilityId,
                tankId,
                groupId,
                source,
                outcome,
                from,
                to,
                decoded == null ? null : decoded.scheduledFor(),
                decoded == null ? null : decoded.id());
        // Fetch only one extra row to determine the cursor; no offset or count query.
        List<FeedingSession> result = sessions.findBy(specification, query -> query
                .sortBy(Sort.by(Sort.Order.desc("scheduledFor"), Sort.Order.desc("id")))
                .limit(size + 1)
                .all());
        boolean hasMore = result.size() > size;
        List<FeedingSession> page = hasMore ? result.subList(0, size) : result;
        String nextCursor = hasMore ? encodeCursor(page.get(page.size() - 1)) : null;
        return new HistoryPage(List.copyOf(page), nextCursor);
    }

    private void requireAccess(UUID userId, UUID facilityId) {
        if (memberships.findByUser_IdAndFacility_Id(userId, facilityId).isEmpty()) {
            throw new FacilityException(
                    HttpStatus.NOT_FOUND,
                    "facility_not_found",
                    "The aquarium was not found or is not accessible");
        }
    }

    private String encodeCursor(FeedingSession session) {
        String value = session.getScheduledFor() + "|" + session.getId();
        return Base64.getUrlEncoder().withoutPadding()
                .encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }

    private Cursor decodeCursor(String cursor) {
        if (cursor == null || cursor.isBlank()) return null;
        try {
            String value = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8);
            String[] parts = value.split("\\|", 2);
            return new Cursor(Instant.parse(parts[0]), UUID.fromString(parts[1]));
        } catch (RuntimeException error) {
            throw new FacilityException(HttpStatus.BAD_REQUEST, "invalid_cursor", "The history cursor is invalid");
        }
    }

    private record Cursor(Instant scheduledFor, UUID id) {
    }

    public record Dashboard(
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
            List<UpcomingSession> upcoming,
            List<UnhealthyDevice> unhealthyDevices,
            List<FeedingSession> recentSessions) {
    }

    public record UpcomingSession(
            UUID tankId, String tankName, UUID groupId, String groupName, Instant scheduledFor) {
        static UpcomingSession from(Tank tank, Instant scheduledFor) {
            return new UpcomingSession(
                    tank.getId(),
                    tank.getName(),
                    tank.getGroup() == null ? null : tank.getGroup().getId(),
                    tank.getGroup() == null ? null : tank.getGroup().getName(),
                    scheduledFor);
        }
    }

    public record UnhealthyDevice(
            UUID tankId,
            String tankName,
            DeviceType type,
            DeviceOperationalState state,
            Instant lastHeartbeatAt) {
        static UnhealthyDevice from(TankDevice device, Instant now) {
            return new UnhealthyDevice(
                    device.getTank().getId(),
                    device.getTank().getName(),
                    device.getType(),
                    device.stateAt(now),
                    device.getLastHeartbeatAt());
        }
    }

    public record HistoryPage(List<FeedingSession> items, String nextCursor) {
    }
}
