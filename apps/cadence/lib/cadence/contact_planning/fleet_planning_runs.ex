defmodule Cadence.ContactPlanning.FleetPlanningRuns do
  @moduledoc "Authorized durable lifecycle and evidence boundary for fleet planning orchestration."

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.PlanUpdates

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContentHash,
    FleetPlanningDecision,
    FleetPlanningPolicies,
    FleetPlanningRun,
    FleetPlanningRunRequirementRef
  }

  alias Cadence.Management.Contacts.PlanningResults

  alias Cadence.Management.Contacts.Store.{
    ContactRequirementRow,
    ContactRequirementVersionRow,
    FleetPlanningDecisionRow,
    FleetPlanningRunRequirementRefRow,
    FleetPlanningRunRow,
    FleetPlanningScoreDocumentRow
  }

  alias Cadence.Repo

  @algorithm_key "deterministic_bounded_greedy"
  @algorithm_version 1
  # Safety bound, not a planning batch size. A 1,000 spacecraft, 4/day weekly run is 28,000.
  @maximum_requirements 100_000
  @insert_batch_size 500
  @decision_batch_size 4_000
  @coverage_batch_size 2_000
  @document_limit 256 * 1_024

  @spec maximum_requirements() :: pos_integer()
  def maximum_requirements,
    do: Application.get_env(:cadence, :fleet_planning_requirement_limit, @maximum_requirements)

  @spec create(Scope.t(), binary(), map(), keyword()) ::
          {:ok, FleetPlanningRun.t(), [FleetPlanningRunRequirementRef.t()]} | {:error, term()}
  def create(%Scope{} = scope, mission_id, attrs, opts \\ []) do
    create_unpublished(scope, mission_id, attrs, nil, opts)
    |> PlanUpdates.published(scope.organization_id, mission_id)
  end

  @doc "Creates a run from inputs locked and materialized by the reviewed fleet start transaction."
  @spec create_reviewed(Scope.t(), binary(), map(), [{struct(), struct()}]) ::
          {:ok, FleetPlanningRun.t(), [FleetPlanningRunRequirementRef.t()]} | {:error, term()}
  def create_reviewed(%Scope{} = scope, mission_id, attrs, requirements)
      when is_list(requirements) do
    if Repo.in_transaction?() do
      create_unpublished(scope, mission_id, attrs, requirements, [])
      |> PlanUpdates.published(scope.organization_id, mission_id)
    else
      {:error, :fleet_run_transaction_required}
    end
  end

  defp create_unpublished(%Scope{} = scope, mission_id, attrs, provided_requirements, _opts)
       when is_binary(mission_id) and is_map(attrs) do
    with :ok <- authorize_member(scope, mission_id),
         {:ok, _policy, policy_version} <-
           FleetPlanningPolicies.fetch_active(scope.organization_id, mission_id),
         {:ok, horizon_start} <- datetime(value(attrs, :horizon_start)),
         {:ok, horizon_end} <- datetime(value(attrs, :horizon_end)),
         :ok <- validate_horizon(horizon_start, horizon_end, policy_version),
         {:ok, requirements} <-
           requirements_for_run(
             scope.organization_id,
             mission_id,
             horizon_start,
             horizon_end,
             attrs,
             provided_requirements
           ),
         :ok <- require_requirements(requirements),
         {:ok, actor} <- actor(scope),
         {:ok, run} <-
           build_run(
             scope.organization_id,
             mission_id,
             policy_version,
             requirements,
             horizon_start,
             horizon_end,
             actor,
             attrs
           ) do
      persist_run(run, requirements)
    end
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, FleetPlanningRun.t()} | {:error, term()}
  def fetch(organization_id, mission_id, run_id) do
    case Repo.get_by(FleetPlanningRunRow,
           organization_id: organization_id,
           mission_id: mission_id,
           fleet_planning_run_id: run_id
         ) do
      nil -> {:error, :fleet_planning_run_not_found}
      row -> {:ok, FleetPlanningRunRow.to_domain(row)}
    end
  end

  @doc """
  Records the console operation that created a run (DECISIONS #27). Returns
  `{:error, :operation_already_claimed}` when another run in the mission holds
  the same `operation_id`.
  """
  @spec claim_operation(binary(), binary(), binary(), binary()) ::
          :ok | {:error, :operation_already_claimed | term()}
  def claim_operation(organization_id, mission_id, run_id, operation_id) do
    with %FleetPlanningRunRow{} = row <-
           Repo.get_by(FleetPlanningRunRow,
             organization_id: organization_id,
             mission_id: mission_id,
             fleet_planning_run_id: run_id
           ) || {:error, :fleet_planning_run_not_found},
         {:ok, _row} <-
           row |> FleetPlanningRunRow.operation_changeset(operation_id) |> Repo.update() do
      :ok
    else
      {:error, %Ecto.Changeset{}} -> {:error, :operation_already_claimed}
      {:error, _reason} = error -> error
    end
  end

  @spec fetch_by_operation(binary(), binary(), binary()) ::
          {:ok, FleetPlanningRun.t()} | {:error, :fleet_planning_run_not_found}
  def fetch_by_operation(organization_id, mission_id, operation_id) do
    case Repo.get_by(FleetPlanningRunRow,
           organization_id: organization_id,
           mission_id: mission_id,
           operation_id: operation_id
         ) do
      nil -> {:error, :fleet_planning_run_not_found}
      row -> {:ok, FleetPlanningRunRow.to_domain(row)}
    end
  end

  @doc "Locks a scoped run for a short database-only reviewed decision."
  def fetch_locked(organization_id, mission_id, run_id) do
    if Repo.in_transaction?() do
      case lock_run(organization_id, mission_id, run_id) do
        {:ok, row} -> {:ok, FleetPlanningRunRow.to_domain(row)}
        {:error, _} = error -> error
      end
    else
      {:error, :fleet_run_transaction_required}
    end
  end

  @doc """
  Repair runs that proposed the given plans: `%{candidate_plan_id => %{run_id, plan: %{id,
  version}}}`, where `plan` is the plan being repaired (console: a draft that is a repair
  proposal says so).
  """
  @spec repairs_for(binary(), binary(), [binary()]) :: %{binary() => map()}
  def repairs_for(_organization_id, _mission_id, []), do: %{}

  def repairs_for(organization_id, mission_id, plan_ids) do
    FleetPlanningRunRow
    |> where(
      [run],
      run.organization_id == ^organization_id and run.mission_id == ^mission_id and
        run.candidate_contact_plan_id in ^plan_ids and not is_nil(run.source_contact_plan_id)
    )
    |> select(
      [run],
      {run.candidate_contact_plan_id, run.fleet_planning_run_id, run.source_contact_plan_id,
       run.source_contact_plan_version}
    )
    |> Repo.all()
    |> Map.new(fn {candidate, run_id, source, version} ->
      {candidate, %{run_id: run_id, plan: %{id: source, version: version}}}
    end)
  end

  @spec list(binary(), binary(), keyword()) :: [FleetPlanningRun.t()]
  def list(organization_id, mission_id, opts \\ []) do
    FleetPlanningRunRow
    |> where(
      [run],
      run.organization_id == ^organization_id and run.mission_id == ^mission_id
    )
    |> maybe_filter_state(opts[:lifecycle_state])
    |> order_by([run], desc: run.inserted_at, desc: run.fleet_planning_run_id)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> Repo.all()
    |> Enum.map(&FleetPlanningRunRow.to_domain/1)
  end

  @doc "A bounded, mission-scoped run directory with one row of next-page evidence."
  def list_page(organization_id, mission_id, page, state \\ nil)

  def list_page(organization_id, mission_id, page, state)
      when is_integer(page) and page in 1..1_000_000 and
             state in [nil, "queued", "running", "completed", "partial", "failed", "canceled"] do
    rows =
      FleetPlanningRunRow
      |> where([run], run.organization_id == ^organization_id and run.mission_id == ^mission_id)
      |> maybe_filter_state(state)
      |> order_by([run], desc: run.inserted_at, desc: run.fleet_planning_run_id)
      |> offset(^((page - 1) * 25))
      |> limit(26)
      |> Repo.all()

    {:ok,
     %{
       page: page,
       more: length(rows) > 25,
       entries: rows |> Enum.take(25) |> Enum.map(&FleetPlanningRunRow.to_domain/1)
     }}
  end

  def list_page(_, _, _, _), do: {:error, :invalid_fleet_planning_page}

  @spec list_requirement_refs(binary(), binary(), binary()) ::
          [FleetPlanningRunRequirementRef.t()]
  def list_requirement_refs(organization_id, mission_id, run_id) do
    FleetPlanningRunRequirementRefRow
    |> where(
      [ref],
      ref.organization_id == ^organization_id and ref.mission_id == ^mission_id and
        ref.fleet_planning_run_id == ^run_id
    )
    |> order_by([ref], asc: ref.contact_requirement_id, asc: ref.contact_requirement_version)
    |> Repo.all()
    |> Enum.map(&FleetPlanningRunRequirementRefRow.to_domain/1)
  end

  @spec list_decisions(binary(), binary(), binary()) :: [FleetPlanningDecision.t()]
  def list_decisions(organization_id, mission_id, run_id) do
    visible_decisions(organization_id, mission_id, run_id)
    |> with_score_evidence()
    |> order_by([decision],
      asc_nulls_last: decision.rank,
      desc: decision.score,
      asc: decision.contact_opportunity_snapshot_id
    )
    |> Repo.all()
    |> Enum.map(fn {decision, evidence} ->
      FleetPlanningDecisionRow.to_domain(decision, evidence)
    end)
  end

  @spec selected_snapshot_ids(binary(), binary(), binary()) :: {[binary()], [binary()]}
  def selected_snapshot_ids(organization_id, mission_id, run_id) do
    visible_decisions(organization_id, mission_id, run_id)
    |> where([decision], decision.disposition in ["selected", "locked"])
    |> order_by([decision], asc: decision.rank)
    |> select([decision], {decision.disposition, decision.contact_opportunity_snapshot_id})
    |> Repo.all()
    |> Enum.reduce({[], []}, fn
      {"selected", id}, {selected, locked} -> {[id | selected], locked}
      {"locked", id}, {selected, locked} -> {selected, [id | locked]}
    end)
    |> then(fn {selected, locked} -> {Enum.reverse(selected), Enum.reverse(locked)} end)
  end

  @doc "Bounded optimizer decisions in rank, score and snapshot identity order."
  def decisions_page(org, mission, run_id, page) when is_integer(page) and page in 1..1_000_000 do
    query = visible_decisions(org, mission, run_id) |> with_score_evidence()

    rows =
      query
      |> order_by([d],
        asc_nulls_last: d.rank,
        desc: d.score,
        asc: d.contact_opportunity_snapshot_id
      )
      |> offset(^((page - 1) * 10))
      |> limit(11)
      |> Repo.all()

    %{
      page: page,
      more: length(rows) > 10,
      entries:
        rows
        |> Enum.take(10)
        |> Enum.map(fn {decision, evidence} ->
          FleetPlanningDecisionRow.to_domain(decision, evidence)
        end)
    }
  end

  defp with_score_evidence(query) do
    query
    |> join(:inner, [decision, _run], evidence in FleetPlanningScoreDocumentRow,
      on:
        evidence.mission_id == decision.mission_id and
          evidence.score_document_sha256 == decision.score_document_sha256
    )
    |> select([decision, _run, evidence], {decision, evidence})
  end

  defp visible_decisions(organization_id, mission_id, run_id) do
    FleetPlanningDecisionRow
    |> join(:inner, [decision], run in FleetPlanningRunRow,
      on: run.fleet_planning_run_id == decision.fleet_planning_run_id
    )
    |> where(
      [decision, run],
      decision.organization_id == ^organization_id and decision.mission_id == ^mission_id and
        decision.fleet_planning_run_id == ^run_id and
        run.phase in ["materializing_plan", "finished"]
    )
  end

  @spec advance_phase(
          Scope.t(),
          binary(),
          binary(),
          atom(),
          atom(),
          map(),
          keyword()
        ) :: {:ok, FleetPlanningRun.t()} | {:error, term()}
  def advance_phase(
        %Scope{} = scope,
        mission_id,
        run_id,
        expected_phase,
        next_phase,
        attrs \\ %{},
        opts \\ []
      ) do
    advance_phase_unpublished(scope, mission_id, run_id, expected_phase, next_phase, attrs, opts)
    |> PlanUpdates.published(scope.organization_id, mission_id)
  end

  defp advance_phase_unpublished(
         %Scope{} = scope,
         mission_id,
         run_id,
         expected_phase,
         next_phase,
         attrs,
         opts
       )
       when is_atom(expected_phase) and is_atom(next_phase) and is_map(attrs) do
    now = now(opts)

    with :ok <- authorize_member(scope, mission_id),
         :ok <- allowed_phase_transition(expected_phase, next_phase) do
      advance_transaction(
        scope.organization_id,
        mission_id,
        run_id,
        expected_phase,
        next_phase,
        attrs,
        now
      )
    end
  end

  @spec cancel(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, FleetPlanningRun.t()} | {:error, term()}
  def cancel(%Scope{} = scope, mission_id, run_id, reason, opts \\ []) do
    cancel_unpublished(scope, mission_id, run_id, reason, opts)
    |> PlanUpdates.published(scope.organization_id, mission_id)
  end

  defp cancel_unpublished(%Scope{} = scope, mission_id, run_id, reason, opts) do
    reason = reason |> to_string() |> String.trim()
    now = now(opts)

    with :ok <- authorize_member(scope, mission_id),
         :ok <- require_reason(reason) do
      cancel_transaction(scope.organization_id, mission_id, run_id, reason, now)
    end
  end

  @spec fail(Scope.t(), binary(), binary(), atom(), map(), keyword()) ::
          {:ok, FleetPlanningRun.t()} | {:error, term()}
  def fail(%Scope{} = scope, mission_id, run_id, expected_phase, failure_document, opts \\ []) do
    fail_unpublished(scope, mission_id, run_id, expected_phase, failure_document, opts)
    |> PlanUpdates.published(scope.organization_id, mission_id)
  end

  defp fail_unpublished(
         %Scope{} = scope,
         mission_id,
         run_id,
         expected_phase,
         failure_document,
         opts
       )
       when is_atom(expected_phase) and is_map(failure_document) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_member(scope, mission_id),
         :ok <- bounded_document(failure_document, :fleet_planning_run_failure_too_large) do
      fail_transaction(
        scope.organization_id,
        mission_id,
        run_id,
        expected_phase,
        failure_document,
        now
      )
    end
  end

  @spec update_requirement_progress(
          Scope.t(),
          binary(),
          binary(),
          binary(),
          atom(),
          atom(),
          map()
        ) :: {:ok, FleetPlanningRunRequirementRef.t()} | {:error, term()}
  def update_requirement_progress(
        %Scope{} = scope,
        mission_id,
        run_id,
        requirement_id,
        input_state,
        result_state,
        attrs \\ %{}
      )
      when is_atom(input_state) and is_atom(result_state) and is_map(attrs) do
    with :ok <- authorize_member(scope, mission_id) do
      case Repo.get_by(FleetPlanningRunRequirementRefRow,
             organization_id: scope.organization_id,
             mission_id: mission_id,
             fleet_planning_run_id: run_id,
             contact_requirement_id: requirement_id
           ) do
        nil ->
          {:error, :fleet_planning_run_requirement_not_found}

        row ->
          persist_requirement_progress(row, input_state, result_state, attrs)
      end
    end
  end

  @doc false
  def checkpoint_search_batch(%Scope{} = scope, mission_id, run_id, entries) do
    organization_id = scope.organization_id

    with :ok <- authorize_member(scope, mission_id) do
      Repo.transaction(fn ->
        persist_search_batch(organization_id, mission_id, run_id, entries)
      end)
    end
  end

  defp persist_search_batch(organization_id, mission_id, run_id, entries) do
    # Concurrent batches update distinct requirement refs. A phase change waits until they commit.
    case lock_run(organization_id, mission_id, run_id, :shared) do
      {:ok, %{phase: "searching"}} ->
        :ok = PlanningResults.insert_fleet_entries(entries)
        update_search_refs(organization_id, mission_id, run_id, entries)

      {:ok, _run} ->
        Repo.rollback(:fleet_planning_run_phase_mismatch)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp update_search_refs(organization_id, mission_id, run_id, entries) do
    checkpoints = Enum.map(entries, &search_checkpoint(&1.run))

    types = %{
      contact_requirement_id: :string,
      contact_requirement_version: :integer,
      contact_planning_run_id: :string,
      input_state: :string,
      result_state: :string,
      explanation_document: :map
    }

    {count, _} =
      FleetPlanningRunRequirementRefRow
      |> join(:inner, [ref], checkpoint in values(checkpoints, types),
        on:
          ref.contact_requirement_id == checkpoint.contact_requirement_id and
            ref.contact_requirement_version == checkpoint.contact_requirement_version
      )
      |> where(
        [ref],
        ref.organization_id == ^organization_id and ref.mission_id == ^mission_id and
          ref.fleet_planning_run_id == ^run_id and is_nil(ref.contact_planning_run_id)
      )
      |> update([_ref, checkpoint],
        set: [
          contact_planning_run_id: checkpoint.contact_planning_run_id,
          input_state: checkpoint.input_state,
          result_state: checkpoint.result_state,
          explanation_document: checkpoint.explanation_document,
          updated_at: ^DateTime.utc_now()
        ]
      )
      |> Repo.update_all([])

    if count != length(checkpoints), do: Repo.rollback(:fleet_planning_search_checkpoint_changed)
    :ok
  end

  defp search_checkpoint(run) do
    failed? = run.lifecycle_state == :failed

    %{
      contact_requirement_id: run.contact_requirement_id,
      contact_requirement_version: run.contact_requirement_version,
      contact_planning_run_id: run.contact_planning_run_id,
      input_state: if(failed?, do: "failed", else: "searched"),
      result_state: if(failed?, do: "failed", else: "pending"),
      explanation_document: %{
        "code" => if(failed?, do: "stage_4_planning_failed", else: "stage_4_planning_complete"),
        "contact_planning_run_id" => run.contact_planning_run_id,
        "lifecycle_state" => Atom.to_string(run.lifecycle_state),
        "summary" => run.summary_document
      }
    }
  end

  @spec persist_decisions(Scope.t(), binary(), binary(), [map()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def persist_decisions(%Scope{} = scope, mission_id, run_id, decisions)
      when is_list(decisions) do
    with :ok <- authorize_member(scope, mission_id),
         {:ok, run} <- fetch(scope.organization_id, mission_id, run_id),
         :ok <- optimizing_run(run) do
      with :ok <- persist_score_documents(run, decisions) do
        replace_decisions(run, decisions)
      end
    end
  end

  @spec persist_coverage(Scope.t(), binary(), binary(), map()) :: :ok | {:error, term()}
  def persist_coverage(%Scope{} = scope, mission_id, run_id, coverage) when is_map(coverage) do
    with :ok <- authorize_member(scope, mission_id),
         {:ok, run} <- fetch(scope.organization_id, mission_id, run_id),
         :ok <- optimizing_run(run) do
      persist_coverage_rows(run, coverage)
    end
  end

  defp persist_coverage_rows(run, coverage) do
    run.organization_id
    |> list_requirement_refs(run.mission_id, run.fleet_planning_run_id)
    |> Stream.map(&coverage_ref(&1, coverage))
    |> Stream.chunk_every(@coverage_batch_size)
    |> Enum.reduce_while(:ok, fn batch, :ok ->
      rows = Enum.map(batch, &FleetPlanningRunRequirementRefRow.insert_attrs/1)

      {count, _} =
        Repo.insert_all(FleetPlanningRunRequirementRefRow, rows,
          on_conflict:
            {:replace, [:input_state, :result_state, :explanation_document, :updated_at]},
          conflict_target: [:fleet_planning_run_requirement_ref_id]
        )

      if count == length(batch),
        do: {:cont, :ok},
        else: {:halt, {:error, :fleet_planning_coverage_persistence_incomplete}}
    end)
  end

  defp coverage_ref(ref, coverage) do
    result = Map.fetch!(coverage, ref.contact_requirement_id)

    {input_state, result_state} =
      if ref.input_state == :failed,
        do: {:failed, :failed},
        else: {:searched, coverage_state(result["state"])}

    %{
      ref
      | input_state: input_state,
        result_state: result_state,
        explanation_document: Map.put(ref.explanation_document, "coverage", result)
    }
  end

  defp coverage_state("satisfied"), do: :satisfied
  defp coverage_state("partial"), do: :partial
  defp coverage_state("unsatisfied"), do: :unsatisfied

  defp persist_run(run, requirements) do
    Repo.transaction(fn ->
      with {:ok, run_row} <- Repo.insert(FleetPlanningRunRow.changeset(run)),
           {:ok, refs} <- insert_requirement_refs(run, requirements) do
        {FleetPlanningRunRow.to_domain(run_row), refs}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {persisted_run, refs}} -> {:ok, persisted_run, refs}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_requirement_refs(run, requirements) do
    inserted =
      requirements
      |> Stream.chunk_every(@insert_batch_size)
      |> Enum.reduce([], fn batch, acc ->
        refs = requirement_refs_for_batch(run, batch)
        rows = Enum.map(refs, &FleetPlanningRunRequirementRefRow.insert_attrs/1)
        {count, _} = Repo.insert_all(FleetPlanningRunRequirementRefRow, rows)

        if count != length(batch), do: Repo.rollback(:fleet_planning_run_requirement_refs_invalid)

        [refs | acc]
      end)

    {:ok, inserted |> Enum.reverse() |> List.flatten()}
  end

  defp requirement_refs_for_batch(run, requirements) do
    now = DateTime.utc_now()

    Enum.map(requirements, fn {_requirement, version} ->
      FleetPlanningRunRequirementRef.new(%{
        fleet_planning_run_id: run.fleet_planning_run_id,
        organization_id: run.organization_id,
        mission_id: run.mission_id,
        contact_requirement_id: version.contact_requirement_id,
        contact_requirement_version: version.version,
        input_content_sha256: version.content_sha256,
        inserted_at: now,
        updated_at: now
      })
    end)
  end

  defp build_run(
         organization_id,
         mission_id,
         policy,
         requirements,
         horizon_start,
         horizon_end,
         actor,
         attrs
       ) do
    refs =
      Enum.map(requirements, fn {_requirement, version} ->
        {version.contact_requirement_id, version.version, version.content_sha256}
      end)

    run =
      FleetPlanningRun.new(%{
        fleet_planning_run_id:
          value(attrs, :fleet_planning_run_id, Cadence.Ids.new("fleet_planning_run")),
        organization_id: organization_id,
        mission_id: mission_id,
        lifecycle_state: :queued,
        phase: :queued,
        trigger_kind: value(attrs, :trigger_kind, :manual),
        fleet_planning_policy_id: policy.fleet_planning_policy_id,
        fleet_planning_policy_version: policy.version,
        algorithm_key: @algorithm_key,
        algorithm_version: @algorithm_version,
        horizon_start: horizon_start,
        horizon_end: horizon_end,
        source_fleet_planning_run_id: value(attrs, :source_fleet_planning_run_id, nil),
        source_contact_plan_id: value(attrs, :source_contact_plan_id, nil),
        source_contact_plan_version: value(attrs, :source_contact_plan_version, nil),
        input_document:
          creation_input_document(
            %{
              "requirement_count" => length(refs),
              "requirements_sha256" => refs |> Enum.sort() |> ContentHash.sha256(),
              "policy_content_sha256" => policy.content_sha256,
              "template_materialization" => value(attrs, :template_materialization_document, %{}),
              "repair" => value(attrs, :repair_input_document, %{}),
              # DECISIONS #78: live single bookings the run plans around (from its starter).
              "occupied" => value(attrs, :occupied_document, [])
            },
            attrs
          ),
        progress_document: initial_progress(length(refs)),
        result_summary_document: %{},
        failure_document: %{},
        trigger_actor_document: actor,
        triggered_by: actor["id"],
        started_at: nil,
        completed_at: nil
      })

    if document_size(run.input_document) <= @document_limit,
      do: {:ok, run},
      else: {:error, :fleet_planning_run_input_too_large}
  rescue
    error in ArgumentError -> {:error, {:invalid_fleet_planning_run, error.message}}
  end

  defp creation_input_document(document, attrs) do
    case value(attrs, :creation_review_document, nil) do
      nil -> document
      review when is_map(review) -> Map.put(document, "creation_review", review)
    end
  end

  defp requirements_for_run(org, mission, start_at, end_at, _attrs, requirements)
       when is_list(requirements),
       do: validate_claimed_requirements(org, mission, start_at, end_at, requirements)

  defp requirements_for_run(org, mission, start_at, end_at, attrs, nil),
    do: select_requirements(org, mission, start_at, end_at, attrs)

  defp validate_claimed_requirements(org, mission, start_at, end_at, requirements) do
    cond do
      length(requirements) > maximum_requirements() ->
        {:error, :fleet_planning_run_requirement_limit_exceeded}

      Enum.all?(requirements, &valid_claimed_requirement?(&1, org, mission, start_at, end_at)) ->
        {:ok, requirements}

      true ->
        {:error, :fleet_planning_run_requirement_refs_invalid}
    end
  end

  defp valid_claimed_requirement?({r, v}, org, mission, start_at, end_at) do
    r.organization_id == org and r.mission_id == mission and
      r.lifecycle_state == :active and r.current_version == v.version and
      r.contact_requirement_id == v.contact_requirement_id and
      v.organization_id == org and v.mission_id == mission and
      DateTime.before?(v.earliest_start, end_at) and DateTime.after?(v.latest_end, start_at)
  end

  defp valid_claimed_requirement?(_, _, _, _, _), do: false

  defp select_requirements(organization_id, mission_id, horizon_start, horizon_end, attrs) do
    case value(attrs, :requirement_refs, nil) do
      nil ->
        select_active_requirements(organization_id, mission_id, horizon_start, horizon_end)

      refs when is_list(refs) ->
        select_explicit_requirements(organization_id, mission_id, refs)

      _value ->
        {:error, :fleet_planning_run_requirement_refs_invalid}
    end
  end

  defp select_active_requirements(organization_id, mission_id, horizon_start, horizon_end) do
    rows =
      ContactRequirementRow
      |> join(:inner, [r], v in ContactRequirementVersionRow,
        on:
          v.contact_requirement_id == r.contact_requirement_id and
            v.version == r.current_version and v.organization_id == r.organization_id and
            v.mission_id == r.mission_id
      )
      |> where(
        [r, v],
        r.organization_id == ^organization_id and r.mission_id == ^mission_id and
          r.lifecycle_state == "active" and v.earliest_start < ^horizon_end and
          v.latest_end > ^horizon_start
      )
      |> order_by([r, v], asc: v.latest_end, asc: r.contact_requirement_id)
      |> limit(^(maximum_requirements() + 1))
      |> select([r, v], {r, v})
      |> Repo.all()

    if length(rows) > maximum_requirements() do
      {:error, :fleet_planning_run_requirement_limit_exceeded}
    else
      {:ok,
       Enum.map(rows, fn {r, v} ->
         {ContactRequirementRow.to_domain(r), ContactRequirementVersionRow.to_domain(v)}
       end)}
    end
  end

  defp select_explicit_requirements(organization_id, mission_id, refs) do
    with true <- Enum.all?(refs, &is_map/1),
         unique <- Enum.uniq_by(refs, &ref_identity/1),
         :ok <- explicit_limit(unique) do
      fetch_explicit_requirements(organization_id, mission_id, unique)
    else
      false -> {:error, :fleet_planning_run_requirement_refs_invalid}
      error -> error
    end
  end

  defp explicit_limit(refs) do
    if length(refs) > maximum_requirements(),
      do: {:error, :fleet_planning_run_requirement_limit_exceeded},
      else: :ok
  end

  defp ref_identity(ref),
    do: {value(ref, :contact_requirement_id, value(ref, :id, nil)), value(ref, :version, nil)}

  defp fetch_explicit_requirements(organization_id, mission_id, refs) do
    refs
    |> Stream.chunk_every(@insert_batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, selected} ->
      ids = Enum.map(batch, &value(&1, :contact_requirement_id, value(&1, :id, nil)))
      found = ContactRequirements.fetch_many(organization_id, mission_id, ids)

      case select_ref_batch(batch, found) do
        {:ok, rows} -> {:cont, {:ok, [rows | selected]}}
        error -> {:halt, error}
      end
    end)
    |> normalize_selected_requirements()
  end

  defp select_ref_batch(batch, found) do
    Enum.reduce_while(batch, {:ok, []}, fn ref, {:ok, selected} ->
      id = value(ref, :contact_requirement_id, value(ref, :id, nil))
      version = value(ref, :version, nil)

      case Map.get(found, id) do
        {%{lifecycle_state: :active, current_version: ^version} = requirement, current} ->
          {:cont, {:ok, [{requirement, current} | selected]}}

        {%{lifecycle_state: state}, _} when state != :active ->
          {:halt, {:error, :fleet_planning_requirement_not_active}}

        {_, _} ->
          {:halt, {:error, :fleet_planning_requirement_version_changed}}

        nil ->
          {:halt, {:error, :fleet_planning_requirement_not_found}}
      end
    end)
    |> case do
      {:ok, selected} -> {:ok, Enum.reverse(selected)}
      error -> error
    end
  end

  defp normalize_selected_requirements({:ok, selected}) do
    selected =
      selected
      |> Enum.reverse()
      |> List.flatten()
      |> Enum.sort_by(fn {_requirement, version} ->
        {version.latest_end, version.contact_requirement_id}
      end)

    {:ok, selected}
  end

  defp normalize_selected_requirements({:error, reason}), do: {:error, reason}

  defp validate_horizon(start_at, end_at, policy) do
    duration = DateTime.diff(end_at, start_at, :second)

    cond do
      duration <= 0 ->
        {:error, :fleet_planning_horizon_invalid}

      duration > policy.horizon_document["max_horizon_seconds"] ->
        {:error, :fleet_planning_horizon_exceeds_policy}

      true ->
        :ok
    end
  end

  defp require_requirements([]), do: {:error, :fleet_planning_run_has_no_requirements}
  defp require_requirements(_requirements), do: :ok

  defp persist_requirement_progress(row, input_state, result_state, attrs) do
    row
    |> FleetPlanningRunRequirementRefRow.progress_changeset(%{
      contact_planning_run_id:
        value(attrs, :contact_planning_run_id, row.contact_planning_run_id),
      input_state: Atom.to_string(input_state),
      result_state: Atom.to_string(result_state),
      explanation_document: value(attrs, :explanation_document, row.explanation_document)
    })
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, FleetPlanningRunRequirementRefRow.to_domain(updated)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_score_documents(run, decisions) do
    result =
      Enum.reduce_while(decisions, {:ok, %{}}, fn decision, {:ok, documents} ->
        document = Map.fetch!(decision, :score_document)

        sha256 =
          Map.get(decision, :score_document_sha256) || ContentHash.sha256(document)

        case Map.fetch(documents, sha256) do
          :error -> {:cont, {:ok, Map.put(documents, sha256, document)}}
          {:ok, ^document} -> {:cont, {:ok, documents}}
          {:ok, _other} -> {:halt, {:error, :fleet_planning_score_document_hash_collision}}
        end
      end)

    with {:ok, documents} <- result,
         true <-
           Enum.all?(documents, fn {sha256, document} ->
             ContentHash.sha256(document) == sha256
           end) do
      documents
      |> Enum.map(fn {sha256, document} ->
        FleetPlanningScoreDocumentRow.insert_attrs(
          document,
          sha256,
          run.organization_id,
          run.mission_id
        )
      end)
      |> Enum.chunk_every(@decision_batch_size)
      |> Enum.each(fn rows ->
        Repo.insert_all(FleetPlanningScoreDocumentRow, rows,
          on_conflict: :nothing,
          conflict_target: [:mission_id, :score_document_sha256]
        )
      end)

      :ok
    else
      false -> {:error, :fleet_planning_score_document_hash_invalid}
      error -> error
    end
  end

  defp replace_decisions(run, decisions) do
    clear_decisions(run.fleet_planning_run_id)

    result =
      decisions
      |> Stream.chunk_every(@decision_batch_size)
      |> Task.async_stream(
        fn batch ->
          rows = Enum.map(batch, &decision_insert_attrs(&1, run))
          {count, _} = Repo.insert_all(FleetPlanningDecisionRow, rows)

          if count == length(batch),
            do: {:ok, count},
            else: {:error, :fleet_planning_decisions_invalid}
        end,
        max_concurrency: 4,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.reduce_while({:ok, 0}, fn
        {:ok, {:ok, count}}, {:ok, total} -> {:cont, {:ok, total + count}}
        {:ok, {:error, reason}}, _total -> {:halt, {:error, reason}}
        {:exit, reason}, _total -> {:halt, {:error, reason}}
      end)

    case result do
      {:ok, _count} ->
        result

      {:error, _reason} ->
        clear_decisions(run.fleet_planning_run_id)
        result
    end
  rescue
    error in ArgumentError ->
      clear_decisions(run.fleet_planning_run_id)
      {:error, {:invalid_fleet_planning_decision, error.message}}

    error ->
      clear_decisions(run.fleet_planning_run_id)
      reraise error, __STACKTRACE__
  end

  defp clear_decisions(run_id) do
    FleetPlanningDecisionRow
    |> where([decision], decision.fleet_planning_run_id == ^run_id)
    |> Repo.delete_all()
  end

  defp decision_insert_attrs(attrs, run) do
    sha256 =
      Map.get(attrs, :score_document_sha256) ||
        ContentHash.sha256(Map.fetch!(attrs, :score_document))

    attrs
    |> Map.put(:fleet_planning_run_id, run.fleet_planning_run_id)
    |> Map.put(:organization_id, run.organization_id)
    |> Map.put(:mission_id, run.mission_id)
    |> FleetPlanningDecision.new()
    |> FleetPlanningDecisionRow.insert_attrs(sha256)
  end

  defp advance_transaction(
         organization_id,
         mission_id,
         run_id,
         expected_phase,
         next_phase,
         attrs,
         now
       ) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_run(organization_id, mission_id, run_id),
           {:ok, result} <- advance_locked(row, expected_phase, next_phase, attrs, now) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_single_result()
  end

  defp cancel_transaction(organization_id, mission_id, run_id, reason, now) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_run(organization_id, mission_id, run_id),
           :ok <- cancelable(row),
           {:ok, updated} <-
             update_run(row, %{
               lifecycle_state: "canceled",
               phase: "finished",
               progress_document: row.progress_document,
               result_summary_document: row.result_summary_document,
               failure_document: %{"code" => "operator_canceled", "reason" => reason},
               completed_at: now
             }) do
        FleetPlanningRunRow.to_domain(updated)
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> normalize_single_result()
  end

  defp fail_transaction(
         organization_id,
         mission_id,
         run_id,
         expected_phase,
         failure_document,
         now
       ) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_run(organization_id, mission_id, run_id),
           {:ok, failed} <- fail_locked(row, expected_phase, failure_document, now) do
        failed
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_single_result()
  end

  defp advance_locked(row, expected, next, attrs, now) do
    cond do
      row.phase == Atom.to_string(next) ->
        {:ok, FleetPlanningRunRow.to_domain(row)}

      row.phase != Atom.to_string(expected) ->
        {:error, :stale_fleet_planning_run_phase}

      row.lifecycle_state in ["completed", "partial", "failed", "canceled"] ->
        {:error, :fleet_planning_run_terminal}

      true ->
        lifecycle_state = phase_lifecycle(next, attrs)

        row
        |> update_run(%{
          lifecycle_state: Atom.to_string(lifecycle_state),
          phase: Atom.to_string(next),
          progress_document: value(attrs, :progress_document, row.progress_document),
          result_summary_document:
            value(attrs, :result_summary_document, row.result_summary_document),
          failure_document: value(attrs, :failure_document, row.failure_document),
          candidate_contact_plan_id:
            value(attrs, :candidate_contact_plan_id, row.candidate_contact_plan_id),
          candidate_contact_plan_version:
            value(attrs, :candidate_contact_plan_version, row.candidate_contact_plan_version),
          started_at: row.started_at || now,
          completed_at: if(next == :finished, do: now, else: row.completed_at)
        })
        |> case do
          {:ok, updated} -> {:ok, FleetPlanningRunRow.to_domain(updated)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp phase_lifecycle(:finished, attrs) do
    case value(attrs, :outcome, :completed) do
      outcome when outcome in [:completed, :partial, :failed] -> outcome
      _outcome -> :failed
    end
  end

  defp phase_lifecycle(_phase, _attrs), do: :running

  defp fail_locked(%FleetPlanningRunRow{lifecycle_state: "failed"} = row, _phase, _failure, _now),
    do: {:ok, FleetPlanningRunRow.to_domain(row)}

  defp fail_locked(
         %FleetPlanningRunRow{lifecycle_state: state},
         _phase,
         _failure,
         _now
       )
       when state in ["completed", "partial", "canceled"],
       do: {:error, :fleet_planning_run_terminal}

  defp fail_locked(row, expected_phase, failure_document, now) do
    if row.phase == Atom.to_string(expected_phase) do
      row
      |> update_run(%{
        lifecycle_state: "failed",
        phase: "finished",
        progress_document: row.progress_document,
        result_summary_document: row.result_summary_document,
        failure_document: failure_document,
        completed_at: now
      })
      |> case do
        {:ok, updated} -> {:ok, FleetPlanningRunRow.to_domain(updated)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :stale_fleet_planning_run_phase}
    end
  end

  defp allowed_phase_transition(:queued, :materializing), do: :ok
  defp allowed_phase_transition(:materializing, :searching), do: :ok
  defp allowed_phase_transition(:searching, :optimizing), do: :ok
  defp allowed_phase_transition(:optimizing, :materializing_plan), do: :ok
  defp allowed_phase_transition(:materializing_plan, :finished), do: :ok
  defp allowed_phase_transition(_expected, _next), do: {:error, :invalid_fleet_planning_phase}

  defp optimizing_run(%FleetPlanningRun{phase: :optimizing}), do: :ok
  defp optimizing_run(_run), do: {:error, :fleet_planning_run_not_optimizing}

  defp cancelable(%FleetPlanningRunRow{lifecycle_state: state})
       when state in ["queued", "running"],
       do: :ok

  defp cancelable(_row), do: {:error, :fleet_planning_run_terminal}

  defp update_run(row, attrs),
    do: row |> FleetPlanningRunRow.projection_changeset(attrs) |> Repo.update()

  defp lock_run(organization_id, mission_id, run_id, mode \\ :exclusive) do
    case FleetPlanningRunRow
         |> where(
           [run],
           run.organization_id == ^organization_id and run.mission_id == ^mission_id and
             run.fleet_planning_run_id == ^run_id
         )
         |> lock_fleet_run(mode)
         |> Repo.one() do
      nil -> {:error, :fleet_planning_run_not_found}
      row -> {:ok, row}
    end
  end

  defp lock_fleet_run(query, :shared), do: lock(query, "FOR SHARE")
  defp lock_fleet_run(query, :exclusive), do: lock(query, "FOR UPDATE")

  defp initial_progress(requirement_count) do
    %{
      "requirements_total" => requirement_count,
      "requirements_searched" => 0,
      "requirements_failed" => 0,
      "snapshots_considered" => 0,
      "snapshots_selected" => 0
    }
  end

  defp actor(%Scope{actor_kind: :user, user: user}) do
    {:ok,
     %{
       "kind" => "user",
       "id" => user.user_id,
       "display_name" => user.display_name
     }}
  end

  defp actor(%Scope{actor_kind: :service, service_identity: identity}) do
    {:ok,
     %{
       "kind" => "service",
       "id" => identity.service_identity_id,
       "display_name" => identity.display_name
     }}
  end

  defp actor(%Scope{}), do: {:error, :authenticated_actor_required}

  defp authorize_member(scope, mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp maybe_filter_state(query, nil), do: query

  defp maybe_filter_state(query, state)
       when state in [:queued, :running, :completed, :partial, :failed, :canceled],
       do: where(query, [run], run.lifecycle_state == ^Atom.to_string(state))

  defp maybe_filter_state(query, state)
       when state in ~w(queued running completed partial failed canceled),
       do: where(query, [run], run.lifecycle_state == ^state)

  defp require_reason(""), do: {:error, :fleet_planning_run_cancel_reason_required}
  defp require_reason(_reason), do: :ok

  defp datetime(%DateTime{} = value), do: {:ok, DateTime.truncate(value, :microsecond)}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> {:ok, DateTime.truncate(parsed, :microsecond)}
      _other -> {:error, :fleet_planning_horizon_invalid}
    end
  end

  defp datetime(_value), do: {:error, :fleet_planning_horizon_invalid}

  defp normalize_single_result({:ok, run}), do: {:ok, run}
  defp normalize_single_result({:error, reason}), do: {:error, reason}

  defp document_size(document),
    do: document |> :erlang.term_to_binary([:deterministic]) |> byte_size()

  defp bounded_document(document, error) do
    if document_size(document) <= @document_limit, do: :ok, else: {:error, error}
  end

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
