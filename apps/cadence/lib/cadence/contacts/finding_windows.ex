defmodule Cadence.Contacts.FindingWindows do
  @moduledoc "Set-based contact findings and counts over a mission's filtered time window."

  alias Cadence.Contacts.PassWindows
  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  @doc "Returns only one page of finding facts, with counts over all matching findings."
  def page(org, mission, from, to, opts) do
    max_gap_s = Keyword.fetch!(opts, :max_gap_s)
    query = PassWindows.finding_bookings(org, mission, DateTime.add(from, -max_gap_s), to)
    {bookings_sql, bindings} = SQL.to_sql(:all, Repo, query)
    payload = payload(from, to, opts)
    argument = "$#{length(bindings) + 1}::jsonb"

    %{rows: [[conflicts, gaps, findings]]} =
      Repo.query!(findings_sql(bookings_sql, argument), bindings ++ [payload])

    {%{conflicts: conflicts, gaps: gaps}, findings || []}
  end

  defp payload(from, to, opts) do
    {at, id} =
      case Keyword.fetch!(opts, :after) do
        nil -> {nil, nil}
        {at, id, _kind} -> {DateTime.to_iso8601(at), id}
      end

    outages =
      for {station_id, windows} <- Keyword.fetch!(opts, :outages),
          {window, position} <- Enum.with_index(windows) do
        %{
          station_id: station_id,
          id: window.window_id,
          starts_at: DateTime.to_iso8601(window.starts_at),
          ends_at: window.ends_at && DateTime.to_iso8601(window.ends_at),
          position: position
        }
      end

    %{
      from: DateTime.to_iso8601(from),
      to: DateTime.to_iso8601(to),
      max_gap_s: Keyword.fetch!(opts, :max_gap_s),
      limit: Keyword.fetch!(opts, :limit) + 1,
      after_at: at,
      after_id: id,
      spacecraft_ids: Keyword.fetch!(opts, :spacecraft_ids),
      station_ids_by_ref: Keyword.fetch!(opts, :station_ids_by_ref),
      outages: outages
    }
  end

  # Time comparisons use UTC timestamps, the same representation as the reservation columns.
  # The last booking before the window anchors coverage, and a running maximum keeps overlaps
  # from reopening the gap before a longer booking ends. Send booking detail only for this page.
  defp findings_sql(bookings_sql, argument) do
    """
    WITH bounds AS (
      SELECT (#{argument}->>'from')::timestamp AS from_at,
             (#{argument}->>'to')::timestamp AS to_at,
             (#{argument}->>'after_at')::timestamp AS after_at,
             #{argument}->>'after_id' AS after_id,
             (#{argument}->>'max_gap_s')::integer AS max_gap_s
    ), booking_facts AS (
      #{bookings_sql}
    ), bookings AS MATERIALIZED (
      SELECT b.*, (#{argument}->'station_ids_by_ref')->>b.station_ref AS station_id
      FROM booking_facts b
    ), visible AS (
      SELECT b.* FROM bookings b CROSS JOIN bounds w WHERE b.ends_at > w.from_at
    ), adjacent AS (
      SELECT b.*,
             lag(id) OVER (PARTITION BY coalesce(station_id, station_ref)
                           ORDER BY starts_at, id COLLATE "C") AS previous_id
      FROM visible b WHERE coalesce(station_id, station_ref) IS NOT NULL
    ), conflicts AS (
      SELECT 'station_double_booked:' || a.id || ':' || b.id AS id,
             'station_double_booked' AS kind, b.starts_at AS at,
             a.id AS first_id, b.id AS second_id, NULL::text AS spacecraft_id,
             NULL::timestamp AS gap_end
      FROM adjacent b JOIN visible a ON a.id = b.previous_id
      WHERE least(a.ends_at, b.ends_at) - greatest(a.starts_at, b.starts_at) >= interval '1 second'
        AND (a.antenna_ref IS NULL OR b.antenna_ref IS NULL OR a.antenna_ref = b.antenna_ref)
    ), outages AS (
      SELECT * FROM jsonb_to_recordset(#{argument}->'outages')
        AS w(station_id text, id text, starts_at timestamp, ends_at timestamp, position integer)
    ), outages_hit AS (
      SELECT 'booked_into_outage:' || b.id || ':' || o.id AS id,
             'booked_into_outage' AS kind, b.starts_at AS at,
             b.id AS first_id, NULL::text AS second_id, NULL::text AS spacecraft_id,
             NULL::timestamp AS gap_end
      FROM visible b
      JOIN LATERAL (
        SELECT o.id FROM outages o
        WHERE o.station_id = b.station_id AND o.starts_at < b.ends_at
          AND (o.ends_at IS NULL OR o.ends_at > b.starts_at)
        ORDER BY o.position LIMIT 1
      ) o ON TRUE
    ), previous AS (
      SELECT DISTINCT ON (b.spacecraft_id) b.spacecraft_id, b.ends_at
      FROM bookings b CROSS JOIN bounds w WHERE b.ends_at < w.from_at
      ORDER BY b.spacecraft_id, b.starts_at DESC, b.id COLLATE "C" DESC
    ), origins AS (
      SELECT craft.id AS spacecraft_id, coalesce(p.ends_at, w.from_at) AS starts_at
      FROM jsonb_array_elements_text(#{argument}->'spacecraft_ids') craft(id)
      CROSS JOIN bounds w LEFT JOIN previous p ON p.spacecraft_id = craft.id
    ), coverage_bookings AS MATERIALIZED (
      SELECT o.spacecraft_id, b.id, b.starts_at, b.ends_at,
             greatest(o.starts_at, max(b.ends_at) OVER (
               PARTITION BY o.spacecraft_id ORDER BY b.starts_at, b.id COLLATE "C"
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
             )) AS gap_start
      FROM origins o JOIN bookings b ON b.spacecraft_id = o.spacecraft_id
      CROSS JOIN bounds w WHERE b.ends_at >= w.from_at
    ), gap_intervals AS (
      SELECT spacecraft_id, gap_start, starts_at AS gap_end FROM coverage_bookings
      UNION ALL
      SELECT o.spacecraft_id, greatest(o.starts_at, max(b.ends_at)), w.to_at
      FROM origins o CROSS JOIN bounds w LEFT JOIN coverage_bookings b USING (spacecraft_id)
      GROUP BY o.spacecraft_id, o.starts_at, w.to_at
    ), gaps AS (
      SELECT 'coverage_gap:' || g.spacecraft_id || ':' || floor(extract(epoch FROM g.gap_start))::bigint AS id,
             'coverage_gap' AS kind, g.gap_start AS at,
             NULL::text AS first_id, NULL::text AS second_id, g.spacecraft_id, g.gap_end
      FROM gap_intervals g CROSS JOIN bounds w
      WHERE g.gap_end > w.from_at AND floor(extract(epoch FROM g.gap_end - g.gap_start)) > w.max_gap_s
    ), findings AS MATERIALIZED (
      SELECT * FROM conflicts UNION ALL SELECT * FROM outages_hit UNION ALL SELECT * FROM gaps
    ), page AS (
      SELECT f.* FROM findings f CROSS JOIN bounds w
      WHERE w.after_at IS NULL OR (f.at, f.id COLLATE "C") > (w.after_at, w.after_id COLLATE "C")
      ORDER BY f.at, f.id COLLATE "C"
      LIMIT (#{argument}->>'limit')::integer
    )
    SELECT (SELECT count(*) FROM findings WHERE kind <> 'coverage_gap'),
           (SELECT count(*) FROM findings WHERE kind = 'coverage_gap'),
           (SELECT jsonb_agg(
                     to_jsonb(f) || jsonb_build_object('first', to_jsonb(a), 'second', to_jsonb(b))
                     ORDER BY f.at, f.id COLLATE "C"
                   )
            FROM page f LEFT JOIN bookings a ON a.id = f.first_id
                        LEFT JOIN bookings b ON b.id = f.second_id)
    """
  end
end
