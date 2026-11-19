defmodule CadenceWeb.Console.ContactPlanningController do
  @moduledoc """
  Contact planning setup (CP2 policy) under
  `/api/console/v1/missions/:mission_id/contact-planning`. Contract:
  docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.ContactPlanning.FleetPlanningPolicySchema
  alias Cadence.Control.PlanningPolicy
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def policy(conn, _params) do
    data =
      conn.assigns.current_scope.organization_id
      |> PlanningPolicy.get(conn.assigns.current_mission.mission_id)
      |> Map.put(:permissions, PlanningPolicy.permissions(conn.assigns.current_scope))

    json(conn, %{data: ConfigJSON.encode(data)})
  end

  def save_policy(conn, %{"document" => document} = params) when is_map(document) do
    expected = if is_integer(params["expected_version"]), do: params["expected_version"]

    case PlanningPolicy.save(
           conn.assigns.current_scope,
           conn.assigns.current_mission.mission_id,
           document,
           expected,
           params["reason"]
         ) do
      {:ok, result} -> conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def save_policy(conn, _params),
    do: Problem.respond(conn, :invalid_params, %{document: "is required (object)"})

  def decide_policy(conn, %{"version" => version} = params) do
    with {:ok, number} <- positive(version),
         {:ok, decision} <- decision(params["decision"]),
         {:ok, comment} <- comment(params["comment"]),
         {:ok, result} <-
           PlanningPolicy.decide(
             conn.assigns.current_scope,
             conn.assigns.current_mission.mission_id,
             number,
             decision,
             comment
           ) do
      json(conn, %{data: ConfigJSON.encode(result)})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp positive(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> {:ok, n}
      _invalid -> {:error, {:invalid_params, %{version: "must be a positive integer"}}}
    end
  end

  defp decision("approve"), do: {:ok, :approve}
  defp decision("reject"), do: {:ok, :reject}
  defp decision(_other), do: {:error, {:invalid_params, %{decision: "must be approve or reject"}}}

  defp comment(value) when is_binary(value) and byte_size(value) > 0, do: {:ok, value}
  defp comment(_value), do: {:error, {:invalid_params, %{comment: "is required"}}}

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:version_conflict, current}),
    do: Problem.respond(conn, :version_conflict, %{expected_version: current})

  defp error(conn, {:invalid_fleet_planning_policy_field, section, key}),
    do: Problem.respond(conn, :invalid_params, %{field_path(section, key) => "is invalid"})

  defp error(conn, {:unknown_fleet_planning_policy_field, section, key}),
    do: Problem.respond(conn, :invalid_params, %{"#{section}.#{key}" => "is not a policy field"})

  defp error(conn, {:invalid_fleet_planning_policy_section, section}),
    do: Problem.respond(conn, :invalid_params, %{"#{section}" => "must be an object"})

  defp error(conn, :reviewer_is_author), do: Problem.respond(conn, :reviewer_is_author)
  defp error(conn, :forbidden), do: Problem.respond(conn, :forbidden)
  defp error(conn, :scope_mismatch), do: Problem.respond(conn, :forbidden)

  defp error(conn, reason)
       when reason in [:fleet_planning_policy_not_found, :fleet_planning_policy_version_not_found],
       do: Problem.respond(conn, :policy_not_found)

  defp error(conn, reason) when is_atom(reason),
    do: Problem.respond(conn, :policy_rejected, %{reason: Atom.to_string(reason)})

  defp error(conn, reason),
    do: Problem.respond(conn, :policy_rejected, %{reason: inspect(reason)})

  # The domain reports some bounds with a generic section; find the group by field name.
  defp field_path(section, key) do
    key = to_string(key)
    groups = Enum.map(FleetPlanningPolicySchema.groups(), &elem(&1, 0))

    if to_string(section) in groups do
      "#{section}.#{key}"
    else
      case Enum.find(FleetPlanningPolicySchema.fields(), &String.ends_with?(&1.path, "." <> key)) do
        %{path: path} -> path
        nil -> key
      end
    end
  end
end
