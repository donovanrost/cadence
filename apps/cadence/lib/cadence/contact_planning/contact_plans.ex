defmodule Cadence.ContactPlanning.ContactPlans do
  @moduledoc "Authorized persistence boundary for immutable Contact Plan proposals."

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    ContactPlan,
    ContactPlanVersion,
    PolicyNarrowing,
    RequirementEvaluator
  }

  alias Cadence.Missions

  alias Cadence.Management.Contacts.Store.ContactOpportunitySnapshotRow
  alias Cadence.Management.Contacts.Store.ContactPlanApprovalRow
  alias Cadence.Management.Contacts.Store.ContactPlanningRunRow
  alias Cadence.Management.Contacts.Store.ContactPlanningSearchRow
  alias Cadence.Management.Contacts.Store.ContactPlanOpportunityRefRow
  alias Cadence.Management.Contacts.Store.ContactPlanRequirementRefRow
  alias Cadence.Management.Contacts.Store.ContactPlanRow
  alias Cadence.Management.Contacts.Store.ContactPlanRunRefRow
  alias Cadence.Management.Contacts.Store.ContactPlanVersionRow
  alias Cadence.Management.Contacts.Store.ContactRequirementVersionRow

  alias Cadence.Repo

  @spec create(Scope.t(), binary(), map(), keyword()) ::
          {:ok, ContactPlan.t(), ContactPlanVersion.t()} | {:error, term()}
  def create(%Scope{} = current_scope, mission_id, attrs, opts \\ [])
      when is_binary(mission_id) and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_member(current_scope, mission_id),
         {:ok, _mission} <- Missions.fetch_mission(current_scope.organization_id, mission_id),
         {:ok, actor_id} <- actor_id(current_scope),
         {:ok, proposal} <-
           build_proposal(current_scope.organization_id, mission_id, attrs, nil),
         plan_id <- value(attrs, :contact_plan_id, Cadence.Ids.new("contact_plan")),
         {:ok, version} <-
           build_version(plan_id, 1, actor_id, now, proposal),
         plan <-
           ContactPlan.new(%{
             contact_plan_id: plan_id,
             organization_id: current_scope.organization_id,
             mission_id: mission_id,
             current_version: 1,
             lifecycle_state: :draft,
             created_by: actor_id,
             lifecycle_changed_by: actor_id,
             lifecycle_changed_at: now,
             lifecycle_reason: "created"
           }) do
      persist_new_plan(plan, version, proposal)
    end
  rescue
    error in ArgumentError -> {:error, {:invalid_contact_plan, error.message}}
  end

  @spec version(Scope.t(), binary(), binary(), pos_integer(), map(), keyword()) ::
          {:ok, ContactPlan.t(), ContactPlanVersion.t()} | {:error, term()}
  def version(
        %Scope{} = current_scope,
        mission_id,
        plan_id,
        expected_version,
        attrs,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(plan_id) and is_integer(expected_version) and
             expected_version > 0 and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_member(current_scope, mission_id),
         {:ok, _mission} <- Missions.fetch_mission(current_scope.organization_id, mission_id),
         {:ok, actor_id} <- actor_id(current_scope) do
      Repo.transaction(fn ->
        version_transaction(
          current_scope.organization_id,
          mission_id,
          plan_id,
          expected_version,
          attrs,
          actor_id,
          now
        )
      end)
      |> normalize_pair_result()
    end
  rescue
    error in ArgumentError -> {:error, {:invalid_contact_plan, error.message}}
  end

  @spec submit(Scope.t(), binary(), binary(), pos_integer(), binary(), keyword()) ::
          {:ok, ContactPlan.t()} | {:error, term()}
  def submit(current_scope, mission_id, plan_id, expected_version, reason, opts \\ []) do
    transition_to_pending(
      current_scope,
      mission_id,
      plan_id,
      expected_version,
      reason,
      opts
    )
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, ContactPlan.t(), ContactPlanVersion.t()} | {:error, term()}
  def fetch(organization_id, mission_id, plan_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(plan_id) do
    case Repo.get_by(ContactPlanRow,
           organization_id: organization_id,
           mission_id: mission_id,
           contact_plan_id: plan_id
         ) do
      nil ->
        {:error, :contact_plan_not_found}

      row ->
        with {:ok, version} <-
               fetch_version(organization_id, mission_id, plan_id, row.current_version) do
          {:ok, ContactPlanRow.to_domain(row), version}
        end
    end
  end

  @spec fetch_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, ContactPlanVersion.t()} | {:error, term()}
  def fetch_version(organization_id, mission_id, plan_id, version) do
    case Repo.get_by(ContactPlanVersionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           contact_plan_id: plan_id,
           version: version
         ) do
      nil -> {:error, :contact_plan_version_not_found}
      row -> {:ok, ContactPlanVersionRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) :: [{ContactPlan.t(), ContactPlanVersion.t()}]
  def list(organization_id, mission_id, opts \\ []) do
    ContactPlanRow
    |> join(:inner, [plan], version in ContactPlanVersionRow,
      on:
        version.organization_id == plan.organization_id and
          version.mission_id == plan.mission_id and
          version.contact_plan_id == plan.contact_plan_id and
          version.version == plan.current_version
    )
    |> where(
      [plan],
      plan.organization_id == ^organization_id and plan.mission_id == ^mission_id
    )
    |> maybe_filter_lifecycle(opts[:lifecycle_state])
    |> order_by([plan], desc: plan.updated_at, asc: plan.contact_plan_id)
    |> select([plan, version], {plan, version})
    |> Repo.all()
    |> Enum.map(fn {plan, version} ->
      {ContactPlanRow.to_domain(plan), ContactPlanVersionRow.to_domain(version)}
    end)
  end

  @spec list_versions(binary(), binary(), binary()) :: [ContactPlanVersion.t()]
  def list_versions(organization_id, mission_id, plan_id) do
    ContactPlanVersionRow
    |> where(
      [version],
      version.organization_id == ^organization_id and version.mission_id == ^mission_id and
        version.contact_plan_id == ^plan_id
    )
    |> order_by([version], desc: version.version)
    |> Repo.all()
    |> Enum.map(&ContactPlanVersionRow.to_domain/1)
  end

  @spec selected_snapshots(binary(), binary(), binary(), pos_integer()) :: [struct()]
  def selected_snapshots(organization_id, mission_id, plan_id, version) do
    ContactPlanOpportunityRefRow
    |> join(:inner, [ref], snapshot in ContactOpportunitySnapshotRow,
      on: snapshot.contact_opportunity_snapshot_id == ref.contact_opportunity_snapshot_id
    )
    |> where(
      [ref],
      ref.organization_id == ^organization_id and ref.mission_id == ^mission_id and
        ref.contact_plan_id == ^plan_id and ref.contact_plan_version == ^version and
        ref.disposition in ["selected", "locked"]
    )
    |> order_by([ref], asc: ref.selection_order)
    |> select([_ref, snapshot], snapshot)
    |> Repo.all()
    |> Enum.map(&ContactOpportunitySnapshotRow.to_domain/1)
  end

  @spec bookable_snapshots(binary(), binary(), binary(), pos_integer()) :: [struct()]
  def bookable_snapshots(organization_id, mission_id, plan_id, version) do
    ContactPlanOpportunityRefRow
    |> join(:inner, [ref], snapshot in ContactOpportunitySnapshotRow,
      on: snapshot.contact_opportunity_snapshot_id == ref.contact_opportunity_snapshot_id
    )
    |> where(
      [ref],
      ref.organization_id == ^organization_id and ref.mission_id == ^mission_id and
        ref.contact_plan_id == ^plan_id and ref.contact_plan_version == ^version and
        ref.disposition == "selected"
    )
    |> order_by([ref], asc: ref.selection_order)
    |> select([_ref, snapshot], snapshot)
    |> Repo.all()
    |> Enum.map(&ContactOpportunitySnapshotRow.to_domain/1)
  end

  @spec fetch_opportunity_snapshot(binary(), binary(), binary()) ::
          {:ok, struct()} | {:error, :contact_opportunity_snapshot_not_found}
  def fetch_opportunity_snapshot(organization_id, mission_id, snapshot_id) do
    case Repo.get_by(ContactOpportunitySnapshotRow,
           organization_id: organization_id,
           mission_id: mission_id,
           contact_opportunity_snapshot_id: snapshot_id
         ) do
      nil -> {:error, :contact_opportunity_snapshot_not_found}
      row -> {:ok, ContactOpportunitySnapshotRow.to_domain(row)}
    end
  end

  @doc false
  @spec start_execution_projection(binary(), binary(), binary(), DateTime.t()) ::
          {:ok, ContactPlan.t()} | {:error, term()}
  def start_execution_projection(organization_id, mission_id, plan_id, %DateTime{} = now) do
    Repo.transaction(fn ->
      case lock_plan(organization_id, mission_id, plan_id) do
        {:ok, %ContactPlanRow{lifecycle_state: "reserved"} = row} ->
          ContactPlanRow.to_domain(row)

        {:ok, %ContactPlanRow{lifecycle_state: state} = row}
        when state in ["approved", "executing", "partially_reserved", "failed"] ->
          advance_execution_projection(row, now)

        {:ok, _row} ->
          Repo.rollback(:contact_plan_not_executable)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> normalize_single_result()
  end

  @doc false
  @spec update_execution_projection(
          binary(),
          binary(),
          binary(),
          pos_integer(),
          atom(),
          binary(),
          DateTime.t()
        ) :: {:ok, ContactPlan.t()} | {:error, term()}
  def update_execution_projection(
        organization_id,
        mission_id,
        plan_id,
        plan_version,
        state,
        reason,
        %DateTime{} = now
      ) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_plan(organization_id, mission_id, plan_id),
           true <- row.approved_version == plan_version,
           {:ok, updated} <-
             row
             |> ContactPlanRow.projection_changeset(%{
               current_version: row.current_version,
               lifecycle_state: Atom.to_string(state),
               lifecycle_changed_by: row.approved_by,
               lifecycle_changed_at: now,
               lifecycle_reason: reason,
               approved_version: row.approved_version,
               approved_at: row.approved_at,
               approved_by: row.approved_by
             })
             |> Repo.update() do
        ContactPlanRow.to_domain(updated)
      else
        false -> Repo.rollback(:contact_plan_approved_version_changed)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_single_result()
  end

  defp build_proposal(organization_id, mission_id, attrs, previous) do
    with {:ok, run_ids} <- proposal_list(attrs, :planning_run_ids, previous_run_ids(previous)),
         :ok <- require_nonempty(run_ids, :planning_run_ids),
         {:ok, selected_ids} <-
           proposal_list(attrs, :selected_snapshot_ids, previous_selected_ids(previous)),
         {:ok, locked_ids} <-
           proposal_list(attrs, :locked_snapshot_ids, previous_locked_ids(previous)),
         :ok <- disjoint_snapshot_ids(selected_ids, locked_ids),
         {:ok, runs} <- fetch_runs(organization_id, mission_id, run_ids),
         :ok <- completed_runs(runs),
         requirement_refs <- requirement_refs(runs),
         {:ok, requirements} <- fetch_requirements(organization_id, mission_id, requirement_refs),
         {:ok, snapshots} <- fetch_snapshots(organization_id, mission_id, run_ids),
         :ok <- selected_belongs(selected_ids ++ locked_ids, snapshots),
         selected <- select_snapshots(snapshots, selected_ids),
         locked <- select_snapshots(snapshots, locked_ids),
         commitments <- selected ++ locked,
         :ok <- eligible_selected(commitments),
         searches <- fetch_searches(organization_id, mission_id, run_ids),
         coverage <- coverage(requirements, commitments, searches, runs),
         conflicts <- conflicts(commitments),
         rejected <- reject_snapshots(snapshots, selected_ids ++ locked_ids),
         rationale <- proposal_rationale(attrs, previous),
         {:ok, policy} <- policy_snapshot(requirements, commitments) do
      {:ok,
       %{
         run_ids: run_ids,
         requirement_refs: requirement_refs,
         requirements: requirements,
         selected: selected,
         locked: locked,
         rejected: rejected,
         coverage: coverage,
         conflicts: conflicts,
         unsatisfied: unsatisfied(coverage, conflicts),
         policy: policy,
         rationale: rationale
       }}
    end
  end

  defp build_version(plan_id, version, actor_id, created_at, proposal) do
    requirement_refs_document = %{"requirements" => proposal.requirement_refs}
    planning_run_refs_document = %{"runs" => proposal.run_ids}

    {:ok,
     ContactPlanVersion.new(%{
       contact_plan_id: plan_id,
       organization_id: hd(proposal.requirements).organization_id,
       mission_id: hd(proposal.requirements).mission_id,
       version: version,
       requirement_refs_document: requirement_refs_document,
       planning_run_refs_document: planning_run_refs_document,
       selected_snapshot_ids: Enum.map(proposal.selected, & &1.contact_opportunity_snapshot_id),
       locked_snapshot_ids: Enum.map(proposal.locked, & &1.contact_opportunity_snapshot_id),
       rejected_snapshot_ids: Enum.map(proposal.rejected, & &1.contact_opportunity_snapshot_id),
       coverage_document: proposal.coverage,
       conflict_document: proposal.conflicts,
       unsatisfied_document: proposal.unsatisfied,
       policy_snapshot_document: proposal.policy,
       rationale: proposal.rationale,
       created_by: actor_id,
       created_at: created_at
     })}
  end

  defp insert_refs(version, proposal) do
    base = %{
      organization_id: version.organization_id,
      mission_id: version.mission_id,
      contact_plan_id: version.contact_plan_id,
      contact_plan_version: version.version
    }

    requirement_results =
      Enum.map(proposal.requirement_refs, fn ref ->
        base
        |> Map.merge(%{
          contact_plan_requirement_ref_id: Cadence.Ids.new("contact_plan_requirement_ref"),
          contact_requirement_id: ref["id"],
          contact_requirement_version: ref["version"]
        })
        |> ContactPlanRequirementRefRow.changeset()
        |> Repo.insert()
      end)

    run_results =
      Enum.map(proposal.run_ids, fn run_id ->
        base
        |> Map.merge(%{
          contact_plan_run_ref_id: Cadence.Ids.new("contact_plan_run_ref"),
          contact_planning_run_id: run_id
        })
        |> ContactPlanRunRefRow.changeset()
        |> Repo.insert()
      end)

    opportunity_results =
      proposal.selected
      |> Enum.map(&{&1, "selected"})
      |> Kernel.++(Enum.map(proposal.locked, &{&1, "locked"}))
      |> Kernel.++(Enum.map(proposal.rejected, &{&1, "rejected"}))
      |> Enum.with_index()
      |> Enum.map(fn {{snapshot, disposition}, index} ->
        base
        |> Map.merge(%{
          contact_plan_opportunity_ref_id: Cadence.Ids.new("contact_plan_opportunity_ref"),
          contact_opportunity_snapshot_id: snapshot.contact_opportunity_snapshot_id,
          disposition: disposition,
          selection_order: index,
          reason_document: reference_reason(snapshot, disposition)
        })
        |> ContactPlanOpportunityRefRow.changeset()
        |> Repo.insert()
      end)

    case Enum.find(
           requirement_results ++ run_results ++ opportunity_results,
           &match?({:error, _}, &1)
         ) do
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp reference_reason(snapshot, "selected"),
    do: %{
      "eligible" => snapshot.eligible,
      "warnings" => snapshot.evaluation_document["warnings"] || []
    }

  defp reference_reason(snapshot, "locked"),
    do: %{
      "eligible" => snapshot.eligible,
      "reason" => "existing_successful_or_uncertain_commitment"
    }

  defp reference_reason(snapshot, "rejected"), do: snapshot.evaluation_document

  defp persist_new_plan(plan, version, proposal) do
    Repo.transaction(fn ->
      with {:ok, plan_row} <- Repo.insert(ContactPlanRow.changeset(plan)),
           {:ok, version_row} <- Repo.insert(ContactPlanVersionRow.changeset(version)),
           :ok <- insert_refs(version, proposal) do
        {ContactPlanRow.to_domain(plan_row), ContactPlanVersionRow.to_domain(version_row)}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_pair_result()
  end

  defp version_transaction(
         organization_id,
         mission_id,
         plan_id,
         expected_version,
         attrs,
         actor_id,
         now
       ) do
    with {:ok, row} <- lock_plan(organization_id, mission_id, plan_id),
         :ok <- editable_plan(row),
         :ok <- expected_version(row, expected_version),
         {:ok, current} <- fetch_version_row(row, row.current_version),
         previous <- ContactPlanVersionRow.to_domain(current),
         {:ok, proposal} <- build_proposal(organization_id, mission_id, attrs, previous),
         {:ok, next_version} <-
           build_version(plan_id, row.current_version + 1, actor_id, now, proposal),
         {:ok, version_row} <- Repo.insert(ContactPlanVersionRow.changeset(next_version)),
         :ok <- insert_refs(next_version, proposal),
         {:ok, updated_row} <- update_current_version(row, next_version, actor_id, now) do
      {ContactPlanRow.to_domain(updated_row), ContactPlanVersionRow.to_domain(version_row)}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp update_current_version(row, next_version, actor_id, now) do
    row
    |> ContactPlanRow.projection_changeset(%{
      current_version: next_version.version,
      lifecycle_state: "draft",
      lifecycle_changed_by: actor_id,
      lifecycle_changed_at: now,
      lifecycle_reason: "versioned",
      approved_version: nil,
      approved_at: nil,
      approved_by: nil
    })
    |> Repo.update()
  end

  defp transition_to_pending(
         %Scope{} = current_scope,
         mission_id,
         plan_id,
         expected_version,
         reason,
         opts
       ) do
    now = now(opts)
    reason = reason |> to_string() |> String.trim()

    with :ok <- authorize_submit(current_scope, mission_id, opts),
         {:ok, actor_id} <- actor_id(current_scope),
         :ok <- require_reason(reason) do
      Repo.transaction(fn ->
        submit_transaction(
          current_scope.organization_id,
          mission_id,
          plan_id,
          expected_version,
          reason,
          actor_id,
          now
        )
      end)
      |> normalize_single_result()
    end
  end

  defp submit_transaction(
         organization_id,
         mission_id,
         plan_id,
         expected_version,
         reason,
         actor_id,
         now
       ) do
    with {:ok, row} <- lock_plan(organization_id, mission_id, plan_id),
         :ok <- draft_plan(row),
         :ok <- expected_version(row, expected_version),
         :ok <- undecided_version(row),
         {:ok, updated} <- update_pending_plan(row, reason, actor_id, now) do
      ContactPlanRow.to_domain(updated)
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update_pending_plan(row, reason, actor_id, now) do
    row
    |> ContactPlanRow.projection_changeset(%{
      current_version: row.current_version,
      lifecycle_state: "pending_approval",
      lifecycle_changed_by: actor_id,
      lifecycle_changed_at: now,
      lifecycle_reason: reason,
      approved_version: nil,
      approved_at: nil,
      approved_by: nil
    })
    |> Repo.update()
  end

  defp fetch_runs(organization_id, mission_id, run_ids) do
    runs =
      ContactPlanningRunRow
      |> where(
        [run],
        run.organization_id == ^organization_id and run.mission_id == ^mission_id and
          run.contact_planning_run_id in ^run_ids
      )
      |> Repo.all()

    if length(runs) == length(run_ids),
      do: {:ok, Enum.sort_by(runs, & &1.contact_planning_run_id)},
      else: {:error, :contact_plan_planning_run_not_found}
  end

  defp fetch_requirements(organization_id, mission_id, refs) do
    required_keys = MapSet.new(refs, &{&1["id"], &1["version"]})
    requirement_ids = refs |> Enum.map(& &1["id"]) |> Enum.uniq()

    requirements =
      ContactRequirementVersionRow
      |> where(
        [version],
        version.organization_id == ^organization_id and version.mission_id == ^mission_id and
          version.contact_requirement_id in ^requirement_ids
      )
      |> Repo.all()
      |> Enum.map(&ContactRequirementVersionRow.to_domain/1)
      |> Enum.filter(&MapSet.member?(required_keys, {&1.contact_requirement_id, &1.version}))
      |> Enum.sort_by(&{&1.contact_requirement_id, &1.version})

    if length(requirements) == MapSet.size(required_keys),
      do: {:ok, requirements},
      else: {:error, :contact_plan_requirement_version_not_found}
  end

  defp fetch_snapshots(organization_id, mission_id, run_ids) do
    snapshots =
      ContactOpportunitySnapshotRow
      |> where(
        [snapshot],
        snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
          snapshot.contact_planning_run_id in ^run_ids
      )
      |> order_by([snapshot],
        asc: snapshot.starts_at,
        asc: snapshot.contact_opportunity_snapshot_id
      )
      |> Repo.all()
      |> Enum.map(&ContactOpportunitySnapshotRow.to_domain/1)

    {:ok, snapshots}
  end

  defp fetch_searches(organization_id, mission_id, run_ids) do
    ContactPlanningSearchRow
    |> where(
      [search],
      search.organization_id == ^organization_id and search.mission_id == ^mission_id and
        search.contact_planning_run_id in ^run_ids
    )
    |> order_by([search], asc: search.route_key)
    |> Repo.all()
    |> Enum.map(&ContactPlanningSearchRow.to_domain/1)
  end

  defp requirement_refs(runs) do
    runs
    |> Enum.map(fn run ->
      %{"id" => run.contact_requirement_id, "version" => run.contact_requirement_version}
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1["id"], &1["version"]})
  end

  defp coverage(requirements, selected, searches, runs) do
    selected_by_requirement =
      Enum.group_by(selected, &{&1.contact_requirement_id, &1.contact_requirement_version})

    searches_by_run = Enum.group_by(searches, & &1.contact_planning_run_id)

    run_ids_by_requirement =
      Enum.group_by(
        runs,
        &{&1.contact_requirement_id, &1.contact_requirement_version},
        & &1.contact_planning_run_id
      )

    evaluations =
      requirements
      |> Enum.map(fn requirement ->
        key = {requirement.contact_requirement_id, requirement.version}
        snapshots = Map.get(selected_by_requirement, key, [])

        requirement_searches =
          run_ids_by_requirement
          |> Map.get(key, [])
          |> Enum.flat_map(&Map.get(searches_by_run, &1, []))

        evaluation =
          RequirementEvaluator.evaluate_selection(requirement, snapshots, requirement_searches)

        Map.merge(evaluation, %{
          "contact_requirement_id" => requirement.contact_requirement_id,
          "contact_requirement_version" => requirement.version
        })
      end)

    %{
      "requirements" => evaluations,
      "satisfied" => Enum.all?(evaluations, & &1["satisfied"])
    }
  end

  defp conflicts(snapshots) do
    items =
      snapshots
      |> Enum.group_by(& &1.route_binding_document["spacecraft_id"])
      |> Enum.flat_map(fn {spacecraft_id, spacecraft_snapshots} ->
        spacecraft_conflicts(spacecraft_id, spacecraft_snapshots)
      end)
      |> Enum.sort_by(& &1["snapshot_ids"])

    %{"items" => items, "clear" => items == []}
  end

  defp spacecraft_conflicts(spacecraft_id, snapshots) do
    ordered = Enum.sort_by(snapshots, & &1.starts_at, DateTime)

    ordered
    |> Enum.with_index()
    |> Enum.flat_map(fn {left, index} ->
      left_conflicts(spacecraft_id, left, Enum.drop(ordered, index + 1))
    end)
  end

  defp left_conflicts(spacecraft_id, left, candidates) do
    candidates
    |> Enum.filter(&overlap?(left, &1))
    |> Enum.map(&conflict_document(spacecraft_id, left, &1))
  end

  defp conflict_document(spacecraft_id, left, right) do
    %{
      "code" => "selected_contacts_overlap",
      "spacecraft_id" => spacecraft_id,
      "snapshot_ids" =>
        Enum.sort([
          left.contact_opportunity_snapshot_id,
          right.contact_opportunity_snapshot_id
        ])
    }
  end

  defp overlap?(left, right),
    do:
      DateTime.before?(left.starts_at, right.ends_at) and
        DateTime.before?(right.starts_at, left.ends_at)

  defp unsatisfied(coverage, conflicts) do
    requirement_items =
      coverage["requirements"]
      |> Enum.reject(& &1["satisfied"])
      |> Enum.map(fn item ->
        %{
          "contact_requirement_id" => item["contact_requirement_id"],
          "contact_requirement_version" => item["contact_requirement_version"],
          "hard_failures" => item["hard_failures"],
          "search_failures" => item["search_failures"]
        }
      end)

    %{
      "requirements" => requirement_items,
      "conflicts" => conflicts["items"],
      "clear" => requirement_items == [] and conflicts["clear"]
    }
  end

  @doc false
  @spec policy_snapshot([struct()], [struct()]) :: {:ok, map()} | {:error, term()}
  def policy_snapshot(requirements, selected) do
    requirement_policies =
      requirements
      |> Enum.map(fn requirement ->
        %{
          "contact_requirement_id" => requirement.contact_requirement_id,
          "contact_requirement_version" => requirement.version,
          "approval_policy" => requirement.approval_policy_document,
          "policy_constraints" => requirement.policy_constraints_document
        }
      end)
      |> Enum.sort_by(&{&1["contact_requirement_id"], &1["contact_requirement_version"]})

    routes =
      Enum.map(selected, fn snapshot ->
        requirement =
          Enum.find(requirements, fn requirement ->
            requirement.contact_requirement_id == snapshot.contact_requirement_id and
              requirement.version == snapshot.contact_requirement_version
          end)

        mission_policy = snapshot.route_binding_document["delivery_policy_document"] || %{}

        with %{} = requirement <- requirement,
             {:ok, effective_policy} <-
               PolicyNarrowing.narrow(
                 mission_policy,
                 requirement.policy_constraints_document
               ) do
          {:ok,
           %{
             "contact_opportunity_snapshot_id" => snapshot.contact_opportunity_snapshot_id,
             "route_binding" => snapshot.route_binding_document,
             "mission_delivery_policy" => mission_policy,
             "effective_policy" => effective_policy
           }}
        else
          nil -> {:error, :contact_plan_snapshot_requirement_not_referenced}
          {:error, reason} -> {:error, reason}
        end
      end)

    case Enum.find(routes, &match?({:error, _}, &1)) do
      nil ->
        {:ok,
         %{
           "requirements" => requirement_policies,
           "selections" =>
             routes
             |> Enum.map(fn {:ok, route} -> route end)
             |> Enum.sort_by(& &1["contact_opportunity_snapshot_id"])
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp select_snapshots(snapshots, selected_ids) do
    positions = selected_ids |> Enum.with_index() |> Map.new()

    snapshots
    |> Enum.filter(&Map.has_key?(positions, &1.contact_opportunity_snapshot_id))
    |> Enum.sort_by(&Map.fetch!(positions, &1.contact_opportunity_snapshot_id))
  end

  defp reject_snapshots(snapshots, selected_ids) do
    selected = MapSet.new(selected_ids)
    Enum.reject(snapshots, &MapSet.member?(selected, &1.contact_opportunity_snapshot_id))
  end

  defp selected_belongs(selected_ids, snapshots) do
    available = MapSet.new(snapshots, & &1.contact_opportunity_snapshot_id)

    if Enum.all?(selected_ids, &MapSet.member?(available, &1)),
      do: :ok,
      else: {:error, :contact_plan_snapshot_not_in_referenced_runs}
  end

  defp eligible_selected(snapshots) do
    if Enum.all?(snapshots, & &1.eligible),
      do: :ok,
      else: {:error, :contact_plan_selected_snapshot_ineligible}
  end

  defp completed_runs(runs) do
    if Enum.all?(runs, &(&1.lifecycle_state in ["completed", "partial", "failed"])),
      do: :ok,
      else: {:error, :contact_plan_planning_run_incomplete}
  end

  defp proposal_list(attrs, field, default) do
    items = value(attrs, field, default)

    cond do
      not is_list(items) ->
        {:error, {:invalid_contact_plan_field, field}}

      not Enum.all?(items, &(is_binary(&1) and &1 != "")) ->
        {:error, {:invalid_contact_plan_field, field}}

      length(Enum.uniq(items)) != length(items) ->
        {:error, {:duplicate_contact_plan_reference, field}}

      true ->
        {:ok, items}
    end
  end

  defp proposal_rationale(attrs, previous) do
    case value(attrs, :rationale, (previous && previous.rationale) || "") do
      item when is_binary(item) -> item
      _item -> raise ArgumentError, "rationale must be a string"
    end
  end

  defp previous_run_ids(nil), do: []
  defp previous_run_ids(previous), do: previous.planning_run_refs_document["runs"] || []
  defp previous_selected_ids(nil), do: []
  defp previous_selected_ids(previous), do: previous.selected_snapshot_ids
  defp previous_locked_ids(nil), do: []
  defp previous_locked_ids(previous), do: previous.locked_snapshot_ids

  defp disjoint_snapshot_ids(selected, locked) do
    if MapSet.disjoint?(MapSet.new(selected), MapSet.new(locked)),
      do: :ok,
      else: {:error, :contact_plan_snapshot_dispositions_overlap}
  end

  defp require_nonempty([], field), do: {:error, {:contact_plan_reference_required, field}}
  defp require_nonempty(_items, _field), do: :ok

  defp lock_plan(organization_id, mission_id, plan_id) do
    case ContactPlanRow
         |> where(
           [plan],
           plan.organization_id == ^organization_id and plan.mission_id == ^mission_id and
             plan.contact_plan_id == ^plan_id
         )
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil -> {:error, :contact_plan_not_found}
      row -> {:ok, row}
    end
  end

  defp advance_execution_projection(%ContactPlanRow{approved_version: version} = row, now)
       when is_integer(version) do
    case row
         |> ContactPlanRow.projection_changeset(%{
           current_version: row.current_version,
           lifecycle_state: "executing",
           lifecycle_changed_by: row.approved_by,
           lifecycle_changed_at: now,
           lifecycle_reason: "execution started",
           approved_version: row.approved_version,
           approved_at: row.approved_at,
           approved_by: row.approved_by
         })
         |> Repo.update() do
      {:ok, updated} -> ContactPlanRow.to_domain(updated)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp advance_execution_projection(_row, _now),
    do: Repo.rollback(:contact_plan_not_approved)

  defp fetch_version_row(row, version) do
    case Repo.get_by(ContactPlanVersionRow,
           organization_id: row.organization_id,
           mission_id: row.mission_id,
           contact_plan_id: row.contact_plan_id,
           version: version
         ) do
      nil -> {:error, :contact_plan_version_not_found}
      version_row -> {:ok, version_row}
    end
  end

  defp editable_plan(%ContactPlanRow{lifecycle_state: state})
       when state in ["draft", "pending_approval"],
       do: :ok

  defp editable_plan(_row), do: {:error, :contact_plan_not_editable}
  defp draft_plan(%ContactPlanRow{lifecycle_state: "draft"}), do: :ok
  defp draft_plan(_row), do: {:error, :contact_plan_not_draft}
  defp expected_version(%ContactPlanRow{current_version: version}, version), do: :ok
  defp expected_version(_row, _version), do: {:error, :stale_contact_plan_version}

  defp undecided_version(row) do
    decided? =
      Repo.exists?(
        from(approval in ContactPlanApprovalRow,
          where:
            approval.organization_id == ^row.organization_id and
              approval.mission_id == ^row.mission_id and
              approval.contact_plan_id == ^row.contact_plan_id and
              approval.contact_plan_version == ^row.current_version
        )
      )

    if decided?, do: {:error, :contact_plan_version_already_decided}, else: :ok
  end

  defp require_reason(""), do: {:error, :contact_plan_transition_reason_required}
  defp require_reason(_reason), do: :ok

  defp maybe_filter_lifecycle(query, nil), do: query

  defp maybe_filter_lifecycle(query, lifecycle_state)
       when lifecycle_state in [
              :draft,
              :pending_approval,
              :approved,
              :executing,
              :partially_reserved,
              :reserved,
              :failed,
              :canceled,
              :superseded
            ] do
    where(query, [plan], plan.lifecycle_state == ^Atom.to_string(lifecycle_state))
  end

  defp authorize_member(current_scope, mission_id) do
    Policy.authorize(current_scope, :operate_mission, %{
      organization_id: current_scope.organization_id,
      mission_id: mission_id
    })
  end

  defp authorize_submit(%Scope{actor_kind: :user} = scope, mission_id, _opts),
    do: authorize_member(scope, mission_id)

  defp authorize_submit(%Scope{actor_kind: :service} = scope, mission_id, opts) do
    grant_id = Keyword.get(opts, :automation_grant_id)
    evidence = Keyword.get(opts, :automation_evidence, %{})

    case AutomationGrants.authorize(
           scope,
           mission_id,
           grant_id,
           :submit,
           evidence,
           opts
         ) do
      {:ok, _grant} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp actor_id(%Scope{actor_kind: :user, user: %{user_id: user_id}})
       when is_binary(user_id) and user_id != "",
       do: {:ok, user_id}

  defp actor_id(%Scope{
         actor_kind: :service,
         service_identity: %{service_identity_id: service_identity_id}
       })
       when is_binary(service_identity_id) and service_identity_id != "",
       do: {:ok, service_identity_id}

  defp actor_id(%Scope{}), do: {:error, :authenticated_actor_required}

  defp normalize_pair_result({:ok, {plan, version}}), do: {:ok, plan, version}
  defp normalize_pair_result({:error, %Changeset{} = changeset}), do: {:error, changeset}
  defp normalize_pair_result({:error, reason}), do: {:error, reason}
  defp normalize_single_result({:ok, plan}), do: {:ok, plan}
  defp normalize_single_result({:error, reason}), do: {:error, reason}

  defp value(attrs, key, default),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
