package com.aquasense.backend.facility.repository;

import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.Facility;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FacilityRepository extends JpaRepository<Facility, UUID> {
    Optional<Facility> findByCreatedBy_IdAndCreationRequestKey(UUID userId, String creationRequestKey);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select facility from Facility facility where facility.id = :id")
    Optional<Facility> findByIdForUpdate(@Param("id") UUID id);
}
