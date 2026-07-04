defmodule CadenceWeb.OpsDashboardShowLive.Navigation do
  @moduledoc false

  import Phoenix.LiveView, only: [push_patch: 2]

  alias CadenceWeb.OpsDashboardShowLive.RouteQuery

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  def current_query(socket_or_assigns), do: RouteQuery.current(socket_or_assigns)

  def show_path(socket_or_assigns, overrides \\ %{}) do
    assigns = dashboard_assigns(socket_or_assigns)
    mission_id = assigns.current_mission.mission_id
    dashboard_id = assigns.dashboard_document.dashboard_id

    query = RouteQuery.current_with(socket_or_assigns, overrides)

    case query do
      query when map_size(query) == 0 ->
        ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}"

      query ->
        ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{query}"
    end
  end

  def patch(socket, overrides, opts \\ []) do
    case Keyword.get(opts, :patch) do
      callback when is_function(callback, 2) ->
        callback.(socket, overrides)

      _missing ->
        push_patch(socket, to: show_path(socket, overrides))
    end
  end

  defp dashboard_assigns(%{assigns: assigns}), do: assigns
  defp dashboard_assigns(assigns) when is_map(assigns), do: assigns
end
