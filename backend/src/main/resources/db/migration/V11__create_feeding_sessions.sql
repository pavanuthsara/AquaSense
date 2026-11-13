CREATE TABLE feeding_sessions (
    id UUID PRIMARY KEY,
    tank_id UUID NOT NULL REFERENCES tanks(id) ON DELETE CASCADE,
    scheduled_for TIMESTAMP WITH TIME ZONE NOT NULL,
    outcome VARCHAR(48) NOT NULL,
    observation_id UUID REFERENCES appetite_observations(id) ON DELETE SET NULL,
    calibration_id UUID REFERENCES feeder_calibrations(id) ON DELETE SET NULL,
    portion_units NUMERIC(12, 4),
    command_sent_at TIMESTAMP WITH TIME ZONE,
    feedback_at TIMESTAMP WITH TIME ZONE,
    failure_reason VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_feeding_session_occurrence UNIQUE (tank_id, scheduled_for)
);

CREATE INDEX idx_feeding_sessions_tank_time
    ON feeding_sessions(tank_id, scheduled_for DESC);
CREATE INDEX idx_feeding_sessions_pending_command
    ON feeding_sessions(tank_id, outcome, command_sent_at);
