package com.aquasense.backend.facility.repository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.GroupFeedingTime;
import org.springframework.data.jpa.repository.JpaRepository;

public interface GroupFeedingTimeRepository extends JpaRepository<GroupFeedingTime, UUID> {
    List<GroupFeedingTime> findByNextExecutionAtLessThanEqual(Instant now);
}
