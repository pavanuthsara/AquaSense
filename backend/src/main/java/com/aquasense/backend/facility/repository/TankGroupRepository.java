package com.aquasense.backend.facility.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.TankGroup;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TankGroupRepository extends JpaRepository<TankGroup, UUID> {
    @EntityGraph(attributePaths = "facility")
    List<TankGroup> findAllByFacility_IdOrderByNameAsc(UUID facilityId);

    boolean existsByFacility_IdAndNormalizedNameAndArchivedAtIsNull(
            UUID facilityId,
            String normalizedName);

    boolean existsByFacility_IdAndNormalizedNameAndArchivedAtIsNullAndIdNot(
            UUID facilityId,
            String normalizedName,
            UUID id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @EntityGraph(attributePaths = "facility")
    @Query("""
            select tankGroup from TankGroup tankGroup
            where tankGroup.id = :id and tankGroup.facility.id = :facilityId
            """)
    Optional<TankGroup> findByIdAndFacilityIdForUpdate(
            @Param("id") UUID id,
            @Param("facilityId") UUID facilityId);
}
