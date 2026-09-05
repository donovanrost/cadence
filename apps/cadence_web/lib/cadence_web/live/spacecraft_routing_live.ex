defmodule CadenceWeb.SpacecraftRoutingLive do
  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    routing_rules =
      RoutingRuleStore.list_routing_rules_for_spacecraft(
        scope.organization_id,
        mission.mission_id,
        spacecraft.spacecraft_id
      )

    transport_by_id =
      scope.organization_id
      |> TransportStore.list_transports(mission.mission_id)
      |> Map.new(&{&1.transport_id, &1})

    page = spacecraft_routing_dto(mission, spacecraft, routing_rules, transport_by_id)

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Routing")
     |> assign(:nav_item, :spacecraft)
     |> assign(:spacecraft_routing, page)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-routing-page"
        v-component="FederatedFullPageSurface"
        page={@spacecraft_routing}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp spacecraft_routing_dto(mission, spacecraft, routing_rules, transport_by_id) do
    %{
      title: "Comms Routing",
      subtitle:
        "Durable routing rules that describe how this spacecraft uses mission transports.",
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Spacecraft", href: ~p"/missions/#{mission.mission_id}/spacecraft"},
        %{
          label: spacecraft.display_name,
          href: ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
        },
        %{label: "Routing", href: nil}
      ],
      new_rule: %{
        id: "new-spacecraft-routing-rule-link",
        label: "New Routing Rule",
        href:
          ~p"/missions/#{mission.mission_id}/comms/routing/new?spacecraft_id=#{spacecraft.spacecraft_id}"
      },
      empty_state: %{
        title: "No routing rules",
        description:
          "Create a routing rule to declare how this spacecraft should use a transport."
      },
      rules_id: "spacecraft-routing-rules",
      rows:
        Enum.map(
          routing_rules,
          &routing_rule_dto(&1, mission.mission_id, transport_by_id)
        )
    }
  end

  defp routing_rule_dto(rule, mission_id, transport_by_id) do
    %{
      id: "spacecraft-routing-rule-#{rule.routing_rule_id}",
      purpose_label: rule.purpose_label,
      display_name: rule.display_name,
      direction: human_atom(rule.direction),
      transport_name: transport_name(transport_by_id, rule.transport_id),
      role: human_atom(rule.role),
      state: if(rule.enabled?, do: "ENABLED", else: "DISABLED"),
      href: ~p"/missions/#{mission_id}/comms/routing/#{rule.routing_rule_id}"
    }
  end

  defp transport_name(transport_by_id, transport_id) do
    case Map.fetch(transport_by_id, transport_id) do
      {:ok, transport} -> transport.display_name
      :error -> transport_id
    end
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()
  end
end
