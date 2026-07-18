defmodule Cadence.ContactPlanning.FleetAutomation do
  @moduledoc """
  Exact-grant unattended fleet workflow.

  The service identity remains the actor. The approving administrator is retained
  through the immutable Automation Grant and every high-impact action revalidates
  that exact grant before changing Plan or provider state.
  """

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    ContactPlanApprovals,
    ContactPlanExecutions,
    ContactPlans,
    FleetAutomationActions,
    FleetPlanner,
    FleetPlanningRuns,
    FleetRepairs
  }

  @spec plan(Scope.t(), binary(), map(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def plan(%Scope{} = scope, mission_id, attrs, grant_id, opts \\ [])
      when is_binary(mission_id) and is_map(attrs) and is_binary(grant_id) and is_list(opts) do
    with {:ok, horizon_seconds} <- horizon_seconds(attrs),
         {:ok, _grant} <-
           AutomationGrants.authorize(
             scope,
             mission_id,
             grant_id,
             :plan,
             %{horizon_seconds: horizon_seconds},
             opts
           ),
         {:ok, run, _refs} <- FleetPlanner.start(scope, mission_id, attrs, opts) do
      run(scope, mission_id, run.fleet_planning_run_id, grant_id, opts)
    end
  end

  @spec repair(
          Scope.t(),
          binary(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          binary(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def repair(
        %Scope{} = scope,
        mission_id,
        source_run_id,
        source_plan_id,
        source_plan_version,
        attrs,
        grant_id,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(source_run_id) and
             is_binary(source_plan_id) and is_integer(source_plan_version) and
             source_plan_version > 0 and is_map(attrs) and is_binary(grant_id) and
             is_list(opts) do
    with {:ok, horizon_seconds} <- horizon_seconds(attrs),
         {:ok, _grant} <-
           AutomationGrants.authorize(
             scope,
             mission_id,
             grant_id,
             :repair,
             %{horizon_seconds: horizon_seconds},
             opts
           ),
         {:ok, run, _refs} <-
           FleetRepairs.start(
             scope,
             mission_id,
             source_run_id,
             source_plan_id,
             source_plan_version,
             attrs,
             opts
           ) do
      run(scope, mission_id, run.fleet_planning_run_id, grant_id, opts)
    end
  end

  @spec run(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run(%Scope{} = scope, mission_id, run_id, grant_id, opts \\ [])
      when is_binary(mission_id) and is_binary(run_id) and is_binary(grant_id) and
             is_list(opts) do
    with {:ok, run} <- FleetPlanningRuns.fetch(scope.organization_id, mission_id, run_id),
         horizon = DateTime.diff(run.horizon_end, run.horizon_start, :second),
         {:ok, grant} <-
           AutomationGrants.authorize(
             scope,
             mission_id,
             grant_id,
             action_for_run(run),
             %{horizon_seconds: horizon},
             opts
           ),
         {:ok, planning, plan_action} <-
           execute_planning(scope, mission_id, run, grant, opts),
         {:ok, workflow} <-
           continue_automatic_actions(scope, planning, grant, opts) do
      {:ok,
       Map.merge(workflow, %{
         planning: planning,
         actions:
           FleetAutomationActions.list(
             scope.organization_id,
             mission_id,
             run_id
           ),
         plan_action: plan_action
       })}
    end
  end

  defp execute_planning(scope, mission_id, run, grant, opts) do
    evidence = %{
      "horizon_seconds" => DateTime.diff(run.horizon_end, run.horizon_start, :second),
      "trigger_kind" => Atom.to_string(run.trigger_kind)
    }

    with {:ok, status, action} <-
           FleetAutomationActions.begin_action(
             scope,
             grant,
             run.fleet_planning_run_id,
             action_for_run(run),
             evidence,
             %{},
             opts
           ),
         {:ok, planning} <- FleetPlanner.run(scope, mission_id, run.fleet_planning_run_id, opts),
         {:ok, completed_action} <-
           complete_planning_action(scope, status, action, planning, opts) do
      {:ok, planning, completed_action}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_planning_action(scope, _status, action, planning, opts) do
    outcome = if planning.run.lifecycle_state == :failed, do: :failed, else: :succeeded

    result = %{
      "fleet_planning_run_id" => planning.run.fleet_planning_run_id,
      "lifecycle_state" => Atom.to_string(planning.run.lifecycle_state),
      "candidate_contact_plan_id" => planning.run.candidate_contact_plan_id,
      "candidate_contact_plan_version" => planning.run.candidate_contact_plan_version
    }

    error =
      if outcome == :failed,
        do: planning.run.failure_document,
        else: %{}

    FleetAutomationActions.complete(
      scope,
      action.fleet_automation_action_id,
      outcome,
      result,
      error,
      opts
    )
  end

  defp continue_automatic_actions(
         _scope,
         %{run: %{lifecycle_state: state}},
         _grant,
         _opts
       )
       when state != :completed do
    {:ok, %{submission: nil, approval: nil, execution: nil}}
  end

  defp continue_automatic_actions(scope, planning, grant, opts) do
    with {:ok, submission} <- maybe_submit(scope, planning, grant, opts),
         {:ok, approval} <- maybe_approve(scope, planning, submission, grant, opts),
         {:ok, execution} <- maybe_execute(scope, planning, approval, grant, opts) do
      {:ok,
       %{
         submission: submission,
         approval: approval,
         execution: execution
       }}
    end
  end

  defp maybe_submit(scope, planning, grant, opts) do
    if :submit in grant.allowed_actions,
      do: submit(scope, planning, grant, opts),
      else: {:ok, nil}
  end

  defp submit(scope, planning, grant, opts) do
    plan = planning.plan
    version = planning.plan_version
    evidence = plan_evidence(planning, grant)

    with {:ok, _grant} <-
           AutomationGrants.authorize(
             scope,
             plan.mission_id,
             grant.automation_grant_id,
             :submit,
             evidence,
             opts
           ),
         {:ok, _status, action} <-
           FleetAutomationActions.begin_action(
             scope,
             grant,
             planning.run.fleet_planning_run_id,
             :submit,
             evidence,
             plan_ref(plan, version),
             opts
           ),
         {:ok, submitted} <-
           ensure_submitted(scope, plan, version, grant, evidence, opts),
         {:ok, completed} <-
           FleetAutomationActions.complete(
             scope,
             action.fleet_automation_action_id,
             :succeeded,
             %{"contact_plan_id" => submitted.contact_plan_id, "state" => "pending_approval"},
             %{},
             opts
           ) do
      {:ok, %{plan: submitted, action: completed}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_submitted(scope, %{lifecycle_state: :draft} = plan, version, grant, evidence, opts) do
    ContactPlans.submit(
      scope,
      plan.mission_id,
      plan.contact_plan_id,
      version.version,
      "Submitted by exact bounded automation grant",
      automation_opts(opts, grant, evidence)
    )
  end

  defp ensure_submitted(_scope, plan, _version, _grant, _evidence, _opts)
       when plan.lifecycle_state in [
              :pending_approval,
              :approved,
              :executing,
              :partially_reserved,
              :reserved
            ],
       do: {:ok, plan}

  defp ensure_submitted(_scope, _plan, _version, _grant, _evidence, _opts),
    do: {:error, :automated_contact_plan_not_submittable}

  defp maybe_approve(scope, planning, submission, grant, opts) do
    cond do
      is_nil(submission) ->
        {:ok, nil}

      :approve in grant.allowed_actions ->
        approve(scope, planning, submission, grant, opts)

      true ->
        {:ok, submission}
    end
  end

  defp approve(scope, planning, submission, grant, opts) do
    plan = submission.plan
    version = planning.plan_version
    evidence = plan_evidence(planning, grant)

    with {:ok, _grant} <-
           AutomationGrants.authorize(
             scope,
             plan.mission_id,
             grant.automation_grant_id,
             :approve,
             evidence,
             opts
           ),
         {:ok, _status, action} <-
           FleetAutomationActions.begin_action(
             scope,
             grant,
             planning.run.fleet_planning_run_id,
             :approve,
             evidence,
             plan_ref(plan, version),
             opts
           ),
         {:ok, approved, approval} <-
           ensure_approved(scope, plan, version, grant, evidence, opts),
         {:ok, completed} <-
           FleetAutomationActions.complete(
             scope,
             action.fleet_automation_action_id,
             :succeeded,
             %{
               "contact_plan_id" => approved.contact_plan_id,
               "state" => "approved",
               "contact_plan_approval_id" => approval.contact_plan_approval_id
             },
             %{},
             opts
           ) do
      {:ok, %{plan: approved, approval: approval, action: completed}}
    end
  end

  defp ensure_approved(
         scope,
         %{lifecycle_state: :pending_approval} = plan,
         version,
         grant,
         evidence,
         opts
       ) do
    case ContactPlanApprovals.approve(
           scope,
           plan.mission_id,
           plan.contact_plan_id,
           version.version,
           version.content_sha256,
           "Approved by exact bounded automation grant",
           automation_opts(opts, grant, evidence)
         ) do
      {:ok, approved, _version, approval} -> {:ok, approved, approval}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_approved(_scope, plan, _version, _grant, _evidence, _opts)
       when plan.lifecycle_state in [
              :approved,
              :executing,
              :partially_reserved,
              :reserved
            ] do
    case ContactPlanApprovals.list(
           plan.organization_id,
           plan.mission_id,
           plan.contact_plan_id
         ) do
      [approval | _rest] -> {:ok, plan, approval}
      [] -> {:error, :automated_contact_plan_approval_evidence_not_found}
    end
  end

  defp ensure_approved(_scope, _plan, _version, _grant, _evidence, _opts),
    do: {:error, :automated_contact_plan_not_approvable}

  defp maybe_execute(scope, planning, approval, grant, opts) do
    cond do
      is_nil(approval) ->
        {:ok, nil}

      approval.plan.lifecycle_state not in [
        :approved,
        :executing,
        :partially_reserved,
        :reserved
      ] ->
        {:ok, nil}

      :execute in grant.allowed_actions ->
        execute(scope, planning, approval, grant, opts)

      true ->
        {:ok, approval}
    end
  end

  defp execute(scope, planning, approval, grant, opts) do
    plan = approval.plan
    version = planning.plan_version
    concurrency = grant.maximum_execution_concurrency

    evidence =
      planning
      |> plan_evidence(grant)
      |> Map.put(:execution_concurrency, concurrency)
      |> Map.put(:contact_count, length(version.selected_snapshot_ids))

    with {:ok, _grant} <-
           AutomationGrants.authorize(
             scope,
             plan.mission_id,
             grant.automation_grant_id,
             :execute,
             evidence,
             opts
           ),
         {:ok, _status, action} <-
           FleetAutomationActions.begin_action(
             scope,
             grant,
             planning.run.fleet_planning_run_id,
             :execute,
             evidence,
             plan_ref(plan, version),
             opts
           ),
         {:ok, execution} <-
           ContactPlanExecutions.execute(
             scope,
             plan.mission_id,
             plan.contact_plan_id,
             automation_opts(opts, grant, evidence)
             |> Keyword.put(:execution_concurrency, concurrency)
           ),
         {:ok, completed} <-
           FleetAutomationActions.complete(
             scope,
             action.fleet_automation_action_id,
             :succeeded,
             %{
               "contact_plan_id" => execution.plan.contact_plan_id,
               "state" => Atom.to_string(execution.plan.lifecycle_state),
               "item_count" => length(execution.items)
             },
             %{},
             opts
           ) do
      {:ok, %{execution: execution, action: completed}}
    end
  end

  defp plan_evidence(planning, grant) do
    budgets = planning.run.result_summary_document["budgets"] || %{}
    version = planning.plan_version

    evidence = %{
      contact_count: length(version.selected_snapshot_ids) + length(version.locked_snapshot_ids)
    }

    if grant.maximum_estimated_cost_micros do
      evidence
      |> Map.put(:estimated_cost_micros, budgets["known_cost_micros"])
      |> Map.put(:currency, budgets["currency"])
      |> Map.put(:unknown_cost_count, budgets["unknown_cost_count"])
    else
      evidence
    end
  end

  defp automation_opts(opts, grant, evidence) do
    opts
    |> Keyword.take([
      :now,
      :resolve_route,
      :reserve,
      :provider_opts,
      :retry_failed
    ])
    |> Keyword.put(:automation_grant_id, grant.automation_grant_id)
    |> Keyword.put(:automation_evidence, evidence)
  end

  defp plan_ref(plan, version) do
    %{
      contact_plan_id: plan.contact_plan_id,
      contact_plan_version: version.version
    }
  end

  defp action_for_run(%{trigger_kind: :repair}), do: :repair
  defp action_for_run(_run), do: :plan

  defp horizon_seconds(attrs) do
    with {:ok, start_at} <- datetime(value(attrs, :horizon_start)),
         {:ok, end_at} <- datetime(value(attrs, :horizon_end)),
         seconds when seconds > 0 <- DateTime.diff(end_at, start_at, :second) do
      {:ok, seconds}
    else
      _reason -> {:error, :fleet_automation_horizon_invalid}
    end
  end

  defp datetime(%DateTime{} = value), do: {:ok, value}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> {:ok, parsed}
      _other -> {:error, :invalid_datetime}
    end
  end

  defp datetime(_value), do: {:error, :invalid_datetime}

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
