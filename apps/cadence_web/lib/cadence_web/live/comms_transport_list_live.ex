defmodule CadenceWeb.CommsTransportListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.TransportKinds.TCPSocket

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    transports = Cadence.list_transports(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Transports")
     |> assign(:nav_item, :comms_transports)
     |> assign(:transport_count, length(transports))
     |> assign(:transports_empty?, transports == [])
     |> stream(:transports, transports, dom_id: &"transport-#{&1.transport_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-transports-page" class="space-y-6">
      <div class="flex items-end justify-between gap-4 border-b border-primary/20 pb-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms"}
            class="hud-label text-base-content/50 hover:text-primary"
          >
            &larr; Comms
          </.link>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            Transports
            <span class="ml-3 font-mono text-base text-base-content/40">
              {@transport_count} configured
            </span>
          </h1>
          <p class="mt-1 max-w-2xl text-sm text-base-content/60">
            Durable byte-moving capabilities Cadence can use for inbound, outbound, or bidirectional spacecraft traffic.
          </p>
        </div>
        <.link
          id="new-transport-link"
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports/new"}
          class="btn btn-primary btn-sm gap-1 hover-glow-cyan transition-glow"
        >
          <.icon name="hero-plus" class="h-4 w-4" /> New Transport
        </.link>
      </div>

      <%= if @transports_empty? do %>
        <div class="card bg-base-200 hud-corners border border-base-300">
          <div class="card-body p-8 text-center">
            <p class="hud-label mb-3 text-base-content/60">No transports</p>
            <p class="text-sm text-base-content/60 max-w-md mx-auto">
              Create a transport to describe an external capability for moving bytes.
            </p>
            <div class="mt-5">
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports/new"}
                class="btn btn-primary btn-sm hover-glow-cyan transition-glow"
              >
                Create the first transport
              </.link>
            </div>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200 hud-corners border border-base-300">
          <table id="transports-table" class="table">
            <thead>
              <tr>
                <th class="hud-label">Name</th>
                <th class="hud-label">Kind</th>
                <th class="hud-label">Capability</th>
                <th class="hud-label">Endpoint</th>
                <th class="hud-label">Version</th>
              </tr>
            </thead>
            <tbody id="transports" phx-update="stream">
              <tr
                :for={{id, transport} <- @streams.transports}
                id={id}
                class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
              >
                <td class="font-medium">
                  <.link
                    navigate={
                      ~p"/missions/#{@current_mission.mission_id}/comms/transports/#{transport.transport_id}"
                    }
                    class="text-primary hover:underline"
                  >
                    {transport.display_name}
                  </.link>
                </td>
                <td class="font-mono text-sm uppercase text-primary/80">
                  {human_atom(transport.transport_kind)}
                </td>
                <td class="font-mono text-sm uppercase text-base-content/70">
                  {human_atom(transport.direction_capability)}
                </td>
                <td class="font-mono text-sm text-base-content/70">
                  {transport_summary(transport).endpoint}
                </td>
                <td class="font-mono text-sm text-base-content/70">v{transport.version}</td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp transport_summary(%{transport_kind: :tcp_socket, configuration: configuration}) do
    TCPSocket.display_summary(configuration)
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()
  end
end
