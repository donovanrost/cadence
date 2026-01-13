defmodule Cadence.Telemetry.Convert do
  @moduledoc """
  Pure entry point for telemetry conversion.
  """

  require Logger

  alias Cadence.Telemetry.Conversions

  @parallel_threshold 500

  def run(%{raw_items: raw_items} = _event, _state) when map_size(raw_items) == 0 do
    {:skip, :no_items}
  end

  def run(%{raw_items: raw_items, packet_def: packet_def, packet: packet} = event, _state) do
    items_by_name = packet_def.items_by_name
    packet_name = packet_def.name

    converted_items =
      if map_size(raw_items) > @parallel_threshold do
        apply_conversions_parallel(raw_items, items_by_name)
      else
        apply_conversions(raw_items, items_by_name)
      end

    qualified_items =
      converted_items
      |> Enum.map(fn {name, value} -> {qualify_item_name(packet_name, name), value} end)
      |> Map.new()

    qualified_items = inject_timestamp_items(qualified_items, packet_name, packet)

    {:ok,
     %{
       event
       | converted_items: converted_items,
         qualified_items: qualified_items
     }}
  end

  def run(_event, _state), do: {:error, :invalid_event}

  defp apply_conversions(raw_items, items_by_name) do
    raw_items
    |> Enum.map(fn {item_name, raw_value} ->
      {item_name, convert_item(item_name, raw_value, items_by_name)}
    end)
    |> Map.new()
  end

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
        raw_value
    end
  end

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

  defp qualify_item_name(packet_name, item_name) do
    prefix = packet_name <> "."

    if String.starts_with?(item_name, prefix) do
      item_name
    else
      prefix <> item_name
    end
  end

  defp datetime_to_unix_float(%DateTime{} = dt) do
    DateTime.to_unix(dt, :microsecond) / 1_000_000
  end

  defp datetime_to_unix_float(_), do: 0.0
end
