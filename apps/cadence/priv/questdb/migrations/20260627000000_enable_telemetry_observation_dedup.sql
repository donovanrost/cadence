-- Enable retry-safe QuestDB storage deduplication for telemetry observations.
--
-- QuestDB deduplication requires the designated timestamp column in the upsert
-- key list. Cadence pairs observed_at with the domain idempotency key computed
-- before storage so retrying the same write cannot create dashboard-visible
-- duplicate observation rows.

ALTER TABLE telemetry_observations
DEDUP ENABLE UPSERT KEYS(observed_at, idempotency_key);
