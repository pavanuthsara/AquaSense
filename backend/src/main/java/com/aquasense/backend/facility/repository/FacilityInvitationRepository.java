package com.aquasense.backend.facility.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.FacilityInvitation;
import com.aquasense.backend.facility.model.InvitationStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FacilityInvitationRepository extends JpaRepository<FacilityInvitation, UUID> {
    @EntityGraph(attributePaths = {"facility", "invitedBy", "acceptedBy"})
    List<FacilityInvitation> findAllByFacility_IdOrderByCreatedAtDesc(UUID facilityId);

    @EntityGraph(attributePaths = {"facility", "invitedBy"})
    List<FacilityInvitation> findAllByEmailIgnoreCaseAndStatusOrderByCreatedAtAsc(
            String email,
            InvitationStatus status);

    Optional<FacilityInvitation> findFirstByFacility_IdAndEmailIgnoreCaseAndStatusOrderByCreatedAtDesc(
            UUID facilityId,
            String email,
            InvitationStatus status);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @EntityGraph(attributePaths = {"facility", "acceptedBy"})
    @Query("select invitation from FacilityInvitation invitation where invitation.id = :id")
    Optional<FacilityInvitation> findByIdForUpdate(@Param("id") UUID id);
}
