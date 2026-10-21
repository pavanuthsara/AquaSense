CREATE TABLE tank_devices (
    id UUID PRIMARY KEY,
    tank_id UUID NOT NULL REFERENCES tanks(id) ON DELETE CASCADE,
    device_type VARCHAR(32) NOT NULL,
    credential_hash VARCHAR(64) NOT NULL,
    reported_healthy BOOLEAN,
    status_message VARCHAR(500),
    last_heartbeat_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_tank_device_type UNIQUE (tank_id, device_type)
);

CREATE INDEX idx_tank_devices_tank_id ON tank_devices(tank_id);
