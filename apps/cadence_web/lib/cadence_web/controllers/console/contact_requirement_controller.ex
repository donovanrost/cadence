defmodule CadenceWeb.Console.ContactRequirementController do
  @moduledoc """
  Console one-off contact requirements (BACKLOG §8 8g; contract scheduling.md §Requirements):
  list, show, the form schema, create and new version.
  """
  use CadenceWeb, :controller

  alias Cadence.Control.PlanningRequirements
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  # todo(authz): reads are open to the mission's console members (the plan reads are too);
  # writes are authorized by ContactRequirements (operate_mission). Cedar should decide both.
  def schema(conn, _params), do: ok(conn, PlanningRequirements.schema())

  def index(conn, params) do
    case PlanningRequirements.list(org_id(conn), mission_id(conn), params) do
      {:ok, page} -> ok(conn, page)
      {:error, reason} -> error(conn, reason)
    end
  end

  def by_template(conn, params) do
    case PlanningRequirements.by_template(org_id(conn), mission_id(conn), params) do
      {:ok, data} -> ok(conn, data)
      {:error, reason} -> error(conn, reason)
    end
  end

  def show(conn, %{"requirement_id" => id}) do
    case PlanningRequirements.get(org_id(conn), mission_id(conn), id) do
      {:ok, requirement} -> ok(conn, requirement)
      {:error, reason} -> error(conn, reason)
    end
  end

  def create(conn, params), do: save(conn, nil, params)
  def update(conn, %{"requirement_id" => id} = params), do: save(conn, id, params)

  def close(conn, %{"requirement_id" => id} = params), do: finish(conn, id, :close, params)
  def cancel(conn, %{"requirement_id" => id} = params), do: finish(conn, id, :cancel, params)

  defp finish(conn, id, action, params) do
    scope = conn.assigns.current_scope

    case PlanningRequirements.end_requirement(scope, mission_id(conn), id, action, params) do
      {:ok, result} -> ok(conn, result)
      {:error, reason} -> error(conn, reason)
    end
  end

  defp save(conn, id, params) do
    case PlanningRequirements.save(conn.assigns.current_scope, mission_id(conn), id, params) do
      {:ok, result} -> conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp ok(conn, data), do: json(conn, %{data: ConfigJSON.encode(data)})

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, reason) when reason in [:forbidden, :scope_mismatch],
    do: Problem.respond(conn, :forbidden)

  defp error(conn, {:duplicate_operation, id}),
    do: Problem.respond(conn, :duplicate_operation, %{requirement_id: id})

  defp error(conn, {:version_conflict, current}),
    do: Problem.respond(conn, :version_conflict, %{expected_version: current})

  defp error(conn, {:requirement_not_active, details}),
    do: Problem.respond(conn, :requirement_not_active, details)

  defp error(conn, :requirement_not_found), do: Problem.respond(conn, :requirement_not_found)

  defp error(conn, reason),
    do: Problem.respond(conn, :requirement_rejected, %{reason: inspect(reason)})

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
