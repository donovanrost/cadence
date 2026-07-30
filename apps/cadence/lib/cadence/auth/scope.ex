defmodule Cadence.Auth.Scope do
  @moduledoc """
  Canonical authenticated scope for API and internal actors.
  """

  alias Cadence.Accounts.OrganizationMembership
  alias Cadence.Accounts.User
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  @type actor_kind :: :service | :user
  @type capability ::
          ServiceIdentity.capability() | User.capability() | OrganizationMembership.capability()

  @type t :: %__MODULE__{
          actor_kind: actor_kind(),
          organization_id: binary() | nil,
          organization: Organization.t() | nil,
          mission_id: binary() | nil,
          mission: Mission.t() | nil,
          user: User.t() | nil,
          organization_membership: OrganizationMembership.t() | nil,
          service_identity: ServiceIdentity.t() | nil,
          role: atom() | nil,
          admin_mode?: boolean(),
          capabilities: MapSet.t(capability())
        }

  defstruct [
    :actor_kind,
    :organization_id,
    :organization,
    :mission_id,
    :mission,
    :user,
    :organization_membership,
    :service_identity,
    :role,
    admin_mode?: false,
    capabilities: MapSet.new()
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    if Map.has_key?(attrs, :user) do
      user_scope(attrs)
    else
      service_scope(attrs)
    end
  end

  defp service_scope(attrs) do
    service_identity = Map.fetch!(attrs, :service_identity)
    mission = Map.get(attrs, :mission)

    %__MODULE__{
      actor_kind: :service,
      organization_id: Map.fetch!(attrs, :organization_id),
      organization: Map.fetch!(attrs, :organization),
      mission_id: (mission && mission.mission_id) || service_identity.mission_id,
      mission: mission,
      service_identity: service_identity,
      admin_mode?: false,
      capabilities:
        service_identity.capabilities
        |> MapSet.new()
    }
  end

  defp user_scope(attrs) do
    user = Map.fetch!(attrs, :user)
    organization_membership = Map.get(attrs, :organization_membership)
    admin_mode? = Map.get(attrs, :admin_mode?, false) and platform_admin_user?(user)

    %__MODULE__{
      actor_kind: :user,
      organization_id:
        Map.get(
          attrs,
          :organization_id,
          organization_membership && organization_membership.organization_id
        ),
      organization: Map.get(attrs, :organization),
      mission_id: nil,
      mission: nil,
      user: user,
      organization_membership: organization_membership,
      service_identity: nil,
      role: Map.get(attrs, :role, default_user_role(user, organization_membership, admin_mode?)),
      admin_mode?: admin_mode?,
      capabilities:
        user
        |> effective_user_capabilities(admin_mode?)
        |> MapSet.new()
        |> MapSet.union(MapSet.new(OrganizationMembership.capabilities(organization_membership)))
    }
  end

  @spec platform_admin_eligible?(t()) :: boolean()
  def platform_admin_eligible?(%__MODULE__{user: %User{} = user}), do: platform_admin_user?(user)
  def platform_admin_eligible?(%__MODULE__{}), do: false

  @spec admin_mode?(t()) :: boolean()
  def admin_mode?(%__MODULE__{admin_mode?: true} = scope), do: platform_admin_eligible?(scope)
  def admin_mode?(%__MODULE__{}), do: false

  defp default_user_role(_user, nil, true), do: :platform_admin
  defp default_user_role(_user, nil, false), do: nil

  defp default_user_role(_user, %OrganizationMembership{} = organization_membership, _admin_mode?) do
    organization_membership.role
  end

  defp effective_user_capabilities(%User{capabilities: capabilities}, true), do: capabilities

  defp effective_user_capabilities(%User{capabilities: capabilities}, false) do
    List.delete(capabilities, :platform_admin)
  end

  defp platform_admin_user?(%User{capabilities: capabilities}),
    do: :platform_admin in capabilities
end
