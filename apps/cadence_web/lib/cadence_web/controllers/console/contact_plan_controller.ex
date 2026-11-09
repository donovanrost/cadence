defmodule CadenceWeb.Console.ContactPlanController do
  @moduledoc """
  Contact plan reads for scheduling (S6 list, plan detail with demand).
  Contract: docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.ContactPlanning.ContactPlan
  alias Cadence.Reads.ContactPlanOverview
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  @states Map.new(ContactPlan.states(), &{Atom.to_string(&1), &1})

  def index(conn, params) do
    with {:ok, day} <- day(params["day"]),
         {:ok, state} <- state(params["state"]) do
      plans = ContactPlanOverview.list(org_id(conn), mission_id(conn), %{day: day, state: state})
      json(conn, %{data: ConfigJSON.encode(%{plans: plans})})
    else
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  def show(conn, %{"plan_id" => plan_id} = params) do
    with {:ok, version} <- version(params["version"]),
         {:ok, plan} <- ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id, version) do
      json(conn, %{data: ConfigJSON.encode(plan)})
    else
      {:error, :plan_not_found} -> Problem.respond(conn, :plan_not_found)
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  defp day(nil), do: {:ok, nil}

  defp day(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, %{day: "must be YYYY-MM-DD"}}
    end
  end

  defp state(nil), do: {:ok, nil}

  defp state(value) do
    case Map.fetch(@states, value) do
      {:ok, state} ->
        {:ok, state}

      :error ->
        {:error,
         %{state: "must be one of #{@states |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"}}
    end
  end

  defp version(nil), do: {:ok, nil}

  defp version(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> {:ok, n}
      _invalid -> {:error, %{version: "must be a positive integer"}}
    end
  end

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
