package com.aquasense.backend.facility.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.Tank;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TankRepository extends JpaRepository<Tank, UUID>, JpaSpecificationExecutor<Tank> {
    boolean existsByFacility_IdAndNormalizedCode(UUID facilityId, String normalizedCode);

    boolean existsByFacility_IdAndNormalizedCodeAndIdNot(
            UUID facilityId,
            String normalizedCode,
            UUID id);

    @EntityGraph(attributePaths = {"facility", "group", "tags"})
    Optional<Tank> findByIdAndFacility_Id(UUID id, UUID facilityId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @EntityGraph(attributePaths = {"facility", "group", "tags"})
    @Query("select tank from Tank tank where tank.id = :id and tank.facility.id = :facilityId")
    Optional<Tank> findByIdAndFacilityIdForUpdate(
            @Param("id") UUID id,
            @Param("facilityId") UUID facilityId);

    @Query("""
            select distinct tag from Tank tank join tank.tags tag
            where tank.facility.id = :facilityId and tank.archivedAt is null
            order by tag
            """)
    List<String> findActiveTags(@Param("facilityId") UUID facilityId);
}
