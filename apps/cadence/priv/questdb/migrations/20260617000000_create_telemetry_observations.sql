-- QuestDB managed telemetry observation storage.
--
-- This table is intentionally append-oriented. Cadence records
-- observation_identity_id, observation_id, and idempotency_key here, but
-- duplicate/correction policy is still owned by Cadence before rows reach the
-- physical store.
--
-- Deduplication and the observation identity column are part of this one create (dev QuestDB is
-- disposable, so there are no incremental migrations to keep).
--
-- SYMBOL CAPACITY is the expected number of distinct values; it is sized for 1,000+ spacecraft
-- (4x headroom: 4,096) and for a mission catalog of thousands of points (16,384), so the symbol
-- maps never resize mid-ingest. The default of 256 is far below a constellation's craft count.
-- Retention: Cadence drops whole day partitions (Cadence.Telemetry.Storage.QuestDB.Retention).

CREATE TABLE IF NOT EXISTS telemetry_observations (
  observed_at TIMESTAMP,
  generation_time TIMESTAMP,
  receipt_time TIMESTAMP,
  ingested_at TIMESTAMP,

  organization_id SYMBOL,
  mission_id SYMBOL,
  realm SYMBOL,
  data_source_id SYMBOL,
  binding_id SYMBOL,
  source_endpoint_id SYMBOL CAPACITY 4096,
  replay_run_id SYMBOL,

  observation_id STRING,
  observation_identity_id STRING,
  idempotency_key STRING,
  sample_id STRING,
  spacecraft_id SYMBOL CAPACITY 4096,
  observable_id SYMBOL CAPACITY 16384,
  point_id SYMBOL CAPACITY 16384,
  point_name STRING,

  packet_definition_id SYMBOL,
  packet_definition_version LONG,
  packet_id STRING,
  evidence_id STRING,

  value_kind SYMBOL,
  value_double DOUBLE,
  value_long LONG,
  value_bool BOOLEAN,
  value_string STRING,
  raw_value_text STRING,

  quality_state SYMBOL,
  validity_state SYMBOL,
  revision LONG,
  supersedes_observation_id STRING,

  provenance_json STRING,
  metadata_json STRING
) TIMESTAMP(observed_at) PARTITION BY DAY WAL
DEDUP UPSERT KEYS(observed_at, idempotency_key);
