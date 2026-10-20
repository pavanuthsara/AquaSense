package com.aquasense.backend.facility.model;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
        name = "feeder_calibrations",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_feeder_calibration_version",
                columnNames = {"facility_id", "version"}))
public class FeederCalibration {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "facility_id", nullable = false)
    private Facility facility;

    @Column(nullable = false)
    private int version;

    @Column(name = "units_per_fish", nullable = false, precision = 12, scale = 4)
    private BigDecimal unitsPerFish;

    @Column(name = "minimum_units", nullable = false, precision = 12, scale = 4)
    private BigDecimal minimumUnits;

    @Column(name = "maximum_units", nullable = false, precision = 12, scale = 4)
    private BigDecimal maximumUnits;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "created_by_user_id", nullable = false)
    private AppUser createdBy;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected FeederCalibration() {
    }

    public FeederCalibration(
            Facility facility,
            int version,
            BigDecimal unitsPerFish,
            BigDecimal minimumUnits,
            BigDecimal maximumUnits,
            AppUser createdBy,
            Instant createdAt) {
        this.id = UUID.randomUUID();
        this.facility = facility;
        this.version = version;
        this.unitsPerFish = unitsPerFish;
        this.minimumUnits = minimumUnits;
        this.maximumUnits = maximumUnits;
        this.createdBy = createdBy;
        this.createdAt = createdAt;
    }

    public UUID getId() { return id; }
    public Facility getFacility() { return facility; }
    public int getVersion() { return version; }
    public BigDecimal getUnitsPerFish() { return unitsPerFish; }
    public BigDecimal getMinimumUnits() { return minimumUnits; }
    public BigDecimal getMaximumUnits() { return maximumUnits; }
    public AppUser getCreatedBy() { return createdBy; }
    public Instant getCreatedAt() { return createdAt; }
}
