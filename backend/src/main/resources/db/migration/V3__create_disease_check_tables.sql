-- DIS-002: results of the image-based guppy disease check.
-- The phone runs the model and sends only the result, not the photo.
CREATE TABLE disease_checks (
    id UUID PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    checked_by_user_id UUID NOT NULL REFERENCES app_users(id),
    request_key VARCHAR(128) NOT NULL,
    predicted_label VARCHAR(40) NOT NULL,
    confidence DOUBLE PRECISION NOT NULL,
    uncertain BOOLEAN NOT NULL,
    model_version VARCHAR(64) NOT NULL,
    tank_label VARCHAR(80),
    note VARCHAR(500),
    checked_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_disease_check_request UNIQUE (checked_by_user_id, request_key),
    CONSTRAINT chk_disease_check_confidence CHECK (confidence >= 0 AND confidence <= 1)
);

CREATE INDEX idx_disease_checks_facility_checked_at ON disease_checks(facility_id, checked_at DESC);
