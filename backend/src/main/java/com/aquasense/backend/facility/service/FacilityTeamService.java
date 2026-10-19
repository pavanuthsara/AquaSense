package com.aquasense.backend.facility.service;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.FacilityInvitation;
import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.model.InvitationStatus;
import com.aquasense.backend.facility.repository.FacilityInvitationRepository;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FacilityTeamService {
    private static final Duration INVITATION_TTL = Duration.ofDays(7);

    private final AppUserRepository users;
    private final FacilityRepository facilities;
    private final FacilityMembershipRepository memberships;
    private final FacilityInvitationRepository invitations;

    public FacilityTeamService(
            AppUserRepository users,
            FacilityRepository facilities,
            FacilityMembershipRepository memberships,
            FacilityInvitationRepository invitations) {
        this.users = users;
        this.facilities = facilities;
        this.memberships = memberships;
        this.invitations = invitations;
    }

    @Transactional(readOnly = true)
    public List<FacilityMembership> listMembers(UUID userId, UUID facilityId) {
        requireMembership(userId, facilityId);
        return memberships.findAllByFacility_IdOrderByJoinedAtAsc(facilityId);
    }

    @Transactional
    public List<FacilityInvitation> listFacilityInvitations(UUID userId, UUID facilityId) {
        requireOwner(userId, facilityId);
        List<FacilityInvitation> results = invitations.findAllByFacility_IdOrderByCreatedAtDesc(facilityId);
        expirePending(results, Instant.now());
        return results;
    }

    @Transactional
    public FacilityInvitation invite(UUID userId, UUID facilityId, String requestedEmail) {
        requireOwner(userId, facilityId);
        Facility facility = facilities.findByIdForUpdate(facilityId)
                .orElseThrow(() -> notFound());
        AppUser inviter = requireUser(userId);
        String email = normalizeEmail(requestedEmail);
        Instant now = Instant.now();

        if (memberships.existsByFacility_IdAndUser_EmailIgnoreCase(facilityId, email)) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "already_a_member",
                    "That email already belongs to this aquarium");
        }

        invitations.findFirstByFacility_IdAndEmailIgnoreCaseAndStatusOrderByCreatedAtDesc(
                        facilityId, email, InvitationStatus.PENDING)
                .ifPresent(existing -> {
                    if (existing.isExpiredAt(now)) {
                        existing.expire();
                    } else {
                        throw new FacilityException(
                                HttpStatus.CONFLICT,
                                "invitation_already_pending",
                                "An active invitation already exists for that email");
                    }
                });

        return invitations.save(new FacilityInvitation(
                facility,
                inviter,
                email,
                now,
                now.plus(INVITATION_TTL)));
    }

    @Transactional
    public void revokeInvitation(UUID userId, UUID facilityId, UUID invitationId) {
        requireOwner(userId, facilityId);
        FacilityInvitation invitation = invitations.findByIdForUpdate(invitationId)
                .filter(item -> item.getFacility().getId().equals(facilityId))
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND,
                        "invitation_not_found",
                        "The invitation was not found"));

        if (invitation.getStatus() == InvitationStatus.REVOKED
                || invitation.getStatus() == InvitationStatus.EXPIRED) {
            return;
        }
        if (invitation.getStatus() == InvitationStatus.ACCEPTED) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "invitation_already_accepted",
                    "Remove the worker membership instead of revoking an accepted invitation");
        }
        Instant now = Instant.now();
        if (invitation.isExpiredAt(now)) {
            invitation.expire();
        } else {
            invitation.revoke(now);
        }
    }

    @Transactional
    public List<FacilityInvitation> listMyPendingInvitations(UUID userId) {
        AppUser user = requireUser(userId);
        List<FacilityInvitation> results = invitations
                .findAllByEmailIgnoreCaseAndStatusOrderByCreatedAtAsc(
                        normalizeEmail(user.getEmail()), InvitationStatus.PENDING);
        Instant now = Instant.now();
        expirePending(results, now);
        return results.stream()
                .filter(invitation -> invitation.getStatus() == InvitationStatus.PENDING)
                .toList();
    }

    @Transactional
    public FacilityMembership accept(UUID userId, UUID invitationId) {
        AppUser user = requireUser(userId);
        FacilityInvitation invitation = invitations.findByIdForUpdate(invitationId)
                .orElseThrow(() -> invitationNotFound());

        if (!invitation.getEmail().equalsIgnoreCase(user.getEmail())) {
            throw invitationNotFound();
        }

        if (invitation.getStatus() == InvitationStatus.ACCEPTED) {
            if (invitation.getAcceptedBy() == null
                    || !invitation.getAcceptedBy().getId().equals(userId)) {
                throw invitationNotFound();
            }
            return memberships.findByUser_IdAndFacility_Id(userId, invitation.getFacility().getId())
                    .orElseThrow(() -> new IllegalStateException("Accepted invitation membership is missing"));
        }

        if (invitation.getStatus() != InvitationStatus.PENDING) {
            throw new FacilityException(
                    HttpStatus.GONE,
                    "invitation_unavailable",
                    "That invitation is no longer available");
        }

        Instant now = Instant.now();
        if (invitation.isExpiredAt(now)) {
            throw new FacilityException(
                    HttpStatus.GONE,
                    "invitation_expired",
                    "That invitation has expired");
        }

        Facility facility = invitation.getFacility();
        FacilityMembership membership = memberships.findByUser_IdAndFacility_Id(userId, facility.getId())
                .orElseGet(() -> memberships.save(
                        new FacilityMembership(facility, user, FacilityRole.WORKER, now)));
        invitation.accept(user, now);
        return membership;
    }

    @Transactional
    public void removeWorker(UUID userId, UUID facilityId, UUID membershipId) {
        requireOwner(userId, facilityId);
        FacilityMembership membership = memberships.findByIdAndFacility_Id(membershipId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND,
                        "membership_not_found",
                        "The worker membership was not found"));
        if (membership.getRole() == FacilityRole.OWNER) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "owner_membership_required",
                    "The aquarium owner cannot be removed");
        }
        memberships.delete(membership);
    }

    private FacilityMembership requireMembership(UUID userId, UUID facilityId) {
        return memberships.findByUser_IdAndFacility_Id(userId, facilityId)
                .orElseThrow(() -> notFound());
    }

    private FacilityMembership requireOwner(UUID userId, UUID facilityId) {
        FacilityMembership membership = requireMembership(userId, facilityId);
        if (membership.getRole() != FacilityRole.OWNER) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN,
                    "owner_required",
                    "Only an aquarium owner can perform this action");
        }
        return membership;
    }

    private AppUser requireUser(UUID userId) {
        return users.findById(userId)
                .orElseThrow(() -> new AuthenticationFailureException("The authenticated user no longer exists"));
    }

    private void expirePending(List<FacilityInvitation> results, Instant now) {
        results.stream()
                .filter(invitation -> invitation.getStatus() == InvitationStatus.PENDING)
                .filter(invitation -> invitation.isExpiredAt(now))
                .forEach(FacilityInvitation::expire);
    }

    private String normalizeEmail(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }

    private FacilityException notFound() {
        return new FacilityException(
                HttpStatus.NOT_FOUND,
                "facility_not_found",
                "The aquarium was not found or is not accessible");
    }

    private FacilityException invitationNotFound() {
        return new FacilityException(
                HttpStatus.NOT_FOUND,
                "invitation_not_found",
                "The invitation was not found");
    }
}
