defmodule CadenceWeb.Console.SpacecraftDetailController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id/spacecraft/:spacecraft_id`. Contract: docs/apogee/api/setup.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.SpacecraftDetail
  alias CadenceWeb.Console.Problem

  def show(conn, %{"spacecraft_id" => spacecraft_id}) do
    case SpacecraftDetail.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           spacecraft_id
         ) do
      {:ok, detail} -> json(conn, %{data: Map.put(detail, :configuration, nil)})
      {:error, :spacecraft_not_found} -> Problem.respond(conn, :spacecraft_not_found)
    end
  end
end
