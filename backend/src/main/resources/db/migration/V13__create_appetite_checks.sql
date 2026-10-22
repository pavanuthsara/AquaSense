CREATE TABLE appetite_checks (
    id UUID PRIMARY KEY,
    tank_id UUID NOT NULL REFERENCES tanks(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES tank_devices(id) ON DELETE CASCADE,
    status VARCHAR(24) NOT NULL,
    requested_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    observed_at TIMESTAMP WITH TIME ZONE,
    appetite_result VARCHAR(16),
    confidence NUMERIC(5, 4),
    model_version VARCHAR(120),
    message VARCHAR(500)
);
CREATE INDEX idx_appetite_checks_tank_status ON appetite_checks(tank_id, status, requested_at);
