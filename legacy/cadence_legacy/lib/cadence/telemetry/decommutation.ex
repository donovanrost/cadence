defmodule Cadence.Telemetry.Decommutation do
  @moduledoc """
  Decommutation engine for extracting telemetry items from packets.

  Supports binary CCSDS payloads extracted from spacecraft data.

  For binary packets, extracts fields based on bit_offset and bit_length
  from the packet definition. Handles endianness and data type conversions.

  For CCSDS packets, extracts fields from the binary payload.
  """

  require Logger
  alias Cadence.Telemetry.BinaryExtractor

  @doc """
  Extracts a single field from a binary packet.

  This is a convenience wrapper around BinaryExtractor.extract/5 for testing
  and simple use cases.

  ## Parameters

  - `packet` - The binary packet data
  - `item_def` - Map containing:
    - `:name` - Field name (optional, for error messages)
    - `:bit_offset` - Bit offset from start of packet
    - `:bit_length` - Size in bits
    - `:data_type` - Data type string ("uint", "int", "float", "string", "boolean")
    - `:endianness` - Byte order (optional, defaults to "big_endian")

  ## Returns

  - `{:ok, value}` - Extracted value
  - `{:error, reason}` - Extraction failed
  """
  @spec extract_field(binary(), map()) :: {:ok, term()} | {:error, term()}
  def extract_field(packet, item_def) do
    bit_offset = item_def.bit_offset
    bit_length = item_def[:bit_length] || item_def[:bit_size]
    data_type = normalize_data_type(item_def.data_type)
    endianness = normalize_endianness(item_def[:endianness])

    case data_type do
      :boolean ->
        # Special handling for boolean - extract as uint then convert
        case BinaryExtractor.extract(packet, bit_offset, bit_length, :uint, endianness) do
          {:ok, value} -> {:ok, value != 0}
          error -> error
        end

      :float when bit_length not in [32, 64] ->
        {:error, {:unsupported_float_size, bit_length}}

      _ ->
        BinaryExtractor.extract(packet, bit_offset, bit_length, data_type, endianness)
    end
  end

  defp normalize_data_type("uint"), do: :uint
  defp normalize_data_type("int"), do: :int
  defp normalize_data_type("float"), do: :float
  defp normalize_data_type("string"), do: :string
  defp normalize_data_type("boolean"), do: :boolean
  defp normalize_data_type("block"), do: :block
  defp normalize_data_type(atom) when is_atom(atom), do: atom

  defp normalize_endianness(nil), do: :big_endian
  defp normalize_endianness("big_endian"), do: :big_endian
  defp normalize_endianness("little_endian"), do: :little_endian
  defp normalize_endianness(atom) when is_atom(atom), do: atom

  @doc """
  Decommutates a packet and returns extracted telemetry items.

  Returns `{:ok, items}` where items is a map of item_name => raw_value.

  Accepts format as:
  - `:binary` or `:ccsds` - Binary CCSDS packet from spacecraft

  ## Examples

      # Binary packet (from spacecraft)
      packet_data = <<0x00, 0x01, 0x02, 0x03, ...>>
      {:ok, items} = Decommutation.decommutate(packet_data, packet_def, :ccsds)
  """
  @spec decommutate(binary(), map(), :binary | :ccsds) ::
          {:ok, map()} | {:error, term()}
  def decommutate(packet_data, packet_def, format \\ :ccsds)

  # Map :ccsds format to :binary
  def decommutate(packet_data, packet_def, :ccsds) do
    decommutate(packet_data, packet_def, :binary)
  end

  def decommutate(packet_data, packet_def, :binary) when is_binary(packet_data) do
    # Get field specs - either pre-compiled or build from items
    field_specs = get_field_specs(packet_def)

    case BinaryExtractor.extract_fields(packet_data, field_specs) do
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

  # Get field specs from packet_def - either pre-compiled field_specs or convert from items
  defp get_field_specs(%{field_specs: field_specs}) when is_list(field_specs) do
    field_specs
  end

  defp get_field_specs(%{items: items}) when is_list(items) do
    # Convert items to field_specs format expected by BinaryExtractor
    Enum.map(items, fn item ->
      %{
        name: item.name,
        bit_offset: item.bit_offset,
        bit_size: item[:bit_length] || item[:bit_size],
        data_type: normalize_data_type(item.data_type),
        endianness: normalize_endianness(item[:endianness])
      }
    end)
  end
end
