defmodule CadenceWeb.ApplicationContributions.OrganizationAdminQuery do
  @moduledoc "Stable Phoenix-owned query contracts for the post-auth organization admin remote."

  alias Cadence.Applications.{HostContext, SurfaceQueryContribution, SurfaceQueryRequest}
  alias Cadence.Auth.{Policy, Scope}
  alias CadenceWeb.ApplicationContributions.OrganizationAdminProviders, as: Providers

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

  @doc false
  @spec application_key() :: binary()
  def application_key, do: "organization_admin"

  @doc "Returns one bounded provider contribution for each declared query."
  @spec contributions() :: [SurfaceQueryContribution.t()]
  def contributions do
    Enum.map(@query_contracts, fn contract ->
      %SurfaceQueryContribution{
        application_key: application_key(),
        application_version: 1,
        query_id: contract.id,
        query_version: contract.version,
        provider: __MODULE__
      }
    end)
  end

  @doc "Loads the Phoenix-owned props for one authenticated organization surface."
  @spec load(Scope.t(), HostContext.t(), SurfaceQueryRequest.t()) ::
          {:ok, map()} | {:error, term()}
  def load(
        %Scope{} = scope,
        %HostContext{} = host_context,
        %SurfaceQueryRequest{} = request
      ) do
    with :ok <- validate_request(request),
         :ok <- validate_context(scope, host_context, request.surface_id),
         {:ok, data} <- surface_data(scope, host_context, request.surface_id, request.params) do
      {:ok, %{"navigation" => %{}, "data" => data}}
    end
  end

  defp surface_data(scope, %HostContext{placement: :organization}, "organization_home", _params) do
    with {:ok, organization} <- Cadence.Organizations.fetch_organization(scope.organization_id) do
      {:ok, %{presentation: Providers.OrganizationHome.presentation(organization)}}
    end
  end

  defp surface_data(scope, %HostContext{placement: :organization}, "provider_accounts", _params),
    do: Providers.ProviderAccountList.props(scope)

  defp surface_data(
         _scope,
         %HostContext{placement: :organization},
         "provider_account_new",
         _params
       ),
       do: {:ok, Providers.ProviderAccountNew.props()}

  defp surface_data(
         scope,
         %HostContext{placement: :organization},
         "provider_account_show",
         params
       ) do
    with {:ok, provider_account_id} <- required_param(params, "provider_account_id") do
      Providers.ProviderAccountShow.props(scope, provider_account_id)
    end
  end

  defp surface_data(scope, %HostContext{placement: :user}, "notifications", _params),
    do: {:ok, %{presentation: Providers.Notifications.presentation(scope)}}

  defp surface_data(
         %Scope{user: %{user_id: user_id}},
         %HostContext{placement: :user},
         "notifications_bell",
         _params
       ) do
    notifications = Cadence.Notifications.list_notifications(user_id, limit: 5)

    {:ok,
     %{
       presentation:
         CadenceWeb.UI.notifications_bell_presentation(%{
           id: "notifications-bell-application",
           count: Cadence.Notifications.count_unread_notifications(user_id),
           notifications: notifications
         })
     }}
  end

  defp surface_data(_scope, %HostContext{placement: :admin}, "admin_home", _params),
    do: {:ok, Providers.AdminHome.props()}

  defp surface_data(_scope, %HostContext{placement: :admin}, "admin_runtime", params),
    do: {:ok, Providers.AdminRuntime.props(params)}

  defp surface_data(_scope, %HostContext{placement: :admin}, "admin_organizations", _params),
    do: {:ok, Providers.AdminOrganizationList.props()}

  defp surface_data(_scope, %HostContext{placement: :admin}, "admin_organization_new", _params),
    do: {:ok, Providers.AdminOrganizationNew.props()}

  defp surface_data(_scope, %HostContext{placement: :admin}, "admin_organization_show", params) do
    with {:ok, organization_id} <- required_param(params, "organization_id") do
      case Providers.AdminOrganizationShow.props(organization_id) do
        {:ok, props} -> {:ok, props}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp surface_data(_scope, %HostContext{placement: :admin}, "admin_organization_invite", params) do
    with {:ok, organization_id} <- required_param(params, "organization_id") do
      case Providers.AdminOrganizationInvite.props(organization_id) do
        {:ok, props} -> {:ok, props}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp surface_data(_scope, _host_context, _surface_id, _params),
    do: {:error, :unsupported_application_host_context}

  defp validate_request(%SurfaceQueryRequest{
         application_key: application_key,
         application_version: 1,
         surface_id: surface_id,
         query_id: query_id,
         query_version: query_version,
         params: params
       })
       when application_key == "organization_admin" and is_map(params) do
    case fetch(query_id, query_version) do
      {:ok, %{id: ^query_id, version: ^query_version, surface_id: ^surface_id}} -> :ok
      _unknown -> {:error, :unknown_application_surface_query}
    end
  end

  defp validate_request(_request), do: {:error, :invalid_application_surface_query_contract}

  defp validate_context(
         %Scope{organization_id: organization_id} = scope,
         %HostContext{placement: :organization, organization_id: organization_id},
         surface_id
       )
       when is_binary(organization_id) do
    with :ok <- Policy.authorize(scope, :read_organization, %{organization_id: organization_id}),
         {:ok, surface} <- fetch_surface_scope(surface_id) do
      if surface == :organization, do: :ok, else: {:error, :unsupported_application_host_context}
    end
  end

  defp validate_context(
         %Scope{actor_kind: :user, user: %{user_id: user_id}} = _scope,
         %HostContext{placement: :user, user_id: user_id},
         surface_id
       ) do
    case fetch_surface_scope(surface_id) do
      {:ok, :user} -> :ok
      _other -> {:error, :unsupported_application_host_context}
    end
  end

  defp validate_context(%Scope{} = scope, %HostContext{placement: :admin}, surface_id) do
    with true <- Scope.admin_mode?(scope),
         {:ok, :admin} <- fetch_surface_scope(surface_id) do
      :ok
    else
      false -> {:error, :forbidden}
      _other -> {:error, :unsupported_application_host_context}
    end
  end

  defp validate_context(_scope, _host_context, _surface_id),
    do: {:error, :scope_mismatch}

  defp fetch_surface_scope(surface_id) do
    case Enum.find(@query_contracts, &(&1.surface_id == surface_id)) do
      %{surface_id: ^surface_id} ->
        case CadenceWeb.ApplicationContributions.OrganizationAdmin.fetch_surface(surface_id) do
          {:ok, %{scope: scope}} -> {:ok, scope}
          _other -> {:error, :unknown_surface}
        end

      nil ->
        {:error, :unknown_surface}
    end
  end

  defp required_param(params, key) when is_map(params) do
    case Map.get(params, key) || Map.get(params, query_param_key(key)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :application_surface_subject_required}
    end
  end

  defp required_param(_params, _key), do: {:error, :application_surface_subject_required}

  defp query_param_key("provider_account_id"), do: :provider_account_id
  defp query_param_key("organization_id"), do: :organization_id
  defp query_param_key(_key), do: nil

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
