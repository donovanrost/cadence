-- Add durable observation identity references for canonical-selection reads.
--
-- Older local QuestDB instances may have been created before Cadence separated
-- an observation id from its cross-revision observation identity id. The smoke
-- task depends on this column because the managed TSDB path now preserves the
-- canonical selection evidence needed by dashboard history reads.

ALTER TABLE telemetry_observations
ADD COLUMN IF NOT EXISTS observation_identity_id STRING;
