package com.aquasense.backend.facility.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.EnumMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.aquasense.backend.facility.model.DeviceOperationalState;
import com.aquasense.backend.facility.model.DeviceType;
import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.model.TankDevice;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.TankDeviceRepository;
import com.aquasense.backend.facility.repository.TankRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeviceHealthService {
    private final FacilityMembershipRepository memberships;
    private final TankRepository tanks;
    private final TankDeviceRepository devices;
    private final SecureRandom random = new SecureRandom();

    public DeviceHealthService(
            FacilityMembershipRepository memberships,
            TankRepository tanks,
            TankDeviceRepository devices) {
        this.memberships = memberships;
        this.tanks = tanks;
        this.devices = devices;
    }

    @Transactional(readOnly = true)
    public DeviceHealth health(UUID userId, UUID facilityId, UUID tankId) {
        requireMembership(userId, facilityId);
        requireTank(facilityId, tankId);
        return healthForTank(tankId, Instant.now());
    }

    @Transactional(readOnly = true)
    public DeviceHealth healthForTank(UUID tankId) {
        return healthForTank(tankId, Instant.now());
    }

    @Transactional
    public ProvisionedDevice provision(
            UUID userId, UUID facilityId, UUID tankId, DeviceType type) {
        requireOwner(userId, facilityId);
        Tank tank = requireTank(facilityId, tankId);
        if (tank.isArchived()) {
            throw new FacilityException(
                    HttpStatus.CONFLICT, "tank_archived", "Archived tanks cannot provision hardware");
        }
        String token = newToken();
        String hash = hash(token);
        Instant now = Instant.now();
        TankDevice device = devices.findByTank_IdAndType(tankId, type)
                .map(existing -> {
                    existing.rotateCredential(hash, now);
                    return existing;
                })
                .orElseGet(() -> new TankDevice(tank, type, hash, now));
        devices.save(device);
        return new ProvisionedDevice(device, token);
    }

    @Transactional
    public TankDevice heartbeat(UUID deviceId, String token, boolean healthy, String message) {
        TankDevice device = devices.findById(deviceId)
                .orElseThrow(this::invalidDeviceCredential);
        if (token == null || token.isBlank()
                || !MessageDigest.isEqual(
                        device.getCredentialHash().getBytes(StandardCharsets.US_ASCII),
                        hash(token).getBytes(StandardCharsets.US_ASCII))) {
            throw invalidDeviceCredential();
        }
        device.recordHeartbeat(healthy, message, Instant.now());
        return device;
    }

    @Transactional(readOnly = true)
    public void requireFeedingReady(UUID facilityId, UUID tankId) {
        requireTank(facilityId, tankId);
        DeviceHealth health = healthForTank(tankId, Instant.now());
        if (!health.feedingAllowed()) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "device_not_ready",
                    "Feeding is blocked because required tank hardware is not online and healthy");
        }
    }

    private DeviceHealth healthForTank(UUID tankId, Instant now) {
        Map<DeviceType, TankDevice> byType = new EnumMap<>(DeviceType.class);
        devices.findByTank_Id(tankId).forEach(device -> byType.put(device.getType(), device));
        List<DeviceComponentHealth> components = java.util.Arrays.stream(DeviceType.values())
                .map(type -> {
                    TankDevice device = byType.get(type);
                    return device == null
                            ? new DeviceComponentHealth(type, null, DeviceOperationalState.NOT_CONFIGURED, null, null)
                            : new DeviceComponentHealth(
                                    type,
                                    device.getId(),
                                    device.stateAt(now),
                                    device.getLastHeartbeatAt(),
                                    device.getStatusMessage());
                })
                .toList();
        DeviceOperationalState overall = aggregate(components);
        return new DeviceHealth(overall, overall == DeviceOperationalState.ONLINE, components);
    }

    private DeviceOperationalState aggregate(List<DeviceComponentHealth> components) {
        if (components.stream().anyMatch(item -> item.state() == DeviceOperationalState.NOT_CONFIGURED)) {
            return DeviceOperationalState.NOT_CONFIGURED;
        }
        if (components.stream().anyMatch(item -> item.state() == DeviceOperationalState.UNHEALTHY)) {
            return DeviceOperationalState.UNHEALTHY;
        }
        if (components.stream().anyMatch(item -> item.state() == DeviceOperationalState.OFFLINE)) {
            return DeviceOperationalState.OFFLINE;
        }
        if (components.stream().anyMatch(item -> item.state() == DeviceOperationalState.STALE)) {
            return DeviceOperationalState.STALE;
        }
        return DeviceOperationalState.ONLINE;
    }

    private FacilityMembership requireMembership(UUID userId, UUID facilityId) {
        return memberships.findByUser_IdAndFacility_Id(userId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND,
                        "facility_not_found",
                        "The aquarium was not found or is not accessible"));
    }

    private void requireOwner(UUID userId, UUID facilityId) {
        if (requireMembership(userId, facilityId).getRole() != FacilityRole.OWNER) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN,
                    "owner_required",
                    "Only an aquarium owner can provision tank hardware");
        }
    }

    private Tank requireTank(UUID facilityId, UUID tankId) {
        return tanks.findByIdAndFacility_Id(tankId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND, "tank_not_found", "The tank was not found"));
    }

    private FacilityException invalidDeviceCredential() {
        return new FacilityException(
                HttpStatus.UNAUTHORIZED,
                "invalid_device_credential",
                "The device credential is invalid");
    }

    private String newToken() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String hash(String token) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    public record DeviceComponentHealth(
            DeviceType type,
            UUID deviceId,
            DeviceOperationalState state,
            Instant lastHeartbeatAt,
            String message) {
    }

    public record DeviceHealth(
            DeviceOperationalState overallState,
            boolean feedingAllowed,
            List<DeviceComponentHealth> components) {
    }

    public record ProvisionedDevice(TankDevice device, String heartbeatToken) {
    }
}
