defmodule CadenceWeb.CommsRoutingShowLive do
  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"routing_rule_id" => routing_rule_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case RoutingRuleStore.fetch_routing_rule(
           scope.organization_id,
           mission.mission_id,
           routing_rule_id
         ) do
      {:ok, routing_rule} ->
        spacecraft =
          fetch_spacecraft(scope.organization_id, mission.mission_id, routing_rule)

        transport =
          fetch_transport(scope.organization_id, mission.mission_id, routing_rule)

        events =
          RoutingRuleStore.list_routing_rule_events(
            scope.organization_id,
            mission.mission_id,
            routing_rule.routing_rule_id
          )

        {:ok,
         socket
         |> assign(:page_title, routing_rule.display_name)
         |> assign(:nav_item, :comms_routing)
         |> assign(:navigation, navigation_dto(mission, routing_rule))
         |> assign(:rule, routing_rule_dto(routing_rule, spacecraft, transport))
         |> assign(:events, Enum.map(events, &event_dto/1))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Routing rule not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/routing")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="comms-routing-show-page">
        <.vue
          id="comms-routing-show-component"
          v-component="FederatedFullPageSurface"
          navigation={@navigation}
          rule={@rule}
          events={@events}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp navigation_dto(mission, routing_rule) do
    %{
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{label: "Routing", href: ~p"/missions/#{mission.mission_id}/comms/routing"},
        %{label: routing_rule.display_name, href: nil}
      ]
    }
  end

  defp routing_rule_dto(routing_rule, spacecraft, transport) do
    %{
      display_name: routing_rule.display_name,
      routing_rule_id: routing_rule.routing_rule_id,
      state: routing_rule_state_dto(routing_rule.enabled?),
      section_title: "Routing Rule",
      description: "Durable spacecraft use of a transport for a purpose and direction.",
      details: [
        %{label: "Spacecraft", value: spacecraft_name(spacecraft, routing_rule.spacecraft_id)},
        %{label: "Purpose", value: routing_rule.purpose_label},
        %{label: "Direction", value: human_atom(routing_rule.direction)},
        %{label: "Transport", value: transport_name(transport, routing_rule.transport_id)},
        %{label: "Transport Version", value: "v#{routing_rule.transport_version}"},
        %{label: "Role", value: human_atom(routing_rule.role)}
      ],
      runtime_artifacts_title: "Internal Runtime Artifacts",
      runtime_artifacts: [
        %{
          label: "Assignment artifact",
          value: routing_rule.materialized_link_assignment_id || "Not materialized"
        },
        %{
          label: "Path artifacts",
          value:
            routing_rule.metadata
            |> Map.get("materialized_path_template_ids", [])
            |> Enum.join(", ")
        }
      ]
    }
  end

  defp routing_rule_state_dto(true), do: %{label: "Enabled", tone: "ready"}
  defp routing_rule_state_dto(false), do: %{label: "Disabled", tone: "info"}

  defp event_dto(event) do
    %{
      event_type: human_atom(event.event_type),
      occurred_at: Calendar.strftime(event.occurred_at, "%Y-%m-%d %H:%M:%S UTC")
    }
  end

  defp fetch_spacecraft(organization_id, mission_id, routing_rule) do
    case Cadence.SpacecraftStore.fetch_spacecraft(
           organization_id,
           mission_id,
           routing_rule.spacecraft_id
         ) do
      {:ok, spacecraft} -> spacecraft
      {:error, _reason} -> nil
    end
  end

  defp fetch_transport(organization_id, mission_id, routing_rule) do
    case TransportStore.fetch_transport_version(
           organization_id,
           mission_id,
           routing_rule.transport_id,
           routing_rule.transport_version
         ) do
      {:ok, transport} -> transport
      {:error, _reason} -> nil
    end
  end

  defp spacecraft_name(nil, spacecraft_id), do: spacecraft_id
  defp spacecraft_name(spacecraft, _spacecraft_id), do: spacecraft.display_name

  defp transport_name(nil, transport_id), do: transport_id
  defp transport_name(transport, _transport_id), do: transport.display_name

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()
  end
end
