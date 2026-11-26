defmodule CadenceWeb.Console.ContactDraftController do
  @moduledoc """
  Fleet drafts for a day (S3): `POST /contact-plans/drafts` starts one
  (202, idempotent by `operation_id`), `GET /contact-plans/drafts/:run_id`
  reads it with its candidate plan, `POST …/:run_id/continue` resumes an
  interrupted one. Contract: docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Comms.StationRefs
  alias Cadence.ContactPlanning.{FleetPlanningRuns, RepairChain}
  alias Cadence.Control.Scheduling
  alias Cadence.Reads.{ContactPlanOverview, PlanRepairHeader, RepairDiff}
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

  @repair_refusals [
    :fleet_repair_attempt_limit_exceeded,
    :fleet_repair_horizon_exceeded,
    :fleet_repair_horizon_invalid
  ]

  @doc "S8: start a repair (re-plan after provider changes) for a plan."
  def repair(conn, %{"plan_id" => plan_id} = params) do
    with {:ok, operation_id} <- operation_id(params["operation_id"]),
         {:ok, window} <- window(params["from"], params["to"]),
         {:ok, run, outcome} <-
           Scheduling.start_repair(scope(conn), mission_id(conn), plan_id, window, operation_id) do
      if outcome == :created, do: start(conn, run.fleet_planning_run_id, &Scheduling.run_draft/3)

      conn
      |> put_status(:accepted)
      |> json(%{
        data: %{run_id: run.fleet_planning_run_id, outcome: outcome, state: state(conn, run)}
      })
    else
      {:error, :repair_source_not_found} -> Problem.respond(conn, :plan_not_repairable)
      {:error, :fleet_repair_source_unavailable} -> Problem.respond(conn, :plan_not_repairable)
      {:error, reason} when reason in @repair_refusals -> repair_refused(conn, plan_id, reason)
      error -> error(conn, error)
    end
  end

  # ux U76: the refusal carries what its line names (the attempts, or the policy's horizon).
  defp repair_refused(conn, plan_id, reason) do
    header =
      PlanRepairHeader.for_plan(
        conn.assigns.current_scope.organization_id,
        mission_id(conn),
        plan_id,
        DateTime.utc_now()
      )

    details =
      case {reason, header} do
        {:fleet_repair_attempt_limit_exceeded, %{attempts: attempts}} -> attempts
        {:fleet_repair_horizon_exceeded, %{horizon_seconds: s}} -> %{horizon_seconds: s}
        _other -> nil
      end

    Problem.respond(conn, reason, details)
  end

  @doc "S8: the repair run, its new candidate plan and the diff against the source plan."
  def show_repair(conn, %{"run_id" => run_id}) do
    case FleetPlanningRuns.fetch(org_id(conn), mission_id(conn), run_id) do
      {:ok, %{source_contact_plan_id: source_id} = run} when is_binary(source_id) ->
        data =
          conn
          |> draft(run)
          |> Map.merge(%{
            source_plan: %{id: source_id, version: run.source_contact_plan_version},
            diff: diff(conn, run)
          })

        json(conn, %{data: ConfigJSON.encode(data)})

      _not_repair ->
        Problem.respond(conn, :draft_not_found)
    end
  end

  # qa #30: the bookings the repair started from (across the day's repair chain) against the
  # candidate, classified by the candidate's locked passes.
  defp diff(conn, run) do
    case RepairChain.review_passes(run) do
      nil ->
        nil

      %{before: before, after: after_passes, locked: locked} = review ->
        RepairDiff.diff(
          before,
          after_passes,
          StationRefs.index(org_id(conn), mission_id(conn)),
          locked,
          Map.get(review, :covered, %{})
        )
    end
  end

  defp window(nil, nil), do: {:ok, nil}

  defp window(from, to) when is_binary(from) and is_binary(to) do
    with {:ok, from, _} <- DateTime.from_iso8601(from),
         {:ok, to, _} <- DateTime.from_iso8601(to),
         true <- DateTime.before?(from, to) do
      {:ok, {from, to}}
    else
      _invalid -> {:error, {:invalid_params, %{from: "from/to must be ISO-8601 with from < to"}}}
    end
  end

  defp window(_from, _to),
    do: {:error, {:invalid_params, %{from: "give both from and to, or neither"}}}

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
        # The same derived state as GET /contact-plans/:id (`interrupted` when nobody executes).
        %{
          plan
          | state: Scheduling.plan_state(org_id(conn), mission_id(conn), plan.id, plan.state)
        }
      else
        _none -> nil
      end

    state = state(conn, run)

    %{
      run: %{
        id: run.fleet_planning_run_id,
        state: state,
        phase: run.phase,
        horizon: %{from: run.horizon_start, to: run.horizon_end},
        failure: if(run.failure_document == %{}, do: nil, else: run.failure_document),
        started_at: run.started_at,
        updated_at: run.updated_at,
        stopped_at: stopped_at(state, run)
      },
      plan: plan
    }
  end

  defp state(conn, run), do: Scheduling.draft_state(org_id(conn), mission_id(conn), run)

  # Backlog: when the run stopped. A finished run's completion time; an interrupted run's last
  # recorded progress (nothing records the moment a node dies, so it stopped at or after this).
  defp stopped_at(:interrupted, run), do: run.updated_at
  defp stopped_at(state, _run) when state in [:queued, :running], do: nil
  defp stopped_at(_finished, run), do: run.completed_at || run.updated_at

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

  # U52: the whole count and the limit, so the console can say how far over it is.
  defp error(conn, {:error, {:fleet_planning_occurrence_limit_exceeded, count, limit}}),
    do:
      Problem.respond(conn, :fleet_planning_occurrence_limit_exceeded, %{
        count: count,
        limit: limit
      })

  defp error(conn, {:error, :fleet_planning_run_requirement_limit_exceeded}),
    do:
      Problem.respond(conn, :fleet_planning_run_requirement_limit_exceeded, %{
        limit: FleetPlanningRuns.maximum_requirements()
      })

  defp error(conn, {:error, :fleet_planning_review_changed}),
    do: Problem.respond(conn, :inputs_changed)

  defp error(conn, {:error, :forbidden}), do: Problem.respond(conn, :forbidden)
  defp error(conn, {:error, reason}) when is_atom(reason), do: Problem.respond(conn, reason)
  defp error(conn, _error), do: Problem.respond(conn, :draft_failed)

  defp scope(conn), do: conn.assigns.current_scope
  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
