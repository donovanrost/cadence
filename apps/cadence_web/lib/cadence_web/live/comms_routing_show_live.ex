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
        {:ok,
         socket
         |> assign(:page_title, routing_rule.display_name)
         |> assign(:nav_item, :comms_routing)
         |> assign(:routing_rule, routing_rule)
         |> assign(
           :spacecraft,
           fetch_spacecraft(scope.organization_id, mission.mission_id, routing_rule)
         )
         |> assign(
           :transport,
           fetch_transport(scope.organization_id, mission.mission_id, routing_rule)
         )
         |> assign(
           :events,
           RoutingRuleStore.list_routing_rule_events(
             scope.organization_id,
             mission.mission_id,
             routing_rule.routing_rule_id
           )
         )}

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
    <div id="comms-routing-show-page" class="space-y-6">
      <.page_header
        title={@routing_rule.display_name}
        subtitle={@routing_rule.routing_rule_id}
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Routing", ~p"/missions/#{@current_mission.mission_id}/comms/routing"},
          {@routing_rule.display_name, nil}
        ]}
      >
        <:actions>
          <.status_badge
            status={if @routing_rule.enabled?, do: :ready, else: :info}
            label={if @routing_rule.enabled?, do: "Enabled", else: "Disabled"}
          />
        </:actions>
      </.page_header>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <.rule_card routing_rule={@routing_rule} spacecraft={@spacecraft} transport={@transport} />
        <.events_card events={@events} />
      </div>
    </div>
    """
  end

  attr :routing_rule, :map, required: true
  attr :spacecraft, :any, required: true
  attr :transport, :any, required: true

  defp rule_card(assigns) do
    ~H"""
    <.card title="Routing Rule">
      <p class="text-sm text-base-content/70">
        Durable spacecraft use of a transport for a purpose and direction.
      </p>

      <div class="mt-6 space-y-1">
        <.detail_row
          label="Spacecraft"
          value={spacecraft_name(@spacecraft, @routing_rule.spacecraft_id)}
        />
        <.detail_row label="Purpose" value={@routing_rule.purpose_label} />
        <.detail_row label="Direction" value={human_atom(@routing_rule.direction)} />
        <.detail_row label="Transport" value={transport_name(@transport, @routing_rule.transport_id)} />
        <.detail_row label="Transport Version" value={"v#{@routing_rule.transport_version}"} />
        <.detail_row label="Role" value={human_atom(@routing_rule.role)} />
      </div>

      <details class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">
        <summary class="cursor-pointer hud-label hover:text-primary">
          Internal Runtime Artifacts
        </summary>
        <div class="mt-3 space-y-1">
          <.detail_row
            label="Assignment artifact"
            value={@routing_rule.materialized_link_assignment_id || "Not materialized"}
          />
          <.detail_row
            label="Path artifacts"
            value={
              Enum.join(Map.get(@routing_rule.metadata, "materialized_path_template_ids", []), ", ")
            }
          />
        </div>
      </details>
    </.card>
    """
  end

  attr :events, :list, required: true

  defp events_card(assigns) do
    ~H"""
    <.card title="Events">
      <div id="routing-rule-events" class="space-y-2">
        <div :for={event <- @events} class="rounded-[2px] border border-base-300 bg-base-100/40 p-3">
          <p class="font-mono text-xs text-base-content/70">{human_atom(event.event_type)}</p>
          <p class="mt-1 text-xs text-base-content/60">
            {Calendar.strftime(event.occurred_at, "%Y-%m-%d %H:%M:%S UTC")}
          </p>
        </div>
      </div>
    </.card>
    """
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
