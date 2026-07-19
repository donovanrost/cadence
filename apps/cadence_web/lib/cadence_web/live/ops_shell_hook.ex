defmodule CadenceWeb.OpsShellHook do
  alias Cadence.Reads.MissionHealth, as: MissionHealthReads

  @moduledoc """
  on_mount hook for the ops console live_session: loads the assigns the
  `:ops` layout's status bar and nav rail render, so each ops LiveView does
  not repeat them. The show page overrides `:active_dashboard_id` and keeps
  `:fleet_health` fresh on its tick.
  """

  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    {:cont,
     socket
     |> assign(
       :fleet_health,
       MissionHealthReads.summary(scope.organization_id, mission.mission_id, [])
     )
     |> assign(
       :ops_dashboards,
       Cadence.Dashboards.list_dashboard_summaries(scope.organization_id, mission.mission_id)
     )
     |> assign(:active_dashboard_id, nil)
     |> assign(:ops_nav_item, :dashboards)}
  end
end
