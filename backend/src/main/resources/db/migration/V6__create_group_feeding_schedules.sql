ALTER TABLE tank_groups
    ADD COLUMN feeding_automation_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE group_feeding_times (
    id UUID PRIMARY KEY,
    tank_group_id UUID NOT NULL REFERENCES tank_groups(id) ON DELETE CASCADE,
    local_time TIME NOT NULL,
    next_execution_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_group_feeding_time UNIQUE (tank_group_id, local_time)
);

CREATE INDEX idx_group_feeding_next_execution
    ON group_feeding_times(next_execution_at);
