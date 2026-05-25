defmodule CadenceWeb.SpacecraftShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents, only: [display_name: 2, status_badge: 1]

  alias Cadence.Applications.TelemetryDecom
  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id

    runtime_identity =
      SpacecraftCommsReadiness.runtime_identity(organization_id, mission_id, spacecraft)

    link_assignment =
      SpacecraftCommsReadiness.link_assignment(organization_id, mission_id, runtime_identity)

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
     |> assign(:telemetry_decom_status, TelemetryDecom.status(config, active))
     |> assign(:runtime_identity, runtime_identity)
     |> assign(:link_assignment, link_assignment)}
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

      <section id="spacecraft-interpretation-overview" class="grid gap-4 xl:grid-cols-4">
        <.workflow_card
          id="spacecraft-overview-identity"
          title="Identity"
          value={identity_summary(@current_spacecraft, @runtime_identity)}
          description="Spacecraft values Cadence uses to recognize incoming bytes."
          status={identity_status(@current_spacecraft, @runtime_identity)}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
          }
          action_label="Edit Identity"
        />
        <.workflow_card
          id="spacecraft-overview-telemetry"
          title="Telemetry Interpretation"
          value={label(@telemetry_decom_status)}
          description={description(@telemetry_decom_status)}
          status={telemetry_panel_status(@telemetry_decom_status)}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/telemetry"
          }
          action_label={configure_label(@telemetry_decom_status)}
        />
        <.workflow_card
          id="spacecraft-overview-links"
          title="Link Assignments"
          value={link_summary(@link_assignment)}
          description={link_description(@link_assignment)}
          status={link_status(@link_assignment)}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/links"
          }
          action_label="Manage Links"
        />
        <.workflow_card
          id="spacecraft-overview-readiness"
          title="Readiness"
          value={overall_readiness_label(@current_spacecraft, @telemetry_decom_status, @link_assignment)}
          description="Review identity, interpretation, and link assignment together."
          status={overall_status(@current_spacecraft, @telemetry_decom_status, @link_assignment)}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/readiness"
          }
          action_label="Review"
        />
      </section>

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
            <.detail_row label="SCID" value={format_scid(@current_spacecraft.scid)} mono />
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

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :description, :string, required: true
  attr :status, :atom, required: true
  attr :navigate, :string, default: nil
  attr :action_label, :string, default: nil

  defp workflow_card(assigns) do
    ~H"""
    <div id={@id} class="card bg-base-200 border border-base-300">
      <div class="card-body p-5">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="hud-label mb-2">{@title}</p>
            <h2 class="text-base font-semibold">{@value}</h2>
          </div>
          <.status_badge status={@status} />
        </div>
        <p class="mt-3 text-sm text-base-content/60">{@description}</p>
        <.link
          :if={@navigate}
          navigate={@navigate}
          class="mt-4 text-sm text-primary hover:underline"
        >
          {@action_label}
        </.link>
      </div>
    </div>
    """
  end

  defp identity_status(%{scid: nil}, _runtime_identity), do: :blocked
  defp identity_status(_spacecraft, nil), do: :attention
  defp identity_status(_spacecraft, _runtime_identity), do: :ready

  defp identity_summary(%{scid: nil}, _runtime_identity), do: "Missing SCID"
  defp identity_summary(_spacecraft, nil), do: "Runtime identity missing"
  defp identity_summary(spacecraft, _runtime_identity), do: "SCID #{spacecraft.scid} configured"

  defp telemetry_panel_status(:applied), do: :ready
  defp telemetry_panel_status(:configured), do: :attention
  defp telemetry_panel_status(:outdated), do: :attention
  defp telemetry_panel_status(:disabled), do: :blocked
  defp telemetry_panel_status(:not_configured), do: :blocked

  defp link_status(%{selected_downlink: nil}), do: :attention
  defp link_status(_link_assignment), do: :ready

  defp link_summary(%{selected_downlink: nil, available_downlink_count: count}) when count > 0 do
    "#{count} available downlink link#{if count == 1, do: "", else: "s"}"
  end

  defp link_summary(%{selected_downlink: nil, assigned_count: 0}), do: "No links assigned"

  defp link_summary(%{selected_downlink: nil, assigned_count: count}) do
    "#{count} candidate link#{if count == 1, do: "", else: "s"}"
  end

  defp link_summary(%{selected_downlink: selected_downlink}),
    do: display_name(selected_downlink, :path_template_id)

  defp link_description(%{selected_downlink: nil, available_downlink_count: count})
       when count > 0,
       do: "Mission-owned downlink links are available to assign."

  defp link_description(_link_assignment),
    do: "Mission-owned links attached to this spacecraft."

  defp overall_status(spacecraft, telemetry_status, link_assignment) do
    if SpacecraftCommsReadiness.identity_ready?(spacecraft) and telemetry_status == :applied and
         not is_nil(link_assignment.selected_downlink) do
      :ready
    else
      :attention
    end
  end

  defp overall_readiness_label(spacecraft, telemetry_status, link_assignment) do
    if overall_status(spacecraft, telemetry_status, link_assignment) == :ready do
      "Ready"
    else
      "Needs review"
    end
  end

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
    do: "Telemetry interpretation is disabled for this spacecraft."

  defp description(:not_configured),
    do: "Configure a catalog revision and data source to decode packets for this spacecraft."

  defp configure_label(:not_configured), do: "Configure"
  defp configure_label(_), do: "Manage"

  defp format_scid(nil), do: "Not set"
  defp format_scid(scid), do: Integer.to_string(scid)
end
