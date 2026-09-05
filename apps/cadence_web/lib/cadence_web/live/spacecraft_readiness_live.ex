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
     |> assign(
       :readiness_page,
       readiness_page_dto(mission, spacecraft, application_summary, type_binding)
     )
     |> assign(
       :readiness_panels,
       readiness_panels_dto(mission, spacecraft, application_summary, type_binding)
     )
     |> assign(:readiness_applications, Enum.map(applications, &application_dto/1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-readiness-component"
        v-component="FederatedFullPageSurface"
        page={@readiness_page}
        panels={@readiness_panels}
        applications={@readiness_applications}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp readiness_page_dto(mission, spacecraft, application_summary, type_binding) do
    %{
      id: "spacecraft-readiness-page",
      title: "Readiness",
      title_suffix: "· #{spacecraft.display_name}",
      subtitle: "Identity, profile, and application setup for this spacecraft.",
      breadcrumbs: [
        breadcrumb_dto(mission.display_name, ~p"/missions/#{mission.mission_id}"),
        breadcrumb_dto("Spacecraft", ~p"/missions/#{mission.mission_id}/spacecraft"),
        breadcrumb_dto(
          spacecraft.display_name,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
        ),
        breadcrumb_dto("Readiness", nil)
      ],
      status: status_dto(overall_status(spacecraft, application_summary, type_binding))
    }
  end

  defp readiness_panels_dto(mission, spacecraft, application_summary, type_binding) do
    identity_href =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"

    applications_href =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"

    routing_href =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"

    [
      panel_dto(
        "spacecraft-readiness-identity",
        "Identity",
        status_dto(identity_status(spacecraft), identity_status_label(spacecraft)),
        identity_description(spacecraft),
        [detail_dto("SCID", format_scid(spacecraft.scid))],
        action_dto("Edit Identity", identity_href)
      ),
      panel_dto(
        "spacecraft-readiness-profile",
        "Spacecraft Profile",
        status_dto(profile_status(type_binding), profile_status_label(type_binding)),
        profile_description(type_binding),
        [detail_dto("Pinned Profile", profile_detail(type_binding))],
        action_dto(profile_action_label(type_binding), identity_href)
      ),
      panel_dto(
        "spacecraft-readiness-applications",
        "Applications",
        status_dto(application_summary.status.tone, application_summary.status.label),
        application_summary.description,
        [],
        action_dto(application_summary.action_label, applications_href),
        %{
          id: "spacecraft-readiness-application-list",
          empty_state: %{
            id: "spacecraft-readiness-applications-empty",
            description: "No profile applications declared."
          }
        }
      ),
      panel_dto(
        "spacecraft-readiness-routing",
        "Routing",
        status_dto(:info, "Tracked in Comms"),
        "Routing Rules describe durable spacecraft use of mission transports.",
        [detail_dto("Setup Area", "Routing Rules")],
        action_dto("Review Routing", routing_href)
      )
    ]
  end

  defp panel_dto(id, title, status, description, details, action, application_list \\ nil) do
    %{
      id: id,
      title: title,
      status: status,
      description: description,
      details: details,
      action: action,
      application_list: application_list
    }
  end

  defp breadcrumb_dto(label, href), do: %{label: label, href: href}
  defp detail_dto(label, value), do: %{label: label, value: value}
  defp action_dto(label, href), do: %{label: label, href: href}

  defp application_dto(application) do
    %{
      id: application_dom_id(application),
      application_key: application.application_key,
      display_name: application.display_name,
      status: status_dto(application.status.tone, application.status.label)
    }
  end

  defp status_dto(tone), do: status_dto(tone, status_label(tone))
  defp status_dto(tone, label), do: %{tone: Atom.to_string(tone), label: label}

  defp status_label(:ready), do: "Ready"
  defp status_label(:attention), do: "Needs Work"
  defp status_label(:blocked), do: "Missing"
  defp status_label(:info), do: "Setup"

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
