CREATE TABLE tank_groups (
    id UUID PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    name VARCHAR(80) NOT NULL,
    normalized_name VARCHAR(80) NOT NULL,
    tank_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT chk_tank_group_count CHECK (tank_count >= 0)
);

CREATE INDEX idx_tank_groups_facility
    ON tank_groups(facility_id, archived_at, normalized_name);
