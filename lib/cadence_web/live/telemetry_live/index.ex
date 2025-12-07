defmodule CadenceWeb.TelemetryLive.Index do
  @moduledoc """
  Real-time telemetry display for a mission.

  Subscribes to telemetry updates via PubSub and displays current values
  from the CVT with sub-100ms latency.
  """

  use CadenceWeb, :live_view

  alias Cadence.{Missions, Targets}
  alias Cadence.Telemetry.CurrentValueTable

  @impl true
  def mount(%{"mission_id" => mission_id}, _session, socket) do
    mission = Missions.get_mission!(mission_id)

    if connected?(socket) do
      # Poll CVT at ~120 Hz (8ms interval) instead of PubSub subscription
      # This decouples UI updates from telemetry ingestion rate
      :timer.send_interval(8, self(), :poll_cvt)
    end

    # Check if mission is running using Registry lookup
    mission_running? = match?({:ok, _pid}, Missions.MissionSupervisor.get_mission_pid(mission_id))

    # Load targets from database
    targets = Targets.list_targets(mission)

    # Load telemetry data if mission is running
    telemetry_data =
      if mission_running? do
        load_telemetry_data(mission_id, targets)
      else
        %{}
      end

    socket =
      socket
      |> assign(:mission, mission)
      |> assign(:mission_running?, mission_running?)
      |> assign(:targets, targets)
      |> assign(:telemetry_data, telemetry_data)
      |> assign(:last_update, DateTime.utc_now())
      |> assign(:poll_count, 0)

    {:ok, socket}
  end

  @impl true
  def handle_info(:poll_cvt, socket) do
    # Poll CVT for latest telemetry data
    telemetry_data =
      if socket.assigns.mission_running? do
        load_telemetry_data(socket.assigns.mission.id, socket.assigns.targets)
      else
        socket.assigns.telemetry_data
      end

    socket =
      socket
      |> assign(:telemetry_data, telemetry_data)
      |> assign(:last_update, DateTime.utc_now())
      |> assign(:poll_count, socket.assigns.poll_count + 1)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <div class="mb-6">
        <h1 class="text-3xl font-bold">Telemetry - {@mission.name}</h1>
        <p class="text-gray-600 mt-2">{@mission.description}</p>
      </div>

      <div class="mb-4 flex justify-between items-center">
        <div class="text-sm text-gray-600">
          Last Update: {format_datetime(@last_update)}
        </div>
        <div class="text-sm">
          <%= if @mission_running? do %>
            <span class="inline-flex items-center px-3 py-1 rounded-full bg-green-100 text-green-800">
              <span class="h-2 w-2 bg-green-600 rounded-full mr-2 animate-pulse"></span> LIVE
            </span>
          <% else %>
            <span class="inline-flex items-center px-3 py-1 rounded-full bg-gray-100 text-gray-800">
              <span class="h-2 w-2 bg-gray-600 rounded-full mr-2"></span> OFFLINE
            </span>
          <% end %>
        </div>
      </div>

      <%= if not @mission_running? do %>
        <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6 text-center">
          <p class="text-yellow-800 mb-4">
            Mission runtime is not running. Start the mission to view telemetry.
          </p>
          <p class="text-sm text-yellow-700">
            You can start the mission from the mission details page.
          </p>
        </div>
      <% else %>
        <%= if Enum.empty?(@targets) do %>
          <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6 text-center">
            <p class="text-yellow-800">No targets found for this mission.</p>
          </div>
        <% else %>
          <div class="space-y-6">
            <%= for target <- @targets do %>
              <div class="bg-white shadow rounded-lg overflow-hidden">
                <div class="bg-gray-50 px-6 py-3 border-b">
                  <h2 class="text-xl font-semibold">Target: {target.name} ({target.identifier})</h2>
                </div>

                <div class="grid grid-cols-3 gap-4 p-6">
                  <%= for packet_name <- ["HEALTH", "ATTITUDE", "POWER"] do %>
                    <div>
                      <h3 class="font-semibold text-gray-700 mb-3">{packet_name}</h3>
                      <div class="space-y-2">
                        <%= for {key, value} <- filter_telemetry(@telemetry_data, target.identifier, packet_name) do %>
                          <div class="flex justify-between items-center text-sm">
                            <span class="text-gray-600">{elem(key, 2)}:</span>
                            <span class={[
                              "font-mono font-semibold",
                              limits_color_class(value.limits_state)
                            ]}>
                              {format_value(value.value)}
                            </span>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  ## Private Functions

  defp load_telemetry_data(mission_id, targets) do
    # Load all current telemetry from CVT
    # Targets can be either target structs or target identifiers (strings)
    Enum.reduce(targets, %{}, fn target, acc ->
      # Use identifier (e.g., "SAT-1") not UUID, as that's what CVT uses
      target_identifier = if is_binary(target), do: target, else: target.identifier

      target_telemetry = CurrentValueTable.get_target_telemetry(mission_id, target_identifier)

      Enum.reduce(target_telemetry, acc, fn {key, value}, acc2 ->
        Map.put(acc2, key, value)
      end)
    end)
  end

  defp filter_telemetry(telemetry_data, target_id, packet_name) do
    telemetry_data
    |> Enum.filter(fn {{tid, pname, _item}, _value} ->
      tid == target_id and pname == packet_name
    end)
    |> Enum.sort_by(fn {key, _} -> elem(key, 2) end)
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_value(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp format_value(value) when is_integer(value) do
    Integer.to_string(value)
  end

  defp format_value(value) when is_binary(value) do
    value
  end

  defp format_value(value) do
    inspect(value)
  end

  # Green state - value within all limits
  defp limits_color_class(:green), do: "text-green-600"

  # Yellow states - warning level violation (can be high or low)
  defp limits_color_class(:yellow), do: "text-yellow-600 bg-yellow-100 px-1 rounded"
  defp limits_color_class(:yellow_low), do: "text-yellow-700 bg-yellow-100 px-1 rounded"
  defp limits_color_class(:yellow_high), do: "text-yellow-700 bg-yellow-100 px-1 rounded"

  # Red states - critical level violation (can be high or low)
  defp limits_color_class(:red), do: "text-red-600 bg-red-100 px-1 rounded font-bold"
  defp limits_color_class(:red_low), do: "text-red-700 bg-red-100 px-1 rounded font-bold"
  defp limits_color_class(:red_high), do: "text-red-700 bg-red-100 px-1 rounded font-bold"

  # Blue state - stale data (hasn't been updated within timeout)
  defp limits_color_class(:blue), do: "text-blue-600 bg-blue-100 px-1 rounded"

  # Unknown state - default styling
  defp limits_color_class(_), do: "text-gray-600"
end
