CREATE TABLE facilities (
    id UUID PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    time_zone VARCHAR(64) NOT NULL,
    created_by_user_id UUID NOT NULL REFERENCES app_users(id),
    creation_request_key VARCHAR(128) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_facility_creation_request UNIQUE (created_by_user_id, creation_request_key)
);

CREATE TABLE facility_memberships (
    id UUID PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL,
    joined_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_facility_membership UNIQUE (facility_id, user_id),
    CONSTRAINT chk_facility_membership_role CHECK (role IN ('OWNER', 'WORKER'))
);

CREATE INDEX idx_facility_memberships_user ON facility_memberships(user_id);
