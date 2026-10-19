package com.aquasense.backend.facility.service;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.model.TankGroup;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.aquasense.backend.facility.repository.TankGroupRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TankGroupService {
    private static final Comparator<TankGroup> GROUP_ORDER = Comparator
            .comparing(TankGroup::isArchived)
            .thenComparing(TankGroup::getName, String.CASE_INSENSITIVE_ORDER);

    private final FacilityRepository facilities;
    private final FacilityMembershipRepository memberships;
    private final TankGroupRepository groups;

    public TankGroupService(
            FacilityRepository facilities,
            FacilityMembershipRepository memberships,
            TankGroupRepository groups) {
        this.facilities = facilities;
        this.memberships = memberships;
        this.groups = groups;
    }

    @Transactional(readOnly = true)
    public List<TankGroup> list(UUID userId, UUID facilityId) {
        requireMembership(userId, facilityId);
        return groups.findAllByFacility_IdOrderByNameAsc(facilityId).stream()
                .sorted(GROUP_ORDER)
                .toList();
    }

    @Transactional
    public TankGroup create(UUID userId, UUID facilityId, String requestedName) {
        requireOwner(userId, facilityId);
        Facility facility = lockFacility(facilityId);
        String name = cleanName(requestedName);
        String normalizedName = normalizeName(name);
        rejectDuplicate(facilityId, normalizedName, null);
        return groups.save(new TankGroup(facility, name, normalizedName, Instant.now()));
    }

    @Transactional
    public TankGroup rename(UUID userId, UUID facilityId, UUID groupId, String requestedName) {
        requireOwner(userId, facilityId);
        lockFacility(facilityId);
        TankGroup group = lockGroup(facilityId, groupId);
        if (group.isArchived()) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "group_archived",
                    "An archived tank group cannot be renamed");
        }
        String name = cleanName(requestedName);
        String normalizedName = normalizeName(name);
        rejectDuplicate(facilityId, normalizedName, groupId);
        if (!group.getName().equals(name)) {
            group.rename(name, normalizedName, Instant.now());
        }
        return group;
    }

    @Transactional
    public TankGroup archive(UUID userId, UUID facilityId, UUID groupId) {
        requireOwner(userId, facilityId);
        TankGroup group = lockGroup(facilityId, groupId);
        if (group.isArchived()) {
            return group;
        }
        if (group.getTankCount() > 0) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "group_not_empty",
                    "Move or archive every tank in this group before archiving it");
        }
        group.archive(Instant.now());
        return group;
    }

    private FacilityMembership requireMembership(UUID userId, UUID facilityId) {
        return memberships.findByUser_IdAndFacility_Id(userId, facilityId)
                .orElseThrow(this::facilityNotFound);
    }

    private void requireOwner(UUID userId, UUID facilityId) {
        FacilityMembership membership = requireMembership(userId, facilityId);
        if (membership.getRole() != FacilityRole.OWNER) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN,
                    "owner_required",
                    "Only an aquarium owner can manage tank groups");
        }
    }

    private Facility lockFacility(UUID facilityId) {
        return facilities.findByIdForUpdate(facilityId).orElseThrow(this::facilityNotFound);
    }

    private TankGroup lockGroup(UUID facilityId, UUID groupId) {
        return groups.findByIdAndFacilityIdForUpdate(groupId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.NOT_FOUND,
                        "tank_group_not_found",
                        "The tank group was not found"));
    }

    private void rejectDuplicate(UUID facilityId, String normalizedName, UUID currentGroupId) {
        boolean duplicate = currentGroupId == null
                ? groups.existsByFacility_IdAndNormalizedNameAndArchivedAtIsNull(facilityId, normalizedName)
                : groups.existsByFacility_IdAndNormalizedNameAndArchivedAtIsNullAndIdNot(
                        facilityId, normalizedName, currentGroupId);
        if (duplicate) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "tank_group_name_exists",
                    "An active tank group already uses that name");
        }
    }

    private String cleanName(String requestedName) {
        return requestedName.trim().replaceAll("\\s+", " ");
    }

    private String normalizeName(String name) {
        return name.toLowerCase(Locale.ROOT);
    }

    private FacilityException facilityNotFound() {
        return new FacilityException(
                HttpStatus.NOT_FOUND,
                "facility_not_found",
                "The aquarium was not found or is not accessible");
    }
}
