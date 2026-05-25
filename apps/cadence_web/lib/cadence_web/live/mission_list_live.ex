defmodule CadenceWeb.MissionListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Phoenix.LiveView.JS

  import CadenceWeb.CommsComponents, only: [status_badge: 1]

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_rows = load_mission_rows(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Missions")
     |> assign(:nav_item, :missions)
     |> assign(:mission_rows, mission_rows)}
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

      <%= if @mission_rows == [] do %>
        <.empty_state
          icon="hero-rocket-launch"
          title="No missions yet"
          description="Create your first mission to get started."
          action_label="New Mission"
          action_navigate={~p"/missions/new"}
        />
      <% else %>
        <div class="card bg-base-200">
          <table id="mission-list-table" class="table">
            <thead>
              <tr>
                <th class="hud-label">Mission</th>
                <th class="hud-label">Slug</th>
                <th class="hud-label text-right">Spacecraft</th>
                <th class="hud-label">Status</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @mission_rows}
                id={"mission-row-#{row.mission.mission_id}"}
                phx-click={JS.navigate(~p"/missions/#{row.mission.mission_id}")}
                class="cursor-pointer hover:bg-base-300/40"
              >
                <td class="font-medium">{row.mission.display_name}</td>
                <td class="font-mono text-sm text-base-content/70">{row.mission.slug}</td>
                <td class="text-right font-mono text-sm">{row.spacecraft_count}</td>
                <td>
                  <.status_badge status={row.status} label={row.status_label} />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp load_mission_rows(organization_id) do
    organization_id
    |> Cadence.list_missions()
    |> Enum.map(fn mission ->
      spacecraft = Cadence.list_spacecraft(organization_id, mission.mission_id)
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
