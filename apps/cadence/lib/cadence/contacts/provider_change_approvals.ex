defmodule Cadence.Contacts.ProviderChangeApprovals do
  @moduledoc "Organization-admin decisions on current provider Contact proposals."

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Contacts.{
    ProviderChangeApproval,
    ProviderReservationChange,
    ProviderReservationChanges
  }

  alias Cadence.Control.Contacts.Store.ProviderChangeApprovalRow
  alias Cadence.Repo

  @spec approve(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def approve(%Scope{} = current_scope, change_id, proposal_hash, reason, opts \\ []) do
    with :ok <- authorize(current_scope),
         {:ok, change} <-
           ProviderReservationChanges.fetch(current_scope.organization_id, change_id),
         {:ok, approval} <-
           build_approval(current_scope, change, :approved, proposal_hash, reason, opts) do
      ProviderReservationChanges.apply(
        current_scope.organization_id,
        change_id,
        actor_document(current_scope),
        allowed_states: [:pending_approval],
        decision_state: :approved,
        proposal_hash: proposal_hash,
        approval: approval,
        require_current_deadline?: true,
        now: now(opts),
        fail_before_commit?: Keyword.get(opts, :fail_before_commit?, false)
      )
    end
  end

  @spec reject(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, ProviderReservationChange.t()} | {:error, term()}
  def reject(%Scope{} = current_scope, change_id, proposal_hash, reason, opts \\ []) do
    with :ok <- authorize(current_scope),
         {:ok, change} <-
           ProviderReservationChanges.fetch(current_scope.organization_id, change_id),
         {:ok, approval} <-
           build_approval(current_scope, change, :rejected, proposal_hash, reason, opts) do
      ProviderReservationChanges.decide_without_application(
        change_id,
        current_scope.organization_id,
        :rejected,
        actor_document(current_scope),
        %{"decision" => "rejected", "reason" => normalize_reason(reason)},
        allowed_states: [:pending_approval],
        proposal_hash: proposal_hash,
        approval: approval,
        require_actionable?: true,
        now: now(opts)
      )
    end
  end

  @spec acknowledge(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, ProviderReservationChange.t()} | {:error, term()}
  def acknowledge(%Scope{} = current_scope, change_id, proposal_hash, reason, opts \\ []) do
    with :ok <- authorize(current_scope),
         {:ok, change} <-
           ProviderReservationChanges.fetch(current_scope.organization_id, change_id),
         {:ok, approval} <-
           build_approval(current_scope, change, :acknowledged, proposal_hash, reason, opts) do
      ProviderReservationChanges.decide_without_application(
        change_id,
        current_scope.organization_id,
        :acknowledged,
        actor_document(current_scope),
        %{"decision" => "acknowledged", "reason" => normalize_reason(reason)},
        allowed_states: [:acknowledgment_required],
        proposal_hash: proposal_hash,
        approval: approval,
        now: now(opts)
      )
    end
  end

  @spec fetch(binary(), binary()) ::
          {:ok, ProviderChangeApproval.t()} | {:error, :provider_change_approval_not_found}
  def fetch(organization_id, provider_reservation_change_id) do
    case Repo.get_by(ProviderChangeApprovalRow,
           organization_id: organization_id,
           provider_reservation_change_id: provider_reservation_change_id
         ) do
      nil -> {:error, :provider_change_approval_not_found}
      row -> {:ok, ProviderChangeApprovalRow.to_domain(row)}
    end
  end

  @spec list_for_mission(binary(), binary()) :: [ProviderChangeApproval.t()]
  def list_for_mission(organization_id, mission_id) do
    ProviderChangeApprovalRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], desc: row.decided_at)
    |> Repo.all()
    |> Enum.map(&ProviderChangeApprovalRow.to_domain/1)
  end

  defp authorize(%Scope{actor_kind: :user, user: user} = scope) when not is_nil(user) do
    Policy.authorize(scope, :approve_provider_changes, %{organization_id: scope.organization_id})
  end

  defp authorize(%Scope{}), do: {:error, :authenticated_user_required}

  defp build_approval(scope, change, decision, proposal_hash, reason, opts) do
    {:ok,
     ProviderChangeApproval.new(%{
       organization_id: scope.organization_id,
       mission_id: change.mission_id,
       provider_reservation_change_id: change.provider_reservation_change_id,
       decision: decision,
       proposal_hash: proposal_hash,
       policy_version: change.policy_version,
       reason: normalize_reason(reason),
       actor_user_id: scope.user.user_id,
       actor_document: actor_document(scope),
       decided_at: now(opts)
     })}
  rescue
    error in ArgumentError -> {:error, {:invalid_provider_change_approval, error.message}}
  end

  defp actor_document(scope) do
    %{
      "kind" => "user",
      "id" => scope.user.user_id,
      "email" => scope.user.email,
      "display_name" => scope.user.display_name
    }
  end

  defp normalize_reason(reason) when is_binary(reason), do: String.trim(reason)
  defp normalize_reason(_reason), do: ""

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
