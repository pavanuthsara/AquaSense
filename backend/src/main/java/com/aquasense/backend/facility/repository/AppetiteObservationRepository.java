package com.aquasense.backend.facility.repository;

import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.AppetiteObservation;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AppetiteObservationRepository extends JpaRepository<AppetiteObservation, UUID> {
    Optional<AppetiteObservation> findFirstByTank_IdOrderByObservedAtDescReceivedAtDesc(UUID tankId);
}
