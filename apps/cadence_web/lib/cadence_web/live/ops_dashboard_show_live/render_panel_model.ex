defmodule CadenceWeb.OpsDashboardShowLive.RenderPanelModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.PublishReadinessModel
  alias CadenceWeb.OpsDashboardShowLive.RenderPanelAssigns
  alias CadenceWeb.OpsDashboardShowLive.RenderShellAssigns
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation
  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectModel
  alias Phoenix.HTML.Form

  def open?(assigns) when is_map(assigns) do
    assigns
    |> RenderShellAssigns.shell_context()
    |> Map.fetch!(:panel_open?)
  end

  def props(assigns, runtime_diagnostics, current_path) when is_map(assigns) do
    context =
      assigns
      |> Map.put(
        :dashboard_recent_invalidations,
        recent_invalidations(assigns, runtime_diagnostics)
      )
      |> RenderPanelAssigns.panel_context()

    widget_form = context.widget_form
    point_query = form_value(widget_form, :point_q)
    widget_type = form_value(widget_form, :type)
    points = context.points
    operational_observables = context.operational_observables

    %{
      panel: context.panel,
      widget_inspect:
        WidgetInspectModel.build(
          context.panel,
          context.dashboard_render_items,
          context.frames_by_placement
        ),
      dashboard_activity_filter: context.dashboard_activity_filter,
      dashboard_activity_event_id: context.dashboard_activity_event_id,
      dashboard_review_placement_id: context.dashboard_review_placement_id,
      dashboard_selected_publish_issue_id: context.dashboard_selected_publish_issue_id,
      dashboard_comparison_review_action_outcome:
        context.dashboard_comparison_review_action_outcome,
      form: widget_form,
      binding_preview: context.widget_binding_preview,
      section_form: context.section_form,
      section_error: context.section_error,
      spacecraft: context.spacecraft,
      operational_observables: operational_observables,
      filtered_points: WidgetFormPresentation.filter_points(points, point_query),
      filtered_operational_observables:
        WidgetFormPresentation.filter_operational_observables(
          operational_observables,
          point_query,
          widget_type
        ),
      points_empty?: context.points_empty?,
      selected_point: WidgetFormPresentation.selected_point(points, context.selected_point_id),
      selected_points: WidgetFormPresentation.selected_points(points, context.selected_point_ids),
      selected_operational_observables:
        WidgetFormPresentation.selected_operational_observables(
          operational_observables,
          context.selected_point_ids,
          widget_type
        ),
      dashboard_scope_context: context.dashboard_scope_context,
      dashboard_editor_focus: context.dashboard_editor_focus,
      error: context.widget_error,
      mission_id: context.mission_id,
      dashboard_document: context.dashboard_document,
      dashboard_summary: context.dashboard_summary,
      dashboard_versions: context.dashboard_versions,
      dashboard_lifecycle_events: context.dashboard_lifecycle_events,
      dashboard_comparison_review_queue: context.dashboard_comparison_review_queue,
      dashboard_source_action_events: context.dashboard_source_action_events,
      dashboard_recent_invalidations: context.dashboard_recent_invalidations,
      dashboard_publish_readiness:
        PublishReadinessModel.build(
          context.dashboard_publish_validation,
          context.dashboard_publish_validation_freshness
        ),
      runtime_diagnostics: runtime_diagnostics,
      dashboard_current_path: current_path,
      historical_workflow_request_form: context.historical_workflow_request_form,
      data_link_action_outcome: context.data_link_action_outcome
    }
  end

  defp form_value(nil, _field), do: nil
  defp form_value(form, field), do: Form.input_value(form, field)

  defp recent_invalidations(%{dashboard_recent_invalidations: recent_invalidations}, _diagnostics)
       when is_list(recent_invalidations),
       do: recent_invalidations

  defp recent_invalidations(_assigns, %{recent_invalidations: recent_invalidations})
       when is_list(recent_invalidations),
       do: recent_invalidations

  defp recent_invalidations(_assigns, _runtime_diagnostics), do: []
end
