defmodule Cadence.Control.Scheduling do
  @moduledoc """
  Console scheduling orchestration over the contact-planning domain
  (DECISIONS #26–#28). It composes the existing reviewed flows instead of
  re-implementing them:

  - `start_draft/4`: fleet-run preview + create for a UTC day (the evidence
    pattern), recording the client's `operation_id` on the run in the same
    transaction, so a replay on any node finds it.
  - `run_draft/3` and `continue_draft/3`: execute or resume the run. These block
    on provider searches, so callers run them off the request path.
  - `draft_state/3`: the run's lifecycle, plus `interrupted` when a run sits
    queued/running with no session holding its execution lock.

  Authorization is the domain's own (`operate_mission`).
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.SingleBookings
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Control.PlanResubmission
  alias Cadence.Management.Contacts, as: ManagementContacts

  alias Cadence.ContactPlanning.{
    ContactPlan,
    ContactPlanApprovals,
    ContactPlanExecutions,
    ContactPlans,
    FleetPlanner,
    FleetPlanningRun,
    FleetPlanningRuns,
    FleetPlanningStarts,
    FleetRunActions,
    FleetRunLock,
    FleetRunRepairs,
    FleetRunReviews,
    RepairChain,
    StationConflicts
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

  @doc """
  The template fan-out a draft of `day` (one UTC day, as start_draft/4 drafts it) counts toward
  the 50,000 limit, with the templates its per-run cap cuts short (U52, the Start screen's
  estimate): `{:ok, %{count, limit, capped: [%{template_id, limit, last_at}]}}`.
  """
  @spec draft_template_estimate(Scope.t(), binary(), Date.t()) :: {:ok, map()} | {:error, term()}
  def draft_template_estimate(%Scope{} = scope, mission_id, %Date{} = day) do
    FleetPlanningStarts.estimate(scope, mission_id, %{
      horizon_start: DateTime.new!(day, ~T[00:00:00], "Etc/UTC"),
      horizon_end: day |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    })
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

  @doc """
  S5 "Submit N requests" (DECISIONS #27/#28). For an organization admin:
  submit (when draft) + approve with acknowledged exceptions, then
  `{:ok, {:execute, version, content_sha256}}`; the caller runs
  `execute_plan/5` off the request. For a member: submit only →
  `{:ok, :pending_approval}`. A replayed `operation_id` → `{:ok, :replayed}`.

  Params: `expected_version`, `reason`, `acknowledgements` (`[%{requirement_id, reason}]`).
  """
  @spec submit_plan(Scope.t(), binary(), binary(), binary(), map()) ::
          {:ok, :pending_approval | :replayed | {:execute, pos_integer(), binary()}}
          | {:error, term()}
  def submit_plan(%Scope{} = scope, mission_id, plan_id, operation_id, params) do
    org = scope.organization_id

    case ContactPlans.plan_id_for_operation(org, mission_id, operation_id) do
      ^plan_id ->
        {:ok, :replayed}

      nil ->
        # U36: lock, expected version, cut-if-sent-back, submit and round record are one
        # transaction (PlanResubmission); approval and execution follow it.
        with {:ok, plan, version} <-
               PlanResubmission.submit(
                 scope,
                 mission_id,
                 plan_id,
                 params,
                 &stations_available(org, mission_id, plan_id, &1)
               ),
             {:ok, outcome} <- decide(scope, mission_id, plan, version, params),
             :ok <- ContactPlans.claim_operation(org, mission_id, plan_id, operation_id) do
          # Claimed only after the action succeeded, so a failed attempt can be retried
          # with the same operation_id; concurrent duplicates lose on expected_version.
          {:ok, outcome}
        end

      _other_plan ->
        {:error, :operation_already_claimed}
    end
  end

  # U26: a selected pass at a station that is down or in maintenance blocks submit (degraded
  # only warns). The console reads the conflicts from the plan detail.
  defp stations_available(org, mission_id, plan_id, version) do
    passes = ManagementContacts.selected_opportunities(org, mission_id, plan_id, version.version)

    case StationConflicts.check(org, mission_id, passes) do
      %{conflicts: []} -> :ok
      _blocked -> {:error, :contact_plan_not_satisfied}
    end
  end

  @doc """
  S4: adds and removes passes (snapshot ids the plan's runs found) as a new
  plan version; coverage, conflicts and unsatisfied are recomputed by the
  domain. A plan in review returns to draft (the domain's rule).
  """
  @spec edit_plan(Scope.t(), binary(), binary(), pos_integer(), [binary()], [binary()]) ::
          {:ok, ContactPlan.t(), map()} | {:error, term()}
  def edit_plan(%Scope{} = scope, mission_id, plan_id, expected_version, add, remove) do
    with {:ok, _plan, version} <-
           ManagementContacts.fetch_plan(scope.organization_id, mission_id, plan_id),
         :ok <- expected(version.version, expected_version) do
      selected =
        ((version.selected_snapshot_ids || []) ++ add)
        |> Enum.uniq()
        |> Enum.reject(&(&1 in remove))

      ManagementContacts.version_plan(scope, mission_id, plan_id, expected_version, %{
        selected_snapshot_ids: selected,
        locked_snapshot_ids: Enum.reject(version.locked_snapshot_ids || [], &(&1 in remove)),
        rationale: "Edited in the console contact plan"
      })
    end
  end

  @doc """
  S8 re-plan after provider changes: creates a repair (successor) fleet run for
  the run that produced `plan_id`, locking passes already committed; the
  caller runs it off the request with `run_draft/3`. The successor produces a
  **new** candidate plan; apply it with `submit_plan/5`. `window` is
  `{from, to}` or `nil` (now → the end of the source run's horizon).

  The operation is recorded on the successor right after creation (the reviewed
  repair flow has no option for it), so a crash in between can leave an
  unrecorded run; a replay then starts another repair.
  """
  @spec start_repair(Scope.t(), binary(), binary(), {DateTime.t(), DateTime.t()} | nil, binary()) ::
          {:ok, FleetPlanningRun.t(), :created | :replayed} | {:error, term()}
  def start_repair(%Scope{} = scope, mission_id, plan_id, window, operation_id) do
    org = scope.organization_id

    case FleetPlanningRuns.fetch_by_operation(org, mission_id, operation_id) do
      {:ok, run} ->
        {:ok, run, :replayed}

      {:error, :fleet_planning_run_not_found} ->
        with {:ok, source} <- source_run(org, mission_id, plan_id),
             {:ok, reviewed} <-
               FleetRunReviews.load(scope, mission_id, source.fleet_planning_run_id),
             {:ok, %{evidence: evidence}} <-
               FleetRunRepairs.review(scope, reviewed),
             {from, to} = window || {DateTime.utc_now(), source.horizon_end},
             {:ok, receipt} <-
               FleetRunActions.execute(scope, mission_id, :repair, %{
                 "fleet_planning_run_id" => source.fleet_planning_run_id,
                 "evidence" => evidence,
                 "repair" => %{
                   "horizon_start" => DateTime.to_iso8601(from),
                   "horizon_end" => DateTime.to_iso8601(to)
                 }
               }),
             run_id = receipt["fleetPlanningRunId"],
             :ok <- FleetPlanningRuns.claim_operation(org, mission_id, run_id, operation_id),
             {:ok, run} <- FleetPlanningRuns.fetch(org, mission_id, run_id) do
          {:ok, run, :created}
        end
    end
  end

  # qa #30: a repair starts from the chain head, whichever plan of the chain the console names.
  defp source_run(organization_id, mission_id, plan_id),
    do: RepairChain.head_run(organization_id, mission_id, plan_id)

  @doc "Books an approved plan with providers (blocking); holds the plan's execution lock."
  @spec execute_plan(Scope.t(), binary(), binary(), pos_integer(), binary()) ::
          {:ok, map()} | {:error, term()}
  def execute_plan(%Scope{} = scope, mission_id, plan_id, version, content_sha256) do
    FleetRunLock.with_key(execution_key(scope.organization_id, mission_id, plan_id), fn ->
      ControlContacts.execute_approved_plan(scope, mission_id, plan_id,
        expected_plan_version: version,
        expected_plan_hash: content_sha256
      )
    end)
  end

  @doc "A plan's lifecycle as operators see it: `Control.Contacts.plan_state/5`."
  @spec plan_state(binary(), binary(), binary(), atom(), keyword()) :: atom()
  defdelegate plan_state(organization_id, mission_id, plan_id, lifecycle_state, opts \\ []),
    to: ControlContacts

  @doc "The approved version and hash of a plan, for (re-)execution."
  @spec approved_version(binary(), binary(), binary()) ::
          {:ok, pos_integer(), binary()} | {:error, term()}
  def approved_version(organization_id, mission_id, plan_id) do
    with {:ok, approved} <-
           ManagementContacts.fetch_approved_plan(organization_id, mission_id, plan_id) do
      {:ok, approved.contact_plan_version, approved.content_sha256}
    end
  end

  @spec approver?(Scope.t(), binary()) :: boolean()
  def approver?(%Scope{} = scope, _mission_id),
    do:
      Policy.authorize(scope, :approve_contact_plans, %{organization_id: scope.organization_id}) ==
        :ok

  # An approver's Submit also approves, but only under 'direct' approval. Under 'independent' a
  # second person approves (director 11-15), so it waits like a member's.
  defp decide(scope, mission_id, plan, version, params) do
    if approver?(scope, mission_id) and
         not ContactPlanApprovals.separation_required?(%{
           organization_id: scope.organization_id,
           mission_id: mission_id
         }),
       do: approve(scope, mission_id, plan, version, params),
       else: {:ok, :pending_approval}
  end

  defp approve(scope, mission_id, plan, version, params) do
    with {:ok, _approved} <-
           ControlContacts.approve_and_accept_plan(
             scope,
             mission_id,
             plan.contact_plan_id,
             version.version,
             version.content_sha256,
             reason(params[:decision_note] || params[:reason]),
             acknowledged_exceptions: params[:acknowledgements]
           ) do
      {:ok, {:execute, version.version, version.content_sha256}}
    end
  end

  defp expected(version, version), do: :ok
  defp expected(_current, _expected), do: {:error, :contact_plan_version_changed}

  # U76: the approver's note for the record, or none (recorded as NULL); never a canned text.
  defp reason(reason) when is_binary(reason) and byte_size(reason) > 0, do: reason
  defp reason(_reason), do: nil

  defp execution_key(organization_id, mission_id, plan_id),
    do: ContactPlanExecutions.execution_key(organization_id, mission_id, plan_id)

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
           FleetPlanningStarts.create(
             scope,
             mission_id,
             %{"fleet_run" => fleet_run, "evidence" => evidence},
             operation_id: operation_id,
             # DECISIONS #78: the day's live single bookings are fixed occupancy.
             occupied:
               SingleBookings.occupancy_document(scope.organization_id, mission_id, fleet_run)
           ) do
      {:ok, run, :created}
    else
      # A concurrent request with the same operation won the unique index; answer with its run.
      {:error, :operation_already_claimed} ->
        with {:ok, run} <-
               FleetPlanningRuns.fetch_by_operation(
                 scope.organization_id,
                 mission_id,
                 operation_id
               ),
             do: {:ok, run, :replayed}

      other ->
        other
    end
  end

  defp stringify({:ok, review}) when is_map(review),
    do: {:ok, Map.new(review, fn {key, value} -> {to_string(key), value} end)}

  defp stringify(other), do: other

  defp recent?(%FleetPlanningRun{inserted_at: %DateTime{} = at}),
    do: DateTime.diff(DateTime.utc_now(), at) < @queued_grace_s

  defp recent?(_run), do: false
end
