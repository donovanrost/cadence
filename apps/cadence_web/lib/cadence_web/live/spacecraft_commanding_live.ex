defmodule CadenceWeb.SpacecraftCommandingLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents, only: [status_badge: 1]

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Command Interpretation")
     |> assign(:nav_item, :spacecraft)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-commanding-page" class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <.breadcrumbs items={[
            {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
            {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
            {@current_spacecraft.display_name,
             ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
            {"Commanding", nil}
          ]} />
          <p class="hud-label mt-3 mb-2">Command Interpretation</p>
          <h1 class="text-2xl font-bold text-base-content">
            Commanding for {@current_spacecraft.display_name}
          </h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            Spacecraft-owned command interpretation will collect command encoding,
            TC frame defaults, and uplink behavior once command setup is exposed.
          </p>
        </div>
        <.status_badge status={:info} label="Not tracked" />
      </div>

      <section class="grid gap-4 lg:grid-cols-3">
        <.command_panel
          id="spacecraft-commanding-encoding"
          title="Command Encoding"
          value="Not tracked"
          description="Command catalog binding and encoding defaults will live with this spacecraft."
        />
        <.command_panel
          id="spacecraft-commanding-tc-framing"
          title="TC Framing Defaults"
          value="Not tracked"
          description="SCID, VCID, sequence defaults, and frame settings will be configured here when needed."
        />
        <.command_panel
          id="spacecraft-commanding-uplink"
          title="Uplink Behavior"
          value="Not tracked"
          description="COP-1 and uplink gateway behavior can be reviewed from mission protocol behaviors today."
          action_label="View Protocol Behaviors"
          action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/protocol-behaviors"}
        />
      </section>

      <section class="card bg-base-200 border border-base-300">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Readiness Impact</p>
              <h2 class="text-lg font-semibold">Command interpretation is not part of readiness yet</h2>
              <p class="mt-1 text-sm text-base-content/60">
                This page keeps the spacecraft-owned command surface visible while command
                setup matures. Current readiness still focuses on identity, telemetry
                interpretation, and link assignment.
              </p>
            </div>
            <.status_badge status={:info} label="Placeholder" />
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :description, :string, required: true
  attr :action_label, :string, default: nil
  attr :action_navigate, :string, default: nil

  defp command_panel(assigns) do
    ~H"""
    <section id={@id} class="card bg-base-200 border border-base-300">
      <div class="card-body p-5">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="hud-label mb-2">{@title}</p>
            <h2 class="text-base font-semibold">{@value}</h2>
          </div>
          <.status_badge status={:info} label="Setup" />
        </div>
        <p class="mt-3 text-sm text-base-content/60">{@description}</p>
        <.link
          :if={@action_navigate}
          navigate={@action_navigate}
          class="mt-4 text-sm text-primary hover:underline"
        >
          {@action_label}
        </.link>
      </div>
    </section>
    """
  end
end
