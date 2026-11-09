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

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts

  alias Cadence.ContactPlanning.{
    ContactPlan,
    ContactPlans,
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
        with {:ok, %ContactPlan{} = plan, version} <-
               ManagementContacts.fetch_plan(org, mission_id, plan_id),
             :ok <- expected(version.version, params[:expected_version]),
             {:ok, plan} <- maybe_submit(scope, mission_id, plan, version, params[:reason]),
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

  @doc "A plan's lifecycle, with `:interrupted` for an `executing` plan nobody is executing."
  @spec plan_state(binary(), binary(), binary(), atom()) :: atom()
  def plan_state(organization_id, mission_id, plan_id, :executing) do
    if FleetRunLock.key_held?(execution_key(organization_id, mission_id, plan_id)),
      do: :executing,
      else: :interrupted
  end

  def plan_state(_organization_id, _mission_id, _plan_id, lifecycle_state), do: lifecycle_state

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

  defp maybe_submit(
         scope,
         mission_id,
         %ContactPlan{lifecycle_state: :draft} = plan,
         version,
         reason
       ) do
    case ManagementContacts.submit_plan(
           scope,
           mission_id,
           plan.contact_plan_id,
           version.version,
           reason(reason)
         ) do
      {:ok, submitted} -> {:ok, submitted}
      {:error, _reason} = error -> error
    end
  end

  defp maybe_submit(
         _scope,
         _mission_id,
         %ContactPlan{lifecycle_state: :pending_approval} = plan,
         _version,
         _reason
       ),
       do: {:ok, plan}

  defp maybe_submit(_scope, _mission_id, %ContactPlan{}, _version, _reason),
    do: {:error, :contact_plan_not_submittable}

  defp decide(scope, mission_id, plan, version, params) do
    if approver?(scope, mission_id),
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
             reason(params[:reason]),
             acknowledged_exceptions: params[:acknowledgements]
           ) do
      {:ok, {:execute, version.version, version.content_sha256}}
    end
  end

  defp expected(version, version), do: :ok
  defp expected(_current, _expected), do: {:error, :contact_plan_version_changed}

  defp reason(reason) when is_binary(reason) and byte_size(reason) > 0, do: reason
  defp reason(_reason), do: "Submitted from the console contact plan"

  defp execution_key(organization_id, mission_id, plan_id),
    do: ["cadence.contact_plan.execute", organization_id, mission_id, plan_id]

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
