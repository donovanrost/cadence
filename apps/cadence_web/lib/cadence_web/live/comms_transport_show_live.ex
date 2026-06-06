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
      <div class="border-b border-primary/20 pb-4">
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports"}
          class="hud-label text-base-content/50 hover:text-primary"
        >
          &larr; Transports
        </.link>
        <div class="mt-2 flex items-start justify-between gap-4">
          <div>
            <div class="flex items-baseline gap-3">
              <h1 class="text-2xl font-bold text-base-content tracking-tight">
                {@transport.display_name}
              </h1>
              <span class="mc-value-small text-primary/80">v{@transport.version}</span>
            </div>
            <p class="mt-1 font-mono text-xs text-base-content/40">
              {@transport.transport_id}
            </p>
          </div>
        </div>
      </div>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <section class="card bg-base-200 border border-base-300 hud-corners">
          <div class="card-body p-6">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="hud-label mb-2">Byte-Moving Capability</p>
                <h2 class="font-mono text-lg font-semibold text-primary">
                  {@summary.endpoint}
                </h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Durable transport setup. Runtime Links and Contacts are realized later under execution context.
                </p>
              </div>
              <span class="badge badge-outline">{human_atom(@transport.transport_kind)}</span>
            </div>

            <div class="mt-6 space-y-1">
              <.detail label="Direction Capability" value={human_text(@summary.direction_capability)} />
              <.detail label="Mode" value={human_text(@summary.mode)} />
              <.detail label="Framing" value={human_text(@summary.framing)} />
              <.detail label="TLS" value={if @summary.tls_enabled?, do: "Enabled", else: "Disabled"} />
              <.detail
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
          </div>
        </section>

        <aside class="card bg-base-200 border border-base-300">
          <div class="card-body p-5">
            <p class="hud-label mb-3">Version History</p>
            <div id="transport-versions" class="space-y-1">
              <div :for={version <- @versions} class="hud-data-row">
                <span class="hud-data-label">v{version.version}</span>
                <span class="hud-data-value text-xs">
                  {version.lifecycle_state |> Atom.to_string() |> String.upcase()}
                </span>
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
