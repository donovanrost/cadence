defmodule CadenceWeb.OpsDashboardShowLive.DashboardPageSummaryModel do
  @moduledoc false

  alias Cadence.Dashboards.ComparisonReviewQueue
  alias CadenceWeb.OpsDashboardShowLive.ComparisonFindingDecisions
  alias CadenceWeb.OpsDashboardShowLive.ComparisonInvestigationPreset
  alias CadenceWeb.OpsDashboardShowLive.DashboardHealthRollup
  alias CadenceWeb.OpsDashboardShowLive.WidgetComparisonSummary

  @spec props(map(), [map()], binary(), map()) :: map()
  def props(assigns, widget_items, current_path, shell_context)
      when is_map(assigns) and is_list(widget_items) and is_map(shell_context) do
    dashboard_health =
      widget_items
      |> DashboardHealthRollup.rollup()
      |> DashboardHealthRollup.with_snapshot(
        dashboard_health_snapshot_context(assigns, shell_context)
      )

    comparison_rollup =
      widget_items
      |> WidgetComparisonSummary.rollup()
      |> ComparisonFindingDecisions.enrich_rollup(assigns)

    %{
      dashboard_health: dashboard_health,
      comparison_rollup: comparison_rollup,
      comparison_preset:
        ComparisonInvestigationPreset.build(assigns, current_path, comparison_rollup),
      open_review_summary: open_review_summary(assigns),
      comparison_presets: Map.get(assigns, :dashboard_investigation_presets, []),
      root_attrs:
        WidgetComparisonSummary.root_attrs(comparison_rollup)
        |> Map.merge(DashboardHealthRollup.root_attrs(dashboard_health))
    }
  end

  def props(assigns, widget_items, current_path, shell_context) when is_map(assigns) do
    props(assigns, List.wrap(widget_items), current_path, Map.new(shell_context || %{}))
  end

  defp open_review_summary(%{
         dashboard_comparison_review_queue: %{count: count, requests: requests} = summary
       })
       when is_integer(count) and is_list(requests),
       do: summary

  defp open_review_summary(_assigns), do: ComparisonReviewQueue.open_summary([])

  defp dashboard_health_snapshot_context(assigns, shell_context) do
    %{
      organization_id:
        assigns
        |> Map.get(:current_scope)
        |> map_value(:organization_id),
      mission_id:
        assigns
        |> Map.get(:current_mission)
        |> map_value(:mission_id),
      dashboard_id: Map.get(shell_context, :dashboard_id),
      realm: Map.get(assigns, :dashboard_data_realm),
      data_view: Map.get(assigns, :dashboard_data_view),
      compare_data_view: Map.get(assigns, :dashboard_compare_data_view),
      time_mode: Map.get(assigns, :dashboard_time_mode),
      time_from: Map.get(assigns, :dashboard_time_from),
      time_to: Map.get(assigns, :dashboard_time_to),
      replay_run_id: Map.get(assigns, :dashboard_replay_run_id),
      scope_kind: Map.get(assigns, :context_scope_kind),
      scope_id: Map.get(assigns, :context_scope_id),
      scope_ids: Map.get(assigns, :context_scope_ids, []),
      data_source_id: Map.get(assigns, :dashboard_data_source_id),
      source_binding_id: Map.get(assigns, :dashboard_source_binding_id),
      limit_mode: Map.get(assigns, :dashboard_limit_mode)
    }
  end

  defp map_value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp map_value(_map, _key), do: nil
end
