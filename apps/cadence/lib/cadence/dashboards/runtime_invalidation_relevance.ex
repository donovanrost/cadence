defmodule Cadence.Dashboards.RuntimeInvalidationRelevance do
  @moduledoc """
  Dashboard runtime invalidation relevance policy.

  This module keeps source/event/runtime matching rules out of the LiveView.
  Callers pass the active dashboard document, scope, mission, and a small
  runtime context map; this module answers whether an invalidation belongs to
  that dashboard and whether it should trigger an engine refresh.
  """

  alias Cadence.Dashboards.{Document, Placement}
  alias Cadence.Dashboards.RuntimeInvalidation.Event

  @live_refresh_boundaries [
    :dashboard_version_changed,
    :catalog_revision_changed,
    :events_changed,
    :limit_definition_changed,
    :data_source_binding_changed,
    :source_health_changed,
    :telemetry_revision_state_changed,
    :source_watermark_changed
  ]

  @type runtime_context :: %{
          optional(:data_realm) => atom() | binary() | nil,
          optional(:engine_result) => map() | struct() | nil,
          optional(:time_context) => map() | nil,
          optional(:time_mode) => binary() | atom() | nil,
          optional(:replay_run_id) => binary() | nil,
          optional(:context_since) => DateTime.t() | nil,
          optional(:edit_mode?) => boolean()
        }

  @spec summarize_recent_events([map()], map(), map(), Document.t()) :: map()
  def summarize_recent_events(events, current_scope, mission, %Document{} = document)
      when is_list(events) do
    Enum.reduce(events, empty_summary(), fn event, summary ->
      summarize_recent_event(event, summary, current_scope, mission, document)
    end)
  end

  @spec recent_event_matches_dashboard?(map(), map(), map(), Document.t()) :: boolean()
  def recent_event_matches_dashboard?(event, current_scope, mission, %Document{} = document) do
    case Event.from_recent_event(event) do
      {:ok, %Event{} = invalidation_event} ->
        event_matches_dashboard?(invalidation_event, current_scope, mission, document)

      :error ->
        false
    end
  end

  @spec relevant_recent_events([map()], map(), map(), Document.t(), keyword()) :: [Event.t()]
  def relevant_recent_events(events, current_scope, mission, %Document{} = document, opts \\ [])
      when is_list(events) do
    limit = Keyword.get(opts, :limit, 5)

    events
    |> Enum.reverse()
    |> Enum.flat_map(&recent_event/1)
    |> Enum.filter(&event_matches_dashboard?(&1, current_scope, mission, document))
    |> Enum.take(max(limit, 0))
  end

  @spec event_matches?(map() | Event.t(), map(), map(), Document.t(), runtime_context()) ::
          boolean()
  def event_matches?(event, current_scope, mission, %Document{} = document, runtime_context)
      when is_map(runtime_context) do
    event
    |> event_relevance(current_scope, mission, document, runtime_context)
    |> Map.get(:matches?, false)
  end

  def event_matches?(_event, _current_scope, _mission, _document, _runtime_context), do: false

  @spec event_relevance(map() | Event.t(), map(), map(), Document.t(), runtime_context()) :: map()
  def event_relevance(event, current_scope, mission, %Document{} = document, runtime_context)
      when is_map(runtime_context) do
    case normalize_event(event) do
      {:ok, %Event{} = invalidation_event} ->
        event_relevance_for(invalidation_event, current_scope, mission, document, runtime_context)

      :error ->
        event_relevance_result(false, false, false, :invalid_event)
    end
  end

  def event_relevance(_event, _current_scope, _mission, _document, _runtime_context),
    do: event_relevance_result(false, false, false, :invalid_event)

  @spec affected_placements(map() | Event.t(), Document.t()) :: [map()]
  def affected_placements(event, %Document{} = document) do
    case normalize_event(event) do
      {:ok, %Event{} = invalidation_event} ->
        document.placements
        |> Enum.flat_map(&placement_impact(&1, invalidation_event))

      :error ->
        []
    end
  end

  def affected_placements(_event, _document), do: []

  @spec affected_placement_summary([map()]) :: map()
  def affected_placement_summary(placements) when is_list(placements) do
    %{
      count: length(placements),
      placement_ids: Enum.map(placements, & &1.placement_id),
      widget_type_ids:
        placements
        |> Enum.map(& &1.widget_type_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      impact_reasons:
        placements
        |> Enum.map(& &1.impact_reason)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  def affected_placement_summary(_placements) do
    %{count: 0, placement_ids: [], widget_type_ids: [], impact_reasons: []}
  end

  @spec refresh_allowed?(map() | Event.t(), runtime_context()) :: boolean()
  def refresh_allowed?(invalidation, runtime_context) when is_map(runtime_context) do
    invalidation
    |> refresh_relevance(runtime_context)
    |> Map.get(:allowed?, false)
  end

  @spec refresh_relevance(map() | Event.t(), runtime_context()) :: map()
  def refresh_relevance(invalidation, runtime_context) when is_map(runtime_context) do
    case normalize_event(invalidation) do
      {:ok, %Event{} = event} -> refresh_relevance_for_event(event, runtime_context)
      :error -> refresh_relevance_result(false, :invalid_event)
    end
  end

  def refresh_relevance(_invalidation, _runtime_context),
    do: refresh_relevance_result(false, :invalid_event)

  @spec remounts_charts?(map() | Event.t()) :: boolean()
  def remounts_charts?(invalidation) do
    case normalize_event(invalidation) do
      {:ok, %Event{boundary: :events_changed}} -> true
      _other -> false
    end
  end

  @spec notice(map() | Event.t()) :: map()
  def notice(event) do
    case normalize_event(event) do
      {:ok, %Event{} = invalidation_event} ->
        %{
          boundary: invalidation_event.boundary,
          refresh_reason: :runtime_invalidation,
          refresh_action: Event.refresh_action(invalidation_event),
          invalidated_artifacts: artifact_count(invalidation_event)
        }

      :error ->
        %{
          boundary: nil,
          refresh_reason: :runtime_invalidation,
          refresh_action: nil,
          invalidated_artifacts: 0
        }
    end
  end

  @spec notice_boundary(map() | nil) :: binary() | nil
  def notice_boundary(%{boundary: boundary}) when is_atom(boundary) or is_binary(boundary),
    do: to_string(boundary)

  def notice_boundary(_notice), do: nil

  @spec notice_refresh_reason(map() | nil) :: binary() | nil
  def notice_refresh_reason(%{refresh_reason: reason}) when is_atom(reason) or is_binary(reason),
    do: to_string(reason)

  def notice_refresh_reason(_notice), do: nil

  @spec notice_refresh_action(map() | nil) :: binary() | nil
  def notice_refresh_action(%{refresh_action: action}) when is_atom(action) or is_binary(action),
    do: to_string(action)

  def notice_refresh_action(_notice), do: nil

  @spec boundary_summary(map()) :: binary() | nil
  def boundary_summary(%{boundaries: boundaries}) when is_map(boundaries) do
    labels =
      boundaries
      |> Enum.sort_by(fn {boundary, _count} -> to_string(boundary) end)
      |> Enum.map_join(" ", fn {boundary, count} -> "#{boundary}:#{count}" end)

    if labels == "", do: nil, else: labels
  end

  def boundary_summary(_summary), do: nil

  @spec boundary(map() | Event.t()) :: atom() | nil
  def boundary(event) do
    case normalize_event(event) do
      {:ok, %Event{boundary: boundary}} -> boundary
      :error -> nil
    end
  end

  @spec artifact_count(map() | Event.t()) :: non_neg_integer()
  def artifact_count(%Event{measurements: measurements}) do
    case Map.get(measurements, :total) do
      count when is_integer(count) and count >= 0 -> count
      _other -> 0
    end
  end

  def artifact_count(event) do
    case normalize_event(event) do
      {:ok, %Event{} = invalidation_event} -> artifact_count(invalidation_event)
      :error -> 0
    end
  end

  defp empty_summary, do: %{event_count: 0, artifact_count: 0, boundaries: %{}}

  defp recent_event(event) do
    case Event.from_recent_event(event) do
      {:ok, %Event{} = invalidation_event} -> [invalidation_event]
      :error -> []
    end
  end

  defp summarize_recent_event(event, summary, current_scope, mission, document) do
    case Event.from_recent_event(event) do
      {:ok, %Event{} = invalidation_event} ->
        summarize_event_if_relevant(invalidation_event, summary, current_scope, mission, document)

      :error ->
        summary
    end
  end

  defp summarize_event_if_relevant(%Event{} = event, summary, current_scope, mission, document) do
    if event_matches_dashboard?(event, current_scope, mission, document) do
      summary
      |> Map.update!(:event_count, &(&1 + 1))
      |> Map.update!(:artifact_count, &(&1 + artifact_count(event)))
      |> update_boundary(event.boundary)
    else
      summary
    end
  end

  defp event_relevance_for(
         %Event{} = event,
         current_scope,
         mission,
         %Document{} = document,
         runtime_context
       ) do
    case dashboard_match_reason(event, current_scope, mission, document) do
      :matched ->
        case context_match_reason(event, runtime_context) do
          :matched -> event_relevance_result(true, true, true, :matched)
          reason -> event_relevance_result(false, true, false, reason)
        end

      reason ->
        event_relevance_result(false, false, false, reason)
    end
  end

  defp event_relevance_result(matches?, dashboard_matches?, context_matches?, reason) do
    %{
      matches?: matches?,
      dashboard_matches?: dashboard_matches?,
      context_matches?: context_matches?,
      reason: reason
    }
  end

  defp refresh_relevance_for_event(%Event{} = event, runtime_context) do
    cond do
      Map.get(runtime_context, :edit_mode?) ->
        refresh_relevance_result(false, :edit_mode)

      stale_for_context?(runtime_context, event) ->
        refresh_relevance_result(false, :stale_for_context)

      live_context?(runtime_context) and event.boundary not in @live_refresh_boundaries ->
        refresh_relevance_result(false, :non_live_boundary)

      snapshot_historical_data?(event, runtime_context) ->
        if overlaps_snapshot_time_context?(runtime_context, event) do
          refresh_relevance_result(true, :allowed)
        else
          refresh_relevance_result(false, :snapshot_time_mismatch)
        end

      true ->
        refresh_relevance_result(true, :allowed)
    end
  end

  defp refresh_relevance_result(allowed?, reason), do: %{allowed?: allowed?, reason: reason}

  defp live_context?(runtime_context),
    do: to_string(Map.get(runtime_context, :time_mode)) == "live"

  defp snapshot_historical_data?(%Event{boundary: :historical_data_changed}, runtime_context) do
    Map.get(runtime_context, :time_mode)
    |> to_string()
    |> then(&(&1 in ["archive", "replay_run"]))
  end

  defp snapshot_historical_data?(_event, _runtime_context), do: false

  defp normalize_event(%Event{} = event), do: {:ok, event}

  defp normalize_event(%{metadata: metadata, measurements: measurements}) do
    Event.from_metadata(metadata, measurements)
  end

  defp normalize_event(
         %{boundary: _boundary, filters: _filters, measurements: measurements} = event
       ) do
    Event.from_metadata(event, measurements, occurred_at: Map.get(event, :occurred_at))
  end

  defp normalize_event(_event), do: :error

  defp event_matches_dashboard?(%Event{} = event, current_scope, mission, %Document{} = document) do
    scope_matches?(event.filters, current_scope, mission, document) and
      relevant_to_document?(event.filters, document)
  end

  defp dashboard_match_reason(%Event{} = event, current_scope, mission, %Document{} = document) do
    cond do
      not scope_matches?(event.filters, current_scope, mission, document) ->
        :scope_mismatch

      not relevant_to_document?(event.filters, document) ->
        :document_not_relevant

      true ->
        :matched
    end
  end

  defp context_match_reason(%Event{} = event, runtime_context) do
    cond do
      not realm_matches?(filter(event.filters, :realm), Map.get(runtime_context, :data_realm)) ->
        :realm_mismatch

      not replay_run_matches?(filter(event.filters, :replay_run_id), runtime_context) ->
        :replay_run_mismatch

      true ->
        source_identity_match_reason(event, runtime_context)
    end
  end

  defp source_identity_match_reason(
         %Event{boundary: :data_source_binding_changed},
         _runtime_context
       ),
       do: :matched

  defp source_identity_match_reason(%Event{} = event, runtime_context) do
    cond do
      not data_source_matches?(event.filters, runtime_context) ->
        :data_source_mismatch

      not source_binding_matches?(event.filters, runtime_context) ->
        :source_binding_mismatch

      true ->
        :matched
    end
  end

  defp realm_matches?(nil, _active_realm), do: true
  defp realm_matches?(realm, active_realm), do: to_string(realm) == to_string(active_realm)

  defp replay_run_matches?(nil, _runtime_context), do: true

  defp replay_run_matches?(replay_run_id, runtime_context) do
    case runtime_context_replay_run_id(runtime_context) do
      nil -> false
      active_replay_run_id -> to_string(replay_run_id) == to_string(active_replay_run_id)
    end
  end

  defp runtime_context_replay_run_id(runtime_context) do
    Map.get(runtime_context, :replay_run_id) ||
      filter(Map.get(runtime_context, :data_context) || %{}, :replay_run_id) ||
      filter(Map.get(runtime_context, :time_context) || %{}, :replay_run_id)
  end

  defp data_source_matches?(filters, runtime_context) do
    data_source_id = filter(filters, :data_source_id) || filter(filters, :source_id)
    identity_matches?(data_source_id, runtime_context, :data_source_id)
  end

  defp source_binding_matches?(filters, runtime_context) do
    source_binding_id = filter(filters, :source_binding_id) || filter(filters, :binding_id)
    identity_matches?(source_binding_id, runtime_context, :source_binding_id)
  end

  defp identity_matches?(nil, _runtime_context, _identity_key), do: true

  defp identity_matches?(identity, runtime_context, identity_key) do
    runtime_context
    |> Map.get(:engine_result)
    |> result_identity_values(identity_key)
    |> Enum.any?(&(to_string(&1) == to_string(identity)))
  end

  defp result_identity_values(nil, _identity_key), do: []

  defp result_identity_values(result, identity_key) do
    (watermark_identity_values(result, identity_key) ++
       source_result_identity_values(result, identity_key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp watermark_identity_values(%{watermarks: watermarks}, identity_key)
       when is_list(watermarks) do
    Enum.map(watermarks, &Map.get(&1, identity_key))
  end

  defp watermark_identity_values(_result, _identity_key), do: []

  defp source_result_identity_values(result, identity_key) do
    result
    |> source_result_cache_keys()
    |> Enum.flat_map(&cache_key_identity_values(&1, identity_key))
  end

  defp source_result_cache_keys(%{plan_metadata: plan_metadata}) when is_map(plan_metadata) do
    cache = Map.get(plan_metadata, :cache, %{})

    source_result_keys =
      cache
      |> Map.get(:source_result_keys_by_request_id, %{})
      |> Map.values()

    source_result_entry_keys =
      cache
      |> Map.get(:source_result_cache_by_request_id, %{})
      |> Map.values()
      |> Enum.map(fn
        %{key: key} -> key
        _entry -> nil
      end)

    Enum.reject(source_result_keys ++ source_result_entry_keys, &is_nil/1)
  end

  defp source_result_cache_keys(_result), do: []

  defp cache_key_identity_values(%{parts: parts}, :data_source_id) when is_map(parts) do
    [
      get_in(parts, [:data_source, :data_source_id]),
      get_in(parts, [:source_binding, :data_source_id]),
      get_in(parts, [:watermark_cursor, :data_source_id])
    ] ++ segment_identity_values(parts, :data_source_id)
  end

  defp cache_key_identity_values(%{parts: parts}, :source_binding_id) when is_map(parts) do
    [
      get_in(parts, [:source_binding, :binding_id]),
      get_in(parts, [:watermark_cursor, :source_binding_id])
    ] ++ segment_identity_values(parts, :source_binding_id)
  end

  defp cache_key_identity_values(_cache_key, _identity_key), do: []

  defp segment_identity_values(parts, identity_key) do
    parts
    |> Map.get(:source_binding_segments, [])
    |> List.wrap()
    |> Enum.flat_map(fn
      segment when is_map(segment) ->
        [
          Map.get(segment, identity_key),
          Map.get(segment, Atom.to_string(identity_key))
        ]

      _segment ->
        []
    end)
  end

  defp relevant_to_document?(filters, document) do
    case filter(filters, :logical_source) do
      source when source in [:telemetry, "telemetry"] ->
        document_has_affected_source_placement?(document, filters, :telemetry)

      source when source in [:events, "events"] ->
        document_has_affected_source_placement?(document, filters, :events)

      source when source in [:limits, "limits"] ->
        document_has_affected_source_placement?(document, filters, :limits)

      source when source in [:operational_observables, "operational_observables"] ->
        document_has_affected_source_placement?(document, filters, :operational_observables)

      _other ->
        true
    end
  end

  defp document_has_affected_source_placement?(%Document{placements: placements}, filters, source) do
    Enum.any?(placements, &placement_impacted_by_source?(&1, filters, source))
  end

  defp document_has_affected_source_placement?(_document, _filters, _source), do: false

  defp placement_impact(%Placement{} = placement, %Event{} = event) do
    case placement_impact_reason(placement, event.filters, event.boundary) do
      nil ->
        []

      reason ->
        [
          %{
            placement_id: placement.placement_id,
            widget_type_id: placement.widget_def && placement.widget_def.widget_type_id,
            title: placement.widget_def && placement.widget_def.title,
            logical_source: normalized_logical_source(filter(event.filters, :logical_source)),
            impact_reason: reason
          }
        ]
    end
  end

  defp placement_impact(_placement, _event), do: []

  defp placement_impact_reason(%Placement{} = placement, filters, boundary) do
    case normalized_logical_source(filter(filters, :logical_source)) do
      nil -> broad_boundary_impact_reason(boundary)
      source -> placement_source_impact_reason(placement, filters, source)
    end
  end

  defp broad_boundary_impact_reason(:dashboard_version_changed), do: :dashboard_document
  defp broad_boundary_impact_reason(:catalog_revision_changed), do: :catalog_revision
  defp broad_boundary_impact_reason(:data_source_binding_changed), do: :source_binding
  defp broad_boundary_impact_reason(_boundary), do: :dashboard_scope

  defp placement_source_impact_reason(%Placement{} = placement, filters, source) do
    cond do
      placement_impacted_by_primary_source?(placement, filters, source) ->
        :primary_source

      placement_impacted_by_overlay?(placement, filters, source) ->
        :overlay

      true ->
        nil
    end
  end

  defp placement_impacted_by_source?(%Placement{} = placement, filters, source) do
    not is_nil(placement_source_impact_reason(placement, filters, source))
  end

  defp placement_impacted_by_primary_source?(%Placement{} = placement, filters, source) do
    placement_uses_primary_source?(placement, source) and
      placement_matches_observable_filter?(placement, filter(filters, :observable))
  end

  defp placement_impacted_by_overlay?(%Placement{} = placement, filters, :limits) do
    placement_uses_overlay?(placement, :limits) and
      placement_matches_observable_filter?(placement, filter(filters, :observable))
  end

  defp placement_impacted_by_overlay?(%Placement{} = placement, _filters, :events) do
    placement_uses_overlay?(placement, :events)
  end

  defp placement_impacted_by_overlay?(_placement, _filters, _source), do: false

  defp placement_uses_overlay?(%Placement{widget_def: nil}, _overlay), do: false

  defp placement_uses_overlay?(%Placement{widget_def: %{binding: binding}}, overlay)
       when is_map(binding) do
    overlay_string = Atom.to_string(overlay)

    binding
    |> Map.get(:overlays, [])
    |> List.wrap()
    |> Enum.any?(&(&1 == overlay or &1 == overlay_string))
  end

  defp placement_uses_overlay?(_placement, _overlay), do: false

  defp placement_uses_primary_source?(
         %Placement{widget_def: %{widget_type_id: widget_type_id, binding: binding}},
         :telemetry
       )
       when is_map(binding) do
    observables =
      binding
      |> Map.get(:observables, [])
      |> List.wrap()

    widget_type_id in [
      "cadence.value_tile",
      "cadence.time_series",
      "cadence.status_matrix",
      "cadence.data_table"
    ] and
      binding_source(binding) == :telemetry and
      Enum.any?(observables)
  end

  defp placement_uses_primary_source?(
         %Placement{widget_def: %{widget_type_id: widget_type_id, binding: binding}},
         :operational_observables
       )
       when is_map(binding) do
    widget_type_id == "cadence.constellation_health" or
      (widget_type_id in [
         "cadence.value_tile",
         "cadence.status_matrix",
         "cadence.data_table"
       ] and binding_source(binding) == :operational_observables)
  end

  defp placement_uses_primary_source?(
         %Placement{widget_def: %{widget_type_id: widget_type_id, binding: binding}},
         :limits
       )
       when is_map(binding) do
    widget_type_id == "cadence.state_timeline" or binding_source(binding) == :limits
  end

  defp placement_uses_primary_source?(
         %Placement{widget_def: %{widget_type_id: widget_type_id, binding: binding}},
         :events
       )
       when is_map(binding) do
    widget_type_id == "cadence.event_timeline" or binding_source(binding) == :events
  end

  defp placement_uses_primary_source?(_placement, _source), do: false

  defp placement_uses_observable?(%Placement{widget_def: nil}, _observable), do: false

  defp placement_uses_observable?(%Placement{widget_def: %{binding: binding}}, observable)
       when is_map(binding) do
    observable = to_string(observable)

    binding
    |> Map.get(:observables, [])
    |> List.wrap()
    |> Enum.any?(&(to_string(&1) == observable))
  end

  defp placement_uses_observable?(_placement, _observable), do: false

  defp placement_matches_observable_filter?(_placement, nil), do: true

  defp placement_matches_observable_filter?(%Placement{} = placement, observable) do
    placement_uses_observable?(placement, observable)
  end

  defp normalized_logical_source(source)
       when source in [:telemetry, :limits, :events, :operational_observables],
       do: source

  defp normalized_logical_source(source) when is_binary(source) do
    case source do
      "telemetry" -> :telemetry
      "limits" -> :limits
      "events" -> :events
      "operational_observables" -> :operational_observables
      _source -> nil
    end
  end

  defp normalized_logical_source(_source), do: nil

  defp binding_source(binding) when is_map(binding) do
    binding
    |> filter(:source)
    |> normalized_logical_source()
    |> Kernel.||(:telemetry)
  end

  defp scope_matches?(filters, current_scope, mission, document) do
    dashboard_id = filter(filters, :dashboard_id)
    organization_id = filter(filters, :organization_id)
    mission_id = filter(filters, :mission_id)

    cond do
      is_binary(dashboard_id) ->
        dashboard_id == document.dashboard_id and
          organization_matches?(organization_id, current_scope) and
          mission_matches?(mission_id, mission)

      is_binary(mission_id) ->
        mission_id == identity_value(mission, :mission_id) and
          organization_matches?(organization_id, current_scope)

      is_binary(organization_id) ->
        organization_id == identity_value(current_scope, :organization_id)

      true ->
        false
    end
  end

  defp organization_matches?(nil, _current_scope), do: true

  defp organization_matches?(organization_id, current_scope),
    do: organization_id == identity_value(current_scope, :organization_id)

  defp mission_matches?(nil, _mission), do: true

  defp mission_matches?(mission_id, mission),
    do: mission_id == identity_value(mission, :mission_id)

  defp identity_value(%{} = value, key),
    do: Map.get(value, key) || Map.get(value, Atom.to_string(key))

  defp identity_value(_value, _key), do: nil

  defp stale_for_context?(runtime_context, %Event{occurred_at: %DateTime{} = occurred_at}) do
    case Map.get(runtime_context, :context_since) do
      %DateTime{} = context_since -> DateTime.compare(occurred_at, context_since) == :lt
      _missing -> false
    end
  end

  defp stale_for_context?(_runtime_context, _invalidation), do: false

  defp overlaps_snapshot_time_context?(runtime_context, invalidation) do
    with {:ok, archive_range} <- normalize_time_range(Map.get(runtime_context, :time_context)),
         {:ok, invalidation_range} <-
           invalidation
           |> event_time_range()
           |> normalize_time_range(),
         true <- axes_compatible?(archive_range.axis, invalidation_range.axis) do
      intervals_overlap?(archive_range, invalidation_range)
    else
      :no_invalidation_range -> true
      _other -> true
    end
  end

  defp event_time_range(%Event{filters: filters}), do: filter(filters, :time_range)

  defp event_time_range(_event), do: nil

  defp normalize_time_range(nil), do: :no_invalidation_range

  defp normalize_time_range(range) when is_map(range) do
    from = filter(range, :from) || filter(range, :start) || filter(range, :start_time)
    to = filter(range, :to) || filter(range, :end) || filter(range, :end_time)
    axis = filter(range, :axis)

    with true <- not (is_nil(from) and is_nil(to)),
         {:ok, from} <- normalize_time_bound(from),
         {:ok, to} <- normalize_time_bound(to),
         true <- valid_interval?(from, to) do
      {:ok, %{axis: time_axis(axis), from: from, to: to}}
    else
      _other -> :error
    end
  end

  defp normalize_time_range(_range), do: :error

  defp normalize_time_bound(nil), do: {:ok, nil}
  defp normalize_time_bound(%DateTime{} = value), do: {:ok, value}

  defp normalize_time_bound(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> :error
    end
  end

  defp normalize_time_bound(_value), do: :error

  defp time_axis(nil), do: nil
  defp time_axis(axis) when is_atom(axis), do: Atom.to_string(axis)
  defp time_axis(axis) when is_binary(axis), do: axis
  defp time_axis(axis), do: to_string(axis)

  defp axes_compatible?(nil, _changed_axis), do: true
  defp axes_compatible?(_archive_axis, nil), do: true
  defp axes_compatible?(axis, axis), do: true
  defp axes_compatible?(_archive_axis, _changed_axis), do: false

  defp valid_interval?(%DateTime{} = from, %DateTime{} = to),
    do: DateTime.compare(from, to) != :gt

  defp valid_interval?(_from, _to), do: true

  defp intervals_overlap?(left, right) do
    starts_before_or_at_end?(left.from, right.to) and
      starts_before_or_at_end?(right.from, left.to)
  end

  defp starts_before_or_at_end?(nil, _right_to), do: true
  defp starts_before_or_at_end?(_left_from, nil), do: true

  defp starts_before_or_at_end?(%DateTime{} = left_from, %DateTime{} = right_to) do
    DateTime.compare(left_from, right_to) != :gt
  end

  defp update_boundary(summary, nil), do: summary

  defp update_boundary(summary, boundary) do
    Map.update!(
      summary,
      :boundaries,
      &Map.update(&1, boundary, 1, fn count -> count + 1 end)
    )
  end

  defp filter(filters, key), do: Map.get(filters, key) || Map.get(filters, Atom.to_string(key))
end
