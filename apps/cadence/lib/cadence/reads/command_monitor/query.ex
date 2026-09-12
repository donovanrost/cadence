defmodule Cadence.Reads.CommandMonitor.Query do
  @moduledoc false

  alias Cadence.Reads.CommandMonitor.Search

  @search Enum.map_join(
            ["command_name", "command_id", "command_request_id", "target", "requested_by"],
            " OR ",
            &"strpos(#{Search.expression(&1)}, $5::text) > 0"
          )
  @rank "CASE status WHEN 'failed' THEN 0 WHEN 'indeterminate' THEN 1 " <>
          "WHEN 'release_pending' THEN 2 WHEN 'in_flight' THEN 3 WHEN 'queued' THEN 4 " <>
          "WHEN 'approval_pending' THEN 5 WHEN 'approved' THEN 6 WHEN 'validated' THEN 7 " <>
          "WHEN 'released' THEN 8 ELSE 9 END"
  @order "#{@rank}, coalesce(occurred_at, timestamp '1970-01-01') DESC, " <>
           "command_request_id COLLATE \"C\""

  @sql """
  WITH facts AS MATERIALIZED (
    SELECT r.command_request_id, r.command_id,
      coalesce(r.command_display_name, r.command_name, r.command_id) AS command_name,
      r.source_endpoint_ref AS target,
      CASE WHEN jsonb_typeof(label.value) = 'string' THEN label.value #>> '{}' END AS requested_by,
      r.requested_at,
      CASE WHEN r.lifecycle_state IN ('draft','validated','approval_pending','approved','rejected','queued','released','canceled')
        THEN r.lifecycle_state ELSE 'draft' END AS request_state,
      CASE WHEN r.verification_state IN ('not_required','pending','satisfied','failed','timed_out')
        THEN r.verification_state END AS request_verification,
      q.command_queue_entry_id, q.queue_lane_key,
      CASE WHEN q.command_queue_entry_id IS NULL THEN NULL
        WHEN q.lifecycle_state IN ('pending','release_pending','released','canceled')
        THEN q.lifecycle_state ELSE 'pending' END AS queue_state,
      q.enqueued_at,
      a.command_release_attempt_id, a.command_queue_entry_id AS release_queue_id,
      a.lifecycle_state AS release_state, a.verification_state AS release_verification,
      a.realized_contact_id, a.attempted_at, a.released_at,
      v.verifier_total, v.failed, v.timed_out, v.pending, v.satisfied,
      greatest(r.requested_at, q.enqueued_at, a.attempted_at, a.released_at, v.occurred_at) AS occurred_at
    FROM command_requests r
    CROSS JOIN LATERAL (
      SELECT CASE WHEN r.requested_by_document ? 'value'
        THEN r.requested_by_document->'value' ELSE r.requested_by_document END AS doc
    ) actor
    CROSS JOIN LATERAL (
      SELECT coalesce(nullif(nullif(actor.doc->'display_name', 'false'::jsonb), 'null'::jsonb),
                      nullif(nullif(actor.doc->'email', 'false'::jsonb), 'null'::jsonb),
                      nullif(nullif(actor.doc->'user_id', 'false'::jsonb), 'null'::jsonb),
                      '"Unknown"'::jsonb) AS value
    ) label
    LEFT JOIN command_queue_entries q ON q.organization_id = $1 AND q.mission_id = $2
      AND q.command_request_id = r.command_request_id
    LEFT JOIN LATERAL (
      SELECT a.command_release_attempt_id, a.command_queue_entry_id,
        CASE WHEN a.lifecycle_state IN ('release_pending','released','release_failed','release_uncertain','canceled')
          THEN a.lifecycle_state ELSE 'release_pending' END AS lifecycle_state,
        CASE WHEN a.verification_state IN ('not_required','pending','satisfied','failed','timed_out')
          THEN a.verification_state END AS verification_state, a.realized_contact_id,
        a.attempted_at, a.released_at
      FROM command_release_attempts a
      WHERE a.organization_id = $1 AND a.mission_id = $2
        AND a.command_request_id = r.command_request_id
      ORDER BY a.attempted_at DESC NULLS FIRST, a.command_release_attempt_id DESC
      LIMIT 1
    ) a ON true
    CROSS JOIN LATERAL (
      SELECT count(*) AS verifier_total,
        bool_or(v.lifecycle_state = 'failed') AS failed,
        bool_or(v.lifecycle_state = 'timed_out') AS timed_out,
        bool_or(coalesce(v.lifecycle_state NOT IN ('satisfied','failed','timed_out','canceled'), true)) AS pending,
        bool_and(v.lifecycle_state = 'satisfied') AS satisfied,
        max(greatest(v.matched_at, v.timeout_at)) AS occurred_at
      FROM command_verifier_instances v
      WHERE v.organization_id = $1 AND v.mission_id = $2
        AND v.command_request_id = r.command_request_id
    ) v
    WHERE r.organization_id = $1 AND r.mission_id = $2
  ), classified AS MATERIALIZED (
    SELECT facts.*,
      CASE
        WHEN request_verification IN ('failed', 'timed_out')
          OR release_verification IN ('failed', 'timed_out') OR failed OR timed_out THEN 'failed'
        WHEN release_state = 'release_failed' THEN 'failed'
        WHEN release_state = 'release_uncertain' THEN 'indeterminate'
        WHEN release_state = 'release_pending' OR queue_state = 'release_pending' THEN 'release_pending'
        WHEN release_state = 'released' THEN CASE
          WHEN request_verification = 'pending' OR release_verification = 'pending' OR pending
          THEN 'in_flight' ELSE 'released' END
        WHEN queue_state = 'pending' THEN 'queued'
        ELSE coalesce(request_state, 'indeterminate')
      END AS status,
      CASE WHEN failed THEN 'failed' WHEN timed_out THEN 'timed_out'
        WHEN pending THEN 'pending' WHEN verifier_total > 0 AND satisfied THEN 'satisfied'
        WHEN command_release_attempt_id IS NOT NULL THEN release_verification
        ELSE request_verification END AS verification_state
    FROM facts
  ), matching AS MATERIALIZED (
    SELECT * FROM classified
    WHERE ($3::text = 'all' OR status = $3) AND ($4::text = 'all' OR target = $4)
      AND ($5::text = '' OR (#{@search}))
  ), totals AS (
    SELECT count(*) AS total, greatest(1, (count(*) + 24) / 25) AS pages FROM matching
  ), position AS (
    SELECT total, pages, least($6::bigint, pages) AS page FROM totals
  ), page_rows AS MATERIALIZED (
    SELECT command_request_id, row_number() OVER (ORDER BY #{@order}) AS ordinal
    FROM matching ORDER BY #{@order}
    LIMIT 25 OFFSET (SELECT (page - 1) * 25 FROM position)
  ), selected AS MATERIALIZED (
    SELECT command_request_id FROM page_rows
    UNION SELECT command_request_id FROM classified WHERE command_request_id = $7::text
  ), projected AS MATERIALIZED (
    SELECT c.command_request_id, jsonb_build_object(
      'command_request_id', c.command_request_id, 'command_id', c.command_id,
      'command_name', c.command_name, 'target', c.target, 'requested_by', c.requested_by,
      'requested_at', c.requested_at, 'occurred_at', c.occurred_at,
      'request_state', c.request_state, 'status', c.status, 'verification_state', c.verification_state,
      'verifier_total', c.verifier_total,
      'queue_entry', CASE WHEN c.command_queue_entry_id IS NULL THEN NULL ELSE jsonb_build_object(
        'command_queue_entry_id', c.command_queue_entry_id, 'queue_lane_key', c.queue_lane_key,
        'lifecycle_state', c.queue_state, 'enqueued_at', c.enqueued_at) END,
      'release_attempt', CASE WHEN c.command_release_attempt_id IS NULL THEN NULL ELSE jsonb_build_object(
        'command_release_attempt_id', c.command_release_attempt_id,
        'command_queue_entry_id', c.release_queue_id, 'lifecycle_state', c.release_state,
        'verification_state', c.release_verification, 'realized_contact_id', c.realized_contact_id,
        'attempted_at', c.attempted_at, 'released_at', c.released_at) END,
      'verifier_instances', previews.items
    ) AS data
    FROM classified c JOIN selected s USING (command_request_id)
    CROSS JOIN LATERAL (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'command_verifier_instance_id', v.command_verifier_instance_id,
        'command_release_attempt_id', v.command_release_attempt_id,
        'verifier_name', v.verifier_name, 'lifecycle_state', v.lifecycle_state,
        'matched_at', v.matched_at, 'timeout_at', v.timeout_at,
        'matched_record_kind', v.matched_record_kind, 'matched_record_id', v.matched_record_id
      ) ORDER BY v.inserted_at, v.command_verifier_instance_id), '[]'::jsonb) AS items
      FROM (
        SELECT command_verifier_instance_id, command_release_attempt_id, verifier_name,
          CASE WHEN lifecycle_state IN ('pending','satisfied','failed','timed_out','canceled')
            THEN lifecycle_state ELSE 'pending' END AS lifecycle_state,
          matched_at, timeout_at,
          CASE WHEN matched_record_kind IN ('telemetry_sample','transport_action_request','transport_capability_record')
            THEN matched_record_kind END AS matched_record_kind, matched_record_id, inserted_at
        FROM command_verifier_instances v WHERE v.organization_id = $1 AND v.mission_id = $2
          AND v.command_request_id = c.command_request_id
        ORDER BY v.inserted_at, v.command_verifier_instance_id LIMIT 20
      ) v
    ) previews
  ), bounded AS MATERIALIZED (
    SELECT command_request_id,
      CASE WHEN octet_length(data::text) <= 65536 THEN data ELSE '{"invalid": true}'::jsonb END AS data
    FROM projected
  ), targets AS MATERIALIZED (
    SELECT DISTINCT target COLLATE "C" AS target FROM classified WHERE target IS NOT NULL
    ORDER BY target COLLATE "C" LIMIT 201
  )
  SELECT jsonb_build_object(
    'total', position.total, 'pages', position.pages, 'page', position.page,
    'summary', (SELECT jsonb_build_object(
      'total_count', count(*),
      'active_count', count(*) FILTER (WHERE status IN ('queued','release_pending','in_flight','failed','indeterminate')),
      'queued_count', count(*) FILTER (WHERE status = 'queued'),
      'release_pending_count', count(*) FILTER (WHERE status = 'release_pending'),
      'in_flight_count', count(*) FILTER (WHERE status = 'in_flight'),
      'released_count', count(*) FILTER (WHERE status = 'released'),
      'failed_count', count(*) FILTER (WHERE status = 'failed'),
      'indeterminate_count', count(*) FILTER (WHERE status = 'indeterminate')
    ) FROM classified),
    'targets', (SELECT coalesce(jsonb_agg(CASE WHEN octet_length(target) BETWEEN 1 AND 256
      THEN target ELSE NULL END ORDER BY target COLLATE "C"), '[]'::jsonb) FROM targets),
    'rows', (SELECT coalesce(jsonb_agg(b.data ORDER BY p.ordinal), '[]'::jsonb)
      FROM page_rows p JOIN bounded b USING (command_request_id)),
    'focus', (SELECT data FROM bounded WHERE command_request_id = $7::text)
  ) FROM position
  """

  def statement, do: @sql
end
