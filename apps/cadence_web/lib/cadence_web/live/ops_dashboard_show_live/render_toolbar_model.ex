defmodule CadenceWeb.OpsDashboardShowLive.RenderToolbarModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.PublishReadinessModel
  alias CadenceWeb.OpsDashboardShowLive.RenderToolbarAssigns

  def props(assigns) when is_map(assigns) do
    context = RenderToolbarAssigns.toolbar_context(assigns)

    %{
      dashboard_document: context.dashboard_document,
      dashboard_lifecycle_status: context.dashboard_lifecycle_status,
      dashboard_lifecycle_events: context.dashboard_lifecycle_events,
      dashboard_comparison_review_queue: context.dashboard_comparison_review_queue,
      dashboard_publish_readiness:
        PublishReadinessModel.build(
          context.dashboard_publish_validation,
          context.dashboard_publish_validation_freshness
        ),
      edit_mode?: context.edit_mode?,
      editor_route?: context.editor_route?,
      editor_dirty?: context.editor_dirty?,
      editor_conflict: context.editor_conflict,
      dashboard_author?: context.dashboard_author?,
      show_context?: context.show_context?,
      current_mission: context.current_mission,
      spacecraft: context.spacecraft,
      source_endpoints: context.source_endpoints,
      transports: context.transports,
      ground_stations: context.ground_stations,
      link_assignments: context.link_assignments,
      scheduled_contacts: context.scheduled_contacts,
      realized_contacts: context.realized_contacts,
      context_spacecraft_id: context.context_spacecraft_id,
      context_scope_kind: context.context_scope_kind,
      context_scope_id: context.context_scope_id,
      context_scope_ids: context.context_scope_ids,
      time_mode: context.time_mode,
      time_axis: context.time_axis,
      time_from: context.time_from,
      time_to: context.time_to,
      replay_run_id: context.replay_run_id,
      time_validation: context.time_validation,
      data_realm: context.data_realm,
      data_realms: context.data_realms,
      data_view: context.data_view,
      compare_data_view: context.compare_data_view,
      data_source_id: context.data_source_id,
      source_binding_id: context.source_binding_id,
      data_bindings: context.data_bindings,
      replay_runs: context.replay_runs,
      selected_replay_run: selected_replay_run(context.replay_runs, context.replay_run_id),
      limit_mode: context.limit_mode,
      limit_mode_fallback: context.limit_mode_fallback,
      hidden_marker_categories: context.hidden_marker_categories,
      selected_data_ref: context.selected_data_ref,
      time_quick_query: context.time_quick_query,
      time_recent_ranges: context.time_recent_ranges,
      query: context.query
    }
  end

  defp selected_replay_run(replay_runs, replay_run_id)
       when is_list(replay_runs) and is_binary(replay_run_id) do
    Enum.find(replay_runs, &(replay_run_value(&1, :replay_run_id) == replay_run_id))
  end

  defp selected_replay_run(_replay_runs, _replay_run_id), do: nil

  defp replay_run_value(replay_run, field) when is_map(replay_run) do
    Map.get(replay_run, field) || Map.get(replay_run, Atom.to_string(field))
  end
end
