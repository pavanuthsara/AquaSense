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

@Entity
@Table(name = "facility_invitations")
public class FacilityInvitation {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "facility_id", nullable = false)
    private Facility facility;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "invited_by_user_id", nullable = false)
    private AppUser invitedBy;

    @Column(nullable = false, length = 320)
    private String email;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private InvitationStatus status;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "accepted_by_user_id")
    private AppUser acceptedBy;

    @Column(name = "accepted_at")
    private Instant acceptedAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    protected FacilityInvitation() {
    }

    public FacilityInvitation(
            Facility facility,
            AppUser invitedBy,
            String email,
            Instant createdAt,
            Instant expiresAt) {
        this.id = UUID.randomUUID();
        this.facility = facility;
        this.invitedBy = invitedBy;
        this.email = email;
        this.status = InvitationStatus.PENDING;
        this.createdAt = createdAt;
        this.expiresAt = expiresAt;
    }

    public void accept(AppUser user, Instant now) {
        this.status = InvitationStatus.ACCEPTED;
        this.acceptedBy = user;
        this.acceptedAt = now;
    }

    public void revoke(Instant now) {
        this.status = InvitationStatus.REVOKED;
        this.revokedAt = now;
    }

    public void expire() {
        this.status = InvitationStatus.EXPIRED;
    }

    public boolean isExpiredAt(Instant now) {
        return !expiresAt.isAfter(now);
    }

    public UUID getId() { return id; }
    public Facility getFacility() { return facility; }
    public AppUser getInvitedBy() { return invitedBy; }
    public String getEmail() { return email; }
    public InvitationStatus getStatus() { return status; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getCreatedAt() { return createdAt; }
    public AppUser getAcceptedBy() { return acceptedBy; }
    public Instant getAcceptedAt() { return acceptedAt; }
    public Instant getRevokedAt() { return revokedAt; }
}
