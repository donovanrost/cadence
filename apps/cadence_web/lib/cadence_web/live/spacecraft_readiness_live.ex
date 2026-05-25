defmodule CadenceWeb.SpacecraftReadinessLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents, only: [display_name: 2, status_badge: 1]

  alias Cadence.Applications.TelemetryDecom
  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    telemetry_status = telemetry_status(scope.organization_id, mission.mission_id, spacecraft)

    runtime_identity =
      SpacecraftCommsReadiness.runtime_identity(
        scope.organization_id,
        mission.mission_id,
        spacecraft
      )

    link_assignment =
      SpacecraftCommsReadiness.link_assignment(
        scope.organization_id,
        mission.mission_id,
        runtime_identity
      )

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Readiness")
     |> assign(:nav_item, :spacecraft)
     |> assign(:telemetry_status, telemetry_status)
     |> assign(:runtime_identity, runtime_identity)
     |> assign(:link_assignment, link_assignment)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-readiness-page" class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <.link
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"
            }
            class="text-sm text-primary hover:underline"
          >
            &larr; {@current_spacecraft.display_name}
          </.link>
          <p class="hud-label mt-4 mb-2">Spacecraft Readiness</p>
          <h1 class="text-2xl font-bold text-base-content">
            Identity, interpretation, and link assignment
          </h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            Mission Comms owns shared network paths. This page shows whether this spacecraft
            can be identified, interpreted, and assigned to those mission-owned links.
          </p>
        </div>
        <.status_badge status={overall_status(@current_spacecraft, @telemetry_status, @link_assignment)} />
      </div>

      <div class="grid gap-4 xl:grid-cols-2">
        <.readiness_panel
          id="spacecraft-readiness-identity"
          title="Identity"
          status={identity_status(@current_spacecraft, @runtime_identity)}
          status_label={identity_status_label(@current_spacecraft, @runtime_identity)}
          description={identity_description(@current_spacecraft, @runtime_identity)}
          action_label="Edit Identity"
          action_navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
          }
        >
          <:detail label="SCID" value={format_scid(@current_spacecraft.scid)} />
          <:detail label="Runtime Identity" value={runtime_identity_label(@runtime_identity)} />
        </.readiness_panel>

        <.readiness_panel
          id="spacecraft-readiness-telemetry"
          title="Telemetry Interpretation"
          status={telemetry_panel_status(@telemetry_status)}
          status_label={telemetry_status_label(@telemetry_status)}
          description={telemetry_description(@telemetry_status)}
          action_label={telemetry_action_label(@telemetry_status)}
          action_navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/telemetry"
          }
        >
          <:detail label="Configuration" value={telemetry_status_label(@telemetry_status)} />
        </.readiness_panel>

        <.readiness_panel
          id="spacecraft-readiness-links"
          title="Link Assignments"
          status={link_panel_status(@link_assignment)}
          status_label={link_status_label(@link_assignment)}
          description={link_description(@link_assignment)}
          action_label={link_action_label(@link_assignment)}
          action_navigate={link_action_navigate(@current_mission.mission_id, @current_spacecraft)}
        >
          <:detail label="Downlink" value={link_detail(@link_assignment)} />
          <:detail label="Runtime Identity" value={runtime_identity_label(@runtime_identity)} />
        </.readiness_panel>

        <.readiness_panel
          id="spacecraft-readiness-command"
          title="Command Interpretation"
          status={:info}
          status_label="Not tracked"
          description="Command interpretation will live with the spacecraft once command setup is exposed."
          action_label="Review Commanding"
          action_navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/commanding"
          }
        >
          <:detail label="TC framing" value="Not tracked" />
          <:detail label="Command routing" value="Not tracked" />
        </.readiness_panel>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :status, :atom, required: true
  attr :status_label, :string, required: true
  attr :description, :string, required: true
  attr :action_label, :string, default: nil
  attr :action_navigate, :string, default: nil

  slot :detail do
    attr :label, :string, required: true
    attr :value, :string, required: true
  end

  defp readiness_panel(assigns) do
    ~H"""
    <section id={@id} class="card bg-base-200 border border-base-300">
      <div class="card-body p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="hud-label mb-2">{@title}</p>
            <h2 class="text-lg font-semibold">{@status_label}</h2>
            <p class="mt-1 text-sm text-base-content/60">{@description}</p>
          </div>
          <.status_badge status={@status} label={@status_label} />
        </div>

        <div class="mt-5 divide-y divide-base-300">
          <div :for={detail <- @detail} class="grid gap-2 py-3 sm:grid-cols-[10rem_1fr]">
            <div class="hud-label text-base-content/50">{detail.label}</div>
            <div class="text-sm text-base-content">{detail.value}</div>
          </div>
        </div>

        <.link
          :if={@action_navigate}
          navigate={@action_navigate}
          class="btn btn-primary btn-sm mt-5"
        >
          {@action_label}
        </.link>
      </div>
    </section>
    """
  end

  defp telemetry_status(organization_id, mission_id, spacecraft) do
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

        {:error, _reason} ->
          nil
      end

    TelemetryDecom.status(config, active)
  end

  defp overall_status(spacecraft, telemetry_status, link_assignment) do
    if SpacecraftCommsReadiness.identity_ready?(spacecraft) and telemetry_status == :applied and
         not is_nil(link_assignment.selected_downlink) do
      :ready
    else
      :attention
    end
  end

  defp identity_status(%{scid: nil}, _runtime_identity), do: :blocked
  defp identity_status(_spacecraft, nil), do: :attention
  defp identity_status(_spacecraft, _runtime_identity), do: :ready

  defp identity_status_label(%{scid: nil}, _runtime_identity), do: "Missing SCID"
  defp identity_status_label(_spacecraft, nil), do: "Runtime identity missing"
  defp identity_status_label(_spacecraft, _runtime_identity), do: "Ready"

  defp identity_description(%{scid: nil}, _runtime_identity),
    do: "Set SCID so Cadence can identify this spacecraft from TM transfer frames."

  defp identity_description(_spacecraft, nil),
    do: "Create or sync the runtime identity for this spacecraft."

  defp identity_description(_spacecraft, _runtime_identity),
    do: "Cadence can resolve incoming bytes to this spacecraft identity."

  defp telemetry_panel_status(:applied), do: :ready
  defp telemetry_panel_status(:configured), do: :attention
  defp telemetry_panel_status(:outdated), do: :attention
  defp telemetry_panel_status(:disabled), do: :blocked
  defp telemetry_panel_status(:not_configured), do: :blocked

  defp telemetry_status_label(:applied), do: "Applied"
  defp telemetry_status_label(:configured), do: "Configured"
  defp telemetry_status_label(:outdated), do: "Out of date"
  defp telemetry_status_label(:disabled), do: "Disabled"
  defp telemetry_status_label(:not_configured), do: "Not configured"

  defp telemetry_description(:applied),
    do: "Telemetry interpretation is live for this spacecraft."

  defp telemetry_description(:configured),
    do: "Telemetry interpretation is saved but not applied to the mission runtime."

  defp telemetry_description(:outdated),
    do: "Telemetry interpretation has changed since it was last applied."

  defp telemetry_description(:disabled),
    do: "Telemetry interpretation is disabled for this spacecraft."

  defp telemetry_description(:not_configured),
    do: "Configure catalog binding and APID ownership before downlink data can be interpreted."

  defp telemetry_action_label(:not_configured), do: "Configure Telemetry"
  defp telemetry_action_label(_status), do: "Manage Telemetry"

  defp link_panel_status(%{selected_downlink: nil}), do: :attention
  defp link_panel_status(_assignment), do: :ready

  defp link_status_label(%{selected_downlink: nil, available_downlink_count: count})
       when count > 0,
       do: "Needs assignment"

  defp link_status_label(%{selected_downlink: nil}), do: "Needs downlink"

  defp link_status_label(_assignment), do: "Ready"

  defp link_description(%{selected_downlink: nil, available_downlink_count: count})
       when count > 0,
       do: "Assign an available provider-backed downlink link template from Mission Network."

  defp link_description(%{selected_downlink: nil}),
    do: "Assign a provider-backed downlink link template from Mission Network."

  defp link_description(_assignment),
    do: "This spacecraft has a selected provider-backed downlink link template."

  defp link_detail(%{selected_downlink: nil, available_downlink_count: count}) when count > 0 do
    "#{count} available downlink link template#{if count == 1, do: "", else: "s"}"
  end

  defp link_detail(%{selected_downlink: nil, assigned_count: 0}), do: "No assigned links"

  defp link_detail(%{selected_downlink: nil, assigned_count: count}) do
    "#{count} assigned link template#{if count == 1, do: "", else: "s"}"
  end

  defp link_detail(%{selected_downlink: template}) do
    display_name(template, :path_template_id)
  end

  defp link_action_label(%{selected_downlink: nil}), do: "Assign Link"
  defp link_action_label(_assignment), do: "View Links"

  defp link_action_navigate(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"
  end

  defp runtime_identity_label(nil), do: "Not created"
  defp runtime_identity_label(runtime_identity), do: runtime_identity.source_endpoint_id

  defp format_scid(nil), do: "Not set"
  defp format_scid(scid), do: Integer.to_string(scid)
end
