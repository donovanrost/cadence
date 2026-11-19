defmodule CadenceWeb.Console.ContactGrantController do
  @moduledoc """
  §11 L3 automation grants (contract scheduling.md §Automation grants): the Policy tab's Grants
  panel. Read for mission operators; issue and revoke for organization admins.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.PlanningGrants
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, _params),
    do: reply(conn, :ok, PlanningGrants.load(scope(conn), mission_id(conn)))

  def create(conn, params),
    do: reply(conn, :created, PlanningGrants.issue(scope(conn), mission_id(conn), params), :grant)

  def revoke(conn, %{"grant_id" => id} = params),
    do: reply(conn, :ok, PlanningGrants.revoke(scope(conn), mission_id(conn), id, params), :grant)

  defp reply(conn, status, result, wrap \\ nil)

  defp reply(conn, status, {:ok, data}, wrap) do
    data = if wrap, do: %{wrap => data}, else: data
    conn |> put_status(status) |> json(%{data: ConfigJSON.encode(data)})
  end

  defp reply(conn, _status, {:error, reason}, _wrap), do: error(conn, reason)

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:policy_changed, active}),
    do: Problem.respond(conn, :policy_changed, %{active_version: active})

  defp error(conn, :policy_changed),
    do: Problem.respond(conn, :policy_changed, %{active_version: nil})

  defp error(conn, reason) when reason in [:grant_changed, :grant_not_found],
    do: Problem.respond(conn, reason)

  defp error(conn, reason)
       when reason in [:forbidden, :scope_mismatch, :authenticated_user_required],
       do: Problem.respond(conn, :forbidden)

  defp error(conn, reason), do: Problem.respond(conn, :invalid_params, %{grant: inspect(reason)})

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
