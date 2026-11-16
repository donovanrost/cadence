defmodule Cadence.Reads.EventLog do
  @moduledoc """
  The console event log (Investigate B2, Timeline) on top of
  `Cadence.Reads.MissionTimeline`: newest-first events in a window with an
  opaque cursor, and a severity density histogram.

  Console vocabulary:
  - `kind`: `limit | flight_event | contact | command | config | operator | data`
    (`data` = data-plane housekeeping such as source watermarks and source health)
    (derived from the timeline entry's source and category; the original kind
    is kept as `raw_kind`). `flight_event` is reserved for what the spacecraft itself
    reports (docs/apogee/domain/flight-events.md); no timeline entry is one yet. Ground
    health entries are `data`; limit-definition lifecycle entries and applied configuration
    revisions (`Cadence.Reads.ConfigRevisionEvents`) are `config`.
  - `severity`: `critical | caution | nominal | info` (timeline `critical`/`error`
    → critical, `warning` → caution, cleared/resolved statuses and a source's health
    recovering → nominal).
  """

  alias Cadence.Dashboards.DocumentStore
  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.EventLog.{ById, RawKinds}
  alias Cadence.Reads.EventLog.DensityCounts, as: EventDensityCounts

  alias Cadence.Reads.{
    EventContacts,
    EventSentences,
    MissionTimeline,
    OffPlanBookingEvents,
    SpacecraftMetadata
  }

  alias Cadence.SpacecraftStore

  @kinds ~w(limit flight_event contact command config operator data)
  @no_names %{spacecraft: %{}, users: %{}, dashboards: %{}, contacts: %{}}
  @max_rounds 10
  @density_cap 5_000

  @spec kinds() :: [binary()]
  def kinds, do: @kinds

  @doc """
  Options: `:from`, `:to`, `:spacecraft_id`, `:plane` (the spacecraft in that orbital plane,
  from spacecraft metadata; with `:spacecraft_id`, only that one if it's in the plane), `:kinds`
  (console kinds), `:raw_kinds` (`EventLog.RawKinds` patterns), `:severity_at_least` (`:caution | :critical`),
  `:limit`, `:cursor`.
  """
  @spec page(binary(), binary(), map()) :: {:ok, map()} | {:error, :invalid_cursor}
  def page(organization_id, mission_id, opts) do
    with {:ok, cursor} <- decode_cursor(opts[:cursor]) do
      {entries, next_cursor} =
        collect(organization_id, mission_id, opts, cursor, opts.limit, [], @max_rounds)

      {entries, contacts} = EventContacts.enrich(organization_id, mission_id, entries)
      context = Map.put(context(organization_id, mission_id, entries), :contacts, contacts)

      {:ok,
       %{
         events: entries |> Enum.map(&event(&1, context)) |> dedupe(),
         next_cursor: encode_cursor(next_cursor)
       }}
    end
  end

  @doc "U69 A8b: one event, in the row shape, by its id (a Timeline permalink)."
  @spec fetch(binary(), binary(), binary()) :: {:ok, map()} | {:error, :event_not_found}
  def fetch(organization_id, mission_id, id) do
    case ById.entry(organization_id, mission_id, id) do
      {:ok, entry} ->
        {[entry], contacts} = EventContacts.enrich(organization_id, mission_id, [entry])
        context = Map.put(context(organization_id, mission_id, [entry]), :contacts, contacts)
        {:ok, event(entry, context)}

      :error ->
        {:error, :event_not_found}
    end
  end

  # Kinds are derived per entry, so they can't be pushed into the source reads. Read timeline
  # pages until `limit` selected entries or the end (fe-ops: housekeeping rows used to starve
  # an unfiltered page), at most @max_rounds pages. Each round asks only for what's still
  # needed, so a page never exceeds `limit`; the cursor continues where reading stopped.
  defp collect(_org, _mission, _opts, cursor, remaining, acc, rounds)
       when remaining <= 0 or rounds <= 0,
       do: {acc, cursor}

  defp collect(organization_id, mission_id, opts, cursor, remaining, acc, rounds) do
    page =
      MissionTimeline.page_for_mission(organization_id, mission_id,
        from_occurred_at: opts.from,
        to_occurred_at: opts.to,
        spacecraft_id: spacecraft_filter(organization_id, mission_id, opts),
        config_revisions: true,
        off_plan_bookings: true,
        exclude_housekeeping: skip_housekeeping?(opts[:kinds]),
        # U69 A9b: exact raw kinds filter in SQL; prefixes per page, above.
        kind: RawKinds.exact(opts[:raw_kinds]),
        limit: remaining,
        cursor: cursor
      )

    selected =
      Enum.filter(
        page.entries,
        &(kind_selected?(%{kind: kind(&1)}, opts[:kinds]) and
            RawKinds.selected?(&1.kind, opts[:raw_kinds]) and
            severe_enough?(&1, opts[:severity_at_least]))
      )

    acc = acc ++ selected

    case page.next_cursor do
      nil ->
        {acc, nil}

      next ->
        collect(
          organization_id,
          mission_id,
          opts,
          next,
          remaining - length(selected),
          acc,
          rounds - 1
        )
    end
  end

  @doc "Severity counts per `bucket_s` bucket aligned to `from` (at most #{@density_cap} events read)."
  @spec density(binary(), binary(), map()) :: map()
  def density(organization_id, mission_id, opts) do
    # lead 11-15: counted in SQL, never loading rows, unless a spacecraft or plane filter needs the
    # page's per-entry spacecraft resolution (fewer rows).
    case spacecraft_filter(organization_id, mission_id, opts) do
      nil -> EventDensityCounts.density(organization_id, mission_id, opts)
      _filtered -> loaded_density(organization_id, mission_id, opts)
    end
  end

  @doc false
  # The per-entry density (spacecraft and plane filters); also the SQL path's parity reference.
  def loaded_density(organization_id, mission_id, opts) do
    entries =
      MissionTimeline.list_for_mission(organization_id, mission_id,
        from_occurred_at: opts.from,
        to_occurred_at: opts.to,
        spacecraft_id: spacecraft_filter(organization_id, mission_id, opts),
        config_revisions: true,
        off_plan_bookings: true,
        exclude_housekeeping: skip_housekeeping?(opts[:kinds]),
        limit: @density_cap
      )

    origin = DateTime.to_unix(opts.from)

    counts =
      entries
      |> Enum.map(&event(&1, @no_names))
      |> dedupe()
      |> Enum.filter(
        &(kind_selected?(&1, opts[:kinds]) and RawKinds.selected?(&1.raw_kind, opts[:raw_kinds]) and
            at_least?(&1.severity, opts[:severity_at_least]))
      )
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
      detail: detail(entry),
      spacecraft: spacecraft(entry.spacecraft_id, context.spacecraft),
      refs: %{
        subject: described.subject,
        alarm_id: nil,
        point_id: if(entry.subject_kind == :telemetry_point, do: entry.subject_id),
        command_request_id: (entry.metadata || %{})["command_request_id"],
        contact_id: entry.realized_contact_id || entry.scheduled_contact_id
      },
      record: record(entry)
    }
  end

  # U69 A8a: the producing record's own fields, for the event detail panel.
  defp record(%Entry{} = entry),
    do: %{
      status: text(entry.status),
      source_record:
        entry.source_record_kind &&
          %{kind: text(entry.source_record_kind), id: entry.source_record_id},
      source_endpoint_ref: entry.source_endpoint_ref,
      scheduled_contact_id: entry.scheduled_contact_id,
      realized_contact_id: entry.realized_contact_id,
      path_id: entry.path_id,
      capability_instance_id: entry.capability_instance_id,
      activation_id: entry.activation_id,
      correlation_key: entry.correlation_key
    }

  defp text(nil), do: nil
  defp text(value), do: to_string(value)

  # L15: an off-plan booking's note.
  defp detail(%Entry{source_record_kind: :off_plan_booking} = entry),
    do: OffPlanBookingEvents.detail(entry)

  defp detail(_entry), do: nil

  defp kind(%Entry{kind: kind} = entry) when is_atom(kind) or is_binary(kind) do
    raw = to_string(kind)

    cond do
      housekeeping?(raw) -> "data"
      String.starts_with?(raw, "limit_definition_") -> "config"
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
  defp classify(%Entry{source_record_kind: :config_revision}), do: "config"
  defp classify(%Entry{category: :transport}), do: "contact"
  defp classify(%Entry{category: :runtime}), do: "config"
  defp classify(%Entry{category: :health}), do: "data"
  defp classify(%Entry{}), do: "operator"

  defp severity(%Entry{status: status})
       when status in [:cleared, :resolved, "cleared", "resolved"],
       do: :nominal

  defp severity(%Entry{kind: kind})
       when kind in [:source_health_recovered, "source_health_recovered"],
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

  # 21:08Z 500s (domain): the default Timeline excludes `data`, so its rows needn't be read.
  @doc false
  def skip_housekeeping?([_ | _] = kinds), do: "data" not in kinds
  def skip_housekeeping?(_all), do: false

  @doc false
  # The page's console kind and severity for an entry built from a density group.
  def classify_entry(%Entry{} = entry), do: {kind(entry), severity(entry)}

  # U69 A9a: the severity the row shows (its sentence's, else the entry's), at or above the floor.
  defp severe_enough?(_entry, nil), do: true
  defp severe_enough?(entry, floor), do: at_least?(event(entry, @no_names).severity, floor)

  @doc false
  def at_least?(_severity, nil), do: true

  def at_least?(severity, floor),
    do: Map.get(@severity_rank, severity, 0) >= Map.fetch!(@severity_rank, floor)

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
