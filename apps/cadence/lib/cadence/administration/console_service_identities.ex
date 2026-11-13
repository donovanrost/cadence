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
      rows = PlatformDirectory.service_identities(params["organization_id"], @cap)
      creators = rows |> Enum.map(& &1.created_by_id) |> Enum.reject(&is_nil/1) |> names()

      {:ok,
       %{
         service_identities:
           Enum.map(rows, fn row ->
             creator = row.created_by_id

             row
             |> Map.delete(:created_by_id)
             |> Map.merge(%{
               capabilities: Enum.map(row.capabilities, &%{key: &1, label: label(&1)}),
               created_by: creator && %{name: Map.get(creators, creator)},
               last_used_at: nil
             })
           end),
         capabilities: @capabilities
       }}
    end
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
