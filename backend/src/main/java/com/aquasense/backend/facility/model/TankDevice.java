package com.aquasense.backend.facility.model;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
        name = "tank_devices",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_tank_device_type",
                columnNames = {"tank_id", "device_type"}))
public class TankDevice {
    public static final Duration STALE_AFTER = Duration.ofMinutes(2);
    public static final Duration OFFLINE_AFTER = Duration.ofMinutes(10);

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tank_id", nullable = false)
    private Tank tank;

    @Enumerated(EnumType.STRING)
    @Column(name = "device_type", nullable = false, length = 32)
    private DeviceType type;

    @Column(name = "credential_hash", nullable = false, length = 64)
    private String credentialHash;

    @Column(name = "reported_healthy")
    private Boolean reportedHealthy;

    @Column(name = "status_message", length = 500)
    private String statusMessage;

    @Column(name = "last_heartbeat_at")
    private Instant lastHeartbeatAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected TankDevice() {
    }

    public TankDevice(Tank tank, DeviceType type, String credentialHash, Instant now) {
        this.id = UUID.randomUUID();
        this.tank = tank;
        this.type = type;
        this.credentialHash = credentialHash;
        this.createdAt = now;
        this.updatedAt = now;
    }

    public void rotateCredential(String credentialHash, Instant now) {
        this.credentialHash = credentialHash;
        this.reportedHealthy = null;
        this.statusMessage = null;
        this.lastHeartbeatAt = null;
        this.updatedAt = now;
    }

    public void recordHeartbeat(boolean healthy, String message, Instant now) {
        this.reportedHealthy = healthy;
        this.statusMessage = message == null || message.isBlank() ? null : message.trim();
        this.lastHeartbeatAt = now;
        this.updatedAt = now;
    }

    public DeviceOperationalState stateAt(Instant now) {
        if (lastHeartbeatAt == null || !lastHeartbeatAt.isAfter(now.minus(OFFLINE_AFTER))) {
            return DeviceOperationalState.OFFLINE;
        }
        if (!lastHeartbeatAt.isAfter(now.minus(STALE_AFTER))) {
            return DeviceOperationalState.STALE;
        }
        return Boolean.FALSE.equals(reportedHealthy)
                ? DeviceOperationalState.UNHEALTHY
                : DeviceOperationalState.ONLINE;
    }

    public UUID getId() { return id; }
    public Tank getTank() { return tank; }
    public DeviceType getType() { return type; }
    public String getCredentialHash() { return credentialHash; }
    public Boolean getReportedHealthy() { return reportedHealthy; }
    public String getStatusMessage() { return statusMessage; }
    public Instant getLastHeartbeatAt() { return lastHeartbeatAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
