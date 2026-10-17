package com.aquasense.backend.facility.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.FacilityMembership;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface FacilityMembershipRepository extends JpaRepository<FacilityMembership, UUID> {
    @EntityGraph(attributePaths = "facility")
    List<FacilityMembership> findAllByUser_IdOrderByJoinedAtAsc(UUID userId);

    @EntityGraph(attributePaths = "facility")
    Optional<FacilityMembership> findByUser_IdAndFacility_Id(UUID userId, UUID facilityId);
}
