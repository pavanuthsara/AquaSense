package com.aquasense.backend.disease.model;

import java.time.Instant;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.facility.model.Facility;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

/** One saved result of the guppy disease check for an aquarium facility. */
@Entity
@Table(
        name = "disease_checks",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_disease_check_request",
                columnNames = {"checked_by_user_id", "request_key"}))
public class DiseaseCheck {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "facility_id", nullable = false)
    private Facility facility;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "checked_by_user_id", nullable = false)
    private AppUser checkedBy;

    @Column(name = "request_key", nullable = false, length = 128)
    private String requestKey;

    @Column(name = "predicted_label", nullable = false, length = 40)
    private String predictedLabel;

    @Column(nullable = false)
    private double confidence;

    @Column(nullable = false)
    private boolean uncertain;

    @Column(name = "model_version", nullable = false, length = 64)
    private String modelVersion;

    @Column(name = "tank_label", length = 80)
    private String tankLabel;

    @Column(length = 500)
    private String note;

    @Column(name = "checked_at", nullable = false)
    private Instant checkedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected DiseaseCheck() {
    }

    public DiseaseCheck(
            Facility facility,
            AppUser checkedBy,
            String requestKey,
            String predictedLabel,
            double confidence,
            boolean uncertain,
            String modelVersion,
            String tankLabel,
            String note,
            Instant checkedAt,
            Instant now) {
        this.id = UUID.randomUUID();
        this.facility = facility;
        this.checkedBy = checkedBy;
        this.requestKey = requestKey;
        this.predictedLabel = predictedLabel;
        this.confidence = confidence;
        this.uncertain = uncertain;
        this.modelVersion = modelVersion;
        this.tankLabel = tankLabel;
        this.note = note;
        this.checkedAt = checkedAt;
        this.createdAt = now;
    }

    public UUID getId() { return id; }
    public Facility getFacility() { return facility; }
    public AppUser getCheckedBy() { return checkedBy; }
    public String getRequestKey() { return requestKey; }
    public String getPredictedLabel() { return predictedLabel; }
    public double getConfidence() { return confidence; }
    public boolean isUncertain() { return uncertain; }
    public String getModelVersion() { return modelVersion; }
    public String getTankLabel() { return tankLabel; }
    public String getNote() { return note; }
    public Instant getCheckedAt() { return checkedAt; }
    public Instant getCreatedAt() { return createdAt; }
}
