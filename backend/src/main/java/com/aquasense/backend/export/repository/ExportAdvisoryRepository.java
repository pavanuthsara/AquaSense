package com.aquasense.backend.export.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.export.model.ExportAdvisory;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ExportAdvisoryRepository extends JpaRepository<ExportAdvisory, UUID> {
    List<ExportAdvisory> findTop50ByFacilityIdOrderByCreatedAtDesc(UUID facilityId);

    Optional<ExportAdvisory> findByIdAndFacilityId(UUID id, UUID facilityId);
}
