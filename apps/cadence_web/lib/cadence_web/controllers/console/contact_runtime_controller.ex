defmodule CadenceWeb.Console.ContactRuntimeController do
  @moduledoc "Live realized-contact and path runtime snapshots."

  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias Cadence.Runtime
  alias CadenceWeb.Console.{ContactRuntimeJSON, Problem}

  def runtime(conn, %{"realized_contact_id" => contact_id}) do
    mission_id = conn.assigns.current_mission.mission_id

    with :ok <- authorize(conn, mission_id),
         {:ok, snapshot} <- Runtime.realized_contact_snapshot(mission_id, contact_id) do
      json(conn, %{data: ContactRuntimeJSON.realized_contact_runtime_snapshot(snapshot)})
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  def path_runtime(conn, %{"realized_contact_id" => contact_id, "path_id" => path_id}) do
    mission_id = conn.assigns.current_mission.mission_id

    with :ok <- authorize(conn, mission_id),
         {:ok, snapshot} <- Runtime.path_runtime_snapshot(mission_id, contact_id, path_id) do
      json(conn, %{data: ContactRuntimeJSON.path_runtime_snapshot(snapshot)})
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp authorize(conn, mission_id) do
    scope = conn.assigns.current_scope

    Policy.authorize(scope, :manage_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp failure(conn, {:path_runtime_not_running, _path_id}),
    do: Problem.respond(conn, :path_runtime_not_running)

  defp failure(conn, reason) when is_atom(reason), do: Problem.respond(conn, reason)
  defp failure(conn, _reason), do: Problem.respond(conn, :runtime_snapshot_unavailable)
end
