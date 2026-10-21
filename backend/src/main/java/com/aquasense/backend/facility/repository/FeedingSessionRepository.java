package com.aquasense.backend.facility.repository;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.FeedingOutcome;
import com.aquasense.backend.facility.model.FeedingSession;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FeedingSessionRepository extends JpaRepository<FeedingSession, UUID> {
    @EntityGraph(attributePaths = {"tank", "observation", "calibration"})
    @Query("select session from FeedingSession session where session.id = :id")
    Optional<FeedingSession> findDetailedById(@Param("id") UUID id);

    @EntityGraph(attributePaths = {"tank", "tank.facility", "observation", "calibration"})
    Optional<FeedingSession> findByTank_IdAndScheduledFor(UUID tankId, Instant scheduledFor);

    Optional<FeedingSession> findFirstByTank_IdAndCommandSentAtIsNotNullOrderByCommandSentAtDesc(UUID tankId);

    @EntityGraph(attributePaths = {"tank", "observation", "calibration"})
    Optional<FeedingSession> findFirstByTank_IdOrderByScheduledForDesc(UUID tankId);

    @EntityGraph(attributePaths = {"tank", "observation", "calibration"})
    Optional<FeedingSession> findFirstByTank_IdAndOutcomeOrderByCommandSentAtAsc(
            UUID tankId, FeedingOutcome outcome);
}
