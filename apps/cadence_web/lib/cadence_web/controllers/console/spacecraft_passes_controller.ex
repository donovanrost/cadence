defmodule CadenceWeb.Console.SpacecraftPassesController do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/spacecraft/:spacecraft_id/passes`: Investigate's
  Passes tab coverage (P1) and queued counts (P3). Contract: docs/apogee/api/ops.md §Investigate
  Passes.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.SpacecraftPasses
  alias CadenceWeb.Console.Problem

  def show(conn, %{"spacecraft_id" => spacecraft_id}) do
    case SpacecraftPasses.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           spacecraft_id
         ) do
      {:ok, passes} -> json(conn, %{data: passes})
      {:error, :spacecraft_not_found} -> Problem.respond(conn, :spacecraft_not_found)
    end
  end
end
