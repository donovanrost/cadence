defmodule Cadence.Reads.CommandHistory.Query do
  @moduledoc """
  One scoped statement snapshot for two 25-row history ledgers and independent selections.
  The database uses one lookahead row per ledger. Cursor identities are resolved inside
  the same request and selected release. Result size is bounded before database return;
  database scan and aggregation work are not constant. No wire payloads are selected.
  """
  alias Cadence.Reads.CommandHistory.EvidenceQuery

  @sql """
  WITH request AS MATERIALIZED (
    SELECT jsonb_build_object('id', r.command_request_id,
      'command_id', r.command_id,
      'name', coalesce(r.command_display_name,r.command_name,r.command_id),
      'target', r.source_endpoint_ref,
      'target_name', endpoint.display_name,
      'model_revision_id', r.mission_model_revision_id,
      'state', CASE WHEN r.lifecycle_state IN ('draft','validated','approval_pending','approved','rejected','queued','released','canceled') THEN r.lifecycle_state ELSE 'draft' END,
      'verification_state', CASE WHEN r.verification_state IN ('not_required','pending','satisfied','failed','timed_out') THEN r.verification_state ELSE NULL END) AS data FROM command_requests r
    LEFT JOIN mission_source_endpoints endpoint ON endpoint.organization_id = $1 AND endpoint.mission_id = $2
      AND endpoint.source_endpoint_id = r.source_endpoint_ref
    WHERE r.organization_id = $1 AND r.mission_id = $2 AND r.command_request_id = $3
  ), releases AS MATERIALIZED (
    SELECT a.command_release_attempt_id AS id, a.attempted_at AS occurred_at,
      jsonb_build_object('id', a.command_release_attempt_id,
      'request_id', a.command_request_id,
      'queue_entry_id', a.command_queue_entry_id,
      'contact_id', a.realized_contact_id,
      'path_id', a.path_id,
      'binding_id', a.transport_binding_id,
      'state', CASE WHEN a.lifecycle_state IN ('release_pending','released','release_failed','release_uncertain','canceled') THEN a.lifecycle_state ELSE 'release_pending' END,
      'verification_state', CASE WHEN a.verification_state IN ('not_required','pending','satisfied','failed','timed_out') THEN a.verification_state ELSE NULL END,
      'attempted_at', a.attempted_at,
      'released_at', a.released_at,
      'encoded_size_bytes', a.encoded_size_bytes) AS data
    FROM command_release_attempts a WHERE a.organization_id = $1 AND a.mission_id = $2
      AND a.command_request_id = $3 AND EXISTS (SELECT 1 FROM request)
  ), verifiers AS MATERIALIZED (
    SELECT v.command_verifier_instance_id AS id, v.inserted_at AS occurred_at,
      v.command_release_attempt_id AS release_id,
      v.matched_record_kind AS raw_kind, v.matched_record_id AS raw_id,
      jsonb_build_object('id', v.command_verifier_instance_id,
      'request_id', v.command_request_id,
      'release_attempt_id', v.command_release_attempt_id,
      'name', v.verifier_name,
      'phase', CASE WHEN v.phase IN ('acceptance','start','completion','custom') THEN v.phase ELSE 'completion' END,
      'severity', CASE WHEN v.severity IN ('info','warning','error','critical') THEN v.severity ELSE NULL END,
      'state', CASE WHEN v.lifecycle_state IN ('pending','satisfied','failed','timed_out','canceled') THEN v.lifecycle_state ELSE 'pending' END,
      'failure_code', CASE WHEN v.failure_reason IN ('timed_out','failure_criteria_matched') THEN v.failure_reason ELSE NULL END,
      'matched_at', v.matched_at,
      'timeout_at', v.timeout_at,
      'matched_record_kind', CASE WHEN v.matched_record_kind IN ('telemetry_sample','transport_action_request','transport_capability_record') THEN v.matched_record_kind ELSE NULL END,
      'matched_record_id', v.matched_record_id) AS data
    FROM command_verifier_instances v WHERE v.organization_id = $1 AND v.mission_id = $2
      AND v.command_request_id = $3 AND ($4::text = '' OR v.command_release_attempt_id = $4)
      AND EXISTS (SELECT 1 FROM request)
  ), release_cursor AS (SELECT id, occurred_at FROM releases WHERE id = $5),
  verifier_cursor AS (SELECT id, occurred_at FROM verifiers WHERE id = $6),
  release_page AS MATERIALIZED (
    SELECT id, occurred_at, data FROM releases
    WHERE $5::text = '' OR (coalesce(occurred_at, timestamp 'infinity'), id) <
      (SELECT coalesce(occurred_at, timestamp 'infinity'), id FROM release_cursor)
    ORDER BY occurred_at DESC NULLS FIRST, id DESC LIMIT 26
  ), verifier_page AS MATERIALIZED (
    SELECT id, occurred_at, data FROM verifiers
    WHERE $6::text = '' OR (coalesce(occurred_at, timestamp 'infinity'), id) >
      (SELECT coalesce(occurred_at, timestamp 'infinity'), id FROM verifier_cursor)
    ORDER BY occurred_at ASC NULLS LAST, id ASC LIMIT 26
  ), selected_release AS (SELECT data FROM releases WHERE id = $4),
  selected_verifier AS MATERIALIZED (SELECT * FROM verifiers WHERE id = $7),
  #{EvidenceQuery.ctes()},
  result AS (
    SELECT jsonb_build_object(
      'valid', EXISTS (SELECT 1 FROM request)
        AND ($4::text = '' OR EXISTS (SELECT 1 FROM selected_release))
        AND ($5::text = '' OR EXISTS (SELECT 1 FROM release_cursor))
        AND ($6::text = '' OR EXISTS (SELECT 1 FROM verifier_cursor))
        AND ($7::text = '' OR EXISTS (SELECT 1 FROM selected_verifier)),
      'request', (SELECT data FROM request),
      'release_rows', (SELECT coalesce(jsonb_agg(data ORDER BY occurred_at DESC NULLS FIRST, id DESC), '[]'::jsonb) FROM release_page),
      'verifier_rows', (SELECT coalesce(jsonb_agg(data ORDER BY occurred_at ASC NULLS LAST, id ASC), '[]'::jsonb) FROM verifier_page),
      'release', (SELECT data FROM selected_release),
      'verifier', (SELECT data FROM selected_verifier),
      'evidence', (SELECT jsonb_build_object('status', CASE
        WHEN $7::text = '' THEN 'not_selected'
        WHEN EXISTS (SELECT 1 FROM selected_verifier WHERE raw_kind IS NULL AND raw_id IS NULL) THEN 'unmatched'
        WHEN record IS NULL THEN 'unavailable' ELSE 'ready' END, 'record', record)
        FROM bounded_evidence)
    ) AS data
  )
  SELECT CASE WHEN octet_length(data::text) <= 524288 THEN data ELSE '{"valid": false}'::jsonb END FROM result
  """
  def statement, do: @sql
end
