defmodule Cadence.Control.Scheduling do
  @moduledoc """
  Console scheduling orchestration over the contact-planning domain
  (DECISIONS #26–#28). It composes the existing reviewed flows instead of
  re-implementing them:

  - `start_draft/4`: fleet-run preview + create for a UTC day (the evidence
    pattern), then records the client's `operation_id` on the run so a replay
    on any node finds it.
  - `run_draft/3` and `continue_draft/3`: execute or resume the run. These block
    on provider searches, so callers run them off the request path.
  - `draft_state/3`: the run's lifecycle, plus `interrupted` when a run sits
    queued/running with no session holding its execution lock.

  Authorization is the domain's own (`operate_mission`).
  """

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    FleetPlanner,
    FleetPlanningRun,
    FleetPlanningRuns,
    FleetPlanningStarts,
    FleetRunActions,
    FleetRunLock,
    FleetRunReviews
  }

  # A queued run gets this long for its task to take the execution lock.
  @queued_grace_s 60

  @spec start_draft(Scope.t(), binary(), Date.t(), binary()) ::
          {:ok, FleetPlanningRun.t(), :created | :replayed} | {:error, term()}
  def start_draft(%Scope{} = scope, mission_id, %Date{} = day, operation_id)
      when is_binary(operation_id) do
    case FleetPlanningRuns.fetch_by_operation(scope.organization_id, mission_id, operation_id) do
      {:ok, run} ->
        {:ok, run, :replayed}

      {:error, :fleet_planning_run_not_found} ->
        create_draft(scope, mission_id, day, operation_id)
    end
  end

  @spec run_draft(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def run_draft(%Scope{} = scope, mission_id, run_id),
    do: FleetPlanner.run(scope, mission_id, run_id)

  @spec continue_draft(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def continue_draft(%Scope{} = scope, mission_id, run_id) do
    with {:ok, %{evidence: evidence}} <- FleetRunReviews.load(scope, mission_id, run_id) do
      FleetRunActions.execute(scope, mission_id, :continue, %{
        "fleet_planning_run_id" => run_id,
        "evidence" => evidence
      })
    end
  end

  @spec draft_state(binary(), binary(), FleetPlanningRun.t()) :: atom()
  def draft_state(organization_id, mission_id, %FleetPlanningRun{} = run) do
    active? = run.lifecycle_state in [:queued, :running]

    cond do
      not active? ->
        run.lifecycle_state

      FleetRunLock.held?(organization_id, mission_id, run.fleet_planning_run_id) ->
        run.lifecycle_state

      run.lifecycle_state == :queued and recent?(run) ->
        :queued

      true ->
        :interrupted
    end
  end

  defp create_draft(scope, mission_id, day, operation_id) do
    fleet_run = %{
      "horizon_start" => day |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_iso8601(),
      "horizon_end" =>
        day |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_iso8601(),
      "include_recurring" => true
    }

    with {:ok, %{"evidence" => evidence}} <-
           FleetPlanningStarts.preview(scope, mission_id, %{"fleet_run" => fleet_run})
           |> stringify(),
         {:ok, run, _refs} <-
           FleetPlanningStarts.create(scope, mission_id, %{
             "fleet_run" => fleet_run,
             "evidence" => evidence
           }) do
      case FleetPlanningRuns.claim_operation(
             scope.organization_id,
             mission_id,
             run.fleet_planning_run_id,
             operation_id
           ) do
        :ok ->
          {:ok, run, :created}

        {:error, :operation_already_claimed} ->
          # A concurrent replay won; retire ours and answer with theirs.
          _ =
            FleetPlanningRuns.cancel(
              scope,
              mission_id,
              run.fleet_planning_run_id,
              "duplicate console operation"
            )

          start_draft(scope, mission_id, day, operation_id)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp stringify({:ok, review}) when is_map(review),
    do: {:ok, Map.new(review, fn {key, value} -> {to_string(key), value} end)}

  defp stringify(other), do: other

  defp recent?(%FleetPlanningRun{inserted_at: %DateTime{} = at}),
    do: DateTime.diff(DateTime.utc_now(), at) < @queued_grace_s

  defp recent?(_run), do: false
end
