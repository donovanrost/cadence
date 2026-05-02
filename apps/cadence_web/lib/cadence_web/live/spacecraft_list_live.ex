defmodule CadenceWeb.SpacecraftListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    spacecraft = Cadence.list_spacecraft(organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:spacecraft, spacecraft)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}"}
          class="text-sm text-primary hover:underline"
        >
          &larr; {@current_mission.display_name}
        </.link>
      </div>

      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-base-content">Spacecraft</h1>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
          class="btn btn-primary btn-sm gap-1"
        >
          <span class="hero-plus h-4 w-4"></span> New Spacecraft
        </.link>
      </div>

      <%= if @spacecraft == [] do %>
        <.empty_state
          icon="hero-rocket-launch"
          title="No spacecraft yet"
          description="Register the first spacecraft for this mission."
          action_label="New Spacecraft"
          action_navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
        />
      <% else %>
        <div class="card bg-base-200">
          <table class="table">
            <thead>
              <tr>
                <th class="hud-label">Name</th>
                <th class="hud-label">Spacecraft ID</th>
                <th class="hud-label">SCID</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={spacecraft <- @spacecraft}>
                <td class="font-medium">{spacecraft.display_name}</td>
                <td class="font-mono text-sm text-base-content/70">{spacecraft.spacecraft_id}</td>
                <td class="font-mono text-sm text-base-content/70">
                  {spacecraft.scid || "Not set"}
                </td>
                <td class="text-right">
                  <.action_menu>
                    <:action>
                      <.link navigate={
                        ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
                      }>
                        View
                      </.link>
                    </:action>
                    <:action>
                      <.link navigate={
                        ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
                      }>
                        Identity
                      </.link>
                    </:action>
                  </.action_menu>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
