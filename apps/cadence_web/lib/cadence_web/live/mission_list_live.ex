defmodule CadenceWeb.MissionListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    missions = Cadence.list_missions(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Missions")
     |> assign(:nav_item, :missions)
     |> assign(:missions, missions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-base-content">Missions</h1>
        <.link navigate={~p"/missions/new"} class="btn btn-primary btn-sm gap-1">
          <span class="hero-plus h-4 w-4"></span> New Mission
        </.link>
      </div>

      <%= if @missions == [] do %>
        <.empty_state
          icon="hero-rocket-launch"
          title="No missions yet"
          description="Create your first mission to get started."
          action_label="New Mission"
          action_navigate={~p"/missions/new"}
        />
      <% else %>
        <div class="card bg-base-200 overflow-hidden">
          <table class="table">
            <thead>
              <tr>
                <th class="hud-label">Mission</th>
                <th class="hud-label">Slug</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={mission <- @missions}>
                <td class="font-medium">{mission.display_name}</td>
                <td class="font-mono text-sm text-base-content/70">{mission.slug}</td>
                <td class="text-right">
                  <.action_menu>
                    <:action>
                      <.link navigate={~p"/missions/#{mission.mission_id}"}>View</.link>
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
