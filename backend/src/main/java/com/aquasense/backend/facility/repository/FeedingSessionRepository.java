package com.aquasense.backend.facility.repository;

import java.time.Instant;
import java.util.Optional;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.FeedingOutcome;
import com.aquasense.backend.facility.model.FeedingSession;
import com.aquasense.backend.facility.model.FeedingSource;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FeedingSessionRepository extends JpaRepository<FeedingSession, UUID> {
    interface OutcomeCount {
        FeedingOutcome getOutcome();
        long getCount();
    }

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

    @EntityGraph(attributePaths = {"tank", "tank.group"})
    @Query("""
            select session from FeedingSession session
            where session.tank.facility.id = :facilityId
              and (:tankId is null or session.tank.id = :tankId)
              and (:groupId is null or session.tank.group.id = :groupId)
              and (:source is null or session.source = :source)
              and (:outcome is null or session.outcome = :outcome)
              and (:fromTime is null or session.scheduledFor >= :fromTime)
              and (:toTime is null or session.scheduledFor < :toTime)
              and (:cursorTime is null or session.scheduledFor < :cursorTime
                   or (session.scheduledFor = :cursorTime and session.id < :cursorId))
            order by session.scheduledFor desc, session.id desc
            """)
    List<FeedingSession> findHistory(
            @Param("facilityId") UUID facilityId,
            @Param("tankId") UUID tankId,
            @Param("groupId") UUID groupId,
            @Param("source") FeedingSource source,
            @Param("outcome") FeedingOutcome outcome,
            @Param("fromTime") Instant fromTime,
            @Param("toTime") Instant toTime,
            @Param("cursorTime") Instant cursorTime,
            @Param("cursorId") UUID cursorId,
            Pageable pageable);

    @Query("""
            select session.outcome as outcome, count(session) as count
            from FeedingSession session
            where session.tank.facility.id = :facilityId
              and session.scheduledFor >= :since
            group by session.outcome
            """)
    List<OutcomeCount> countOutcomesSince(
            @Param("facilityId") UUID facilityId,
            @Param("since") Instant since);
}
