package com.aquasense.backend.facility.model;

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
        name = "facilities",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_facility_creation_request",
                columnNames = {"created_by_user_id", "creation_request_key"}))
public class Facility {
    @Id
    private UUID id;

    @Column(nullable = false, length = 120)
    private String name;

    @Column(name = "time_zone", nullable = false, length = 64)
    private String timeZone;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "created_by_user_id", nullable = false)
    private AppUser createdBy;

    @Column(name = "creation_request_key", nullable = false, length = 128)
    private String creationRequestKey;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected Facility() {
    }

    public Facility(AppUser createdBy, String name, String timeZone, String creationRequestKey, Instant now) {
        this.id = UUID.randomUUID();
        this.createdBy = createdBy;
        this.name = name;
        this.timeZone = timeZone;
        this.creationRequestKey = creationRequestKey;
        this.createdAt = now;
    }

    public UUID getId() { return id; }
    public String getName() { return name; }
    public String getTimeZone() { return timeZone; }
    public AppUser getCreatedBy() { return createdBy; }
    public String getCreationRequestKey() { return creationRequestKey; }
    public Instant getCreatedAt() { return createdAt; }
}
