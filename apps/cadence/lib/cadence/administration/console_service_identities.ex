defmodule Cadence.Administration.ConsoleServiceIdentities do
  @moduledoc """
  Service identities across organizations for the console admin area (L7 AD3), platform
  administrators in admin mode only. Active identities, newest first, at most 500, optionally for
  one organization; capabilities in words. `last_used_at` isn't tracked yet (always null).
  """

  alias Cadence.Accounts
  alias Cadence.Accounts.PlatformDirectory
  alias Cadence.Administration.Access

  @cap 500
  @capabilities [
    %{key: "organization_admin", label: "Organization admin, all missions", needs_mission: false},
    %{key: "mission_admin", label: "Mission admin, one mission", needs_mission: true}
  ]

  @spec list(term(), map()) :: {:ok, map()} | {:error, term()}
  def list(scope, params) do
    with {:ok, _admin} <- Access.authorize(scope) do
      {:ok,
       %{
         service_identities:
           params["organization_id"] |> PlatformDirectory.service_identities(@cap) |> present(),
         capabilities: @capabilities
       }}
    end
  end

  @doc "One active identity of the organization as a list row (AD3), or nil."
  @spec row(binary(), binary()) :: map() | nil
  def row(organization_id, id) do
    case PlatformDirectory.service_identity(organization_id, id) do
      nil -> nil
      found -> hd(present([found]))
    end
  end

  @doc """
  An issue or rotate result for the console: `{service_identity, token}`, where `service_identity`
  is the list row (AD3), so the sheet can show the token once and the row it belongs to.
  """
  @spec issued({:ok, map()} | term(), binary()) :: {:ok, map()} | term()
  def issued({:ok, %{service_identity: identity, api_token: token}}, organization_id) do
    case row(organization_id, identity.id) do
      nil -> {:error, :service_identity_not_found}
      row -> {:ok, %{service_identity: row, token: token}}
    end
  end

  def issued(other, _organization_id), do: other

  defp present(rows) do
    creators = rows |> Enum.map(& &1.created_by_id) |> Enum.reject(&is_nil/1) |> names()

    Enum.map(rows, fn row ->
      creator = row.created_by_id

      row
      |> Map.delete(:created_by_id)
      |> Map.merge(%{
        capabilities: Enum.map(row.capabilities, &%{key: &1, label: label(&1)}),
        created_by: creator && %{name: Map.get(creators, creator)},
        last_used_at: nil
      })
    end)
  end

  @doc "A capability key in words (unknown keys stay as they are)."
  def label(key), do: Enum.find_value(@capabilities, key, &(&1.key == key && &1.label))

  defp names(ids) do
    Map.new(Enum.uniq(ids), fn id ->
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _missing -> {id, nil}
      end
    end)
  end
end
