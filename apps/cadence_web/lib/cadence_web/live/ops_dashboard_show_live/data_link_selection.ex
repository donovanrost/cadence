defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelection do
  @moduledoc false

  alias Cadence.Dashboards.{DataContext, DataLink, ScopeContext}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection.EvidencePanel

  alias CadenceWeb.OpsDashboardShowLive.{
    EvidenceQuery,
    RuntimeQueryParams,
    SelectedDataRef,
    SelectionQuery
  }

  def synthetic_link_from_query(query) when is_map(query) do
    selection_query = SelectionQuery.to_params(query)

    with target when not is_nil(target) <- target(Map.get(selection_query, "selected_target")),
         target_id when is_binary(target_id) <- text_param(selection_query["selected_id"]) do
      %DataLink{
        link_id: synthetic_link_id(target, target_id),
        label: target |> data_ref_text() |> String.replace("_", " "),
        target: target,
        target_id: target_id,
        context: context_from_query(query),
        presentation: :side_panel,
        source: :annotation
      }
    else
      _missing -> nil
    end
  end

  def synthetic_link_from_query(_query), do: nil

  def synthetic_link_from_event_params(params) when is_map(params) do
    %{
      "selected_target" => text_param(params["target"]),
      "selected_id" => text_param(params["target-id"]),
      "selected_placement" => text_param(params["placement-id"]),
      "selected_time" => integer_param(params, "timestamp-ms")
    }
    |> synthetic_link_from_query()
  end

  def synthetic_link_from_event_params(_params), do: nil

  def with_selection_context(%DataLink{} = link, params) when is_map(params) do
    selection =
      %{
        placement_id: text_param(params["placement-id"]),
        timestamp_ms: integer_param(params, "timestamp-ms"),
        series_role: text_param(params["series-role"]),
        compare_of: text_param(params["compare-of"])
      }
      |> compact_flat()

    data_context =
      %{
        realm: text_param(params["realm"]),
        view: text_param(params["data-view"]),
        data_source_id: text_param(params["data-source-id"]),
        source_binding_id: text_param(params["source-binding-id"]),
        replay_run_id: text_param(params["replay-run-id"])
      }
      |> compact_flat()

    time_context =
      %{
        mode: text_param(params["time-mode"]),
        axis: text_param(params["time-axis"]),
        replay_run_id: text_param(params["replay-run-id"])
      }
      |> compact_flat()

    comparison_context =
      %{
        state: text_param(params["comparison-state"]),
        delta: text_param(params["comparison-delta"]),
        primary_sample_id: text_param(params["primary-sample-id"]),
        compare_sample_id: text_param(params["compare-sample-id"]),
        primary_data_view: text_param(params["primary-data-view"]),
        compare_data_view: text_param(params["compare-data-view"]),
        primary_data_management: text_param(params["primary-data-management"]),
        compare_data_management: text_param(params["compare-data-management"]),
        primary_count: integer_param(params, "primary-count"),
        compare_count: integer_param(params, "compare-count"),
        widget_id: text_param(params["widget-id"]),
        widget_title: text_param(params["widget-title"]),
        widget_type: text_param(params["widget-type"]),
        widget_source: text_param(params["widget-source"]),
        primary_kind: text_param(params["primary-kind"]),
        compare_kind: text_param(params["compare-kind"]),
        primary_observables: text_param(params["primary-observables"]),
        compare_observables: text_param(params["compare-observables"])
      }
      |> compact_flat()

    scope_context =
      %{
        scope_kind: text_param(params["scope-kind"]),
        scope_id: text_param(params["scope-id"]),
        scope_ids: scope_ids_param(params["scope-ids"]),
        resource_id: text_param(params["resource-id"]),
        spacecraft_id: text_param(params["spacecraft-id"]),
        contact_id: text_param(params["contact-id"]),
        contact_ids: scope_ids_param(params["contact-ids"]),
        transport_id: text_param(params["transport-id"]),
        source_endpoint_id: text_param(params["source-endpoint-id"]),
        ground_station_id: text_param(params["ground-station-id"]),
        scope_link_id: text_param(params["scope-link-id"])
      }
      |> compact_flat()

    navigation_context =
      %{
        from: %{
          link_id: text_param(params["nav-from-link-id"]),
          target: text_param(params["nav-from-target"]),
          target_id: text_param(params["nav-from-target-id"]),
          label: text_param(params["nav-from-label"]),
          relationship_kind: text_param(params["nav-from-relationship-kind"]),
          relationship_label: text_param(params["nav-from-relationship-label"])
        },
        trail: navigation_trail_param(params["nav-trail"])
      }
      |> compact_nested_context()

    context =
      link.context
      |> context_map()
      |> maybe_put_context(:selection, selection)
      |> maybe_put_context(:time, time_context)
      |> maybe_put_context(:data, data_context)
      |> maybe_put_context(:comparison, comparison_context)
      |> maybe_put_context(:scope, scope_context)
      |> maybe_put_context(:navigation, navigation_context)

    if context == context_map(link.context) do
      link
    else
      %DataLink{link | context: context}
    end
  end

  def with_runtime_context(%DataLink{} = link, runtime_context) when is_map(runtime_context) do
    context =
      runtime_context
      |> compact_nested_context()
      |> deep_merge_context(context_map(link.context))

    %DataLink{link | context: context}
  end

  def context_from_query(%SelectionQuery{} = query),
    do: query |> SelectionQuery.to_params() |> context_from_query()

  def context_from_query(query) when is_map(query) do
    %{
      time: %{
        mode: text_param(query["time_mode"]),
        axis: text_param(query["time_axis"]),
        from: text_param(query["from"]),
        to: text_param(query["to"]),
        replay_run_id: text_param(query["replay_run_id"])
      },
      data: %{
        realm: text_param(query["realm"]),
        view: text_param(query["selected_data_view"]) || text_param(query["data_view"]),
        data_source_id: text_param(query["data_source_id"]),
        source_binding_id: text_param(query["source_binding_id"]),
        replay_run_id: text_param(query["replay_run_id"])
      },
      limit: %{
        semantics_mode: text_param(query["limit_mode"])
      },
      observable_id: text_param(query["selected_observable"]),
      selection: %{
        placement_id: text_param(query["selected_placement"]),
        timestamp_ms: integer_param(query, "selected_time"),
        series_role: text_param(query["selected_series_role"]),
        compare_of: text_param(query["selected_compare_of"])
      },
      comparison: %{
        state: text_param(query["selected_comparison_state"]),
        delta: text_param(query["selected_comparison_delta"]),
        primary_sample_id: text_param(query["selected_primary_sample"]),
        compare_sample_id: text_param(query["selected_compare_sample"]),
        primary_data_view: text_param(query["selected_primary_data_view"]),
        compare_data_view: text_param(query["selected_compare_data_view"]),
        primary_data_management: text_param(query["selected_primary_data_management"]),
        compare_data_management: text_param(query["selected_compare_data_management"]),
        primary_count: integer_param(query, "selected_primary_count"),
        compare_count: integer_param(query, "selected_compare_count"),
        widget_id: text_param(query["selected_widget"]),
        widget_title: text_param(query["selected_widget_title"]),
        widget_type: text_param(query["selected_widget_type"]),
        widget_source: text_param(query["selected_widget_source"]),
        primary_kind: text_param(query["selected_primary_kind"]),
        compare_kind: text_param(query["selected_compare_kind"]),
        primary_observables: text_param(query["selected_primary_observables"]),
        compare_observables: text_param(query["selected_compare_observables"])
      },
      scope: %{
        scope_kind: text_param(query["selected_scope_kind"]),
        scope_id: text_param(query["selected_scope_id"]),
        scope_ids: scope_ids_param(query["selected_scope_ids"]),
        resource_id: text_param(query["selected_resource_id"]),
        spacecraft_id: text_param(query["selected_spacecraft_id"]),
        contact_id: text_param(query["selected_contact_id"]),
        contact_ids: scope_ids_param(query["selected_contact_ids"]),
        transport_id: text_param(query["selected_transport_id"]),
        source_endpoint_id: text_param(query["selected_source_endpoint_id"]),
        ground_station_id: text_param(query["selected_ground_station_id"]),
        scope_link_id: text_param(query["selected_scope_link_id"])
      },
      navigation: %{
        from: %{
          link_id: text_param(query["nav_from_link_id"]),
          target: text_param(query["nav_from_target"]),
          target_id: text_param(query["nav_from_target_id"]),
          label: text_param(query["nav_from_label"]),
          relationship_kind: text_param(query["nav_from_relationship_kind"]),
          relationship_label: text_param(query["nav_from_relationship_label"])
        },
        trail: navigation_trail_param(query["nav_trail"])
      }
    }
    |> compact_nested_context()
  end

  def event_params_from_selection_query(query), do: SelectionQuery.to_event_params(query)

  def missing_selected_link_id(query), do: SelectionQuery.missing_selected_link_id(query)

  def panel_from_params(params) when is_map(params) do
    case text_param(params["panel"]) do
      "data_link" -> :data_link
      "evidence" -> :evidence
      "versions" -> :versions
      _other -> nil
    end
  end

  def selection_query_from_params(params, panel_query),
    do: SelectionQuery.from_params(params, panel_query)

  def selection_query_from_ref(selected_ref), do: SelectionQuery.from_ref(selected_ref)

  def selected_ref(%DataLink{} = link, params) when is_map(params) do
    {scope_kind, scope_id, scope_ids} = data_link_scope_identity(link.context)

    operational_scope_kind =
      data_link_context_value(link.context, :operational_resource, :scope_kind)

    operational_scope_id =
      data_link_context_value(link.context, :operational_resource, :resource_id)

    {selected_scope_kind, selected_scope_id} =
      selected_scope_identity(
        link.target,
        link.target_id,
        scope_kind,
        scope_id,
        scope_ids,
        operational_scope_kind,
        operational_scope_id
      )

    %{
      "link_id" => link.link_id,
      "target" => data_ref_text(link.target),
      "target_id" => link.target_id,
      "target_text" => link.target |> data_ref_text() |> String.replace("_", " "),
      "timestamp_ms" => selected_timestamp_ms(link, params),
      "placement_id" => selected_placement_id(link, params),
      "source" => data_ref_text(link.source),
      "scope_kind" => selected_scope_kind,
      "scope_id" => selected_scope_id,
      "scope_ids" => scope_ids_text(scope_ids),
      "spacecraft_id" => data_link_context_spacecraft_id(link.context),
      "resource_id" => data_link_context_value(link.context, :scope, :resource_id),
      "contact_id" => data_link_context_value(link.context, :scope, :contact_id),
      "contact_ids" => data_link_context_contact_ids_text(link.context),
      "transport_id" =>
        data_link_scope_or_target_resource_value(
          link.context,
          :transport_id,
          link.target,
          :transport
        ),
      "source_endpoint_id" =>
        data_link_scope_or_target_resource_value(
          link.context,
          :source_endpoint_id,
          link.target,
          :source_endpoint
        ),
      "ground_station_id" =>
        data_link_scope_or_target_resource_value(
          link.context,
          :ground_station_id,
          link.target,
          :ground_station
        ),
      "scope_link_id" =>
        data_link_scope_or_target_resource_value(
          link.context,
          :scope_link_id,
          link.target,
          :link,
          :link_id
        ),
      "realm" => data_link_context_value(link.context, :data, :realm),
      "time_mode" => data_link_context_value(link.context, :time, :mode),
      "time_axis" => data_link_context_value(link.context, :time, :axis),
      "data_view" => data_link_source_context_value(link.context, :view),
      "series_role" =>
        text_param(params["series-role"]) ||
          data_link_context_value(link.context, :selection, :series_role),
      "compare_of" =>
        text_param(params["compare-of"]) ||
          data_link_context_value(link.context, :selection, :compare_of),
      "replay_run_id" => data_link_replay_run_id(link.context),
      "data_source_id" => data_link_source_context_value(link.context, :data_source_id),
      "source_binding_id" => data_link_source_context_value(link.context, :source_binding_id),
      "limit_mode" => data_link_context_value(link.context, :limit, :semantics_mode),
      "observable_id" => data_link_context_value(link.context, :observable_id),
      "nav_from_link_id" => data_link_context_value(link.context, :navigation, :from, :link_id),
      "nav_from_target" => data_link_context_value(link.context, :navigation, :from, :target),
      "nav_from_target_id" =>
        data_link_context_value(link.context, :navigation, :from, :target_id),
      "nav_from_label" => data_link_context_value(link.context, :navigation, :from, :label),
      "nav_from_relationship_kind" =>
        data_link_context_value(link.context, :navigation, :from, :relationship_kind),
      "nav_from_relationship_label" =>
        data_link_context_value(link.context, :navigation, :from, :relationship_label),
      "nav_trail" => navigation_trail_context_value(link.context)
    }
    |> Map.merge(comparison_selected_ref(link.context))
    |> compact_flat()
    |> SelectedDataRef.new()
  end

  def selected_ref_for_runtime_context(selected_ref, runtime_context) do
    SelectedDataRef.for_runtime_context(selected_ref, runtime_context)
  end

  def selected_ref_matches_runtime_context?(selected_ref, runtime_context) do
    SelectedDataRef.matches_runtime_context?(selected_ref, runtime_context)
  end

  def selected_ref_matches_query_runtime_context?(selected_ref, runtime_context) do
    SelectedDataRef.matches_query_runtime_context?(selected_ref, runtime_context)
  end

  def stale_selection_decision(query, selected_ref, selection_query, runtime_context) do
    query = Map.new(query)

    if selected_ref_for_runtime_context(selected_ref, runtime_context) do
      %{action: :keep, query: query}
    else
      %{
        action: stale_selection_action(selected_ref, selection_query),
        query: Map.merge(query, clear_selection_query())
      }
    end
  end

  def evidence_query_from_params(params, panel_query),
    do: EvidenceQuery.from_params(params, panel_query)

  def evidence_query_from_event_params(params) when is_map(params) do
    EvidenceQuery.from_event_params(params)
  end

  def event_params_from_evidence_query(query) do
    EvidenceQuery.to_event_params(query)
  end

  def missing_evidence_inspector(query) do
    kind = EvidenceQuery.value(query, "selected_evidence_kind") || "evidence"

    %{
      kind: kind,
      kind_text: context_text(kind) || "evidence",
      subject: missing_evidence_subject(query),
      status: :missing,
      status_text: "missing",
      title: "Missing Evidence",
      message:
        "The dashboard could not resolve this evidence link against the current runtime context.",
      subject_rows: missing_evidence_subject_rows(query),
      detail_rows: missing_evidence_detail_rows(query),
      evidence: [],
      links: []
    }
  end

  def evidence_state(panel, evidence_query) do
    cond do
      EvidencePanel.status(panel) == :missing ->
        "missing"

      EvidencePanel.panel?(panel) ->
        "active"

      evidence_query?(evidence_query) ->
        "query_only"

      true ->
        "none"
    end
  end

  def evidence_kind(panel, evidence_query) do
    EvidencePanel.kind(panel) ||
      evidence_query_value(evidence_query, "selected_evidence_kind")
  end

  def evidence_source_request(panel, evidence_query) do
    EvidencePanel.source_request(panel) ||
      evidence_query_value(evidence_query, "selected_source_request")
  end

  def evidence_logical_source(panel, evidence_query) do
    EvidencePanel.logical_source(panel) ||
      evidence_query_value(evidence_query, "selected_logical_source")
  end

  def evidence_realm(panel, evidence_query) do
    EvidencePanel.realm(panel) ||
      evidence_query_value(evidence_query, "selected_realm")
  end

  def evidence_data_source_id(panel, evidence_query) do
    EvidencePanel.data_source_id(panel) ||
      evidence_query_value(evidence_query, "selected_data_source")
  end

  def evidence_source_binding_id(panel, evidence_query) do
    EvidencePanel.source_binding_id(panel) ||
      evidence_query_value(evidence_query, "selected_source_binding")
  end

  def evidence_time_mode(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Time mode") ||
      evidence_query_value(evidence_query, "selected_time_mode")
  end

  def evidence_time_axis(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Time axis") ||
      evidence_query_value(evidence_query, "selected_time_axis")
  end

  def evidence_replay_run_id(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Replay run") ||
      evidence_query_value(evidence_query, "selected_replay_run_id")
  end

  def evidence_scope_kind(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Scope kind") ||
      evidence_query_value(evidence_query, "selected_scope_kind")
  end

  def evidence_scope_id(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Scope") ||
      evidence_query_value(evidence_query, "selected_scope_id")
  end

  def evidence_scope_ids(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Scopes") ||
      evidence_query_value(evidence_query, "selected_scope_ids")
  end

  def evidence_contact_id(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Contact") ||
      evidence_query_value(evidence_query, "selected_contact_id")
  end

  def evidence_source_endpoint_id(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Source endpoint") ||
      evidence_query_value(evidence_query, "selected_source_endpoint_id")
  end

  def evidence_source_empty_reason(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Source empty reason") ||
      evidence_query_value(evidence_query, "selected_source_empty_reason")
  end

  def evidence_requested_realm(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Requested realm") ||
      evidence_query_value(evidence_query, "selected_requested_realm")
  end

  def evidence_requested_data_view(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Requested data view") ||
      evidence_query_value(evidence_query, "selected_requested_data_view")
  end

  def evidence_requested_data_source_id(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Requested data source") ||
      evidence_query_value(evidence_query, "selected_requested_data_source")
  end

  def evidence_requested_source_binding_id(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Requested source binding") ||
      evidence_query_value(evidence_query, "selected_requested_source_binding")
  end

  def evidence_requested_dataset(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Requested dataset") ||
      evidence_query_value(evidence_query, "selected_requested_dataset")
  end

  def evidence_requested_validity_state(panel, evidence_query) do
    EvidencePanel.row_value(panel, "Requested validity") ||
      evidence_query_value(evidence_query, "selected_requested_validity_state")
  end

  def current_query(attrs), do: RuntimeQueryParams.to_params(attrs)

  def compact_query(query), do: RuntimeQueryParams.compact(query)

  def panel_query(:data_link, query) when is_map(query) do
    clear_evidence_query()
    |> Map.merge(SelectionQuery.to_params(query))
    |> Map.put("panel", "data_link")
  end

  def panel_query(:evidence, query) when is_map(query) do
    clear_selection_query()
    |> Map.merge(EvidenceQuery.to_params(query))
    |> Map.put("panel", "evidence")
  end

  def clear_panel_query(:data_link), do: Map.put(clear_selection_query(), "panel", nil)
  def clear_panel_query(:evidence), do: Map.put(clear_evidence_query(), "panel", nil)

  def current_panel_query(selection_query, evidence_query),
    do: RuntimeQueryParams.current_panel_query(selection_query, evidence_query)

  def data_link_panel_query?(query), do: SelectionQuery.query?(query)

  def clear_evidence_query, do: EvidenceQuery.clear_query()

  def clear_selection_query, do: SelectionQuery.clear_query()

  defp target(target_value), do: DataLink.parse_resolvable_target(target_value)

  defp synthetic_link_id(target, target_id), do: "direct:#{target}:#{target_id}"

  defp context_map(context) when is_map(context), do: context
  defp context_map(_context), do: %{}

  defp deep_merge_context(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge_context(left_value, right_value)
    end)
  end

  defp deep_merge_context(_left, right), do: right

  defp maybe_put_context(context, _key, value) when value == %{}, do: context

  defp maybe_put_context(context, key, value) when is_map(context) and is_map(value) do
    Map.update(context, key, value, fn existing ->
      deep_merge_context(context_map(existing), value)
    end)
  end

  defp compact_nested_context(context) when is_map(context) do
    context
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case compact_context_value(value) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp compact_context_value(%_{} = value), do: value

  defp compact_context_value([]), do: nil

  defp compact_context_value(value) when is_map(value) do
    case compact_nested_context(value) do
      compacted when map_size(compacted) == 0 -> nil
      compacted -> compacted
    end
  end

  defp compact_context_value(value) when value in [nil, ""], do: nil
  defp compact_context_value(value), do: value

  defp compact_flat(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil

  defp navigation_trail_param(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, entries} when is_list(entries) ->
        entries
        |> Enum.map(&normalize_navigation_trail_entry/1)
        |> Enum.reject(&(&1 == %{}))
        |> Enum.take(-3)

      _invalid ->
        []
    end
  end

  defp navigation_trail_param(_value), do: []

  defp normalize_navigation_trail_entry(entry) when is_map(entry) do
    %{
      link_id: navigation_entry_text(entry, :link_id),
      target: navigation_entry_text(entry, :target),
      target_id: navigation_entry_text(entry, :target_id),
      label: navigation_entry_text(entry, :label),
      relationship_kind: navigation_entry_text(entry, :relationship_kind),
      relationship_label: navigation_entry_text(entry, :relationship_label),
      placement_id: navigation_entry_text(entry, :placement_id),
      timestamp_ms: navigation_entry_text(entry, :timestamp_ms),
      realm: navigation_entry_text(entry, :realm),
      data_view: navigation_entry_text(entry, :data_view),
      data_source_id: navigation_entry_text(entry, :data_source_id),
      source_binding_id: navigation_entry_text(entry, :source_binding_id),
      time_mode: navigation_entry_text(entry, :time_mode),
      time_axis: navigation_entry_text(entry, :time_axis),
      replay_run_id: navigation_entry_text(entry, :replay_run_id)
    }
    |> compact_flat()
  end

  defp normalize_navigation_trail_entry(_entry), do: %{}

  defp navigation_entry_text(entry, key) when is_map(entry) do
    entry
    |> Map.get(key, Map.get(entry, Atom.to_string(key)))
    |> context_text()
    |> text_param()
  end

  defp integer_param(params, key) do
    case Map.get(params, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _invalid -> nil
        end

      _other ->
        nil
    end
  end

  defp stale_selection_action(nil, nil), do: :none
  defp stale_selection_action(_selected_ref, _selection_query), do: :clear_stale

  defp missing_evidence_subject(query) do
    EvidenceQuery.subject(query)
  end

  defp missing_evidence_subject_rows(query) do
    EvidenceQuery.subject_rows(query, &context_text/1)
  end

  defp missing_evidence_detail_rows(query) do
    EvidenceQuery.detail_rows(query, &context_text/1)
  end

  defp evidence_query_value(evidence_query, key) do
    EvidenceQuery.value(evidence_query, key)
  end

  defp evidence_query?(evidence_query) do
    EvidenceQuery.query?(evidence_query)
  end

  defp data_link_context_spacecraft_id(context) do
    scope = data_link_context_value(context, :scope)

    ScopeContext.scope_id(scope, :spacecraft)
  end

  defp data_link_scope_identity(context) do
    context
    |> data_link_context_value(:scope)
    |> scope_identity()
  end

  defp selected_scope_identity(
         target,
         target_id,
         scope_kind,
         scope_id,
         scope_ids,
         operational_scope_kind,
         operational_scope_id
       ) do
    cond do
      operational_resource_target?(target, operational_scope_kind) ->
        {operational_scope_kind, operational_scope_id}

      scoped_data_link_target?(target, target_id, scope_kind, scope_ids) ->
        {scope_kind, target_id}

      true ->
        {scope_kind || operational_scope_kind, scope_id || operational_scope_id}
    end
  end

  defp operational_resource_target?(target, operational_scope_kind)
       when is_binary(operational_scope_kind) do
    data_ref_text(target) == operational_scope_kind
  end

  defp operational_resource_target?(_target, _operational_scope_kind), do: false

  defp scoped_data_link_target?(target, target_id, scope_kind, scope_ids)
       when is_binary(target_id) and is_binary(scope_kind) and is_list(scope_ids) do
    data_ref_text(target) == scope_kind and target_id in scope_ids
  end

  defp scoped_data_link_target?(_target, _target_id, _scope_kind, _scope_ids), do: false

  defp data_link_source_context_value(context, key) do
    data_context = data_link_context_value(context, :data)
    logical_source = data_link_context_value(context, :logical_source)

    data_context
    |> DataContext.source_value(logical_source || :telemetry, key)
    |> context_text()
  rescue
    ArgumentError -> nil
  end

  defp data_link_replay_run_id(context) do
    data_link_context_value(context, :data, :replay_run_id) ||
      data_link_context_value(context, :time, :replay_run_id) ||
      data_link_context_value(context, :replay_run_id)
  end

  defp comparison_selected_ref(context) do
    %{
      "comparison_state" => data_link_context_value(context, :comparison, :state),
      "comparison_delta" => data_link_context_value(context, :comparison, :delta),
      "primary_sample_id" => data_link_context_value(context, :comparison, :primary_sample_id),
      "compare_sample_id" => data_link_context_value(context, :comparison, :compare_sample_id),
      "primary_data_view" => data_link_context_value(context, :comparison, :primary_data_view),
      "compare_data_view" => data_link_context_value(context, :comparison, :compare_data_view),
      "primary_data_management" =>
        data_link_context_value(context, :comparison, :primary_data_management),
      "compare_data_management" =>
        data_link_context_value(context, :comparison, :compare_data_management),
      "primary_count" => data_link_context_value(context, :comparison, :primary_count),
      "compare_count" => data_link_context_value(context, :comparison, :compare_count),
      "widget_id" => data_link_context_value(context, :comparison, :widget_id),
      "widget_title" => data_link_context_value(context, :comparison, :widget_title),
      "widget_type" => data_link_context_value(context, :comparison, :widget_type),
      "widget_source" => data_link_context_value(context, :comparison, :widget_source),
      "primary_kind" => data_link_context_value(context, :comparison, :primary_kind),
      "compare_kind" => data_link_context_value(context, :comparison, :compare_kind),
      "primary_observables" =>
        data_link_context_value(context, :comparison, :primary_observables),
      "compare_observables" => data_link_context_value(context, :comparison, :compare_observables)
    }
  end

  defp navigation_trail_context_value(context) do
    context
    |> data_link_context_value(:navigation)
    |> data_link_context_value(:trail)
    |> case do
      entries when is_list(entries) ->
        normalized_entries =
          entries
          |> Enum.map(&normalize_navigation_trail_entry/1)
          |> Enum.reject(&(&1 == %{}))
          |> Enum.take(-3)

        if normalized_entries == [], do: nil, else: Jason.encode!(normalized_entries)

      _other ->
        nil
    end
  end

  defp data_link_context_value(context, section, key) do
    context
    |> data_link_context_value(section)
    |> data_link_context_value(key)
    |> context_text()
  end

  defp data_link_context_value(context, section, subsection, key) do
    context
    |> data_link_context_value(section)
    |> data_link_context_value(subsection)
    |> data_link_context_value(key)
    |> context_text()
  end

  defp data_link_context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp data_link_context_value(_context, _key), do: nil

  defp data_link_context_contact_ids_text(context) do
    scope = data_link_context_value(context, :scope)

    contact_ids =
      scope
      |> data_link_context_value(:contact_ids)
      |> scope_ids_param()

    contact_ids =
      if contact_ids == [] and contact_scope?(scope) do
        scope_ids(scope)
      else
        contact_ids
      end

    scope_ids_text(contact_ids)
  end

  defp contact_scope?(scope) when is_map(scope) do
    ScopeContext.primary_kind(scope) in [:contact, "contact"]
  rescue
    _error -> false
  end

  defp contact_scope?(_scope), do: false

  defp data_link_scope_or_target_resource_value(
         context,
         scope_key,
         target,
         resource_target,
         resource_key \\ nil
       ) do
    resource_key = resource_key || scope_key

    data_link_context_value(context, :scope, scope_key) ||
      data_link_context_value(context, :operational_resource, resource_key) ||
      data_link_target_resource_value(context, target, resource_target, resource_key)
  end

  defp data_link_target_resource_value(context, target, resource_target, resource_key) do
    if target == resource_target do
      data_link_context_value(context, :operational_resource, resource_key)
    end
  end

  defp scope_identity(%{scope_kind: kind, scope_id: id} = scope),
    do: {context_text(kind), context_text(id), scope_ids(scope)}

  defp scope_identity(%{"scope_kind" => kind, "scope_id" => id} = scope),
    do: {context_text(kind), context_text(id), scope_ids(scope)}

  defp scope_identity(scope) when is_map(scope) do
    primary_scope_identity(scope) || typed_scope_identity(scope)
  end

  defp scope_identity(_scope), do: {nil, nil, []}

  defp primary_scope_identity(scope) do
    kind = scope |> ScopeContext.primary_kind() |> context_text()
    ids = scope_ids(scope)

    if kind in [nil, ""] or ids == [] do
      nil
    else
      {kind, List.first(ids), ids}
    end
  end

  defp typed_scope_identity(scope) do
    cond do
      id = ScopeContext.scope_id(scope, :spacecraft) ->
        {"spacecraft", id, scope_ids(scope)}

      id = ScopeContext.scope_id(scope, :mission) ->
        {"mission", id, scope_ids(scope)}

      id = ScopeContext.scope_id(scope, :contact) ->
        {"contact", id, scope_ids(scope)}

      id = ScopeContext.scope_id(scope, :ground_station) ->
        {"ground_station", id, scope_ids(scope)}

      id = ScopeContext.scope_id(scope, :source_endpoint) ->
        {"source_endpoint", id, scope_ids(scope)}

      id = ScopeContext.scope_id(scope, :transport) ->
        {"transport", id, scope_ids(scope)}

      id = ScopeContext.scope_id(scope, :link) ->
        {"link", id, scope_ids(scope)}

      true ->
        {nil, nil, []}
    end
  end

  defp scope_ids(scope) when is_map(scope) do
    scope
    |> data_link_context_value(:scope_ids)
    |> scope_ids_param()
    |> case do
      [] -> ScopeContext.primary_ids(scope)
      ids -> ids
    end
  rescue
    _error -> []
  end

  defp scope_ids_text(scope_ids) when is_list(scope_ids) and length(scope_ids) > 1,
    do: Enum.join(scope_ids, ",")

  defp scope_ids_text(_scope_ids), do: nil

  defp scope_ids_param(value) when is_list(value) do
    value
    |> Enum.flat_map(&scope_ids_param/1)
    |> Enum.uniq()
  end

  defp scope_ids_param(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp scope_ids_param(_value), do: []

  defp selected_timestamp_ms(%DataLink{} = link, params) do
    integer_param(params, "timestamp-ms") ||
      get_in(link.context, [:selection, :timestamp_ms]) ||
      get_in(link.context, ["selection", "timestamp_ms"])
  end

  defp selected_placement_id(%DataLink{} = link, params) do
    text_param(params["placement-id"]) ||
      get_in(link.context, [:selection, :placement_id]) ||
      get_in(link.context, ["selection", "placement_id"])
  end

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
  defp context_text(value) when is_integer(value), do: Integer.to_string(value)
  defp context_text(_value), do: nil

  defp data_ref_text(nil), do: nil
  defp data_ref_text(value) when is_atom(value), do: Atom.to_string(value)
  defp data_ref_text(value) when is_binary(value), do: value
  defp data_ref_text(value), do: to_string(value)
end
