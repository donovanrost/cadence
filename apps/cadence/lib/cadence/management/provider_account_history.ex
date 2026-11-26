defmodule Cadence.Management.ProviderAccountHistory do
  @moduledoc """
  A provider account's version history for the console (PA1, backlog): newest first, each with
  who made it, when, and what changed from the version before. Credentials appear only as their
  reference (`credential_ref`); Cadence never holds the secret itself.
  """

  alias Cadence.Accounts
  alias Cadence.Accounts.MemberNames
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

      people = MemberNames.members(scope.organization_id, Enum.map(versions, & &1.created_by))

      {:ok,
       %{
         id: account.provider_account_id,
         name: account.display_name,
         current_version: current.version,
         versions:
           [nil | versions]
           |> Enum.zip(versions)
           |> Enum.map(fn {before, version} -> entry(before, version, people) end)
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

  defp entry(before, version, people) do
    %{
      version: version.version,
      created_at: version.created_at,
      actor: actor(version.created_by, people),
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

  # #146 (#468): a person is named, and keeps their id, only while an active member of the
  # account's organization (one batched lookup per read), never by email. A person who isn't
  # (a platform admin, someone who has left) reads id and name nil; a non-person stays system.
  defp actor(id, people) when is_binary(id) and id != "" do
    case Map.fetch(people, id) do
      {:ok, name} -> %{kind: "user", id: id, name: name}
      :error -> outsider(id)
    end
  end

  defp actor(_none, _people), do: nil

  # Only for ids that aren't members: whether the id is a person at all (its kind).
  defp outsider(id) do
    case Accounts.fetch_user(id) do
      {:ok, _person} -> %{kind: "user", id: nil, name: nil}
      _not_a_user -> %{kind: "system", id: id, name: nil}
    end
  end
end
