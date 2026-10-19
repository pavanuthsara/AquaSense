package com.aquasense.backend.facility.model;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
        name = "tanks",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_tank_facility_code",
                columnNames = {"facility_id", "normalized_code"}))
public class Tank {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "facility_id", nullable = false)
    private Facility facility;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "group_id")
    private TankGroup group;

    @Column(nullable = false, length = 120)
    private String name;

    @Column(nullable = false, length = 64)
    private String code;

    @Column(name = "normalized_code", nullable = false, length = 64)
    private String normalizedCode;

    @Column(name = "expected_guppy_count", nullable = false)
    private int expectedGuppyCount;

    @Column(name = "detected_guppy_count")
    private Integer detectedGuppyCount;

    @Column(name = "detection_confidence", precision = 5, scale = 4)
    private BigDecimal detectionConfidence;

    @Column(name = "count_observed_at")
    private Instant countObservedAt;

    @Column(name = "automation_enabled", nullable = false)
    private boolean automationEnabled;

    @Column(length = 2000)
    private String notes;

    @ElementCollection(fetch = FetchType.LAZY)
    @CollectionTable(name = "tank_tags", joinColumns = @JoinColumn(name = "tank_id"))
    @Column(name = "tag", nullable = false, length = 40)
    private Set<String> tags = new LinkedHashSet<>();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "archived_at")
    private Instant archivedAt;

    protected Tank() {
    }

    public Tank(
            Facility facility,
            TankGroup group,
            String name,
            String code,
            String normalizedCode,
            int expectedGuppyCount,
            Set<String> tags,
            boolean automationEnabled,
            String notes,
            Instant now) {
        this.id = UUID.randomUUID();
        this.facility = facility;
        this.group = group;
        this.name = name;
        this.code = code;
        this.normalizedCode = normalizedCode;
        this.expectedGuppyCount = expectedGuppyCount;
        this.tags = new LinkedHashSet<>(tags);
        this.automationEnabled = automationEnabled;
        this.notes = notes;
        this.createdAt = now;
        this.updatedAt = now;
    }

    public void update(
            TankGroup group,
            String name,
            String code,
            String normalizedCode,
            int expectedGuppyCount,
            Set<String> tags,
            boolean automationEnabled,
            String notes,
            Instant now) {
        this.group = group;
        this.name = name;
        this.code = code;
        this.normalizedCode = normalizedCode;
        this.expectedGuppyCount = expectedGuppyCount;
        this.tags.clear();
        this.tags.addAll(tags);
        this.automationEnabled = automationEnabled;
        this.notes = notes;
        this.updatedAt = now;
    }

    public void archive(Instant now) {
        this.automationEnabled = false;
        this.archivedAt = now;
        this.updatedAt = now;
    }

    public UUID getId() { return id; }
    public Facility getFacility() { return facility; }
    public TankGroup getGroup() { return group; }
    public String getName() { return name; }
    public String getCode() { return code; }
    public String getNormalizedCode() { return normalizedCode; }
    public int getExpectedGuppyCount() { return expectedGuppyCount; }
    public Integer getDetectedGuppyCount() { return detectedGuppyCount; }
    public BigDecimal getDetectionConfidence() { return detectionConfidence; }
    public Instant getCountObservedAt() { return countObservedAt; }
    public boolean isAutomationEnabled() { return automationEnabled; }
    public String getNotes() { return notes; }
    public Set<String> getTags() { return Set.copyOf(tags); }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public Instant getArchivedAt() { return archivedAt; }
    public boolean isArchived() { return archivedAt != null; }
}
