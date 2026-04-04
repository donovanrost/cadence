defmodule Cadence.Auth.Scope do
  @moduledoc """
  Canonical authenticated scope for API and internal actors.
  """

  alias Cadence.Accounts.User
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  @type actor_kind :: :service | :user

  @type t :: %__MODULE__{
          actor_kind: actor_kind(),
          organization_id: binary() | nil,
          organization: Organization.t() | nil,
          mission_id: binary() | nil,
          mission: Mission.t() | nil,
          user: User.t() | nil,
          organization_membership: nil,
          service_identity: ServiceIdentity.t() | nil,
          role: atom() | nil,
          capabilities: MapSet.t(ServiceIdentity.capability() | User.capability())
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

    %__MODULE__{
      actor_kind: :user,
      organization_id: Map.get(attrs, :organization_id),
      organization: Map.get(attrs, :organization),
      mission_id: nil,
      mission: nil,
      user: user,
      service_identity: nil,
      role: Map.get(attrs, :role),
      capabilities:
        user.capabilities
        |> MapSet.new()
    }
  end

  @spec temporary_setup_access?(t()) :: boolean()
  def temporary_setup_access?(%__MODULE__{user: %User{} = user}) do
    User.temporary_setup_access?(user)
  end

  def temporary_setup_access?(%__MODULE__{}), do: false
end
