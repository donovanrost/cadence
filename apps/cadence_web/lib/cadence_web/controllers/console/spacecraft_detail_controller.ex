defmodule CadenceWeb.Console.SpacecraftDetailController do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/spacecraft/:spacecraft_id`, and one extra route's
  document for its editor (`…/routes/:route_id`, ux U79). Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.{SpacecraftDetail, SpacecraftRouteDocument, SpacecraftSwitches}
  alias CadenceWeb.Console.Problem

  def show(conn, %{"spacecraft_id" => spacecraft_id}) do
    case SpacecraftDetail.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           spacecraft_id
         ) do
      {:ok, detail} ->
        switches = SpacecraftSwitches.running(conn.assigns.current_mission, spacecraft_id)
        json(conn, %{data: detail |> Map.put(:configuration, nil) |> Map.merge(switches)})

      {:error, :spacecraft_not_found} ->
        Problem.respond(conn, :spacecraft_not_found)
    end
  end

  def route(conn, %{"spacecraft_id" => spacecraft_id, "route_id" => route_id}) do
    case SpacecraftRouteDocument.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           spacecraft_id,
           route_id
         ) do
      {:ok, route} -> json(conn, %{data: route})
      {:error, :spacecraft_route_not_found} -> Problem.respond(conn, :spacecraft_route_not_found)
    end
  end
end
