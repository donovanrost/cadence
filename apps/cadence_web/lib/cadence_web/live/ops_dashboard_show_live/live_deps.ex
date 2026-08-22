defmodule CadenceWeb.OpsDashboardShowLive.LiveDeps do
  @moduledoc false

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document

  alias CadenceWeb.OpsDashboardShowLive.ContactScopePolicy
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.OperationalResourceScopePolicy
  alias CadenceWeb.OpsDashboardShowLive.RouteHydration
  alias CadenceWeb.OpsDashboardShowLive.StagedEditor
  alias CadenceWeb.OpsDashboardShowLive.WidgetEditingEvents

  def historical_workflow_event_opts, do: []

  def late_data_policy_event_opts do
    Application.get_env(:cadence_web, :ops_dashboard_show_live, [])
    |> Keyword.get(:late_data_policy_event_opts, [])
  end

  def revision_decision_event_opts, do: []

  def investigation_preset_event_opts, do: []

  def comparison_review_event_opts do
    [dashboard_comparison_review_queue: &dashboard_comparison_review_queue/4]
  end

  def health_snapshot_event_opts, do: []

  def selection_event_opts, do: []

  def selection_hydration_opts, do: []

  def runtime_control_opts do
    [
      valid_contact?: &ContactScopePolicy.valid_contact?/3,
      valid_operational_resource_scope?: &OperationalResourceScopePolicy.valid_resource?/4
    ]
  end

  def route_hydration_opts do
    [
      valid_contact?: &ContactScopePolicy.valid_contact?/3,
      valid_operational_resource_scope?: &OperationalResourceScopePolicy.valid_resource?/4,
      dashboard_list_path: &dashboard_list_path/1,
      assign_runtime_context: &assign_runtime_context_for_document/2
    ]
  end

  def runtime_shell_opts do
    [selection_hydration_opts: selection_hydration_opts()]
  end

  def mount_flow_opts do
    [
      dashboard_list_path: &dashboard_list_path/1,
      runtime_shell_opts: runtime_shell_opts()
    ]
  end

  def widget_editing_event_opts do
    [
      dashboard_list_path: &dashboard_list_path/1,
      persist_document: &persist_document/3,
      refresh_widget_data: &WidgetEditingEvents.refresh_widget_data/1,
      assign_runtime_context: &assign_runtime_context_for_document/2
    ]
  end

  def staged_widget_editing_event_opts do
    [
      dashboard_list_path: &dashboard_list_path/1,
      persist_document: &StagedEditor.stage/3,
      refresh_widget_data: &WidgetEditingEvents.refresh_widget_data/1,
      assign_runtime_context: &assign_runtime_context_for_document/2
    ]
  end

  def rename_flow_opts do
    [persist_document: &persist_document/3]
  end

  def staged_rename_flow_opts do
    [persist_document: &StagedEditor.stage/3]
  end

  def lifecycle_event_opts do
    [dashboard_list_path: &dashboard_list_path/1]
  end

  def persist_document(socket, %Document{} = document, opts) do
    DocumentLifecycle.persist_document(socket, document, opts,
      dashboard_list_path: &dashboard_list_path/1
    )
  end

  def dashboard_list_path(socket) do
    ~p"/missions/#{socket.assigns.current_mission.mission_id}/ops/dashboards"
  end

  def dashboard_comparison_review_queue(
        organization_id,
        mission_id,
        dashboard_id,
        _lifecycle_events
      ) do
    Cadence.Dashboards.dashboard_comparison_review_queue(
      organization_id,
      mission_id,
      dashboard_id
    )
  end

  defp assign_runtime_context_for_document(socket, %Document{} = document) do
    RouteHydration.assign_runtime_context(
      socket,
      RouteHydration.runtime_context_for_document(socket, document, route_hydration_opts())
    )
  end
end
