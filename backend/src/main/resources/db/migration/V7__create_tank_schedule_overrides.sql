ALTER TABLE tanks
    ADD COLUMN schedule_mode VARCHAR(16) NOT NULL DEFAULT 'INHERITED';

CREATE TABLE tank_feeding_times (
    id UUID PRIMARY KEY,
    tank_id UUID NOT NULL REFERENCES tanks(id) ON DELETE CASCADE,
    local_time TIME NOT NULL,
    next_execution_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_tank_feeding_time UNIQUE (tank_id, local_time)
);

CREATE INDEX idx_tank_feeding_next_execution
    ON tank_feeding_times(next_execution_at);
