package com.aquasense.backend.facility.service;

import java.time.DateTimeException;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FacilityService {
    private final AppUserRepository users;
    private final FacilityRepository facilities;
    private final FacilityMembershipRepository memberships;

    public FacilityService(
            AppUserRepository users,
            FacilityRepository facilities,
            FacilityMembershipRepository memberships) {
        this.users = users;
        this.facilities = facilities;
        this.memberships = memberships;
    }

    @Transactional
    public CreationResult create(UUID userId, String requestKey, String requestedName, String requestedTimeZone) {
        AppUser owner = users.findByIdForUpdate(userId)
                .orElseThrow(() -> new AuthenticationFailureException("The authenticated user no longer exists"));
        String name = requestedName.trim();
        String timeZone = validTimeZone(requestedTimeZone.trim());
        String normalizedKey = requestKey.trim();

        return facilities.findByCreatedBy_IdAndCreationRequestKey(userId, normalizedKey)
                .map(existing -> {
                    if (!existing.getName().equals(name) || !existing.getTimeZone().equals(timeZone)) {
                        throw new FacilityException(
                                HttpStatus.CONFLICT,
                                "idempotency_conflict",
                                "That creation request key was already used with different aquarium details");
                    }
                    FacilityMembership membership = memberships
                            .findByUser_IdAndFacility_Id(userId, existing.getId())
                            .orElseThrow(() -> new IllegalStateException("Facility owner membership is missing"));
                    return new CreationResult(membership, false);
                })
                .orElseGet(() -> {
                    Instant now = Instant.now();
                    Facility facility = facilities.save(
                            new Facility(owner, name, timeZone, normalizedKey, now));
                    FacilityMembership membership = memberships.save(
                            new FacilityMembership(facility, owner, FacilityRole.OWNER, now));
                    return new CreationResult(membership, true);
                });
    }

    @Transactional(readOnly = true)
    public List<FacilityMembership> list(UUID userId) {
        return memberships.findAllByUser_IdOrderByJoinedAtAsc(userId);
    }

    @Transactional(readOnly = true)
    public FacilityMembership get(UUID userId, UUID facilityId) {
        return memberships.findByUser_IdAndFacility_Id(userId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND,
                        "facility_not_found",
                        "The aquarium was not found or is not accessible"));
    }

    public List<String> listTimeZones() {
        return ZoneId.getAvailableZoneIds().stream().sorted().toList();
    }

    private String validTimeZone(String timeZone) {
        try {
            return ZoneId.of(timeZone).getId();
        } catch (DateTimeException exception) {
            throw new FacilityException(
                    HttpStatus.BAD_REQUEST,
                    "invalid_time_zone",
                    "Select a valid IANA time zone");
        }
    }

    public record CreationResult(FacilityMembership membership, boolean created) {
    }
}
