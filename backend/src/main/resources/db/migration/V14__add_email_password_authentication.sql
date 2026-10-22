ALTER TABLE app_users ALTER COLUMN google_subject DROP NOT NULL;
ALTER TABLE app_users ADD COLUMN password_hash VARCHAR(255);

ALTER TABLE app_users ADD CONSTRAINT chk_app_user_credentials
    CHECK (google_subject IS NOT NULL OR password_hash IS NOT NULL);

-- Canonical emails let the existing UNIQUE constraint also reject case variants.
UPDATE app_users SET email = LOWER(TRIM(email));
ALTER TABLE app_users ADD CONSTRAINT chk_app_user_email_normalized
    CHECK (email = LOWER(TRIM(email)));
