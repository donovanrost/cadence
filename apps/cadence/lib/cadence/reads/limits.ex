defmodule Cadence.Reads.Limits do
  @moduledoc """
  Read-side queries for limit events and latest limit states.

  A point's latest state, its event history and their watermark are the runtime's alarm states and
  transitions (`Cadence.Reads.AlarmEvents`, #451 T3e), as limit events; its definition intervals
  are empty for monitoring rules (bands are not shown yet, #1127). The mission-wide latest states
  (`latest_states_for_mission/2,3`, `latest_states_page/3`) still read the ground projection for the
  legacy readers that remain, and go with them.
  """

  alias Cadence.Limits
  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.Limits.Store
  alias Cadence.Reads.AlarmEvents
  alias Cadence.Telemetry.SourceFilters

  @mission_scope_key "__mission__"

  defdelegate latest_states_page(org, mission, opts), to: Store

  @spec latest_state(binary(), binary(), keyword()) :: Event.t() | nil
  def latest_state(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    latest_state_for_scope(nil, mission_id, point_id, opts)
  end

  @spec latest_state(binary(), binary(), binary(), keyword()) :: Event.t() | nil
  def latest_state(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    latest_state_for_scope(organization_id, mission_id, point_id, opts)
  end

  # The runtime's alarm states (#451 T3e), as limit events.
  defp latest_state_for_scope(organization_id, mission_id, point_id, opts),
    do: AlarmEvents.latest_state(organization_id, mission_id, point_id, opts)

  @doc """
  The point ids that have an active limit definition in the mission (ux T1 'No limits':
  the points read's `has_limits`).
  """
  @spec limited_point_ids(binary(), binary()) :: MapSet.t(binary())
  def limited_point_ids(organization_id, mission_id) do
    organization_id
    |> Limits.active_limit_definitions(mission_id)
    |> MapSet.new(& &1.point_id)
  end

  @spec latest_states_for_mission(binary(), keyword()) :: [Event.t()]
  def latest_states_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    mission_id
    |> Store.list_latest_states(opts)
    |> filter_source_events(opts)
  end

  @spec latest_states_for_mission(binary(), binary(), keyword()) :: [Event.t()]
  def latest_states_for_mission(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    mission_id
    |> Store.list_latest_states(Keyword.put(opts, :organization_id, organization_id))
    |> filter_source_events(opts)
  end

  @spec latest_states_for_points(binary(), [binary()], [binary() | nil]) :: [Event.t()]
  def latest_states_for_points(mission_id, point_ids, spacecraft_ids)
      when is_binary(mission_id) and is_list(point_ids) and is_list(spacecraft_ids) do
    scope_ids = spacecraft_ids |> Enum.map(&spacecraft_scope_id/1) |> Enum.uniq()

    Store.list_latest_states(mission_id,
      point_ids: point_ids,
      spacecraft_scope_ids: scope_ids
    )
  end

  @spec event_history(binary(), binary(), keyword()) :: [Event.t()]
  def event_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    AlarmEvents.event_history(nil, mission_id, point_id, opts)
  end

  @spec event_history(binary(), binary(), binary(), keyword()) :: [Event.t()]
  def event_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    AlarmEvents.event_history(organization_id, mission_id, point_id, opts)
  end

  @doc """
  The limit definition intervals of a point. Always `[]` for the runtime's monitoring rules (#451
  T3e): bands for them are not shown yet (issue #1127 builds them from the plan per revision).
  """
  @spec definition_intervals(binary(), binary(), keyword()) :: [DefinitionInterval.t()]
  def definition_intervals(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts),
      do: []

  @spec definition_intervals(binary(), binary(), binary(), keyword()) :: [
          DefinitionInterval.t()
        ]
  def definition_intervals(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts),
      do: []

  @spec watermark_result(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def watermark_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    %{latest: latest, events: events} = AlarmEvents.watermark(nil, mission_id, point_id, opts)
    {:ok, merge_projection_watermarks(latest, events)}
  end

  @spec watermark_result(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def watermark_result(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    %{latest: latest, events: events} =
      AlarmEvents.watermark(organization_id, mission_id, point_id, opts)

    {:ok, merge_projection_watermarks(latest, events)}
  end

  defp filter_source_events(events, opts) do
    filters = SourceFilters.normalize(opts)

    if limit_event_source_filters?(filters) do
      Enum.filter(events, &source_event_matches?(&1, filters))
    else
      events
    end
  end

  defp source_event_matches?(%Event{} = event, filters) when is_map(filters) do
    storage = storage_provenance(event)

    source_realm_matches?(storage, Map.get(filters, :realm)) and
      source_value_matches?(storage, :replay_run_id, Map.get(filters, :replay_run_id)) and
      source_endpoint_matches?(storage, Map.get(filters, :source_endpoint_ids))
  end

  defp limit_event_source_filters?(filters) when is_map(filters) do
    present?(Map.get(filters, :replay_run_id)) or Map.get(filters, :realm) == "replay" or
      Map.has_key?(filters, :source_endpoint_ids)
  end

  defp storage_provenance(%Event{provenance: provenance}) when is_map(provenance) do
    provenance_value(provenance, :storage) || %{}
  end

  defp storage_provenance(%Event{}), do: %{}

  defp source_value_matches?(_storage, _key, nil), do: true

  defp source_value_matches?(storage, key, expected) do
    storage
    |> provenance_value(key)
    |> compare_source_value(expected)
  end

  defp source_realm_matches?(_storage, nil), do: true
  defp source_realm_matches?(_storage, "flight"), do: true

  defp source_realm_matches?(storage, expected),
    do: source_value_matches?(storage, :realm, expected)

  defp source_endpoint_matches?(_storage, nil), do: true
  defp source_endpoint_matches?(_storage, []), do: true

  defp source_endpoint_matches?(storage, expected_ids) when is_list(expected_ids) do
    case provenance_value(storage, :source_endpoint_id) do
      nil -> false
      actual -> to_string(actual) in expected_ids
    end
  end

  defp compare_source_value(nil, _expected), do: false
  defp compare_source_value(actual, expected), do: to_string(actual) == expected

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp provenance_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp provenance_value(map, key) when is_map(map), do: Map.get(map, key)
  defp provenance_value(_value, _key), do: nil

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id

  defp merge_projection_watermarks(left, right) do
    latest_receipt_time = latest_datetime([left, right], :latest_receipt_time)
    sample_count = sample_count(left) + sample_count(right)

    %{
      complete_through: latest_receipt_time,
      latest_receipt_time: latest_receipt_time,
      retention_starts_at: earliest_datetime([left, right], :retention_starts_at),
      sample_count: sample_count,
      confidence: watermark_confidence(latest_receipt_time, sample_count),
      projection_sources: %{
        latest_state_count: sample_count(left),
        event_count: sample_count(right)
      }
    }
  end

  defp sample_count(nil), do: 0
  defp sample_count(%{sample_count: count}) when is_integer(count), do: count
  defp sample_count(_projection), do: 0

  defp latest_datetime(projections, key) do
    projections
    |> datetimes(key)
    |> Enum.reduce(nil, &later_datetime/2)
  end

  defp earliest_datetime(projections, key) do
    projections
    |> datetimes(key)
    |> Enum.reduce(nil, &earlier_datetime/2)
  end

  defp datetimes(projections, key) do
    projections
    |> Enum.map(fn projection -> projection && Map.get(projection, key) end)
    |> Enum.reject(&is_nil/1)
  end

  defp earlier_datetime(datetime, nil), do: datetime
  defp earlier_datetime(datetime, minimum), do: compare_datetime(datetime, minimum, :lt)

  defp later_datetime(datetime, nil), do: datetime
  defp later_datetime(datetime, maximum), do: compare_datetime(datetime, maximum, :gt)

  defp compare_datetime(datetime, other, comparison) do
    if DateTime.compare(datetime, other) == comparison, do: datetime, else: other
  end

  defp watermark_confidence(%DateTime{}, sample_count) when sample_count > 0, do: :best_effort
  defp watermark_confidence(_latest_receipt_time, _sample_count), do: :unknown
end
