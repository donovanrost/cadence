defmodule Cadence.Simulator.PacketEncoder do
  @moduledoc """
  Encodes telemetry values into binary packets using packet definitions.

  The PacketEncoder reads packet definitions from YAML files (same format as
  the telemetry database) and uses them to:

  1. Validate that item names exist in the definitions
  2. Apply reverse conversions (CONVERTED → RAW)
  3. Pack values into binary according to bit offsets and sizes
  4. Add CCSDS headers and sync patterns as needed

  ## Usage

      {:ok, encoder} = PacketEncoder.load("path/to/definitions.yaml")

      values = %{
        "HEALTH.cpu_temp" => 25.5,
        "HEALTH.battery_voltage" => 14.5
      }

      {:ok, packets} = PacketEncoder.encode(encoder, "SIM-1", values)
      # Returns list of {packet_name, binary} tuples

  ## CCSDS Encoding

  When encoding CCSDS packets, the encoder:
  - Creates a 6-byte primary header with APID and sequence count
  - Creates an 8-byte secondary header with timestamp and target hash
  - Packs user data according to item definitions
  """

  require Logger

  import Bitwise

  defstruct [
    :packets,
    :items_by_qualified_name,
    :conversions,
    :sequence_counts
  ]

  # Note: Sync pattern removed - TM frames provide framing via frame structure
  # @ccsds_sync <<0x1A, 0xCF, 0xFC, 0x1D>>

  @type t :: %__MODULE__{
          packets: %{String.t() => packet_def()},
          items_by_qualified_name: %{String.t() => item_def()},
          conversions: %{String.t() => conversion_def()},
          sequence_counts: %{non_neg_integer() => non_neg_integer()}
        }

  @type packet_def :: %{
          name: String.t(),
          apid: non_neg_integer() | nil,
          is_big_endian: boolean(),
          items: [item_def()]
        }

  @type item_def :: %{
          name: String.t(),
          packet_name: String.t(),
          bit_offset: non_neg_integer(),
          bit_size: non_neg_integer(),
          data_type: String.t(),
          endianness: String.t(),
          conversion: conversion_def() | nil
        }

  @type conversion_def :: %{
          type: String.t(),
          coefficients: [number()] | nil,
          states: %{String.t() => any()} | nil
        }

  @doc """
  Loads packet definitions from a YAML file.
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, parsed} <- YamlElixir.read_from_string(content) do
      build_encoder(parsed)
    else
      {:error, reason} -> {:error, {:load_error, path, reason}}
    end
  end

  @doc """
  Loads packet definitions from a YAML string.
  """
  @spec load_string(String.t()) :: {:ok, t()} | {:error, term()}
  def load_string(yaml_content) do
    with {:ok, parsed} <- YamlElixir.read_from_string(yaml_content) do
      build_encoder(parsed)
    end
  end

  @doc """
  Encodes telemetry values into binary packets.

  Takes a map of qualified item names to values and returns a list of
  encoded packets. Values are grouped by packet name and encoded together.
  """
  @spec encode(t(), String.t(), %{String.t() => any()}) ::
          {:ok, [{String.t(), binary()}], t()} | {:error, term()}
  def encode(encoder, target_id, values) do
    # Group values by packet name
    values_by_packet =
      values
      |> Enum.group_by(fn {qualified_name, _value} ->
        case String.split(qualified_name, ".", parts: 2) do
          [packet_name, _item_name] -> packet_name
          _ -> nil
        end
      end)
      |> Map.delete(nil)

    # Encode each packet
    {packets, encoder} =
      Enum.reduce(values_by_packet, {[], encoder}, fn {packet_name, items}, {acc, enc} ->
        case encode_packet(enc, packet_name, target_id, items) do
          {:ok, binary, updated_enc} ->
            {[{packet_name, binary} | acc], updated_enc}

          {:error, reason} ->
            Logger.warning("Failed to encode packet #{packet_name}: #{inspect(reason)}")
            {acc, enc}
        end
      end)

    {:ok, Enum.reverse(packets), encoder}
  end

  @doc """
  Returns the list of known packet names.
  """
  @spec packet_names(t()) :: [String.t()]
  def packet_names(encoder) do
    Map.keys(encoder.packets)
  end

  @doc """
  Returns the list of known qualified item names.
  """
  @spec item_names(t()) :: [String.t()]
  def item_names(encoder) do
    Map.keys(encoder.items_by_qualified_name)
  end

  @doc """
  Returns the list of APIDs from packet definitions.
  """
  @spec apids(t()) :: [non_neg_integer()]
  def apids(encoder) do
    encoder.packets
    |> Map.values()
    |> Enum.map(& &1.apid)
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

  @doc """
  Encodes telemetry values with external sequence number allocation.

  Unlike `encode/3`, this function does not maintain internal sequence counts.
  Instead, the caller provides a sequence number allocator function that is
  called for each packet's APID.

  This is designed for parallel encoding where sequence numbers must be
  allocated atomically from a shared source.

  ## Parameters

  - `encoder` - The encoder struct
  - `target_id` - Target identifier for the packet
  - `values` - Map of qualified item names to values
  - `sequence_fn` - Function that takes an APID and returns the next sequence number

  ## Example

      allocator = SequenceAllocator.new([100, 101])

      {:ok, packets} = PacketEncoder.encode_with_sequence(
        encoder,
        "SIM-1",
        %{"HEALTH.cpu_temp" => 25.5},
        fn apid -> SequenceAllocator.next(allocator, apid) end
      )
  """
  @spec encode_with_sequence(t(), String.t(), %{String.t() => any()}, (non_neg_integer() ->
                                                                         non_neg_integer())) ::
          {:ok, [{String.t(), binary()}]} | {:error, term()}
  def encode_with_sequence(encoder, target_id, values, sequence_fn)
      when is_function(sequence_fn, 1) do
    # Group values by packet name
    values_by_packet =
      values
      |> Enum.group_by(fn {qualified_name, _value} ->
        case String.split(qualified_name, ".", parts: 2) do
          [packet_name, _item_name] -> packet_name
          _ -> nil
        end
      end)
      |> Map.delete(nil)

    # Encode each packet
    packets =
      Enum.reduce(values_by_packet, [], fn {packet_name, items}, acc ->
        case encode_packet_with_sequence(encoder, packet_name, target_id, items, sequence_fn) do
          {:ok, binary} ->
            [{packet_name, binary} | acc]

          {:error, reason} ->
            Logger.warning("Failed to encode packet #{packet_name}: #{inspect(reason)}")
            acc
        end
      end)

    {:ok, Enum.reverse(packets)}
  end

  # Encode a single packet with external sequence number
  defp encode_packet_with_sequence(encoder, packet_name, target_id, items, sequence_fn) do
    case Map.get(encoder.packets, packet_name) do
      nil ->
        {:error, {:unknown_packet, packet_name}}

      packet_def ->
        # Convert items list to map of item_name => value
        item_values =
          items
          |> Enum.map(fn {qualified_name, value} ->
            [_packet, item_name] = String.split(qualified_name, ".", parts: 2)
            {item_name, value}
          end)
          |> Map.new()

        # Get sequence from external allocator
        apid = packet_def.apid || 0
        seq = sequence_fn.(apid)

        # Encode to binary with provided sequence
        binary = encode_packet_binary_with_seq(encoder, packet_def, target_id, item_values, seq)

        {:ok, binary}
    end
  end

  # Encode packet binary with explicit sequence number
  defp encode_packet_binary_with_seq(_encoder, packet_def, target_id, item_values, sequence) do
    # Calculate packet size from item definitions
    max_bit =
      packet_def.items
      |> Enum.map(fn item -> item.bit_offset + item.bit_size end)
      |> Enum.max(fn -> 0 end)

    # Round up to byte boundary
    payload_size = div(max_bit + 7, 8)

    # Start with zeroed payload
    payload = :binary.copy(<<0>>, payload_size)

    # Pack each item into the payload
    payload =
      Enum.reduce(packet_def.items, payload, fn item_def, acc ->
        case Map.get(item_values, item_def.name) do
          nil ->
            acc

          value ->
            # Apply reverse conversion if needed
            raw_value = reverse_convert(value, item_def.conversion)
            pack_value(acc, item_def, raw_value)
        end
      end)

    # Build CCSDS packet with provided sequence
    apid = packet_def.apid || 0
    build_ccsds_packet(apid, sequence, target_id, payload)
  end

  # Build encoder from parsed YAML
  defp build_encoder(parsed) do
    packets = parsed["packets"] || []

    {packet_map, items_map, conversions_map} =
      Enum.reduce(packets, {%{}, %{}, %{}}, fn packet_data, {pkts, items, convs} ->
        packet_name = packet_data["name"]

        packet_def = %{
          name: packet_name,
          apid: packet_data["apid"],
          is_big_endian: packet_data["big_endian"] != false,
          items: []
        }

        # Process items
        {item_defs, new_convs} =
          (packet_data["items"] || [])
          |> Enum.map(fn item_data ->
            item_name = item_data["name"]
            qualified_name = "#{packet_name}.#{item_name}"

            conversion = parse_conversion(item_data["conversion"])

            item_def = %{
              name: item_name,
              packet_name: packet_name,
              qualified_name: qualified_name,
              bit_offset: item_data["bit_offset"],
              bit_size: item_data["bit_size"],
              data_type: item_data["data_type"],
              endianness: item_data["endianness"] || "big",
              conversion: conversion
            }

            {item_def, {qualified_name, conversion}}
          end)
          |> Enum.unzip()

        packet_def = %{packet_def | items: item_defs}

        new_items = Enum.into(item_defs, items, fn item -> {item.qualified_name, item} end)

        new_conv_map =
          new_convs
          |> Enum.filter(fn {_name, conv} -> conv != nil end)
          |> Enum.into(convs)

        {Map.put(pkts, packet_name, packet_def), new_items, Map.merge(convs, new_conv_map)}
      end)

    encoder = %__MODULE__{
      packets: packet_map,
      items_by_qualified_name: items_map,
      conversions: conversions_map,
      sequence_counts: %{}
    }

    {:ok, encoder}
  end

  defp parse_conversion(nil), do: nil

  defp parse_conversion(%{"type" => "polynomial", "coefficients" => coefficients}) do
    %{type: "polynomial", coefficients: coefficients}
  end

  defp parse_conversion(%{"type" => "state_table", "states" => states}) do
    # Convert keys to strings
    string_states = Enum.into(states, %{}, fn {k, v} -> {to_string(k), v} end)
    %{type: "state_table", states: string_states}
  end

  defp parse_conversion(data) do
    Logger.warning("Unknown conversion format: #{inspect(data)}")
    nil
  end

  # Encode a single packet
  defp encode_packet(encoder, packet_name, target_id, items) do
    case Map.get(encoder.packets, packet_name) do
      nil ->
        {:error, {:unknown_packet, packet_name}}

      packet_def ->
        # Convert items list to map of item_name => value
        item_values =
          items
          |> Enum.map(fn {qualified_name, value} ->
            [_packet, item_name] = String.split(qualified_name, ".", parts: 2)
            {item_name, value}
          end)
          |> Map.new()

        # Encode to binary
        binary = encode_packet_binary(encoder, packet_def, target_id, item_values)

        # Update sequence count
        apid = packet_def.apid || 0
        seq = Map.get(encoder.sequence_counts, apid, 0)
        new_seq = rem(seq + 1, 16_384)
        encoder = %{encoder | sequence_counts: Map.put(encoder.sequence_counts, apid, new_seq)}

        {:ok, binary, encoder}
    end
  end

  defp encode_packet_binary(encoder, packet_def, target_id, item_values) do
    # Calculate packet size from item definitions
    max_bit =
      packet_def.items
      |> Enum.map(fn item -> item.bit_offset + item.bit_size end)
      |> Enum.max(fn -> 0 end)

    # Round up to byte boundary
    payload_size = div(max_bit + 7, 8)

    # Start with zeroed payload
    payload = :binary.copy(<<0>>, payload_size)

    # Pack each item into the payload
    payload =
      Enum.reduce(packet_def.items, payload, fn item_def, acc ->
        case Map.get(item_values, item_def.name) do
          nil ->
            acc

          value ->
            # Apply reverse conversion if needed
            raw_value = reverse_convert(value, item_def.conversion)
            pack_value(acc, item_def, raw_value)
        end
      end)

    # Build CCSDS packet
    apid = packet_def.apid || 0
    seq = Map.get(encoder.sequence_counts, apid, 0)

    build_ccsds_packet(apid, seq, target_id, payload)
  end

  # Apply reverse conversion (CONVERTED → RAW)
  defp reverse_convert(value, nil), do: value

  defp reverse_convert(value, %{type: "polynomial", coefficients: coefficients}) do
    # For polynomial y = c0 + c1*x + c2*x^2 + ...
    # We need to solve for x given y
    # For linear (2 coefficients): x = (y - c0) / c1
    case coefficients do
      [c0, c1] when c1 != 0 ->
        (value - c0) / c1

      [c0] ->
        # Constant conversion, just return value - c0
        value - c0

      _ ->
        # For higher-order polynomials, we'd need numerical methods
        # For now, just return the value as-is
        Logger.warning("Cannot reverse non-linear polynomial conversion")
        value
    end
  end

  defp reverse_convert(value, %{type: "state_table", states: states}) do
    # Find the raw value that maps to this state
    case Enum.find(states, fn {_k, v} -> v == value end) do
      {raw_str, _state} ->
        case Integer.parse(raw_str) do
          {raw_int, ""} -> raw_int
          _ -> 0
        end

      nil ->
        Logger.warning("State '#{value}' not found in state table, using 0")
        0
    end
  end

  # Pack a value into the binary payload at the specified bit offset
  defp pack_value(payload, item_def, value) do
    bit_offset = item_def.bit_offset
    bit_size = item_def.bit_size
    data_type = item_def.data_type
    endianness = item_def.endianness

    # Convert value to binary representation
    value_binary = value_to_binary(value, data_type, bit_size, endianness)

    # Insert into payload at bit offset
    insert_bits(payload, value_binary, bit_offset, bit_size)
  end

  defp value_to_binary(value, "float", 32, endianness) do
    case endianness do
      "big" -> <<value::float-big-32>>
      "little" -> <<value::float-little-32>>
      _ -> <<value::float-big-32>>
    end
  end

  defp value_to_binary(value, "float", 64, endianness) do
    case endianness do
      "big" -> <<value::float-big-64>>
      "little" -> <<value::float-little-64>>
      _ -> <<value::float-big-64>>
    end
  end

  defp value_to_binary(value, "uint", bit_size, endianness) do
    int_value = trunc(value)
    byte_size = div(bit_size + 7, 8)

    case endianness do
      "big" -> <<int_value::unsigned-big-size(byte_size * 8)>>
      "little" -> <<int_value::unsigned-little-size(byte_size * 8)>>
      _ -> <<int_value::unsigned-big-size(byte_size * 8)>>
    end
  end

  defp value_to_binary(value, "int", bit_size, endianness) do
    int_value = trunc(value)
    byte_size = div(bit_size + 7, 8)

    case endianness do
      "big" -> <<int_value::signed-big-size(byte_size * 8)>>
      "little" -> <<int_value::signed-little-size(byte_size * 8)>>
      _ -> <<int_value::signed-big-size(byte_size * 8)>>
    end
  end

  defp value_to_binary(value, "boolean", _bit_size, _endianness) do
    if value, do: <<1>>, else: <<0>>
  end

  defp value_to_binary(value, "string", bit_size, _endianness) do
    str = to_string(value)
    byte_size = div(bit_size, 8)

    String.pad_trailing(str, byte_size, <<0>>)
    |> String.slice(0, byte_size)
  end

  defp value_to_binary(value, "binary", bit_size, _endianness) when is_binary(value) do
    byte_size = div(bit_size, 8)
    # Pad or truncate to exact size
    case byte_size(value) do
      ^byte_size -> value
      n when n < byte_size -> value <> :binary.copy(<<0>>, byte_size - n)
      _ -> binary_part(value, 0, byte_size)
    end
  end

  defp value_to_binary(_value, "binary", bit_size, _endianness) do
    # If not already binary, generate zeros
    byte_size = div(bit_size, 8)
    :binary.copy(<<0>>, byte_size)
  end

  defp value_to_binary(value, _unknown_type, bit_size, endianness) do
    # Default to uint
    value_to_binary(value, "uint", bit_size, endianness)
  end

  # Insert bits into payload (simplified byte-aligned version)
  defp insert_bits(payload, value_binary, bit_offset, bit_size) do
    # For simplicity, we handle byte-aligned offsets
    # A more complete implementation would handle arbitrary bit offsets
    byte_offset = div(bit_offset, 8)
    byte_size = div(bit_size + 7, 8)

    prefix = binary_part(payload, 0, byte_offset)
    suffix_start = byte_offset + byte_size
    suffix_len = byte_size(payload) - suffix_start
    suffix = if suffix_len > 0, do: binary_part(payload, suffix_start, suffix_len), else: <<>>

    prefix <> binary_part(value_binary, 0, min(byte_size, byte_size(value_binary))) <> suffix
  end

  # Build a CCSDS packet (no sync pattern - TM frames provide framing)
  defp build_ccsds_packet(apid, sequence, target_id, payload) do
    # Secondary header (8 bytes): timestamp + target hash
    timestamp = System.system_time(:second)
    target_hash = :erlang.phash2(target_id, 65_536)
    secondary_header = <<timestamp::48, target_hash::16>>

    user_data = secondary_header <> payload

    # Primary header (6 bytes)
    version = 0
    # telemetry
    type = 0
    sec_hdr_flag = 1
    packet_id = version <<< 13 ||| type <<< 12 ||| sec_hdr_flag <<< 11 ||| apid

    # unsegmented
    sequence_flags = 3
    seq_control = sequence_flags <<< 14 ||| sequence

    data_length = byte_size(user_data) - 1

    primary_header = <<packet_id::16, seq_control::16, data_length::16>>

    # No sync pattern - when used with TM frames, framing is provided by the frame structure
    # The sync pattern was causing APID misalignment (0x1ACF parsed as APID 719)
    primary_header <> user_data
  end
end
