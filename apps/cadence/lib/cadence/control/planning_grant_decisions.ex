defmodule Cadence.Control.PlanningGrantDecisions do
  @moduledoc """
  The console's decisions on automation grants (#283, ux U105): approve and reject a proposal,
  narrow an active grant. Each takes an `operation_id` (as #257's plans): one transaction, the
  mission's approval setting held stable first (Governance.ActivationLocks' order), then the
  grant row lock, then the operation check (`GrantOperations`: the same request again gets the
  original answer, `replayed: true`), then the act (`AutomationGrantReview`), then the record.
  """

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{AutomationGrantReview, GrantOperations}
  alias Cadence.Control.PlanningGrants
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Contacts.Store.AutomationGrantRow
  alias Cadence.Repo

  import Ecto.Query

  @doc "Approves the proposal read at `sha256`: `{:ok, {:decided | :replayed, row}}`."
  @spec approve(Scope.t(), binary(), binary(), map()) :: {:ok, tuple()} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, grant_id, params) do
    with {:ok, sha} <- required(params, :sha256) do
      run(scope, mission_id, grant_id, params, :approve, sha, fn ->
        AutomationGrantReview.approve(scope, mission_id, grant_id, sha)
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
    with {:ok, operation_id} <- required(params, :operation_id),
         :ok <- person(scope) do
      ActivationPolicy.with_stable_policy(scope.organization_id, fn ->
        Repo.transaction(fn ->
          with :ok <- lock_row(scope.organization_id, mission_id, grant_id),
               :new <-
                 GrantOperations.check(scope, mission_id, operation_id, grant_id, action, request),
               {:ok, grant} <- act.(),
               answer = {200, PlanningGrants.encode_row(scope, grant)},
               :ok <-
                 GrantOperations.record(
                   scope,
                   mission_id,
                   operation_id,
                   grant_id,
                   action,
                   request,
                   answer
                 ) do
            {:decided, elem(answer, 1)}
          else
            {:replay, {_status, body}} -> {:replayed, body}
            :duplicate_operation -> Repo.rollback(:duplicate_operation)
            :operation_conflict -> Repo.rollback(:operation_already_claimed)
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
      end)
    end
  end

  # Every grant act is person-only (#283): refused before anything is read or recorded.
  defp person(%Scope{actor_kind: :user, user: %{user_id: id}}) when is_binary(id), do: :ok
  defp person(_scope), do: {:error, :authenticated_user_required}

  defp lock_row(organization_id, mission_id, grant_id) do
    AutomationGrantRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.automation_grant_id == ^grant_id
    )
    |> lock("FOR UPDATE")
    |> select([r], r.automation_grant_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :automation_grant_not_found}
      _id -> :ok
    end
  end

  defp required(params, key) do
    case params[Atom.to_string(key)] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:invalid_params, %{key => "is required"}}}
    end
  end
end
