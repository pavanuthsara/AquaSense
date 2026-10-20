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

    @EntityGraph(attributePaths = "user")
    List<FacilityMembership> findAllByFacility_IdOrderByJoinedAtAsc(UUID facilityId);

    @EntityGraph(attributePaths = {"facility", "user"})
    Optional<FacilityMembership> findByIdAndFacility_Id(UUID membershipId, UUID facilityId);

    boolean existsByFacility_IdAndUser_EmailIgnoreCase(UUID facilityId, String email);
}
