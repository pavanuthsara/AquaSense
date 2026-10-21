CREATE TABLE facility_invitations (
    id UUID PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    invited_by_user_id UUID NOT NULL REFERENCES app_users(id),
    email VARCHAR(320) NOT NULL,
    status VARCHAR(20) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    accepted_by_user_id UUID REFERENCES app_users(id),
    accepted_at TIMESTAMP WITH TIME ZONE,
    revoked_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT chk_facility_invitation_status
        CHECK (status IN ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED'))
);

CREATE INDEX idx_facility_invitations_facility
    ON facility_invitations(facility_id, created_at);
CREATE INDEX idx_facility_invitations_email_status
    ON facility_invitations(email, status);
