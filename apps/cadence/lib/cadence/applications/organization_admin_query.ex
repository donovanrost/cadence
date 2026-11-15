defmodule Cadence.Applications.OrganizationAdminQuery do
  @moduledoc "Stable Phoenix-owned query contracts for the post-auth organization admin remote."

  alias Cadence.Applications.{HostContext, SurfaceQueryContribution, SurfaceQueryRequest}
  alias Cadence.Applications.OrganizationAdmin
  alias Cadence.Applications.OrganizationAdminProviders, as: Providers
  alias Cadence.Auth.{Policy, Scope}

  @query_contracts [
    %{
      id: "cadence.organization.notifications_bell",
      version: 1,
      surface_id: "notifications_bell",
      stream?: true
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

  defp surface_data(scope, %HostContext{placement: :user}, "notifications_bell", _params),
    do: {:ok, Providers.Notifications.bell_props(scope)}

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
    with :ok <- authorize_organization_surface(scope, organization_id, surface_id),
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

  defp authorize_organization_surface(scope, organization_id, _surface_id) do
    Policy.authorize(scope, :read_organization, %{organization_id: organization_id})
  end

  defp fetch_surface_scope(surface_id) do
    case Enum.find(@query_contracts, &(&1.surface_id == surface_id)) do
      %{surface_id: ^surface_id} ->
        case OrganizationAdmin.fetch_surface(surface_id) do
          {:ok, %{scope: scope}} -> {:ok, scope}
          _other -> {:error, :unknown_surface}
        end

      nil ->
        {:error, :unknown_surface}
    end
  end

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
