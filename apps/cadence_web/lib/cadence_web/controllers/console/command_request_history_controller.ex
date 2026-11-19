defmodule CadenceWeb.Console.CommandRequestHistoryController do
  @moduledoc """
  U68 R3/R4: `GET /command-requests/:id/history`, one member's release attempts and verifiers
  with their matched evidence (`?attempts_after=` / `?verifiers_after=` page on). Contract:
  docs/apogee/api/commanding.md § Request history.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.CommandRequestHistory
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, %{"command_request_id" => id} = params) do
    case CommandRequestHistory.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           id,
           attempts_after: cursor(params["attempts_after"]),
           verifiers_after: cursor(params["verifiers_after"])
         ) do
      {:ok, history} -> json(conn, %{data: ConfigJSON.encode(history)})
      {:error, :command_request_not_found} -> Problem.respond(conn, :command_request_not_found)
      {:error, :invalid_cursor} -> Problem.respond(conn, :invalid_params, %{field: "cursor"})
    end
  end

  defp cursor(value) when is_binary(value) and value != "", do: value
  defp cursor(_value), do: nil
end
