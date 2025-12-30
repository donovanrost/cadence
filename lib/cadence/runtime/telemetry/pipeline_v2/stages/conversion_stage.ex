defmodule Cadence.Runtime.Telemetry.PipelineV2.Stages.ConversionStage do
  @moduledoc """
  Pipeline stage that applies conversions to raw telemetry values.

  Converts raw ADC counts, bit fields, etc. into engineering units
  using polynomial, state table, or other conversion definitions.

  Also injects automatic timestamp items for OpenC3 compatibility.

  ## Input

  PipelineEvent with:
  - `raw_items` - Map of item_name => raw_value
  - `packet_def` - Packet definition with item conversions
  - `packet` - Original Packet struct with timestamp information

  ## Output

  PipelineEvent enriched with:
  - `converted_items` - Map of item_name => converted_value
  - `qualified_items` - Map of "PACKET.item" => converted_value (includes timestamps)

  ## Automatic Timestamp Items

  The following items are automatically added to every packet:
  - `RECEIVED_TIMESECONDS` - Unix timestamp (float) when packet was received
  - `RECEIVED_TIMEFORMATTED` - ISO8601 string of received time
  - `PACKET_TIMESECONDS` - Unix timestamp (float) of packet generation time
  - `PACKET_TIMEFORMATTED` - ISO8601 string of packet time

  ## Parallelization

  For large packets (> 50 items), conversions are applied in parallel
  using Task.async_stream to maximize throughput.
  """

  use Cadence.Runtime.Telemetry.PipelineV2.Stages.StageBehaviour

  alias Cadence.Telemetry.Conversions

  # Raised threshold: with optimized polynomial eval (~50ns/item),
  # Task.async_stream overhead (~10-50μs) only pays off for very large packets
  @parallel_threshold 500

  @impl true
  def stage_name, do: :convert

  @impl true
  def process(%{raw_items: raw_items} = _event, _state) when map_size(raw_items) == 0 do
    {:skip, :no_items}
  end

  @impl true
  def process(%{raw_items: raw_items, packet_def: packet_def, packet: packet} = event, _state) do
    # Use pre-built O(1) lookup map from PacketIdentifier
    items_by_name = packet_def.items_by_name
    packet_name = packet_def.name

    # Choose parallel or sequential based on item count
    converted_items =
      if map_size(raw_items) > @parallel_threshold do
        apply_conversions_parallel(raw_items, items_by_name)
      else
        apply_conversions(raw_items, items_by_name)
      end

    # Qualify item names with packet name (PACKET.item format)
    qualified_items =
      converted_items
      |> Enum.map(fn {name, value} -> {"#{packet_name}.#{name}", value} end)
      |> Map.new()

    # Add automatic timestamp items
    qualified_items = inject_timestamp_items(qualified_items, packet_name, packet)

    {:ok,
     %{
       event
       | converted_items: converted_items,
         qualified_items: qualified_items
     }}
  end

  def process(_event, _state), do: {:error, :invalid_event}

  # Sequential conversion for small packets
  defp apply_conversions(raw_items, items_by_name) do
    raw_items
    |> Enum.map(fn {item_name, raw_value} ->
      {item_name, convert_item(item_name, raw_value, items_by_name)}
    end)
    |> Map.new()
  end

  # Parallel conversion for large packets
  defp apply_conversions_parallel(raw_items, items_by_name) do
    raw_items
    |> Task.async_stream(
      fn {item_name, raw_value} ->
        {item_name, convert_item(item_name, raw_value, items_by_name)}
      end,
      max_concurrency: System.schedulers_online(),
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Map.new()
  end

  # Convert a single item value using O(1) map lookup
  defp convert_item(item_name, raw_value, items_by_name) do
    item_def = Map.get(items_by_name, item_name)

    case item_def do
      %{conversion: conversion} when not is_nil(conversion) ->
        case Conversions.apply_db_conversion(raw_value, conversion) do
          {:ok, value} ->
            value

          {:error, reason} ->
            Logger.warning(
              "Conversion failed for #{item_name}: #{inspect(reason)}, using raw value"
            )

            raw_value
        end

      _ ->
        # No conversion defined
        raw_value
    end
  end

  # Inject automatic timestamp items (OpenC3 compatibility)
  defp inject_timestamp_items(qualified_items, packet_name, packet) do
    received_time = packet.received_time || DateTime.utc_now()
    packet_time = packet.packet_time || received_time

    timestamp_items = %{
      "#{packet_name}.RECEIVED_TIMESECONDS" => datetime_to_unix_float(received_time),
      "#{packet_name}.RECEIVED_TIMEFORMATTED" => DateTime.to_iso8601(received_time),
      "#{packet_name}.PACKET_TIMESECONDS" => datetime_to_unix_float(packet_time),
      "#{packet_name}.PACKET_TIMEFORMATTED" => DateTime.to_iso8601(packet_time)
    }

    Map.merge(qualified_items, timestamp_items)
  end

  # Convert DateTime to Unix timestamp as float (with microsecond precision)
  defp datetime_to_unix_float(%DateTime{} = dt) do
    DateTime.to_unix(dt, :microsecond) / 1_000_000
  end

  defp datetime_to_unix_float(_), do: 0.0
end
