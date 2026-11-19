defmodule Cadence.ContactPlanning.AutomationGrantReview do
  @moduledoc """
  Deciding on automation grants (#283, ux U105; plan reviewed by ca-security and api-ops 11-19):
  approve and reject a proposal, narrow or revoke an active grant. Every act is person-only and
  `:manage_automation_grants` (organization admin); a service, even one holding
  organization_admin, is refused `:authenticated_user_required`. Each act locks the grant row
  `FOR UPDATE`, writes one append-only decision (`AutomationGrantDecisions`) in the same
  transaction, and refusals write nothing.

  - Approve: the proposal must still be proposed and within its window, at the hash the approver
    read. The mission's approval setting is re-read; if it changed since the proposal, the
    approval is refused (`approval_policy_changed`). Under 'independent' the approver is none of:
    the proposer, the people accountable for the service (#280; an unknown set refuses), and on a
    widening, the replaced grant's proposer. Validity starts now. A widening's approval revokes
    the grant it replaces, in the same transaction, as the approver.
  - Reject: a proposal, with a reason.
  - Narrow and revoke are tightenings: one admin, at once, never refused for want of a reason.
    Revoking also withdraws any proposal waiting to replace the grant, so the two-person rule can
    never block switching automation off.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.{AutomationGrant, AutomationGrantDecisions, GrantNarrowing}
  alias Cadence.Governance.{Accountability, ActivationPolicy}
  alias Cadence.Management.Contacts.Store.AutomationGrantRow
  alias Cadence.Repo

  @doc "Approves the proposal read at `digest`."
  @spec approve(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, grant_id, digest, opts \\ []) do
    now = now(opts)

    with {:ok, approver} <- decider(scope) do
      ActivationPolicy.with_stable_policy(scope.organization_id, fn ->
        transaction(fn ->
          with {:ok, row, grant} <- lock_grant(scope.organization_id, mission_id, grant_id),
               :ok <- proposed(grant, now),
               :ok <- at_digest(grant, digest),
               {:ok, policy} <- same_policy(grant),
               :ok <- confers(scope, mission_id, grant),
               {:ok, separated} <- separated(scope, approver, grant, policy) do
            approve_locked(scope, row, grant, policy, separated, now)
          end
        end)
      end)
    end
  end

  @doc "Rejects a proposal, with a reason."
  @spec reject(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def reject(%Scope{} = scope, mission_id, grant_id, reason, opts \\ []) do
    now = now(opts)

    with {:ok, actor} <- decider(scope),
         {:ok, reason} <- reason(reason, :automation_grant_rejection_reason_required) do
      transaction(fn ->
        with {:ok, row, grant} <- lock_grant(scope.organization_id, mission_id, grant_id),
             :ok <- proposed(grant, now) do
          rejected =
            rebuild(grant, %{
              lifecycle_state: :rejected,
              rejected_by: actor,
              rejected_at: now,
              rejection_reason: reason
            })

          write(scope, row, rejected, :rejected, %{reason: reason, decided_at: now})
        end
      end)
    end
  end

  @doc """
  Revokes an active grant, at once (one person). The reason is recorded when given, never
  required. Any proposal waiting to replace the grant is withdrawn in the same transaction.
  """
  @spec revoke(Scope.t(), binary(), binary(), binary() | nil, keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def revoke(%Scope{} = scope, mission_id, grant_id, reason, opts \\ []) do
    now = now(opts)

    with {:ok, actor} <- decider(scope) do
      transaction(fn ->
        with {:ok, row, grant} <- lock_grant(scope.organization_id, mission_id, grant_id),
             :ok <- revocable(grant),
             {:ok, revoked} <- revoke_locked(scope, row, grant, actor, present(reason), now),
             :ok <- withdraw_replacements(scope, grant, actor, now) do
          {:ok, revoked}
        end
      end)
    end
  end

  @doc """
  Narrows an active grant, at once (one person): `changes` may only take access away, judged on
  every field (`GrantNarrowing`); anything else is a widening and needs a new proposal.
  """
  @spec narrow(Scope.t(), binary(), binary(), map(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def narrow(%Scope{} = scope, mission_id, grant_id, changes, opts \\ []) do
    now = now(opts)

    with {:ok, _actor} <- decider(scope) do
      transaction(fn ->
        with {:ok, row, grant} <- lock_grant(scope.organization_id, mission_id, grant_id),
             :ok <- active_now(grant, now),
             {:ok, narrowed} <- GrantNarrowing.narrow(grant, changes) do
          write(scope, row, narrowed, :narrowed, %{
            previous_digest: grant.content_sha256,
            policy: grant.approval_policy,
            decided_at: now
          })
        end
      end)
    end
  end

  @doc """
  Why `scope` can't decide on `grant` now, for the console's flags (U105, #233's pattern: the
  server says, the console never computes it): nil when they can, else `{reason, details}` with
  reason not_a_person | not_admin | not_proposed | proposer | accountable | authors_unknown.
  The same separation check approval runs, against the setting in force now.
  """
  @spec viewer_block(Scope.t(), AutomationGrant.t(), DateTime.t()) ::
          nil | {binary(), map() | nil}
  def viewer_block(%Scope{} = scope, %AutomationGrant{} = grant, now) do
    with {:ok, viewer} <- viewer(scope),
         :proposed <- AutomationGrant.effective_state(grant, now),
         policy = ActivationPolicy.evidence(grant.organization_id, grant.mission_id),
         {:ok, _separated} <- separated(scope, viewer, grant, policy) do
      nil
    else
      {:blocked, reason} ->
        {reason, nil}

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

  defp viewer(%Scope{actor_kind: :user} = scope) do
    case decider(scope) do
      {:ok, id} -> {:ok, id}
      _refused -> {:blocked, "not_admin"}
    end
  end

  defp viewer(_scope), do: {:blocked, "not_a_person"}

  # -- approve -----------------------------------------------------------------------------

  defp approve_locked(scope, row, grant, policy, separated, now) do
    approved =
      rebuild(grant, %{
        lifecycle_state: :active,
        approved_by: separated.approver,
        approved_at: now,
        approval_policy: policy,
        valid_from: now,
        valid_until: DateTime.add(now, grant.validity_seconds, :second)
      })

    # A widening replaces its grant: the old one is revoked first (one active grant per
    # service), as the approver, never the system (ca-security).
    with :ok <- supersede(scope, grant, separated.approver, now) do
      write(scope, row, approved, :approved, %{
        policy: policy,
        separated_from: separated.ids,
        decided_at: now
      })
    end
  end

  defp supersede(_scope, %{replaces_grant_id: nil}, _actor, _now), do: :ok

  defp supersede(scope, grant, actor, now) do
    case lock_grant(grant.organization_id, grant.mission_id, grant.replaces_grant_id) do
      {:ok, row, %{lifecycle_state: :active} = replaced} ->
        reason = "Superseded by #{grant.automation_grant_id}"

        with {:ok, _revoked} <- revoke_locked(scope, row, replaced, actor, reason, now),
             do: :ok

      # Already revoked (and so this proposal withdrawn), or gone: nothing to replace.
      _not_active ->
        {:error, {:automation_grant_not_proposed, %{state: :withdrawn}}}
    end
  end

  defp same_policy(grant) do
    current = ActivationPolicy.evidence(grant.organization_id, grant.mission_id)

    case ActivationPolicy.validate(grant.organization_id, grant.mission_id, grant.approval_policy) do
      :ok -> {:ok, current}
      {:error, _changed} -> {:error, {:approval_policy_changed, %{kind: "automation_grants"}}}
    end
  end

  # Under 'independent' (separation_of_duties): not the proposer, not the replaced grant's
  # proposer, and outside the service's accountable people (an unknown set refuses everyone).
  defp separated(_scope, approver, _grant, %{"separation_of_duties" => required})
       when required != true,
       do: {:ok, %{approver: approver, ids: []}}

  defp separated(scope, approver, grant, _policy) do
    replaced_by = replaced_proposer(grant)
    ids = Enum.reject([grant.proposed_by, replaced_by], &is_nil/1)

    cond do
      approver in ids ->
        {:error,
         {:automation_grant_self_approval_forbidden,
          %{because: "proposed", grantee: grantee(scope, grant)}}}

      true ->
        accountable(scope, approver, grant, ids)
    end
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

  # -- revoke and withdraw -------------------------------------------------------------------

  defp revoke_locked(scope, row, grant, actor, reason, now) do
    revoked =
      rebuild(grant, %{
        lifecycle_state: :revoked,
        revoked_by: actor,
        revoked_at: now,
        revocation_reason: reason || ""
      })

    write(scope, row, revoked, :revoked, %{
      reason: reason,
      policy: grant.approval_policy,
      decided_at: now
    })
  end

  defp withdraw_replacements(scope, grant, actor, now) do
    AutomationGrantRow
    |> where(
      [r],
      r.organization_id == ^grant.organization_id and r.mission_id == ^grant.mission_id and
        r.replaces_grant_id == ^grant.automation_grant_id and r.lifecycle_state == "proposed"
    )
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn row, :ok ->
      proposal = AutomationGrantRow.to_domain(row)

      withdrawn =
        rebuild(proposal, %{lifecycle_state: :withdrawn, withdrawn_by: actor, withdrawn_at: now})

      case write(scope, row, withdrawn, :withdrawn, %{
             reason: "The grant it would replace was revoked.",
             decided_at: now
           }) do
        {:ok, _withdrawn} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # -- shared ------------------------------------------------------------------------------

  defp write(scope, row, grant, decision, attrs) do
    with {:ok, updated} <- row |> AutomationGrantRow.transition_changeset(grant) |> Repo.update(),
         :ok <- AutomationGrantDecisions.record(scope, decision, grant, attrs) do
      {:ok, AutomationGrantRow.to_domain(updated)}
    end
  end

  defp rebuild(%AutomationGrant{} = grant, changes) do
    grant
    |> Map.from_struct()
    |> Map.merge(changes)
    |> Map.put(:content_sha256, nil)
    |> AutomationGrant.new()
  end

  defp lock_grant(organization_id, mission_id, grant_id) do
    AutomationGrantRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.automation_grant_id == ^grant_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :automation_grant_not_found}
      row -> {:ok, row, AutomationGrantRow.to_domain(row)}
    end
  end

  defp proposed(grant, now) do
    case AutomationGrant.effective_state(grant, now) do
      :proposed -> :ok
      state -> {:error, {:automation_grant_not_proposed, not_proposed(grant, state)}}
    end
  end

  # `decided_by` and `decided_at` both or neither (U105).
  defp not_proposed(%{approved_by: by, approved_at: at}, state) when is_binary(by),
    do: %{state: state, decided_by: by, decided_at: at}

  defp not_proposed(%{rejected_by: by, rejected_at: at}, state) when is_binary(by),
    do: %{state: state, decided_by: by, decided_at: at}

  defp not_proposed(%{withdrawn_by: by, withdrawn_at: at}, state) when is_binary(by),
    do: %{state: state, decided_by: by, decided_at: at}

  defp not_proposed(_grant, state), do: %{state: state}

  defp at_digest(%{content_sha256: digest}, digest), do: :ok
  defp at_digest(_grant, _digest), do: {:error, :stale_automation_grant_hash}

  defp revocable(%{lifecycle_state: :active}), do: :ok

  defp revocable(grant),
    do: {:error, {:automation_grant_not_active, %{state: grant.lifecycle_state}}}

  defp active_now(grant, now) do
    case AutomationGrant.effective_state(grant, now) do
      :active -> :ok
      state -> {:error, {:automation_grant_not_active, %{state: state}}}
    end
  end

  # Person-only and org admin (#283; #282's default): a service never decides on a grant.
  defp decider(%Scope{actor_kind: :user, user: %{user_id: id}} = scope) when is_binary(id) do
    case Policy.authorize(scope, :manage_automation_grants, %{
           organization_id: scope.organization_id
         }) do
      :ok -> {:ok, id}
      error -> error
    end
  end

  defp decider(%Scope{}), do: {:error, :authenticated_user_required}

  defp reason(reason, missing) do
    case present(reason) do
      nil -> {:error, missing}
      text -> {:ok, text}
    end
  end

  defp present(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_text), do: nil

  defp transaction(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, grant} -> grant
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
