defmodule CadenceWeb.CommsOverviewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  alias CadenceWeb.CommsValidation

  @impl true
  def mount(_params, _session, socket) do
    summary = load_summary(socket.assigns)
    overview = overview_dto(socket.assigns.current_mission.mission_id, summary)

    {:ok,
     socket
     |> assign(:page_title, "Comms")
     |> assign(:nav_item, :comms_overview)
     |> assign(:overview, overview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="comms-overview-page" class="space-y-6">
        <.page_header title={@current_mission.display_name} eyebrow="Communications">
          <:title_suffix>&middot; Mission Comms</:title_suffix>
        </.page_header>

        <.vue
          id="comms-overview-component"
          v-component="CommsOverview"
          overview={@overview}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp load_summary(%{current_scope: scope, current_mission: mission}) do
    spacecraft =
      Cadence.SpacecraftStore.list_spacecraft(scope.organization_id, mission.mission_id)

    source_endpoints =
      Cadence.SourceEndpoints.list_source_endpoints(scope.organization_id, mission.mission_id)

    transports =
      TransportStore.list_transports(scope.organization_id, mission.mission_id)

    provider_profiles =
      Cadence.Contacts.list_provider_profiles(scope.organization_id, mission.mission_id)

    transport_profiles =
      Cadence.Contacts.list_transport_profiles(scope.organization_id, mission.mission_id)

    path_templates =
      Cadence.Contacts.list_path_templates(scope.organization_id, mission.mission_id)

    routing_rules =
      RoutingRuleStore.list_routing_rules(scope.organization_id, mission.mission_id)

    findings =
      CommsValidation.findings_for_resources(
        scope,
        mission.mission_id,
        %{
          spacecraft: spacecraft,
          source_endpoints: source_endpoints,
          path_templates: path_templates,
          provider_profiles: provider_profiles,
          transport_profiles: transport_profiles,
          transports: transports,
          routing_rules: routing_rules
        }
      )

    %{
      transports: Enum.take(transports, 6),
      transport_count: length(transports),
      findings: findings,
      finding_groups: CommsValidation.finding_groups(findings)
    }
  end

  defp overview_dto(mission_id, summary) do
    %{
      transport: transport_summary_dto(mission_id, summary),
      validation: validation_summary_dto(summary)
    }
  end

  defp transport_summary_dto(mission_id, summary) do
    count = summary.transport_count

    %{
      id: "comms-transports",
      eyebrow: "Transport",
      count: count,
      count_label: if(count == 1, do: "transport configured", else: "transports configured"),
      description:
        "Transports describe durable capabilities for moving bytes. Routing rules will decide how spacecraft use those capabilities.",
      status: transport_status_dto(count),
      empty: summary.transports == [],
      empty_state: %{
        title: "No transports configured",
        description: "Add a transport to describe a byte-moving capability for this mission.",
        action_label: "Add a transport",
        action_href: ~p"/missions/#{mission_id}/comms/transports/new"
      },
      rows: Enum.map(summary.transports, &transport_dto(&1, mission_id)),
      manage_label: "Manage transports →",
      manage_href: ~p"/missions/#{mission_id}/comms/transports",
      add_label: "+ Add a transport",
      add_href: ~p"/missions/#{mission_id}/comms/transports/new"
    }
  end

  defp transport_status_dto(0), do: status_dto(:attention, "Needs Work")
  defp transport_status_dto(_count), do: status_dto(:ready, "Ready")

  defp transport_dto(transport, mission_id) do
    %{
      id: "comms-transport-#{transport.transport_id}",
      display_name: transport.display_name,
      metadata:
        "#{transport.transport_kind} · #{transport.direction_capability} · v#{transport.version}",
      href: ~p"/missions/#{mission_id}/comms/transports/#{transport.transport_id}"
    }
  end

  defp validation_summary_dto(summary) do
    finding_count = length(summary.findings)

    %{
      id: "comms-validation-page",
      eyebrow: "Setup Checks",
      title: "What's missing or broken",
      description: "Checks on saved configuration for spacecraft on this mission.",
      status: validation_status_dto(finding_count),
      empty: summary.findings == [],
      empty_state: %{
        title: "All clear",
        description: "The saved configuration looks consistent."
      },
      findings_id: "comms-validation-findings",
      finding_groups: Enum.map(summary.finding_groups, &finding_group_dto/1)
    }
  end

  defp validation_status_dto(0), do: status_dto(:ready, "No Findings")

  defp validation_status_dto(finding_count),
    do: status_dto(:attention, "#{finding_count} Findings")

  defp finding_group_dto(group) do
    %{
      id: group.id,
      title: group.title,
      description: group.description,
      findings: Enum.map(group.findings, &finding_dto/1)
    }
  end

  defp finding_dto(finding) do
    action_href = Map.get(finding, :action_navigate)

    %{
      id: Map.get(finding, :id),
      title: finding.title,
      body: finding.body,
      action_label: action_href && Map.get(finding, :action_label, "Review"),
      action_href: action_href,
      status: status_dto(finding.severity, CommsValidation.finding_label(finding.severity))
    }
  end

  defp status_dto(tone, label) do
    %{tone: Atom.to_string(tone), label: label}
  end
end
