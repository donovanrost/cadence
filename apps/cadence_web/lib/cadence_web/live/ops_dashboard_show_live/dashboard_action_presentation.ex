defmodule CadenceWeb.OpsDashboardShowLive.DashboardActionPresentation do
  @moduledoc false

  alias Cadence.Dashboards.DashboardAction

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  def for_inspector(inspector, mission_id, rendered_source, dashboard_document)
      when is_map(inspector) do
    inspector
    |> Map.get(:actions, [])
    |> hydrate_many(mission_id, rendered_source, dashboard_document)
    |> Enum.uniq_by(& &1.action_id)
  end

  def for_inspector(_inspector, _mission_id, _rendered_source, _dashboard_document), do: []

  def visible(actions) when is_list(actions), do: Enum.filter(actions, &routed?/1)
  def visible(_actions), do: []

  def icon(%DashboardAction{target: :telemetry_explore}), do: "hero-chart-bar-square"
  def icon(%DashboardAction{target: :source_inventory}), do: "hero-circle-stack"
  def icon(%DashboardAction{target: :routing_rule}), do: "hero-signal"
  def icon(%DashboardAction{}), do: "hero-arrow-top-right-on-square"

  def hydrate_many(actions, mission_id, rendered_source, dashboard_document)
      when is_list(actions) do
    actions
    |> Enum.map(&hydrate(&1, mission_id, rendered_source, dashboard_document))
    |> Enum.reject(&is_nil/1)
  end

  def hydrate_many(_actions, _mission_id, _rendered_source, _dashboard_document), do: []

  def routed?(%DashboardAction{route: route}) when is_binary(route) and route != "", do: true
  def routed?(%DashboardAction{}), do: false

  defp hydrate(
         %DashboardAction{target: :telemetry_explore, kind: :invoke} = action,
         mission_id,
         rendered_source,
         dashboard_document
       ) do
    query =
      action.query
      |> maybe_put_dashboard_source(dashboard_document)
      |> compact_query()

    %DashboardAction{
      action
      | action_id: telemetry_panel_action_id(action, rendered_source),
        kind: :navigate,
        route: ~p"/missions/#{mission_id}/ops/explore?#{query}",
        query: query,
        source: rendered_source || action.source
    }
  end

  defp hydrate(
         %DashboardAction{target: target, kind: :invoke} = action,
         mission_id,
         rendered_source,
         dashboard_document
       )
       when target in [:source_health, :source_inventory] do
    query =
      action.query
      |> maybe_put_dashboard_source(dashboard_document)
      |> compact_query()

    %DashboardAction{
      action
      | action_id: source_panel_action_id(action, rendered_source),
        kind: :navigate,
        route: ~p"/missions/#{mission_id}/ops/data-sources?#{query}",
        query: query,
        source: rendered_source || action.source
    }
  end

  defp hydrate(
         %DashboardAction{target: :routing_rule, kind: :invoke} = action,
         mission_id,
         rendered_source,
         _dashboard_document
       ) do
    routing_rule_id = Map.get(action.query, "routing_rule_id")

    if is_binary(routing_rule_id) and routing_rule_id != "" do
      %DashboardAction{
        action
        | kind: :navigate,
          route: ~p"/missions/#{mission_id}/comms/routing/#{routing_rule_id}",
          source: rendered_source || action.source
      }
    end
  end

  defp hydrate(
         %DashboardAction{} = action,
         _mission_id,
         rendered_source,
         _dashboard_document
       ) do
    %DashboardAction{action | source: rendered_source || action.source}
  end

  defp hydrate(_action, _mission_id, _rendered_source, _dashboard_document), do: nil

  defp telemetry_panel_action_id(_action, :data_link_panel), do: "dashboard-data-link-explore"
  defp telemetry_panel_action_id(_action, :evidence_panel), do: "dashboard-evidence-explore"
  defp telemetry_panel_action_id(%DashboardAction{action_id: action_id}, _source), do: action_id

  defp source_panel_action_id(%DashboardAction{target: :source_inventory}, :evidence_panel),
    do: "dashboard-evidence-source-inventory"

  defp source_panel_action_id(%DashboardAction{target: :source_health}, :evidence_panel),
    do: "dashboard-evidence-source-health"

  defp source_panel_action_id(%DashboardAction{action_id: action_id}, _source), do: action_id

  defp compact_query(query) when is_map(query) do
    query
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp compact_query(_query), do: %{}

  defp maybe_put_dashboard_source(query, %{dashboard_id: dashboard_id})
       when is_map(query) and is_binary(dashboard_id) and dashboard_id != "" do
    Map.put_new(query, "source_dashboard_id", dashboard_id)
  end

  defp maybe_put_dashboard_source(query, _dashboard_document), do: query
end
