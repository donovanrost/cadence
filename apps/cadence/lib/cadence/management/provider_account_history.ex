defmodule Cadence.Management.ProviderAccountHistory do
  @moduledoc """
  A provider account's version history for the console (PA1, backlog): newest first, each with
  who made it, when, and what changed from the version before. Credentials appear only as their
  reference (`credential_ref`); Cadence never holds the secret itself.
  """

  alias Cadence.Accounts
  alias Cadence.Auth.Scope
  alias Cadence.GroundNetworks.ProviderAccounts

  @fields [
    {:base_url, "Endpoint"},
    {:region_ref, "Region"},
    {:environment_ref, "Environment"},
    {:client_key, "Client key"},
    {:credential_ref, "Credential reference"},
    {:event_ingestion_mode, "Event ingestion"},
    {:event_configuration, "Event settings"},
    {:request_policy, "Request policy"},
    {:guardrails, "Guardrails"},
    {:provider_configuration, "Provider settings"}
  ]

  @spec versions(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def versions(%Scope{} = scope, provider_account_id) do
    with {:ok, account, current} <- ProviderAccounts.fetch(scope, provider_account_id) do
      versions =
        Enum.flat_map(
          1..current.version,
          &version(scope.organization_id, provider_account_id, &1)
        )

      {:ok,
       %{
         id: account.provider_account_id,
         name: account.display_name,
         current_version: current.version,
         versions:
           [nil | versions]
           |> Enum.zip(versions)
           |> Enum.map(fn {before, version} -> entry(before, version) end)
           |> Enum.reverse()
       }}
    end
  end

  defp version(organization_id, provider_account_id, number) do
    case ProviderAccounts.fetch_version(organization_id, provider_account_id, number) do
      {:ok, version} -> [version]
      _missing -> []
    end
  end

  defp entry(before, version) do
    %{
      version: version.version,
      created_at: version.created_at,
      actor: actor(version.created_by),
      changes: if(before, do: changes(before, version), else: [])
    }
  end

  defp changes(before, version) do
    for {field, label} <- @fields,
        Map.get(before, field) != Map.get(version, field),
        do: %{
          field: field,
          label: label,
          before: Map.get(before, field),
          after: Map.get(version, field)
        }
  end

  defp actor(id) when is_binary(id) and id != "" do
    case Accounts.fetch_user(id) do
      {:ok, user} -> %{kind: "user", id: id, name: user.display_name || user.email}
      _not_a_user -> %{kind: "system", id: id, name: nil}
    end
  end

  defp actor(_none), do: nil
end
