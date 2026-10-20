package com.aquasense.backend.disease.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.disease.model.DiseaseCheck;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DiseaseCheckRepository extends JpaRepository<DiseaseCheck, UUID> {
    @EntityGraph(attributePaths = {"facility", "checkedBy"})
    Optional<DiseaseCheck> findByCheckedBy_IdAndRequestKey(UUID userId, String requestKey);

    @EntityGraph(attributePaths = {"facility", "checkedBy"})
    List<DiseaseCheck> findAllByFacility_IdOrderByCheckedAtDescIdDesc(UUID facilityId, Pageable page);
}
