defmodule Cadence.Reads.EventLog do
  @moduledoc """
  The console event log (Investigate B2, Timeline) on top of
  `Cadence.Reads.MissionTimeline`: newest-first events in a window with an
  opaque cursor, and a severity density histogram.

  Console vocabulary:
  - `kind`: `limit | flight_event | contact | command | config | operator | data`
    (`data` = data-plane housekeeping such as source watermarks and source health)
    (derived from the timeline entry's source and category; the original kind
    is kept as `raw_kind`).
  - `severity`: `critical | caution | nominal | info` (timeline `critical`/`error`
    → critical, `warning` → caution, cleared/resolved statuses → nominal).
  """

  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.MissionTimeline

  @kinds ~w(limit flight_event contact command config operator data)
  @density_cap 5_000

  @spec kinds() :: [binary()]
  def kinds, do: @kinds

  @doc "Options: `:from`, `:to`, `:spacecraft_id`, `:kinds` (console kinds), `:limit`, `:cursor`."
  @spec page(binary(), binary(), map()) :: {:ok, map()} | {:error, :invalid_cursor}
  def page(organization_id, mission_id, opts) do
    with {:ok, cursor} <- decode_cursor(opts[:cursor]) do
      page =
        MissionTimeline.page_for_mission(organization_id, mission_id,
          from_occurred_at: opts.from,
          to_occurred_at: opts.to,
          spacecraft_id: opts[:spacecraft_id],
          limit: opts.limit,
          cursor: cursor
        )

      names = spacecraft_names(organization_id, mission_id)

      {:ok,
       %{
         events:
           page.entries
           |> Enum.map(&event(&1, names))
           |> Enum.filter(&kind_selected?(&1, opts[:kinds])),
         next_cursor: encode_cursor(page.next_cursor)
       }}
    end
  end

  @doc "Severity counts per `bucket_s` bucket aligned to `from` (at most #{@density_cap} events read)."
  @spec density(binary(), binary(), map()) :: map()
  def density(organization_id, mission_id, opts) do
    entries =
      MissionTimeline.list_for_mission(organization_id, mission_id,
        from_occurred_at: opts.from,
        to_occurred_at: opts.to,
        spacecraft_id: opts[:spacecraft_id],
        limit: @density_cap
      )

    origin = DateTime.to_unix(opts.from)

    counts =
      entries
      |> Enum.map(&event(&1, %{}))
      |> Enum.filter(&kind_selected?(&1, opts[:kinds]))
      |> Enum.group_by(fn event -> div(DateTime.to_unix(event.at) - origin, opts.bucket_s) end)

    buckets =
      counts
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {index, events} ->
        frequencies = Enum.frequencies_by(events, & &1.severity)

        %{
          t: DateTime.from_unix!(origin + index * opts.bucket_s),
          critical: Map.get(frequencies, :critical, 0),
          caution: Map.get(frequencies, :caution, 0),
          nominal: Map.get(frequencies, :nominal, 0),
          info: Map.get(frequencies, :info, 0)
        }
      end)

    %{bucket_s: opts.bucket_s, buckets: buckets, truncated: length(entries) >= @density_cap}
  end

  defp event(%Entry{} = entry, names) do
    %{
      id: entry.mission_event_id,
      at: entry.occurred_at,
      kind: kind(entry),
      raw_kind: entry.kind && to_string(entry.kind),
      severity: severity(entry),
      text: entry.title || entry.summary,
      detail: if(entry.title, do: entry.summary),
      spacecraft: spacecraft(entry.spacecraft_id, names),
      refs: %{
        alarm_id: nil,
        point_id: if(entry.subject_kind == :telemetry_point, do: entry.subject_id),
        command_request_id: (entry.metadata || %{})["command_request_id"],
        contact_id: entry.realized_contact_id || entry.scheduled_contact_id
      }
    }
  end

  defp kind(%Entry{kind: kind} = entry) when is_atom(kind) or is_binary(kind) do
    if housekeeping?(to_string(kind)), do: "data", else: classify(entry)
  end

  defp kind(entry), do: classify(entry)

  defp housekeeping?(raw),
    do: String.starts_with?(raw, "source_") or String.contains?(raw, "watermark")

  defp classify(%Entry{source_record_kind: :limit_event}), do: "limit"
  defp classify(%Entry{kind: :limit_violation}), do: "limit"
  defp classify(%Entry{source_record_kind: :contact_action}), do: "contact"
  defp classify(%Entry{source_record_kind: :managed_action_request}), do: "command"

  defp classify(%Entry{source_record_kind: source})
       when source in [:combined_downlink_record, :downlink_diagnostic], do: "contact"

  defp classify(%Entry{kind: :binding_set_activated}), do: "config"
  defp classify(%Entry{category: :transport}), do: "contact"
  defp classify(%Entry{category: :runtime}), do: "config"
  defp classify(%Entry{category: :health}), do: "flight_event"
  defp classify(%Entry{}), do: "operator"

  defp severity(%Entry{status: status})
       when status in [:cleared, :resolved, "cleared", "resolved"],
       do: :nominal

  defp severity(%Entry{severity: severity}) when severity in [:critical, :error], do: :critical
  defp severity(%Entry{severity: :warning}), do: :caution
  defp severity(%Entry{}), do: :info

  defp spacecraft(nil, _names), do: nil

  defp spacecraft(id, names) do
    case Map.get(names, id) do
      nil -> %{id: id, name: nil, scid: nil}
      {name, scid} -> %{id: id, name: name, scid: scid}
    end
  end

  defp spacecraft_names(organization_id, mission_id) do
    organization_id
    |> Cadence.SpacecraftStore.list_spacecraft(mission_id)
    |> Map.new(&{&1.spacecraft_id, {&1.display_name, &1.scid}})
  end

  defp kind_selected?(_event, nil), do: true
  defp kind_selected?(_event, []), do: true
  defp kind_selected?(event, kinds), do: event.kind in kinds

  defp encode_cursor(nil), do: nil

  defp encode_cursor(%{occurred_at: at, mission_event_id: id}),
    do: Base.url_encode64(DateTime.to_iso8601(at) <> "|" <> id, padding: false)

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(raw, "|", parts: 2),
         {:ok, occurred_at, _offset} <- DateTime.from_iso8601(at) do
      {:ok, %{occurred_at: occurred_at, mission_event_id: id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end
end
