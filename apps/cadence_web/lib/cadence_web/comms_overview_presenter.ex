defmodule CadenceWeb.CommsOverviewPresenter do
  @moduledoc """
  Builds the JSON-safe presentation DTO shared by the Comms LiveView and the
  federated application-host query.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Comms.{RoutingRuleStore, TransportStore}
  alias Cadence.Missions.Mission
  alias CadenceWeb.CommsValidation

  @spec build(Scope.t(), Mission.t()) :: map()
  def build(%Scope{} = current_scope, %Mission{} = mission) do
    presentation(mission, load_summary(current_scope, mission))
  end

  @spec presentation(Mission.t(), map()) :: map()
  def presentation(%Mission{} = mission, summary) when is_map(summary) do
    %{
      root: %{
        attrs:
          presentation_attrs(%{
            "class" => "space-y-6",
            "id" => "comms-overview-page"
          })
      },
      header: %{
        attrs: presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
        body: %{attrs: presentation_attrs(%{"class" => false})},
        content: %{attrs: presentation_attrs(%{})},
        eyebrow: %{
          attrs: presentation_attrs(%{"class" => "hud-label"}),
          text: "Communications"
        },
        title: %{
          attrs:
            presentation_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          text: mission.display_name
        },
        title_suffix: %{
          attrs:
            presentation_attrs(%{
              "class" => "ml-3 font-mono text-base text-base-content/60"
            }),
          text: "· Mission Comms"
        }
      },
      overview: overview_dto(mission.mission_id, summary)
    }
    |> json_safe()
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp load_summary(%Scope{organization_id: organization_id} = scope, %Mission{} = mission) do
    spacecraft = Cadence.SpacecraftStore.list_spacecraft(organization_id, mission.mission_id)

    source_endpoints =
      Cadence.SourceEndpoints.list_source_endpoints(organization_id, mission.mission_id)

    transports = TransportStore.list_transports(organization_id, mission.mission_id)

    provider_profiles =
      Cadence.Contacts.list_provider_profiles(organization_id, mission.mission_id)

    transport_profiles =
      Cadence.Contacts.list_transport_profiles(organization_id, mission.mission_id)

    path_templates = Cadence.Contacts.list_path_templates(organization_id, mission.mission_id)

    routing_rules = RoutingRuleStore.list_routing_rules(organization_id, mission.mission_id)

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

  defp json_safe(%{} = map) do
    Map.new(map, fn {key, value} -> {json_key(key), json_safe(value)} end)
  end

  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)
  defp json_safe(value) when is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: key
end
