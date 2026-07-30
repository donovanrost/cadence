defmodule CadenceWeb.API.IdentityParams do
  @moduledoc "Identity and tenancy request parsing boundary."

  import CadenceWeb.API.ParamParser

  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  @spec bootstrap_admin_session(map()) :: {:ok, {binary(), binary()}} | {:error, term()}
  def bootstrap_admin_session(params) when is_map(params) do
    with {:ok, email} <- required_string(params, "email"),
         {:ok, password} <- required_string(params, "password") do
      {:ok, {email, password}}
    end
  end

  @spec durable_session(map()) :: {:ok, {binary(), binary()}} | {:error, term()}
  def durable_session(params) when is_map(params) do
    with {:ok, email} <- required_string(params, "email"),
         {:ok, password} <- required_string(params, "password") do
      {:ok, {email, password}}
    end
  end

  @spec organization_invitation_acceptance(map()) ::
          {:ok, %{display_name: binary(), password: binary()}} | {:error, term()}
  def organization_invitation_acceptance(params) when is_map(params) do
    with {:ok, display_name} <- required_string(params, "display_name"),
         {:ok, password} <- required_string(params, "password"),
         {:ok, password_confirmation} <- required_string(params, "password_confirmation"),
         :ok <- validate_password_confirmation(password, password_confirmation) do
      {:ok, %{display_name: display_name, password: password}}
    end
  end

  @spec organization(map()) :: {:ok, Organization.t()} | {:error, term()}
  def organization(params) when is_map(params) do
    with {:ok, slug} <- required_string(params, "slug"),
         {:ok, display_name} <- required_string(params, "display_name") do
      {:ok,
       Organization.new(%{
         organization_id: string_value(params, "organization_id"),
         slug: slug,
         display_name: display_name,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec mission(binary(), map()) :: {:ok, Mission.t()} | {:error, term()}
  def mission(organization_id, params) when is_binary(organization_id) and is_map(params) do
    with {:ok, slug} <- required_string(params, "slug"),
         {:ok, display_name} <- required_string(params, "display_name") do
      {:ok,
       Mission.new(%{
         mission_id: string_value(params, "mission_id"),
         organization_id: organization_id,
         slug: slug,
         display_name: display_name,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec service_identity(binary(), map()) :: {:ok, ServiceIdentity.t()} | {:error, term()}
  def service_identity(organization_id, params)
      when is_binary(organization_id) and is_map(params) do
    with {:ok, display_name} <- required_string(params, "display_name"),
         {:ok, capabilities} <- capabilities(params, []),
         {:ok, lifecycle_state} <- service_identity_lifecycle_state(params) do
      {:ok,
       ServiceIdentity.new(%{
         service_identity_id: string_value(params, "service_identity_id"),
         organization_id: organization_id,
         mission_id: string_value(params, "mission_id"),
         display_name: display_name,
         capabilities: capabilities,
         lifecycle_state: lifecycle_state,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec bootstrap_service_identity(binary(), map()) ::
          {:ok, ServiceIdentity.t()} | {:error, term()}
  def bootstrap_service_identity(organization_id, bootstrap_params)
      when is_binary(organization_id) and is_map(bootstrap_params) do
    service_identity_params = Map.get(bootstrap_params, "service_identity", %{})

    with {:ok, display_name} <- required_string(service_identity_params, "display_name"),
         {:ok, capabilities} <- capabilities(service_identity_params, [:organization_admin]),
         {:ok, lifecycle_state} <- service_identity_lifecycle_state(service_identity_params) do
      {:ok,
       ServiceIdentity.new(%{
         service_identity_id: string_value(service_identity_params, "service_identity_id"),
         organization_id: organization_id,
         display_name: display_name,
         capabilities: capabilities,
         lifecycle_state: lifecycle_state,
         metadata: map_value(service_identity_params, "metadata")
       })}
    end
  end

  @spec bootstrap_mission(binary(), map()) :: {:ok, Mission.t() | nil} | {:error, term()}
  def bootstrap_mission(organization_id, bootstrap_params)
      when is_binary(organization_id) and is_map(bootstrap_params) do
    case Map.get(bootstrap_params, "mission") do
      nil -> {:ok, nil}
      mission_params when is_map(mission_params) -> mission(organization_id, mission_params)
      _other -> {:error, {:invalid_param, "mission", :map}}
    end
  end
end
