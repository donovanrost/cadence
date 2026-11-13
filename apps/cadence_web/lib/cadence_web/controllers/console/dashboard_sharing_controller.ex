defmodule CadenceWeb.Console.DashboardSharingController do
  @moduledoc """
  D14-D16 (owner: api; fe-setup's docs/apogee/plans/dashboards-settings.md, contract
  dashboards.md §D14-D16): a dashboard's settings, its General save, and its shares and snapshots.
  Under `…/dashboards/:dashboard_id`. Author only.
  """

  use CadenceWeb, :controller

  alias Cadence.Dashboards.StatelessAuthoring
  alias CadenceWeb.Console.{ConfigJSON, DashboardSettings, Problem}

  def show(conn, %{"dashboard_id" => id} = params),
    do: reply(conn, id, DashboardSettings.load(scope(conn), mission(conn), id, params))

  def update(conn, %{"dashboard_id" => id} = params),
    do: reply(conn, id, DashboardSettings.save(scope(conn), mission(conn), id, params))

  def create_share(conn, %{"dashboard_id" => id} = params),
    do: created(conn, id, DashboardSettings.create_share(scope(conn), mission(conn), id, params))

  def revoke_share(conn, %{"dashboard_id" => id, "share_id" => share_id}) do
    case DashboardSettings.revoke_share(scope(conn), mission(conn), id, share_id) do
      {:error, :conflict} -> Problem.respond(conn, :share_not_active)
      result -> reply(conn, id, result)
    end
  end

  def create_snapshot(conn, %{"dashboard_id" => id} = params),
    do:
      created(conn, id, DashboardSettings.create_snapshot(scope(conn), mission(conn), id, params))

  def delete_snapshot(conn, %{"dashboard_id" => id, "snapshot_id" => snapshot_id}) do
    case DashboardSettings.delete_snapshot(scope(conn), mission(conn), snapshot_id) do
      :ok -> send_resp(conn, :no_content, "")
      error -> reply(conn, id, error)
    end
  end

  defp created(conn, _id, {:ok, data}),
    do: conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(data)})

  defp created(conn, id, error), do: reply(conn, id, error)

  defp reply(conn, _id, {:ok, data}), do: json(conn, %{data: ConfigJSON.encode(data)})

  defp reply(conn, _id, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp reply(conn, _id, {:error, {:invalid, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp reply(conn, _id, {:error, :invalid_input}),
    do: Problem.respond(conn, :invalid_params, %{request: "isn't valid for this dashboard"})

  defp reply(conn, _id, {:error, :forbidden}), do: Problem.respond(conn, :forbidden)

  defp reply(conn, id, {:error, :conflict}),
    do: Problem.respond(conn, :version_conflict, conflict(conn, id))

  defp reply(conn, _id, {:error, :unknown}), do: Problem.respond(conn, :dashboard_unavailable)
  defp reply(conn, _id, {:error, _missing}), do: Problem.respond(conn, :not_found)

  # The same details as D9's conflict: who saved the version now current, and when.
  defp conflict(conn, id) do
    case StatelessAuthoring.versions(scope(conn), mission(conn), id) do
      {:ok, [newest | _]} ->
        %{
          current_version: newest.version,
          saved_by:
            newest.created_by &&
              %{kind: "user", id: newest.created_by.id, name: newest.created_by.name},
          saved_at: newest.created_at
        }

      _none ->
        %{current_version: nil, saved_by: nil, saved_at: nil}
    end
  end

  defp scope(conn), do: conn.assigns.current_scope
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
