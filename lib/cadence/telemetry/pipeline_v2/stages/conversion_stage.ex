defmodule Cadence.Telemetry.PipelineV2.Stages.ConversionStage do
  @moduledoc """
  Pipeline stage that applies conversions to raw telemetry values.

  Converts raw ADC counts, bit fields, etc. into engineering units
  using polynomial, state table, or other conversion definitions.

  ## Input

  PipelineEvent with:
  - `raw_items` - Map of item_name => raw_value
  - `packet_def` - Packet definition with item conversions

  ## Output

  PipelineEvent enriched with:
  - `converted_items` - Map of item_name => converted_value
  - `qualified_items` - Map of "PACKET.item" => converted_value

  ## Parallelization

  For large packets (> 50 items), conversions are applied in parallel
  using Task.async_stream to maximize throughput.
  """

  use Cadence.Telemetry.PipelineV2.Stages.StageBehaviour

  alias Cadence.Telemetry.Conversions

  @parallel_threshold 50

  @impl true
  def stage_name, do: :convert

  @impl true
  def process(event, _state) do
    %{raw_items: raw_items, packet_def: packet_def} = event
    packet_items = packet_def.items
    packet_name = packet_def.name

    # Choose parallel or sequential based on item count
    converted_items =
      if map_size(raw_items) > @parallel_threshold do
        apply_conversions_parallel(raw_items, packet_items)
      else
        apply_conversions(raw_items, packet_items)
      end

    # Qualify item names with packet name (PACKET.item format)
    qualified_items =
      converted_items
      |> Enum.map(fn {name, value} -> {"#{packet_name}.#{name}", value} end)
      |> Map.new()

    {:ok,
     %{
       event
       | converted_items: converted_items,
         qualified_items: qualified_items
     }}
  end

  # Sequential conversion for small packets
  defp apply_conversions(raw_items, packet_items) do
    raw_items
    |> Enum.map(fn {item_name, raw_value} ->
      {item_name, convert_item(item_name, raw_value, packet_items)}
    end)
    |> Map.new()
  end

  # Parallel conversion for large packets
  defp apply_conversions_parallel(raw_items, packet_items) do
    raw_items
    |> Task.async_stream(
      fn {item_name, raw_value} ->
        {item_name, convert_item(item_name, raw_value, packet_items)}
      end,
      max_concurrency: System.schedulers_online(),
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Map.new()
  end

  # Convert a single item value
  defp convert_item(item_name, raw_value, packet_items) do
    item_def = Enum.find(packet_items, fn item -> to_string(item.name) == item_name end)

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
end
