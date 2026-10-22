package com.aquasense.backend.facility.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import com.aquasense.backend.facility.model.*;
import com.aquasense.backend.facility.repository.*;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class AppetiteCheckService {
    private static final List<AppetiteCheckStatus> ACTIVE = List.of(
            AppetiteCheckStatus.PENDING, AppetiteCheckStatus.CHECKING);
    private final AppetiteCheckRepository checks;
    private final TankRepository tanks;
    private final TankDeviceRepository devices;
    private final FacilityMembershipRepository memberships;
    private final DeviceHealthService deviceHealth;

    public AppetiteCheckService(AppetiteCheckRepository checks, TankRepository tanks,
            TankDeviceRepository devices, FacilityMembershipRepository memberships,
            DeviceHealthService deviceHealth) {
        this.checks = checks;
        this.tanks = tanks;
        this.devices = devices;
        this.memberships = memberships;
        this.deviceHealth = deviceHealth;
    }

    public AppetiteCheck request(UUID userId, UUID facilityId, UUID tankId) {
        requireMembership(userId, facilityId);
        Tank tank = tanks.findByIdAndFacilityIdForUpdate(tankId, facilityId).orElseThrow(this::notFound);
        if (tank.isArchived()) throw error(HttpStatus.CONFLICT, "tank_archived", "Archived tanks cannot be checked.");
        TankDevice device = devices.findByTank_IdAndType(tankId, DeviceType.EDGE_PROCESSOR)
                .orElseThrow(() -> error(HttpStatus.CONFLICT, "edge_processor_missing",
                        "Connect this tank's edge processor before checking appetite."));
        Optional<AppetiteCheck> active = activeForTank(tankId);
        if (active.isPresent()) return active.get();
        return checks.save(new AppetiteCheck(tank, device, Instant.now()));
    }

    public AppetiteCheck get(UUID userId, UUID facilityId, UUID tankId, UUID checkId) {
        requireMembership(userId, facilityId);
        AppetiteCheck check = checks.findForUpdate(checkId).orElseThrow(this::notFound);
        if (!check.getTank().getId().equals(tankId)
                || !check.getTank().getFacility().getId().equals(facilityId)) throw notFound();
        check.expireIfNeeded(Instant.now());
        return check;
    }

    public Optional<AppetiteCheck> next(UUID deviceId, String token) {
        TankDevice device = requireEdge(deviceId, token);
        if (device.getTank().isArchived()) return Optional.empty();
        Optional<AppetiteCheck> active = activeForTank(device.getTank().getId());
        active.ifPresent(check -> check.start(Instant.now()));
        return active;
    }

    public AppetiteCheck result(UUID deviceId, String token, UUID checkId, AppetiteCheckStatus outcome,
            AppetiteResult label, BigDecimal confidence, String version, Instant observedAt, String message) {
        TankDevice device = requireEdge(deviceId, token);
        AppetiteCheck check = checks.findForUpdate(checkId).orElseThrow(this::notFound);
        if (!check.getDevice().getId().equals(device.getId())
                || !check.getTank().getId().equals(device.getTank().getId())) throw notFound();
        Instant now = Instant.now();
        check.expireIfNeeded(now);
        // Retried delivery cannot overwrite a completed result or revive an expired check.
        if (!check.getStatus().isActive()) return check;
        if (check.getStatus() != AppetiteCheckStatus.CHECKING || device.getTank().isArchived()) {
            throw error(HttpStatus.CONFLICT, "check_not_started", "This appetite check is not active.");
        }
        if (outcome != AppetiteCheckStatus.COMPLETED && outcome != AppetiteCheckStatus.INSUFFICIENT_DATA
                && outcome != AppetiteCheckStatus.FAILED) {
            throw error(HttpStatus.BAD_REQUEST, "invalid_check_status", "Invalid appetite check outcome.");
        }
        if (outcome == AppetiteCheckStatus.COMPLETED && (label == null || confidence == null
                || version == null || version.isBlank() || observedAt == null
                || observedAt.isBefore(check.getStartedAt()) || observedAt.isAfter(now.plusSeconds(5)))) {
            throw error(HttpStatus.BAD_REQUEST, "invalid_check_result", "A fresh prediction and model version are required.");
        }
        check.finish(outcome, outcome == AppetiteCheckStatus.COMPLETED ? label : null,
                outcome == AppetiteCheckStatus.COMPLETED ? confidence : null, version,
                outcome == AppetiteCheckStatus.COMPLETED ? observedAt : null, message, now);
        return check;
    }

    private Optional<AppetiteCheck> activeForTank(UUID tankId) {
        Optional<AppetiteCheck> check = checks.findFirstByTank_IdAndStatusInOrderByRequestedAtAsc(tankId, ACTIVE);
        check.ifPresent(item -> item.expireIfNeeded(Instant.now()));
        return check.filter(item -> item.getStatus().isActive());
    }

    private TankDevice requireEdge(UUID id, String token) {
        TankDevice device = deviceHealth.authenticate(id, token);
        if (device.getType() != DeviceType.EDGE_PROCESSOR) {
            throw error(HttpStatus.FORBIDDEN, "edge_processor_required", "An edge processor is required.");
        }
        return device;
    }

    private void requireMembership(UUID userId, UUID facilityId) {
        if (memberships.findByUser_IdAndFacility_Id(userId, facilityId).isEmpty()) throw notFound();
    }

    private FacilityException notFound() {
        return error(HttpStatus.NOT_FOUND, "appetite_check_not_found", "The tank or appetite check was not found.");
    }

    private FacilityException error(HttpStatus status, String code, String message) {
        return new FacilityException(status, code, message);
    }
}
