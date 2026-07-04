defmodule CadenceWeb.CommsRoutingListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    routing_rules = Cadence.list_routing_rules(scope.organization_id, mission.mission_id)
    spacecraft_by_id = spacecraft_lookup(scope.organization_id, mission.mission_id)
    transport_by_id = transport_lookup(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Routing")
     |> assign(:nav_item, :comms_routing)
     |> assign(:routing_rule_count, length(routing_rules))
     |> assign(:routing_rules_empty?, routing_rules == [])
     |> assign(:spacecraft_by_id, spacecraft_by_id)
     |> assign(:transport_by_id, transport_by_id)
     |> stream(:routing_rules, routing_rules, dom_id: &"routing-rule-#{&1.routing_rule_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
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
        <.routing_rules_table
          rows={@streams.routing_rules}
          current_mission={@current_mission}
          spacecraft_by_id={@spacecraft_by_id}
          transport_by_id={@transport_by_id}
        />
      <% end %>
    </div>
    """
  end

  attr :rows, :any, required: true
  attr :current_mission, :map, required: true
  attr :spacecraft_by_id, :map, required: true
  attr :transport_by_id, :map, required: true

  defp routing_rules_table(assigns) do
    ~H"""
    <.card padding={:none}>
      <.table id="routing-rules-table" body_id="routing-rules" rows={@rows}>
        <:col :let={rule} label="Rule" class="font-medium">
          <.link
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/routing/#{rule.routing_rule_id}"
            }
            class="text-primary hover:underline"
          >
            {rule.display_name}
          </.link>
        </:col>
        <:col :let={rule} label="Spacecraft">
          {spacecraft_name(@spacecraft_by_id, rule.spacecraft_id)}
        </:col>
        <:col :let={rule} label="Purpose">{rule.purpose_label}</:col>
        <:col :let={rule} label="Direction" mono class="uppercase text-primary/80">
          {human_atom(rule.direction)}
        </:col>
        <:col :let={rule} label="Transport">
          {transport_name(@transport_by_id, rule.transport_id)}
        </:col>
        <:col :let={rule} label="Role" mono class="uppercase text-base-content/70">
          {human_atom(rule.role)}
        </:col>
      </.table>
    </.card>
    """
  end

  defp spacecraft_lookup(organization_id, mission_id) do
    organization_id
    |> Cadence.list_spacecraft(mission_id)
    |> Map.new(&{&1.spacecraft_id, &1})
  end

  defp transport_lookup(organization_id, mission_id) do
    organization_id
    |> Cadence.list_transports(mission_id)
    |> Map.new(&{&1.transport_id, &1})
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
