defmodule CadenceWeb.SpacecraftCommandingLive do
  @moduledoc false
  use CadenceWeb, :live_view

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
      <.page_header
        title={"Commanding for #{@current_spacecraft.display_name}"}
        subtitle="Spacecraft-owned command interpretation will collect command encoding, TC frame defaults, and uplink behavior once command setup is exposed."
        eyebrow="Command Interpretation"
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name,
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
          {"Commanding", nil}
        ]}
      >
        <:actions>
          <.status_badge status={:info} label="Not tracked" />
        </:actions>
      </.page_header>

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
          description="COP-1 and uplink-gateway behavior is configured on the spacecraft's type. Surface here when commanding ships."
        />
      </section>

      <.card>
        <.section_header
          eyebrow="Readiness Impact"
          title="Command interpretation is not part of readiness yet"
          description="This page keeps the spacecraft-owned command surface visible while command setup matures. Current readiness still focuses on identity, telemetry interpretation, and link assignment."
        >
          <:actions>
            <.status_badge status={:info} label="Placeholder" />
          </:actions>
        </.section_header>
      </.card>
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
    <.card id={@id}>
      <div class="flex items-start justify-between gap-3">
        <div>
          <p class="hud-label mb-2">{@title}</p>
          <h2 class="text-base font-semibold">{@value}</h2>
        </div>
        <.status_badge status={:info} label="Setup" />
      </div>
      <p class="mt-3 text-sm text-base-content/70">{@description}</p>
      <.link
        :if={@action_navigate}
        navigate={@action_navigate}
        class="mt-4 text-sm text-primary hover:underline"
      >
        {@action_label}
      </.link>
    </.card>
    """
  end
end
