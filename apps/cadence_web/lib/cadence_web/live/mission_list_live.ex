defmodule CadenceWeb.MissionListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.MissionListLive.Presentation

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_rows = load_mission_rows(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Missions")
     |> assign(:nav_item, :missions)
     |> assign(:mission_list_presentation, Presentation.build(mission_rows))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="mission-list-component"
        v-component="FederatedFullPageSurface"
        application_key="mission_catalog"
        surface_id="mission_list"
        host_scope="organization"
        organization_id={@current_scope.organization.organization_id}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp load_mission_rows(organization_id) do
    organization_id
    |> Cadence.Missions.list_missions()
    |> Enum.map(fn mission ->
      spacecraft = Cadence.SpacecraftStore.list_spacecraft(organization_id, mission.mission_id)
      Map.put(mission_status(spacecraft), :mission, mission)
    end)
  end

  defp mission_status(spacecraft) do
    cond do
      spacecraft == [] ->
        %{spacecraft_count: 0, status: :info, status_label: "No spacecraft"}

      Enum.all?(spacecraft, & &1.scid) ->
        %{spacecraft_count: length(spacecraft), status: :ready, status_label: "Ready"}

      true ->
        %{spacecraft_count: length(spacecraft), status: :attention, status_label: "Needs setup"}
    end
  end
end
