defmodule CadenceWeb.SpacecraftShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.SpacecraftShowComponents, only: [type_binding_card: 1, applications_card: 1]

  alias Cadence.Applications.TelemetryDecom
  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id

    runtime_identity =
      SpacecraftCommsReadiness.runtime_identity(organization_id, mission_id, spacecraft)

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

    type_binding = load_type_binding(organization_id, mission_id, spacecraft)

    {:ok,
     socket
     |> assign(:page_title, spacecraft.display_name)
     |> assign(:nav_item, :spacecraft)
     |> assign(:telemetry_decom_config, config)
     |> assign(:telemetry_decom_status, TelemetryDecom.status(config, active))
     |> assign(:runtime_identity, runtime_identity)
     |> assign(:type_binding, type_binding)}
  end

  defp load_type_binding(_organization_id, _mission_id, %{spacecraft_type_id: nil}), do: nil

  defp load_type_binding(organization_id, mission_id, spacecraft) do
    pinned =
      Cadence.fetch_spacecraft_type_version(
        organization_id,
        mission_id,
        spacecraft.spacecraft_type_id,
        spacecraft.spacecraft_type_version
      )

    latest =
      Cadence.fetch_spacecraft_type(
        organization_id,
        mission_id,
        spacecraft.spacecraft_type_id
      )

    case {pinned, latest} do
      {{:ok, pinned_type}, {:ok, latest_type}} ->
        %{
          pinned: pinned_type,
          latest_version: latest_type.version,
          drift?: latest_type.version > pinned_type.version
        }

      {{:ok, pinned_type}, _} ->
        %{pinned: pinned_type, latest_version: pinned_type.version, drift?: false}

      _ ->
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="border-b border-primary/20 pb-4">
        <.breadcrumbs items={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name, nil}
        ]} />
        <div class="mt-2 flex items-baseline gap-3">
          <h1 class="text-2xl font-bold text-base-content tracking-tight">
            {@current_spacecraft.display_name}
          </h1>
          <span :if={@current_spacecraft.scid} class="mc-value-small text-primary/80">
            SCID {@current_spacecraft.scid}
          </span>
          <span
            :if={is_nil(@current_spacecraft.scid)}
            class="hud-label text-warning/70"
          >
            SCID not set
          </span>
        </div>
      </div>

      <.type_binding_card
        mission_id={@current_mission.mission_id}
        spacecraft_id={@current_spacecraft.spacecraft_id}
        type_binding={@type_binding}
      />

      <.applications_card
        type_binding={@type_binding}
        telemetry_decom_status={@telemetry_decom_status}
        mission_id={@current_mission.mission_id}
        spacecraft_id={@current_spacecraft.spacecraft_id}
      />

      <section id="spacecraft-interpretation-overview" class="grid gap-4 xl:grid-cols-3">
        <.workflow_card
          id="spacecraft-overview-identity"
          title="Identity"
          value={identity_summary(@current_spacecraft, @runtime_identity)}
          description="Values Cadence uses to recognize incoming bytes."
          status={identity_status(@current_spacecraft, @runtime_identity)}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
          }
          action_label="Edit Identity"
        />
        <.workflow_card
          id="spacecraft-overview-telemetry"
          title="Applications"
          value={label(@telemetry_decom_status)}
          description={description(@telemetry_decom_status)}
          status={telemetry_panel_status(@telemetry_decom_status)}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/applications"
          }
          action_label={configure_label(@telemetry_decom_status)}
        />
        <.workflow_card
          id="spacecraft-overview-readiness"
          title="Readiness"
          value={overall_readiness_label(@current_spacecraft, @telemetry_decom_status)}
          description="Identity and interpretation status at a glance."
          status={overall_status(@current_spacecraft, @telemetry_decom_status)}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/readiness"
          }
          action_label="Review"
        />
      </section>

      <section class="card bg-base-200 border border-base-300">
        <div class="card-body p-6 space-y-3">
          <p class="hud-label">Overview</p>
          <div class="grid gap-x-8 gap-y-1 md:grid-cols-2">
            <div class="hud-data-row">
              <span class="hud-data-label">SCID</span>
              <span class="hud-data-value">{format_scid(@current_spacecraft.scid)}</span>
            </div>
            <div class="hud-data-row">
              <span class="hud-data-label">Display name</span>
              <span class="hud-data-value">{@current_spacecraft.display_name}</span>
            </div>
            <div class="hud-data-row">
              <span class="hud-data-label">Spacecraft ID</span>
              <span class="hud-data-value text-xs">{@current_spacecraft.spacecraft_id}</span>
            </div>
            <div class="hud-data-row">
              <span class="hud-data-label">Mission</span>
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}"}
                class="hud-data-value text-primary hover:underline"
              >
                {@current_mission.display_name}
              </.link>
            </div>
            <div class="hud-data-row md:col-span-2">
              <span class="hud-data-label">Organization ID</span>
              <span class="hud-data-value text-xs">{@current_spacecraft.organization_id}</span>
            </div>
          </div>

          <div :if={map_size(@current_spacecraft.metadata) > 0} class="pt-2">
            <details class="text-sm">
              <summary class="cursor-pointer hud-label text-base-content/50 hover:text-primary">
                Metadata
              </summary>
              <pre class="mt-2 p-3 bg-base-300/40 border border-base-300 rounded-sm overflow-x-auto text-xs font-mono">{Jason.encode!(@current_spacecraft.metadata, pretty: true)}</pre>
            </details>
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
  attr :status, :atom, required: true
  attr :navigate, :string, default: nil
  attr :action_label, :string, default: nil

  defp workflow_card(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "card bg-base-200 border border-base-300",
        workflow_accent(@status)
      ]}
    >
      <div class="card-body p-5">
        <div class="flex items-start justify-between gap-3">
          <p class="hud-label">{@title}</p>
          <.status_badge status={@status} />
        </div>
        <h2 class="mt-3 text-base font-semibold">{@value}</h2>
        <p class="mt-2 text-sm text-base-content/60">{@description}</p>
        <.link
          :if={@navigate}
          navigate={@navigate}
          class="mt-4 inline-flex text-sm text-primary hover:underline"
        >
          {@action_label} &rarr;
        </.link>
      </div>
    </div>
    """
  end

  defp workflow_accent(:ready), do: "border-l-2 border-l-success/60"
  defp workflow_accent(:attention), do: "border-l-2 border-l-warning/60"
  defp workflow_accent(:blocked), do: "border-l-2 border-l-error/60"
  defp workflow_accent(_), do: "border-l-2 border-l-transparent"

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

  defp overall_status(spacecraft, telemetry_status) do
    if SpacecraftCommsReadiness.identity_ready?(spacecraft) and telemetry_status == :applied do
      :ready
    else
      :attention
    end
  end

  defp overall_readiness_label(spacecraft, telemetry_status) do
    if overall_status(spacecraft, telemetry_status) == :ready do
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
    do: "Configure application packet claims for this spacecraft."

  defp configure_label(:not_configured), do: "Configure"
  defp configure_label(_), do: "Manage"

  defp format_scid(nil), do: "Not set"
  defp format_scid(scid), do: Integer.to_string(scid)
end
