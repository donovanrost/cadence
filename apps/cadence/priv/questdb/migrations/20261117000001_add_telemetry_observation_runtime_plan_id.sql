-- Provenance as typed columns (DECISIONS #103; docs/apogee/domain/provenance-storage.md, option B),
-- column 2 of 9. One column per file: QuestDB refuses a multi-column ADD COLUMN on a WAL table
-- ("contains multiple transactions"; 9.4.3), and one file per statement lets a partial run resume.
-- Additive and metadata-only: existing partitions read the column as null (false for a BOOLEAN),
-- and the reader decodes their full provenance_json as before.

ALTER TABLE telemetry_observations ADD COLUMN IF NOT EXISTS runtime_plan_id SYMBOL CAPACITY 32768 CACHE;
