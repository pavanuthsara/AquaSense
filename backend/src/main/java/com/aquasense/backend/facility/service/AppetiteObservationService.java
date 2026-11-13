package com.aquasense.backend.facility.service;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.AppetiteObservation;
import com.aquasense.backend.facility.model.AppetiteResult;
import com.aquasense.backend.facility.model.DeviceType;
import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.model.TankDevice;
import com.aquasense.backend.facility.repository.AppetiteObservationRepository;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.TankRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AppetiteObservationService {
    public static final BigDecimal MINIMUM_CONFIDENCE = new BigDecimal("0.8000");
    public static final Duration MAXIMUM_AGE = Duration.ofMinutes(5);
    public static final Duration MAXIMUM_FUTURE_SKEW = Duration.ofMinutes(1);

    private final DeviceHealthService deviceHealthService;
    private final AppetiteObservationRepository observations;
    private final FacilityMembershipRepository memberships;
    private final TankRepository tanks;

    public AppetiteObservationService(
            DeviceHealthService deviceHealthService,
            AppetiteObservationRepository observations,
            FacilityMembershipRepository memberships,
            TankRepository tanks) {
        this.deviceHealthService = deviceHealthService;
        this.observations = observations;
        this.memberships = memberships;
        this.tanks = tanks;
    }

    @Transactional
    public AppetiteObservation ingest(
            UUID deviceId,
            String deviceToken,
            UUID tankId,
            int detectedGuppyCount,
            BigDecimal confidence,
            AppetiteResult appetiteResult,
            String modelVersion,
            Instant observedAt) {
        TankDevice device = deviceHealthService.authenticate(deviceId, deviceToken);
        if (device.getType() != DeviceType.EDGE_PROCESSOR) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN,
                    "edge_processor_required",
                    "Only an edge processor can submit appetite observations");
        }
        Tank tank = device.getTank();
        if (!tank.getId().equals(tankId)) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN,
                    "observation_tank_mismatch",
                    "The edge processor is not assigned to this tank");
        }
        if (tank.isArchived()) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "tank_archived",
                    "Archived tanks cannot receive observations");
        }
        Instant receivedAt = Instant.now();
        boolean stale = observedAt.isBefore(receivedAt.minus(MAXIMUM_AGE))
                || observedAt.isAfter(receivedAt.plus(MAXIMUM_FUTURE_SKEW));
        boolean lowConfidence = confidence.compareTo(MINIMUM_CONFIDENCE) < 0;
        int allowedDifference = Math.max(5, (int) Math.ceil(tank.getExpectedGuppyCount() * 0.20));
        boolean inconsistent = Math.abs((long) detectedGuppyCount - tank.getExpectedGuppyCount())
                > allowedDifference;
        AppetiteObservation observation = new AppetiteObservation(
                tank,
                device,
                detectedGuppyCount,
                confidence,
                appetiteResult,
                modelVersion.trim(),
                observedAt,
                receivedAt,
                stale,
                lowConfidence,
                inconsistent);
        if (observation.isValidForFeedingDecision()) {
            tank.recordDetectedCount(detectedGuppyCount, confidence, observedAt, receivedAt);
        }
        return observations.save(observation);
    }

    @Transactional(readOnly = true)
    public Optional<AppetiteObservation> latest(UUID userId, UUID facilityId, UUID tankId) {
        requireTankAccess(userId, facilityId, tankId);
        return latestForTank(tankId);
    }

    @Transactional(readOnly = true)
    public Optional<AppetiteObservation> latestForTank(UUID tankId) {
        return observations.findFirstByTank_IdOrderByObservedAtDescReceivedAtDesc(tankId);
    }

    @Transactional(readOnly = true)
    public AppetiteObservation requireValidForFeeding(UUID facilityId, UUID tankId) {
        Tank tank = tanks.findByIdAndFacility_Id(tankId, facilityId)
                .orElseThrow(this::tankNotFound);
        AppetiteObservation observation = latestForTank(tank.getId())
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.CONFLICT,
                        "observation_missing",
                        "Feeding is blocked because no appetite observation is available"));
        Instant now = Instant.now();
        boolean currentlyStale = observation.getObservedAt().isBefore(now.minus(MAXIMUM_AGE))
                || observation.getObservedAt().isAfter(now.plus(MAXIMUM_FUTURE_SKEW));
        if (!observation.isValidForFeedingDecision() || currentlyStale) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "observation_not_valid",
                    "Feeding is blocked because the latest appetite observation is not valid");
        }
        return observation;
    }

    private void requireTankAccess(UUID userId, UUID facilityId, UUID tankId) {
        if (memberships.findByUser_IdAndFacility_Id(userId, facilityId).isEmpty()) {
            throw new FacilityException(
                    HttpStatus.NOT_FOUND,
                    "facility_not_found",
                    "The aquarium was not found or is not accessible");
        }
        tanks.findByIdAndFacility_Id(tankId, facilityId).orElseThrow(this::tankNotFound);
    }

    private FacilityException tankNotFound() {
        return new FacilityException(HttpStatus.NOT_FOUND, "tank_not_found", "The tank was not found");
    }
}
