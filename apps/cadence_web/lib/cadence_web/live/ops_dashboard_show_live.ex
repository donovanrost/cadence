defmodule CadenceWeb.OpsDashboardShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.OpsDashboardShowLive.Components

  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewEvents
  alias CadenceWeb.OpsDashboardShowLive.ContextRailSections
  alias CadenceWeb.OpsDashboardShowLive.FormComponents
  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotEvents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowEvents
  alias CadenceWeb.OpsDashboardShowLive.InvestigationPresetEvents
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyEvents
  alias CadenceWeb.OpsDashboardShowLive.LifecycleEvents
  alias CadenceWeb.OpsDashboardShowLive.LiveDeps
  alias CadenceWeb.OpsDashboardShowLive.MountFlow
  alias CadenceWeb.OpsDashboardShowLive.PanelEvents
  alias CadenceWeb.OpsDashboardShowLive.RenameFlow
  alias CadenceWeb.OpsDashboardShowLive.RenderContext
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionEvents
  alias CadenceWeb.OpsDashboardShowLive.RouteHydration
  alias CadenceWeb.OpsDashboardShowLive.RuntimeControlEvents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeShell
  alias CadenceWeb.OpsDashboardShowLive.SelectionEvents
  alias CadenceWeb.OpsDashboardShowLive.WidgetEditingEvents
  alias CadenceWeb.ScopeLoader

  @impl true
  def mount(%{"dashboard_id" => dashboard_id}, session, socket) do
    socket =
      assign(
        socket,
        :dashboard_browser_test_sandbox_owner_key,
        ScopeLoader.browser_test_sandbox_owner_key(session)
      )

    MountFlow.mount_dashboard(
      socket,
      dashboard_id,
      connected?(socket),
      LiveDeps.mount_flow_opts()
    )
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, RouteHydration.handle_params(socket, params, LiveDeps.route_hydration_opts())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, RuntimeShell.handle_tick(socket, LiveDeps.runtime_shell_opts())}
  end

  @impl true
  def handle_info({:dashboard_runtime_invalidated, invalidation}, socket) do
    {:noreply,
     RuntimeShell.handle_invalidation(socket, invalidation, LiveDeps.runtime_shell_opts())}
  end

  @impl true
  def handle_async(
        {:dashboard_engine_resolve, resolve_id},
        {:ok, {returned_resolve_id, result}},
        socket
      ) do
    {:noreply,
     RuntimeShell.resolve_succeeded(
       socket,
       resolve_id,
       returned_resolve_id,
       result,
       LiveDeps.runtime_shell_opts()
     )}
  end

  def handle_async({:dashboard_engine_resolve, resolve_id}, {:exit, reason}, socket) do
    {:noreply,
     RuntimeShell.resolve_failed(socket, resolve_id, reason, LiveDeps.runtime_shell_opts())}
  end

  @impl true
  def terminate(_reason, socket) do
    RuntimeShell.terminate(socket, LiveDeps.runtime_shell_opts())
    :ok
  end

  @impl true
  def handle_event("context_search", %{"q" => q}, socket) do
    {:noreply, RuntimeControlEvents.context_search(socket, q, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("set_context", %{"scope-kind" => scope_kind, "scope-ids" => scope_ids}, socket) do
    {:noreply,
     RuntimeControlEvents.set_context(
       socket,
       %{"scope_kind" => scope_kind, "scope_ids" => scope_ids},
       LiveDeps.runtime_control_opts()
     )}
  end

  @impl true
  def handle_event("set_context", %{"scope-kind" => scope_kind, "scope-id" => scope_id}, socket) do
    {:noreply,
     RuntimeControlEvents.set_context(
       socket,
       %{"scope_kind" => scope_kind, "scope_id" => scope_id},
       LiveDeps.runtime_control_opts()
     )}
  end

  def handle_event("set_context", %{"spacecraft-id" => spacecraft_id}, socket) do
    {:noreply,
     RuntimeControlEvents.set_context(socket, spacecraft_id, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("clear_context", _params, socket) do
    {:noreply, RuntimeControlEvents.clear_context(socket, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("set_runtime_context", params, socket) do
    {:noreply,
     RuntimeControlEvents.set_runtime_context(socket, params, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("resume_live", _params, socket) do
    {:noreply, RuntimeControlEvents.resume_live(socket, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("set_time_preset", %{"preset" => "live"}, socket) do
    {:noreply,
     RuntimeControlEvents.set_time_preset(socket, "live", LiveDeps.runtime_control_opts())}
  end

  def handle_event("set_time_preset", %{"preset" => preset}, socket) do
    {:noreply,
     RuntimeControlEvents.set_time_preset(socket, preset, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("pause_at_selected_time", _params, socket) do
    {:noreply,
     RuntimeControlEvents.pause_at_selected_time(socket, LiveDeps.runtime_control_opts())}
  end

  def handle_event("scrub_replay_to_selection", _params, socket) do
    {:noreply,
     RuntimeControlEvents.scrub_replay_to_selection(socket, LiveDeps.runtime_control_opts())}
  end

  def handle_event("clear_data_selection", _params, socket) do
    {:noreply, RuntimeControlEvents.clear_data_selection(socket, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("save_comparison_preset", params, socket) do
    {:noreply,
     InvestigationPresetEvents.save_comparison_preset(
       socket,
       params,
       LiveDeps.investigation_preset_event_opts()
     )}
  end

  @impl true
  def handle_event("apply_comparison_preset", params, socket) do
    {:noreply,
     InvestigationPresetEvents.apply_comparison_preset(
       socket,
       params,
       LiveDeps.investigation_preset_event_opts()
     )}
  end

  @impl true
  def handle_event("delete_comparison_preset", params, socket) do
    {:noreply,
     InvestigationPresetEvents.delete_comparison_preset(
       socket,
       params,
       LiveDeps.investigation_preset_event_opts()
     )}
  end

  @impl true
  def handle_event("request_comparison_review", params, socket) do
    {:noreply,
     ComparisonReviewEvents.request_open_findings_review(
       socket,
       params,
       LiveDeps.comparison_review_event_opts()
     )}
  end

  @impl true
  def handle_event("resolve_comparison_review", params, socket) do
    {:noreply,
     ComparisonReviewEvents.resolve_open_findings_review(
       socket,
       params,
       LiveDeps.comparison_review_event_opts()
     )}
  end

  @impl true
  def handle_event("apply_comparison_review_bulk_decision", params, socket) do
    {:noreply,
     ComparisonReviewEvents.apply_bulk_revision_decision(
       socket,
       params,
       LiveDeps.comparison_review_event_opts()
     )}
  end

  @impl true
  def handle_event("capture_dashboard_health_snapshot", params, socket) do
    {:noreply,
     HealthSnapshotEvents.capture_dashboard_health_snapshot(
       socket,
       params,
       LiveDeps.health_snapshot_event_opts()
     )}
  end

  @impl true
  def handle_event("toggle_edit", _params, socket) do
    {:noreply, WidgetEditingEvents.toggle_edit(socket, LiveDeps.widget_editing_event_opts())}
  end

  @impl true
  def handle_event("layout_changed", %{"layouts" => layouts}, socket)
      when is_list(layouts) do
    {:noreply,
     WidgetEditingEvents.layout_changed(socket, layouts, LiveDeps.widget_editing_event_opts())}
  end

  @impl true
  def handle_event("open_add_widget", _params, socket) do
    {:noreply, WidgetEditingEvents.open_add_widget(socket, LiveDeps.widget_editing_event_opts())}
  end

  @impl true
  def handle_event("open_widget_config", %{"widget-id" => placement_id}, socket) do
    {:noreply,
     WidgetEditingEvents.open_widget_config(
       socket,
       placement_id,
       LiveDeps.widget_editing_event_opts()
     )}
  end

  @impl true
  def handle_event("open_rename", _params, socket) do
    {:noreply, PanelEvents.open_rename(socket)}
  end

  @impl true
  def handle_event("open_versions", _params, socket) do
    {:noreply, PanelEvents.open_versions(socket)}
  end

  @impl true
  def handle_event("refresh_publish_readiness", _params, socket) do
    {:noreply, PanelEvents.refresh_publish_readiness(socket)}
  end

  @impl true
  def handle_event("set_activity_filter", %{"filter" => filter}, socket) do
    {:noreply, PanelEvents.open_activity_filter(socket, filter)}
  end

  @impl true
  def handle_event("select_activity_event", %{"event-id" => event_id}, socket) do
    {:noreply, PanelEvents.select_activity_event(socket, event_id)}
  end

  @impl true
  def handle_event("open_review_activity", _params, socket) do
    {:noreply, PanelEvents.open_review_activity(socket)}
  end

  @impl true
  def handle_event("select_review_placement", %{"placement-id" => placement_id}, socket) do
    {:noreply, PanelEvents.select_review_placement(socket, placement_id)}
  end

  @impl true
  def handle_event("open_diagnostics", _params, socket) do
    {:noreply, PanelEvents.open_diagnostics(socket)}
  end

  @impl true
  def handle_event("open_historical_workflow_request", _params, socket) do
    {:noreply,
     HistoricalWorkflowEvents.open_request(socket, LiveDeps.historical_workflow_event_opts())}
  end

  @impl true
  def handle_event("open_comparison_review_workflow_request", params, socket) do
    {:noreply,
     HistoricalWorkflowEvents.open_comparison_review_request(
       socket,
       params,
       LiveDeps.historical_workflow_event_opts()
     )}
  end

  @impl true
  def handle_event("open_evidence", params, socket) do
    {:noreply, SelectionEvents.open_evidence(socket, params, LiveDeps.selection_event_opts())}
  end

  @impl true
  def handle_event("open_data_link", %{"link-id" => link_id} = params, socket) do
    {:noreply,
     SelectionEvents.open_data_link(socket, link_id, params, LiveDeps.selection_event_opts())}
  end

  @impl true
  def handle_event("record_historical_workflow_stage", params, socket) do
    {:noreply,
     HistoricalWorkflowEvents.record_stage(
       socket,
       params,
       LiveDeps.historical_workflow_event_opts()
     )}
  end

  @impl true
  def handle_event("record_historical_workflow_group_stage", params, socket) do
    {:noreply,
     HistoricalWorkflowEvents.record_group_stage(
       socket,
       params,
       LiveDeps.historical_workflow_event_opts()
     )}
  end

  @impl true
  def handle_event("record_historical_workflow_request", params, socket) do
    {:noreply,
     HistoricalWorkflowEvents.record_request(
       socket,
       params,
       LiveDeps.historical_workflow_event_opts()
     )}
  end

  @impl true
  def handle_event("record_corrected_historical_workflow_request", params, socket) do
    {:noreply,
     HistoricalWorkflowEvents.record_correction_request(
       socket,
       params,
       LiveDeps.historical_workflow_event_opts()
     )}
  end

  @impl true
  def handle_event("record_late_data_policy_decision", params, socket) do
    {:noreply,
     LateDataPolicyEvents.record_decision(socket, params, LiveDeps.late_data_policy_event_opts())}
  end

  @impl true
  def handle_event("apply_revision_decision", params, socket) do
    {:noreply,
     RevisionDecisionEvents.apply_decision(
       socket,
       params,
       LiveDeps.revision_decision_event_opts()
     )}
  end

  @impl true
  def handle_event(
        "retry_historical_workflow_job",
        %{"job-id" => job_id, "event-id" => event_id} = params,
        socket
      ) do
    opts =
      LiveDeps.historical_workflow_event_opts()
      |> maybe_put_replacement_run_id(params)

    {:noreply,
     HistoricalWorkflowEvents.retry_job(
       socket,
       job_id,
       event_id,
       opts
     )}
  end

  @impl true
  def handle_event(
        "inspect_stale_historical_workflow_replacement_job",
        %{"job-id" => job_id, "event-id" => event_id} = params,
        socket
      ) do
    opts =
      LiveDeps.historical_workflow_event_opts()
      |> maybe_put_replacement_run_id(params)

    {:noreply,
     HistoricalWorkflowEvents.inspect_stale_replacement_job(
       socket,
       job_id,
       event_id,
       opts
     )}
  end

  @impl true
  def handle_event(
        "inspect_missing_historical_workflow_replacement_job",
        %{"request-group-id" => request_group_id, "replacement-run-id" => replacement_run_id},
        socket
      ) do
    {:noreply,
     HistoricalWorkflowEvents.inspect_missing_replacement_job(
       socket,
       request_group_id,
       replacement_run_id,
       LiveDeps.historical_workflow_event_opts()
     )}
  end

  @impl true
  def handle_event(
        "requeue_stale_historical_workflow_replacement_job",
        %{"job-id" => job_id, "event-id" => event_id} = params,
        socket
      ) do
    opts =
      LiveDeps.historical_workflow_event_opts()
      |> maybe_put_replacement_run_id(params)

    {:noreply,
     HistoricalWorkflowEvents.requeue_stale_replacement_job(
       socket,
       job_id,
       event_id,
       opts
     )}
  end

  @impl true
  def handle_event(
        "retry_historical_workflow_group_failed_jobs",
        %{"request-group-id" => request_group_id, "event-id" => event_id} = params,
        socket
      ) do
    opts =
      LiveDeps.historical_workflow_event_opts()
      |> Keyword.put(:retry_run_ids, retry_run_ids(Map.get(params, "retry-run-ids")))

    {:noreply,
     HistoricalWorkflowEvents.retry_group_failed_jobs(
       socket,
       request_group_id,
       event_id,
       opts
     )}
  end

  @impl true
  def handle_event("close_panel", _params, socket) do
    {:noreply, PanelEvents.close(socket)}
  end

  @impl true
  def handle_event("validate_widget", %{"widget" => params}, socket) do
    {:noreply,
     WidgetEditingEvents.validate_widget(socket, params, LiveDeps.widget_editing_event_opts())}
  end

  @impl true
  def handle_event("pick_point", %{"point-id" => point_id}, socket) do
    {:noreply,
     WidgetEditingEvents.pick_point(socket, point_id, LiveDeps.widget_editing_event_opts())}
  end

  @impl true
  def handle_event("save_widget", %{"widget" => params}, socket) do
    {:noreply,
     WidgetEditingEvents.save_widget(socket, params, LiveDeps.widget_editing_event_opts())}
  end

  @impl true
  def handle_event("remove_widget", %{"widget-id" => placement_id}, socket) do
    {:noreply,
     WidgetEditingEvents.remove_widget(
       socket,
       placement_id,
       LiveDeps.widget_editing_event_opts()
     )}
  end

  @impl true
  def handle_event("rename", %{"dashboard" => params}, socket) do
    case RenameFlow.rename(socket, params, LiveDeps.rename_flow_opts()) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("archive_dashboard", _params, socket) do
    {:noreply, LifecycleEvents.archive_dashboard(socket, LiveDeps.lifecycle_event_opts())}
  end

  @impl true
  def handle_event("publish_dashboard", _params, socket) do
    {:noreply, LifecycleEvents.publish_dashboard(socket, LiveDeps.lifecycle_event_opts())}
  end

  @impl true
  def handle_event("publish_dashboard_version", %{"version" => version}, socket) do
    {:noreply,
     LifecycleEvents.publish_dashboard_version(socket, version, LiveDeps.lifecycle_event_opts())}
  end

  @impl true
  def handle_event("save_runtime_defaults", _params, socket) do
    case LifecycleEvents.save_runtime_defaults(socket, LiveDeps.lifecycle_event_opts()) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("restore_version_as_draft", %{"version" => version}, socket) do
    {:noreply,
     LifecycleEvents.restore_version_as_draft(socket, version, LiveDeps.lifecycle_event_opts())}
  end

  defp retry_run_ids(value) when is_binary(value) do
    value
    |> String.split([",", ";", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp retry_run_ids(_value), do: []

  defp maybe_put_replacement_run_id(opts, params) do
    case text_param(Map.get(params, "replacement-run-id")) do
      nil -> opts
      replacement_run_id -> Keyword.put(opts, :replacement_run_id, replacement_run_id)
    end
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <% render_model = RenderContext.model(assigns) %>
    <div {render_model.page_attrs}>
      <.dashboard_toolbar
        {render_model.toolbar_props}
        dashboard_warnings={render_model.dashboard_warning_props.warnings}
        dashboard_degraded?={render_model.dashboard_warning_props.degraded?}
        dashboard_health={render_model.dashboard_health}
      />
      <div class="flex flex-1 min-h-0">
        <div {render_model.content_attrs}>
          <div
            {render_model.grid_props}
          >
            <div
              :for={widget_item <- render_model.widget_items}
              {widget_item.shell_attrs}
            >
              <div class={widget_item.content_class}>
                <.widget
                  {widget_item.component_props}
                />
              </div>
            </div>
          </div>
          <div
            :if={render_model.empty_state.visible?}
            class={render_model.empty_state.wrapper_class}
          >
            <%!-- empty_state actions only take navigate/patch; this dashboard needs a phx-click add --%>
            <div class={render_model.empty_state.card_class}>
              <span class={render_model.empty_state.icon_class}></span>
              <p class="hud-label mt-3">{render_model.empty_state.title}</p>
              <p class="mt-2 max-w-md mx-auto text-sm text-base-content/70">
                {render_model.empty_state.message}
              </p>
              <div class="mt-5">
                <.button phx-click={render_model.empty_state.action_event}>
                  <.icon name={render_model.empty_state.action_icon} class="-ml-0.5 mr-1 h-4 w-4" />
                  {render_model.empty_state.action_label}
                </.button>
              </div>
            </div>
          </div>
        </div>
        <ContextRailSections.dashboard_context_rail render_model={render_model} />
      </div>
      <FormComponents.widget_panel
        :if={render_model.panel_open?}
        {render_model.panel_props}
      />
    </div>
    """
  end
end
