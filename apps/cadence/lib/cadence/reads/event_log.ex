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

  alias Cadence.Dashboards.DocumentStore
  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.{EventContacts, EventSentences, MissionTimeline, SpacecraftMetadata}
  alias Cadence.SpacecraftStore

  @kinds ~w(limit flight_event contact command config operator data)
  @no_names %{spacecraft: %{}, users: %{}, dashboards: %{}, contacts: %{}}
  @density_cap 5_000

  @spec kinds() :: [binary()]
  def kinds, do: @kinds

  @doc """
  Options: `:from`, `:to`, `:spacecraft_id`, `:plane` (the spacecraft in that orbital plane,
  from spacecraft metadata; with `:spacecraft_id`, only that one if it's in the plane), `:kinds`
  (console kinds), `:limit`, `:cursor`.
  """
  @spec page(binary(), binary(), map()) :: {:ok, map()} | {:error, :invalid_cursor}
  def page(organization_id, mission_id, opts) do
    with {:ok, cursor} <- decode_cursor(opts[:cursor]) do
      page =
        MissionTimeline.page_for_mission(organization_id, mission_id,
          from_occurred_at: opts.from,
          to_occurred_at: opts.to,
          spacecraft_id: spacecraft_filter(organization_id, mission_id, opts),
          limit: opts.limit,
          cursor: cursor
        )

      {entries, contacts} = EventContacts.enrich(organization_id, mission_id, page.entries)
      context = Map.put(context(organization_id, mission_id, entries), :contacts, contacts)

      {:ok,
       %{
         events:
           entries
           |> Enum.map(&event(&1, context))
           |> dedupe()
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
        spacecraft_id: spacecraft_filter(organization_id, mission_id, opts),
        limit: @density_cap
      )

    origin = DateTime.to_unix(opts.from)

    counts =
      entries
      |> Enum.map(&event(&1, @no_names))
      |> dedupe()
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

  defp event(%Entry{} = entry, context) do
    described = EventSentences.describe(entry, context)

    %{
      id: entry.mission_event_id,
      at: entry.occurred_at,
      kind: kind(entry),
      raw_kind: entry.kind && to_string(entry.kind),
      severity: described.severity || severity(entry),
      text: described.text,
      detail: nil,
      spacecraft: spacecraft(entry.spacecraft_id, context.spacecraft),
      refs: %{
        subject: described.subject,
        alarm_id: nil,
        point_id: if(entry.subject_kind == :telemetry_point, do: entry.subject_id),
        command_request_id: (entry.metadata || %{})["command_request_id"],
        contact_id: entry.realized_contact_id || entry.scheduled_contact_id
      }
    }
  end

  defp kind(%Entry{kind: kind} = entry) when is_atom(kind) or is_binary(kind) do
    raw = to_string(kind)

    cond do
      housekeeping?(raw) -> "data"
      String.contains?(raw, "contact") -> "contact"
      true -> classify(entry)
    end
  end

  defp kind(entry), do: classify(entry)

  @severity_rank %{critical: 3, caution: 2, nominal: 1, info: 0}

  # The same fact can reach the timeline from two sources (a projected mission event and its
  # operational event): same kind, subject and second. Keep one, the more severe.
  defp dedupe(events) do
    events
    |> Enum.chunk_by(&{&1.raw_kind, subject_id(&1), DateTime.truncate(&1.at, :second)})
    |> Enum.map(fn
      [event] -> event
      same -> Enum.max_by(same, &Map.fetch!(@severity_rank, &1.severity))
    end)
  end

  defp subject_id(%{refs: %{subject: %{id: id}}}), do: id
  defp subject_id(%{refs: refs}), do: refs.contact_id

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

  # Names the sentences use: spacecraft always, people and dashboards only when the page has them.
  defp context(organization_id, mission_id, entries) do
    users =
      entries
      |> Enum.map(&EventSentences.actor_id(&1.actor))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Map.new(fn id ->
        case Cadence.Accounts.fetch_user(id) do
          {:ok, user} -> {id, user.display_name || user.email}
          _missing -> {id, nil}
        end
      end)

    dashboards =
      if Enum.any?(entries, &String.starts_with?(to_string(&1.kind), "dashboard_")),
        do:
          organization_id
          |> DocumentStore.list_dashboard_summaries(mission_id)
          |> Map.new(&{&1.dashboard_id, &1.name}),
        else: %{}

    %{
      spacecraft: spacecraft_names(organization_id, mission_id),
      users: users,
      dashboards: dashboards
    }
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

  # A plane filter becomes the list of its spacecraft (an empty plane matches nothing).
  defp spacecraft_filter(_organization_id, _mission_id, %{plane: nil} = opts),
    do: opts[:spacecraft_id]

  defp spacecraft_filter(organization_id, mission_id, %{plane: plane} = opts)
       when is_integer(plane) do
    in_plane =
      for craft <- SpacecraftStore.list_spacecraft(organization_id, mission_id),
          SpacecraftMetadata.integer(craft.metadata || %{}, "plane") == plane,
          do: craft.spacecraft_id

    case opts[:spacecraft_id] do
      nil -> in_plane
      id -> Enum.filter(in_plane, &(&1 == id))
    end
  end

  defp spacecraft_filter(_organization_id, _mission_id, opts), do: opts[:spacecraft_id]
end
