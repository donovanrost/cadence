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
      <.page_header
        title="Transports"
        subtitle="Durable byte-moving capabilities Cadence can use for inbound, outbound, or bidirectional spacecraft traffic."
        back_label="Comms"
        back_navigate={~p"/missions/#{@current_mission.mission_id}/comms"}
      >
        <:title_suffix>{@transport_count} configured</:title_suffix>
        <:actions>
          <.button
            id="new-transport-link"
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports/new"}
            class="gap-1"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> New Transport
          </.button>
        </:actions>
      </.page_header>

      <%= if @transports_empty? do %>
        <.empty_state
          title="No transports"
          description="Create a transport to describe an external capability for moving bytes."
          action_label="Create the first transport"
          action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports/new"}
        />
      <% else %>
        <.card padding={:none}>
          <.table id="transports-table" body_id="transports" rows={@streams.transports}>
            <:col :let={transport} label="Name" class="font-medium">
              <.link
                navigate={
                  ~p"/missions/#{@current_mission.mission_id}/comms/transports/#{transport.transport_id}"
                }
                class="text-primary hover:underline"
              >
                {transport.display_name}
              </.link>
            </:col>
            <:col :let={transport} label="Kind" mono class="uppercase text-primary/80">
              {human_atom(transport.transport_kind)}
            </:col>
            <:col :let={transport} label="Capability" mono class="uppercase text-base-content/70">
              {human_atom(transport.direction_capability)}
            </:col>
            <:col :let={transport} label="Endpoint" mono class="text-base-content/70">
              {transport_summary(transport).endpoint}
            </:col>
            <:col :let={transport} label="Version" mono class="text-base-content/70">
              v{transport.version}
            </:col>
          </.table>
        </.card>
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
