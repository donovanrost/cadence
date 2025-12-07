defmodule Cadence.Telemetry.Decommutation do
  @moduledoc """
  Decommutation engine for extracting telemetry items from packets.

  Supports two formats:
  1. **Binary** - Bit-level extraction from raw spacecraft data
  2. **JSON** - For simulators and testing (what PacketSimulator generates)

  For binary packets, extracts fields based on bit_offset and bit_length
  from the packet definition. Handles endianness and data type conversions.

  For JSON packets, parses the JSON and maps fields to items.
  """

  require Logger
  alias Cadence.Telemetry.BinaryExtractor

  @doc """
  Decommutates a packet and returns extracted telemetry items.

  Returns `{:ok, items}` where items is a map of item_name => raw_value.

  Accepts format as:
  - `:json` or `:simulator` - JSON packet from simulator
  - `:binary` or `:ccsds` - Binary CCSDS packet from spacecraft

  ## Examples

      # JSON packet (from simulator)
      packet_data = ~s({"cpu_temp": 25.5, "battery_voltage": 14.2})
      {:ok, items} = Decommutation.decommutate(packet_data, packet_def, :simulator)

      # Binary packet (from spacecraft)
      packet_data = <<0x00, 0x01, 0x02, 0x03, ...>>
      {:ok, items} = Decommutation.decommutate(packet_data, packet_def, :ccsds)
  """
  @spec decommutate(binary(), map(), :json | :binary | :simulator | :ccsds) ::
          {:ok, map()} | {:error, term()}
  def decommutate(packet_data, packet_def, format \\ :json)

  # Map :simulator format to :json
  def decommutate(packet_data, packet_def, :simulator) do
    decommutate(packet_data, packet_def, :json)
  end

  # Map :ccsds format to :binary
  def decommutate(packet_data, packet_def, :ccsds) do
    decommutate(packet_data, packet_def, :binary)
  end

  def decommutate(packet_data, packet_def, :json) when is_binary(packet_data) do
    case Jason.decode(packet_data) do
      {:ok, json_data} ->
        items =
          packet_def.items
          |> Enum.map(fn item_def ->
            value =
              Map.get(json_data, item_def.name) || Map.get(json_data, to_string(item_def.name))

            {item_def.name, value}
          end)
          |> Enum.into(%{})

        {:ok, items}

      {:error, reason} ->
        Logger.error("Failed to parse JSON packet: #{inspect(reason)}")
        {:error, {:json_parse_error, reason}}
    end
  end

  def decommutate(packet_data, packet_def, :binary) when is_binary(packet_data) do
    # Debug: Log payload size (commented out for performance)
    # Logger.debug("Decommutating #{packet_def.name}: payload size=#{byte_size(packet_data)} bytes, expecting items with max offset=#{max_bit_offset(packet_def.items)}")

    # Use pre-compiled field_specs from packet_def (built once at mission start)
    # Field names are already strings, no conversion needed
    case BinaryExtractor.extract_fields(packet_data, packet_def.field_specs) do
      {:ok, items} ->
        {:ok, items}

      {:error, {field_name, reason}} ->
        Logger.error(
          "Failed to extract field #{field_name} from packet #{packet_def.name}: #{inspect(reason)}"
        )

        {:error, {:extraction_failed, field_name, reason}}
    end
  end

  @doc """
  Validates that a packet definition has all required fields for decommutation.
  """
  @spec validate_packet_definition(map()) :: :ok | {:error, term()}
  def validate_packet_definition(packet_def) do
    required_fields = [:id, :name, :items]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(packet_def, &1))

    if Enum.empty?(missing_fields) do
      # Validate each item definition
      item_errors =
        packet_def.items
        |> Enum.map(&validate_item_definition/1)
        |> Enum.reject(&(&1 == :ok))

      if Enum.empty?(item_errors) do
        :ok
      else
        {:error, {:invalid_items, item_errors}}
      end
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end

  defp validate_item_definition(item_def) do
    required_fields = [:name, :bit_offset, :bit_size, :data_type]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(item_def, &1))

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_item_fields, item_def.name, missing_fields}}
    end
  end
end
