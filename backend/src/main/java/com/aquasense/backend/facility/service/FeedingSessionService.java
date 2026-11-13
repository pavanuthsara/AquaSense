package com.aquasense.backend.facility.service;

import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.AppetiteObservation;
import com.aquasense.backend.facility.model.AppetiteResult;
import com.aquasense.backend.facility.model.DeviceOperationalState;
import com.aquasense.backend.facility.model.DeviceType;
import com.aquasense.backend.facility.model.FeedingOutcome;
import com.aquasense.backend.facility.model.FeedingSession;
import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.model.TankDevice;
import com.aquasense.backend.facility.model.TankScheduleMode;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FeedingSessionRepository;
import com.aquasense.backend.facility.repository.GroupFeedingTimeRepository;
import com.aquasense.backend.facility.repository.TankFeedingTimeRepository;
import com.aquasense.backend.facility.repository.TankRepository;
import com.aquasense.backend.facility.service.DeviceHealthService.DeviceHealth;
import com.aquasense.backend.facility.service.FeederCalibrationService.PortionPreview;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FeedingSessionService {
    public static final Duration COOLDOWN = Duration.ofMinutes(15);

    private final FeedingSessionRepository sessions;
    private final TankRepository tanks;
    private final TankFeedingTimeRepository tankTimes;
    private final GroupFeedingTimeRepository groupTimes;
    private final FacilityMembershipRepository memberships;
    private final DeviceHealthService deviceHealthService;
    private final AppetiteObservationService observationService;
    private final FeederCalibrationService calibrationService;

    public FeedingSessionService(
            FeedingSessionRepository sessions,
            TankRepository tanks,
            TankFeedingTimeRepository tankTimes,
            GroupFeedingTimeRepository groupTimes,
            FacilityMembershipRepository memberships,
            DeviceHealthService deviceHealthService,
            AppetiteObservationService observationService,
            FeederCalibrationService calibrationService) {
        this.sessions = sessions;
        this.tanks = tanks;
        this.tankTimes = tankTimes;
        this.groupTimes = groupTimes;
        this.memberships = memberships;
        this.deviceHealthService = deviceHealthService;
        this.observationService = observationService;
        this.calibrationService = calibrationService;
    }

    @Transactional
    public FeedingSession processOccurrence(UUID tankId, Instant scheduledFor) {
        scheduledFor = scheduledFor.truncatedTo(ChronoUnit.MICROS);
        Tank tank = tanks.findByIdForFeedingUpdate(tankId).orElseThrow(this::tankNotFound);
        Optional<FeedingSession> existing = sessions.findByTank_IdAndScheduledFor(tankId, scheduledFor);
        if (existing.isPresent()) return existing.get();

        Instant now = Instant.now();
        FeedingSession session = sessions.save(new FeedingSession(tank, scheduledFor, now));

        if (!automationEnabled(tank)) {
            session.stop(FeedingOutcome.BLOCKED_AUTOMATION, null, "Automatic feeding is paused", now);
            return session;
        }

        DeviceHealth deviceHealth = deviceHealthService.healthForTank(tankId);
        if (deviceHealth.overallState() != DeviceOperationalState.ONLINE) {
            session.stop(
                    FeedingOutcome.BLOCKED_UNHEALTHY_DEVICE,
                    null,
                    "Required hardware state is " + deviceHealth.overallState(),
                    now);
            return session;
        }

        Optional<FeedingSession> previousCommand = sessions
                .findFirstByTank_IdAndCommandSentAtIsNotNullOrderByCommandSentAtDesc(tankId);
        if (previousCommand.isPresent()
                && previousCommand.get().getCommandSentAt().isAfter(now.minus(COOLDOWN))) {
            session.stop(FeedingOutcome.BLOCKED_COOLDOWN, null, "Tank feeding cooldown is active", now);
            return session;
        }

        AppetiteObservation observation = observationService.latestForTank(tankId).orElse(null);
        if (observation == null
                || observation.getObservedAt().isBefore(now.minus(AppetiteObservationService.MAXIMUM_AGE))
                || observation.getObservedAt().isAfter(now.plus(AppetiteObservationService.MAXIMUM_FUTURE_SKEW))) {
            session.stop(
                    FeedingOutcome.SKIPPED_STALE_OBSERVATION,
                    observation,
                    observation == null ? "No appetite observation is available" : "Observation is stale",
                    now);
            return session;
        }
        if (observation.isLowConfidence()) {
            session.stop(FeedingOutcome.SKIPPED_LOW_CONFIDENCE, observation, "Observation confidence is too low", now);
            return session;
        }
        if (observation.isCountInconsistent()) {
            session.stop(
                    FeedingOutcome.SKIPPED_COUNT_INCONSISTENT,
                    observation,
                    "Detected count differs from expected count",
                    now);
            return session;
        }
        if (observation.getAppetiteResult() == AppetiteResult.LOW) {
            session.stop(FeedingOutcome.SKIPPED_LOW_APPETITE, observation, "Fish appetite is low", now);
            return session;
        }

        PortionPreview preview = calibrationService.calculateForFeeding(
                tank.getFacility().getId(), observation.getDetectedGuppyCount());
        if (preview.calibration() == null || preview.portionUnits() == null
                || preview.portionUnits().signum() <= 0) {
            session.stop(
                    FeedingOutcome.BLOCKED_CALIBRATION,
                    observation,
                    "No positive calibrated portion is available",
                    now);
            return session;
        }
        session.sendCommand(observation, preview.calibration(), preview.portionUnits(), now);
        return session;
    }

    @Transactional
    public void processDue(Instant now) {
        tankTimes.findByNextExecutionAtLessThanEqual(now).forEach(time -> {
            Tank tank = time.getTank();
            Instant occurrence = time.getNextExecutionAt();
            processOccurrence(tank.getId(), occurrence);
            time.advance(ZoneId.of(tank.getFacility().getTimeZone()), occurrence.plusSeconds(1));
        });
        groupTimes.findByNextExecutionAtLessThanEqual(now).forEach(time -> {
            var group = time.getTankGroup();
            Instant occurrence = time.getNextExecutionAt();
            tanks.findByGroup_IdAndArchivedAtIsNull(group.getId()).stream()
                    .filter(tank -> tank.getScheduleMode() == TankScheduleMode.INHERITED)
                    .forEach(tank -> processOccurrence(tank.getId(), occurrence));
            time.advance(ZoneId.of(group.getFacility().getTimeZone()), occurrence.plusSeconds(1));
        });
    }

    @Transactional(readOnly = true)
    public Optional<FeedingSession> latest(UUID userId, UUID facilityId, UUID tankId) {
        requireAccess(userId, facilityId, tankId);
        return sessions.findFirstByTank_IdOrderByScheduledForDesc(tankId);
    }

    @Transactional(readOnly = true)
    public Optional<FeedingSession> nextCommand(UUID deviceId, String token) {
        TankDevice device = requireFeeder(deviceId, token);
        return sessions.findFirstByTank_IdAndOutcomeOrderByCommandSentAtAsc(
                device.getTank().getId(), FeedingOutcome.COMMAND_SENT);
    }

    @Transactional
    public FeedingSession feedback(UUID deviceId, String token, UUID sessionId, boolean delivered, String reason) {
        TankDevice device = requireFeeder(deviceId, token);
        FeedingSession session = sessions.findDetailedById(sessionId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND, "feeding_session_not_found", "The feeding session was not found"));
        if (!session.getTank().getId().equals(device.getTank().getId())) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN, "feeding_session_tank_mismatch", "The session belongs to another tank");
        }
        if (session.getOutcome() == FeedingOutcome.DELIVERED || session.getOutcome() == FeedingOutcome.FAILED) {
            boolean same = delivered == (session.getOutcome() == FeedingOutcome.DELIVERED);
            if (!same) {
                throw new FacilityException(
                        HttpStatus.CONFLICT, "feedback_conflict", "Conflicting feeder feedback was already recorded");
            }
            return session;
        }
        if (session.getOutcome() != FeedingOutcome.COMMAND_SENT) {
            throw new FacilityException(
                    HttpStatus.CONFLICT, "command_not_sent", "This session has no pending feeder command");
        }
        session.recordFeedback(delivered, cleanReason(reason), Instant.now());
        return session;
    }

    private boolean automationEnabled(Tank tank) {
        if (tank.isArchived() || !tank.isAutomationEnabled()) return false;
        return tank.getScheduleMode() == TankScheduleMode.OVERRIDE
                || (tank.getGroup() != null && tank.getGroup().isFeedingAutomationEnabled());
    }

    private TankDevice requireFeeder(UUID deviceId, String token) {
        TankDevice device = deviceHealthService.authenticate(deviceId, token);
        if (device.getType() != DeviceType.FEEDER) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN, "feeder_required", "Only a feeder can receive commands or report feedback");
        }
        return device;
    }

    private void requireAccess(UUID userId, UUID facilityId, UUID tankId) {
        if (memberships.findByUser_IdAndFacility_Id(userId, facilityId).isEmpty()
                || tanks.findByIdAndFacility_Id(tankId, facilityId).isEmpty()) {
            throw tankNotFound();
        }
    }

    private String cleanReason(String reason) {
        if (reason == null || reason.isBlank()) return "Feeder reported an unspecified failure";
        String value = reason.trim();
        return value.length() > 500 ? value.substring(0, 500) : value;
    }

    private FacilityException tankNotFound() {
        return new FacilityException(HttpStatus.NOT_FOUND, "tank_not_found", "The tank was not found");
    }
}
