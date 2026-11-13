package com.aquasense.backend.facility.service;

import java.time.Instant;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class FeedingScheduler {
    private final FeedingSessionService sessions;

    public FeedingScheduler(FeedingSessionService sessions) {
        this.sessions = sessions;
    }

    @Scheduled(fixedDelayString = "${aquasense.feeding.scheduler-delay-ms:30000}")
    public void processDueSessions() {
        sessions.processDue(Instant.now());
    }
}
