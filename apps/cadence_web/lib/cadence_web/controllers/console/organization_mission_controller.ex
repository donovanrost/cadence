defmodule CadenceWeb.Console.OrganizationMissionController do
  @moduledoc """
  §11 L4 console mission create (contract setup.md §Missions): the slug check (M1) and the
  create (M2) in the path's organization. Errors: 422 invalid_params with flat field details
  (`name`, `slug` + `suggestion`, as AD1), 403 forbidden.
  """

  use CadenceWeb, :controller

  alias Cadence.Administration.ConsoleMissions
  alias CadenceWeb.Console.Problem

  def slug(conn, %{"organization_id" => org} = params) do
    case ConsoleMissions.slug(conn.assigns.current_scope, org, params["slug"] || "") do
      {:ok, result} -> json(conn, %{data: result})
      {:error, reason} -> error(conn, reason)
    end
  end

  def create(conn, %{"organization_id" => org} = params) do
    case ConsoleMissions.create(conn.assigns.current_scope, org, Map.take(params, ~w(name slug))) do
      {:ok, mission} -> conn |> put_status(:created) |> json(%{data: %{mission: mission}})
      {:invalid, details} -> Problem.respond(conn, :invalid_params, details)
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, reason)
       when reason in [:forbidden, :scope_mismatch, :authenticated_user_required],
       do: Problem.respond(conn, :forbidden)

  defp error(conn, :organization_not_found), do: Problem.respond(conn, :organization_not_found)
  defp error(conn, _reason), do: Problem.respond(conn, :invalid_params)
end
