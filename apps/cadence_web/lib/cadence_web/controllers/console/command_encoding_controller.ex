defmodule CadenceWeb.Console.CommandEncodingController do
  @moduledoc """
  Per-request context for Approve: M24 encode preview (`GET /command-requests/:id/encoding`,
  the payload release would send, from the request's own model revision) and the A1 brief
  (`GET /command-requests/:id/brief`, arguments with current values, prior requests).
  Contract: docs/apogee/api/commanding.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.{CommandBrief, CommandEncodingPreview}
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, %{"command_request_id" => id}) do
    case CommandEncodingPreview.preview(
           conn.assigns.current_scope,
           conn.assigns.current_mission.mission_id,
           id
         ) do
      {:ok, preview} ->
        json(conn, %{data: ConfigJSON.encode(preview)})

      {:error, {:encode_unavailable, reason, detail}} ->
        Problem.respond(conn, :encode_unavailable, %{reason: reason, detail: detail})

      {:error, :command_request_not_found} ->
        Problem.respond(conn, :command_request_not_found)

      {:error, :forbidden} ->
        Problem.respond(conn, :forbidden)
    end
  end

  def brief(conn, %{"command_request_id" => id}) do
    case CommandBrief.brief(
           conn.assigns.current_scope,
           conn.assigns.current_mission.mission_id,
           id
         ) do
      {:ok, brief} -> json(conn, %{data: ConfigJSON.encode(brief)})
      {:error, :command_request_not_found} -> Problem.respond(conn, :command_request_not_found)
      {:error, :forbidden} -> Problem.respond(conn, :forbidden)
    end
  end
end
