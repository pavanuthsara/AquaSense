package com.aquasense.backend.facility.repository;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Objects;
import java.util.UUID;

import com.aquasense.backend.facility.model.FeedingOutcome;
import com.aquasense.backend.facility.model.FeedingSession;
import com.aquasense.backend.facility.model.FeedingSource;
import jakarta.persistence.criteria.JoinType;
import jakarta.persistence.criteria.Predicate;
import org.springframework.data.jpa.domain.Specification;

public final class FeedingSessionSpecifications {
    private FeedingSessionSpecifications() { }

    public static Specification<FeedingSession> history(
            UUID facilityId, UUID tankId, UUID groupId, FeedingSource source, FeedingOutcome outcome,
            Instant from, Instant to, Instant cursorTime, UUID cursorId) {
        Objects.requireNonNull(facilityId, "History must be scoped to a facility");
        return (root, query, cb) -> {
            if (query != null && FeedingSession.class.equals(query.getResultType())) {
                // Keep history details eager, including tanks with no group.
                root.fetch("tank", JoinType.INNER).fetch("group", JoinType.LEFT);
            }
            var tank = root.get("tank");
            var scheduledFor = root.<Instant>get("scheduledFor");
            var predicates = new ArrayList<Predicate>();
            predicates.add(cb.equal(tank.get("facility").get("id"), facilityId));
            // Omit absent filters entirely: PostgreSQL cannot type a bare null IS NULL parameter.
            if (tankId != null) predicates.add(cb.equal(tank.get("id"), tankId));
            if (groupId != null) predicates.add(cb.equal(tank.get("group").get("id"), groupId));
            if (source != null) predicates.add(cb.equal(root.get("source"), source));
            if (outcome != null) predicates.add(cb.equal(root.get("outcome"), outcome));
            if (from != null) predicates.add(cb.greaterThanOrEqualTo(scheduledFor, from));
            if (to != null) predicates.add(cb.lessThan(scheduledFor, to));
            if (cursorTime != null) {
                predicates.add(cb.or(
                        cb.lessThan(scheduledFor, cursorTime),
                        cb.and(cb.equal(scheduledFor, cursorTime),
                                cb.lessThan(root.<UUID>get("id"), Objects.requireNonNull(cursorId)))));
            }
            return cb.and(predicates.toArray(Predicate[]::new));
        };
    }
}
