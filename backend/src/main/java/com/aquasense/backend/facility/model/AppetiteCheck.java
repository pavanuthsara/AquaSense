package com.aquasense.backend.facility.model;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import jakarta.persistence.*;

@Entity
@Table(name = "appetite_checks")
public class AppetiteCheck {
    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tank_id", nullable = false) private Tank tank;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "device_id", nullable = false) private TankDevice device;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 24) private AppetiteCheckStatus status;
    @Column(name = "requested_at", nullable = false) private Instant requestedAt;
    @Column(name = "expires_at", nullable = false) private Instant expiresAt;
    @Column(name = "started_at") private Instant startedAt;
    @Column(name = "completed_at") private Instant completedAt;
    @Column(name = "observed_at") private Instant observedAt;
    @Enumerated(EnumType.STRING)
    @Column(name = "appetite_result", length = 16) private AppetiteResult appetiteResult;
    @Column(precision = 5, scale = 4) private BigDecimal confidence;
    @Column(name = "model_version", length = 120) private String modelVersion;
    @Column(length = 500) private String message;

    protected AppetiteCheck() {}

    public AppetiteCheck(Tank tank, TankDevice device, Instant now) {
        this.id = UUID.randomUUID();
        this.tank = tank;
        this.device = device;
        this.status = AppetiteCheckStatus.PENDING;
        this.requestedAt = now;
        this.expiresAt = now.plusSeconds(60);
    }

    public void expireIfNeeded(Instant now) {
        if (status.isActive() && !now.isBefore(expiresAt)) {
            status = AppetiteCheckStatus.TIMED_OUT;
            completedAt = now;
            message = "No result received. Check that the laptop camera process is running, then try again.";
        }
    }

    public void start(Instant now) {
        if (status == AppetiteCheckStatus.PENDING) {
            status = AppetiteCheckStatus.CHECKING;
            startedAt = now;
        }
    }

    public void finish(AppetiteCheckStatus outcome, AppetiteResult label, BigDecimal probability,
            String version, Instant observationTime, String detail, Instant now) {
        status = outcome;
        appetiteResult = label;
        confidence = probability;
        modelVersion = version;
        observedAt = observationTime;
        message = detail;
        completedAt = now;
    }

    public UUID getId() { return id; }
    public Tank getTank() { return tank; }
    public TankDevice getDevice() { return device; }
    public AppetiteCheckStatus getStatus() { return status; }
    public Instant getRequestedAt() { return requestedAt; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getStartedAt() { return startedAt; }
    public Instant getCompletedAt() { return completedAt; }
    public Instant getObservedAt() { return observedAt; }
    public AppetiteResult getAppetiteResult() { return appetiteResult; }
    public BigDecimal getConfidence() { return confidence; }
    public String getModelVersion() { return modelVersion; }
    public String getMessage() { return message; }
}
