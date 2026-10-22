package com.aquasense.backend.facility.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.Tank;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TankRepository extends JpaRepository<Tank, UUID>, JpaSpecificationExecutor<Tank> {
    // Fetch only the to-one group here; collection fetches would break SQL pagination.
    @Override
    @EntityGraph(attributePaths = "group")
    Page<Tank> findAll(Specification<Tank> specification, Pageable pageable);

    boolean existsByFacility_IdAndNormalizedCode(UUID facilityId, String normalizedCode);

    boolean existsByFacility_IdAndNormalizedCodeAndIdNot(
            UUID facilityId,
            String normalizedCode,
            UUID id);

    @EntityGraph(attributePaths = {"facility", "group", "tags", "feedingTimes"})
    Optional<Tank> findByIdAndFacility_Id(UUID id, UUID facilityId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @EntityGraph(attributePaths = {"facility", "group", "tags", "feedingTimes"})
    @Query("select tank from Tank tank where tank.id = :id and tank.facility.id = :facilityId")
    Optional<Tank> findByIdAndFacilityIdForUpdate(
            @Param("id") UUID id,
            @Param("facilityId") UUID facilityId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @EntityGraph(attributePaths = {"facility", "group"})
    @Query("select tank from Tank tank where tank.id = :id")
    Optional<Tank> findByIdForFeedingUpdate(@Param("id") UUID id);

    @Query("""
            select distinct tag from Tank tank join tank.tags tag
            where tank.facility.id = :facilityId and tank.archivedAt is null
            order by tag
            """)
    List<String> findActiveTags(@Param("facilityId") UUID facilityId);

    @EntityGraph(attributePaths = {"facility", "group", "tags", "feedingTimes"})
    List<Tank> findByGroup_IdAndArchivedAtIsNull(UUID groupId);

    @EntityGraph(attributePaths = {"facility", "group"})
    List<Tank> findByFacility_IdAndArchivedAtIsNull(UUID facilityId);
}
