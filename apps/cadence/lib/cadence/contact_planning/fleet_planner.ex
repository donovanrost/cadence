defmodule Cadence.ContactPlanning.FleetPlanner do
  @moduledoc """
  Restart-safe composition of recurring Requirement generation, Stage 4 searches,
  deterministic fleet optimization, and ordinary Contact Plan materialization.
  """

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirements,
    ContactRequirementTemplates,
    ContentHash,
    FleetOptimizer,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    FleetRepairInputs,
    FleetRunLock,
    FleetSearch,
    Planner,
    RepairPairing
  }

  alias Cadence.Management.Contacts.PlanningResults

  @type result :: %{
          required(:run) => struct(),
          required(:plan) => struct() | nil,
          required(:plan_version) => struct() | nil
        }

  @spec start(Scope.t(), binary(), map(), keyword()) ::
          {:ok, struct(), [struct()]} | {:error, term()}
  def start(%Scope{} = scope, mission_id, attrs, opts \\ [])
      when is_binary(mission_id) and is_map(attrs) and is_list(opts) do
    with {:ok, horizon_start} <- datetime(value(attrs, :horizon_start)),
         {:ok, horizon_end} <- datetime(value(attrs, :horizon_end)),
         {:ok, materialization} <-
           materialize_templates(scope, mission_id, horizon_start, horizon_end, opts) do
      attrs =
        Map.put(
          attrs,
          :template_materialization_document,
          materialization
        )

      FleetPlanningRuns.create(scope, mission_id, attrs, opts)
    end
  end

  @spec plan(Scope.t(), binary(), map(), keyword()) :: {:ok, result()} | {:error, term()}
  def plan(%Scope{} = scope, mission_id, attrs, opts \\ []) do
    with {:ok, run, _refs} <- start(scope, mission_id, attrs, opts) do
      run(scope, mission_id, run.fleet_planning_run_id, opts)
    end
  end

  @spec run(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def run(%Scope{} = scope, mission_id, run_id, opts \\ [])
      when is_binary(mission_id) and is_binary(run_id) and is_list(opts) do
    FleetRunLock.with_run(scope.organization_id, mission_id, run_id, fn ->
      with {:ok, run} <- FleetPlanningRuns.fetch(scope.organization_id, mission_id, run_id) do
        continue(scope, mission_id, run, opts)
      end
    end)
  end

  defp continue(scope, mission_id, %{phase: :queued} = run, opts) do
    with {:ok, advanced} <-
           FleetPlanningRuns.advance_phase(
             scope,
             mission_id,
             run.fleet_planning_run_id,
             :queued,
             :materializing,
             %{},
             opts
           ) do
      continue(scope, mission_id, advanced, opts)
    end
  end

  defp continue(scope, mission_id, %{phase: :materializing} = run, opts) do
    with :ok <- ensure_current_inputs(run),
         {:ok, advanced} <-
           FleetPlanningRuns.advance_phase(
             scope,
             mission_id,
             run.fleet_planning_run_id,
             :materializing,
             :searching,
             %{},
             opts
           ) do
      continue(scope, mission_id, advanced, opts)
    else
      {:error, reason} ->
        fail_and_return(scope, mission_id, run, "fleet_inputs_stale", reason, opts)
    end
  end

  defp continue(scope, mission_id, %{phase: :searching} = run, opts) do
    with {:ok, policy} <- exact_policy(run),
         refs <- requirement_refs(run),
         {:ok, requirements} <- exact_requirements(run, refs),
         {:ok, search_summary} <-
           search_requirements(scope, run, refs, requirements, policy, opts),
         {:ok, advanced} <-
           FleetPlanningRuns.advance_phase(
             scope,
             mission_id,
             run.fleet_planning_run_id,
             :searching,
             :optimizing,
             %{progress_document: search_summary},
             opts
           ) do
      continue(scope, mission_id, advanced, opts)
    else
      {:error, reason} ->
        fail_and_return(scope, mission_id, run, "fleet_search_failed", reason, opts)
    end
  end

  defp continue(scope, mission_id, %{phase: :optimizing} = run, opts) do
    case optimize_phase(scope, mission_id, run, opts) do
      {:ok, advanced} ->
        :erlang.garbage_collect()
        continue(scope, mission_id, advanced, opts)

      {:error, reason} ->
        fail_and_return(scope, mission_id, run, "fleet_optimization_failed", reason, opts)
    end
  end

  defp continue(scope, mission_id, %{phase: :materializing_plan} = run, opts) do
    case materialize_phase(scope, mission_id, run, opts) do
      {:ok, completed, plan, version} ->
        :erlang.garbage_collect()
        terminal_result(completed, plan, version)

      {:error, reason} ->
        fail_and_return(scope, mission_id, run, "fleet_plan_materialization_failed", reason, opts)
    end
  end

  defp continue(_scope, _mission_id, %{phase: :finished} = run, _opts) do
    case candidate_plan(run) do
      {:ok, plan, version} -> terminal_result(run, plan, version)
      {:error, :fleet_planning_candidate_plan_not_linked} -> terminal_result(run, nil, nil)
      {:error, reason} -> {:error, reason}
    end
  end

  defp optimize_phase(scope, mission_id, run, opts) do
    with {:ok, policy} <- exact_policy(run),
         :ok <- ensure_active_policy(run, policy),
         {:ok, requirements} <- FleetPlanningRuns.optimization_requirements(run),
         snapshots <- planning_snapshots(run),
         {:ok, locked_commitments} <- FleetRepairInputs.locked_commitments(run),
         {:ok, optimization} <-
           FleetOptimizer.optimize_stream(
             requirements,
             snapshots,
             policy,
             optimizer_opts(run, locked_commitments, opts)
           ),
         {:ok, _decisions} <-
           FleetPlanningRuns.persist_decisions(
             scope,
             mission_id,
             run.fleet_planning_run_id,
             optimization.decisions
           ),
         :ok <- checkpoint_coverage(scope, run, optimization.coverage_by_requirement) do
      FleetPlanningRuns.advance_phase(
        scope,
        mission_id,
        run.fleet_planning_run_id,
        :optimizing,
        :materializing_plan,
        %{
          progress_document:
            Map.merge(run.progress_document, %{
              "snapshots_considered" => length(optimization.decisions),
              "snapshots_selected" => length(optimization.selected_snapshot_ids)
            }),
          result_summary_document: %{
            "coverage_counts" => coverage_counts(optimization.coverage_by_requirement),
            "resources" => optimization.resource_summary,
            "budgets" => optimization.budget_summary,
            "termination" => optimization.termination_document
          }
        },
        opts
      )
    end
  end

  defp materialize_phase(scope, mission_id, run, opts) do
    with :ok <- ensure_current_inputs(run),
         {:ok, plan, version} <- materialize_candidate_plan(scope, run, opts),
         outcome <- fleet_outcome(run.result_summary_document),
         {:ok, completed} <-
           FleetPlanningRuns.advance_phase(
             scope,
             mission_id,
             run.fleet_planning_run_id,
             :materializing_plan,
             :finished,
             %{
               outcome: outcome,
               candidate_contact_plan_id: plan.contact_plan_id,
               candidate_contact_plan_version: version.version,
               result_summary_document:
                 run.result_summary_document
                 |> Map.merge(%{
                   "candidate_contact_plan_id" => plan.contact_plan_id,
                   "candidate_contact_plan_version" => version.version
                 })
                 # qa #30: which lost bookings this repair's new passes replace, fixed now.
                 |> Map.merge(RepairPairing.summary(run, version))
             },
             opts
           ) do
      {:ok, completed, plan, version}
    end
  end

  defp materialize_templates(scope, mission_id, from, until, opts) do
    if Keyword.get(opts, :materialize_templates, true) do
      template_opts =
        opts
        |> Keyword.take([:now, :template_concurrency])
        |> Keyword.merge(Keyword.get(opts, :template_opts, []))

      ContactRequirementTemplates.materialize_active(
        scope,
        mission_id,
        from,
        until,
        template_opts
      )
    else
      {:ok,
       %{
         "template_count" => 0,
         "occurrence_count" => 0,
         "created_count" => 0,
         "existing_count" => 0,
         "skipped" => true
       }}
    end
  end

  defp search_requirements(scope, run, refs, requirements, policy, opts) do
    planner_opts = Keyword.get(opts, :planner_opts, [])

    if Keyword.has_key?(opts, :plan_requirement) or
         Enum.any?([:list_routes, :search_opportunities], fn key ->
           Keyword.has_key?(opts, key) or Keyword.has_key?(planner_opts, key)
         end) do
      search_custom_requirements(scope, run, refs, policy, opts)
    else
      FleetSearch.run(scope, run, refs, requirements, policy, Keyword.merge(opts, planner_opts))
    end
  end

  defp search_custom_requirements(scope, run, refs, policy, opts) do
    refs
    |> Task.async_stream(
      &search_requirement(scope, run, &1, policy, opts),
      ordered: true,
      max_concurrency: policy.horizon_document["requirement_concurrency"],
      timeout: :infinity
    )
    |> Enum.reduce_while(
      {:ok,
       %{
         "requirements_total" => length(refs),
         "requirements_searched" => 0,
         "requirements_failed" => 0,
         "snapshots_considered" => 0,
         "snapshots_selected" => 0
       }},
      fn
        {:ok, {:ok, result}}, {:ok, summary} ->
          summary =
            summary
            |> Map.update!(
              "requirements_searched",
              &(&1 + if(result.input_state == :searched, do: 1, else: 0))
            )
            |> Map.update!(
              "requirements_failed",
              &(&1 + if(result.input_state == :failed, do: 1, else: 0))
            )
            |> Map.update!("snapshots_considered", &(&1 + result.snapshot_count))

          {:cont, {:ok, summary}}

        {:ok, {:error, reason}}, _ ->
          {:halt, {:error, reason}}

        {:exit, _reason}, _ ->
          {:halt, {:error, :fleet_requirement_search_worker_exit}}
      end
    )
  end

  defp search_requirement(scope, run, ref, policy, opts) do
    case reusable_planning_result(run, ref) do
      {:ok, result} ->
        checkpoint_search_result(scope, run, ref, result)

      {:error, :contact_planning_run_not_found} when is_nil(ref.contact_planning_run_id) ->
        execute_requirement_search(scope, run, ref, policy, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reusable_planning_result(_run, %{contact_planning_run_id: nil}),
    do: {:error, :contact_planning_run_not_found}

  defp reusable_planning_result(run, ref) do
    with {:ok, planning_run} <-
           Planner.fetch_run(
             run.organization_id,
             run.mission_id,
             ref.contact_planning_run_id
           ),
         :ok <- planning_run_matches_ref(planning_run, ref) do
      {:ok,
       %{
         run: planning_run,
         searches:
           Planner.list_searches(
             run.organization_id,
             run.mission_id,
             ref.contact_planning_run_id
           ),
         snapshots:
           Planner.list_snapshots(
             run.organization_id,
             run.mission_id,
             ref.contact_planning_run_id
           )
       }}
    end
  end

  defp execute_requirement_search(scope, run, ref, policy, opts) do
    planner = Keyword.get(opts, :plan_requirement, &Planner.run/5)

    planner_opts =
      opts
      |> Keyword.take([
        :list_routes,
        :search_opportunities,
        :provider_opts,
        :result_limit,
        :now
      ])
      |> Keyword.merge(Keyword.get(opts, :planner_opts, []))
      |> Keyword.put(
        :max_concurrency,
        policy.horizon_document["provider_search_concurrency"]
      )

    case planner.(
           scope,
           run.mission_id,
           ref.contact_requirement_id,
           ref.contact_requirement_version,
           planner_opts
         ) do
      {:ok, result} -> checkpoint_search_result(scope, run, ref, result)
      {:error, reason} -> {:error, {:contact_requirement_search_failed, reason}}
      _other -> {:error, :contact_requirement_search_malformed}
    end
  end

  defp checkpoint_search_result(scope, run, ref, result) do
    input_state =
      if result.run.lifecycle_state == :failed,
        do: :failed,
        else: :searched

    result_state = if input_state == :failed, do: :failed, else: :pending

    explanation = %{
      "code" =>
        if(input_state == :failed,
          do: "stage_4_planning_failed",
          else: "stage_4_planning_complete"
        ),
      "contact_planning_run_id" => result.run.contact_planning_run_id,
      "lifecycle_state" => Atom.to_string(result.run.lifecycle_state),
      "summary" => result.run.summary_document
    }

    case FleetPlanningRuns.update_requirement_progress(
           scope,
           run.mission_id,
           run.fleet_planning_run_id,
           ref.contact_requirement_id,
           input_state,
           result_state,
           %{
             contact_planning_run_id: result.run.contact_planning_run_id,
             explanation_document: explanation
           }
         ) do
      {:ok, _updated} ->
        {:ok,
         %{
           input_state: input_state,
           snapshot_count: length(result.snapshots),
           planning_run_id: result.run.contact_planning_run_id
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp planning_snapshots(run) do
    run_ids = run |> FleetPlanningRuns.planning_run_ids() |> Enum.sort()
    PlanningResults.stream_fleet_snapshots(run.organization_id, run.mission_id, run_ids)
  end

  defp checkpoint_coverage(scope, run, coverage) do
    FleetPlanningRuns.persist_coverage(scope, run.mission_id, run.fleet_planning_run_id, coverage)
  end

  defp materialize_candidate_plan(scope, run, opts) do
    {selected_ids, locked_ids} =
      FleetPlanningRuns.selected_snapshot_ids(
        run.organization_id,
        run.mission_id,
        run.fleet_planning_run_id
      )

    planning_run_ids =
      run
      |> selected_planning_run_ids(selected_ids ++ locked_ids)
      |> Enum.concat(FleetPlanningRuns.planning_run_ids(run))
      |> Enum.concat(source_planning_run_ids(run))
      |> Enum.uniq()
      |> Enum.sort()

    if planning_run_ids == [] do
      {:error, :fleet_planning_run_has_no_stage_4_evidence}
    else
      create_or_fetch_candidate_plan(
        scope,
        run,
        planning_run_ids,
        selected_ids,
        locked_ids,
        opts
      )
    end
  end

  defp selected_planning_run_ids(run, selected_ids) do
    PlanningResults.planning_run_ids_for_fleet_snapshots(
      run.organization_id,
      run.mission_id,
      selected_ids
    )
  end

  defp create_or_fetch_candidate_plan(
         scope,
         run,
         planning_run_ids,
         selected_ids,
         locked_ids,
         opts
       ) do
    plan_id = candidate_plan_id(run)

    case ContactPlans.fetch(run.organization_id, run.mission_id, plan_id) do
      {:ok, plan, version} ->
        if candidate_matches?(version, planning_run_ids, selected_ids, locked_ids),
          do: {:ok, plan, version},
          else: {:error, :fleet_candidate_plan_identity_collision}

      {:error, :contact_plan_not_found} ->
        ContactPlans.create(
          scope,
          run.mission_id,
          %{
            contact_plan_id: plan_id,
            planning_run_ids: planning_run_ids,
            selected_snapshot_ids: selected_ids,
            locked_snapshot_ids: locked_ids,
            rationale:
              "Fleet candidate generated by #{run.algorithm_key} v#{run.algorithm_version} " <>
                "from #{run.fleet_planning_run_id}"
          },
          Keyword.take(opts, [:now])
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp candidate_matches?(version, planning_run_ids, selected_ids, locked_ids) do
    Enum.sort(version.planning_run_refs_document["runs"]) == Enum.sort(planning_run_ids) and
      version.selected_snapshot_ids == selected_ids and
      version.locked_snapshot_ids == locked_ids
  end

  @doc "Checks pinned requirements and the active policy before an explicit operator continuation."
  def check_current_inputs(run), do: ensure_current_inputs(run)

  defp ensure_current_inputs(run) do
    with {:ok, policy} <- exact_policy(run),
         :ok <- ensure_active_policy(run, policy),
         true <- FleetPlanningRuns.requirements_current?(run) do
      :ok
    else
      false -> {:error, :fleet_planning_input_drift}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_active_policy(run, policy) do
    with {:ok, _active_policy, active_version} <-
           FleetPlanningPolicies.fetch_active(run.organization_id, run.mission_id),
         true <-
           active_version.fleet_planning_policy_id == policy.fleet_planning_policy_id and
             active_version.version == policy.version and
             active_version.content_sha256 == policy.content_sha256 do
      :ok
    else
      false -> {:error, :fleet_planning_input_drift}
      {:error, reason} -> {:error, reason}
    end
  end

  defp exact_policy(run) do
    FleetPlanningPolicies.fetch_version(
      run.organization_id,
      run.mission_id,
      run.fleet_planning_policy_id,
      run.fleet_planning_policy_version
    )
  end

  defp requirement_refs(run) do
    FleetPlanningRuns.list_requirement_refs(
      run.organization_id,
      run.mission_id,
      run.fleet_planning_run_id
    )
  end

  defp exact_requirements(run, refs) do
    refs
    |> Stream.chunk_every(500)
    |> Enum.reduce_while({:ok, []}, &fetch_requirement_batch(&1, &2, run))
    |> case do
      {:ok, batches} -> {:ok, batches |> Enum.reverse() |> List.flatten()}
      error -> error
    end
  end

  defp fetch_requirement_batch(refs, {:ok, batches}, run) do
    ids = Enum.map(refs, & &1.contact_requirement_id)
    found = ContactRequirements.fetch_many(run.organization_id, run.mission_id, ids)
    versions = Enum.map(refs, &current_version_for_ref(&1, found))

    if Enum.any?(versions, &is_nil/1),
      do: {:halt, {:error, :fleet_planning_input_drift}},
      else: {:cont, {:ok, [versions | batches]}}
  end

  defp current_version_for_ref(ref, found) do
    case Map.get(found, ref.contact_requirement_id) do
      {%{lifecycle_state: :active, current_version: version}, current}
      when version == ref.contact_requirement_version ->
        if current.content_sha256 == ref.input_content_sha256, do: current

      _ ->
        nil
    end
  end

  defp planning_run_matches_ref(planning_run, ref) do
    if planning_run.contact_requirement_id == ref.contact_requirement_id and
         planning_run.contact_requirement_version == ref.contact_requirement_version,
       do: :ok,
       else: {:error, :fleet_planning_stage_4_run_binding_mismatch}
  end

  defp source_planning_run_ids(%{trigger_kind: trigger}) when trigger != :repair, do: []

  defp source_planning_run_ids(run) do
    run.input_document
    |> get_in(["repair", "locked_commitments"])
    |> List.wrap()
    |> Enum.map(& &1["contact_planning_run_id"])
    |> Enum.reject(&is_nil/1)
  end

  defp optimizer_opts(run, repair_locked_commitments, opts) do
    caller_locked_commitments = Keyword.get(opts, :locked_commitments, [])

    [
      now: Keyword.get(opts, :now, DateTime.utc_now()),
      locked_commitments: repair_locked_commitments ++ caller_locked_commitments,
      locked_snapshot_ids: Keyword.get(opts, :locked_snapshot_ids, []),
      # DECISIONS #78: drafts and repairs plan around live single bookings.
      occupied: occupied(run)
    ]
    |> Keyword.put(:fleet_planning_run_id, run.fleet_planning_run_id)
  end

  # Recorded on the run by whoever started it (`Contacts.SingleBookings.occupancy_document/3`).
  defp occupied(%{input_document: %{"occupied" => occupied}}) when is_list(occupied) do
    Enum.flat_map(occupied, fn o ->
      with {:ok, from, _} <- DateTime.from_iso8601(o["starts_at"] || ""),
           {:ok, to, _} <- DateTime.from_iso8601(o["ends_at"] || "") do
        [
          %{
            reservation_id: o["reservation_id"],
            spacecraft_id: o["spacecraft_id"],
            antenna_ref: o["antenna_ref"],
            starts_at: from,
            ends_at: to
          }
        ]
      else
        _invalid -> []
      end
    end)
  end

  defp occupied(_run), do: []

  defp fleet_outcome(%{"coverage_counts" => counts}) when is_map(counts) do
    if counts["satisfied"] == counts["total"],
      do: :completed,
      else: :partial
  end

  defp fleet_outcome(_summary), do: :partial

  defp coverage_counts(coverage) do
    Enum.reduce(
      coverage,
      %{"total" => 0, "satisfied" => 0, "partial" => 0, "unsatisfied" => 0},
      fn {_id, result}, counts ->
        state = result["state"]
        counts |> Map.update!("total", &(&1 + 1)) |> Map.update!(state, &(&1 + 1))
      end
    )
  end

  defp candidate_plan(%{candidate_contact_plan_id: nil}),
    do: {:error, :fleet_planning_candidate_plan_not_linked}

  defp candidate_plan(run) do
    case ContactPlans.fetch(
           run.organization_id,
           run.mission_id,
           run.candidate_contact_plan_id
         ) do
      {:ok, plan, %{version: version} = plan_version}
      when version == run.candidate_contact_plan_version ->
        {:ok, plan, plan_version}

      {:ok, _plan, _version} ->
        {:error, :fleet_planning_candidate_plan_version_changed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp terminal_result(run, plan, version) do
    {:ok, %{run: run, plan: plan, plan_version: version}}
  end

  defp fail_and_return(scope, mission_id, run, code, reason, opts) do
    failure = %{
      "code" => code,
      "reason_code" => reason_code(reason),
      "phase" => Atom.to_string(run.phase)
    }

    case FleetPlanningRuns.fail(
           scope,
           mission_id,
           run.fleet_planning_run_id,
           run.phase,
           failure,
           opts
         ) do
      {:ok, failed} -> terminal_result(failed, nil, nil)
      {:error, fail_reason} -> {:error, fail_reason}
    end
  end

  defp candidate_plan_id(run) do
    digest =
      %{"fleet_planning_run_id" => run.fleet_planning_run_id}
      |> ContentHash.sha256()
      |> binary_part(0, 24)

    "contact_plan_fleet_#{digest}"
  end

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code({reason, _left, _right}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code(_reason), do: "unclassified_failure"

  defp datetime(%DateTime{} = value), do: {:ok, DateTime.truncate(value, :microsecond)}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> {:ok, DateTime.truncate(parsed, :microsecond)}
      _other -> {:error, :fleet_planning_horizon_invalid}
    end
  end

  defp datetime(_value), do: {:error, :fleet_planning_horizon_invalid}

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
