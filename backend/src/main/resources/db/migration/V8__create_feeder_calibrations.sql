CREATE TABLE feeder_calibrations (
    id UUID PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    units_per_fish NUMERIC(12, 4) NOT NULL,
    minimum_units NUMERIC(12, 4) NOT NULL,
    maximum_units NUMERIC(12, 4) NOT NULL,
    created_by_user_id UUID NOT NULL REFERENCES app_users(id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_feeder_calibration_version UNIQUE (facility_id, version),
    CONSTRAINT ck_feeder_calibration_rate CHECK (units_per_fish > 0),
    CONSTRAINT ck_feeder_calibration_minimum CHECK (minimum_units > 0),
    CONSTRAINT ck_feeder_calibration_maximum CHECK (maximum_units >= minimum_units)
);

CREATE INDEX idx_feeder_calibration_active
    ON feeder_calibrations(facility_id, version DESC);
