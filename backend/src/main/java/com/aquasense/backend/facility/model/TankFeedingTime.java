package com.aquasense.backend.facility.model;

import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
        name = "tank_feeding_times",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_tank_feeding_time",
                columnNames = {"tank_id", "local_time"}))
public class TankFeedingTime {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tank_id", nullable = false)
    private Tank tank;

    @Column(name = "local_time", nullable = false)
    private LocalTime localTime;

    @Column(name = "next_execution_at")
    private Instant nextExecutionAt;

    protected TankFeedingTime() {
    }

    TankFeedingTime(Tank tank, LocalTime localTime, boolean enabled, ZoneId timeZone, Instant now) {
        this.id = UUID.randomUUID();
        this.tank = tank;
        this.localTime = localTime;
        schedule(enabled, timeZone, now);
    }

    void schedule(boolean enabled, ZoneId timeZone, Instant now) {
        nextExecutionAt = enabled
                ? GroupFeedingTime.nextOccurrence(localTime, timeZone, now)
                : null;
    }

    void pause() {
        nextExecutionAt = null;
    }

    public LocalTime getLocalTime() { return localTime; }
    public Instant getNextExecutionAt() { return nextExecutionAt; }
}
