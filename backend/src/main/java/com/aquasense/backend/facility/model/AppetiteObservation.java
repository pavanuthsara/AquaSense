package com.aquasense.backend.facility.model;

import java.math.BigDecimal;
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

@Entity
@Table(name = "appetite_observations")
public class AppetiteObservation {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tank_id", nullable = false)
    private Tank tank;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "source_device_id", nullable = false)
    private TankDevice sourceDevice;

    @Column(name = "detected_guppy_count", nullable = false)
    private int detectedGuppyCount;

    @Column(nullable = false, precision = 5, scale = 4)
    private BigDecimal confidence;

    @Enumerated(EnumType.STRING)
    @Column(name = "appetite_result", nullable = false, length = 16)
    private AppetiteResult appetiteResult;

    @Column(name = "model_version", nullable = false, length = 120)
    private String modelVersion;

    @Column(name = "observed_at", nullable = false)
    private Instant observedAt;

    @Column(name = "received_at", nullable = false)
    private Instant receivedAt;

    @Column(nullable = false)
    private boolean stale;

    @Column(name = "low_confidence", nullable = false)
    private boolean lowConfidence;

    @Column(name = "count_inconsistent", nullable = false)
    private boolean countInconsistent;

    @Column(name = "valid_for_feeding_decision", nullable = false)
    private boolean validForFeedingDecision;

    protected AppetiteObservation() {
    }

    public AppetiteObservation(
            Tank tank,
            TankDevice sourceDevice,
            int detectedGuppyCount,
            BigDecimal confidence,
            AppetiteResult appetiteResult,
            String modelVersion,
            Instant observedAt,
            Instant receivedAt,
            boolean stale,
            boolean lowConfidence,
            boolean countInconsistent) {
        this.id = UUID.randomUUID();
        this.tank = tank;
        this.sourceDevice = sourceDevice;
        this.detectedGuppyCount = detectedGuppyCount;
        this.confidence = confidence;
        this.appetiteResult = appetiteResult;
        this.modelVersion = modelVersion;
        this.observedAt = observedAt;
        this.receivedAt = receivedAt;
        this.stale = stale;
        this.lowConfidence = lowConfidence;
        this.countInconsistent = countInconsistent;
        this.validForFeedingDecision = !stale && !lowConfidence && !countInconsistent;
    }

    public UUID getId() { return id; }
    public Tank getTank() { return tank; }
    public TankDevice getSourceDevice() { return sourceDevice; }
    public int getDetectedGuppyCount() { return detectedGuppyCount; }
    public BigDecimal getConfidence() { return confidence; }
    public AppetiteResult getAppetiteResult() { return appetiteResult; }
    public String getModelVersion() { return modelVersion; }
    public Instant getObservedAt() { return observedAt; }
    public Instant getReceivedAt() { return receivedAt; }
    public boolean isStale() { return stale; }
    public boolean isLowConfidence() { return lowConfidence; }
    public boolean isCountInconsistent() { return countInconsistent; }
    public boolean isValidForFeedingDecision() { return validForFeedingDecision; }
}
