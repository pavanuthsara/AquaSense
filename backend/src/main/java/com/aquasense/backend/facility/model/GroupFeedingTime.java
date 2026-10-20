package com.aquasense.backend.facility.model;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
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
        name = "group_feeding_times",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_group_feeding_time",
                columnNames = {"tank_group_id", "local_time"}))
public class GroupFeedingTime {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tank_group_id", nullable = false)
    private TankGroup tankGroup;

    @Column(name = "local_time", nullable = false)
    private LocalTime localTime;

    @Column(name = "next_execution_at")
    private Instant nextExecutionAt;

    protected GroupFeedingTime() {
    }

    GroupFeedingTime(
            TankGroup tankGroup,
            LocalTime localTime,
            boolean automationEnabled,
            ZoneId timeZone,
            Instant now) {
        this.id = UUID.randomUUID();
        this.tankGroup = tankGroup;
        this.localTime = localTime;
        this.nextExecutionAt = automationEnabled ? nextOccurrence(localTime, timeZone, now) : null;
    }

    void pause() {
        nextExecutionAt = null;
    }

    void schedule(boolean automationEnabled, ZoneId timeZone, Instant now) {
        nextExecutionAt = automationEnabled ? nextOccurrence(localTime, timeZone, now) : null;
    }

    public static Instant nextOccurrence(LocalTime localTime, ZoneId timeZone, Instant now) {
        LocalDate localDate = now.atZone(timeZone).toLocalDate();
        ZonedDateTime candidate = localDate.atTime(localTime).atZone(timeZone);
        if (!candidate.toInstant().isAfter(now)) {
            candidate = localDate.plusDays(1).atTime(localTime).atZone(timeZone);
        }
        return candidate.toInstant();
    }

    public UUID getId() { return id; }
    public LocalTime getLocalTime() { return localTime; }
    public Instant getNextExecutionAt() { return nextExecutionAt; }
}
