package com.aquasense.backend.facility.model;

import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

@Entity
@Table(name = "tank_groups")
public class TankGroup {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "facility_id", nullable = false)
    private Facility facility;

    @Column(nullable = false, length = 80)
    private String name;

    @Column(name = "normalized_name", nullable = false, length = 80)
    private String normalizedName;

    @Column(name = "tank_count", nullable = false)
    private int tankCount;

    @Column(name = "feeding_automation_enabled", nullable = false)
    private boolean feedingAutomationEnabled;

    @OneToMany(mappedBy = "tankGroup", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("localTime ASC")
    private List<GroupFeedingTime> feedingTimes = new ArrayList<>();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "archived_at")
    private Instant archivedAt;

    protected TankGroup() {
    }

    public TankGroup(Facility facility, String name, String normalizedName, Instant now) {
        this.id = UUID.randomUUID();
        this.facility = facility;
        this.name = name;
        this.normalizedName = normalizedName;
        this.tankCount = 0;
        this.feedingAutomationEnabled = false;
        this.createdAt = now;
        this.updatedAt = now;
    }

    public void rename(String name, String normalizedName, Instant now) {
        this.name = name;
        this.normalizedName = normalizedName;
        this.updatedAt = now;
    }

    public void archive(Instant now) {
        this.feedingAutomationEnabled = false;
        this.feedingTimes.forEach(GroupFeedingTime::pause);
        this.archivedAt = now;
        this.updatedAt = now;
    }

    public void configureFeedingSchedule(
            List<LocalTime> localTimes,
            boolean automationEnabled,
            ZoneId timeZone,
            Instant now) {
        Map<LocalTime, GroupFeedingTime> existingByTime = new HashMap<>();
        this.feedingTimes.forEach(item -> existingByTime.put(item.getLocalTime(), item));
        this.feedingTimes.removeIf(item -> !localTimes.contains(item.getLocalTime()));
        localTimes.forEach(time -> {
            GroupFeedingTime existing = existingByTime.get(time);
            if (existing == null) {
                this.feedingTimes.add(new GroupFeedingTime(
                        this, time, automationEnabled, timeZone, now));
            } else {
                existing.schedule(automationEnabled, timeZone, now);
            }
        });
        this.feedingAutomationEnabled = automationEnabled;
        this.updatedAt = now;
    }

    public void addTank(Instant now) {
        this.tankCount += 1;
        this.updatedAt = now;
    }

    public void removeTank(Instant now) {
        if (tankCount <= 0) {
            throw new IllegalStateException("Tank group count cannot become negative");
        }
        this.tankCount -= 1;
        this.updatedAt = now;
    }

    public UUID getId() { return id; }
    public Facility getFacility() { return facility; }
    public String getName() { return name; }
    public String getNormalizedName() { return normalizedName; }
    public int getTankCount() { return tankCount; }
    public boolean isFeedingAutomationEnabled() { return feedingAutomationEnabled; }
    public List<GroupFeedingTime> getFeedingTimes() { return List.copyOf(feedingTimes); }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public Instant getArchivedAt() { return archivedAt; }
    public boolean isArchived() { return archivedAt != null; }
}
