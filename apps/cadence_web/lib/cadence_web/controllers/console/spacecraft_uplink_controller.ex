defmodule CadenceWeb.Console.SpacecraftUplinkController do
  @moduledoc """
  `GET …/spacecraft/:spacecraft_id/uplink`: Investigate's Uplink tab. Contract:
  docs/apogee/api/ops.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.SpacecraftUplink
  alias CadenceWeb.Console.Problem

  def show(conn, %{"spacecraft_id" => spacecraft_id}) do
    case SpacecraftUplink.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           spacecraft_id
         ) do
      {:ok, uplink} -> json(conn, %{data: uplink})
      {:error, :spacecraft_not_found} -> Problem.respond(conn, :spacecraft_not_found)
    end
  end
end
