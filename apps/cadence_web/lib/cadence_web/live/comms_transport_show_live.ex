defmodule CadenceWeb.CommsTransportShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.TransportKinds.TCPSocket

  @impl true
  def mount(%{"transport_id" => transport_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_transport(scope.organization_id, mission.mission_id, transport_id) do
      {:ok, transport} ->
        versions =
          Cadence.list_transport_versions(
            scope.organization_id,
            mission.mission_id,
            transport.transport_id
          )

        {:ok,
         socket
         |> assign(:page_title, transport.display_name)
         |> assign(:nav_item, :comms_transports)
         |> assign(:transport, transport)
         |> assign(:versions, versions)
         |> assign(:summary, transport_summary(transport))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Transport not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/transports")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-transport-show-page" class="space-y-6">
      <.page_header
        title={@transport.display_name}
        subtitle={@transport.transport_id}
        back_label="Transports"
        back_navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports"}
      >
        <:title_suffix>v{@transport.version}</:title_suffix>
      </.page_header>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <.capability_card transport={@transport} summary={@summary} />
        <.version_history_card versions={@versions} />
      </div>
    </div>
    """
  end

  attr :transport, :map, required: true
  attr :summary, :map, required: true

  defp capability_card(assigns) do
    ~H"""
    <.card>
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="hud-label mb-2">Byte-Moving Capability</p>
          <h2 class="font-mono text-lg font-semibold text-primary">
            {@summary.endpoint}
          </h2>
          <p class="mt-1 text-sm text-base-content/70">
            Durable transport setup. Runtime Links and Contacts are realized later under execution context.
          </p>
        </div>
        <span class="badge badge-outline">{human_atom(@transport.transport_kind)}</span>
      </div>

      <div class="mt-6 space-y-1">
        <.detail_row label="Direction Capability" value={human_text(@summary.direction_capability)} />
        <.detail_row label="Mode" value={human_text(@summary.mode)} />
        <.detail_row label="Framing" value={human_text(@summary.framing)} />
        <.detail_row label="TLS" value={if @summary.tls_enabled?, do: "Enabled", else: "Disabled"} />
        <.detail_row
          label="Compatibility Provider"
          value={@transport.materialized_provider_profile_id || "Not materialized"}
        />
      </div>

      <details class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">
        <summary class="cursor-pointer hud-label hover:text-primary">
          Configuration
        </summary>
        <pre class="mt-3 overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(@transport.configuration, pretty: true)}</pre>
      </details>
    </.card>
    """
  end

  attr :versions, :list, required: true

  defp version_history_card(assigns) do
    ~H"""
    <.card title="Version History">
      <div id="transport-versions" class="space-y-1">
        <.detail_row :for={version <- @versions} label={"v#{version.version}"}>
          <span class="text-xs">
            {version.lifecycle_state |> Atom.to_string() |> String.upcase()}
          </span>
        </.detail_row>
      </div>
    </.card>
    """
  end

  defp transport_summary(%{transport_kind: :tcp_socket, configuration: configuration}) do
    TCPSocket.display_summary(configuration)
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> human_text()
  end

  defp human_text(value) when is_binary(value) do
    value |> String.replace("_", " ") |> String.upcase()
  end
end
