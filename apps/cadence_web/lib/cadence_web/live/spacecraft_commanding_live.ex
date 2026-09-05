defmodule CadenceWeb.SpacecraftCommandingLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    spacecraft = socket.assigns.current_spacecraft

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Command Interpretation")
     |> assign(:nav_item, :spacecraft)
     |> assign(:commanding_page, commanding_page_dto(mission, spacecraft))
     |> assign(:command_panels, command_panels_dto())
     |> assign(:readiness_impact, readiness_impact_dto())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-commanding-component"
        v-component="FederatedFullPageSurface"
        application_key="spacecraft"
        surface_id="commanding"
        host_scope="spacecraft"
        mission_id={@current_mission.mission_id}
        spacecraft_id={@current_spacecraft.spacecraft_id}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp commanding_page_dto(mission, spacecraft) do
    %{
      id: "spacecraft-commanding-page",
      title: "Commanding for #{spacecraft.display_name}",
      subtitle:
        "Spacecraft-owned command interpretation will collect command encoding, TC frame defaults, and uplink behavior once command setup is exposed.",
      eyebrow: "Command Interpretation",
      breadcrumbs: [
        breadcrumb_dto(mission.display_name, ~p"/missions/#{mission.mission_id}"),
        breadcrumb_dto("Spacecraft", ~p"/missions/#{mission.mission_id}/spacecraft"),
        breadcrumb_dto(
          spacecraft.display_name,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
        ),
        breadcrumb_dto("Commanding", nil)
      ],
      status: status_dto("Not tracked")
    }
  end

  defp command_panels_dto do
    [
      command_panel_dto(
        "spacecraft-commanding-encoding",
        "Command Encoding",
        "Command catalog binding and encoding defaults will live with this spacecraft."
      ),
      command_panel_dto(
        "spacecraft-commanding-tc-framing",
        "TC Framing Defaults",
        "SCID, VCID, sequence defaults, and frame settings will be configured here when needed."
      ),
      command_panel_dto(
        "spacecraft-commanding-uplink",
        "Uplink Behavior",
        "COP-1 and uplink-gateway behavior is configured on the spacecraft's type. Surface here when commanding ships."
      )
    ]
  end

  defp command_panel_dto(id, title, description) do
    %{
      id: id,
      title: title,
      value: "Not tracked",
      status: status_dto("Setup"),
      description: description
    }
  end

  defp readiness_impact_dto do
    %{
      eyebrow: "Readiness Impact",
      title: "Command interpretation is not part of readiness yet",
      description:
        "This page keeps the spacecraft-owned command surface visible while command setup matures. Current readiness still focuses on identity, telemetry interpretation, and link assignment.",
      status: status_dto("Placeholder")
    }
  end

  defp breadcrumb_dto(label, href), do: %{label: label, href: href}
  defp status_dto(label), do: %{tone: "info", label: label}
end
