defmodule Cadence.GroundNetworks.ProviderAccountRename do
  @moduledoc """
  Renames a provider account. The display name is presentation on the account, not part of its
  versioned connection settings, so renaming writes no new version. It is audited.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.GroundNetworks.{ProviderAccount, ProviderAudit, ProviderAuditEntry}
  alias Cadence.GroundNetworks.ProviderAccounts.AccountRow
  alias Cadence.Repo
  alias Ecto.Multi

  @spec rename(Scope.t(), binary(), String.t()) ::
          {:ok, ProviderAccount.t()}
          | {:error, :forbidden | :provider_account_not_found | :invalid_display_name}
  def rename(%Scope{} = scope, provider_account_id, display_name) do
    with :ok <- authorize(scope),
         {:ok, name} <- name(display_name) do
      Repo.transaction(fn -> rename_locked(scope, provider_account_id, name) end)
    end
  end

  defp rename_locked(scope, provider_account_id, name) do
    case lock_account(scope.organization_id, provider_account_id) do
      nil -> Repo.rollback(:provider_account_not_found)
      row -> write(scope, row, name)
    end
  end

  defp write(scope, row, name) do
    %ProviderAccount{} = account = AccountRow.to_domain(row)
    renamed = %ProviderAccount{account | display_name: name}

    audit =
      ProviderAuditEntry.new(%{
        organization_id: account.organization_id,
        provider_account_id: account.provider_account_id,
        action: "provider_account.renamed",
        outcome: "succeeded",
        recorded_at: DateTime.utc_now(),
        source_document: %{"kind" => "provider_account_registry"},
        actor_document: Scope.audit_actor(scope),
        current_document: %{"from" => account.display_name, "to" => name}
      })

    Multi.new()
    |> Multi.update(:account, AccountRow.changeset(row, renamed))
    |> ProviderAudit.put_entry(:audit_entry, audit)
    |> Repo.transaction()
    |> case do
      {:ok, %{account: persisted}} -> AccountRow.to_domain(persisted)
      {:error, _operation, reason, _changes} -> Repo.rollback(reason)
    end
  end

  defp lock_account(org, id) do
    AccountRow
    |> where([a], a.organization_id == ^org and a.provider_account_id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp name(value) when is_binary(value) do
    case String.trim(value) do
      trimmed when byte_size(trimmed) in 1..120 -> {:ok, trimmed}
      _invalid -> {:error, :invalid_display_name}
    end
  end

  defp name(_value), do: {:error, :invalid_display_name}

  defp authorize(scope) do
    case Policy.authorize(scope, :manage_provider_accounts, %{
           organization_id: scope.organization_id
         }) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end
end
