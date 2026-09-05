defmodule CadenceWeb.ApplicationContributions.OrganizationAdminQuery do
  @moduledoc "Stable Phoenix-owned query contracts for the post-auth organization admin remote."

  @query_contracts [
    %{
      id: "cadence.organization.home",
      version: 1,
      surface_id: "organization_home",
      stream?: false
    },
    %{
      id: "cadence.organization.provider_accounts.list",
      version: 1,
      surface_id: "provider_accounts",
      stream?: true
    },
    %{
      id: "cadence.organization.provider_accounts.new",
      version: 1,
      surface_id: "provider_account_new",
      stream?: false
    },
    %{
      id: "cadence.organization.provider_account.show",
      version: 1,
      surface_id: "provider_account_show",
      stream?: false
    },
    %{
      id: "cadence.organization.notifications",
      version: 1,
      surface_id: "notifications",
      stream?: true
    },
    %{
      id: "cadence.organization.notifications_bell",
      version: 1,
      surface_id: "notifications_bell",
      stream?: true
    },
    %{id: "cadence.platform_admin.home", version: 1, surface_id: "admin_home", stream?: false},
    %{
      id: "cadence.platform_admin.runtime",
      version: 1,
      surface_id: "admin_runtime",
      stream?: true
    },
    %{
      id: "cadence.platform_admin.organizations",
      version: 1,
      surface_id: "admin_organizations",
      stream?: true
    },
    %{
      id: "cadence.platform_admin.organization.new",
      version: 1,
      surface_id: "admin_organization_new",
      stream?: false
    },
    %{
      id: "cadence.platform_admin.organization.show",
      version: 1,
      surface_id: "admin_organization_show",
      stream?: true
    },
    %{
      id: "cadence.platform_admin.organization.invite",
      version: 1,
      surface_id: "admin_organization_invite",
      stream?: false
    }
  ]

  @doc "Returns the complete bounded query contract set."
  @spec all() :: [map()]
  def all, do: @query_contracts

  @doc "Fetches a query contract by its durable string identity."
  @spec fetch(binary(), pos_integer()) :: {:ok, map()} | {:error, :unknown_query}
  def fetch(query_id, version \\ 1)

  def fetch(query_id, version) when is_binary(query_id) and is_integer(version) do
    case Enum.find(@query_contracts, &(&1.id == query_id and &1.version == version)) do
      nil -> {:error, :unknown_query}
      contract -> {:ok, contract}
    end
  end

  def fetch(_query_id, _version), do: {:error, :unknown_query}

  @doc "Returns the query contract for a contributed surface."
  @spec for_surface(binary()) :: {:ok, map()} | {:error, :unknown_surface_query}
  def for_surface(surface_id) when is_binary(surface_id) do
    case Enum.find(@query_contracts, &(&1.surface_id == surface_id)) do
      nil -> {:error, :unknown_surface_query}
      contract -> {:ok, contract}
    end
  end

  def for_surface(_surface_id), do: {:error, :unknown_surface_query}

  @doc false
  @spec validate() :: :ok | {:error, :duplicate_query_contracts}
  def validate do
    ids = Enum.map(@query_contracts, &{&1.id, &1.version})
    if length(ids) == length(Enum.uniq(ids)), do: :ok, else: {:error, :duplicate_query_contracts}
  end
end
