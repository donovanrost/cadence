defmodule Cadence.Reads.Comms.ProviderAccountDirectory do
  @moduledoc "Organization-scoped Provider Account directory, independent of frontend delivery."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ExtensionCatalog
  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}

  def load(%Scope{} = scope) do
    with :ok <-
           Policy.authorize(scope, :manage_provider_accounts, %{
             organization_id: scope.organization_id
           }),
         {:ok, account_pairs} <- ProviderAccounts.list(scope) do
      rows =
        Enum.map(account_pairs, fn {account, version} ->
          account
          |> provider_account_card(version, credential_for(scope, account, version))
          |> Map.put(:__dom_id, "provider-account-#{account.provider_account_id}")
        end)

      {:ok,
       %{
         organization_id: scope.organization_id,
         count: length(rows),
         provider_accounts: rows
       }}
    end
  end

  defp credential_for(scope, account, version) do
    case ProviderCredentials.fetch(
           scope.organization_id,
           account.provider_account_id,
           version.credential_ref
         ) do
      {:ok, credential} -> credential
      {:error, _reason} -> nil
    end
  end

  defp provider_account_card(account, version, credential) do
    %{
      id: "provider-account-#{account.provider_account_id}",
      display_name: account.display_name,
      provider_account_id: account.provider_account_id,
      status: account_health_status(account) |> Atom.to_string(),
      status_label: account_health_label(account),
      provider: provider_label(version),
      config: "v#{account.active_version}",
      credential: credential_label(credential),
      events: ingestion_label(version),
      endpoint: endpoint_summary(version),
      href:
        "/provider-accounts/#{URI.encode(to_string(account.provider_account_id), &URI.char_unreserved?/1)}"
    }
  end

  defp account_health_status(%{credential_status: :revoked}), do: :blocked
  defp account_health_status(%{event_ingestion_status: :degraded}), do: :attention
  defp account_health_status(%{last_validated_at: %DateTime{}}), do: :ready
  defp account_health_status(_account), do: :info
  defp account_health_label(%{credential_status: :revoked}), do: "Credential revoked"
  defp account_health_label(%{event_ingestion_status: :degraded}), do: "Degraded"
  defp account_health_label(%{last_validated_at: %DateTime{}}), do: "Validated"
  defp account_health_label(_account), do: "Not validated"

  defp provider_label(version) do
    case ExtensionCatalog.fetch_provider_connector(Atom.to_string(version.provider_type)) do
      {:ok, connector} -> connector.label
      {:error, _reason} -> version.provider_type |> Atom.to_string() |> String.capitalize()
    end
  end

  defp credential_label(nil), do: "Unavailable"

  defp credential_label(credential),
    do:
      "#{credential.status |> Atom.to_string() |> String.capitalize()} · v#{credential.registry_version}"

  defp ingestion_label(version),
    do: version.event_ingestion_mode |> Atom.to_string() |> String.capitalize()

  defp endpoint_summary(version) do
    uri = URI.parse(version.base_url)
    location = version.region_ref || version.environment_ref
    Enum.join(Enum.reject([uri.host, location], &is_nil/1), " · ")
  end
end
