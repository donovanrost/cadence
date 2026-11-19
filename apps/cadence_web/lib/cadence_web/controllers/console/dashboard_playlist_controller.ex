defmodule CadenceWeb.Console.DashboardPlaylistController do
  @moduledoc """
  D23/D24 (owner: api; dashboards' docs/apogee/plans/dashboards-slice6.md, contract
  dashboards.md §D23-D24): `…/dashboard-playlists[/:playlist_id]`.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.Console.{ConfigJSON, DashboardPlaylists, Problem}

  def index(conn, params),
    do: reply(conn, DashboardPlaylists.list(scope(conn), mission(conn), params))

  def show(conn, %{"playlist_id" => id}),
    do: reply(conn, DashboardPlaylists.get(scope(conn), mission(conn), id))

  def create(conn, params) do
    case DashboardPlaylists.create(scope(conn), mission(conn), params) do
      {:ok, data} -> conn |> put_status(:created) |> json(%{data: data})
      error -> reply(conn, error)
    end
  end

  def update(conn, %{"playlist_id" => id} = params),
    do: reply(conn, DashboardPlaylists.update(scope(conn), mission(conn), id, params))

  def delete(conn, %{"playlist_id" => id}) do
    case DashboardPlaylists.delete(scope(conn), mission(conn), id) do
      :ok -> send_resp(conn, :no_content, "")
      error -> reply(conn, error)
    end
  end

  defp reply(conn, {:ok, data}), do: json(conn, %{data: ConfigJSON.encode(data)})

  defp reply(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp reply(conn, {:error, {:version_conflict, details}}),
    do: Problem.respond(conn, :version_conflict, ConfigJSON.encode(details))

  defp reply(conn, {:error, :forbidden}), do: Problem.respond(conn, :forbidden)
  defp reply(conn, {:error, :playlist_not_found}), do: Problem.respond(conn, :playlist_not_found)
  defp reply(conn, {:error, _unknown}), do: Problem.respond(conn, :dashboard_unavailable)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
