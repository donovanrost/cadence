defmodule CadenceWeb.Console.MissionChannel do
  @moduledoc """
  `mission:<mission_id>` — live change notifications for one mission.

  The channel pushes coalesced `invalidate` events naming the resources that
  changed (`commanding`, `telemetry`, `limits`, ...); the SPA refetches the
  affected REST reads. This mirrors the existing dashboard runtime, which reads
  through invalidated caches instead of streaming per-packet updates.

  Contract: `docs/apogee/api/realtime.md`.
  """

  use Phoenix.Channel

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Platform.ScopedReadUpdates
  alias CadenceWeb.Console.Access

  @flush_ms 500

  @read_update_resources %{
    commanding_changed: "commanding",
    spacecraft_configuration_changed: "spacecraft",
    dashboards_changed: "dashboards",
    settings_changed: "settings"
  }

  @runtime_resources %{
    catalog_revision_changed: "catalog",
    limit_definition_changed: "limits",
    data_source_binding_changed: "data_sources",
    source_health_changed: "data_sources",
    source_watermark_changed: "telemetry",
    historical_data_changed: "telemetry",
    telemetry_revision_state_changed: "telemetry",
    events_changed: "events",
    dashboard_version_changed: "dashboards"
  }

  @doc "Resource names the channel can emit in `invalidate` payloads."
  @spec resources() :: [binary()]
  def resources do
    (Map.values(@read_update_resources) ++ Map.values(@runtime_resources))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @impl true
  def join("mission:" <> mission_id, _payload, socket) do
    case Access.authorize_mission(socket.assigns.console_credentials, mission_id) do
      {:ok, scope, mission} ->
        :ok = subscribe(scope.organization_id, mission.mission_id)

        {:ok, %{mission_id: mission.mission_id, resources: resources()},
         assign(socket,
           organization_id: scope.organization_id,
           mission_id: mission.mission_id,
           pending: MapSet.new(),
           flush_timer: nil
         )}

      {:error, reason} ->
        {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  @impl true
  def handle_info({event, organization_id, mission_id}, socket)
      when is_map_key(@read_update_resources, event) do
    if {organization_id, mission_id} ==
         {socket.assigns.organization_id, socket.assigns.mission_id},
       do: {:noreply, mark(socket, Map.fetch!(@read_update_resources, event))},
       else: {:noreply, socket}
  end

  def handle_info({:dashboard_runtime_invalidated, %{boundary: boundary}}, socket) do
    resource = Map.get(@runtime_resources, boundary, to_string(boundary))
    {:noreply, mark(socket, resource)}
  end

  def handle_info(:flush, socket) do
    resources = socket.assigns.pending |> MapSet.to_list() |> Enum.sort()
    if resources != [], do: push(socket, "invalidate", %{resources: resources})
    {:noreply, assign(socket, pending: MapSet.new(), flush_timer: nil)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp mark(socket, resource) do
    socket = assign(socket, :pending, MapSet.put(socket.assigns.pending, resource))

    case socket.assigns.flush_timer do
      nil -> assign(socket, :flush_timer, Process.send_after(self(), :flush, @flush_ms))
      _scheduled -> socket
    end
  end

  defp subscribe(organization_id, mission_id) do
    Enum.each(Map.keys(@read_update_resources), fn event ->
      :ok = ScopedReadUpdates.subscribe(event, organization_id, mission_id)
    end)

    RuntimeInvalidation.subscribe(%{organization_id: organization_id, mission_id: mission_id})
  end
end
