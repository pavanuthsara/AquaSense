package com.aquasense.backend.facility.model;

import java.time.Instant;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
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
        name = "facility_memberships",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_facility_membership",
                columnNames = {"facility_id", "user_id"}))
public class FacilityMembership {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "facility_id", nullable = false)
    private Facility facility;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private AppUser user;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private FacilityRole role;

    @Column(name = "joined_at", nullable = false)
    private Instant joinedAt;

    protected FacilityMembership() {
    }

    public FacilityMembership(Facility facility, AppUser user, FacilityRole role, Instant now) {
        this.id = UUID.randomUUID();
        this.facility = facility;
        this.user = user;
        this.role = role;
        this.joinedAt = now;
    }

    public Facility getFacility() { return facility; }
    public FacilityRole getRole() { return role; }
    public Instant getJoinedAt() { return joinedAt; }
}
