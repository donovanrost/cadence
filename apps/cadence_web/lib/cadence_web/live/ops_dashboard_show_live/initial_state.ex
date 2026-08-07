defmodule CadenceWeb.OpsDashboardShowLive.InitialState do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.DashboardSectionEditing
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenter
  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation
  alias CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowRequestDefaults

  def assign_loaded_dashboard(socket, resources, opts \\ []) when is_map(resources) do
    %{
      document: %Document{} = document,
      document_mode: document_mode,
      points: points,
      operational_observables: operational_observables,
      spacecraft: spacecraft,
      source_endpoints: source_endpoints,
      transports: transports,
      link_assignments: link_assignments,
      scheduled_contacts: scheduled_contacts,
      realized_contacts: realized_contacts,
      data_realms: data_realms,
      data_bindings: data_bindings
    } = resources

    ground_stations = Map.get(resources, :ground_stations, [])
    replay_runs = Map.get(resources, :replay_runs, [])
    default_realm = RuntimeQuery.default_data_realm(data_realms)
    default_live_refresh_ms = Keyword.fetch!(opts, :default_live_refresh_ms)
    runtime_context_since = Keyword.get_lazy(opts, :runtime_context_since, &DateTime.utc_now/0)

    socket
    |> DocumentLifecycle.assign_document(document, document_mode)
    |> assign(:dashboard_versions, [])
    |> assign(:dashboard_lifecycle_events, [])
    |> assign(:dashboard_comparison_review_queue, ComparisonReviewQueue.open_summary([]))
    |> assign(:dashboard_source_action_events, [])
    |> assign(:dashboard_lifecycle_status, Cadence.Dashboards.dashboard_lifecycle_status(nil))
    |> assign(:dashboard_publish_validation, nil)
    |> assign(:dashboard_publish_validation_freshness, nil)
    |> assign(:dashboard_summary, nil)
    |> assign(:active_dashboard_id, document.dashboard_id)
    |> assign(:points, points)
    |> assign(:points_by_id, Map.new(points, &{&1.point_id, &1}))
    |> assign(:operational_observables, operational_observables)
    |> assign(:stale_timeouts, stale_timeouts(points))
    |> assign(:spacecraft, spacecraft)
    |> assign(:source_endpoints, source_endpoints)
    |> assign(:transports, transports)
    |> assign(:ground_stations, ground_stations)
    |> assign(:link_assignments, link_assignments)
    |> assign(:scheduled_contacts, scheduled_contacts)
    |> assign(:realized_contacts, realized_contacts)
    |> assign(:context_spacecraft_id, nil)
    |> assign(:context_scope_kind, nil)
    |> assign(:context_scope_id, nil)
    |> assign(:context_scope_ids, [])
    |> assign(:dashboard_scope_context, RuntimeQuery.default_scope_context())
    |> assign(:dashboard_time_mode, "live")
    |> assign(:dashboard_time_from, nil)
    |> assign(:dashboard_time_to, nil)
    |> assign(:dashboard_time_axis, "generation_time")
    |> assign(:dashboard_replay_run_id, nil)
    |> assign(:dashboard_time_validation, "ok")
    |> assign(:dashboard_time_quick_query, "")
    |> assign(:dashboard_time_recent_ranges, [])
    |> assign(:dashboard_data_realms, data_realms)
    |> assign(:dashboard_data_bindings, data_bindings)
    |> assign(:dashboard_replay_runs, replay_runs)
    |> assign(:dashboard_data_realm, default_realm)
    |> assign(:dashboard_data_view, "canonical")
    |> assign(:dashboard_compare_data_view, nil)
    |> assign(:dashboard_data_source_id, nil)
    |> assign(:dashboard_source_binding_id, nil)
    |> assign(:dashboard_limit_mode, "observed")
    |> assign(:dashboard_limit_mode_fallback, nil)
    |> assign(:dashboard_hidden_marker_categories, [])
    |> assign(:dashboard_time_context, %{"mode" => "live", "axis" => "generation_time"})
    |> assign(:dashboard_data_context, %{
      "realm" => default_realm,
      "view" => "canonical",
      "source_mode" => "primary",
      "source_contexts" => %{}
    })
    |> assign(:dashboard_limit_context, %{"semantics_mode" => "observed"})
    |> assign(:context_query, "")
    |> assign(:widget_data, %{})
    |> assign(:backfills, %{})
    |> assign(:tick_count, 0)
    |> assign(:edit_mode?, false)
    |> assign(:panel, nil)
    |> assign(:dashboard_activity_filter, nil)
    |> assign(:dashboard_activity_event_id, nil)
    |> assign(:dashboard_review_placement_id, nil)
    |> assign(:dashboard_readiness_return_intent, nil)
    |> assign(:dashboard_selected_publish_issue_id, nil)
    |> assign(:dashboard_comparison_review_action_outcome, nil)
    |> assign(:comparison_inspector_open?, false)
    |> assign(:widget_error, nil)
    |> assign(:widget_binding_preview, nil)
    |> assign(:section_error, nil)
    |> assign(:section_form, to_form(DashboardSectionEditing.form_defaults(), as: :section))
    |> assign(:selected_point_id, nil)
    |> assign(:selected_point_ids, [])
    |> assign(:dashboard_selected_data_ref, nil)
    |> assign(:dashboard_selection_query, nil)
    |> assign(:dashboard_selection_state, "none")
    |> assign(:dashboard_evidence_query, nil)
    |> assign(:widget_form, to_form(WidgetFormPresentation.widget_form_defaults(), as: :widget))
    |> assign(
      :historical_workflow_request_form,
      to_form(
        HistoricalWorkflowPresenter.request_form_defaults()
        |> HistoricalWorkflowRequestDefaults.form_params(),
        as: :historical_workflow_request
      )
    )
    |> assign(:data_link_action_outcome, nil)
    |> assign(:data_link_action_outcome_query, nil)
    |> assign(:chart_epoch, 0)
    |> assign(:dashboard_engine_result, nil)
    |> assign(:dashboard_engine_frames_by_placement, %{})
    |> assign(:dashboard_compare_engine_result, nil)
    |> assign(:dashboard_compare_engine_frames_by_placement, %{})
    |> assign(:dashboard_live_refresh_ms, default_live_refresh_ms)
    |> assign(:dashboard_tick_timer_ref, nil)
    |> assign(:dashboard_last_runtime_invalidation, nil)
    |> assign(:dashboard_runtime_context_since, runtime_context_since)
    |> Runtime.assign_runtime()
  end

  defp stale_timeouts(points) do
    for %{stale_timeout_ms: timeout} = point <- points,
        is_integer(timeout),
        into: %{},
        do: {point.point_id, timeout}
  end
end
