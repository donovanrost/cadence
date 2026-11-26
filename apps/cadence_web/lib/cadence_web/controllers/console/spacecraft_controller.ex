defmodule CadenceWeb.Console.SpacecraftController do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/spacecraft` and `…/spacecraft/names` (#847). Contract:
  docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.{SpacecraftDirectory, SpacecraftNames}
  alias CadenceWeb.Console.Problem

  def index(conn, _params) do
    directory =
      SpacecraftDirectory.index(
        conn.assigns.current_scope.organization_id,
        conn.assigns.current_mission.mission_id
      )

    json(conn, %{data: directory})
  end

  @doc """
  Spacecraft names and SCIDs (#847): `?ids=a,b` for at most 100 known craft, or the whole
  mission a page at a time (`?cursor=`, `?limit=` up to 500), sorted by name then id. Both are
  `{data: {names: [{id, name, scid}]}, meta: {next_cursor}}`.
  """
  def names(conn, %{"ids" => ids}) when is_binary(ids) do
    case SpacecraftNames.by_ids(org(conn), mission(conn), String.split(ids, ",", trim: true)) do
      {:ok, names} -> json(conn, %{data: %{names: names}, meta: %{next_cursor: nil}})
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  def names(conn, params) do
    case SpacecraftNames.page(org(conn), mission(conn), params["cursor"], limit(params["limit"])) do
      {:ok, page} ->
        json(conn, %{data: %{names: page.names}, meta: %{next_cursor: page.next_cursor}})

      {:error, :invalid_cursor} ->
        Problem.respond(conn, :invalid_params, %{cursor: "is not a valid cursor"})
    end
  end

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp limit(_value), do: nil

  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
