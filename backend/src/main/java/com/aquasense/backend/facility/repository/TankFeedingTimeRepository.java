package com.aquasense.backend.facility.repository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.TankFeedingTime;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TankFeedingTimeRepository extends JpaRepository<TankFeedingTime, UUID> {
    List<TankFeedingTime> findByNextExecutionAtLessThanEqual(Instant now);
}
