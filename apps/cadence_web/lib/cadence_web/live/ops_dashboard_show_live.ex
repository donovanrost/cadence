defmodule CadenceWeb.OpsDashboardShowLive.Controller do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.OpsDashboardShowLive.Components

  alias CadenceWeb.OpsDashboardShowLive.ComparisonInspectorComponents
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewEvents
  alias CadenceWeb.OpsDashboardShowLive.DashboardSectionEditing
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
  alias CadenceWeb.OpsDashboardShowLive.RuntimeControls
  alias CadenceWeb.OpsDashboardShowLive.RuntimeShell
  alias CadenceWeb.OpsDashboardShowLive.SelectionEvents
  alias CadenceWeb.OpsDashboardShowLive.StagedEditor
  alias CadenceWeb.OpsDashboardShowLive.WidgetEditingEvents
  alias CadenceWeb.OpsShellHook

  @impl true
  def mount(%{"dashboard_id" => dashboard_id}, _session, socket) do
    connected? = connected?(socket)

    socket
    |> MountFlow.mount_dashboard(
      dashboard_id,
      connected?,
      LiveDeps.mount_flow_opts()
    )
    |> maybe_activate_editor(socket.assigns.live_action)
    |> record_recent_dashboard(dashboard_id, connected?)
  end

  defp maybe_activate_editor({:ok, socket}, :edit), do: {:ok, StagedEditor.activate(socket)}

  defp maybe_activate_editor({:ok, socket}, _viewer_action) do
    {:ok,
     socket
     |> assign(:editor_route?, false)
     |> assign(:editor_dirty?, false)
     |> assign(:editor_change_summaries, [])
     |> assign(:editor_conflict, nil)}
  end

  defp record_recent_dashboard({:ok, socket}, dashboard_id, true) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case {socket.assigns[:dashboard_document], current_user_id(scope)} do
      {%{dashboard_id: ^dashboard_id}, user_id} when is_binary(user_id) ->
        _result =
          Cadence.Dashboards.record_dashboard_view(
            scope.organization_id,
            mission.mission_id,
            user_id,
            dashboard_id
          )

        {:ok, OpsShellHook.refresh_dashboard_navigation(socket)}

      _not_loaded ->
        {:ok, socket}
    end
  end

  defp record_recent_dashboard(result, _dashboard_id, _connected?), do: result

  defp current_user_id(scope) do
    case Map.get(scope, :user) do
      %{user_id: user_id} when is_binary(user_id) -> user_id
      _missing -> nil
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = RouteHydration.handle_params(socket, params, LiveDeps.route_hydration_opts())

    socket =
      if socket.assigns.editor_route? do
        StagedEditor.maybe_stage_explore_candidate(socket, params)
      else
        socket
      end

    {:noreply, socket}
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
  def handle_event("set_chart_time_range", params, socket) do
    {:noreply,
     RuntimeControlEvents.set_chart_time_range(socket, params, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("shift_time_range", %{"direction" => direction}, socket)
      when direction in ["back", "forward"] do
    {:noreply,
     RuntimeControlEvents.shift_time_range(
       socket,
       String.to_existing_atom(direction),
       LiveDeps.runtime_control_opts()
     )}
  end

  @impl true
  def handle_event("zoom_out_time_range", _params, socket) do
    {:noreply, RuntimeControlEvents.zoom_out_time_range(socket, LiveDeps.runtime_control_opts())}
  end

  @impl true
  def handle_event("time_quick_search", %{"query" => query}, socket) do
    {:noreply, RuntimeControls.time_quick_search(socket, query)}
  end

  @impl true
  def handle_event("time_recents_loaded", %{"ranges" => ranges}, socket) do
    {:noreply, RuntimeControls.load_time_recents(socket, ranges)}
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
  def handle_event("toggle_comparison_inspector", _params, socket) do
    {:noreply,
     assign(
       socket,
       :comparison_inspector_open?,
       not Map.get(socket.assigns, :comparison_inspector_open?, false)
     )}
  end

  @impl true
  def handle_event("close_comparison_inspector", _params, socket) do
    {:noreply, assign(socket, :comparison_inspector_open?, false)}
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
    if socket.assigns.editor_route? do
      {:noreply, StagedEditor.discard(socket)}
    else
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/missions/#{socket.assigns.current_mission.mission_id}/ops/dashboards/#{socket.assigns.dashboard_document.dashboard_id}/edit"
       )}
    end
  end

  @impl true
  def handle_event("layout_changed", %{"layouts" => layouts}, socket)
      when is_list(layouts) do
    {:noreply, WidgetEditingEvents.layout_changed(socket, layouts, widget_editing_opts(socket))}
  end

  @impl true
  def handle_event("open_add_widget", _params, socket) do
    {:noreply, WidgetEditingEvents.open_add_widget(socket, LiveDeps.widget_editing_event_opts())}
  end

  @impl true
  def handle_event("open_dashboard_sections", _params, socket) do
    {:noreply, DashboardSectionEditing.open(socket)}
  end

  @impl true
  def handle_event("edit_dashboard_section", %{"section-id" => section_id}, socket) do
    {:noreply, DashboardSectionEditing.edit(socket, section_id)}
  end

  @impl true
  def handle_event("validate_dashboard_section", %{"section" => params}, socket) do
    {:noreply, DashboardSectionEditing.validate(socket, params)}
  end

  @impl true
  def handle_event("save_dashboard_section", %{"section" => params}, socket) do
    {:noreply, DashboardSectionEditing.save(socket, params, widget_editing_opts(socket))}
  end

  @impl true
  def handle_event("remove_dashboard_section", %{"section-id" => section_id}, socket) do
    {:noreply, DashboardSectionEditing.remove(socket, section_id, widget_editing_opts(socket))}
  end

  @impl true
  def handle_event(
        "move_dashboard_section",
        %{"section-id" => section_id, "direction" => direction},
        socket
      ) do
    direction = if direction == "up", do: :up, else: :down

    {:noreply,
     DashboardSectionEditing.move(
       socket,
       section_id,
       direction,
       widget_editing_opts(socket)
     )}
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
  def handle_event("open_widget_inspector", %{"placement-id" => placement_id}, socket) do
    {:noreply, PanelEvents.open_widget_inspector(socket, placement_id)}
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
  def handle_event("preview_widget_binding", _params, socket) do
    {:noreply, WidgetEditingEvents.preview_widget_binding(socket, widget_editing_opts(socket))}
  end

  @impl true
  def handle_event("save_widget", %{"widget" => params}, socket) do
    {:noreply, WidgetEditingEvents.save_widget(socket, params, widget_editing_opts(socket))}
  end

  @impl true
  def handle_event("remove_widget", %{"widget-id" => placement_id}, socket) do
    {:noreply,
     WidgetEditingEvents.remove_widget(
       socket,
       placement_id,
       widget_editing_opts(socket)
     )}
  end

  @impl true
  def handle_event("rename", %{"dashboard" => params}, socket) do
    case RenameFlow.rename(socket, params, rename_flow_opts(socket)) do
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

  @impl true
  def handle_event("save_editor", _params, socket) do
    {:noreply, StagedEditor.save(socket)}
  end

  @impl true
  def handle_event("review_editor", _params, socket) do
    {:noreply, StagedEditor.save(socket, review?: true)}
  end

  @impl true
  def handle_event("discard_editor", _params, socket) do
    {:noreply, StagedEditor.discard(socket)}
  end

  @impl true
  def handle_event("reload_editor", _params, socket) do
    {:noreply, StagedEditor.reload(socket)}
  end

  defp widget_editing_opts(%{assigns: %{editor_route?: true}}),
    do: LiveDeps.staged_widget_editing_event_opts()

  defp widget_editing_opts(_socket), do: LiveDeps.widget_editing_event_opts()

  defp rename_flow_opts(%{assigns: %{editor_route?: true}}),
    do: LiveDeps.staged_rename_flow_opts()

  defp rename_flow_opts(_socket), do: LiveDeps.rename_flow_opts()

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
    assigns = assign(assigns, :render_model, RenderContext.model(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div {@render_model.page_attrs}>
      <.dashboard_toolbar
        {@render_model.toolbar_props}
        dashboard_warnings={@render_model.dashboard_warning_props.warnings}
        dashboard_degraded?={@render_model.dashboard_warning_props.degraded?}
        dashboard_health={@render_model.dashboard_health}
      />
      <div
        :if={@editor_conflict}
        id="dashboard-editor-conflict"
        class="flex shrink-0 items-center gap-3 border-b border-error/40 bg-error/10 px-3 py-2 text-sm"
        data-editor-starting-version={@editor_conflict.starting_version}
        data-editor-current-version={@editor_conflict.current_version}
      >
        <.icon name="hero-exclamation-triangle" class="h-4 w-4 shrink-0 text-error" />
        <p class="min-w-0 flex-1">
          Version {@editor_conflict.current_version} was saved elsewhere. Your staged candidate is
          intact; reload before continuing to avoid an accidental overwrite.
        </p>
        <.button id="dashboard-editor-reload" variant={:ghost} size={:xs} phx-click="reload_editor">
          Reload latest
        </.button>
      </div>
      <div class="flex flex-1 min-h-0">
        <div {@render_model.content_attrs}>
          <section
            :for={group <- @render_model.widget_groups}
            id={"dashboard-widget-group-#{group.id}"}
            class={[
              @editor_route? && "border-b border-base-300/45 last:border-b-0",
              not @editor_route? && "pt-1"
            ]}
            data-dashboard-widget-group={group.id}
          >
            <%= if group.section do %>
              <details
                id={"dashboard-section-group-#{group.id}"}
                open={group.open?}
                class={["group/dashboard-section"]}
                data-dashboard-section={group.id}
              >
                <summary class={[
                  "flex cursor-pointer list-none items-center gap-2 marker:hidden",
                  if(@editor_route?,
                    do: "sticky top-0 z-10 border-b border-base-300/50 bg-base-200/90 px-3 py-2 backdrop-blur",
                    else: "mx-2 rounded px-1 py-1.5 text-base-content/65 hover:text-base-content"
                  )
                ]}>
                  <.icon name="hero-chevron-right" class="h-3.5 w-3.5 text-base-content/45 transition-transform group-open/dashboard-section:rotate-90" />
                  <div class="min-w-0 flex-1">
                    <h2 class="text-xs font-semibold uppercase tracking-wide">{group.section.title}</h2>
                    <p :if={@editor_route? and group.section.description} class="truncate text-[0.65rem] text-base-content/50">
                      {group.section.description}
                    </p>
                  </div>
                  <span :if={@editor_route?} class="font-mono text-[0.65rem] text-base-content/45">
                    {length(group.widget_items)} {if length(group.widget_items) == 1, do: "widget", else: "widgets"}
                  </span>
                </summary>
                <.dashboard_widget_grid group={group} />
              </details>
            <% else %>
              <header
                :if={group.show_header?}
                class={[
                  "flex items-center gap-2 px-3",
                  if(@editor_route?,
                    do: "border-b border-base-300/50 bg-base-200/65 py-2",
                    else: "py-1.5 text-base-content/65"
                  )
                ]}
              >
                <.icon name="hero-square-3-stack-3d" class="h-3.5 w-3.5 text-base-content/45" />
                <h2 class="text-xs font-semibold uppercase tracking-wide">Unsectioned canvas</h2>
                <span :if={@editor_route?} class="ml-auto font-mono text-[0.65rem] text-base-content/45">
                  {length(group.widget_items)} {if length(group.widget_items) == 1, do: "widget", else: "widgets"}
                </span>
              </header>
              <.dashboard_widget_grid group={group} />
            <% end %>
          </section>
          <div
            :if={@render_model.empty_state.visible?}
            class={@render_model.empty_state.wrapper_class}
          >
            <%!-- empty_state actions only take navigate/patch; this dashboard needs a phx-click add --%>
            <div class={@render_model.empty_state.card_class}>
              <span class={@render_model.empty_state.icon_class}></span>
              <p class="hud-label mt-3">{@render_model.empty_state.title}</p>
              <p class="mt-2 max-w-md mx-auto text-sm text-base-content/70">
                {@render_model.empty_state.message}
              </p>
              <div class="mt-5">
                <.button
                  :if={@editor_route?}
                  id="dashboard-editor-empty-add-widget"
                  phx-click={@render_model.empty_state.action_event}
                >
                  <.icon name={@render_model.empty_state.action_icon} class="-ml-0.5 mr-1 h-4 w-4" />
                  {@render_model.empty_state.action_label}
                </.button>
                <.link
                  :if={not @editor_route? and @dashboard_author?}
                  id="dashboard-viewer-empty-edit"
                  navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{@dashboard_document.dashboard_id}/edit"}
                  class="btn btn-primary btn-sm"
                >
                  <.icon name="hero-pencil-square" class="h-4 w-4" /> Open Dashboard Editor
                </.link>
              </div>
            </div>
          </div>
        </div>
        <ComparisonInspectorComponents.comparison_inspector
          open?={@render_model.comparison_inspector_open?}
          rollup={@render_model.comparison_rollup}
          preset={@render_model.comparison_preset}
          open_review_summary={@render_model.open_review_summary}
          saved_presets={@render_model.comparison_presets}
        />
      </div>
      <FormComponents.widget_panel
        :if={@render_model.panel_open?}
        {@render_model.panel_props}
      />
    </div>
    </Layouts.app>
    """
  end

  attr :group, :map, required: true

  defp dashboard_widget_grid(assigns) do
    ~H"""
    <div {@group.grid_props}>
      <div :for={widget_item <- @group.widget_items} {widget_item.shell_attrs}>
        <div class={widget_item.content_class}>
          <.widget {widget_item.component_props} />
        </div>
      </div>
    </div>
    """
  end
end
