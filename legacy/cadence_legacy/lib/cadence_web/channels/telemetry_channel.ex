defmodule CadenceWeb.TelemetryChannel do
  @moduledoc """
  Channel for real-time telemetry streaming to browser clients.

  Clients join with a mission ID and a list of telemetry subscriptions.
  Updates are pushed whenever subscribed telemetry values change.

  ## Topic Format

      "telemetry:<mission_id>"

  ## Join Payload

      %{
        "subscriptions" => [
          %{"target" => "SAT-1", "packet" => "HEALTH", "item" => "CPU_TEMP"},
          %{"target" => "SAT-1", "packet" => "HEALTH", "item" => "BATTERY_V"}
        ]
      }

  ## Incoming Messages

  - `subscribe` - Add new telemetry subscriptions
  - `unsubscribe` - Remove telemetry subscriptions
  - `get_current` - Request current values for subscribed items

  ## Outgoing Messages

  - `telemetry_update` - Batch of telemetry updates
  - `current_values` - Response to get_current request
  """

  use CadenceWeb, :channel

  alias Cadence.Runtime.Telemetry.CurrentValueTable

  require Logger

  @doc """
  Join the telemetry channel for a specific mission.
  """
  @impl true
  def join("telemetry:" <> mission_id, payload, socket) do
    # TODO: Validate user has access to this mission
    # For now, allow all authenticated users

    subscriptions = parse_subscriptions(payload["subscriptions"] || [])

    # Subscribe to telemetry updates for this mission
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:telemetry")

    socket =
      socket
      |> assign(:mission_id, mission_id)
      |> assign(:subscriptions, subscriptions)

    # Send current values for subscribed items
    send(self(), :send_current_values)

    {:ok, socket}
  end

  @doc """
  Handle incoming subscription requests.
  """
  @impl true
  def handle_in("subscribe", %{"items" => items}, socket) do
    new_subs = parse_subscriptions(items)
    current_subs = socket.assigns.subscriptions

    merged = MapSet.union(current_subs, new_subs)

    # Send current values for newly subscribed items
    send_values_for_items(socket.assigns.mission_id, new_subs, socket)

    {:reply, {:ok, %{count: MapSet.size(merged)}}, assign(socket, :subscriptions, merged)}
  end

  @impl true
  def handle_in("unsubscribe", %{"items" => items}, socket) do
    remove_subs = parse_subscriptions(items)
    current_subs = socket.assigns.subscriptions

    remaining = MapSet.difference(current_subs, remove_subs)

    {:reply, {:ok, %{count: MapSet.size(remaining)}}, assign(socket, :subscriptions, remaining)}
  end

  @impl true
  def handle_in("get_current", _payload, socket) do
    mission_id = socket.assigns.mission_id
    subscriptions = socket.assigns.subscriptions

    values = get_current_values(mission_id, subscriptions)

    {:reply, {:ok, %{values: values}}, socket}
  end

  @doc """
  Handle telemetry updates from PubSub.
  Filters to only subscribed items and pushes to the client.
  """
  @impl true
  def handle_info({:telemetry_update, target_id, packet_name, item_name, telemetry_value}, socket) do
    subscriptions = socket.assigns.subscriptions
    key = {target_id, packet_name, item_name}

    if MapSet.member?(subscriptions, key) do
      push(socket, "telemetry_update", %{
        items: [format_telemetry_item(key, telemetry_value)],
        timestamp: System.system_time(:millisecond)
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:telemetry_packet_update, target_id, packet_name, items}, socket) do
    subscriptions = socket.assigns.subscriptions

    # Filter items to only those subscribed
    filtered_items =
      items
      |> Enum.filter(fn {item_name, _value} ->
        MapSet.member?(subscriptions, {target_id, packet_name, item_name})
      end)
      |> Enum.map(fn {item_name, telemetry_value} ->
        format_telemetry_item({target_id, packet_name, item_name}, telemetry_value)
      end)

    if filtered_items != [] do
      push(socket, "telemetry_update", %{
        items: filtered_items,
        timestamp: System.system_time(:millisecond)
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:send_current_values, socket) do
    mission_id = socket.assigns.mission_id
    subscriptions = socket.assigns.subscriptions

    if MapSet.size(subscriptions) > 0 do
      values = get_current_values(mission_id, subscriptions)

      push(socket, "current_values", %{
        values: values,
        timestamp: System.system_time(:millisecond)
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(_message, socket) do
    # Ignore other messages
    {:noreply, socket}
  end

  # Private functions

  defp parse_subscriptions(items) when is_list(items) do
    items
    |> Enum.map(&parse_subscription/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp parse_subscription(%{"target" => t, "packet" => p, "item" => i})
       when is_binary(t) and is_binary(p) and is_binary(i) do
    {t, p, qualify_item_name(p, i)}
  end

  defp parse_subscription(_), do: nil

  defp get_current_values(mission_id, subscriptions) do
    subscriptions
    |> Enum.map(fn {target_id, packet_name, item_name} = key ->
      case CurrentValueTable.get(mission_id, target_id, packet_name, item_name) do
        {:ok, telemetry_value} ->
          format_telemetry_item(key, telemetry_value)

        {:error, :not_found} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp send_values_for_items(mission_id, items, socket) do
    values = get_current_values(mission_id, items)

    if values != [] do
      push(socket, "current_values", %{
        values: values,
        timestamp: System.system_time(:millisecond)
      })
    end
  end

  defp format_telemetry_item({target_id, packet_name, item_name}, telemetry_value) do
    display_item = display_item_name(packet_name, item_name)

    %{
      key: "#{target_id}:#{packet_name}:#{display_item}",
      target: target_id,
      packet: packet_name,
      item: display_item,
      value: telemetry_value.value,
      limits_state: to_string(telemetry_value.limits_state),
      received_time: DateTime.to_unix(telemetry_value.received_time, :millisecond)
    }
  end

  defp qualify_item_name(packet_name, item_name) do
    if String.contains?(item_name, ".") do
      item_name
    else
      "#{packet_name}.#{item_name}"
    end
  end

  defp display_item_name(packet_name, item_name) do
    prefix = packet_name <> "."

    if String.starts_with?(item_name, prefix) do
      String.replace_prefix(item_name, prefix, "")
    else
      item_name
    end
  end
end
