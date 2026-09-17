defmodule CadenceWeb.HostPageAuthorization do
  @moduledoc "Server authorization and operational subscriptions for host context requests."

  import Phoenix.Component

  alias CadenceWeb.{AdminAuth, DashboardAuthorAuth, MissionAuth, OrganizationAuth}
  alias CadenceWeb.{OpsShellHook, SpacecraftAuth, UserAuth}
  alias CadenceWeb.OpsShellHook.CommandUpdates

  @organization {OrganizationAuth, :require_organization_scope}
  @mission {MissionAuth, :load_mission}
  @admin {OrganizationAuth, :require_organization_admin}
  @policies %{
    organization: {@organization, [], false},
    provider_accounts: {@organization, [@admin], false},
    mission: {@organization, [@mission], false},
    spacecraft: {@organization, [@mission], false},
    spacecraft_show: {@organization, [@mission, {SpacecraftAuth, :load_spacecraft}], false},
    catalog: {@organization, [@mission], false},
    comms: {@organization, [@mission], false},
    ops: {@organization, [@mission], true},
    ops_dashboard_author:
      {@organization, [@mission, {DashboardAuthorAuth, :require_dashboard_author}], true},
    ops_admin: {@organization, [@admin, @mission], true},
    user: {{UserAuth, :require_user_scope}, [], false},
    admin: {{AdminAuth, :require_platform_admin}, [], false}
  }

  def prepare(socket, policy, params) do
    {base, guards, operational?} = Map.fetch!(@policies, policy)
    session = socket.private.host_navigation_session
    previous_mission = socket.assigns[:current_mission]
    previous_operational? = socket.assigns[:ops_context_active?]

    socket =
      assign(socket,
        current_mission: nil,
        current_spacecraft: nil,
        ops_context_active?: operational?
      )

    hooks =
      [base | guards] ++ [{UserAuth, :attach_notifications_bell}, {UserAuth, :attach_user_menu}]

    Enum.reduce_while(hooks, {:cont, socket}, fn {module, action}, {:cont, socket} ->
      case module.on_mount(action, params, session, socket) do
        {:cont, socket} -> {:cont, {:cont, socket}}
        {:halt, socket} -> {:halt, {:halt, socket}}
      end
    end)
    |> prepare_operations(params, previous_mission, previous_operational?)
  end

  defp prepare_operations({:halt, socket}, _params, _mission, _shell),
    do: {:halt, socket |> CommandUpdates.stop() |> assign(:ops_context_active?, false)}

  defp prepare_operations(
         {:cont, %{assigns: %{ops_context_active?: true}} = socket},
         params,
         mission,
         was_operational?
       ) do
    if was_operational? && mission == socket.assigns.current_mission do
      {:cont, OpsShellHook.refresh_dashboard_navigation(socket)}
    else
      socket = assign(socket, :ops_context, nil)
      OpsShellHook.on_mount(:default, params, %{}, socket)
    end
  end

  defp prepare_operations({:cont, socket}, _params, _mission, _shell) do
    socket = CommandUpdates.stop(socket)

    {:cont,
     assign(socket,
       ops_context: nil,
       fleet_health: nil,
       ops_dashboard_navigation: %{starred: [], recent: []},
       ops_dock_surfaces: [],
       active_dashboard_id: nil,
       dashboard_author?: false
     )}
  end
end
