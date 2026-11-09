defmodule CadenceWeb.Console.ContactPlanController do
  @moduledoc """
  Contact plan reads for scheduling (S6 list, plan detail with demand).
  Contract: docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.ContactPlanning.ContactPlan
  alias Cadence.Control.Scheduling
  alias Cadence.Reads.{ContactPlanOverview, PlanningSetup}
  alias CadenceWeb.Console.{ConfigJSON, Problem, SchedulingRunner}

  @states Map.new(ContactPlan.states(), &{Atom.to_string(&1), &1})

  def index(conn, params) do
    with {:ok, day} <- day(params["day"]),
         {:ok, state} <- state(params["state"]) do
      plans =
        org_id(conn)
        |> ContactPlanOverview.list(mission_id(conn), %{day: day, state: state})
        |> Enum.map(&effective_state(conn, &1))

      json(conn, %{data: ConfigJSON.encode(%{plans: plans})})
    else
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  def show(conn, %{"plan_id" => plan_id} = params) do
    with {:ok, version} <- version(params["version"]),
         {:ok, plan} <- ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id, version) do
      json(conn, %{data: ConfigJSON.encode(effective_state(conn, plan))})
    else
      {:error, :plan_not_found} -> Problem.respond(conn, :plan_not_found)
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  @doc "Whether drafting is possible (policy + requirements), before offering Draft."
  def setup(conn, _params),
    do:
      json(conn, %{
        data: ConfigJSON.encode(%{setup: PlanningSetup.setup(org_id(conn), mission_id(conn))})
      })

  @doc "Contact demand for a UTC day without a plan (S2)."
  def demand(conn, params) do
    case day(params["day"]) do
      {:ok, %Date{} = day} ->
        json(conn, %{
          data: ConfigJSON.encode(PlanningSetup.demand(org_id(conn), mission_id(conn), day))
        })

      {:ok, nil} ->
        Problem.respond(conn, :invalid_params, %{day: "is required (YYYY-MM-DD)"})

      {:error, details} ->
        Problem.respond(conn, :invalid_params, details)
    end
  end

  @doc "S5: submit (member) or submit + approve + execute (admin). See scheduling.md."
  def submit(conn, %{"plan_id" => plan_id} = params) do
    with {:ok, submit} <- submit_params(params),
         {:ok, outcome} <-
           Scheduling.submit_plan(
             scope(conn),
             mission_id(conn),
             plan_id,
             submit.operation_id,
             submit
           ) do
      respond_submit(conn, plan_id, outcome)
    else
      {:error, reason} -> submit_error(conn, plan_id, reason)
    end
  end

  @doc "Re-executes an approved plan whose execution was interrupted (idempotent per item)."
  def execute(conn, %{"plan_id" => plan_id}) do
    with {:ok, plan} <- ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id),
         true <- effective_state(conn, plan).state in [:interrupted, :approved] or :not_resumable,
         {:ok, version, sha} <-
           Scheduling.approved_version(org_id(conn), mission_id(conn), plan_id) do
      start_execution(conn, plan_id, version, sha)
      conn |> put_status(:accepted) |> json(%{data: %{plan_id: plan_id, state: :executing}})
    else
      {:error, :plan_not_found} -> Problem.respond(conn, :plan_not_found)
      :not_resumable -> Problem.respond(conn, :plan_not_resumable)
      {:error, _reason} -> Problem.respond(conn, :plan_not_resumable)
    end
  end

  defp respond_submit(conn, plan_id, {:execute, version, sha}) do
    start_execution(conn, plan_id, version, sha)

    conn
    |> put_status(:accepted)
    |> json(%{data: %{plan_id: plan_id, state: :executing, outcome: :executing}})
  end

  defp respond_submit(conn, plan_id, outcome) when outcome in [:pending_approval, :replayed] do
    state =
      case ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id) do
        {:ok, plan} -> effective_state(conn, plan).state
        _missing -> nil
      end

    json(conn, %{data: %{plan_id: plan_id, state: state, outcome: outcome}})
  end

  defp start_execution(conn, plan_id, version, sha) do
    scope = scope(conn)
    mission_id = mission_id(conn)

    SchedulingRunner.start(mission_id, :execute, plan_id, fn ->
      Scheduling.execute_plan(scope, mission_id, plan_id, version, sha)
    end)
  end

  defp submit_params(params) do
    with {:ok, version} <- positive(params["expected_version"], :expected_version),
         {:ok, operation_id} <- operation_id(params["operation_id"]),
         {:ok, acknowledgements} <- acknowledgements(params["acknowledgements"]) do
      {:ok,
       %{
         expected_version: version,
         operation_id: operation_id,
         reason: if(is_binary(params["reason"]), do: params["reason"]),
         acknowledgements: acknowledgements
       }}
    end
  end

  defp acknowledgements(nil), do: {:ok, []}

  defp acknowledgements(items) when is_list(items) do
    if Enum.all?(
         items,
         &(is_map(&1) and is_binary(&1["requirement_id"]) and is_binary(&1["reason"]))
       ),
       do: {:ok, Enum.map(items, &%{requirement_id: &1["requirement_id"], reason: &1["reason"]})},
       else: {:error, %{acknowledgements: "must be [{requirement_id, reason}]"}}
  end

  defp acknowledgements(_items), do: {:error, %{acknowledgements: "must be a list"}}

  defp submit_error(conn, plan_id, :contact_plan_not_satisfied) do
    details =
      case ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id) do
        {:ok, plan} -> %{unmet: plan.unmet, conflicts: plan.conflicts}
        _missing -> nil
      end

    Problem.respond(conn, :plan_not_ready, ConfigJSON.encode(details))
  end

  defp submit_error(conn, _plan_id, {:contact_plan_exceptions_required, ids}),
    do: Problem.respond(conn, :acknowledgements_required, %{missing: ids})

  defp submit_error(conn, _plan_id, {:contact_plan_exceptions_unknown, ids}),
    do:
      Problem.respond(conn, :invalid_params, %{
        acknowledgements: "not unmet in this plan: #{Enum.join(ids, ", ")}"
      })

  defp submit_error(conn, _plan_id, {:contact_plan_exception_invalid, id}),
    do:
      Problem.respond(conn, :invalid_params, %{
        acknowledgements: "reason for #{id} must be 10-2000 characters"
      })

  defp submit_error(conn, _plan_id, details) when is_map(details),
    do: Problem.respond(conn, :invalid_params, details)

  defp submit_error(conn, _plan_id, :contact_plan_not_found),
    do: Problem.respond(conn, :plan_not_found)

  defp submit_error(conn, _plan_id, :contact_plan_version_changed),
    do: Problem.respond(conn, :plan_changed)

  defp submit_error(conn, _plan_id, :contact_plan_not_submittable),
    do: Problem.respond(conn, :plan_not_submittable)

  defp submit_error(conn, _plan_id, :operation_already_claimed),
    do: Problem.respond(conn, :operation_conflict)

  defp submit_error(conn, _plan_id, :forbidden), do: Problem.respond(conn, :forbidden)

  defp submit_error(conn, _plan_id, reason) when is_atom(reason),
    do: Problem.respond(conn, reason)

  defp submit_error(conn, _plan_id, _reason), do: Problem.respond(conn, :plan_not_submittable)

  defp effective_state(conn, plan),
    do: %{
      plan
      | state: Scheduling.plan_state(org_id(conn), mission_id(conn), plan.id, plan.state)
    }

  defp positive(value, _key) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(_value, key), do: {:error, %{key => "is required (positive integer)"}}

  defp operation_id(value) when is_binary(value) and byte_size(value) in 1..120, do: {:ok, value}
  defp operation_id(_value), do: {:error, %{operation_id: "is required (1-120 chars)"}}

  defp scope(conn), do: conn.assigns.current_scope

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
