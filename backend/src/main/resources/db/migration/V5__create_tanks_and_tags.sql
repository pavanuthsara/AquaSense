CREATE TABLE tanks (
    id UUID PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    group_id UUID REFERENCES tank_groups(id) ON DELETE SET NULL,
    name VARCHAR(120) NOT NULL,
    code VARCHAR(64) NOT NULL,
    normalized_code VARCHAR(64) NOT NULL,
    expected_guppy_count INTEGER NOT NULL,
    detected_guppy_count INTEGER,
    detection_confidence NUMERIC(5, 4),
    count_observed_at TIMESTAMP WITH TIME ZONE,
    automation_enabled BOOLEAN NOT NULL,
    notes VARCHAR(2000),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_tank_facility_code UNIQUE (facility_id, normalized_code),
    CONSTRAINT chk_tank_expected_count CHECK (expected_guppy_count >= 0),
    CONSTRAINT chk_tank_detected_count CHECK (detected_guppy_count IS NULL OR detected_guppy_count >= 0),
    CONSTRAINT chk_tank_confidence CHECK (
        detection_confidence IS NULL OR (detection_confidence >= 0 AND detection_confidence <= 1)
    )
);

CREATE TABLE tank_tags (
    tank_id UUID NOT NULL REFERENCES tanks(id) ON DELETE CASCADE,
    tag VARCHAR(40) NOT NULL,
    PRIMARY KEY (tank_id, tag)
);

CREATE INDEX idx_tanks_facility_status_name
    ON tanks(facility_id, archived_at, automation_enabled, name);
CREATE INDEX idx_tanks_group ON tanks(group_id);
CREATE INDEX idx_tank_tags_tag ON tank_tags(tag, tank_id);
