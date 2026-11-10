defmodule Cadence.Reads.OrganizationAudit.ProviderAccountEvents do
  @moduledoc """
  Provider account changes for the organization audit (`kind: "provider_accounts"`): added,
  settings changed (a new version), renamed, retired, credential reference added / rotated /
  revoked, and mission access granted / revoked. Read from the provider audit ledger
  (`GroundNetworks.ProviderAudit`), by exact action, so credential resolutions and provider
  events stay out of it.
  """

  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderAudit}

  @actions ~w(
    provider_account.created provider_account.versioned provider_account.renamed
    provider_account.retired provider_credential.created provider_credential.rotated
    provider_credential.revoked provider_account_grant.granted provider_account_grant.revoked
  )
  @limit 500

  @spec list(binary()) :: [map()]
  def list(organization_id) do
    entries =
      organization_id
      |> ProviderAudit.list_entries(actions: @actions, limit: @limit)
      |> Enum.filter(&(&1.outcome in ["succeeded", :succeeded]))

    names = names(organization_id, entries)
    Enum.map(entries, &event(&1, names))
  end

  defp event(entry, names) do
    id = account_id(entry)
    name = Map.get(names, id) || id
    doc = entry.current_document || %{}

    %{
      id: "provider_accounts:#{entry.provider_audit_entry_id}",
      at: entry.recorded_at,
      actor: actor(entry.actor_document),
      kind: "provider_accounts",
      action: action(entry.action, name, doc),
      target: %{kind: "provider_account", id: id, label: name},
      mission: entry.mission_id && %{id: entry.mission_id, name: nil},
      reason: doc["reason"]
    }
  end

  defp action("provider_account.created", name, _doc), do: "Added provider account #{name}"

  defp action("provider_account.versioned", name, doc),
    do: "Changed #{name}'s settings (version #{doc["account_version"]})"

  defp action("provider_account.renamed", _name, doc),
    do: "Renamed provider account #{doc["from"]} to #{doc["to"]}"

  defp action("provider_account.retired", name, _doc), do: "Retired provider account #{name}"
  defp action("provider_credential.created", name, _doc), do: "Set #{name}'s credential reference"

  defp action("provider_credential.rotated", name, _doc),
    do: "Rotated #{name}'s credential reference"

  defp action("provider_credential.revoked", name, _doc),
    do: "Revoked #{name}'s credential reference"

  defp action("provider_account_grant.granted", name, _doc),
    do: "Gave a mission access to #{name}"

  defp action("provider_account_grant.revoked", name, _doc),
    do: "Removed a mission's access to #{name}"

  defp action(other, _name, _doc), do: other

  defp actor(%{"kind" => kind} = doc),
    do: %{kind: kind, id: doc["id"] || doc["user_id"], name: doc["name"] || doc["display_name"]}

  defp actor(_none), do: nil

  # Each account's current name, retired ones included.
  defp names(organization_id, entries) do
    entries
    |> Enum.map(&account_id/1)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn id ->
      case ProviderAccounts.fetch_for_system(organization_id, id) do
        {:ok, account, _version} -> {id, account.display_name}
        _missing -> {id, nil}
      end
    end)
  end

  defp account_id(entry), do: entry.references && entry.references.provider_account_id
end
