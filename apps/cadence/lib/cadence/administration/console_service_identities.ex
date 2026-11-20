defmodule Cadence.Administration.ConsoleServiceIdentities do
  @moduledoc """
  Service identities across organizations for the console admin area (L7 AD3), platform
  administrators in admin mode only. Active identities, newest first, at most 500, optionally for
  one organization; capabilities in words. `last_used_at` isn't tracked yet (always null).
  `created_by` names the person by display name only, never the email (`PlatformNames`, #470).
  """

  alias Cadence.Accounts.PlatformDirectory
  alias Cadence.Administration.{Access, PlatformNames}

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
           params["organization_id"]
           |> PlatformDirectory.service_identities(@cap)
           |> present(scope),
         capabilities: @capabilities
       }}
    end
  end

  @doc """
  One active identity of the organization as a list row (AD3), or nil. Like every read here, it
  admits only a platform administrator in admin mode (`Access`, #470).
  """
  @spec row(term(), binary(), binary()) :: map() | nil | {:error, term()}
  def row(scope, organization_id, id) do
    with {:ok, _admin} <- Access.authorize(scope) do
      case PlatformDirectory.service_identity(organization_id, id) do
        nil -> nil
        found -> hd(present([found], scope))
      end
    end
  end

  @doc """
  An issue or rotate result for the console: `{service_identity, token}`, where `service_identity`
  is the list row (AD3), so the sheet can show the token once and the row it belongs to.
  """
  @spec issued({:ok, map()} | term(), term(), binary()) :: {:ok, map()} | term()
  def issued({:ok, %{service_identity: identity, api_token: token}}, scope, organization_id) do
    case row(scope, organization_id, identity.id) do
      nil -> {:error, :service_identity_not_found}
      {:error, _reason} = error -> error
      row -> {:ok, %{service_identity: row, token: token}}
    end
  end

  def issued(other, _scope, _organization_id), do: other

  defp present(rows, scope) do
    {:ok, creators} =
      PlatformNames.display_names(
        scope,
        rows |> Enum.map(& &1.created_by_id) |> Enum.reject(&is_nil/1)
      )

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
end
