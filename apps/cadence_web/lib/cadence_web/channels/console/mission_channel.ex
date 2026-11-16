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
  alias CadenceWeb.Console.{ConfigJSON, ConfigLive, SchedulingRunner}
  alias CadenceWeb.Console.ContactChanges
  alias CadenceWeb.Console.FleetPush
  alias CadenceWeb.Console.LimitTransitions

  @flush_ms 500

  @read_update_resources %{
    commanding_changed: "commanding",
    alarms_changed: "alarms",
    contacts_changed: "contacts",
    contact_plans_changed: "contact_plans",
    stations_changed: "stations",
    pass_results_changed: "pass_results",
    attention_changed: "attention",
    spacecraft_configuration_changed: "spacecraft",
    dashboards_changed: "dashboards",
    settings_changed: "settings",
    configuration_changed: "configuration",
    activations_changed: "activations"
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
    (["alarms"] ++ Map.values(@read_update_resources) ++ Map.values(@runtime_resources))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @impl true
  def join("mission:" <> mission_id, _payload, socket) do
    case Access.authorize_mission(socket.assigns.console_credentials, mission_id) do
      {:ok, scope, mission} ->
        :ok = subscribe(scope.organization_id, mission.mission_id)

        {:ok, %{mission_id: mission.mission_id, resources: resources()},
         socket
         |> assign(
           scope: scope,
           organization_id: scope.organization_id,
           mission_id: mission.mission_id,
           pending: MapSet.new(),
           flush_timer: nil
         )
         |> ConfigLive.join()
         |> FleetPush.join()}

      {:error, reason} ->
        {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  @impl true
  def handle_info({event, organization_id, mission_id}, socket)
      when is_map_key(@read_update_resources, event) do
    if {organization_id, mission_id} ==
         {socket.assigns.organization_id, socket.assigns.mission_id} do
      socket = mark(socket, Map.fetch!(@read_update_resources, event))

      # Pass rows carry their attention item (U32), so an attention change is a contacts change; and
      # a booking that settles (canceled, pass ended) can close a pass_release item without an
      # attention event of its own (domain 548b8dd9).
      socket =
        case event do
          :attention_changed -> mark(socket, "contacts")
          :contacts_changed -> mark(socket, "attention")
          _other -> socket
        end

      socket =
        if event == :configuration_changed,
          do: ConfigLive.follow_current_set(socket),
          else: socket

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:scheduling_progress, progress}, socket) do
    push(socket, "scheduling_progress", ConfigJSON.encode(progress))
    {:noreply, socket |> mark("contacts") |> mark("contact_plans")}
  end

  def handle_info({:change_set_progress, set_id, step}, socket) do
    push(socket, "change_set_progress", ConfigLive.progress_payload(set_id, step))
    {:noreply, socket}
  end

  def handle_info({:config_runtime, runtime}, socket) do
    push(socket, "config_runtime", ConfigLive.runtime_payload(runtime))
    {:noreply, socket}
  end

  def handle_info({:console_contacts_changed, mission_id}, socket) do
    if mission_id == socket.assigns.mission_id,
      do: {:noreply, mark(socket, "contacts")},
      else: {:noreply, socket}
  end

  def handle_info({:console_limit_transition, mission_id, _spacecraft_id}, socket) do
    if mission_id == socket.assigns.mission_id,
      do: {:noreply, mark(socket, "alarms")},
      else: {:noreply, socket}
  end

  def handle_info({:dashboard_runtime_invalidated, %{boundary: boundary}}, socket) do
    resource = Map.get(@runtime_resources, boundary, to_string(boundary))
    {:noreply, mark(socket, resource)}
  end

  def handle_info(message, socket)
      when message in [:fleet_snapshot, :fleet_refresh, :fleet_tick],
      do: {:noreply, FleetPush.handle(message, socket)}

  def handle_info(:flush, socket) do
    resources = socket.assigns.pending |> MapSet.to_list() |> Enum.sort()
    if resources != [], do: push(socket, "invalidate", %{resources: resources})
    {:noreply, assign(socket, pending: MapSet.new(), flush_timer: nil)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # Opt-in fleet push (api-ops). Contract: realtime.md, "fleet".
  @impl true
  def handle_in("fleet:subscribe", _payload, socket),
    do: {:reply, :ok, FleetPush.subscribe(socket)}

  def handle_in("fleet:unsubscribe", _payload, socket),
    do: {:reply, :ok, FleetPush.unsubscribe(socket)}

  defp mark(socket, resource) do
    socket =
      socket
      |> assign(:pending, MapSet.put(socket.assigns.pending, resource))
      |> FleetPush.note(resource)

    case socket.assigns.flush_timer do
      nil -> assign(socket, :flush_timer, Process.send_after(self(), :flush, @flush_ms))
      _scheduled -> socket
    end
  end

  defp subscribe(organization_id, mission_id) do
    Enum.each(Map.keys(@read_update_resources), fn event ->
      :ok = ScopedReadUpdates.subscribe(event, organization_id, mission_id)
    end)

    :ok = LimitTransitions.subscribe(mission_id)
    :ok = SchedulingRunner.subscribe(mission_id)
    :ok = ContactChanges.subscribe(mission_id)
    RuntimeInvalidation.subscribe(%{organization_id: organization_id, mission_id: mission_id})
  end
end
