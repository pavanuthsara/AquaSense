package com.aquasense.backend.facility.web;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.DeviceOperationalState;
import com.aquasense.backend.facility.model.DeviceType;
import com.aquasense.backend.facility.model.TankDevice;
import com.aquasense.backend.facility.service.DeviceHealthService;
import com.aquasense.backend.facility.service.DeviceHealthService.DeviceComponentHealth;
import com.aquasense.backend.facility.service.DeviceHealthService.DeviceHealth;
import com.aquasense.backend.facility.service.DeviceHealthService.ProvisionedDevice;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DeviceHealthController {
    private final DeviceHealthService service;

    public DeviceHealthController(DeviceHealthService service) {
        this.service = service;
    }

    @GetMapping("/api/v1/facilities/{facilityId}/tanks/{tankId}/device-health")
    DeviceHealthResponse get(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId) {
        return DeviceHealthResponse.from(service.health(userId(jwt), facilityId, tankId));
    }

    @PostMapping("/api/v1/facilities/{facilityId}/tanks/{tankId}/devices/{type}/provision")
    @ResponseStatus(HttpStatus.CREATED)
    ProvisionedDeviceResponse provision(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID tankId,
            @PathVariable DeviceType type) {
        return ProvisionedDeviceResponse.from(service.provision(userId(jwt), facilityId, tankId, type));
    }

    @PostMapping("/api/v1/device-heartbeats")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void heartbeat(
            @RequestHeader("X-Device-Id") UUID deviceId,
            @RequestHeader("X-Device-Token") String token,
            @Valid @RequestBody HeartbeatRequest request) {
        service.heartbeat(deviceId, token, request.healthy(), request.message());
    }

    private UUID userId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }

    public record HeartbeatRequest(@NotNull Boolean healthy, @Size(max = 500) String message) {
    }

    public record DeviceComponentResponse(
            DeviceType type,
            UUID deviceId,
            DeviceOperationalState state,
            Instant lastHeartbeatAt,
            String message) {
        static DeviceComponentResponse from(DeviceComponentHealth health) {
            return new DeviceComponentResponse(
                    health.type(), health.deviceId(), health.state(), health.lastHeartbeatAt(), health.message());
        }
    }

    public record DeviceHealthResponse(
            DeviceOperationalState overallState,
            boolean feedingAllowed,
            List<DeviceComponentResponse> components) {
        static DeviceHealthResponse from(DeviceHealth health) {
            return new DeviceHealthResponse(
                    health.overallState(),
                    health.feedingAllowed(),
                    health.components().stream().map(DeviceComponentResponse::from).toList());
        }
    }

    public record ProvisionedDeviceResponse(
            UUID deviceId,
            DeviceType type,
            String heartbeatToken,
            Instant createdAt) {
        static ProvisionedDeviceResponse from(ProvisionedDevice provisioned) {
            TankDevice device = provisioned.device();
            return new ProvisionedDeviceResponse(
                    device.getId(), device.getType(), provisioned.heartbeatToken(), device.getCreatedAt());
        }
    }
}
