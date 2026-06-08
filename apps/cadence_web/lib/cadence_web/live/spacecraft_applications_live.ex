defmodule CadenceWeb.SpacecraftApplicationsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents, only: [status_badge: 1]

  alias Cadence.Applications.TelemetryDecom
  alias CadenceWeb.SpacecraftTypeApplications

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    type_binding = load_type_binding(scope.organization_id, mission.mission_id, spacecraft)
    telemetry_status = telemetry_status(scope.organization_id, mission.mission_id, spacecraft)

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Applications")
     |> assign(:nav_item, :spacecraft)
     |> assign(:type_binding, type_binding)
     |> assign(:telemetry_decom_status, telemetry_status)
     |> assign(:applications, application_rows(type_binding, telemetry_status))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-applications-page" class="space-y-6">
      <div class="border-b border-primary/20 pb-4">
        <.breadcrumbs items={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name,
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
          {"Applications", nil}
        ]} />
        <div class="mt-2 flex items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-base-content tracking-tight">
              Applications
            </h1>
            <p class="mt-2 max-w-3xl text-sm text-base-content/60">
              Spacecraft-scoped application setup for packet claims and runtime publication.
            </p>
          </div>
          <.link
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/readiness"
            }
            class="btn btn-ghost btn-sm"
          >
            Readiness
          </.link>
        </div>
      </div>

      <section
        :if={is_nil(@type_binding)}
        id="spacecraft-applications-no-profile"
        class="card bg-base-200 border border-base-300 border-l-2 border-l-warning/60"
      >
        <div class="card-body p-6">
          <p class="hud-label">Spacecraft Profile</p>
          <h2 class="mt-2 text-base font-semibold">No profile selected</h2>
          <p class="mt-1 text-sm text-base-content/60">
            Select a Spacecraft Profile before configuring application packet claims.
          </p>
          <.link
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
            }
            class="btn btn-primary btn-sm mt-5"
          >
            Select profile
          </.link>
        </div>
      </section>

      <section
        :if={@type_binding}
        id="spacecraft-applications-profile"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label">Pinned Profile</p>
              <h2 class="mt-2 text-base font-semibold">
                {@type_binding.pinned.display_name}
                <span class="mc-value-small text-primary/70">v{@type_binding.pinned.version}</span>
              </h2>
            </div>
            <.status_badge
              status={if(@type_binding.drift?, do: :attention, else: :ready)}
              label={if(@type_binding.drift?, do: "Profile drift", else: "Current")}
            />
          </div>
        </div>
      </section>

      <section
        :if={@type_binding}
        id="spacecraft-applications-list"
        class="grid gap-4 lg:grid-cols-2"
      >
        <.application_card
          :for={app <- @applications}
          app={app}
          mission={@current_mission}
          spacecraft={@current_spacecraft}
        />
      </section>
    </div>
    """
  end

  attr :app, :map, required: true
  attr :mission, :map, required: true
  attr :spacecraft, :map, required: true

  defp application_card(assigns) do
    ~H"""
    <section
      id={"spacecraft-application-#{@app.key}"}
      class={[
        "card bg-base-200 border border-base-300",
        application_accent(@app.status)
      ]}
    >
      <div class="card-body p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="hud-label">Application</p>
            <h2 class="mt-2 text-base font-semibold">{@app.display_name}</h2>
          </div>
          <.status_badge status={panel_status(@app.status)} label={@app.status_label} />
        </div>
        <p class="mt-3 text-sm text-base-content/60">{@app.description}</p>
        <div class="mt-5 space-y-1">
          <div class="hud-data-row">
            <span class="hud-data-label">Packet claims</span>
            <span class="hud-data-value">{@app.claims_label}</span>
          </div>
          <div class="hud-data-row">
            <span class="hud-data-label">Publication</span>
            <span class="hud-data-value">{@app.publication_label}</span>
          </div>
        </div>
        <.link
          :if={@app.available?}
          navigate={
            ~p"/missions/#{@mission.mission_id}/spacecraft/#{@spacecraft.spacecraft_id}/applications/#{@app.key}"
          }
          class="btn btn-primary btn-sm mt-5"
        >
          Manage
        </.link>
        <p :if={not @app.available?} class="mt-5 text-xs text-base-content/50">
          Not available yet.
        </p>
      </div>
    </section>
    """
  end

  defp application_rows(nil, _telemetry_status), do: []

  defp application_rows(%{pinned: %{applications: applications}}, telemetry_status) do
    entries_by_key = Map.new(SpacecraftTypeApplications.all(), &{&1.key, &1})

    applications
    |> Enum.sort()
    |> Enum.map(fn {key, _config} ->
      entry = Map.fetch!(entries_by_key, key)
      application_row(entry, telemetry_status)
    end)
  end

  defp application_row(%{key: :telemetry_decom} = entry, telemetry_status) do
    %{
      key: :telemetry_decom,
      display_name: entry.display_name,
      description: entry.description,
      available?: entry.available?,
      status: telemetry_status,
      status_label: telemetry_status_label(telemetry_status),
      claims_label: claims_label(telemetry_status),
      publication_label: publication_label(telemetry_status)
    }
  end

  defp application_row(entry, _telemetry_status) do
    %{
      key: entry.key,
      display_name: entry.display_name,
      description: entry.description,
      available?: entry.available?,
      status: :not_configured,
      status_label: if(entry.available?, do: "Not configured", else: "Roadmap"),
      claims_label: "None",
      publication_label: "Not published"
    }
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

  defp telemetry_status(organization_id, mission_id, spacecraft) do
    config =
      case TelemetryDecom.fetch_config(organization_id, mission_id, spacecraft.spacecraft_id) do
        {:ok, config} -> config
        {:error, :not_configured} -> nil
      end

    active =
      case Cadence.fetch_active_binding_set_activation(organization_id, mission_id) do
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

  defp application_accent(:applied), do: "border-l-2 border-l-success/60"
  defp application_accent(:configured), do: "border-l-2 border-l-warning/60"
  defp application_accent(:outdated), do: "border-l-2 border-l-warning/60"
  defp application_accent(:disabled), do: "border-l-2 border-l-error/60"
  defp application_accent(_status), do: "border-l-2 border-l-transparent"

  defp panel_status(:applied), do: :ready
  defp panel_status(:configured), do: :attention
  defp panel_status(:outdated), do: :attention
  defp panel_status(:disabled), do: :blocked
  defp panel_status(_status), do: :blocked

  defp telemetry_status_label(:applied), do: "Applied"
  defp telemetry_status_label(:configured), do: "Configured"
  defp telemetry_status_label(:outdated), do: "Out of date"
  defp telemetry_status_label(:disabled), do: "Disabled"
  defp telemetry_status_label(:not_configured), do: "Not configured"

  defp claims_label(:not_configured), do: "None"
  defp claims_label(:disabled), do: "Disabled"
  defp claims_label(_status), do: "Configured"

  defp publication_label(:applied), do: "Live"
  defp publication_label(:configured), do: "Saved, not live"
  defp publication_label(:outdated), do: "Needs apply"
  defp publication_label(:disabled), do: "Disabled"
  defp publication_label(:not_configured), do: "Not published"
end
