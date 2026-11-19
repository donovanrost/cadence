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

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{AutomationGrant, AutomationGrantDecisions, GrantNarrowing}
  alias Cadence.ContactPlanning.GrantSeparation
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Contacts.Store.AutomationGrantRow
  alias Cadence.Repo

  defdelegate viewer_block(scope, grant, now), to: GrantSeparation
  defdelegate confers(scope, mission_id, grant), to: GrantSeparation

  @doc "Approves the proposal read at `digest`."
  @spec approve(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, grant_id, digest, opts \\ []) do
    now = now(opts)

    with {:ok, approver} <- GrantSeparation.decider(scope) do
      stable_transaction(scope.organization_id, fn ->
        approve_in(scope, mission_id, grant_id, digest, approver, now)
      end)
    end
  end

  @doc "Rejects a proposal, with a reason."
  @spec reject(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def reject(%Scope{} = scope, mission_id, grant_id, reason, opts \\ []) do
    now = now(opts)

    with {:ok, actor} <- GrantSeparation.decider(scope),
         {:ok, reason} <- reason(reason, :automation_grant_rejection_reason_required) do
      transaction(fn -> reject_in(scope, mission_id, grant_id, actor, reason, now) end)
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

    with {:ok, actor} <- GrantSeparation.decider(scope) do
      transaction(fn -> revoke_in(scope, mission_id, grant_id, actor, present(reason), now) end)
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

    with {:ok, _actor} <- GrantSeparation.decider(scope) do
      transaction(fn -> narrow_in(scope, mission_id, grant_id, changes, now) end)
    end
  end

  defp approve_in(scope, mission_id, grant_id, digest, approver, now) do
    with {:ok, row, grant} <- lock_grant(scope.organization_id, mission_id, grant_id),
         :ok <- proposed(grant, now),
         :ok <- at_digest(grant, digest),
         {:ok, policy} <- same_policy(grant),
         :ok <- confers(scope, mission_id, grant),
         {:ok, separated} <- GrantSeparation.check(scope, approver, grant, policy) do
      approve_locked(scope, row, grant, policy, separated, now)
    end
  end

  defp reject_in(scope, mission_id, grant_id, actor, reason, now) do
    with {:ok, row, grant} <- lock_grant(scope.organization_id, mission_id, grant_id),
         :ok <- proposed(grant, now) do
      rejected =
        rebuild(grant, %{
          lifecycle_state: :rejected,
          ending: %{by: actor, at: now, reason: reason}
        })

      write(scope, row, rejected, :rejected, %{reason: reason, decided_at: now})
    end
  end

  defp revoke_in(scope, mission_id, grant_id, actor, reason, now) do
    with {:ok, row, grant} <- lock_grant(scope.organization_id, mission_id, grant_id),
         :ok <- revocable(grant),
         {:ok, revoked} <- revoke_locked(scope, row, grant, actor, reason, now),
         :ok <- withdraw_replacements(scope, grant, actor, now) do
      {:ok, revoked}
    end
  end

  defp narrow_in(scope, mission_id, grant_id, changes, now) do
    with {:ok, row, grant} <- lock_grant(scope.organization_id, mission_id, grant_id),
         :ok <- active_now(grant, now),
         {:ok, narrowed} <- GrantNarrowing.narrow(grant, changes) do
      write(scope, row, narrowed, :narrowed, %{
        previous_digest: grant.content_sha256,
        policy: grant.approval_policy,
        decided_at: now
      })
    end
  end

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
  # -- revoke and withdraw -------------------------------------------------------------------

  defp revoke_locked(scope, row, grant, actor, reason, now) do
    revoked =
      rebuild(grant, %{
        lifecycle_state: :revoked,
        ending: %{by: actor, at: now, reason: reason}
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
        rebuild(proposal, %{lifecycle_state: :withdrawn, ending: %{by: actor, at: now}})

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
  defp not_proposed(%{ending: %{by: by, at: at}}, state),
    do: %{state: state, decided_by: by, decided_at: at}

  defp not_proposed(%{approved_by: by, approved_at: at}, state) when is_binary(by),
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

  # The approval setting held stable first (Governance.ActivationLocks' order), then the rows.
  defp stable_transaction(organization_id, fun),
    do: ActivationPolicy.with_stable_policy(organization_id, fn -> transaction(fun) end)

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
