package com.aquasense.backend.facility.service;

import java.time.Instant;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.model.TankGroup;
import com.aquasense.backend.facility.model.TankScheduleMode;
import com.aquasense.backend.facility.model.TankStatus;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.aquasense.backend.facility.repository.TankGroupRepository;
import com.aquasense.backend.facility.repository.TankRepository;
import jakarta.persistence.criteria.JoinType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TankService {
    private static final int MAX_PAGE_SIZE = 100;
    private static final DateTimeFormatter FEEDING_TIME_FORMAT = DateTimeFormatter.ofPattern("HH:mm");

    private final FacilityRepository facilities;
    private final FacilityMembershipRepository memberships;
    private final TankGroupRepository groups;
    private final TankRepository tanks;

    public TankService(
            FacilityRepository facilities,
            FacilityMembershipRepository memberships,
            TankGroupRepository groups,
            TankRepository tanks) {
        this.facilities = facilities;
        this.memberships = memberships;
        this.groups = groups;
        this.tanks = tanks;
    }

    @Transactional(readOnly = true)
    public TankPage list(
            UUID userId,
            UUID facilityId,
            int requestedPage,
            int requestedSize,
            String search,
            TankStatus status,
            UUID groupId,
            boolean unassigned,
            String tag) {
        requireMembership(userId, facilityId);
        int page = Math.max(requestedPage, 0);
        int size = Math.min(Math.max(requestedSize, 1), MAX_PAGE_SIZE);
        Specification<Tank> specification = facilityIs(facilityId)
                .and(hasStatus(status))
                .and(matchesSearch(search))
                .and(inGroup(groupId, unassigned))
                .and(hasTag(tag));
        Page<Tank> result = tanks.findAll(
                specification,
                PageRequest.of(page, size, Sort.by(
                        Sort.Order.asc("name").ignoreCase(),
                        Sort.Order.asc("id"))));
        result.getContent().forEach(tank -> tank.getTags().size());
        return new TankPage(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements(),
                result.getTotalPages());
    }

    @Transactional(readOnly = true)
    public Tank get(UUID userId, UUID facilityId, UUID tankId) {
        requireMembership(userId, facilityId);
        Tank tank = tanks.findByIdAndFacility_Id(tankId, facilityId)
                .orElseThrow(this::tankNotFound);
        initializeSchedule(tank);
        return tank;
    }

    @Transactional(readOnly = true)
    public List<String> listTags(UUID userId, UUID facilityId) {
        requireMembership(userId, facilityId);
        return tanks.findActiveTags(facilityId);
    }

    @Transactional
    public Tank create(UUID userId, UUID facilityId, TankInput input) {
        requireOwner(userId, facilityId);
        Facility facility = facilities.findByIdForUpdate(facilityId)
                .orElseThrow(this::facilityNotFound);
        String code = clean(input.code());
        String normalizedCode = normalize(code);
        rejectDuplicateCode(facilityId, normalizedCode, null);
        Instant now = Instant.now();
        TankGroup group = input.groupId() == null ? null : lockActiveGroup(facilityId, input.groupId());
        if (group != null) {
            group.addTank(now);
        }
        return tanks.save(new Tank(
                facility,
                group,
                clean(input.name()),
                code,
                normalizedCode,
                input.expectedGuppyCount(),
                cleanTags(input.tags()),
                input.automationEnabled(),
                cleanNotes(input.notes()),
                now));
    }

    @Transactional
    public Tank update(UUID userId, UUID facilityId, UUID tankId, TankInput input) {
        requireOwner(userId, facilityId);
        facilities.findByIdForUpdate(facilityId).orElseThrow(this::facilityNotFound);
        Tank tank = lockTank(facilityId, tankId);
        if (tank.isArchived()) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "tank_archived",
                    "An archived tank cannot be edited");
        }
        String code = clean(input.code());
        String normalizedCode = normalize(code);
        rejectDuplicateCode(facilityId, normalizedCode, tankId);
        UUID oldGroupId = tank.getGroup() == null ? null : tank.getGroup().getId();
        UUID newGroupId = input.groupId();
        TankGroup newGroup = tank.getGroup();
        Instant now = Instant.now();
        if (!java.util.Objects.equals(oldGroupId, newGroupId)) {
            List<UUID> groupIds = java.util.stream.Stream.of(oldGroupId, newGroupId)
                    .filter(java.util.Objects::nonNull)
                    .sorted()
                    .toList();
            java.util.Map<UUID, TankGroup> lockedGroups = new java.util.HashMap<>();
            for (UUID groupId : groupIds) {
                lockedGroups.put(groupId, lockGroup(facilityId, groupId));
            }
            if (oldGroupId != null) {
                lockedGroups.get(oldGroupId).removeTank(now);
            }
            if (newGroupId != null) {
                newGroup = lockedGroups.get(newGroupId);
                if (newGroup.isArchived()) {
                    throw archivedGroup();
                }
                newGroup.addTank(now);
            } else {
                newGroup = null;
            }
        }
        tank.update(
                newGroup,
                clean(input.name()),
                code,
                normalizedCode,
                input.expectedGuppyCount(),
                cleanTags(input.tags()),
                input.automationEnabled(),
                cleanNotes(input.notes()),
                now);
        return tank;
    }

    @Transactional
    public Tank archive(UUID userId, UUID facilityId, UUID tankId) {
        requireOwner(userId, facilityId);
        Tank tank = lockTank(facilityId, tankId);
        if (tank.isArchived()) {
            return tank;
        }
        Instant now = Instant.now();
        if (tank.getGroup() != null) {
            lockGroup(facilityId, tank.getGroup().getId()).removeTank(now);
        }
        tank.archive(now);
        return tank;
    }

    @Transactional
    public Tank configureFeedingSchedule(
            UUID userId,
            UUID facilityId,
            UUID tankId,
            TankScheduleMode mode,
            List<String> requestedTimes) {
        requireOwner(userId, facilityId);
        Tank tank = lockTank(facilityId, tankId);
        if (tank.isArchived()) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "tank_archived",
                    "An archived tank cannot have its feeding schedule changed");
        }
        List<LocalTime> localTimes = requestedTimes.stream()
                .map(time -> LocalTime.parse(time, FEEDING_TIME_FORMAT))
                .sorted()
                .toList();
        if (new LinkedHashSet<>(localTimes).size() != localTimes.size()) {
            throw new FacilityException(
                    HttpStatus.BAD_REQUEST,
                    "duplicate_feeding_time",
                    "Each daily feeding time must be unique");
        }
        if (mode == TankScheduleMode.INHERITED && !localTimes.isEmpty()) {
            throw new FacilityException(
                    HttpStatus.BAD_REQUEST,
                    "inherited_schedule_has_times",
                    "Inherited schedules cannot contain tank-specific times");
        }
        if (mode == TankScheduleMode.OVERRIDE && localTimes.isEmpty()) {
            throw new FacilityException(
                    HttpStatus.BAD_REQUEST,
                    "override_schedule_empty",
                    "Add at least one time to the tank override");
        }
        tank.configureSchedule(mode, localTimes, Instant.now());
        initializeSchedule(tank);
        return tank;
    }

    private void initializeSchedule(Tank tank) {
        tank.getFeedingTimes().size();
        if (tank.getGroup() != null) {
            tank.getGroup().getFeedingTimes().size();
        }
    }

    private Specification<Tank> facilityIs(UUID facilityId) {
        return (root, query, builder) -> builder.equal(root.get("facility").get("id"), facilityId);
    }

    private Specification<Tank> hasStatus(TankStatus status) {
        return (root, query, builder) -> {
            if (status == TankStatus.ARCHIVED) {
                return builder.isNotNull(root.get("archivedAt"));
            }
            var notArchived = builder.isNull(root.get("archivedAt"));
            if (status == TankStatus.ACTIVE) {
                return builder.and(notArchived, builder.isTrue(root.get("automationEnabled")));
            }
            if (status == TankStatus.PAUSED) {
                return builder.and(notArchived, builder.isFalse(root.get("automationEnabled")));
            }
            return notArchived;
        };
    }

    private Specification<Tank> matchesSearch(String requestedSearch) {
        return (root, query, builder) -> {
            if (requestedSearch == null || requestedSearch.isBlank()) {
                return builder.conjunction();
            }
            String pattern = "%" + normalize(requestedSearch.trim()) + "%";
            return builder.or(
                    builder.like(builder.lower(root.get("name")), pattern),
                    builder.like(root.get("normalizedCode"), pattern));
        };
    }

    private Specification<Tank> inGroup(UUID groupId, boolean unassigned) {
        return (root, query, builder) -> {
            if (unassigned) {
                return builder.isNull(root.get("group"));
            }
            return groupId == null
                    ? builder.conjunction()
                    : builder.equal(root.get("group").get("id"), groupId);
        };
    }

    private Specification<Tank> hasTag(String requestedTag) {
        return (root, query, builder) -> {
            if (requestedTag == null || requestedTag.isBlank()) {
                return builder.conjunction();
            }
            query.distinct(true);
            return builder.equal(root.join("tags", JoinType.INNER), normalize(requestedTag.trim()));
        };
    }

    private FacilityMembership requireMembership(UUID userId, UUID facilityId) {
        return memberships.findByUser_IdAndFacility_Id(userId, facilityId)
                .orElseThrow(this::facilityNotFound);
    }

    private void requireOwner(UUID userId, UUID facilityId) {
        if (requireMembership(userId, facilityId).getRole() != FacilityRole.OWNER) {
            throw new FacilityException(
                    HttpStatus.FORBIDDEN,
                    "owner_required",
                    "Only an aquarium owner can manage tanks");
        }
    }

    private Tank lockTank(UUID facilityId, UUID tankId) {
        return tanks.findByIdAndFacilityIdForUpdate(tankId, facilityId)
                .orElseThrow(this::tankNotFound);
    }

    private TankGroup lockActiveGroup(UUID facilityId, UUID groupId) {
        TankGroup group = lockGroup(facilityId, groupId);
        if (group.isArchived()) {
            throw archivedGroup();
        }
        return group;
    }

    private TankGroup lockGroup(UUID facilityId, UUID groupId) {
        return groups.findByIdAndFacilityIdForUpdate(groupId, facilityId)
                .orElseThrow(() -> new FacilityException(
                        HttpStatus.BAD_REQUEST,
                        "invalid_tank_group",
                        "Select an active tank group from this aquarium"));
    }

    private void rejectDuplicateCode(UUID facilityId, String normalizedCode, UUID currentTankId) {
        boolean exists = currentTankId == null
                ? tanks.existsByFacility_IdAndNormalizedCode(facilityId, normalizedCode)
                : tanks.existsByFacility_IdAndNormalizedCodeAndIdNot(facilityId, normalizedCode, currentTankId);
        if (exists) {
            throw new FacilityException(
                    HttpStatus.CONFLICT,
                    "tank_code_exists",
                    "A tank in this aquarium already uses that code");
        }
    }

    private Set<String> cleanTags(List<String> requestedTags) {
        Set<String> result = new LinkedHashSet<>();
        for (String tag : requestedTags) {
            String cleanTag = normalize(clean(tag));
            if (!cleanTag.isBlank()) {
                result.add(cleanTag);
            }
        }
        return result;
    }

    private String clean(String value) {
        return value.trim().replaceAll("\\s+", " ");
    }

    private String cleanNotes(String value) {
        if (value == null) {
            return null;
        }
        String notes = value.trim();
        return notes.isEmpty() ? null : notes;
    }

    private String normalize(String value) {
        return value.toLowerCase(Locale.ROOT);
    }

    private FacilityException facilityNotFound() {
        return new FacilityException(
                HttpStatus.NOT_FOUND,
                "facility_not_found",
                "The aquarium was not found or is not accessible");
    }

    private FacilityException tankNotFound() {
        return new FacilityException(
                HttpStatus.NOT_FOUND,
                "tank_not_found",
                "The tank was not found");
    }

    private FacilityException archivedGroup() {
        return new FacilityException(
                HttpStatus.CONFLICT,
                "tank_group_archived",
                "Archived tank groups cannot receive tanks");
    }

    public record TankInput(
            String name,
            String code,
            int expectedGuppyCount,
            UUID groupId,
            List<String> tags,
            boolean automationEnabled,
            String notes) {
    }

    public record TankPage(
            List<Tank> items,
            int page,
            int size,
            long totalItems,
            int totalPages) {
    }
}
