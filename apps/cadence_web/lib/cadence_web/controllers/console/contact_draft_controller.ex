defmodule CadenceWeb.Console.ContactDraftController do
  @moduledoc """
  Fleet drafts for a day (S3): `POST /contact-plans/drafts` starts one
  (202, idempotent by `operation_id`), `GET /contact-plans/drafts/:run_id`
  reads it with its candidate plan, `POST …/:run_id/continue` resumes an
  interrupted one. Contract: docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.ContactPlanning.FleetPlanningRuns
  alias Cadence.Control.Scheduling
  alias Cadence.Reads.ContactPlanOverview
  alias CadenceWeb.Console.{ConfigJSON, Problem, SchedulingRunner}

  def create(conn, params) do
    with {:ok, day} <- day(params["day"]),
         {:ok, operation_id} <- operation_id(params["operation_id"]),
         {:ok, run, outcome} <-
           Scheduling.start_draft(scope(conn), mission_id(conn), day, operation_id) do
      if outcome == :created, do: start(conn, run.fleet_planning_run_id, &Scheduling.run_draft/3)

      conn
      |> put_status(:accepted)
      |> json(%{
        data: %{run_id: run.fleet_planning_run_id, outcome: outcome, state: state(conn, run)}
      })
    else
      error -> error(conn, error)
    end
  end

  def show(conn, %{"run_id" => run_id}) do
    case FleetPlanningRuns.fetch(org_id(conn), mission_id(conn), run_id) do
      {:ok, run} -> json(conn, %{data: ConfigJSON.encode(draft(conn, run))})
      {:error, _not_found} -> Problem.respond(conn, :draft_not_found)
    end
  end

  def continue(conn, %{"run_id" => run_id}) do
    with {:ok, run} <-
           FleetPlanningRuns.fetch(org_id(conn), mission_id(conn), run_id) |> not_found(),
         :interrupted <- state(conn, run) do
      start(conn, run_id, &Scheduling.continue_draft/3)
      conn |> put_status(:accepted) |> json(%{data: %{run_id: run_id, state: :running}})
    else
      {:error, :draft_not_found} -> Problem.respond(conn, :draft_not_found)
      _other_state -> Problem.respond(conn, :draft_not_interrupted)
    end
  end

  defp start(conn, run_id, work) do
    scope = scope(conn)
    mission_id = mission_id(conn)
    SchedulingRunner.start(mission_id, :draft, run_id, fn -> work.(scope, mission_id, run_id) end)
  end

  defp draft(conn, run) do
    plan =
      with id when is_binary(id) <- run.candidate_contact_plan_id,
           {:ok, plan} <-
             ContactPlanOverview.plan(
               org_id(conn),
               mission_id(conn),
               id,
               run.candidate_contact_plan_version
             ) do
        plan
      else
        _none -> nil
      end

    %{
      run: %{
        id: run.fleet_planning_run_id,
        state: state(conn, run),
        phase: run.phase,
        horizon: %{from: run.horizon_start, to: run.horizon_end},
        failure: if(run.failure_document == %{}, do: nil, else: run.failure_document),
        started_at: run.started_at,
        updated_at: run.updated_at
      },
      plan: plan
    }
  end

  defp state(conn, run), do: Scheduling.draft_state(org_id(conn), mission_id(conn), run)

  defp day(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, {:invalid_params, %{day: "must be YYYY-MM-DD"}}}
    end
  end

  defp day(_value), do: {:error, {:invalid_params, %{day: "is required (YYYY-MM-DD)"}}}

  defp operation_id(value) when is_binary(value) and byte_size(value) in 1..120, do: {:ok, value}

  defp operation_id(_value),
    do: {:error, {:invalid_params, %{operation_id: "is required (1-120 chars)"}}}

  defp not_found({:ok, _run} = ok), do: ok
  defp not_found(_error), do: {:error, :draft_not_found}

  defp error(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:error, :active_fleet_planning_policy_not_found}),
    do: Problem.respond(conn, :planning_not_set_up, %{missing: ["fleet_planning_policy"]})

  defp error(conn, {:error, :fleet_planning_run_has_no_requirements}),
    do: Problem.respond(conn, :planning_not_set_up, %{missing: ["contact_requirements"]})

  defp error(conn, {:error, :fleet_planning_horizon_exceeds_policy}),
    do: Problem.respond(conn, :horizon_exceeds_policy)

  defp error(conn, {:error, :fleet_planning_review_changed}),
    do: Problem.respond(conn, :inputs_changed)

  defp error(conn, {:error, :forbidden}), do: Problem.respond(conn, :forbidden)
  defp error(conn, {:error, reason}) when is_atom(reason), do: Problem.respond(conn, reason)
  defp error(conn, _error), do: Problem.respond(conn, :draft_failed)

  defp scope(conn), do: conn.assigns.current_scope
  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
