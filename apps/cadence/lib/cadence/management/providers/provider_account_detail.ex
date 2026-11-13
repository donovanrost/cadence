defmodule Cadence.Management.Providers.ProviderAccountDetail do
  @moduledoc """
  PA2, one provider account for the console (L13): the account and its active version, the
  credential (reference masked) and the guardrails a grant may narrow, and every mission grant
  (active and revoked, latest version each). Org admins only, like PA1 (`:read_organization`).
  The console adapter adds the PA1 row and permissions (composition, `ProviderAccountDirectory`).
  """

  alias Cadence.{Accounts, Missions}
  alias Cadence.Auth.Scope
  alias Cadence.GroundNetworks.{ProviderAccountGrants, ProviderAccounts, ProviderCredentials}

  @spec fetch(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def fetch(%Scope{} = scope, account_id) do
    with {:ok, account, version} <- ProviderAccounts.fetch(scope, account_id) do
      org = scope.organization_id
      credential = credential(org, account_id, version.credential_ref)
      names = org |> Missions.list_missions() |> Map.new(&{&1.mission_id, &1.display_name})

      {:ok,
       %{
         account: account,
         version: version,
         details: %{
           version: version.version,
           credential: credential,
           guardrails: %{
             allowed_services: list(version.guardrails, "allowed_services"),
             allowed_stations: list(version.guardrails, "allowed_stations")
           }
         },
         grants:
           org
           |> ProviderAccountGrants.list_for_account(account_id)
           |> Enum.sort_by(& &1.granted_at, {:desc, DateTime})
           |> Enum.map(&grant_row(&1, names))
       }}
    end
  end

  @doc "A grant as PA2 lists it; `names` maps mission ids to names."
  @spec grant_row(struct(), map()) :: map()
  def grant_row(grant, names) do
    restrictions = grant.restrictions || %{}

    %{
      id: grant.provider_account_grant_id,
      version: grant.version,
      # A mission with no name on record reads as its id (the console shows a string).
      mission: %{id: grant.mission_id, name: Map.get(names, grant.mission_id) || grant.mission_id},
      state: grant.lifecycle_state,
      allowed_services: list(restrictions, "allowed_services"),
      allowed_stations: list(restrictions, "allowed_stations"),
      max_quota: Map.get(restrictions, "max_quota"),
      reason: grant.grant_reason,
      granted_by: person(grant.granted_by),
      granted_at: grant.granted_at,
      revoked_by: person(grant.revoked_by),
      revoked_at: grant.revoked_at,
      revoke_reason: grant.revoke_reason
    }
  end

  defp credential(org, account_id, ref) do
    case ProviderCredentials.fetch(org, account_id, ref) do
      {:ok, credential} ->
        %{ref: mask(ref), version: credential.registry_version, status: credential.status}

      # The account points at a reference with no registered credential (accounts created without
      # validation, older ones): fe-setup 377e08c79 reads "missing".
      {:error, _not_found} ->
        %{ref: mask(ref), version: nil, status: :missing}
    end
  end

  # The reference isn't the secret, but the console only needs to recognise it.
  defp mask(ref) when is_binary(ref) and byte_size(ref) > 8, do: "…" <> String.slice(ref, -6, 6)
  defp mask(_ref), do: "…"

  defp list(map, key) do
    case Map.get(map || %{}, key) do
      [_ | _] = values -> values
      _none -> nil
    end
  end

  defp person(user_id) when is_binary(user_id) do
    case Accounts.fetch_user(user_id) do
      {:ok, user} -> %{id: user.user_id, name: user.display_name || user.email}
      _unknown -> nil
    end
  end

  defp person(_none), do: nil
end
