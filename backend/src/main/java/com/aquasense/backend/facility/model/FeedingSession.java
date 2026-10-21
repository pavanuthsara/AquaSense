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
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
        name = "feeding_sessions",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_feeding_session_occurrence",
                columnNames = {"tank_id", "scheduled_for"}))
public class FeedingSession {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tank_id", nullable = false)
    private Tank tank;

    @Column(name = "scheduled_for", nullable = false)
    private Instant scheduledFor;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 48)
    private FeedingOutcome outcome;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private FeedingSource source;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "observation_id")
    private AppetiteObservation observation;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "calibration_id")
    private FeederCalibration calibration;

    @Column(name = "portion_units", precision = 12, scale = 4)
    private BigDecimal portionUnits;

    @Column(name = "command_sent_at")
    private Instant commandSentAt;

    @Column(name = "feedback_at")
    private Instant feedbackAt;

    @Column(name = "failure_reason", length = 500)
    private String failureReason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected FeedingSession() {
    }

    public FeedingSession(Tank tank, Instant scheduledFor, Instant now) {
        this.id = UUID.randomUUID();
        this.tank = tank;
        this.scheduledFor = scheduledFor;
        this.outcome = FeedingOutcome.PROCESSING;
        this.source = FeedingSource.SCHEDULED;
        this.createdAt = now;
        this.updatedAt = now;
    }

    public void stop(FeedingOutcome outcome, AppetiteObservation observation, String reason, Instant now) {
        this.outcome = outcome;
        this.observation = observation;
        this.failureReason = reason;
        this.updatedAt = now;
    }

    public void sendCommand(
            AppetiteObservation observation,
            FeederCalibration calibration,
            BigDecimal portionUnits,
            Instant now) {
        this.outcome = FeedingOutcome.COMMAND_SENT;
        this.observation = observation;
        this.calibration = calibration;
        this.portionUnits = portionUnits;
        this.commandSentAt = now;
        this.updatedAt = now;
    }

    public void recordFeedback(boolean delivered, String reason, Instant now) {
        this.outcome = delivered ? FeedingOutcome.DELIVERED : FeedingOutcome.FAILED;
        this.feedbackAt = now;
        this.failureReason = delivered ? null : reason;
        this.updatedAt = now;
    }

    public UUID getId() { return id; }
    public Tank getTank() { return tank; }
    public Instant getScheduledFor() { return scheduledFor; }
    public FeedingOutcome getOutcome() { return outcome; }
    public FeedingSource getSource() { return source; }
    public AppetiteObservation getObservation() { return observation; }
    public FeederCalibration getCalibration() { return calibration; }
    public BigDecimal getPortionUnits() { return portionUnits; }
    public Instant getCommandSentAt() { return commandSentAt; }
    public Instant getFeedbackAt() { return feedbackAt; }
    public String getFailureReason() { return failureReason; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
