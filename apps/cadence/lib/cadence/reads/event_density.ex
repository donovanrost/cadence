defmodule Cadence.Reads.EventDensity do
  @moduledoc """
  The Timeline density bar counted in SQL (lead 11-15): severity counts per bucket without
  loading event rows or their JSON documents. Per-write watermark rows are ~30 KB each on dev, so
  loading even 5,000 of them timed the read out.

  One query over both timeline sources, on the same axes as the page:

    * operational events on the effective axis (`COALESCE(effective_at, occurred_at)`);
    * projected mission events on `occurred_at`, minus the ones that mirror an operational event
      (`source_record_kind = 'operational_event'`; the page replaces those by id);

  then the page's duplicate rule in SQL (`DISTINCT ON (bucket, kind, subject, second)`, the more
  severe kept), grouped by the few columns the console kind and severity depend on. Each group
  comes back as `%{bucket, kind, source, category, source_record_kind, severity, cleared,
  retreat_reason, count}`; `Cadence.Reads.EventLog` maps them with the page's own rules. JSON is
  read only for a watermark retreat's reason (`CASE`, so only those rows) and an event's small
  `current` status.
  """

  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  @housekeeping "AND kind NOT LIKE 'source\\_%' AND kind NOT LIKE '%watermark%'"

  @spec groups(binary(), binary(), DateTime.t(), DateTime.t(), pos_integer(), boolean()) ::
          [map()]
  def groups(organization_id, mission_id, from, to, bucket_s, skip_housekeeping?) do
    skip = if skip_housekeeping?, do: @housekeeping, else: ""

    sql = """
    WITH u AS (
      SELECT floor(extract(epoch FROM (COALESCE(effective_at, occurred_at) - $3::timestamp)) / $5::integer)::bigint AS b,
             kind, 'operational' AS src, category, 'operational_event' AS srk, severity,
             COALESCE(COALESCE(current_document -> 'value' ->> 'status',
                               current_document -> 'value' ->> 'state',
                               current_document ->> 'status') IN ('cleared', 'resolved'), false)
               AS cleared,
             CASE WHEN kind = 'source_watermark_retreated'
                  THEN replay_run_id IS NOT NULL
                       OR COALESCE(payload_document -> 'value' ->> 'reason',
                                   payload_document ->> 'reason', '') ~ '(replay|late)'
                  ELSE false END AS retreat_reason,
             COALESCE(subject_id, '') AS subj,
             date_trunc('second', COALESCE(effective_at, occurred_at)) AS sec
        FROM operational_events
       WHERE organization_id = $1 AND mission_id = $2
         AND COALESCE(effective_at, occurred_at) >= $3
         AND COALESCE(effective_at, occurred_at) < $4
         #{skip}
      UNION ALL
      SELECT floor(extract(epoch FROM (occurred_at - $3::timestamp)) / $5::integer)::bigint,
             kind, 'projected', category, source_record_kind, severity,
             COALESCE(status IN ('cleared', 'resolved'), false), false,
             COALESCE(subject_id, realized_contact_id, scheduled_contact_id, ''),
             date_trunc('second', occurred_at)
        FROM mission_events
       WHERE organization_id = $1 AND mission_id = $2
         AND occurred_at >= $3 AND occurred_at < $4
         AND source_record_kind IS DISTINCT FROM 'operational_event'
         #{skip}
    ), d AS (
      SELECT DISTINCT ON (b, kind, subj, sec) b, kind, src, category, srk, severity, cleared,
             retreat_reason
        FROM u
       ORDER BY b, kind, subj, sec,
                CASE WHEN severity IN ('critical', 'error') THEN 3
                     WHEN severity = 'warning' THEN 2 ELSE 1 END DESC
    )
    SELECT b, kind, src, category, srk, severity, cleared, retreat_reason, count(*)
      FROM d
     GROUP BY b, kind, src, category, srk, severity, cleared, retreat_reason
    """

    params = [organization_id, mission_id, naive(from), naive(to), bucket_s]

    Repo
    |> SQL.query!(sql, params)
    |> Map.fetch!(:rows)
    |> Enum.map(fn [b, kind, src, category, srk, severity, cleared, retreat, count] ->
      %{
        bucket: b,
        kind: kind,
        source: src,
        category: category,
        source_record_kind: srk,
        severity: severity,
        cleared: cleared,
        retreat_reason: retreat,
        count: count
      }
    end)
  end

  defp naive(%DateTime{} = at), do: at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive()
end
