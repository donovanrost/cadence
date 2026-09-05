defmodule CadenceWeb.SpacecraftShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Applications.HostContext
  alias CadenceWeb.ApplicationInventory
  alias CadenceWeb.SpacecraftApplicationSummary
  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    runtime_identity =
      SpacecraftCommsReadiness.runtime_identity(
        organization_id,
        mission.mission_id,
        spacecraft
      )

    type_binding = load_type_binding(organization_id, mission.mission_id, spacecraft)
    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)
    applications = load_applications(socket.assigns.current_scope, type_binding, host_context)
    application_summary = SpacecraftApplicationSummary.build(type_binding, applications)

    {:ok,
     socket
     |> assign(:page_title, spacecraft.display_name)
     |> assign(:nav_item, :spacecraft)
     |> assign(:spacecraft_page, page_dto(mission, spacecraft))
     |> assign(
       :profile_binding,
       profile_binding_dto(type_binding, mission.mission_id, spacecraft.spacecraft_id)
     )
     |> assign(
       :application_inventory,
       application_inventory_dto(
         type_binding,
         applications,
         mission.mission_id,
         spacecraft.spacecraft_id
       )
     )
     |> assign(
       :workflow_cards,
       workflow_cards_dto(
         spacecraft,
         runtime_identity,
         application_summary,
         mission.mission_id
       )
     )
     |> assign(:spacecraft_overview, overview_dto(mission, spacecraft))}
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
      <.vue
        id="spacecraft-show-component"
        v-component="FederatedFullPageSurface"
        application_key="spacecraft"
        surface_id="show"
        host_scope="spacecraft"
        mission_id={@current_mission.mission_id}
        spacecraft_id={@current_spacecraft.spacecraft_id}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp page_dto(mission, spacecraft) do
    %{
      id: "spacecraft-show-page",
      header: %{
        title: spacecraft.display_name,
        breadcrumbs: [
          breadcrumb_dto(mission.display_name, ~p"/missions/#{mission.mission_id}"),
          breadcrumb_dto("Spacecraft", ~p"/missions/#{mission.mission_id}/spacecraft"),
          breadcrumb_dto(spacecraft.display_name, nil)
        ],
        title_suffix: %{
          set: not is_nil(spacecraft.scid),
          label: if(is_nil(spacecraft.scid), do: "SCID not set", else: "SCID #{spacecraft.scid}")
        }
      }
    }
  end

  defp breadcrumb_dto(label, href), do: %{label: label, href: href}

  defp profile_binding_dto(nil, mission_id, spacecraft_id) do
    %{
      id: "spacecraft-profile-binding",
      eyebrow: "Spacecraft Profile",
      bound: false,
      title: "No profile selected",
      description: "Select a spacecraft profile to pin a reusable byte-interpretation contract.",
      version: nil,
      protocols: [],
      status: status_dto(:attention, "Unbound"),
      view_profile_href: nil,
      profile_action: %{
        label: "Select profile",
        href: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/identity"
      }
    }
  end

  defp profile_binding_dto(type_binding, mission_id, spacecraft_id) do
    pinned = type_binding.pinned

    status =
      if type_binding.drift? do
        status_dto(:attention, "Drift · latest v#{type_binding.latest_version}")
      else
        status_dto(:ready, "Current")
      end

    %{
      id: "spacecraft-profile-binding",
      eyebrow: "Spacecraft Profile",
      bound: true,
      title: pinned.display_name,
      description: nil,
      version: "v#{pinned.version}",
      protocols: [
        %{label: "DOWN", value: to_string(pinned.downlink_protocol)},
        %{label: "UP", value: to_string(pinned.uplink_protocol)}
      ],
      status: status,
      view_profile_href:
        ~p"/missions/#{mission_id}/spacecraft/profiles/#{pinned.spacecraft_type_id}",
      profile_action: %{
        label: "Change profile",
        href: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/identity"
      }
    }
  end

  defp application_inventory_dto(type_binding, applications, mission_id, spacecraft_id) do
    %{
      id: "spacecraft-applications",
      list_id: "spacecraft-profile-applications",
      visible: not is_nil(type_binding) or applications != [],
      title: "Applications",
      description:
        if(is_nil(type_binding),
          do:
            "Retained spacecraft installations. Select a profile to restore desired application declarations.",
          else:
            "Platform applications enabled by this spacecraft's profile. Per-application configuration is set per spacecraft."
        ),
      empty: applications == [],
      empty_state: "No applications enabled by this profile.",
      rows: Enum.map(applications, &application_dto(&1, mission_id, spacecraft_id)),
      view_action: %{
        label: "View applications",
        href: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/applications"
      }
    }
  end

  defp application_dto(application, mission_id, spacecraft_id) do
    %{
      id: application_dom_id(application),
      application_key: application.application_key,
      display_name: application.display_name,
      status: status_dto(application.status.tone, application.status.label),
      manage_href:
        if(application.manageable?,
          do:
            ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/applications/#{application.application_key}",
          else: nil
        )
    }
  end

  defp workflow_cards_dto(spacecraft, runtime_identity, application_summary, mission_id) do
    spacecraft_id = spacecraft.spacecraft_id

    [
      workflow_card_dto(
        "spacecraft-overview-identity",
        "Identity",
        identity_summary(spacecraft, runtime_identity),
        "Values Cadence uses to recognize incoming bytes.",
        identity_status(spacecraft, runtime_identity),
        "Edit Identity",
        ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/identity"
      ),
      workflow_card_dto(
        "spacecraft-overview-applications",
        "Applications",
        application_summary.status.label,
        application_summary.description,
        application_summary.status.tone,
        application_summary.action_label,
        ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/applications"
      ),
      workflow_card_dto(
        "spacecraft-overview-readiness",
        "Readiness",
        overall_readiness_label(spacecraft, application_summary),
        "Identity and application status at a glance.",
        overall_status(spacecraft, application_summary),
        "Review",
        ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/readiness"
      )
    ]
  end

  defp workflow_card_dto(id, title, value, description, status, action_label, action_href) do
    %{
      id: id,
      title: title,
      value: value,
      description: description,
      status: status_dto(status),
      action: %{label: action_label, href: action_href}
    }
  end

  defp overview_dto(mission, spacecraft) do
    %{
      title: "Overview",
      scid: %{label: "SCID", value: format_scid(spacecraft.scid)},
      display_name: %{label: "Display name", value: spacecraft.display_name},
      spacecraft_id: %{label: "Spacecraft ID", value: spacecraft.spacecraft_id},
      mission: %{
        label: "Mission",
        value: mission.display_name,
        href: ~p"/missions/#{mission.mission_id}"
      },
      organization_id: %{
        label: "Organization ID",
        value: spacecraft.organization_id
      },
      metadata_json: metadata_json(spacecraft.metadata)
    }
  end

  defp metadata_json(metadata) when map_size(metadata) == 0, do: nil
  defp metadata_json(metadata), do: Jason.encode!(metadata, pretty: true)

  defp status_dto(status, label \\ nil) do
    %{tone: Atom.to_string(status), label: label || status_label(status)}
  end

  defp status_label(:ready), do: "Ready"
  defp status_label(:attention), do: "Needs Work"
  defp status_label(:blocked), do: "Missing"
  defp status_label(:info), do: "Setup"

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
