defmodule CadenceWeb.Console.SessionJSON do
  @moduledoc "Wire shape of the console bootstrap. Contract: docs/apogee/api/session.md."

  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias CadenceWeb.Console.Capabilities

  @socket_path "/socket"

  @spec session(%{scope: Scope.t(), organizations: [map()], csrf_token: binary()}) :: map()
  def session(
        %{scope: %Scope{} = scope, organizations: organizations, csrf_token: csrf_token} = assigns
      ) do
    %{
      user: %{
        id: scope.user.user_id,
        email: scope.user.email,
        display_name: scope.user.display_name
      },
      current_organization_id: scope.organization_id,
      admin_mode: Scope.admin_mode?(scope),
      # L6: the 'ADMIN MODE · 52:10' chip counts down to this.
      admin_mode_expires_at:
        if(Scope.admin_mode?(scope), do: Map.get(assigns, :admin_mode_expires_at)),
      platform_admin_eligible: Scope.platform_admin_eligible?(scope),
      capabilities: capabilities(Capabilities.organization(scope)),
      organizations: Enum.map(organizations, &organization/1),
      csrf_token: csrf_token,
      socket: %{path: @socket_path}
    }
  end

  defp organization(%{
         organization: %Organization{} = organization,
         role: role,
         capabilities: capabilities,
         missions: missions
       }) do
    %{
      id: organization.organization_id,
      slug: organization.slug,
      name: organization.display_name,
      role: role && Atom.to_string(role),
      capabilities: capabilities(capabilities),
      missions: Enum.map(missions, &mission/1)
    }
  end

  defp capabilities(capabilities),
    do: capabilities |> Enum.map(&to_string/1) |> Enum.sort()

  defp mission(%Mission{} = mission) do
    %{id: mission.mission_id, slug: mission.slug, name: mission.display_name}
  end
end
