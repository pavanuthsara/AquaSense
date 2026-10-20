CREATE TABLE appetite_observations (
    id UUID PRIMARY KEY,
    tank_id UUID NOT NULL REFERENCES tanks(id) ON DELETE CASCADE,
    source_device_id UUID NOT NULL REFERENCES tank_devices(id) ON DELETE CASCADE,
    detected_guppy_count INTEGER NOT NULL,
    confidence NUMERIC(5, 4) NOT NULL,
    appetite_result VARCHAR(16) NOT NULL,
    model_version VARCHAR(120) NOT NULL,
    observed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    received_at TIMESTAMP WITH TIME ZONE NOT NULL,
    stale BOOLEAN NOT NULL,
    low_confidence BOOLEAN NOT NULL,
    count_inconsistent BOOLEAN NOT NULL,
    valid_for_feeding_decision BOOLEAN NOT NULL
);

CREATE INDEX idx_appetite_observations_tank_time
    ON appetite_observations(tank_id, observed_at DESC);
