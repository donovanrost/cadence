defmodule CadenceWeb.CommsRoutingShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"routing_rule_id" => routing_rule_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_routing_rule(scope.organization_id, mission.mission_id, routing_rule_id) do
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
           Cadence.list_routing_rule_events(
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
      <div class="border-b border-primary/20 pb-4">
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing"}
          class="hud-label text-base-content/50 hover:text-primary"
        >
          &larr; Routing
        </.link>
        <div class="mt-2 flex items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-base-content tracking-tight">
              {@routing_rule.display_name}
            </h1>
            <p class="mt-1 font-mono text-xs text-base-content/40">
              {@routing_rule.routing_rule_id}
            </p>
          </div>
          <span class="badge badge-outline">{if @routing_rule.enabled?, do: "Enabled", else: "Disabled"}</span>
        </div>
      </div>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <section class="card bg-base-200 border border-base-300 hud-corners">
          <div class="card-body p-6">
            <p class="hud-label mb-2">Routing Rule</p>
            <p class="text-sm text-base-content/60">
              Durable spacecraft use of a transport for a purpose and direction.
            </p>

            <div class="mt-6 space-y-1">
              <.detail label="Spacecraft" value={spacecraft_name(@spacecraft, @routing_rule.spacecraft_id)} />
              <.detail label="Purpose" value={@routing_rule.purpose_label} />
              <.detail label="Direction" value={human_atom(@routing_rule.direction)} />
              <.detail label="Transport" value={transport_name(@transport, @routing_rule.transport_id)} />
              <.detail label="Transport Version" value={"v#{@routing_rule.transport_version}"} />
              <.detail label="Role" value={human_atom(@routing_rule.role)} />
              <.detail
                label="Runtime Identity Policy"
                value={human_atom(@routing_rule.runtime_identity_policy)}
              />
            </div>

            <details class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">
              <summary class="cursor-pointer hud-label hover:text-primary">
                Compatibility Artifacts
              </summary>
              <div class="mt-3 space-y-1">
                <.detail
                  label="Runtime assignment"
                  value={@routing_rule.materialized_link_assignment_id || "Not materialized"}
                />
                <.detail
                  label="Path artifacts"
                  value={Enum.join(Map.get(@routing_rule.metadata, "materialized_path_template_ids", []), ", ")}
                />
              </div>
            </details>
          </div>
        </section>

        <aside class="card bg-base-200 border border-base-300">
          <div class="card-body p-5">
            <p class="hud-label mb-3">Events</p>
            <div id="routing-rule-events" class="space-y-2">
              <div :for={event <- @events} class="rounded border border-base-300 bg-base-100/40 p-3">
                <p class="font-mono text-xs text-primary/80">{human_atom(event.event_type)}</p>
                <p class="mt-1 text-xs text-base-content/50">
                  {Calendar.strftime(event.occurred_at, "%Y-%m-%d %H:%M:%S UTC")}
                </p>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail(assigns) do
    ~H"""
    <div class="hud-data-row">
      <span class="hud-data-label">{@label}</span>
      <span class="hud-data-value">{@value}</span>
    </div>
    """
  end

  defp fetch_spacecraft(organization_id, mission_id, routing_rule) do
    case Cadence.fetch_spacecraft(organization_id, mission_id, routing_rule.spacecraft_id) do
      {:ok, spacecraft} -> spacecraft
      {:error, _reason} -> nil
    end
  end

  defp fetch_transport(organization_id, mission_id, routing_rule) do
    case Cadence.fetch_transport_version(
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
