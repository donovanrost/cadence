defmodule Cadence.Management.ProviderAccountDirectory do
  @moduledoc """
  PA1, the organization's ground-network provider accounts for the console:
  each account's connection status and the missions whose providers use it.
  `test/2` runs the real credential check (`ProviderAccounts.validate/3`).

  Status: `credential_revoked` when the credential is revoked (L13); `not_checked`
  before a first successful validation; otherwise `connected`. `expires_at` is
  always `nil` (credentials carry no expiry yet), so there's no `expiring`.
  """

  alias Cadence.{Accounts, Missions}
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.GroundNetworks.{
    MissionProvider,
    MissionProviders,
    ProviderAccount,
    ProviderAccounts
  }

  @spec list(Scope.t()) :: {:ok, map()} | {:error, term()}
  def list(%Scope{organization_id: organization_id} = scope) do
    with {:ok, accounts} <- ProviderAccounts.list(scope) do
      used_by = missions_by_account(organization_id)

      {:ok,
       %{
         accounts:
           Enum.map(accounts, fn {account, version} -> row(account, version, used_by) end),
         adapters: Enum.map(MissionProvider.provider_types(), &%{key: &1, label: label(&1)}),
         permissions: permissions(scope)
       }}
    end
  end

  @doc """
  Checks the account's credential reference: that it exists, isn't revoked, and resolves in its
  secret backend. It doesn't call the provider itself yet, so `checked` is `["reference"]`.
  `{ok, checked, failed: nil | "reference", reason, message}` (ux: say which part failed).
  """
  @spec test(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def test(%Scope{} = scope, account_id) do
    case ProviderAccounts.validate(scope, account_id) do
      {:ok, _account} ->
        {:ok, result(true, nil, nil, "The secret reference resolves.")}

      {:error, reason}
      when reason in [:forbidden, :scope_mismatch, :provider_account_not_found] ->
        {:error, reason}

      {:error, reason} ->
        {:ok, result(false, "reference", reason_code(reason), reference_message(reason))}
    end
  end

  defp result(ok, failed, reason, message),
    do: %{ok: ok, checked: ["reference"], failed: failed, reason: reason, message: message}

  defp reference_message(:provider_credential_not_found),
    do: "No credential is registered under this reference."

  defp reference_message(:provider_account_credential_revoked),
    do: "The credential was revoked. Register a new reference."

  defp reference_message({:provider_account_credential_unavailable, reason}),
    do: "The secret backend couldn't resolve the reference (#{describe(reason)})."

  defp reference_message(reason), do: "The credential check failed (#{describe(reason)})."

  defp reason_code({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code(_reason), do: "unknown"

  @spec permissions(Scope.t()) :: [binary()]
  def permissions(scope) do
    params = %{organization_id: scope.organization_id}

    if Policy.authorize(scope, :manage_provider_accounts, params) == :ok,
      do: ["provider_accounts.manage"],
      else: []
  end

  @doc "One account's PA1 row (PA2 builds on it)."
  @spec account_row(ProviderAccount.t(), struct()) :: map()
  def account_row(%ProviderAccount{} = account, version),
    do: row(account, version, missions_by_account(account.organization_id))

  defp row(%ProviderAccount{} = account, version, used_by) do
    %{
      id: account.provider_account_id,
      name: account.display_name,
      provider: %{key: version.provider_type, label: label(version.provider_type)},
      # polling | webhook | hybrid | disabled: whether Cadence polls the provider for events.
      event_ingestion_mode: version.event_ingestion_mode,
      status: status(account),
      status_detail: detail(account),
      expires_at: nil,
      last_success_at: account.last_validated_at,
      missions: Map.get(used_by, account.provider_account_id, []),
      added_at: version.created_at,
      added_by: added_by(version.created_by)
    }
  end

  defp status(%ProviderAccount{credential_status: :revoked}), do: :credential_revoked
  defp status(%ProviderAccount{last_validated_at: nil}), do: :not_checked
  defp status(_account), do: :connected

  defp detail(%ProviderAccount{credential_status: :revoked}),
    do: "The credential was revoked. Point the account at a new reference to reconnect."

  defp detail(%ProviderAccount{last_validated_at: nil}), do: "Not checked yet."
  defp detail(_account), do: nil

  defp missions_by_account(organization_id) do
    for mission <- Missions.list_missions(organization_id),
        provider <- MissionProviders.list_providers(organization_id, mission.mission_id),
        is_binary(provider.provider_account_id),
        reduce: %{} do
      acc ->
        entry = %{id: mission.mission_id, name: mission.display_name}
        Map.update(acc, provider.provider_account_id, [entry], &Enum.uniq([entry | &1]))
    end
  end

  defp added_by(user_id) when is_binary(user_id) do
    case Accounts.fetch_user(user_id) do
      {:ok, user} -> %{name: user.display_name || user.email}
      _system -> nil
    end
  end

  defp added_by(_none), do: nil

  defp label(type), do: type |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp describe({reason, _detail}), do: describe(reason)

  defp describe(reason) when is_atom(reason),
    do: reason |> to_string() |> String.replace("_", " ")

  defp describe(_reason), do: "unknown error"
end
