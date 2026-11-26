defmodule Cadence.Control.PlanningGrantDecisions do
  @moduledoc """
  The console's decisions on automation grants (#283, ux U105): approve and reject a proposal,
  narrow an active grant, resume a suspended one (#499). Each takes an `operation_id` (as #257's plans): one transaction, the
  mission's approval setting held stable first (Governance.ActivationLocks' order), then the
  grant row lock, then the operation check (`GrantOperations`: the same request again gets the
  original answer, `replayed: true`), then the act (`AutomationGrantReview`), then the record.
  """

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{AutomationGrantReview, AutomationGrants, GrantOperations}
  alias Cadence.ContactPlanning.GrantSeparation
  alias Cadence.Control.PlanningGrants
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Repo

  @doc "Approves the proposal read at `sha256`: `{:ok, {:decided | :replayed, row}}`."
  @spec approve(Scope.t(), binary(), binary(), map()) :: {:ok, tuple()} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, grant_id, params) do
    with {:ok, sha} <- required(params, :sha256) do
      run(scope, mission_id, grant_id, params, :approve, sha, fn ->
        AutomationGrantReview.approve(scope, mission_id, grant_id, sha)
      end)
    end
  end

  @doc """
  #499: resumes a suspended grant read at `sha256` (an approval-like act, with replays):
  `{:ok, {:decided | :replayed, row}}`. The setting in force decides who may.
  """
  @spec resume(Scope.t(), binary(), binary(), map()) :: {:ok, tuple()} | {:error, term()}
  def resume(%Scope{} = scope, mission_id, grant_id, params) do
    with {:ok, sha} <- required(params, :sha256) do
      run(scope, mission_id, grant_id, params, :resume, sha, fn ->
        AutomationGrantReview.resume(scope, mission_id, grant_id, sha)
      end)
    end
  end

  @doc "Rejects a proposal with a reason."
  @spec reject(Scope.t(), binary(), binary(), map()) :: {:ok, tuple()} | {:error, term()}
  def reject(%Scope{} = scope, mission_id, grant_id, params) do
    reason = params["reason"]

    run(scope, mission_id, grant_id, params, :reject, reason, fn ->
      AutomationGrantReview.reject(scope, mission_id, grant_id, reason)
    end)
  end

  @doc "Narrows an active grant to `params[\"changes\"]`."
  @spec narrow(Scope.t(), binary(), binary(), map()) :: {:ok, tuple()} | {:error, term()}
  def narrow(%Scope{} = scope, mission_id, grant_id, params) do
    changes = params["changes"]

    if is_map(changes) and changes != %{} do
      run(scope, mission_id, grant_id, params, :narrow, changes, fn ->
        AutomationGrantReview.narrow(scope, mission_id, grant_id, changes)
      end)
    else
      {:error, {:invalid_params, %{changes: "is required"}}}
    end
  end

  defp run(scope, mission_id, grant_id, params, action, request, act) do
    # Who may decide comes first, before any lock or replay (ca-security on #497): a member can't
    # probe grant ids (404 vs 403), and a demoted admin gets no replay.
    with {:ok, operation_id} <- required(params, :operation_id),
         {:ok, _decider} <- GrantSeparation.decider(scope) do
      op = %{mission_id: mission_id, id: operation_id, grant_id: grant_id, action: action}

      stable_transaction(scope.organization_id, fn -> decide(scope, op, request, act) end)
    end
  end

  defp stable_transaction(organization_id, fun),
    do: ActivationPolicy.with_stable_policy(organization_id, fn -> Repo.transaction(fun) end)

  defp decide(scope, op, request, act) do
    with :ok <- AutomationGrants.lock(scope.organization_id, op.mission_id, op.grant_id),
         :new <-
           GrantOperations.check(scope, op.mission_id, op.id, op.grant_id, op.action, request),
         {:ok, grant} <- act.(),
         body = PlanningGrants.encode_row(scope, grant),
         :ok <- record(scope, op, request, body) do
      {:decided, body}
    else
      {:replay, {_status, body}} -> {:replayed, body}
      :duplicate_operation -> Repo.rollback(:duplicate_operation)
      :operation_conflict -> Repo.rollback(:operation_already_claimed)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp record(scope, op, request, body),
    do:
      GrantOperations.record(
        scope,
        op.mission_id,
        op.id,
        op.grant_id,
        op.action,
        request,
        {200, body}
      )

  defp required(params, key) do
    case params[Atom.to_string(key)] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:invalid_params, %{key => "is required"}}}
    end
  end
end
