defmodule Cadence.Administration.ServiceIdentityAdministration do
  @moduledoc """
  Service identity writes for the console's People page (O6): create, rotate the key, revoke.
  Organization admins only (`:manage_service_identities`).

  The API token is returned **once**, by create and rotate, and never again: Cadence stores
  only its digest. Rotating invalidates the old token immediately; revoking disables the
  identity, so its token stops authenticating and it leaves the directory.

  Capabilities: `organization_admin` (all missions; no `mission_id`) or `mission_admin` (one
  mission; `mission_id` required).
  """

  alias Cadence.Auth
  alias Cadence.Auth.{Policy, Scope, ServiceIdentity, ServiceIdentityKeys}
  alias Cadence.Missions

  @capabilities %{"organization_admin" => :organization_admin, "mission_admin" => :mission_admin}

  @spec create(Scope.t(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def create(%Scope{} = scope, organization_id, params) do
    with :ok <- authorize(scope, organization_id),
         {:ok, attrs} <- validate(organization_id, params),
         {:ok, %{service_identity: identity, api_token: token}} <-
           Auth.issue_service_identity(
             ServiceIdentity.new(
               Map.merge(attrs, %{
                 organization_id: organization_id,
                 metadata: %{"created_by" => scope_actor(scope)}
               })
             )
           ) do
      {:ok, issued(identity, token)}
    end
  end

  @spec rotate(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def rotate(%Scope{} = scope, organization_id, service_identity_id) do
    with :ok <- authorize(scope, organization_id),
         {:ok, %{service_identity: identity, api_token: token}} <-
           ServiceIdentityKeys.rotate(organization_id, service_identity_id) do
      {:ok, issued(identity, token)}
    end
  end

  @spec revoke(Scope.t(), binary(), binary()) :: :ok | {:error, term()}
  def revoke(%Scope{} = scope, organization_id, service_identity_id) do
    with :ok <- authorize(scope, organization_id),
         {:ok, _identity} <- ServiceIdentityKeys.disable(organization_id, service_identity_id) do
      :ok
    end
  end

  defp issued(identity, token),
    do: %{
      service_identity: %{
        id: identity.service_identity_id,
        name: identity.display_name,
        capabilities: Enum.map(identity.capabilities, &Atom.to_string/1),
        mission_id: identity.mission_id
      },
      # Shown once: Cadence keeps only its digest.
      api_token: token
    }

  defp validate(organization_id, params) do
    name = params |> Map.get("name", "") |> to_string() |> String.trim()
    mission_id = blank_to_nil(params["mission_id"])
    capabilities = List.wrap(params["capabilities"])

    with :ok <- name(name),
         {:ok, capabilities} <- capabilities(capabilities, mission_id),
         :ok <- mission(organization_id, mission_id) do
      {:ok, %{display_name: name, mission_id: mission_id, capabilities: capabilities}}
    end
  end

  defp name(name) when byte_size(name) in 1..120, do: :ok
  defp name(_name), do: {:error, {:invalid, %{name: "is required (1-120 characters)"}}}

  defp capabilities(values, mission_id) do
    parsed = Enum.map(values, &Map.get(@capabilities, &1))

    cond do
      values == [] or Enum.any?(parsed, &is_nil/1) ->
        {:error, {:invalid, %{capabilities: "choose organization_admin or mission_admin"}}}

      :mission_admin in parsed and is_nil(mission_id) ->
        {:error, {:invalid, %{mission_id: "is required for mission_admin"}}}

      :organization_admin in parsed and mission_id != nil ->
        {:error, {:invalid, %{mission_id: "must be empty for organization_admin (all missions)"}}}

      true ->
        {:ok, Enum.uniq(parsed)}
    end
  end

  defp mission(_organization_id, nil), do: :ok

  defp mission(organization_id, mission_id) do
    case Missions.fetch_mission(organization_id, mission_id) do
      {:ok, _mission} -> :ok
      _missing -> {:error, {:invalid, %{mission_id: "isn't a mission of this organization"}}}
    end
  end

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp scope_actor(%Scope{user: %{user_id: id}}), do: %{"kind" => "user", "id" => id}
  defp scope_actor(_scope), do: %{"kind" => "unknown"}

  defp authorize(scope, organization_id),
    do: Policy.authorize(scope, :manage_service_identities, %{organization_id: organization_id})
end
