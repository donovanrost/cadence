defmodule Cadence.Reads.CommandHistory.EvidenceQuery do
  @moduledoc false

  @sql """
  evidence_candidates AS (
    SELECT jsonb_build_object(
      'kind', 'telemetry_sample', 'id', s.sample_id,
      'organization_id', s.organization_id, 'mission_id', s.mission_id,
      'point_id', s.point_id, 'point_name', s.point_name, 'packet_id', s.packet_id,
      'evidence_id', s.evidence_id, 'spacecraft_id', s.spacecraft_id,
      'quality_state', s.quality_state, 'generation_time', s.generation_time,
      'receipt_time', s.receipt_time,
      'raw_value_json', (CASE WHEN s.raw_value ? 'value' THEN s.raw_value->'value' ELSE s.raw_value END)::text,
      'engineering_value_json', (CASE WHEN s.engineering_value ? 'value' THEN s.engineering_value->'value' ELSE s.engineering_value END)::text
    ) AS data
    FROM selected_verifier v JOIN telemetry_samples s ON v.raw_kind = 'telemetry_sample'
      AND s.sample_id = v.raw_id AND s.organization_id = $1 AND s.mission_id = $2
    UNION ALL
    SELECT jsonb_build_object(
      'kind', 'transport_action_request', 'id', a.action_request_id,
      'organization_id', a.organization_id, 'mission_id', a.mission_id,
      'request_id', a.command_request_id, 'release_attempt_id', a.command_release_attempt_id,
      'contact_id', a.realized_contact_id, 'path_id', a.path_id, 'family_key', a.family_key,
      'signal_phase', a.signal_phase, 'action_kind', a.action_kind, 'requested_at', a.requested_at
    ) AS data
    FROM selected_verifier v JOIN transport_action_requests a
      ON v.raw_kind = 'transport_action_request' AND a.action_request_id = v.raw_id
      AND a.organization_id = $1 AND a.mission_id = $2
      AND a.command_request_id = $3 AND a.command_release_attempt_id = v.release_id
    UNION ALL
    SELECT jsonb_build_object(
      'kind', 'transport_capability_record', 'id', c.transport_record_id,
      'organization_id', c.organization_id, 'mission_id', c.mission_id,
      'request_id', $3::text, 'release_attempt_id', v.release_id,
      'contact_id', c.realized_contact_id, 'path_id', c.path_id, 'family_key', c.family_key,
      'event_kind', c.event_kind, 'recorded_at', c.recorded_at
    ) AS data
    FROM selected_verifier v JOIN transport_capability_records c
      ON v.raw_kind = 'transport_capability_record' AND c.transport_record_id = v.raw_id
      AND c.organization_id = $1 AND c.mission_id = $2
    CROSS JOIN LATERAL (
      SELECT CASE WHEN c.state_snapshot ? 'value' THEN c.state_snapshot->'value' ELSE c.state_snapshot END AS state,
        CASE WHEN c.metadata ? 'value' THEN c.metadata->'value' ELSE c.metadata END AS meta
    ) doc
    WHERE jsonb_typeof(doc.state) = 'object' AND jsonb_typeof(doc.meta) = 'object'
      AND coalesce(nullif(nullif(doc.state->'last_command_request_id', 'false'::jsonb), 'null'::jsonb),
        doc.meta->'command_request_id') = to_jsonb($3::text)
      AND coalesce(nullif(nullif(doc.state->'last_release_attempt_id', 'false'::jsonb), 'null'::jsonb),
        doc.meta->'command_release_attempt_id') = to_jsonb(v.release_id)
  ), bounded_evidence AS (
    SELECT (SELECT CASE WHEN octet_length(data::text) <= 147456 THEN data END
      FROM evidence_candidates) AS record
  )
  """

  def ctes, do: @sql
end
