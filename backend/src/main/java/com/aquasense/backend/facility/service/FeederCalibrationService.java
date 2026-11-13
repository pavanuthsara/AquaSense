package com.aquasense.backend.facility.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.model.FeederCalibration;
import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.aquasense.backend.facility.repository.FeederCalibrationRepository;
import com.aquasense.backend.facility.repository.TankRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FeederCalibrationService {
    private final FacilityMembershipRepository memberships;
    private final FacilityRepository facilities;
    private final FeederCalibrationRepository calibrations;
    private final TankRepository tanks;

    public FeederCalibrationService(
            FacilityMembershipRepository memberships,
            FacilityRepository facilities,
            FeederCalibrationRepository calibrations,
            TankRepository tanks) {
        this.memberships = memberships;
        this.facilities = facilities;
        this.calibrations = calibrations;
        this.tanks = tanks;
    }

    @Transactional(readOnly = true)
    public Optional<FeederCalibration> getActive(UUID userId, UUID facilityId) {
        requireMembership(userId, facilityId);
        return calibrations.findFirstByFacility_IdOrderByVersionDesc(facilityId);
    }

    @Transactional
    public FeederCalibration createVersion(
            UUID userId,
            UUID facilityId,
            BigDecimal unitsPerFish,
            BigDecimal minimumUnits,
            BigDecimal maximumUnits) {
        FacilityMembership membership = requireOwner(userId, facilityId);
        var facility = facilities.findByIdForUpdate(facilityId)
                .orElseThrow(this::facilityNotFound);
        BigDecimal rate = normalized(unitsPerFish);
        BigDecimal minimum = normalized(minimumUnits);
        BigDecimal maximum = normalized(maximumUnits);
        if (minimum.compareTo(maximum) > 0) {
            throw new FacilityException(
                    HttpStatus.BAD_REQUEST,
                    "invalid_calibration_bounds",
                    "Minimum feeder units cannot exceed maximum feeder units");
        }
        int version = calibrations.findFirstByFacility_IdOrderByVersionDesc(facilityId)
                .map(item -> item.getVersion() + 1)
                .orElse(1);
        return calibrations.save(new FeederCalibration(
                facility,
                version,
                rate,
                minimum,
                maximum,
                membership.getUser(),
                Instant.now()));
    }

    @Transactional(readOnly = true)
    public PortionPreview preview(UUID userId, UUID facilityId, UUID tankId, Integer requestedFishCount) {
        requireMembership(userId, facilityId);
        Tank tank = tanks.findByIdAndFacility_Id(tankId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND, "tank_not_found", "The tank was not found"));
        int fishCount = requestedFishCount == null
                ? tank.getDetectedGuppyCount() == null
                        ? tank.getExpectedGuppyCount()
                        : tank.getDetectedGuppyCount()
                : requestedFishCount;
        if (fishCount < 0 || fishCount > 1_000_000) {
            throw new FacilityException(
                    HttpStatus.BAD_REQUEST,
                    "invalid_fish_count",
                    "Fish count must be between 0 and 1,000,000");
        }
        return calculateForFeeding(facilityId, fishCount);
    }

    @Transactional(readOnly = true)
    public PortionPreview calculateForFeeding(UUID facilityId, int fishCount) {
        Optional<FeederCalibration> active = calibrations.findFirstByFacility_IdOrderByVersionDesc(facilityId);
        if (active.isEmpty()) {
            return new PortionPreview(fishCount, null, null, null, "NOT_CONFIGURED");
        }
        FeederCalibration calibration = active.get();
        BigDecimal raw = calibration.getUnitsPerFish()
                .multiply(BigDecimal.valueOf(fishCount))
                .setScale(4, RoundingMode.HALF_UP);
        BigDecimal portion;
        String limit;
        if (fishCount == 0) {
            portion = BigDecimal.ZERO.setScale(4);
            limit = "ZERO_FISH";
        } else if (raw.compareTo(calibration.getMinimumUnits()) < 0) {
            portion = calibration.getMinimumUnits();
            limit = "MINIMUM";
        } else if (raw.compareTo(calibration.getMaximumUnits()) > 0) {
            portion = calibration.getMaximumUnits();
            limit = "MAXIMUM";
        } else {
            portion = raw;
            limit = "NONE";
        }
        return new PortionPreview(fishCount, calibration, raw, portion, limit);
    }

    private BigDecimal normalized(BigDecimal value) {
        return value.setScale(4, RoundingMode.HALF_UP);
    }

    private FacilityMembership requireMembership(UUID userId, UUID facilityId) {
        return memberships.findByUser_IdAndFacility_Id(userId, facilityId)
                .orElseThrow(this::facilityNotFound);
    }

    private FacilityMembership requireOwner(UUID userId, UUID facilityId) {
        FacilityMembership membership = requireMembership(userId, facilityId);
        if (membership.getRole() != FacilityRole.OWNER) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN,
                    "owner_required",
                    "Only an aquarium owner can change feeder calibration");
        }
        return membership;
    }

    private FacilityException facilityNotFound() {
        return new FacilityException(
                HttpStatus.NOT_FOUND,
                "facility_not_found",
                "The aquarium was not found or is not accessible");
    }

    public record PortionPreview(
            int fishCount,
            FeederCalibration calibration,
            BigDecimal rawUnits,
            BigDecimal portionUnits,
            String limitedBy) {
    }
}
