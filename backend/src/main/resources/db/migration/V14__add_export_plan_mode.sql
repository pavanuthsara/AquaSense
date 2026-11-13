-- Planning modes: suggest (simulator picks fish per bag), fixed_bags (exporter fixes the number of
-- bags) and check (exporter enters their own packing). meets_target records whether the shown packing
-- reaches the survival target.
ALTER TABLE export_advisories ADD COLUMN plan_mode VARCHAR(16) NOT NULL DEFAULT 'suggest';
ALTER TABLE export_advisories ADD COLUMN meets_target BOOLEAN NOT NULL DEFAULT TRUE;
