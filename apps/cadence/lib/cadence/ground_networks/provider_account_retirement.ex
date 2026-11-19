defmodule Cadence.GroundNetworks.ProviderAccountRetirement do
  @moduledoc """
  Retires (archives) an organization's provider account. Refused with `:in_use` while any
  active mission provider references it, naming those missions, so an account still serving a
  mission can't disappear from under it. Retirement is audited; the account's versions and
  history stay.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.GroundNetworks.MissionProviders.ProviderRow
  alias Cadence.GroundNetworks.{ProviderAccount, ProviderAudit, ProviderAuditEntry}
  alias Cadence.GroundNetworks.ProviderAccounts.AccountRow
  alias Cadence.Repo
  alias Ecto.Multi

  @spec retire(Scope.t(), binary(), String.t() | nil) ::
          {:ok, ProviderAccount.t()}
          | {:error, :forbidden | :provider_account_not_found | :already_retired}
          | {:error, {:in_use, [%{mission_id: binary(), provider_id: binary()}]}}
  def retire(%Scope{} = scope, provider_account_id, reason \\ nil) do
    with :ok <- authorize(scope) do
      Repo.transaction(fn -> retire_locked(scope, provider_account_id, reason) end)
    end
  end

  defp retire_locked(scope, provider_account_id, reason) do
    org = scope.organization_id

    with {:ok, row} <- lock_account(org, provider_account_id),
         :ok <- active(row),
         [] <- users(org, provider_account_id) do
      archive(scope, row, reason)
    else
      [_ | _] = users -> Repo.rollback({:in_use, users})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp authorize(scope) do
    case Policy.authorize(scope, :manage_provider_accounts, %{
           organization_id: scope.organization_id
         }) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end

  defp lock_account(org, id) do
    AccountRow
    |> where([a], a.organization_id == ^org and a.provider_account_id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :provider_account_not_found}
      row -> {:ok, row}
    end
  end

  defp active(%{lifecycle_state: "active"}), do: :ok
  defp active(_row), do: {:error, :already_retired}

  # Mission providers are versioned; only each provider's latest version says whether it is
  # still active (archiving writes a new, archived version).
  defp users(org, id) do
    latest =
      from(p in ProviderRow,
        where: p.organization_id == ^org,
        group_by: [p.mission_id, p.provider_id],
        select: %{mission_id: p.mission_id, provider_id: p.provider_id, version: max(p.version)}
      )

    ProviderRow
    |> join(:inner, [p], l in subquery(latest),
      on:
        p.mission_id == l.mission_id and p.provider_id == l.provider_id and p.version == l.version
    )
    |> where(
      [p],
      p.organization_id == ^org and p.provider_account_id == ^id and
        p.lifecycle_state != "archived"
    )
    |> select([p], %{mission_id: p.mission_id, provider_id: p.provider_id})
    |> Repo.all()
  end

  defp archive(scope, row, reason) do
    %ProviderAccount{} = account = AccountRow.to_domain(row)
    now = DateTime.utc_now()

    retired = %ProviderAccount{
      account
      | lifecycle_state: :archived,
        metadata:
          Map.put(account.metadata || %{}, "retired", %{
            "at" => DateTime.to_iso8601(now),
            "by" => Scope.audit_actor(scope),
            "reason" => reason
          })
    }

    audit =
      ProviderAuditEntry.new(%{
        organization_id: account.organization_id,
        provider_account_id: account.provider_account_id,
        action: "provider_account.retired",
        outcome: "succeeded",
        recorded_at: now,
        source_document: %{"kind" => "provider_account_registry"},
        actor_document: Scope.audit_actor(scope),
        current_document: %{"reason" => reason}
      })

    Multi.new()
    |> Multi.update(:account, AccountRow.changeset(row, retired))
    |> ProviderAudit.put_entry(:audit_entry, audit)
    |> Repo.transaction()
    |> case do
      {:ok, %{account: persisted}} -> AccountRow.to_domain(persisted)
      {:error, _operation, reason, _changes} -> Repo.rollback(reason)
    end
  end
end
