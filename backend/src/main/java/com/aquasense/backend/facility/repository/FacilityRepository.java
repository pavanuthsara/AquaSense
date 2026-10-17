package com.aquasense.backend.facility.repository;

import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.Facility;
import org.springframework.data.jpa.repository.JpaRepository;

public interface FacilityRepository extends JpaRepository<Facility, UUID> {
    Optional<Facility> findByCreatedBy_IdAndCreationRequestKey(UUID userId, String creationRequestKey);
}
