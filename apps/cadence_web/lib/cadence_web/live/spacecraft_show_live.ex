defmodule CadenceWeb.SpacecraftShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Applications.TelemetryDecom

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id

    config =
      case TelemetryDecom.fetch_config(organization_id, mission_id, spacecraft.spacecraft_id) do
        {:ok, config} -> config
        {:error, :not_configured} -> nil
      end

    active =
      case Cadence.fetch_active_binding_set_activation(mission_id) do
        {:ok, activation} ->
          %{
            binding_set_id: activation.binding_set_id,
            binding_set_version: activation.binding_set_version
          }

        {:error, _} ->
          nil
      end

    {:ok,
     socket
     |> assign(:page_title, spacecraft.display_name)
     |> assign(:nav_item, :spacecraft)
     |> assign(:telemetry_decom_config, config)
     |> assign(:telemetry_decom_status, TelemetryDecom.status(config, active))}
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

      <.telemetry_decom_section
        current_mission={@current_mission}
        current_spacecraft={@current_spacecraft}
        status={@telemetry_decom_status}
        config={@telemetry_decom_config}
      />
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :current_spacecraft, :map, required: true
  attr :status, :atom, required: true
  attr :config, :any, default: nil

  defp telemetry_decom_section(assigns) do
    ~H"""
    <div class="card bg-base-200" id="spacecraft-telemetry-decom-section">
      <div class="card-body p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="hud-label mb-2">Telemetry Decom</p>
            <div class="flex items-center gap-2">
              <.status_dot status={dot_status(@status)} />
              <span class="text-base-content font-semibold">{label(@status)}</span>
            </div>
            <p class="text-sm text-base-content/60 mt-2">{description(@status)}</p>
          </div>
          <.link
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/telemetry_decom"
            }
            class="btn btn-ghost btn-sm"
            id="spacecraft-telemetry-decom-configure-link"
          >
            {configure_label(@status)}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp dot_status(:applied), do: :nominal
  defp dot_status(:configured), do: :info
  defp dot_status(:outdated), do: :warning
  defp dot_status(:disabled), do: :offline
  defp dot_status(:not_configured), do: :offline

  defp label(:applied), do: "Applied"
  defp label(:configured), do: "Configured — not yet applied"
  defp label(:outdated), do: "Out of date"
  defp label(:disabled), do: "Disabled"
  defp label(:not_configured), do: "Not configured"

  defp description(:applied),
    do: "The saved configuration is live on the mission."

  defp description(:configured),
    do: "Configuration is saved. Apply it to go live."

  defp description(:outdated),
    do: "Configuration has changed since it was last applied. Re-apply to publish the latest."

  defp description(:disabled),
    do: "Telemetry Decom is disabled for this spacecraft."

  defp description(:not_configured),
    do: "Configure a catalog revision and data source to decode packets for this spacecraft."

  defp configure_label(:not_configured), do: "Configure"
  defp configure_label(_), do: "Manage"
end
