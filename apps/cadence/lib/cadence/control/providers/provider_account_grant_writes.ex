defmodule Cadence.Control.Providers.ProviderAccountGrantWrites do
  @moduledoc """
  L13 writes on one provider account for the console: grant it to a mission, revoke a grant,
  revoke its credential. The console sends the version it saw; the server rebuilds the rest of
  the evidence `ProviderAccountOperations` admits on (credential reference and its version), so
  a stale view answers which thing changed (`account_changed`, `grant_changed`,
  `credential_changed`, each with the current version) instead of one opaque refusal.
  Org admins only (`:manage_provider_accounts`, checked by the domain writes).
  """

  alias Cadence.Auth.Scope
  alias Cadence.Control.Providers, as: ControlProviders

  alias Cadence.GroundNetworks.{
    ProviderAccountGrant,
    ProviderAccountGrants,
    ProviderAccountOperations,
    ProviderAccounts,
    ProviderCredentials
  }

  @widens %{
    "allowed_services" => "Pick only services the account allows.",
    "allowed_stations" => "Pick only stations the account allows.",
    "max_quota" => "Stay within the account's quota."
  }

  @doc "`{mission_id, allowed_services?, allowed_stations?, max_quota?, reason?, expected_account_version}`."
  @spec grant(Scope.t(), binary(), map()) :: {:ok, ProviderAccountGrant.t()} | {:error, term()}
  def grant(%Scope{} = scope, account_id, params) do
    with {:ok, account, version} <- ProviderAccounts.fetch(scope, account_id),
         :ok <- active(account),
         :ok <- expected(version.version, params, "expected_account_version", :account_changed),
         {:ok, mission_id} <- mission_id(params),
         {:ok, restrictions} <- restrictions(params),
         :ok <- narrows(version.guardrails, restrictions) do
      scope
      |> ProviderAccountGrants.grant(mission_id, account_id, %{
        provider_account_version: version.version,
        restrictions: restrictions,
        grant_reason: text(params["reason"])
      })
      |> case do
        {:error, :mission_not_found} -> {:error, {:invalid_params, %{mission_id: "Not found."}}}
        result -> result
      end
    end
  end

  @doc "`{reason, expected_grant_version}` → `{:ok, %{grant, flagged_reservations}}`."
  @spec revoke_grant(Scope.t(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def revoke_grant(%Scope{} = scope, account_id, grant_id, params) do
    with {:ok, _account, _version} <- ProviderAccounts.fetch(scope, account_id),
         {:ok, grant} <- account_grant(scope.organization_id, account_id, grant_id),
         :ok <- expected(grant.version, params, "expected_grant_version", :grant_changed),
         {:ok, reason} <- reason(params),
         {:ok, revoked, flagged} <-
           ControlProviders.revoke_account_grant_flagging(scope, grant_id, reason) do
      {:ok, %{grant: revoked, flagged_reservations: flagged}}
    end
  end

  @doc "`{reason, expected_credential_version}`: revokes the account's current credential."
  @spec revoke_credential(Scope.t(), binary(), map()) :: :ok | {:error, term()}
  def revoke_credential(%Scope{} = scope, account_id, params) do
    with {:ok, _account, version} <- ProviderAccounts.fetch(scope, account_id),
         {:ok, credential} <-
           ProviderCredentials.fetch(scope.organization_id, account_id, version.credential_ref),
         :ok <- credential_active(credential),
         :ok <-
           expected(
             credential.registry_version,
             params,
             "expected_credential_version",
             :credential_changed
           ),
         {:ok, reason} <- reason(params),
         {:ok, _done} <-
           ProviderAccountOperations.execute(scope, "revoke_provider_credential", %{
             "provider_account_id" => account_id,
             "expected_account_version" => version.version,
             "credential_ref" => credential.provider_credential_ref,
             "expected_credential_version" => credential.registry_version,
             "reason" => reason
           }) do
      :ok
    else
      # Changed between the check above and the domain's own admission.
      {:error, :stale_provider_account} ->
        {:error, {:credential_changed, current(scope, account_id)}}

      error ->
        error
    end
  end

  defp current(scope, account_id) do
    with {:ok, _account, version} <- ProviderAccounts.fetch(scope, account_id),
         {:ok, credential} <-
           ProviderCredentials.fetch(scope.organization_id, account_id, version.credential_ref) do
      %{version: credential.registry_version}
    else
      _gone -> %{version: nil}
    end
  end

  defp active(%{lifecycle_state: :active}), do: :ok
  defp active(_account), do: {:error, :account_archived}

  defp credential_active(%{status: :active}), do: :ok
  defp credential_active(_credential), do: {:error, :credential_already_revoked}

  defp account_grant(organization_id, account_id, grant_id) do
    case ProviderAccountGrants.fetch_active_for_system(organization_id, grant_id) do
      {:ok, %{provider_account_id: ^account_id} = grant} ->
        {:ok, grant}

      {:ok, _other_account} ->
        {:error, :account_grant_not_found}

      {:error, :provider_account_grant_revoked} ->
        revoked_here(organization_id, account_id, grant_id)

      {:error, _not_found} ->
        {:error, :account_grant_not_found}
    end
  end

  # Only say "already revoked" for a grant of this account.
  defp revoked_here(organization_id, account_id, grant_id) do
    if Enum.any?(
         ProviderAccountGrants.list_for_account(organization_id, account_id),
         &(&1.provider_account_grant_id == grant_id)
       ),
       do: {:error, :grant_already_revoked},
       else: {:error, :account_grant_not_found}
  end

  defp expected(current, params, key, changed) do
    case params[key] do
      ^current -> :ok
      seen when is_integer(seen) -> {:error, {changed, %{version: current}}}
      _missing -> {:error, {:invalid_params, %{key => "Send the version you loaded."}}}
    end
  end

  defp mission_id(%{"mission_id" => id}) when is_binary(id) and id != "", do: {:ok, id}
  defp mission_id(_params), do: {:error, {:invalid_params, %{mission_id: "Choose a mission."}}}

  defp reason(params) do
    case text(params["reason"]) do
      nil -> {:error, {:invalid_params, %{reason: "Say why."}}}
      reason -> {:ok, reason}
    end
  end

  defp restrictions(params) do
    Enum.reduce_while(~w(allowed_services allowed_stations max_quota), {:ok, %{}}, fn key,
                                                                                      {:ok, acc} ->
      case restriction(key, params[key]) do
        :none -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        :invalid -> {:halt, {:error, {:invalid_params, %{key => invalid_message(key)}}}}
      end
    end)
  end

  defp restriction(_key, value) when value in [nil, []], do: :none
  defp restriction("max_quota", value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp restriction("max_quota", _value), do: :invalid

  defp restriction(_key, values) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and &1 != "")),
      do: {:ok, Enum.uniq(values)},
      else: :invalid
  end

  defp restriction(_key, _value), do: :invalid

  defp invalid_message("max_quota"), do: "Use a whole number, 0 or more."
  defp invalid_message(_key), do: "Use a list of names."

  # Which field widens the account's guardrails, so the console can mark it.
  defp narrows(guardrails, restrictions) do
    case Enum.find(restrictions, fn {key, value} ->
           not ProviderAccountGrant.restrictions_narrow?(guardrails, %{key => value})
         end) do
      nil -> :ok
      {key, _value} -> {:error, {:invalid_params, %{key => Map.fetch!(@widens, key)}}}
    end
  end

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> String.slice(text, 0, 500)
    end
  end

  defp text(_value), do: nil
end
