defmodule Cadence.ContactPlanning.GrantSeparation do
  @moduledoc """
  Who may decide on an automation grant (#283, ux U105; ca-security 11-19). Approval runs
  `check/4`, and the console's flags come from `viewer_block/3`, the same check:

  - person-only and `:manage_automation_grants` (`decider/1`);
  - under 'independent', not the proposer, not the replaced grant's proposer (a widening), and
    outside the people accountable for the service (#280; an unknown set refuses everyone);
  - #281's rule: whoever proposes or approves holds every capability the grant confers
    (`confers/3`).
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.AutomationGrant
  alias Cadence.Governance.{Accountability, ActivationPolicy}
  alias Cadence.Management.Contacts.Store.AutomationGrantRow
  alias Cadence.Repo

  @doc "The deciding person's id, if they're an org admin (#283: person-only)."
  @spec decider(Scope.t()) :: {:ok, binary()} | {:error, term()}
  def decider(%Scope{actor_kind: :user, user: %{user_id: id}} = scope) when is_binary(id) do
    case Policy.authorize(scope, :manage_automation_grants, %{
           organization_id: scope.organization_id
         }) do
      :ok -> {:ok, id}
      error -> error
    end
  end

  def decider(%Scope{}), do: {:error, :authenticated_user_required}

  @doc """
  Why `scope` can't decide on `grant` now, for the console's flags (U105, #233's pattern: the
  server says, the console never computes it): nil when they can, else `{reason, details}` with
  reason not_a_person | not_admin | not_proposed | policy_changed | proposer | accountable |
  authors_unknown.
  The same separation check approval runs, against the setting in force now.
  """
  @spec viewer_block(Scope.t(), AutomationGrant.t(), DateTime.t()) ::
          nil | {binary(), map() | nil}
  def viewer_block(%Scope{} = scope, %AutomationGrant{} = grant, now) do
    with {:ok, viewer} <- viewer(scope),
         :proposed <- AutomationGrant.effective_state(grant, now),
         :ok <- same_setting(grant),
         policy = ActivationPolicy.evidence(grant.organization_id, grant.mission_id),
         {:ok, _separated} <- check(scope, viewer, grant, policy) do
      nil
    else
      {:blocked, reason} ->
        {reason, nil}

      # fe-ops on #497: the setting changed since the proposal, so approval would refuse it
      # (approval_policy_changed); the flags say so up front instead of offering Approve.
      :policy_changed ->
        {"policy_changed", nil}

      {:error, {:automation_grant_self_approval_forbidden, %{because: "proposed"}}} ->
        {"proposer", nil}

      {:error, {:automation_grant_self_approval_forbidden, %{grantee: grantee}}} ->
        {"accountable", %{grantee: grantee}}

      {:error, {:automation_grant_approver_authors_unknown, details}} ->
        {"authors_unknown", details}

      _state ->
        {"not_proposed", nil}
    end
  end

  defp same_setting(grant) do
    case ActivationPolicy.validate(grant.organization_id, grant.mission_id, grant.approval_policy) do
      :ok -> :ok
      {:error, _changed} -> :policy_changed
    end
  end

  defp viewer(%Scope{actor_kind: :user} = scope) do
    case decider(scope) do
      {:ok, id} -> {:ok, id}
      _refused -> {:blocked, "not_admin"}
    end
  end

  defp viewer(_scope), do: {:blocked, "not_a_person"}

  @doc "Separation under the policy `policy`: `{:ok, %{approver, ids}}` or the refusal."
  @spec check(Scope.t(), binary(), AutomationGrant.t(), map()) :: {:ok, map()} | {:error, term()}
  def check(_scope, approver, _grant, %{"separation_of_duties" => required})
      when required != true,
      do: {:ok, %{approver: approver, ids: []}}

  def check(scope, approver, grant, _policy) do
    replaced_by = replaced_proposer(grant)
    ids = Enum.reject([grant.proposed_by, replaced_by], &is_nil/1)

    if approver in ids,
      do:
        {:error,
         {:automation_grant_self_approval_forbidden,
          %{because: "proposed", grantee: grantee(scope, grant)}}},
      else: accountable(scope, approver, grant, ids)
  end

  defp accountable(scope, approver, grant, ids) do
    org = scope.organization_id
    service = {:service, grant.service_identity_id}

    case Accountability.separate(org, {:user, approver}, [service]) do
      :ok ->
        {:ok, people} = Accountability.authors(org, [service])
        {:ok, %{approver: approver, ids: Enum.uniq(ids ++ people)}}

      {:error, {:self, _via}} ->
        {:error,
         {:automation_grant_self_approval_forbidden,
          %{because: "accountable", grantee: grantee(scope, grant)}}}

      {:error, {:unknown, ref}} ->
        {:error, {:automation_grant_approver_authors_unknown, %{service: ref}}}
    end
  end

  defp replaced_proposer(%{replaces_grant_id: nil}), do: nil

  defp replaced_proposer(grant) do
    AutomationGrantRow
    |> where(
      [r],
      r.organization_id == ^grant.organization_id and r.mission_id == ^grant.mission_id and
        r.automation_grant_id == ^grant.replaces_grant_id
    )
    |> select([r], r.proposed_by)
    |> Repo.one()
  end

  defp grantee(scope, grant) do
    name =
      scope.organization_id
      |> Cadence.Auth.service_identity_names([grant.service_identity_id])
      |> Map.get(grant.service_identity_id)

    %{id: grant.service_identity_id, name: name}
  end

  @doc false
  # #281's rule (ca-security): whoever proposes or approves holds every capability the grant
  # confers (its actions: approve plans, or operate the mission).
  @spec confers(Scope.t(), binary(), AutomationGrant.t()) :: :ok | {:error, term()}
  def confers(scope, mission_id, grant) do
    params = %{organization_id: scope.organization_id, mission_id: mission_id}

    grant.allowed_actions
    |> Enum.map(&if(&1 == :approve, do: :approve_contact_plans, else: :operate_mission))
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn action, :ok ->
      case Policy.authorize(scope, action, params) do
        :ok -> {:cont, :ok}
        _refused -> {:halt, {:error, :automation_grant_capability_required}}
      end
    end)
  end
end
