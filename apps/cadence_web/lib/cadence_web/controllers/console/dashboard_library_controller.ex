defmodule CadenceWeb.Console.DashboardLibraryController do
  @moduledoc """
  D21/D22 (owner: api; fe-ops' docs/apogee/plans/dashboards-library.md, contract dashboards.md
  §D21/D22): `…/dashboard-library[/:item_id[/versions]]`.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.Console.{ConfigJSON, DashboardLibrary, Problem}

  def index(conn, params),
    do: reply(conn, DashboardLibrary.list(scope(conn), mission(conn), params))

  def show(conn, %{"item_id" => id} = params),
    do: reply(conn, DashboardLibrary.get(scope(conn), mission(conn), id, params))

  def create(conn, params),
    do: created(conn, DashboardLibrary.create(scope(conn), mission(conn), params))

  def add_version(conn, %{"item_id" => id} = params),
    do: write(conn, DashboardLibrary.add_version(scope(conn), mission(conn), id, params))

  def update(conn, %{"item_id" => id} = params),
    do: write(conn, DashboardLibrary.update(scope(conn), mission(conn), id, params))

  def delete(conn, %{"item_id" => id} = params) do
    case DashboardLibrary.retire(scope(conn), mission(conn), id, params) do
      :ok -> send_resp(conn, :no_content, "")
      error -> write(conn, error)
    end
  end

  defp created(conn, {:ok, data}), do: conn |> put_status(:created) |> json(%{data: data})
  defp created(conn, error), do: write(conn, error)

  # A viewer who may read but not write: say who manages the library (fe-ops' plan).
  defp write(conn, {:error, :forbidden}) do
    conn
    |> put_status(403)
    |> json(Problem.body("forbidden", "Dashboard editors manage the library.", nil))
  end

  defp write(conn, result), do: reply(conn, result)

  defp reply(conn, {:ok, data}), do: json(conn, %{data: ConfigJSON.encode(data)})

  defp reply(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp reply(conn, {:error, {code, details}})
       when code in [:library_item_changed, :library_item_in_use],
       do: Problem.respond(conn, code, ConfigJSON.encode(details))

  defp reply(conn, {:error, :forbidden}), do: Problem.respond(conn, :forbidden)

  defp reply(conn, {:error, :library_item_not_found}),
    do: Problem.respond(conn, :library_item_not_found)

  defp reply(conn, {:error, _unknown}), do: Problem.respond(conn, :dashboard_unavailable)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
