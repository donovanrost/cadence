defmodule CadenceWeb.Console.CommandEncodingController do
  @moduledoc """
  M24 encode preview (Approve A3): `GET /command-requests/:id/encoding`, the command payload
  release would send, from the request's own model revision. Contract:
  docs/apogee/api/commanding.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.CommandEncodingPreview
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, %{"command_request_id" => id}) do
    case CommandEncodingPreview.preview(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           id
         ) do
      {:ok, preview} ->
        json(conn, %{data: ConfigJSON.encode(preview)})

      {:error, {:encode_unavailable, reason, detail}} ->
        Problem.respond(conn, :encode_unavailable, %{reason: reason, detail: detail})

      {:error, :command_request_not_found} ->
        Problem.respond(conn, :command_request_not_found)
    end
  end
end
