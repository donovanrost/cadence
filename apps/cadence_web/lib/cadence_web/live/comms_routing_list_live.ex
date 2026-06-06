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
      <div class="flex items-end justify-between gap-4 border-b border-primary/20 pb-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms"}
            class="hud-label text-base-content/50 hover:text-primary"
          >
            &larr; Comms
          </.link>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            Routing
            <span class="ml-3 font-mono text-base text-base-content/40">
              {@routing_rule_count} rules
            </span>
          </h1>
          <p class="mt-1 max-w-2xl text-sm text-base-content/60">
            Durable rules describing how spacecraft use transports for a purpose and direction.
          </p>
        </div>
        <.link
          id="new-routing-rule-link"
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing/new"}
          class="btn btn-primary btn-sm gap-1 hover-glow-cyan transition-glow"
        >
          <.icon name="hero-plus" class="h-4 w-4" /> New Routing Rule
        </.link>
      </div>

      <%= if @routing_rules_empty? do %>
        <div class="card bg-base-200 hud-corners border border-base-300">
          <div class="card-body p-8 text-center">
            <p class="hud-label mb-3 text-base-content/60">No routing rules</p>
            <p class="text-sm text-base-content/60 max-w-md mx-auto">
              Create a routing rule to declare how a spacecraft should use an available transport.
            </p>
            <div class="mt-5">
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing/new"}
                class="btn btn-primary btn-sm hover-glow-cyan transition-glow"
              >
                Create the first routing rule
              </.link>
            </div>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200 hud-corners border border-base-300">
          <table id="routing-rules-table" class="table">
            <thead>
              <tr>
                <th class="hud-label">Rule</th>
                <th class="hud-label">Spacecraft</th>
                <th class="hud-label">Purpose</th>
                <th class="hud-label">Direction</th>
                <th class="hud-label">Transport</th>
                <th class="hud-label">Role</th>
              </tr>
            </thead>
            <tbody id="routing-rules" phx-update="stream">
              <tr :for={{id, rule} <- @streams.routing_rules} id={id}>
                <td class="font-medium">
                  <.link
                    navigate={
                      ~p"/missions/#{@current_mission.mission_id}/comms/routing/#{rule.routing_rule_id}"
                    }
                    class="text-primary hover:underline"
                  >
                    {rule.display_name}
                  </.link>
                </td>
                <td>{spacecraft_name(@spacecraft_by_id, rule.spacecraft_id)}</td>
                <td>{rule.purpose_label}</td>
                <td class="font-mono text-sm uppercase text-primary/80">{human_atom(rule.direction)}</td>
                <td>{transport_name(@transport_by_id, rule.transport_id)}</td>
                <td class="font-mono text-sm uppercase text-base-content/70">{human_atom(rule.role)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
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
