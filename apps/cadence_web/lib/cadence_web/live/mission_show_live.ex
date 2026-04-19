defmodule CadenceWeb.MissionShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission

    {:ok,
     socket
     |> assign(:page_title, mission.display_name)
     |> assign(:nav_item, :mission_overview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-base-content">{@current_mission.display_name}</h1>
        <p class="mt-1 text-sm text-base-content/50 font-mono">{@current_mission.slug}</p>
      </div>

      <div class="card bg-base-200">
        <div class="card-body p-6">
          <p class="hud-label mb-4">Overview</p>
          <div class="divide-y divide-base-300">
            <.detail_row label="Mission ID" value={@current_mission.mission_id} mono />
            <.detail_row label="Display name" value={@current_mission.display_name} />
            <.detail_row label="Slug" value={@current_mission.slug} mono />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
