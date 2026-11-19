defmodule Cadence.Control.PlanApproval do
  @moduledoc """
  #257 (director 11-19): an approver's explicit approval of a contact plan waiting for approval,
  the console's `POST .../approve`. Submitting never approves; this is the only console path that
  does, under either approval setting.

  One transaction, under the plan row lock: the operation id is checked first
  (`ContactPlanning.PlanOperations`: the same request again gets the original answer back), then
  the version the approver saw must still be current, then `ContactPlanApprovals` decides. It
  reads the approval policy once for the separation check and the record (#226(b)), refuses the
  submitter or the version's author under 'independent' (nothing recorded), and records the
  approver's acknowledgements of the plan's gaps on the approval. The approved plan's execution
  items are accepted, and the operation and its answer are recorded, in the same transaction.
  Execution itself runs off the request (the caller starts it on `{:approved, …}`).

  #273: the approver's `expected_expired_digest` (the plan read's digest; absent means "saw none")
  goes to the domain, which leaves the closed passes out as skipped, or refuses with
  `contact_plan_all_opportunities_expired` or `contact_plan_expired_passes_changed`, recording
  nothing. The answer's `expired` is what the decision RECORDED (`approval.skipped`, read back in
  the same transaction), described by `PlanSkippedPasses`, never recomputed.
  """

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlan, ContactPlanApprovals, ContactPlans, PlanOperations}
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Control.PlanSkippedPasses
  alias Cadence.Repo

  @typedoc "`params`: operation_id, expected_version, note (the decision note), acknowledgements."
  @type params :: %{
          required(:operation_id) => binary(),
          required(:expected_version) => pos_integer(),
          optional(:note) => binary() | nil,
          optional(:acknowledgements) => [map()],
          optional(:expected_expired_digest) => binary() | nil
        }

  @doc """
  Approves the plan. `{:ok, {:approved, answer, version, sha}}` (start execution) or
  `{:ok, {:replayed, answer}}`; `answer` is `{202, body}`. Refusals:
  `{:contact_plan_self_approval_forbidden, :submitted | :edited}`, `:contact_plan_version_changed`,
  `:contact_plan_not_pending_approval`, `:duplicate_operation`, `:operation_already_claimed`,
  and the domain's own (`:forbidden`, unmet requirements, acknowledgements, superseded).
  """
  @spec approve(Scope.t(), binary(), binary(), params()) ::
          {:ok, {:approved, PlanOperations.answer(), pos_integer(), binary()}}
          | {:ok, {:replayed, PlanOperations.answer()}}
          | {:error, term()}
  def approve(%Scope{} = scope, mission_id, plan_id, params) do
    Repo.transaction(fn ->
      with {:ok, plan, version} <-
             ContactPlans.fetch_locked(scope.organization_id, mission_id, plan_id),
           :new <- operation(scope, mission_id, plan_id, params),
           :ok <- expected(version.version, params.expected_version),
           {:ok, _approved} <- decide(scope, mission_id, plan, version, params),
           expired = recorded_skipped(scope.organization_id, mission_id, plan_id, version.version),
           answer = {202, body(plan_id, version.version, expired)},
           :ok <- PlanOperations.record(attrs(scope, mission_id, plan_id, params), answer) do
        {:approved, answer, version.version, version.content_sha256}
      else
        {:replay, answer} -> {:replayed, answer}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      # #273: the domain's refusal rolled the transaction back, so the set is described after it.
      {:error, {code, %{skipped: _, digest: _} = set}}
      when code in [:contact_plan_all_opportunities_expired, :contact_plan_expired_passes_changed] ->
        {:error, {code, refusal_details(scope.organization_id, mission_id, plan_id, params, set)}}

      other ->
        other
    end
  end

  defp decide(scope, mission_id, plan, version, params) do
    case ControlContacts.approve_and_accept_plan(
           scope,
           mission_id,
           plan.contact_plan_id,
           version.version,
           version.content_sha256,
           params[:note],
           acknowledged_exceptions: params[:acknowledgements] || [],
           expected_expired_digest: params[:expected_expired_digest]
         ) do
      {:error, :contact_plan_self_approval_forbidden} ->
        {:error,
         {:contact_plan_self_approval_forbidden, because(plan, PlanOperations.actor_id(scope))}}

      other ->
        other
    end
  end

  # 'submitted' wins when the approver both submitted and wrote the version (domain 11-19:
  # 'edited' is the author of the version being approved). This mirrors the two requesters that
  # ContactPlanApprovals.separate_approver/5 refuses (the plan's lifecycle_changed_by and the
  # version's created_by); keep the two in step if that check gains a cause.
  defp because(%ContactPlan{lifecycle_changed_by: actor_id}, {:ok, actor_id}), do: :submitted
  defp because(_plan, _actor_id), do: :edited

  defp operation(scope, mission_id, plan_id, params) do
    with {:ok, actor_id} <- PlanOperations.actor_id(scope) do
      case PlanOperations.check(
             scope.organization_id,
             mission_id,
             params.operation_id,
             plan_id,
             :approve,
             actor_id,
             params
           ) do
        :new -> :new
        {:replay, answer} -> {:replay, answer}
        :duplicate_operation -> {:error, :duplicate_operation}
        :operation_conflict -> {:error, :operation_already_claimed}
      end
    end
  end

  # Reached only after operation/4 accepted the actor, so actor_id/1 is {:ok, id} here.
  defp attrs(scope, mission_id, plan_id, params) do
    {:ok, actor_id} = PlanOperations.actor_id(scope)

    %{
      organization_id: scope.organization_id,
      mission_id: mission_id,
      operation_id: params.operation_id,
      contact_plan_id: plan_id,
      action: :approve,
      actor_id: actor_id,
      request: params
    }
  end

  defp body(plan_id, version, expired),
    do: %{
      "plan_id" => plan_id,
      "version" => version,
      "state" => "executing",
      "outcome" => "approved",
      "expired" => expired
    }

  # #273: what the decision recorded (read back in its own transaction), never recomputed.
  defp recorded_skipped(organization_id, mission_id, plan_id, version) do
    skipped =
      organization_id
      |> ContactPlanApprovals.list(mission_id, plan_id)
      |> Enum.find(&(&1.contact_plan_version == version and &1.decision == :approved))
      |> case do
        %{skipped: skipped} -> skipped
        nil -> nil
      end

    PlanSkippedPasses.describe(organization_id, mission_id, plan_id, version, skipped)
  end

  # #273: a refusal carries the CURRENT set (the domain's, at the decision's now) and its digest.
  # The version is the one the approver saw, which the version check had just confirmed current.
  defp refusal_details(organization_id, mission_id, plan_id, params, set),
    do: %{
      expired:
        PlanSkippedPasses.describe(
          organization_id,
          mission_id,
          plan_id,
          params.expected_version,
          set.skipped
        ),
      expired_digest: set.digest
    }

  defp expected(version, version), do: :ok
  defp expected(_current, _expected), do: {:error, :contact_plan_version_changed}
end
