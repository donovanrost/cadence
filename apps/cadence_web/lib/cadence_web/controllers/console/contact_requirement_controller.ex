defmodule CadenceWeb.Console.ContactRequirementController do
  @moduledoc """
  Console one-off contact requirements (BACKLOG §8 8g; contract scheduling.md §Requirements):
  list, show, the form schema, create and new version.
  """
  use CadenceWeb, :controller

  alias Cadence.ContactPlanning.ContactPlans
  alias Cadence.Control.{PlanningPolicy, PlanningRequirements}
  alias Cadence.Reads.ContactPlanOverview
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  # todo(authz): reads are open to the mission's console members (the plan reads are too);
  # writes are authorized by ContactRequirements (operate_mission). Cedar should decide both.
  # #1160 row 4: the form's schema and one requirement carry `planning.requirement.edit`, from the
  # check the writes make (`PlanningPolicy.permissions/2`), so New and Edit, Close, Cancel follow it.
  def schema(conn, _params),
    do:
      ok(
        conn,
        Map.put(PlanningRequirements.schema(), :permissions, requirement_permissions(conn))
      )

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
      {:ok, requirement} ->
        requirement
        |> Map.put(:held_by, held_by(conn, id))
        |> Map.put(:permissions, requirement_permissions(conn))
        |> then(&ok(conn, &1))

      {:error, reason} ->
        error(conn, reason)
    end
  end

  # ux P4 (fe-setup): the plan past draft that holds this requirement ('Open plan R41' instead of
  # 'Plan <day>'), the most recently changed one if several do; null when none.
  defp held_by(conn, requirement_id) do
    org = org_id(conn)
    mission = mission_id(conn)

    case ContactPlans.requirement_uptake(org, mission, [requirement_id]) do
      %{^requirement_id => [_ | _] = plan_ids} ->
        plan_ids
        |> Enum.flat_map(&plan(org, mission, &1))
        |> Enum.max_by(&plan_order/1, fn -> nil end)
        |> holder(org, mission)

      _none ->
        nil
    end
  end

  defp holder(nil, _org, _mission), do: nil

  # day: the plan's UTC day as the plans list files it (its first pass), since the console opens
  # a plan through its day (fe-setup). null when the plan has no passes.
  defp holder(plan, org, mission) do
    day =
      case ContactPlanOverview.plan(org, mission, plan.contact_plan_id) do
        {:ok, %{window: %{from: %DateTime{} = from}}} -> DateTime.to_date(from)
        _none -> nil
      end

    %{
      plan_id: plan.contact_plan_id,
      revision: plan.current_version,
      state: plan.lifecycle_state,
      day: day
    }
  end

  defp plan(org, mission, plan_id) do
    case ContactPlans.fetch(org, mission, plan_id) do
      {:ok, plan, _version} -> [plan]
      _gone -> []
    end
  end

  defp plan_order(plan),
    do:
      {DateTime.to_unix(plan.updated_at || ~U[1970-01-01 00:00:00Z], :microsecond),
       plan.contact_plan_id}

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

  defp requirement_permissions(conn) do
    conn.assigns.current_scope
    |> PlanningPolicy.permissions(mission_id(conn))
    |> Enum.filter(&(&1 == "planning.requirement.edit"))
  end

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
