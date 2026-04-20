defmodule CadenceWeb.SpacecraftShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft

    {:ok,
     socket
     |> assign(:page_title, spacecraft.display_name)
     |> assign(:nav_item, :spacecraft)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Spacecraft
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">
          {@current_spacecraft.display_name}
        </h1>
      </div>

      <div class="card bg-base-200">
        <div class="card-body p-6">
          <p class="hud-label mb-4">Overview</p>
          <div class="divide-y divide-base-300">
            <.detail_row
              label="Spacecraft ID"
              value={@current_spacecraft.spacecraft_id}
              mono
            />
            <.detail_row label="Display name" value={@current_spacecraft.display_name} />
            <.detail_row label="Mission">
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}"}
                class="text-primary hover:underline"
              >
                {@current_mission.display_name}
              </.link>
            </.detail_row>
            <.detail_row
              label="Organization ID"
              value={@current_spacecraft.organization_id}
              mono
            />
          </div>

          <div :if={map_size(@current_spacecraft.metadata) > 0} class="mt-6">
            <details class="text-sm">
              <summary class="cursor-pointer text-base-content/60 hover:text-base-content">
                Metadata
              </summary>
              <pre class="mt-2 p-3 bg-base-300 rounded-sm overflow-x-auto text-xs font-mono">{Jason.encode!(@current_spacecraft.metadata, pretty: true)}</pre>
            </details>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
