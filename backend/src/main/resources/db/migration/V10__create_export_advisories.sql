CREATE TABLE export_advisories (
    id UUID PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    created_by_user_id UUID NOT NULL REFERENCES app_users(id),
    label VARCHAR(120),
    species VARCHAR(40) NOT NULL,
    duration_hours DOUBLE PRECISION NOT NULL,
    feasible BOOLEAN NOT NULL,
    fish_per_bag INTEGER,
    bags_needed INTEGER,
    survival_pct DOUBLE PRECISION,
    worst_survival_pct DOUBLE PRECISION,
    request_json VARCHAR(20000) NOT NULL,
    advisory_json VARCHAR(400000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_export_advisories_facility_created ON export_advisories(facility_id, created_at DESC);
