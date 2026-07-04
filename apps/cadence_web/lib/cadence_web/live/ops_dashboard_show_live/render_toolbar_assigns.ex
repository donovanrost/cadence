defmodule CadenceWeb.OpsDashboardShowLive.RenderToolbarAssigns do
  @moduledoc false

  alias Cadence.Dashboards.ComparisonReviewQueue
  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetAssigns

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec toolbar_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def toolbar_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)
    render_items = Map.get(assigns, :dashboard_render_items, [])

    %{
      dashboard_document: Map.get(assigns, :dashboard_document),
      dashboard_lifecycle_status: Map.get(assigns, :dashboard_lifecycle_status),
      dashboard_lifecycle_events: Map.get(assigns, :dashboard_lifecycle_events, []),
      dashboard_comparison_review_queue: comparison_review_queue(assigns),
      dashboard_publish_validation: Map.get(assigns, :dashboard_publish_validation),
      dashboard_publish_validation_freshness:
        Map.get(assigns, :dashboard_publish_validation_freshness),
      edit_mode?: Map.get(assigns, :edit_mode?, false),
      show_context?: RenderWidgetAssigns.context_widgets?(render_items),
      current_mission: Map.get(assigns, :current_mission),
      spacecraft: Map.get(assigns, :spacecraft, []),
      source_endpoints: Map.get(assigns, :source_endpoints, []),
      transports: Map.get(assigns, :transports, []),
      ground_stations: Map.get(assigns, :ground_stations, []),
      link_assignments: Map.get(assigns, :link_assignments, []),
      scheduled_contacts: Map.get(assigns, :scheduled_contacts, []),
      realized_contacts: Map.get(assigns, :realized_contacts, []),
      context_spacecraft_id: Map.get(assigns, :context_spacecraft_id),
      context_scope_kind: Map.get(assigns, :context_scope_kind),
      context_scope_id: Map.get(assigns, :context_scope_id),
      context_scope_ids: Map.get(assigns, :context_scope_ids, []),
      time_mode: Map.get(assigns, :dashboard_time_mode),
      time_axis: Map.get(assigns, :dashboard_time_axis),
      time_from: Map.get(assigns, :dashboard_time_from),
      time_to: Map.get(assigns, :dashboard_time_to),
      replay_run_id: Map.get(assigns, :dashboard_replay_run_id),
      time_validation: Map.get(assigns, :dashboard_time_validation),
      data_realm: Map.get(assigns, :dashboard_data_realm),
      data_realms: Map.get(assigns, :dashboard_data_realms, []),
      data_view: Map.get(assigns, :dashboard_data_view),
      compare_data_view: Map.get(assigns, :dashboard_compare_data_view),
      data_source_id: Map.get(assigns, :dashboard_data_source_id),
      source_binding_id: Map.get(assigns, :dashboard_source_binding_id),
      data_bindings: Map.get(assigns, :dashboard_data_bindings, []),
      replay_runs: Map.get(assigns, :dashboard_replay_runs, []),
      limit_mode: Map.get(assigns, :dashboard_limit_mode),
      limit_mode_fallback: Map.get(assigns, :dashboard_limit_mode_fallback),
      selected_data_ref: Map.get(assigns, :dashboard_selected_data_ref),
      query: Map.get(assigns, :context_query, "")
    }
  end

  defp comparison_review_queue(%{
         dashboard_comparison_review_queue: %{count: count, requests: requests} = summary
       })
       when is_integer(count) and is_list(requests),
       do: summary

  defp comparison_review_queue(_assigns), do: ComparisonReviewQueue.open_summary([])
end
