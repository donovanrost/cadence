defmodule Cadence.ContactPlanning.FleetRepairs do
  @moduledoc """
  Exact-source repair planning that preserves successful or uncertain commitments.

  A repair never mutates or compensates the source Plan. It creates a new Fleet
  Planning Run and records immutable lock evidence for the source commitments
  that the optimizer must plan around.
  """

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlanExecutions,
    ContactPlans,
    FleetPlanner,
    FleetPlanningPolicies,
    FleetPlanningRun,
    FleetPlanningRuns
  }

  @locked_execution_states [:reserved, :uncertain, :requesting]
  @repairable_plan_states [:executing, :partially_reserved, :failed]

  @type source :: %{
          required(:run) => struct(),
          required(:plan) => struct(),
          required(:plan_version) => struct(),
          required(:locked_commitments) => [struct()],
          required(:repair_attempt) => pos_integer()
        }

  @spec start(
          Scope.t(),
          binary(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, FleetPlanningRun.t(), [struct()]} | {:error, term()}
  def start(
        %Scope{} = scope,
        mission_id,
        source_run_id,
        source_plan_id,
        source_plan_version,
        attrs,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(source_run_id) and
             is_binary(source_plan_id) and is_integer(source_plan_version) and
             source_plan_version > 0 and is_map(attrs) and is_list(opts) do
    with {:ok, source} <-
           source(
             scope.organization_id,
             mission_id,
             source_run_id,
             source_plan_id,
             source_plan_version
           ),
         {:ok, _policy, policy} <-
           FleetPlanningPolicies.fetch_active(scope.organization_id, mission_id),
         :ok <- repair_attempt_allowed(source.repair_attempt, policy),
         :ok <- repair_horizon_allowed(attrs, policy),
         run_attrs <-
           repair_run_attrs(
             attrs,
             source,
             source_run_id,
             source_plan_id,
             source_plan_version
           ) do
      FleetPlanner.start(
        scope,
        mission_id,
        run_attrs,
        Keyword.put(opts, :materialize_templates, false)
      )
    end
  end

  @spec repair(
          Scope.t(),
          binary(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def repair(
        %Scope{} = scope,
        mission_id,
        source_run_id,
        source_plan_id,
        source_plan_version,
        attrs,
        opts \\ []
      ) do
    with {:ok, run, _refs} <-
           start(
             scope,
             mission_id,
             source_run_id,
             source_plan_id,
             source_plan_version,
             attrs,
             opts
           ) do
      FleetPlanner.run(scope, mission_id, run.fleet_planning_run_id, opts)
    end
  end

  @spec source(binary(), binary(), binary(), binary(), pos_integer()) ::
          {:ok, source()} | {:error, term()}
  def source(organization_id, mission_id, run_id, plan_id, plan_version) do
    with {:ok, run} <- FleetPlanningRuns.fetch(organization_id, mission_id, run_id),
         {:ok, plan, current_version} <- ContactPlans.fetch(organization_id, mission_id, plan_id),
         :ok <- exact_source(run, plan, current_version, plan_version),
         :ok <- repairable_plan(plan),
         {:ok, attempt} <- repair_attempt(organization_id, mission_id, run),
         locked <- source_locked_commitments(plan, current_version) do
      {:ok,
       %{
         run: run,
         plan: plan,
         plan_version: current_version,
         locked_commitments: locked,
         repair_attempt: attempt
       }}
    end
  end

  defp source_locked_commitments(plan, version) do
    execution_locked_ids =
      plan.organization_id
      |> ContactPlanExecutions.list(plan.mission_id, plan.contact_plan_id, version.version)
      |> Enum.filter(&(&1.lifecycle_state in @locked_execution_states))
      |> Enum.map(& &1.contact_opportunity_snapshot_id)

    locked_ids =
      version.locked_snapshot_ids
      |> Enum.concat(execution_locked_ids)
      |> MapSet.new()

    plan.organization_id
    |> ContactPlans.selected_snapshots(
      plan.mission_id,
      plan.contact_plan_id,
      version.version
    )
    |> Enum.filter(&MapSet.member?(locked_ids, &1.contact_opportunity_snapshot_id))
    |> Enum.sort_by(&{&1.starts_at, &1.contact_opportunity_snapshot_id})
  end

  defp exact_source(run, plan, current_version, requested_version) do
    cond do
      run.candidate_contact_plan_id != plan.contact_plan_id or
          run.candidate_contact_plan_version != requested_version ->
        {:error, :fleet_repair_source_plan_not_run_candidate}

      current_version.version != requested_version ->
        {:error, :fleet_repair_source_plan_version_changed}

      run.lifecycle_state not in [:completed, :partial] ->
        {:error, :fleet_repair_source_run_not_complete}

      true ->
        :ok
    end
  end

  defp repairable_plan(%{lifecycle_state: state}) when state in @repairable_plan_states, do: :ok
  defp repairable_plan(_plan), do: {:error, :fleet_repair_source_plan_not_repairable}

  defp repair_attempt(organization_id, mission_id, run) do
    repair_depth(organization_id, mission_id, run, 1, MapSet.new())
  end

  defp repair_depth(_organization_id, _mission_id, %{trigger_kind: trigger}, depth, _seen)
       when trigger != :repair,
       do: {:ok, depth}

  defp repair_depth(organization_id, mission_id, run, depth, seen) do
    cond do
      MapSet.member?(seen, run.fleet_planning_run_id) ->
        {:error, :fleet_repair_source_cycle}

      depth > 100 ->
        {:error, :fleet_repair_source_depth_exceeded}

      true ->
        seen = MapSet.put(seen, run.fleet_planning_run_id)

        case FleetPlanningRuns.fetch(
               organization_id,
               mission_id,
               run.source_fleet_planning_run_id
             ) do
          {:ok, parent} -> repair_depth(organization_id, mission_id, parent, depth + 1, seen)
          {:error, _reason} -> {:error, :fleet_repair_source_run_not_found}
        end
    end
  end

  defp repair_attempt_allowed(attempt, policy) do
    if attempt <= policy.automation_repair_document["max_repair_attempts"],
      do: :ok,
      else: {:error, :fleet_repair_attempt_limit_exceeded}
  end

  defp repair_horizon_allowed(attrs, policy) do
    with {:ok, starts_at} <- datetime(value(attrs, :horizon_start)),
         {:ok, ends_at} <- datetime(value(attrs, :horizon_end)),
         seconds when seconds > 0 <- DateTime.diff(ends_at, starts_at, :second) do
      if seconds <= policy.automation_repair_document["repair_horizon_seconds"],
        do: :ok,
        else: {:error, :fleet_repair_horizon_exceeded}
    else
      _reason -> {:error, :fleet_repair_horizon_invalid}
    end
  end

  defp repair_run_attrs(attrs, source, source_run_id, source_plan_id, source_plan_version) do
    requirements = source.plan_version.requirement_refs_document["requirements"]

    attrs
    |> Map.put(:trigger_kind, :repair)
    |> Map.put(:source_fleet_planning_run_id, source_run_id)
    |> Map.put(:source_contact_plan_id, source_plan_id)
    |> Map.put(:source_contact_plan_version, source_plan_version)
    |> Map.put(:requirement_refs, requirements)
    |> Map.put(:repair_input_document, %{
      "repair_attempt" => source.repair_attempt,
      "source_plan_content_sha256" => source.plan_version.content_sha256,
      "locked_commitments" =>
        Enum.map(source.locked_commitments, fn snapshot ->
          %{
            "contact_opportunity_snapshot_id" => snapshot.contact_opportunity_snapshot_id,
            "content_sha256" => snapshot.content_sha256,
            "contact_planning_run_id" => snapshot.contact_planning_run_id
          }
        end)
    })
  end

  defp datetime(%DateTime{} = value), do: {:ok, DateTime.truncate(value, :microsecond)}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> {:ok, DateTime.truncate(parsed, :microsecond)}
      _other -> {:error, :invalid_datetime}
    end
  end

  defp datetime(_value), do: {:error, :invalid_datetime}

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
