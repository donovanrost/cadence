defmodule Cadence.GroundNetworks.ProviderAccountOperations do
  @moduledoc "Scoped provider-account effects and observed-version admission."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.GroundNetworks.{ProviderAccountGrants, ProviderAccounts, ProviderCredentials}

  @actions ~w(validate_provider_account rotate_provider_credential revoke_provider_credential grant_provider_account_mission revoke_provider_account_mission)

  def execute(%Scope{} = scope, action, params) when action in @actions and is_map(params) do
    with {:ok, account_id} <- required_param(params, "provider_account_id"),
         :ok <- admit(scope, account_id, params) do
      provider_account_action(scope, action, account_id, params)
    end
  end

  def execute(_scope, _action, _params), do: {:error, :invalid_input}

  defp provider_account_action(scope, "validate_provider_account", account_id, _params),
    do: ProviderAccounts.validate(scope, account_id)

  defp provider_account_action(scope, "rotate_provider_credential", account_id, _params) do
    with {:ok, _account, version} <-
           ProviderAccounts.fetch(scope, account_id),
         {:ok, _result} <-
           ProviderCredentials.rotate(
             scope,
             account_id,
             version.credential_ref,
             provider_account_opts()
           ) do
      {:ok, %{completed: true}}
    end
  end

  defp provider_account_action(scope, "revoke_provider_credential", account_id, _params) do
    with {:ok, _account, version} <-
           ProviderAccounts.fetch(scope, account_id),
         {:ok, _result} <-
           ProviderCredentials.revoke(
             scope,
             account_id,
             version.credential_ref,
             provider_account_opts()
           ) do
      {:ok, %{completed: true}}
    end
  end

  defp provider_account_action(scope, "grant_provider_account_mission", account_id, params) do
    grant = input_map(params, "grant")

    with {:ok, mission_id} <- required_param(grant, "mission_id") do
      ProviderAccountGrants.grant(
        scope,
        mission_id,
        account_id,
        %{
          provider_account_version: value(params, "expected_account_version"),
          restrictions: grant_restrictions(grant),
          grant_reason: optional_text(value(grant, "grant_reason"))
        }
      )
    end
  end

  defp provider_account_action(scope, "revoke_provider_account_mission", account_id, params) do
    with {:ok, grant_id} <- required_param(params, "grant-id"),
         {:ok, grant} <-
           ProviderAccountGrants.fetch_active_for_system(scope.organization_id, grant_id),
         true <- grant.provider_account_id == account_id,
         true <- grant.version === value(params, "expected_grant_version") do
      ControlProviders.revoke_account_grant(
        scope,
        grant_id,
        "Revoked by organization administrator"
      )
    else
      false ->
        {:error, :stale_provider_account}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def admit(scope, account_id, params) do
    with :ok <-
           Policy.authorize(scope, :manage_provider_accounts, %{
             organization_id: scope.organization_id
           }),
         {:ok, _account, version} <- ProviderAccounts.fetch(scope, account_id),
         {:ok, credential} <-
           ProviderCredentials.fetch(scope.organization_id, account_id, version.credential_ref),
         true <- version.version === value(params, "expected_account_version"),
         true <- credential.provider_credential_ref == value(params, "credential_ref"),
         true <- credential.registry_version === value(params, "expected_credential_version") do
      :ok
    else
      false ->
        {:error, :stale_provider_account}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp provider_account_opts,
    do: Application.get_env(:cadence_web, :provider_account_live_opts, [])

  defp grant_restrictions(params) do
    %{
      "allowed_services" => comma_list(value(params, "allowed_services")),
      "allowed_stations" => comma_list(value(params, "allowed_stations")),
      "max_quota" => nonnegative_integer(value(params, "max_quota"))
    }
    |> Map.reject(fn {_key, value} -> value in [nil, []] end)
  end

  defp comma_list(value) do
    case optional_text(value) do
      nil -> []
      text -> text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  defp nonnegative_integer(value) do
    case optional_text(value) do
      nil ->
        nil

      text ->
        case Integer.parse(text) do
          {number, ""} when number >= 0 -> number
          _other -> -1
        end
    end
  end

  defp optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp optional_text(_value), do: nil

  defp input_map(params, key) when is_map(params) do
    case value(params, key) do
      map when is_map(map) -> map
      _other -> %{}
    end
  end

  defp input_map(_params, _key), do: %{}

  defp required_param(params, key) do
    case value(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :invalid_input}
    end
  end

  defp value(params, key) when is_map(params) and is_binary(key) do
    Map.get(params, key) || Map.get(params, atom_key(key))
  end

  defp atom_key("provider_account"), do: :provider_account
  defp atom_key("provider_account_id"), do: :provider_account_id
  defp atom_key("expected_account_version"), do: :expected_account_version
  defp atom_key("expected_credential_version"), do: :expected_credential_version
  defp atom_key("expected_grant_version"), do: :expected_grant_version
  defp atom_key("credential_ref"), do: :credential_ref
  defp atom_key("grant"), do: :grant
  defp atom_key("grant-id"), do: :grant_id
  defp atom_key("notification_id"), do: :notification_id
  defp atom_key("organization"), do: :organization
  defp atom_key("organization_id"), do: :organization_id
  defp atom_key("service_identity"), do: :service_identity
  defp atom_key("runtime_decision_filters"), do: :runtime_decision_filters
  defp atom_key("invite"), do: :invite
  defp atom_key("display_name"), do: :display_name
  defp atom_key("slug"), do: :slug
  defp atom_key("mission_id"), do: :mission_id
  defp atom_key("allowed_services"), do: :allowed_services
  defp atom_key("allowed_stations"), do: :allowed_stations
  defp atom_key("max_quota"), do: :max_quota
  defp atom_key("grant_reason"), do: :grant_reason
  defp atom_key("email"), do: :email
  defp atom_key("membership_role"), do: :membership_role
  defp atom_key("grant_platform_admin"), do: :grant_platform_admin
  defp atom_key(_key), do: nil
end
