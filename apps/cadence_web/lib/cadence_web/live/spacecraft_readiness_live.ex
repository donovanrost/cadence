defmodule CadenceWeb.SpacecraftReadinessLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Applications.HostContext
  alias CadenceWeb.ApplicationInventory
  alias CadenceWeb.SpacecraftApplicationSummary

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    type_binding = load_type_binding(scope.organization_id, mission.mission_id, spacecraft)
    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)
    applications = load_applications(scope, type_binding, host_context)
    application_summary = SpacecraftApplicationSummary.build(type_binding, applications)

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Readiness")
     |> assign(:nav_item, :spacecraft)
     |> assign(:application_summary, application_summary)
     |> assign(:type_binding, type_binding)
     |> stream_configure(:readiness_applications, dom_id: &application_dom_id/1)
     |> stream(:readiness_applications, applications)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div id="spacecraft-readiness-page" class="space-y-6">
      <.page_header
        title="Readiness"
        subtitle="Identity, profile, and application setup for this spacecraft."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name,
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
          {"Readiness", nil}
        ]}
      >
        <:title_suffix>&middot; {@current_spacecraft.display_name}</:title_suffix>
        <:actions>
          <.status_badge status={
            overall_status(@current_spacecraft, @application_summary, @type_binding)
          } />
        </:actions>
      </.page_header>

      <div class="grid gap-4 xl:grid-cols-2">
        <.readiness_panel
          id="spacecraft-readiness-identity"
          title="Identity"
          status={identity_status(@current_spacecraft)}
          status_label={identity_status_label(@current_spacecraft)}
          description={identity_description(@current_spacecraft)}
          action_label="Edit Identity"
          action_navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
          }
        >
          <:detail label="SCID" value={format_scid(@current_spacecraft.scid)} />
        </.readiness_panel>

        <.readiness_panel
          id="spacecraft-readiness-profile"
          title="Spacecraft Profile"
          status={profile_status(@type_binding)}
          status_label={profile_status_label(@type_binding)}
          description={profile_description(@type_binding)}
          action_label={profile_action_label(@type_binding)}
          action_navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
          }
        >
          <:detail label="Pinned Profile" value={profile_detail(@type_binding)} />
        </.readiness_panel>

        <.readiness_panel
          id="spacecraft-readiness-applications"
          title="Applications"
          status={@application_summary.status.tone}
          status_label={@application_summary.status.label}
          description={@application_summary.description}
          action_label={@application_summary.action_label}
          action_navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/applications"
          }
        >
          <div id="spacecraft-readiness-application-list" phx-update="stream">
            <p
              id="spacecraft-readiness-applications-empty"
              class="hidden only:block text-sm text-base-content/60"
            >
              No profile applications declared.
            </p>
            <div :for={{dom_id, application} <- @streams.readiness_applications} id={dom_id}>
              <.detail_row label={application.display_name} value={application.status.label} />
            </div>
          </div>
        </.readiness_panel>

        <.readiness_panel
          id="spacecraft-readiness-routing"
          title="Routing"
          status={:info}
          status_label="Tracked in Comms"
          description="Routing Rules describe durable spacecraft use of mission transports."
          action_label="Review Routing"
          action_navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/routing"
          }
        >
          <:detail label="Setup Area" value="Routing Rules" />
        </.readiness_panel>
      </div>
    </div>
    </Layouts.app>
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

  slot :inner_block

  defp readiness_panel(assigns) do
    ~H"""
    <.card id={@id}>
      <div class="flex items-start justify-between gap-4">
        <p class="hud-label">{@title}</p>
        <.status_badge status={@status} label={@status_label} />
      </div>
      <h2 class="mt-3 text-base font-semibold">{@status_label}</h2>
      <p class="mt-1 text-sm text-base-content/70">{@description}</p>

      <div class="mt-5 space-y-1">
        <.detail_row :for={detail <- @detail} label={detail.label} value={detail.value} />
        {render_slot(@inner_block)}
      </div>

      <.button :if={@action_navigate} navigate={@action_navigate} class="mt-5">
        {@action_label}
      </.button>
    </.card>
    """
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

  defp overall_status(spacecraft, application_summary, type_binding) do
    if identity_status(spacecraft) == :ready and profile_status(type_binding) == :ready and
         application_summary.ready? do
      :ready
    else
      :attention
    end
  end

  defp identity_status(%{scid: nil}), do: :blocked
  defp identity_status(_spacecraft), do: :ready

  defp identity_status_label(%{scid: nil}), do: "Missing SCID"
  defp identity_status_label(_spacecraft), do: "Ready"

  defp identity_description(%{scid: nil}),
    do: "Set SCID so Cadence can identify this spacecraft from TM transfer frames."

  defp identity_description(_spacecraft),
    do: "The spacecraft identity is configured."

  defp profile_status(nil), do: :attention
  defp profile_status(%{drift?: true}), do: :attention
  defp profile_status(_type_binding), do: :ready

  defp profile_status_label(nil), do: "No profile selected"
  defp profile_status_label(%{drift?: true}), do: "Profile drift"
  defp profile_status_label(_type_binding), do: "Current"

  defp profile_description(nil),
    do: "Select a Spacecraft Profile to pin a reusable byte-interpretation contract."

  defp profile_description(%{drift?: true}),
    do: "A newer Spacecraft Profile version is available; this spacecraft remains pinned."

  defp profile_description(_type_binding),
    do: "The spacecraft is pinned to a Spacecraft Profile version."

  defp profile_action_label(nil), do: "Select Profile"
  defp profile_action_label(_type_binding), do: "Change Profile"

  defp profile_detail(nil), do: "Not selected"

  defp profile_detail(%{pinned: profile}) do
    "#{profile.display_name} v#{profile.version}"
  end

  defp application_dom_id(application) do
    safe_key = String.replace(application.application_key, ~r/[^A-Za-z0-9_-]+/, "-")
    "spacecraft-readiness-application-#{safe_key}"
  end

  defp format_scid(nil), do: "Not set"
  defp format_scid(scid), do: Integer.to_string(scid)
end
