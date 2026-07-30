defmodule CadenceWeb.API.IdentityJSON do
  @moduledoc "Identity and tenancy response serialization boundary."

  alias Cadence.Accounts.User
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  @spec bootstrap(map()) :: map()
  def bootstrap(%{
        organization: %Organization{} = organization,
        mission: mission,
        service_identity: %ServiceIdentity{} = service_identity,
        api_token: api_token
      }) do
    %{
      organization: organization(organization),
      mission: if(mission, do: mission(mission), else: nil),
      service_identity:
        issued_service_identity(%{
          service_identity: service_identity,
          api_token: api_token
        })
    }
  end

  @spec bootstrap_admin_session(map()) :: map()
  def bootstrap_admin_session(%{
        user: %User{} = user,
        session_token: session_token,
        expires_at: %DateTime{} = expires_at
      }) do
    %{
      user: user(user),
      session_token: session_token,
      expires_at: iso8601(expires_at)
    }
  end

  @spec current_scope(Scope.t()) :: map()
  def current_scope(%Scope{} = current_scope) do
    %{
      actor_kind: Atom.to_string(current_scope.actor_kind),
      organization:
        if(current_scope.organization, do: organization(current_scope.organization), else: nil),
      mission: if(current_scope.mission, do: mission(current_scope.mission), else: nil),
      user: if(current_scope.user, do: user(current_scope.user), else: nil),
      service_identity:
        if(current_scope.service_identity,
          do: service_identity(current_scope.service_identity),
          else: nil
        ),
      capabilities: current_scope.capabilities |> MapSet.to_list() |> Enum.map(&Atom.to_string/1)
    }
  end

  @spec user(User.t()) :: map()
  def user(%User{} = user) do
    %{
      user_id: user.user_id,
      email: user.email,
      display_name: user.display_name,
      capabilities: Enum.map(user.capabilities, &Atom.to_string/1),
      lifecycle_state: Atom.to_string(user.lifecycle_state),
      metadata: user.metadata
    }
  end

  @spec organization(Organization.t()) :: map()
  def organization(%Organization{} = organization) do
    %{
      organization_id: organization.organization_id,
      slug: organization.slug,
      display_name: organization.display_name,
      metadata: organization.metadata
    }
  end

  @spec mission(Mission.t()) :: map()
  def mission(%Mission{} = mission) do
    %{
      mission_id: mission.mission_id,
      organization_id: mission.organization_id,
      slug: mission.slug,
      display_name: mission.display_name,
      metadata: mission.metadata
    }
  end

  @spec service_identity(ServiceIdentity.t()) :: map()
  def service_identity(%ServiceIdentity{} = service_identity) do
    %{
      service_identity_id: service_identity.service_identity_id,
      organization_id: service_identity.organization_id,
      mission_id: service_identity.mission_id,
      display_name: service_identity.display_name,
      capabilities: Enum.map(service_identity.capabilities, &Atom.to_string/1),
      lifecycle_state: Atom.to_string(service_identity.lifecycle_state),
      token_hint: service_identity.token_hint,
      metadata: service_identity.metadata
    }
  end

  @spec issued_service_identity(map()) :: map()
  def issued_service_identity(%{
        service_identity: %ServiceIdentity{} = service_identity,
        api_token: api_token
      }) do
    %{
      service_identity: service_identity(service_identity),
      api_token: api_token
    }
  end

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
