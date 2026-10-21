package com.aquasense.backend.export.model;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** A saved transit advisory (packing plan) for one planned shipment. */
@Entity
@Table(name = "export_advisories")
public class ExportAdvisory {
    @Id
    private UUID id;

    @Column(name = "facility_id", nullable = false)
    private UUID facilityId;

    @Column(name = "created_by_user_id", nullable = false)
    private UUID createdByUserId;

    @Column(length = 120)
    private String label;

    @Column(nullable = false, length = 40)
    private String species;

    @Column(name = "duration_hours", nullable = false)
    private double durationHours;

    @Column(nullable = false)
    private boolean feasible;

    @Column(name = "fish_per_bag")
    private Integer fishPerBag;

    @Column(name = "bags_needed")
    private Integer bagsNeeded;

    @Column(name = "survival_pct")
    private Double survivalPct;

    @Column(name = "worst_survival_pct")
    private Double worstSurvivalPct;

    @Column(name = "request_json", nullable = false, length = 20000)
    private String requestJson;

    @Column(name = "advisory_json", nullable = false, length = 400000)
    private String advisoryJson;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected ExportAdvisory() {
    }

    public ExportAdvisory(
            UUID facilityId,
            UUID createdByUserId,
            String label,
            String species,
            double durationHours,
            boolean feasible,
            Integer fishPerBag,
            Integer bagsNeeded,
            Double survivalPct,
            Double worstSurvivalPct,
            String requestJson,
            String advisoryJson,
            Instant createdAt) {
        this.id = UUID.randomUUID();
        this.facilityId = facilityId;
        this.createdByUserId = createdByUserId;
        this.label = label;
        this.species = species;
        this.durationHours = durationHours;
        this.feasible = feasible;
        this.fishPerBag = fishPerBag;
        this.bagsNeeded = bagsNeeded;
        this.survivalPct = survivalPct;
        this.worstSurvivalPct = worstSurvivalPct;
        this.requestJson = requestJson;
        this.advisoryJson = advisoryJson;
        this.createdAt = createdAt;
    }

    public UUID getId() { return id; }
    public UUID getFacilityId() { return facilityId; }
    public UUID getCreatedByUserId() { return createdByUserId; }
    public String getLabel() { return label; }
    public String getSpecies() { return species; }
    public double getDurationHours() { return durationHours; }
    public boolean isFeasible() { return feasible; }
    public Integer getFishPerBag() { return fishPerBag; }
    public Integer getBagsNeeded() { return bagsNeeded; }
    public Double getSurvivalPct() { return survivalPct; }
    public Double getWorstSurvivalPct() { return worstSurvivalPct; }
    public String getRequestJson() { return requestJson; }
    public String getAdvisoryJson() { return advisoryJson; }
    public Instant getCreatedAt() { return createdAt; }
}
