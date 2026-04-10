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
          capabilities: MapSet.t(capability()),
          temporary_setup_access: boolean()
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
    capabilities: MapSet.new(),
    temporary_setup_access: false
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
      mission_id: mission && mission.mission_id,
      mission: mission,
      service_identity: service_identity,
      capabilities:
        service_identity.capabilities
        |> MapSet.new()
    }
  end

  defp user_scope(attrs) do
    user = Map.fetch!(attrs, :user)
    organization_membership = Map.get(attrs, :organization_membership)

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
      role: Map.get(attrs, :role, default_user_role(user, organization_membership)),
      capabilities:
        user.capabilities
        |> MapSet.new()
        |> MapSet.union(MapSet.new(OrganizationMembership.capabilities(organization_membership))),
      temporary_setup_access:
        Map.get(attrs, :temporary_setup_access, User.temporary_setup_access?(user))
    }
  end

  defp default_user_role(%User{capabilities: capabilities}, nil) do
    if :platform_admin in capabilities, do: :platform_admin, else: nil
  end

  defp default_user_role(_user, %OrganizationMembership{} = organization_membership) do
    organization_membership.role
  end

  @spec temporary_setup_access?(t()) :: boolean()
  def temporary_setup_access?(%__MODULE__{temporary_setup_access: temporary_setup_access}),
    do: temporary_setup_access

  def temporary_setup_access?(%__MODULE__{}), do: false
end
