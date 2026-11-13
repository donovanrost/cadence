defmodule CadenceWeb.Console.DashboardSharedViewController do
  @moduledoc """
  D20 (owner: api; dashboards' docs/apogee/plans/dashboards-slice6.md, contract dashboards.md
  §D20): `GET …/dashboard-shares/:share_id` and `GET …/dashboard-snapshots/:snapshot_id`.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.Console.{ConfigJSON, DashboardSettings, DashboardSharedViews, Problem}

  def share(conn, %{"share_id" => id} = params), do: show(conn, :share, id, params)
  def snapshot(conn, %{"snapshot_id" => id} = params), do: show(conn, :snapshot, id, params)

  defp show(conn, kind, id, params) do
    scope = conn.assigns.current_scope
    mission = conn.assigns.current_mission.mission_id
    base = DashboardSettings.base_url(scope.organization_id, mission)

    case DashboardSharedViews.load(scope, mission, kind, id, base, params) do
      {:ok, view} ->
        json(conn, %{data: ConfigJSON.encode(view)})

      {:error, {:invalid_params, details}} ->
        Problem.respond(conn, :invalid_params, details)

      # The message is the sentence the page shows (like share_revoked), with the facts too.
      {:error, {:gone, code, message, details}} ->
        conn
        |> put_status(404)
        |> json(Problem.body(Atom.to_string(code), message, ConfigJSON.encode(details)))

      {:error, :unavailable} ->
        Problem.respond(conn, :dashboard_unavailable)

      {:error, _not_found} ->
        Problem.respond(conn, :not_found)
    end
  end
end
