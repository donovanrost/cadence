defmodule CadenceWeb.SpacecraftShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.SpacecraftShowComponents, only: [type_binding_card: 1, applications_card: 1]

  alias Cadence.Applications.HostContext
  alias CadenceWeb.ApplicationInventory
  alias CadenceWeb.SpacecraftApplicationSummary
  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id

    runtime_identity =
      SpacecraftCommsReadiness.runtime_identity(organization_id, mission_id, spacecraft)

    type_binding = load_type_binding(organization_id, mission_id, spacecraft)
    host_context = HostContext.spacecraft(mission_id, spacecraft.spacecraft_id)
    applications = load_applications(socket.assigns.current_scope, type_binding, host_context)
    application_summary = SpacecraftApplicationSummary.build(type_binding, applications)

    {:ok,
     socket
     |> assign(:page_title, spacecraft.display_name)
     |> assign(:nav_item, :spacecraft)
     |> assign(:applications_empty?, applications == [])
     |> assign(:application_summary, application_summary)
     |> assign(:runtime_identity, runtime_identity)
     |> assign(:type_binding, type_binding)
     |> stream_configure(:profile_applications, dom_id: &application_dom_id/1)
     |> stream(:profile_applications, applications)}
  end

  defp load_applications(scope, nil, host_context) do
    load_declared_applications(scope, host_context, %{})
  end

  defp load_applications(scope, %{pinned: %{applications: declarations}}, host_context) do
    load_declared_applications(scope, host_context, declarations)
  end

  defp load_declared_applications(scope, host_context, declarations) do
    case ApplicationInventory.declared(scope, host_context, declarations) do
      {:ok, applications} -> applications
      {:error, _reason} -> []
    end
  end

  defp load_type_binding(_organization_id, _mission_id, %{spacecraft_type_id: nil}), do: nil

  defp load_type_binding(organization_id, mission_id, spacecraft) do
    pinned =
      Cadence.SpacecraftTypeStore.fetch_spacecraft_type_version(
        organization_id,
        mission_id,
        spacecraft.spacecraft_type_id,
        spacecraft.spacecraft_type_version
      )

    latest =
      Cadence.SpacecraftTypeStore.fetch_spacecraft_type(
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div id="spacecraft-show-page" class="space-y-6">
      <.page_header
        title={@current_spacecraft.display_name}
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name, nil}
        ]}
      >
        <:title_suffix>
          <span :if={@current_spacecraft.scid} class="mc-value-small text-base-content">
            SCID {@current_spacecraft.scid}
          </span>
          <span :if={is_nil(@current_spacecraft.scid)} class="hud-label text-warning/70">
            SCID not set
          </span>
        </:title_suffix>
      </.page_header>

      <.type_binding_card
        mission_id={@current_mission.mission_id}
        spacecraft_id={@current_spacecraft.spacecraft_id}
        type_binding={@type_binding}
      />

      <.applications_card
        type_binding={@type_binding}
        applications={@streams.profile_applications}
        applications_empty?={@applications_empty?}
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
          id="spacecraft-overview-applications"
          title="Applications"
          value={@application_summary.status.label}
          description={@application_summary.description}
          status={@application_summary.status.tone}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/applications"
          }
          action_label={@application_summary.action_label}
        />
        <.workflow_card
          id="spacecraft-overview-readiness"
          title="Readiness"
          value={overall_readiness_label(@current_spacecraft, @application_summary)}
          description="Identity and application status at a glance."
          status={overall_status(@current_spacecraft, @application_summary)}
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/readiness"
          }
          action_label="Review"
        />
      </section>

      <.overview_card
        current_spacecraft={@current_spacecraft}
        current_mission={@current_mission}
      />
    </div>
    </Layouts.app>
    """
  end

  attr :current_spacecraft, :any, required: true
  attr :current_mission, :any, required: true

  defp overview_card(assigns) do
    ~H"""
    <.card title="Overview">
      <div class="mt-3 grid gap-x-8 gap-y-1 md:grid-cols-2">
        <.detail_row label="SCID" value={format_scid(@current_spacecraft.scid)} />
        <.detail_row label="Display name" value={@current_spacecraft.display_name} />
        <.detail_row label="Spacecraft ID">
          <span class="text-xs">{@current_spacecraft.spacecraft_id}</span>
        </.detail_row>
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
          <summary class="cursor-pointer hud-label hover:text-primary">
            Metadata
          </summary>
          <pre class="mt-2 p-3 bg-base-300/40 border border-base-300 rounded-sm overflow-x-auto text-xs font-mono">{Jason.encode!(@current_spacecraft.metadata, pretty: true)}</pre>
        </details>
      </div>
    </.card>
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
    <.card id={@id}>
      <div class="flex items-start justify-between gap-3">
        <p class="hud-label">{@title}</p>
        <.status_badge status={@status} />
      </div>
      <h2 class="mt-3 text-base font-semibold">{@value}</h2>
      <p class="mt-2 text-sm text-base-content/70">{@description}</p>
      <.link
        :if={@navigate}
        navigate={@navigate}
        class="mt-4 inline-flex text-sm text-primary hover:underline"
      >
        {@action_label} &rarr;
      </.link>
    </.card>
    """
  end

  defp identity_status(%{scid: nil}, _runtime_identity), do: :blocked
  defp identity_status(_spacecraft, nil), do: :attention
  defp identity_status(_spacecraft, _runtime_identity), do: :ready

  defp identity_summary(%{scid: nil}, _runtime_identity), do: "Missing SCID"
  defp identity_summary(_spacecraft, nil), do: "Runtime identity missing"
  defp identity_summary(spacecraft, _runtime_identity), do: "SCID #{spacecraft.scid} configured"

  defp overall_status(spacecraft, application_summary) do
    if SpacecraftCommsReadiness.identity_ready?(spacecraft) and application_summary.ready? do
      :ready
    else
      :attention
    end
  end

  defp overall_readiness_label(spacecraft, application_summary) do
    if overall_status(spacecraft, application_summary) == :ready do
      "Ready"
    else
      "Needs review"
    end
  end

  defp application_dom_id(application) do
    safe_key = String.replace(application.application_key, ~r/[^A-Za-z0-9_-]+/, "-")
    "spacecraft-profile-application-#{safe_key}"
  end

  defp format_scid(nil), do: "Not set"
  defp format_scid(scid), do: Integer.to_string(scid)
end
