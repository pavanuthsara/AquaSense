package com.aquasense.backend.facility.model;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "tank_groups")
public class TankGroup {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "facility_id", nullable = false)
    private Facility facility;

    @Column(nullable = false, length = 80)
    private String name;

    @Column(name = "normalized_name", nullable = false, length = 80)
    private String normalizedName;

    @Column(name = "tank_count", nullable = false)
    private int tankCount;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "archived_at")
    private Instant archivedAt;

    protected TankGroup() {
    }

    public TankGroup(Facility facility, String name, String normalizedName, Instant now) {
        this.id = UUID.randomUUID();
        this.facility = facility;
        this.name = name;
        this.normalizedName = normalizedName;
        this.tankCount = 0;
        this.createdAt = now;
        this.updatedAt = now;
    }

    public void rename(String name, String normalizedName, Instant now) {
        this.name = name;
        this.normalizedName = normalizedName;
        this.updatedAt = now;
    }

    public void archive(Instant now) {
        this.archivedAt = now;
        this.updatedAt = now;
    }

    public UUID getId() { return id; }
    public Facility getFacility() { return facility; }
    public String getName() { return name; }
    public String getNormalizedName() { return normalizedName; }
    public int getTankCount() { return tankCount; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public Instant getArchivedAt() { return archivedAt; }
    public boolean isArchived() { return archivedAt != null; }
}
