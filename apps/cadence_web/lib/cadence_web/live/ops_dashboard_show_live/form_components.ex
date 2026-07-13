defmodule CadenceWeb.OpsDashboardShowLive.FormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestFormComponents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormComponents

  attr :panel, :any, required: true
  attr :dashboard_activity_filter, :atom, default: nil
  attr :dashboard_activity_event_id, :string, default: nil
  attr :dashboard_review_placement_id, :string, default: nil
  attr :dashboard_readiness_return_intent, :string, default: nil
  attr :dashboard_selected_publish_issue_id, :string, default: nil
  attr :dashboard_comparison_review_action_outcome, :map, default: nil
  attr :form, Phoenix.HTML.Form, required: true
  attr :spacecraft, :list, required: true
  attr :operational_observables, :list, required: true
  attr :filtered_points, :list, required: true
  attr :filtered_operational_observables, :list, required: true
  attr :points_empty?, :boolean, required: true
  attr :selected_point, :any, required: true
  attr :selected_points, :list, required: true
  attr :selected_operational_observables, :list, required: true
  attr :dashboard_scope_context, :any, required: true
  attr :dashboard_editor_focus, :map, default: nil
  attr :error, :string, required: true
  attr :mission_id, :string, required: true
  attr :dashboard_document, :any, required: true
  attr :dashboard_summary, :any, required: true
  attr :dashboard_versions, :list, required: true
  attr :dashboard_lifecycle_events, :list, required: true
  attr :dashboard_comparison_review_queue, :map, required: true
  attr :dashboard_source_action_events, :list, default: []
  attr :dashboard_recent_invalidations, :list, default: []
  attr :dashboard_publish_readiness, :map, default: nil
  attr :runtime_diagnostics, :map, required: true
  attr :dashboard_current_path, :string, required: true
  attr :historical_workflow_request_form, Phoenix.HTML.Form, required: true
  attr :data_link_action_outcome, :map, default: nil

  def widget_panel(assigns) do
    ~H"""
    <.sheet
      id="dashboard-panel"
      title={panel_title(@panel)}
      width={:md}
      close_event="close_panel"
    >
        <.rename_form :if={@panel == :rename} dashboard_document={@dashboard_document} />
        <HistoricalWorkflowRequestFormComponents.request_form
          :if={@panel == :historical_workflow_request}
          form={@historical_workflow_request_form}
        />
        <DataLinkInspectorPanelComponents.data_link_panel
          :if={data_link_panel?(@panel)}
          inspector={data_link_inspector(@panel)}
          mission_id={@mission_id}
          dashboard_document={@dashboard_document}
          dashboard_current_path={@dashboard_current_path}
          data_link_action_outcome={@data_link_action_outcome}
        />
        <EvidenceInspectorPanelComponents.evidence_panel
          :if={evidence_panel?(@panel)}
          inspector={evidence_inspector(@panel)}
          mission_id={@mission_id}
          dashboard_document={@dashboard_document}
          dashboard_current_path={@dashboard_current_path}
          dashboard_lifecycle_events={@dashboard_lifecycle_events}
        />
        <RuntimeDiagnosticsPanelComponents.diagnostics_panel
          :if={@panel == :diagnostics}
          diagnostics={@runtime_diagnostics}
          dashboard_lifecycle_events={@dashboard_lifecycle_events}
          dashboard_current_path={@dashboard_current_path}
        />
        <VersionHistoryPanelComponents.versions_panel
          :if={@panel == :versions}
          dashboard_document={@dashboard_document}
          dashboard_summary={@dashboard_summary}
          dashboard_versions={@dashboard_versions}
          dashboard_lifecycle_events={@dashboard_lifecycle_events}
          dashboard_comparison_review_queue={@dashboard_comparison_review_queue}
          dashboard_source_action_events={@dashboard_source_action_events}
          dashboard_recent_invalidations={@dashboard_recent_invalidations}
          dashboard_activity_filter={@dashboard_activity_filter}
          dashboard_activity_event_id={@dashboard_activity_event_id}
          dashboard_review_placement_id={@dashboard_review_placement_id}
          dashboard_readiness_return_intent={@dashboard_readiness_return_intent}
          dashboard_selected_publish_issue_id={@dashboard_selected_publish_issue_id}
          dashboard_comparison_review_action_outcome={@dashboard_comparison_review_action_outcome}
          dashboard_publish_readiness={@dashboard_publish_readiness}
          dashboard_current_path={@dashboard_current_path}
        />
        <WidgetFormComponents.widget_form
          :if={widget_form_panel?(@panel)}
          panel={@panel}
          form={@form}
          spacecraft={@spacecraft}
          operational_observables={@operational_observables}
          filtered_points={@filtered_points}
          filtered_operational_observables={@filtered_operational_observables}
          points_empty?={@points_empty?}
          selected_point={@selected_point}
          selected_points={@selected_points}
          selected_operational_observables={@selected_operational_observables}
          dashboard_scope_context={@dashboard_scope_context}
          dashboard_editor_focus={@dashboard_editor_focus}
          error={@error}
          mission_id={@mission_id}
        />
    </.sheet>
    """
  end

  attr :dashboard_document, :any, required: true

  defp rename_form(assigns) do
    ~H"""
    <.form
      for={to_form(%{"name" => @dashboard_document.name, "description" => @dashboard_document.description || ""}, as: :dashboard)}
      id="rename-dashboard-form"
      phx-submit="rename"
      class="space-y-4"
    >
      <.input
        name="dashboard[name]"
        value={@dashboard_document.name}
        type="text"
        label="Name"
        required
      />
      <.input
        name="dashboard[description]"
        value={@dashboard_document.description}
        type="text"
        label="Description"
      />
      <.button type="submit" size={:md}>Save</.button>
    </.form>
    """
  end

  defp data_link_panel?({:data_link, _inspector}), do: true
  defp data_link_panel?(_panel), do: false

  defp data_link_inspector({:data_link, inspector}), do: inspector

  defp evidence_panel?({:evidence, _inspector}), do: true
  defp evidence_panel?(_panel), do: false

  defp evidence_inspector({:evidence, inspector}), do: inspector

  defp widget_form_panel?(:add_widget), do: true
  defp widget_form_panel?({:edit_placement, _id}), do: true
  defp widget_form_panel?(_panel), do: false

  defp panel_title(:add_widget), do: "Add Widget"
  defp panel_title({:edit_placement, _id}), do: "Configure Widget"
  defp panel_title(:rename), do: "Rename Dashboard"
  defp panel_title(:versions), do: "Version History"
  defp panel_title(:diagnostics), do: "Diagnostics"
  defp panel_title(:historical_workflow_request), do: "Historical Data Request"
  defp panel_title({:data_link, inspector}), do: inspector.title
  defp panel_title({:evidence, inspector}), do: inspector.title
end
