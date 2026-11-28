defmodule Cadence.Reads.FleetStatus do
  @moduledoc """
  Per-spacecraft operational state for a mission, plus fleet counts.

  A spacecraft's `state` is its worst condition, in precedence order
  `critical > caution > stale > nominal`. `never_heard` means no telemetry or
  limit evaluation has ever been received for it. Limit severities come from the
  latest limit-state projection (`red` is critical, `yellow` is caution,
  `green`/`blue` are nominal); freshness comes from the newest receipt time
  across the spacecraft's current telemetry values and limit evaluations,
  judged against a server-side `stale_after_s`.

  **Cost (#798).** `load/3` never reads the mission's latest limit states or current values whole
  (200,000 of each at 1,000 spacecraft x 200 points: 4.8 s). The limit conditions per spacecraft are
  one row each in a summary the limit-state writers keep (`Cadence.Limits.Store.FleetSummary`, #849), each spacecraft's newest
  telemetry receipt comes from the current-value store, which keeps it as values are recorded
  (`CurrentValueStore.last_receipts/2`), and the durable history receipts come from a cache
  (`durable_receipts_ttl_ms`, 60 s) refreshed off the read's path. The number of queries is
  fixed (pinned in `fleet_status_database_test.exs`) however large the fleet is. `build/1` and
  `build_posture/1` stay the pure builders over raw events (tests), reduced to the same
  per-spacecraft facts.

  Fleet geometry (`plane`, `slot`, `phase_deg`) and `operational_phase` are
  read from spacecraft metadata until they become first-class fields.
  """

  alias Cadence.Control.Contacts
  alias Cadence.Limits.Event
  alias Cadence.Limits.Store.FleetSummary
  alias Cadence.Reads.DurableReceiptCache
  alias Cadence.Reads.SpacecraftMetadata
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.SemanticObservations.FleetAlarms
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftType
  alias Cadence.Telemetry.{Sample, SpacecraftReceipts}

  @default_stale_after_s 900
  @limit_rank %{critical: 2, caution: 1, nominal: 0}

  @type state :: :critical | :caution | :stale | :nominal | :never_heard
  @type limit_state :: :critical | :caution | :nominal | :no_data

  @type spacecraft_row :: %{
          id: binary(),
          name: binary(),
          scid: integer() | nil,
          profile: %{id: binary(), name: binary() | nil, version: integer() | nil} | nil,
          plane: integer() | nil,
          slot: integer() | nil,
          phase_deg: number() | nil,
          operational_phase: binary() | nil,
          state: state(),
          limit_state: limit_state(),
          violating_points: non_neg_integer(),
          worst_point: map() | nil,
          last_received_at: DateTime.t() | nil,
          stale: boolean(),
          in_contact: boolean() | nil,
          next_aos_at: DateTime.t() | nil,
          last_los_at: DateTime.t() | nil
        }

  @doc "Loads and builds the fleet status for one mission."
  @spec load(binary(), binary(), keyword()) :: map()
  def load(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    {limits, received, telemetry} = live_inputs(organization_id, mission_id)

    assemble(%{
      contacts: Contacts.contact_summary(organization_id, mission_id, now),
      spacecraft: Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id),
      profiles: Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id),
      limits: limits,
      received: received,
      telemetry: telemetry,
      now: now,
      stale_after_s: Keyword.get_lazy(opts, :stale_after_s, &stale_after_s/0)
    })
  end

  # What the live read needs of limits and telemetry, from the database and the cache and never by
  # reading every value (#798): the limit conditions per spacecraft (`FleetSummary`, one
  # statement over a row per spacecraft), each spacecraft's newest receipt (the current-value
  # store keeps it as values are recorded) and the durable history's. A fixed number of reads
  # however large the fleet is.
  defp live_inputs(organization_id, mission_id) do
    summaries = FleetSummary.load(organization_id, mission_id)
    alarms = FleetAlarms.load(organization_id, mission_id)
    durable = durable(organization_id, mission_id)

    limits =
      (Map.keys(summaries) ++ Map.keys(alarms))
      |> Enum.uniq()
      |> Map.new(fn id -> {id, combine(Map.get(summaries, id), Map.get(alarms, id))} end)

    received =
      merge_newest([
        Map.new(summaries, fn {id, summary} -> {id, summary.last_received_at} end),
        Map.new(alarms, fn {id, alarm} -> {id, alarm.last_received_at} end),
        TelemetryReads.last_receipts(organization_id, mission_id),
        durable.receipts
      ])

    {limits, received, durable.telemetry}
  end

  # A spacecraft's limit facts from both sources, the worst wins (DECISIONS #17, #871): the ground
  # limits the batch evaluations wrote and the live catalog monitoring alarms the runtime keeps. On a
  # tie the live alarm is the worst point (it is the current one); violating counts both.
  defp combine(ground, nil), do: ground_facts(ground)

  defp combine(nil, alarm), do: alarm_facts(alarm)

  defp combine(ground, alarm) do
    ground = ground_facts(ground)
    alarm = alarm_facts(alarm)

    winner =
      if Map.fetch!(@limit_rank, alarm.limit_state) >= Map.fetch!(@limit_rank, ground.limit_state),
        do: alarm,
        else: ground

    %{winner | violating: ground.violating + alarm.violating}
  end

  defp ground_facts(summary) do
    %{
      limit_state: summary.limit_state,
      violating: summary.violating,
      worst: summary.worst,
      worst_evaluated_at: summary.worst_evaluated_at
    }
  end

  defp alarm_facts(alarm) do
    %{
      limit_state: alarm.limit_state,
      violating: alarm.active,
      worst: Map.put(alarm.worst, :source, :catalog_monitoring),
      worst_evaluated_at: nil
    }
  end

  defp merge_newest(maps) do
    Enum.reduce(maps, %{}, fn map, acc ->
      Enum.reduce(map, acc, fn
        {_id, nil}, acc -> acc
        {id, at}, acc -> Map.update(acc, id, at, &max_datetime([&1, at]))
      end)
    end)
  end

  @doc """
  The fleet counts alone, `%{observed_at, telemetry, counts}` with `counts` of `total`,
  `critical`, `caution`, `stale`, `nominal` and `never_heard`: the same numbers as `load/3`'s, from
  the same inputs and rule, without building rows (the console top bar's posture, on `/counts`).
  """
  @spec posture(binary(), binary(), keyword()) :: map()
  def posture(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) do
    {limits, received, telemetry} = live_inputs(organization_id, mission_id)

    posture_from(%{
      spacecraft: Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id),
      limits: limits,
      received: received,
      telemetry: telemetry,
      now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0),
      stale_after_s: Keyword.get_lazy(opts, :stale_after_s, &stale_after_s/0)
    })
  end

  @posture_counts [:total, :critical, :caution, :stale, :nominal, :never_heard]

  @doc "Pure builder for `posture/3`: `build/1`'s inputs (profiles and contacts aren't used)."
  @spec build_posture(map()) :: map()
  def build_posture(input) do
    posture_from(
      Map.merge(input, %{
        limits: limit_facts(Map.get(input, :limit_states, [])),
        received: received(input),
        telemetry: telemetry(input)
      })
    )
  end

  defp posture_from(%{spacecraft: spacecraft, now: now, stale_after_s: stale_after_s} = input) do
    conditions =
      Enum.map(spacecraft, fn %Spacecraft{spacecraft_id: id} ->
        condition(Map.get(input.limits, id), Map.get(input.received, id), now, stale_after_s)
      end)

    %{
      observed_at: now,
      telemetry: input.telemetry,
      counts: conditions |> counts() |> Map.take(@posture_counts)
    }
  end

  @doc """
  Newest receipt time per spacecraft id: live telemetry values, limit
  evaluations, and the durable history store, so a spacecraft once heard is
  never reported as never heard after a restart.
  """
  @spec last_received_by_spacecraft(binary(), binary()) :: %{binary() => DateTime.t()}
  def last_received_by_spacecraft(organization_id, mission_id),
    do: organization_id |> last_received_with_status(mission_id) |> elem(0)

  @doc """
  `last_received_by_spacecraft/2` plus whether the durable history store answered: `:ok`, or
  `:degraded` when it timed out or failed and only live receipts are included.
  """
  @spec last_received_with_status(binary(), binary()) ::
          {%{binary() => DateTime.t()}, :ok | :degraded}
  def last_received_with_status(organization_id, mission_id) do
    {_limits, received, telemetry} = live_inputs(organization_id, mission_id)
    {received, telemetry}
  end

  # The durable history store (QuestDB in production) can hang. Its receipts only fill in
  # spacecraft not heard since the last restart, so a slow or failed store degrades to the live
  # values and limit states instead of holding the whole read (fe-ops, Compose targets). It is not
  # asked on every fleet read (#798): `DurableReceiptCache` keeps its last answer.
  defp durable(organization_id, mission_id) do
    DurableReceiptCache.get({__MODULE__, :durable, organization_id, mission_id}, fn ->
      SpacecraftReceipts.latest_by_spacecraft(organization_id, mission_id)
    end)
  end

  @doc "Configured staleness threshold in seconds (`config :cadence, :fleet_stale_after_s`)."
  @spec stale_after_s() :: pos_integer()
  def stale_after_s,
    do: Application.get_env(:cadence, :fleet_stale_after_s, @default_stale_after_s)

  @doc "Pure builder; see `load/3` for the inputs."
  @spec build(map()) :: map()
  def build(input) do
    assemble(
      Map.merge(input, %{
        limits: limit_facts(Map.get(input, :limit_states, [])),
        received: received(input),
        telemetry: telemetry(input)
      })
    )
  end

  # The rows and counts from per-spacecraft limit facts and receipts (`load/3`'s inputs, or
  # `build/1`'s events reduced to the same shape).
  defp assemble(%{spacecraft: spacecraft, now: now, stale_after_s: stale_after_s} = input) do
    profiles = Map.new(Map.get(input, :profiles, []), &{&1.spacecraft_type_id, &1})

    contacts =
      Map.get(input, :contacts, %{tracked?: false, passes_next_2h: nil, by_spacecraft: %{}})

    rows =
      spacecraft
      |> Enum.map(fn %Spacecraft{} = craft ->
        row(
          craft,
          profiles,
          Map.get(input.limits, craft.spacecraft_id),
          Map.get(input.received, craft.spacecraft_id),
          now,
          stale_after_s
        )
        |> Map.merge(contact(contacts, craft.spacecraft_id))
      end)
      |> Enum.sort_by(&sort_key/1)

    %{
      observed_at: now,
      stale_after_s: stale_after_s,
      # :degraded when the durable history store didn't answer in time (see durable/2).
      telemetry: input.telemetry,
      last_received_at: rows |> Enum.map(& &1.last_received_at) |> max_datetime(),
      counts: Map.merge(counts(rows), contact_counts(contacts, rows)),
      spacecraft: rows
    }
  end

  # Per-spacecraft limit facts from the latest limit states themselves (the pure builders' input;
  # `FleetSummary` produces the same shape in the database).
  defp limit_facts(limit_states) do
    limit_states
    |> Enum.group_by(& &1.spacecraft_id)
    |> Map.new(fn {id, events} ->
      violating = Enum.filter(events, & &1.violation)

      {id,
       %{
         limit_state: worst_limit_state(events),
         violating: length(violating),
         worst: worst_violating(violating)
       }}
    end)
  end

  defp worst_violating([]), do: nil

  defp worst_violating(violating) do
    Enum.max_by(violating, fn event ->
      {Map.fetch!(@limit_rank, severity(event)),
       event.receipt_time && DateTime.to_unix(event.receipt_time, :microsecond)}
    end)
  end

  defp received(input) do
    latest_receipts(
      Map.get(input, :samples, []),
      Map.get(input, :limit_states, []),
      input
      |> Map.get(:durable, %{})
      |> Map.get(:receipts, Map.get(input, :durable_receipts, %{}))
    )
  end

  defp telemetry(input), do: input |> Map.get(:durable, %{}) |> Map.get(:telemetry, :ok)

  # One spacecraft's condition: what both the rows and the posture count (counts/1).
  defp condition(limits, last_received_at, now, stale_after_s) do
    limit_state = if limits, do: limits.limit_state, else: :no_data
    stale = stale?(last_received_at, now, stale_after_s)

    %{
      state: state(limit_state, last_received_at, stale),
      limit_state: limit_state,
      last_received_at: last_received_at,
      stale: stale
    }
  end

  defp row(craft, profiles, limits, last_received_at, now, stale_after_s) do
    metadata = craft.metadata || %{}
    condition = condition(limits, last_received_at, now, stale_after_s)

    %{
      id: craft.spacecraft_id,
      name: craft.display_name,
      scid: craft.scid,
      profile: profile(craft, profiles),
      plane: SpacecraftMetadata.integer(metadata, "plane"),
      slot: SpacecraftMetadata.integer(metadata, "slot"),
      phase_deg: SpacecraftMetadata.phase_deg(metadata),
      operational_phase: SpacecraftMetadata.string(metadata, "operational_phase"),
      state: condition.state,
      limit_state: condition.limit_state,
      violating_points: if(limits, do: limits.violating, else: 0),
      worst_point: worst_point(limits),
      last_received_at: condition.last_received_at,
      stale: condition.stale
    }
  end

  # Contact facts come from booked reservations; without any, they're not tracked (nil).
  defp contact(%{tracked?: false}, _id),
    do: %{in_contact: nil, next_aos_at: nil, last_los_at: nil}

  defp contact(%{by_spacecraft: by_spacecraft}, id) do
    Map.get(by_spacecraft, id, %{in_contact: false, next_aos_at: nil, last_los_at: nil})
  end

  defp contact_counts(%{tracked?: false}, _rows), do: %{in_contact: nil, passes_next_2h: nil}

  defp contact_counts(contacts, rows) do
    %{in_contact: Enum.count(rows, & &1.in_contact), passes_next_2h: contacts.passes_next_2h}
  end

  defp state(_limit_state, nil, _stale), do: :never_heard
  defp state(:critical, _received, _stale), do: :critical
  defp state(:caution, _received, _stale), do: :caution
  defp state(_limit_state, _received, true), do: :stale
  defp state(_limit_state, _received, false), do: :nominal

  defp stale?(nil, _now, _stale_after_s), do: false
  defp stale?(received, now, stale_after_s), do: DateTime.diff(now, received) > stale_after_s

  defp worst_limit_state([]), do: :no_data

  defp worst_limit_state(limit_states) do
    limit_states
    |> Enum.map(&severity/1)
    |> Enum.max_by(&Map.fetch!(@limit_rank, &1))
  end

  defp severity(%Event{normalized_state: :red}), do: :critical
  defp severity(%Event{normalized_state: :yellow}), do: :caution
  defp severity(%Event{}), do: :nominal

  defp worst_point(nil), do: nil
  defp worst_point(%{worst: nil}), do: nil

  # A live monitoring alarm: the latest state row carries the parameter and its state, not the value
  # that raised it (that is on the alarm episode), so `value` is null and `raw_limit_state` (the
  # ground-limit vocabulary) is too.
  defp worst_point(%{worst: %{source: :catalog_monitoring} = alarm}) do
    %{
      source: :catalog_monitoring,
      point_id: alarm.parameter_id,
      point_name: alarm.parameter_id,
      value: nil,
      limit_state: alarm_severity(alarm.effective_state),
      raw_limit_state: nil,
      received_at: alarm.receipt_time,
      evaluated_at: nil
    }
  end

  defp worst_point(%{worst: %Event{} = event} = limits) do
    %{
      source: :ground_limit,
      point_id: event.point_id,
      point_name: event.point_name,
      value: event.evaluated_value,
      limit_state: severity(event),
      raw_limit_state: event.limit_state && to_string(event.limit_state),
      received_at: event.receipt_time,
      evaluated_at: Map.get(limits, :worst_evaluated_at)
    }
  end

  defp alarm_severity(state) when state in ~w(distress critical severe), do: :critical
  defp alarm_severity(_watch_or_warning), do: :caution

  defp latest_receipts(samples, limit_states, durable) do
    sample_times = Enum.map(samples, fn %Sample{} = s -> {s.spacecraft_id, s.receipt_time} end)
    limit_times = Enum.map(limit_states, fn %Event{} = e -> {e.spacecraft_id, e.receipt_time} end)

    (sample_times ++ limit_times ++ Map.to_list(durable))
    |> Enum.reject(fn {id, at} -> is_nil(id) or is_nil(at) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, times} -> {id, max_datetime(times)} end)
  end

  defp max_datetime(datetimes) do
    case Enum.reject(datetimes, &is_nil/1) do
      [] -> nil
      present -> Enum.max(present, DateTime)
    end
  end

  defp profile(%Spacecraft{spacecraft_type_id: nil}, _profiles), do: nil

  defp profile(%Spacecraft{} = craft, profiles) do
    name =
      case Map.get(profiles, craft.spacecraft_type_id) do
        %SpacecraftType{display_name: name} -> name
        nil -> nil
      end

    %{id: craft.spacecraft_type_id, name: name, version: craft.spacecraft_type_version}
  end

  defp counts(rows) do
    frequencies = Enum.frequencies_by(rows, & &1.state)

    %{
      total: length(rows),
      critical: Map.get(frequencies, :critical, 0),
      caution: Map.get(frequencies, :caution, 0),
      stale: Map.get(frequencies, :stale, 0),
      nominal: Map.get(frequencies, :nominal, 0),
      never_heard: Map.get(frequencies, :never_heard, 0),
      fresh: Enum.count(rows, &(not is_nil(&1.last_received_at) and not &1.stale))
    }
  end

  defp sort_key(row),
    do: {row.plane || :infinity, row.slot || :infinity, row.scid || :infinity, row.name}
end
