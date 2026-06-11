defmodule CadenceWeb.SpacecraftApplicationsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.Catalog, as: ApplicationCatalog
  alias Cadence.Applications.TelemetryDecom

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
      <.page_header
        title="Applications"
        subtitle="Spacecraft-scoped application setup for packet claims and runtime publication."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name,
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
          {"Applications", nil}
        ]}
      >
        <:actions>
          <.button
            variant={:ghost}
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/readiness"
            }
          >
            Readiness
          </.button>
        </:actions>
      </.page_header>

      <.card
        :if={is_nil(@type_binding)}
        id="spacecraft-applications-no-profile"
        title="Spacecraft Profile"
        accent={:warning}
      >
        <h2 class="mt-2 text-base font-semibold">No profile selected</h2>
        <p class="mt-1 text-sm text-base-content/70">
          Select a Spacecraft Profile before configuring application packet claims.
        </p>
        <.button
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
          }
          class="mt-5"
        >
          Select profile
        </.button>
      </.card>

      <.card :if={@type_binding} id="spacecraft-applications-profile">
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
      </.card>

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
    <.card id={@app.dom_id} accent={application_accent(@app.status)}>
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="hud-label">Application</p>
          <h2 class="mt-2 text-base font-semibold">{@app.display_name}</h2>
        </div>
        <.status_badge status={panel_status(@app.status)} label={@app.status_label} />
      </div>
      <p class="mt-3 text-sm text-base-content/70">{@app.description}</p>
      <div class="mt-5 space-y-1">
        <.detail_row label="Packet claims" value={@app.claims_label} />
        <.detail_row label="Publication" value={@app.publication_label} />
      </div>
      <.button
        :if={@app.available?}
        navigate={
          ~p"/missions/#{@mission.mission_id}/spacecraft/#{@spacecraft.spacecraft_id}/applications/#{@app.key}"
        }
        class="mt-5"
      >
        Manage
      </.button>
      <p :if={not @app.available?} class="mt-5 text-xs text-base-content/50">
        Not available yet.
      </p>
    </.card>
    """
  end

  defp application_rows(nil, _telemetry_status), do: []

  defp application_rows(%{pinned: %{applications: applications}}, telemetry_status) do
    entries_by_key = Map.new(ApplicationCatalog.all(), &{&1.key, &1})

    applications
    |> Enum.sort()
    |> Enum.map(fn {key, config} ->
      entry = Map.get(entries_by_key, key, custom_application_entry(key, config))
      application_row(entry, telemetry_status)
    end)
  end

  defp application_row(%{key: "telemetry_decom"} = entry, telemetry_status) do
    %{
      key: "telemetry_decom",
      dom_id: application_dom_id("telemetry_decom"),
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
      dom_id: application_dom_id(entry.key),
      display_name: entry.display_name,
      description: entry.description,
      available?: entry.available?,
      status: :not_configured,
      status_label: if(entry.available?, do: "Not configured", else: "Roadmap"),
      claims_label: "None",
      publication_label: "Not published"
    }
  end

  defp custom_application_entry(key, config) do
    %{
      key: key,
      display_name: Map.get(config, "display_name", humanize_application_key(key)),
      description: Map.get(config, "description", "Custom spacecraft application."),
      available?: false
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

  defp application_accent(:applied), do: :success
  defp application_accent(:configured), do: :warning
  defp application_accent(:outdated), do: :warning
  defp application_accent(:disabled), do: :error
  defp application_accent(_status), do: nil

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

  defp humanize_application_key(key) do
    key
    |> String.replace(["_", "-", ":"], " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp application_dom_id(key) do
    safe_key = String.replace(key, ~r/[^A-Za-z0-9_-]+/, "-")
    "spacecraft-application-#{safe_key}"
  end
end
