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

  #273: the answer carries `expired`, the passes this approval leaves out because their offer had
  already expired (`PlanExpiredPasses`), read at the moment of the decision; `nil` when none.
  """

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlan, ContactPlans, PlanOperations}
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Control.PlanExpiredPasses
  alias Cadence.Repo

  @typedoc "`params`: operation_id, expected_version, note (the decision note), acknowledgements."
  @type params :: %{
          required(:operation_id) => binary(),
          required(:expected_version) => pos_integer(),
          optional(:note) => binary() | nil,
          optional(:acknowledgements) => [map()]
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
           expired =
             PlanExpiredPasses.at(
               scope.organization_id,
               mission_id,
               plan_id,
               version.version,
               DateTime.utc_now()
             ),
           {:ok, _approved} <- decide(scope, mission_id, plan, version, params),
           answer = {202, body(plan_id, version.version, expired)},
           :ok <- PlanOperations.record(attrs(scope, mission_id, plan_id, params), answer) do
        {:approved, answer, version.version, version.content_sha256}
      else
        {:replay, answer} -> {:replayed, answer}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp decide(scope, mission_id, plan, version, params) do
    case ControlContacts.approve_and_accept_plan(
           scope,
           mission_id,
           plan.contact_plan_id,
           version.version,
           version.content_sha256,
           params[:note],
           acknowledged_exceptions: params[:acknowledgements] || []
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

  defp expected(version, version), do: :ok
  defp expected(_current, _expected), do: {:error, :contact_plan_version_changed}
end
