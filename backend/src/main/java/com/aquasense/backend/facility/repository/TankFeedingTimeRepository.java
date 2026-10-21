package com.aquasense.backend.facility.repository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.TankFeedingTime;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TankFeedingTimeRepository extends JpaRepository<TankFeedingTime, UUID> {
    List<TankFeedingTime> findByNextExecutionAtLessThanEqual(Instant now);

    @EntityGraph(attributePaths = {"tank", "tank.group"})
    List<TankFeedingTime> findByTank_Facility_IdAndNextExecutionAtBetween(
            UUID facilityId, Instant from, Instant to);
}
