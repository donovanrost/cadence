-- Store observation provenance as typed columns (DECISIONS #103; docs/apogee/domain/
-- provenance-storage.md, option B). provenance_json keeps only the residual keys that have no
-- column, and is null when nothing is left.
--
-- Additive and metadata-only: existing partitions read these columns as null (flags false), and
-- the reader decodes their full provenance_json as before.
--
-- A SYMBOL dictionary is per column and never pruned, so CAPACITY is sized for every tenant on a
-- platform-shared instance over the table's life ("Symbol CAPACITY" in the design). The two
-- per-point columns are NOCACHE (10^5 long strings would otherwise sit on the heap; no read path
-- filters on them). QuestDB 9.1+ auto-scales a dictionary past 80% of its capacity.

ALTER TABLE telemetry_observations ADD COLUMN IF NOT EXISTS
  mission_model_revision_id SYMBOL CAPACITY 16384 CACHE,
  runtime_plan_id SYMBOL CAPACITY 32768 CACHE,
  producer_kind SYMBOL CAPACITY 256 CACHE,
  producer_id SYMBOL CAPACITY 16384 CACHE,
  semantic_id SYMBOL CAPACITY 262144 NOCACHE,
  qualified_name SYMBOL CAPACITY 262144 NOCACHE,
  identity_ref VARCHAR,
  binding_rule_derived BOOLEAN,
  packet_refs_derived BOOLEAN;
