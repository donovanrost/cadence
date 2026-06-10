defmodule CadenceWeb.SpacecraftRoutingLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    routing_rules =
      Cadence.list_routing_rules_for_spacecraft(
        scope.organization_id,
        mission.mission_id,
        spacecraft.spacecraft_id
      )

    transport_by_id =
      scope.organization_id
      |> Cadence.list_transports(mission.mission_id)
      |> Map.new(&{&1.transport_id, &1})

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Routing")
     |> assign(:nav_item, :spacecraft)
     |> assign(:routing_rules_empty?, routing_rules == [])
     |> assign(:transport_by_id, transport_by_id)
     |> stream(:routing_rules, routing_rules,
       dom_id: &"spacecraft-routing-rule-#{&1.routing_rule_id}"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-routing-page" class="space-y-6">
      <.page_header
        title="Comms Routing"
        subtitle="Durable routing rules that describe how this spacecraft uses mission transports."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name,
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
          {"Routing", nil}
        ]}
      >
        <:actions>
          <.button
            id="new-spacecraft-routing-rule-link"
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/routing/new?spacecraft_id=#{@current_spacecraft.spacecraft_id}"
            }
            class="gap-1"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> New Routing Rule
          </.button>
        </:actions>
      </.page_header>

      <%= if @routing_rules_empty? do %>
        <.empty_state
          title="No routing rules"
          description="Create a routing rule to declare how this spacecraft should use a transport."
        />
      <% else %>
        <%!-- bespoke layout: stream of link-cards (the whole card is the navigation target) --%>
        <div id="spacecraft-routing-rules" phx-update="stream" class="grid gap-3 md:grid-cols-2">
          <.link
            :for={{id, rule} <- @streams.routing_rules}
            id={id}
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing/#{rule.routing_rule_id}"}
            class="card bg-base-200 border border-base-300 hover:border-primary/50 hover-glow-cyan transition-glow"
          >
            <div class="card-body p-5">
              <p class="hud-label">{rule.purpose_label}</p>
              <h2 class="mt-2 font-semibold">{rule.display_name}</h2>
              <p class="mt-2 text-sm text-base-content/60">
                {human_atom(rule.direction)} via {transport_name(@transport_by_id, rule.transport_id)}
              </p>
              <p class="mt-2 font-mono text-xs text-base-content/50">
                {human_atom(rule.role)} · {if rule.enabled?, do: "ENABLED", else: "DISABLED"}
              </p>
            </div>
          </.link>
        </div>
      <% end %>
    </div>
    """
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
