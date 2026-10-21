ALTER TABLE feeding_sessions
    ADD COLUMN source VARCHAR(16) NOT NULL DEFAULT 'SCHEDULED';

ALTER TABLE feeding_sessions
    ALTER COLUMN source DROP DEFAULT;

CREATE INDEX idx_feeding_sessions_facility_history
    ON feeding_sessions(scheduled_for DESC, id);
