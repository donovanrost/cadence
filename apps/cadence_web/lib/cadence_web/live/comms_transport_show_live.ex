defmodule CadenceWeb.CommsTransportShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.TransportKind

  @impl true
  def mount(%{"transport_id" => transport_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case TransportStore.fetch_transport(
           scope.organization_id,
           mission.mission_id,
           transport_id
         ) do
      {:ok, transport} ->
        versions =
          TransportStore.list_transport_versions(
            scope.organization_id,
            mission.mission_id,
            transport.transport_id
          )

        {:ok,
         socket
         |> stream_configure(:transport_versions,
           dom_id: &"transport-version-#{&1.version}"
         )
         |> assign(:page_title, transport.display_name)
         |> assign(:nav_item, :comms_transports)
         |> assign(:transport, transport)
         |> assign(:summary, transport_summary(transport))
         |> stream(:transport_versions, versions)}

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
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Transports", ~p"/missions/#{@current_mission.mission_id}/comms/transports"},
          {@transport.display_name, nil}
        ]}
      >
        <:title_suffix>
          <span id="transport-origin-badge" class="font-mono text-xs uppercase text-primary/80">
            {origin_label(@transport.origin)}
          </span>
          <span class="ml-2 font-mono text-xs text-base-content/60">v{@transport.version}</span>
        </:title_suffix>
      </.page_header>

      <div class="grid gap-3 md:grid-cols-4">
        <.stat_tile id="transport-origin-summary" label="Origin" value={origin_label(@transport.origin)} />
        <.stat_tile id="transport-provider-summary" label="Provider" value={provider_label(@transport)} />
        <.stat_tile id="transport-operator-summary" label="Delivery" value={operator_summary(@transport)} />
        <.stat_tile id="transport-readiness-summary" label="Readiness" value={readiness_label(@transport)} />
      </div>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <.capability_card transport={@transport} summary={@summary} />
        <.version_history_card versions={@streams.transport_versions} />
      </div>
    </div>
    """
  end

  attr :transport, :map, required: true
  attr :summary, :map, required: true

  defp capability_card(assigns) do
    ~H"""
    <.card>
      <.section_header
        eyebrow="Byte-Moving Capability"
        title={@summary.endpoint}
        title_mono
        description="Durable transport setup. Runtime Links and Contacts are realized later under execution context."
      >
        <:actions>
          <span class="bg-base-300 px-2 py-1 font-mono text-[0.65rem] uppercase tracking-wide text-base-content/70">
            {human_atom(@transport.transport_kind)}
          </span>
        </:actions>
      </.section_header>

      <div class="mt-6 space-y-1">
        <.detail_row label="Origin" value={origin_label(@transport.origin)} />
        <.detail_row :if={@transport.origin == :provider_managed} label="Mission Provider">
          <.link
            navigate={
              ~p"/missions/#{@transport.mission_id}/comms/providers/#{@transport.mission_provider_id}"
            }
            class="text-primary hover:underline"
          >
            {provider_label(@transport)} · v{@transport.mission_provider_version}
          </.link>
        </.detail_row>
        <.detail_row
          :if={@transport.origin == :provider_managed}
          label="Service Profile"
          value={profile_ref_label(@transport.service_profile_ref)}
          mono
        />
        <.detail_row
          :if={@transport.origin == :provider_managed}
          label="Delivery Profile"
          value={profile_ref_label(@transport.delivery_profile_ref)}
          mono
        />
        <.detail_row label="Direction Capability" value={human_text(@summary.direction_capability)} />
        <.detail_row label="Mode" value={human_text(@summary.mode)} />
        <.detail_row label="Framing" value={human_text(@summary.framing)} />
        <.detail_row label="TLS" value={if @summary.tls_enabled?, do: "Enabled", else: "Disabled"} />
        <.detail_row label="Readiness" value={readiness_label(@transport)} />
      </div>

      <details
        id="transport-admin-diagnostics"
        class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm"
      >
        <summary class="cursor-pointer hud-label hover:text-primary">
          Administrator Diagnostics
        </summary>
        <pre id="transport-admin-diagnostics-json" class="mt-3 max-h-96 overflow-auto font-mono text-xs text-base-content/70">{diagnostics_json(@transport)}</pre>
      </details>
    </.card>
    """
  end

  attr :versions, :any, required: true

  defp version_history_card(assigns) do
    ~H"""
    <.card title="Version History">
      <div id="transport-versions" phx-update="stream" class="space-y-1">
        <div :for={{dom_id, version} <- @versions} id={dom_id}>
          <.detail_row label={"v#{version.version}"}>
            <span class="text-xs">
              {version.lifecycle_state |> Atom.to_string() |> String.upcase()}
            </span>
          </.detail_row>
        </div>
      </div>
    </.card>
    """
  end

  defp transport_summary(transport) do
    {:ok, entry} = TransportKind.fetch(transport.transport_kind)
    entry.module.display_summary(transport.configuration)
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> human_text()
  end

  defp human_text(value) when is_binary(value) do
    value |> String.replace("_", " ") |> String.upcase()
  end

  defp origin_label(:provider_managed), do: "Provider managed"
  defp origin_label(:direct), do: "Direct"

  defp provider_label(%{origin: :provider_managed} = transport) do
    get_in(transport.provider_configuration_snapshot, ["provider", "display_name"]) ||
      transport.mission_provider_id
  end

  defp provider_label(_transport), do: "Cadence"

  defp operator_summary(%{origin: :provider_managed} = transport) do
    get_in(transport.provider_configuration_snapshot, ["delivery_profile", "operator_summary"]) ||
      "Provider-managed delivery"
  end

  defp operator_summary(%{transport_kind: kind}), do: "Direct #{human_atom(kind)}"

  defp readiness_label(%{origin: :provider_managed} = transport) do
    if get_in(transport.provider_configuration_snapshot, ["delivery_profile", "state"]) == "ready",
      do: "Ready",
      else: "Profile drift"
  end

  defp readiness_label(_transport), do: "Configured"

  defp profile_ref_label(%{"id" => id, "version" => version}), do: "#{id} · v#{version}"
  defp profile_ref_label(_reference), do: "Not selected"

  defp diagnostics_json(transport) do
    Jason.encode!(
      %{
        "origin" => Atom.to_string(transport.origin),
        "configuration" => transport.configuration,
        "provider_configuration_snapshot" => transport.provider_configuration_snapshot,
        "compatibility_provider_profile_id" => transport.materialized_provider_profile_id
      },
      pretty: true
    )
  end
end
