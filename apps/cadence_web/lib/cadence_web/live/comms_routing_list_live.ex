defmodule CadenceWeb.CommsRoutingListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    routing_rules =
      RoutingRuleStore.list_routing_rules(scope.organization_id, mission.mission_id)

    spacecraft_by_id = spacecraft_lookup(scope.organization_id, mission.mission_id)
    transport_by_id = transport_lookup(scope.organization_id, mission.mission_id)

    routing_rule_rows =
      Enum.map(
        routing_rules,
        &routing_rule_row(&1, mission.mission_id, spacecraft_by_id, transport_by_id)
      )

    {:ok,
     socket
     |> assign(:page_title, "Comms Routing")
     |> assign(:nav_item, :comms_routing)
     |> assign(:routing_rule_count, length(routing_rules))
     |> assign(:routing_rules_empty?, routing_rules == [])
     |> assign(:routing_rule_rows, routing_rule_rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="comms-routing-page" class="space-y-6">
        <.page_header
          title="Routing"
          subtitle="Durable rules describing how spacecraft use transports for a purpose and direction."
          breadcrumbs={[
            {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
            {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
            {"Routing", nil}
          ]}
        >
          <:title_suffix>{@routing_rule_count} rules</:title_suffix>
          <:actions>
            <.button
              id="new-routing-rule-link"
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing/new"}
              class="gap-1"
            >
              <.icon name="hero-plus" class="h-4 w-4" /> New Routing Rule
            </.button>
          </:actions>
        </.page_header>

        <%= if @routing_rules_empty? do %>
          <.empty_state
            title="No routing rules"
            description="Create a routing rule to declare how a spacecraft should use an available transport."
            action_label="Create the first routing rule"
            action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing/new"}
          />
        <% else %>
          <.card padding={:none}>
            <.vue
              id="routing-rules-list-component"
              v-component="CommsRoutingList"
              rows={@routing_rule_rows}
              v-ssr={false}
            />
          </.card>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp spacecraft_lookup(organization_id, mission_id) do
    organization_id
    |> Cadence.SpacecraftStore.list_spacecraft(mission_id)
    |> Map.new(&{&1.spacecraft_id, &1})
  end

  defp transport_lookup(organization_id, mission_id) do
    organization_id
    |> TransportStore.list_transports(mission_id)
    |> Map.new(&{&1.transport_id, &1})
  end

  defp routing_rule_row(rule, mission_id, spacecraft_by_id, transport_by_id) do
    %{
      id: "routing-rule-#{rule.routing_rule_id}",
      display_name: rule.display_name,
      spacecraft_name: spacecraft_name(spacecraft_by_id, rule.spacecraft_id),
      purpose_label: rule.purpose_label,
      direction: human_atom(rule.direction),
      transport_name: transport_name(transport_by_id, rule.transport_id),
      role: human_atom(rule.role),
      href: ~p"/missions/#{mission_id}/comms/routing/#{rule.routing_rule_id}"
    }
  end

  defp spacecraft_name(spacecraft_by_id, spacecraft_id) do
    case Map.fetch(spacecraft_by_id, spacecraft_id) do
      {:ok, spacecraft} -> spacecraft.display_name
      :error -> spacecraft_id
    end
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
