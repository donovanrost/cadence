defmodule CadenceWeb.Console.CommandDraftController do
  @moduledoc """
  Compose's current draft for the caller and mission: `GET`, `PUT` and `DELETE /command-draft`.
  Contract: docs/apogee/api/commanding.md §Compose draft.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.Commanding.CommandDrafts
  alias CadenceWeb.Console.Problem

  # 200 {draft: body | null}: having no draft isn't an error (qa a11y #6: a 404 logged a console
  # error on every Commands, Compose and Request load).
  def show(conn, _params) do
    case CommandDrafts.fetch(conn.assigns.current_scope, mission(conn)) do
      {:ok, draft} -> json(conn, %{data: %{draft: draft}})
      {:error, :command_draft_not_found} -> json(conn, %{data: %{draft: nil}})
      error -> problem(conn, error)
    end
  end

  def update(conn, params) do
    case CommandDrafts.put(
           conn.assigns.current_scope,
           mission(conn),
           params["document"],
           params["expected_revision"]
         ) do
      {:ok, saved} -> json(conn, %{data: saved})
      error -> problem(conn, error)
    end
  end

  def delete(conn, _params) do
    case CommandDrafts.delete(conn.assigns.current_scope, mission(conn)) do
      :ok -> send_resp(conn, :no_content, "")
      error -> problem(conn, error)
    end
  end

  defp problem(conn, {:error, :command_draft_not_found}),
    do: Problem.respond(conn, :command_draft_not_found)

  defp problem(conn, {:error, {:command_draft_changed, current}}),
    do: Problem.respond(conn, :command_draft_changed, current)

  defp problem(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp problem(conn, {:error, :unavailable}), do: Problem.respond(conn, :forbidden)
  defp problem(conn, _error), do: Problem.respond(conn, :commanding_unavailable)

  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
