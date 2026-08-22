defmodule Cadence.Dashboards.RuntimeInvalidation.DecisionProjection do
  @moduledoc """
  Query projection for dashboard runtime invalidation decisions.

  Runtime health stores raw telemetry-like recent events. This module turns those
  events into support-facing rows that answer which dashboard runtime saw an
  invalidation, whether it matched, and whether it refreshed.
  """

  alias Cadence.Dashboards.RuntimeInvalidation.Event

  @type decision_row :: %{
          dashboard_runtime_invalidation_decision_event_id: binary() | nil,
          invalidation_event_id: binary() | nil,
          dashboard_id: binary() | nil,
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          boundary: atom() | binary() | nil,
          domain_fact: atom() | binary() | nil,
          decision_status: atom() | binary() | nil,
          matches?: boolean() | nil,
          dashboard_matches?: boolean() | nil,
          context_matches?: boolean() | nil,
          context_reason: atom() | binary() | nil,
          refresh_allowed?: boolean() | nil,
          refresh_reason: atom() | binary() | nil,
          affected_placement_count: non_neg_integer() | nil,
          affected_placement_ids: [binary()] | nil,
          affected_widget_type_ids: [binary()] | nil,
          affected_impact_reasons: [atom() | binary()] | nil,
          invalidated_artifacts: non_neg_integer(),
          invalidation_occurred_at: DateTime.t() | binary() | nil,
          decision_observed_at: DateTime.t() | nil,
          filters: map(),
          measurements: map(),
          decision: map(),
          source_event_present?: boolean()
        }

  @filter_keys [
    :organization_id,
    :mission_id,
    :dashboard_id,
    :decision_status,
    :boundary,
    :context_reason,
    :refresh_reason,
    :refresh_allowed?
  ]

  @spec list(map() | [map()], keyword()) :: [decision_row()]
  def list(snapshot_or_events, opts \\ [])

  def list(%{recent_events: recent_events}, opts) when is_list(recent_events) and is_list(opts),
    do: list(recent_events, opts)

  def list(recent_events, opts) when is_list(recent_events) and is_list(opts) do
    invalidations_by_id = invalidations_by_id(recent_events)

    recent_events
    |> Enum.flat_map(&decision_row(&1, invalidations_by_id))
    |> Enum.filter(&matches_filters?(&1, opts))
    |> Enum.reverse()
    |> Enum.take(limit(opts))
  end

  def list(_snapshot_or_events, _opts), do: []

  defp invalidations_by_id(recent_events) do
    recent_events
    |> Enum.flat_map(&invalidation_event/1)
    |> Map.new(fn event -> {Event.id(event), event} end)
  end

  defp invalidation_event(recent_event) do
    case Event.from_recent_event(recent_event) do
      {:ok, %Event{} = event} -> [event]
      :error -> []
    end
  end

  defp decision_row(recent_event, invalidations_by_id) do
    if decision_event?(recent_event) do
      metadata = get_attr(recent_event, :metadata, %{})
      measurements = get_attr(recent_event, :measurements, %{})
      invalidation_event_id = get_attr(metadata, :invalidation_event_id)
      decision = decision_metadata(metadata)
      source_event = Map.get(invalidations_by_id, invalidation_event_id)
      filters = source_filters(metadata, source_event)

      [
        %{
          dashboard_runtime_invalidation_decision_event_id: nil,
          invalidation_event_id: invalidation_event_id,
          dashboard_id: get_attr(decision, :dashboard_id),
          organization_id:
            get_attr(decision, :organization_id) || get_attr(filters, :organization_id),
          mission_id: get_attr(decision, :mission_id) || get_attr(filters, :mission_id),
          boundary: get_attr(metadata, :boundary) || source_boundary(source_event),
          domain_fact: get_attr(metadata, :domain_fact) || source_domain_fact(source_event),
          decision_status: get_attr(decision, :decision_status),
          matches?: get_attr(decision, :matches?),
          dashboard_matches?: get_attr(decision, :dashboard_matches?),
          context_matches?: get_attr(decision, :context_matches?),
          context_reason: get_attr(decision, :context_reason),
          refresh_allowed?: get_attr(decision, :refresh_allowed?),
          refresh_reason: get_attr(decision, :refresh_reason),
          affected_placement_count: get_attr(decision, :affected_placement_count),
          affected_placement_ids: get_attr(decision, :affected_placement_ids),
          affected_widget_type_ids: get_attr(decision, :affected_widget_type_ids),
          affected_impact_reasons: get_attr(decision, :affected_impact_reasons),
          invalidated_artifacts: invalidated_artifacts(metadata, source_event),
          invalidation_occurred_at: invalidation_occurred_at(metadata, source_event),
          decision_observed_at: get_attr(recent_event, :observed_at),
          filters: filters,
          measurements: measurements,
          decision: decision,
          source_event_present?: match?(%Event{}, source_event)
        }
      ]
    else
      []
    end
  end

  defp decision_event?(%{source: :dashboards_runtime_invalidation, event: event})
       when event in [:decision, "decision"],
       do: true

  defp decision_event?(%{"event" => event, source: :dashboards_runtime_invalidation})
       when event in [:decision, "decision"],
       do: true

  defp decision_event?(_recent_event), do: false

  defp decision_metadata(metadata) do
    metadata
    |> get_attr(:decision, %{})
    |> normalize_decision_metadata()
    |> merge_decision_metadata(metadata)
  end

  defp normalize_decision_metadata(decision) when is_map(decision), do: decision
  defp normalize_decision_metadata(_decision), do: %{}

  defp merge_decision_metadata(decision, metadata) do
    decision_keys =
      @filter_keys ++
        [
          :matches?,
          :dashboard_matches?,
          :context_matches?,
          :affected_placement_count,
          :affected_placement_ids,
          :affected_widget_type_ids,
          :affected_impact_reasons
        ]

    Enum.reduce(decision_keys, decision, fn key, decision ->
      put_decision_metadata_value(decision, metadata, key)
    end)
  end

  defp put_decision_metadata_value(decision, metadata, key) do
    case get_attr(metadata, key) do
      nil -> decision
      value -> Map.put_new(decision, key, value)
    end
  end

  defp source_filters(metadata, %Event{filters: filters}) when is_map(filters) do
    if map_size(filters) == 0, do: get_attr(metadata, :filters, %{}), else: filters
  end

  defp source_filters(metadata, _source_event) do
    case get_attr(metadata, :filters, %{}) do
      filters when is_map(filters) -> filters
      _other -> %{}
    end
  end

  defp source_boundary(%Event{boundary: boundary}), do: boundary
  defp source_boundary(_source_event), do: nil

  defp source_domain_fact(%Event{domain_fact: domain_fact}), do: domain_fact
  defp source_domain_fact(_source_event), do: nil

  defp invalidated_artifacts(_metadata, %Event{measurements: measurements}) do
    get_attr(measurements, :total, 0)
  end

  defp invalidated_artifacts(metadata, _source_event) do
    metadata
    |> get_attr(:measurements, %{})
    |> get_attr(:total, 0)
  end

  defp invalidation_occurred_at(_metadata, %Event{occurred_at: occurred_at}), do: occurred_at
  defp invalidation_occurred_at(metadata, _source_event), do: get_attr(metadata, :occurred_at)

  defp matches_filters?(row, opts) do
    Enum.all?(@filter_keys, &matches_filter?(row, opts, &1)) and
      matches_replay_run_id?(row, Keyword.get(opts, :replay_run_id)) and
      matches_affected_placement?(row, Keyword.get(opts, :affected_placement_id))
  end

  defp matches_filter?(row, opts, key) do
    expected = Keyword.get(opts, key)
    is_nil(expected) or enum_string(get_attr(row, key)) == enum_string(expected)
  end

  defp matches_affected_placement?(_row, nil), do: true
  defp matches_affected_placement?(_row, ""), do: true

  defp matches_affected_placement?(row, placement_id) when is_binary(placement_id) do
    placement_id in List.wrap(get_attr(row, :affected_placement_ids, []))
  end

  defp matches_replay_run_id?(_row, nil), do: true
  defp matches_replay_run_id?(_row, ""), do: true

  defp matches_replay_run_id?(row, replay_run_id) when is_binary(replay_run_id) do
    row
    |> get_attr(:filters, %{})
    |> get_attr(:replay_run_id)
    |> then(&(to_string(&1) == replay_run_id))
  end

  defp limit(opts) do
    case Keyword.get(opts, :limit, 20) do
      limit when is_integer(limit) and limit >= 0 -> limit
      _other -> 20
    end
  end

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(%_{} = attrs, key, default) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key, default)
  end

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value
end
