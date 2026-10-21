package com.aquasense.backend.facility.repository;

import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.FeederCalibration;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface FeederCalibrationRepository extends JpaRepository<FeederCalibration, UUID> {
    @EntityGraph(attributePaths = {"facility", "createdBy"})
    Optional<FeederCalibration> findFirstByFacility_IdOrderByVersionDesc(UUID facilityId);
}
