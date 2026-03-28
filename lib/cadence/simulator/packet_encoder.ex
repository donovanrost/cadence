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

  alias Cadence.Time, as: CadenceTime

  defstruct [
    :packets,
    :packet_order,
    :items_by_qualified_name,
    :conversions,
    :sequence_counts
  ]

  # Note: Sync pattern removed - TM frames provide framing via frame structure
  # @ccsds_sync <<0x1A, 0xCF, 0xFC, 0x1D>>

  @type t :: %__MODULE__{
          packets: %{String.t() => packet_def()},
          packet_order: [String.t()],
          items_by_qualified_name: %{String.t() => item_def()},
          conversions: %{String.t() => conversion_def()},
          sequence_counts: %{non_neg_integer() => non_neg_integer()}
        }

  @type packet_pack_item :: {binary(), item_def(), binary()}

  @type packet_def :: %{
          name: String.t(),
          apid: non_neg_integer() | nil,
          is_big_endian: boolean(),
          payload_size: non_neg_integer(),
          packet_id: non_neg_integer(),
          data_length: non_neg_integer(),
          packing_strategy: :sequential | :spliced,
          pack_items: [packet_pack_item()],
          tail_gap: binary(),
          items: [item_def()]
        }

  @type item_def :: %{
          name: String.t(),
          packet_name: String.t(),
          qualified_name: String.t(),
          bit_offset: non_neg_integer(),
          byte_offset: non_neg_integer(),
          bit_size: non_neg_integer(),
          byte_size: non_neg_integer(),
          data_type: String.t(),
          endianness: String.t(),
          conversion: conversion_def() | nil
        }

  @type conversion_def :: %{
          type: String.t(),
          coefficients: [number()] | nil,
          states: %{String.t() => any()} | nil,
          reverse_states: %{any() => non_neg_integer()} | nil
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
    target_hash = :erlang.phash2(target_id, 65_536)
    timestamp = CadenceTime.system_time(:second)
    active_packets = active_packets(encoder, values)

    # Encode each packet
    {packets, encoder} =
      reduce_active_packets(encoder, active_packets, {[], encoder}, fn packet_name, {acc, enc} ->
        append_encoded_packet(
          encode_packet(enc, packet_name, target_hash, timestamp, values),
          packet_name,
          acc,
          enc
        )
      end)

    {:ok, Enum.reverse(packets), encoder}
  end

  @doc """
  Returns the list of known packet names.
  """
  @spec packet_names(t()) :: [String.t()]
  def packet_names(encoder) do
    encoder.packet_order
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
    encoder.packet_order
    |> Enum.map(&Map.fetch!(encoder.packets, &1).apid)
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
    target_hash = :erlang.phash2(target_id, 65_536)
    timestamp = CadenceTime.system_time(:second)
    active_packets = active_packets(encoder, values)

    # Encode each packet
    packets =
      reduce_active_packets(encoder, active_packets, [], fn packet_name, acc ->
        append_encoded_packet(
          encode_packet_with_sequence(
            encoder,
            packet_name,
            target_hash,
            timestamp,
            values,
            sequence_fn
          ),
          packet_name,
          acc
        )
      end)

    {:ok, Enum.reverse(packets)}
  end

  # Encode a single packet with external sequence number
  defp encode_packet_with_sequence(
         encoder,
         packet_name,
         target_hash,
         timestamp,
         item_values,
         sequence_fn
       ) do
    case Map.get(encoder.packets, packet_name) do
      nil ->
        {:error, {:unknown_packet, packet_name}}

      packet_def ->
        # Get sequence from external allocator
        apid = packet_def.apid || 0
        seq = sequence_fn.(apid)

        # Encode to binary with provided sequence
        binary =
          encode_packet_binary_with_seq(packet_def, target_hash, timestamp, item_values, seq)

        {:ok, binary}
    end
  end

  # Encode packet binary with explicit sequence number
  defp encode_packet_binary_with_seq(packet_def, target_hash, timestamp, values, sequence) do
    payload = build_payload(packet_def, values)

    # Build CCSDS packet with provided sequence
    build_ccsds_packet(packet_def, sequence, target_hash, timestamp, payload)
  end

  # Build encoder from parsed YAML
  defp build_encoder(parsed) do
    packets = parsed["packets"] || []

    {packet_map, packet_order, items_map, conversions_map} =
      Enum.reduce(packets, {%{}, [], %{}, %{}}, fn packet_data, {pkts, order, items, convs} ->
        packet_name = packet_data["name"]

        packet_def = %{
          name: packet_name,
          apid: packet_data["apid"],
          is_big_endian: packet_data["big_endian"] != false,
          payload_size: 0,
          packet_id: 0,
          data_length: 0,
          packing_strategy: :spliced,
          pack_items: [],
          tail_gap: <<>>,
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
              byte_offset: div(item_data["bit_offset"], 8),
              bit_size: item_data["bit_size"],
              byte_size: div(item_data["bit_size"] + 7, 8),
              data_type: item_data["data_type"],
              endianness: item_data["endianness"] || "big",
              conversion: conversion
            }

            {item_def, {qualified_name, conversion}}
          end)
          |> Enum.unzip()

        payload_size = payload_size(item_defs)

        %{strategy: strategy, pack_items: pack_items, tail_gap: tail_gap} =
          build_packing_layout(item_defs, payload_size)

        apid = packet_def.apid || 0

        packet_def = %{
          packet_def
          | items: item_defs,
            payload_size: payload_size,
            packet_id: build_packet_id(apid),
            data_length: payload_size + 7,
            packing_strategy: strategy,
            pack_items: pack_items,
            tail_gap: tail_gap
        }

        new_items = Enum.into(item_defs, items, fn item -> {item.qualified_name, item} end)

        new_conv_map =
          new_convs
          |> Enum.filter(fn {_name, conv} -> conv != nil end)
          |> Enum.into(convs)

        {
          Map.put(pkts, packet_name, packet_def),
          [packet_name | order],
          new_items,
          Map.merge(convs, new_conv_map)
        }
      end)

    encoder = %__MODULE__{
      packets: packet_map,
      packet_order: Enum.reverse(packet_order),
      items_by_qualified_name: items_map,
      conversions: conversions_map,
      sequence_counts: %{}
    }

    {:ok, encoder}
  end

  defp parse_conversion(nil), do: nil

  defp parse_conversion(%{"type" => "polynomial", "coefficients" => coefficients}) do
    %{type: "polynomial", coefficients: coefficients, reverse_states: nil}
  end

  defp parse_conversion(%{"type" => "state_table", "states" => states}) do
    # Convert keys to strings
    string_states = Enum.into(states, %{}, fn {k, v} -> {to_string(k), v} end)

    reverse_states =
      Enum.reduce(string_states, %{}, fn {raw_value, state_value}, acc ->
        case Integer.parse(raw_value) do
          {raw_int, ""} -> Map.put(acc, state_value, raw_int)
          _ -> acc
        end
      end)

    %{type: "state_table", states: string_states, reverse_states: reverse_states}
  end

  defp parse_conversion(data) do
    Logger.warning("Unknown conversion format: #{inspect(data)}")
    nil
  end

  # Encode a single packet
  defp encode_packet(encoder, packet_name, target_hash, timestamp, values) do
    case Map.get(encoder.packets, packet_name) do
      nil ->
        {:error, {:unknown_packet, packet_name}}

      packet_def ->
        # Encode to binary
        binary = encode_packet_binary(encoder, packet_def, target_hash, timestamp, values)

        # Update sequence count
        apid = packet_def.apid || 0
        seq = Map.get(encoder.sequence_counts, apid, 0)
        new_seq = rem(seq + 1, 16_384)
        encoder = %{encoder | sequence_counts: Map.put(encoder.sequence_counts, apid, new_seq)}

        {:ok, binary, encoder}
    end
  end

  defp encode_packet_binary(encoder, packet_def, target_hash, timestamp, values) do
    payload = build_payload(packet_def, values)

    # Build CCSDS packet
    apid = packet_def.apid || 0
    seq = Map.get(encoder.sequence_counts, apid, 0)

    build_ccsds_packet(packet_def, seq, target_hash, timestamp, payload)
  end

  defp build_payload(%{packing_strategy: :sequential} = packet_def, values) do
    iodata =
      Enum.reduce(packet_def.pack_items, [], fn {gap_before, item_def, empty_value}, acc ->
        value_binary =
          case Map.get(values, item_def.qualified_name) do
            nil ->
              empty_value

            value ->
              raw_value = reverse_convert(value, item_def.conversion)

              value_to_binary(
                raw_value,
                item_def.data_type,
                item_def.bit_size,
                item_def.byte_size,
                item_def.endianness
              )
          end

        [acc, gap_before, value_binary]
      end)

    IO.iodata_to_binary([iodata, packet_def.tail_gap])
  end

  defp build_payload(packet_def, values) do
    Enum.reduce(packet_def.items, zero_binary(packet_def.payload_size), fn item_def, acc ->
      case Map.get(values, item_def.qualified_name) do
        nil ->
          acc

        value ->
          raw_value = reverse_convert(value, item_def.conversion)
          pack_value(acc, item_def, raw_value)
      end
    end)
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

  defp reverse_convert(value, %{type: "state_table", reverse_states: reverse_states}) do
    case Map.fetch(reverse_states, value) do
      {:ok, raw_value} ->
        raw_value

      :error ->
        Logger.warning("State '#{value}' not found in state table, using 0")
        0
    end
  end

  # Pack a value into the binary payload at the specified bit offset
  defp pack_value(payload, item_def, value) do
    value_binary =
      value_to_binary(
        value,
        item_def.data_type,
        item_def.bit_size,
        item_def.byte_size,
        item_def.endianness
      )

    insert_bits(payload, value_binary, item_def.byte_offset, item_def.byte_size)
  end

  defp value_to_binary(value, "float", 32, _byte_size, endianness) do
    case endianness do
      "big" -> <<value::float-big-32>>
      "little" -> <<value::float-little-32>>
      _ -> <<value::float-big-32>>
    end
  end

  defp value_to_binary(value, "float", 64, _byte_size, endianness) do
    case endianness do
      "big" -> <<value::float-big-64>>
      "little" -> <<value::float-little-64>>
      _ -> <<value::float-big-64>>
    end
  end

  defp value_to_binary(value, "uint", _bit_size, byte_size, endianness) do
    int_value = trunc(value)

    case endianness do
      "big" -> <<int_value::unsigned-big-size(byte_size * 8)>>
      "little" -> <<int_value::unsigned-little-size(byte_size * 8)>>
      _ -> <<int_value::unsigned-big-size(byte_size * 8)>>
    end
  end

  defp value_to_binary(value, "int", _bit_size, byte_size, endianness) do
    int_value = trunc(value)

    case endianness do
      "big" -> <<int_value::signed-big-size(byte_size * 8)>>
      "little" -> <<int_value::signed-little-size(byte_size * 8)>>
      _ -> <<int_value::signed-big-size(byte_size * 8)>>
    end
  end

  defp value_to_binary(value, "boolean", _bit_size, _byte_size, _endianness) do
    if value, do: <<1>>, else: <<0>>
  end

  defp value_to_binary(value, "string", _bit_size, byte_size, _endianness) do
    str = to_string(value)

    String.pad_trailing(str, byte_size, <<0>>)
    |> String.slice(0, byte_size)
  end

  defp value_to_binary(value, "binary", _bit_size, byte_size, _endianness)
       when is_binary(value) do
    # Pad or truncate to exact size
    case byte_size(value) do
      ^byte_size -> value
      n when n < byte_size -> value <> :binary.copy(<<0>>, byte_size - n)
      _ -> binary_part(value, 0, byte_size)
    end
  end

  defp value_to_binary(_value, "binary", _bit_size, byte_size, _endianness) do
    # If not already binary, generate zeros
    :binary.copy(<<0>>, byte_size)
  end

  defp value_to_binary(value, _unknown_type, bit_size, byte_size, endianness) do
    # Default to uint
    value_to_binary(value, "uint", bit_size, byte_size, endianness)
  end

  # Insert bits into payload (simplified byte-aligned version)
  defp insert_bits(payload, value_binary, byte_offset, byte_size) do
    # For simplicity, we handle byte-aligned offsets
    # A more complete implementation would handle arbitrary bit offsets
    prefix = binary_part(payload, 0, byte_offset)
    suffix_start = byte_offset + byte_size
    suffix_len = byte_size(payload) - suffix_start
    suffix = if suffix_len > 0, do: binary_part(payload, suffix_start, suffix_len), else: <<>>

    prefix <> binary_part(value_binary, 0, min(byte_size, byte_size(value_binary))) <> suffix
  end

  # Build a CCSDS packet (no sync pattern - TM frames provide framing)
  defp build_ccsds_packet(packet_def, sequence, target_hash, timestamp, payload) do
    # unsegmented
    sequence_flags = 3
    seq_control = sequence_flags <<< 14 ||| sequence

    # No sync pattern - when used with TM frames, framing is provided by the frame structure
    # The sync pattern was causing APID misalignment (0x1ACF parsed as APID 719)
    <<packet_def.packet_id::16, seq_control::16, packet_def.data_length::16, timestamp::48,
      target_hash::16, payload::binary>>
  end

  defp active_packets(encoder, values) do
    Enum.reduce(values, %{}, fn {qualified_name, _value}, acc ->
      case Map.get(encoder.items_by_qualified_name, qualified_name) do
        %{packet_name: packet_name} ->
          Map.put(acc, packet_name, true)

        nil ->
          acc
      end
    end)
  end

  defp reduce_active_packets(encoder, active_packets, initial_acc, fun) do
    Enum.reduce(encoder.packet_order, initial_acc, fn packet_name, acc ->
      if Map.has_key?(active_packets, packet_name), do: fun.(packet_name, acc), else: acc
    end)
  end

  defp append_encoded_packet({:ok, binary, updated_encoder}, packet_name, acc, _encoder) do
    {[{packet_name, binary} | acc], updated_encoder}
  end

  defp append_encoded_packet({:error, reason}, packet_name, acc, encoder) do
    Logger.warning("Failed to encode packet #{packet_name}: #{inspect(reason)}")
    {acc, encoder}
  end

  defp append_encoded_packet({:ok, binary}, packet_name, acc) do
    [{packet_name, binary} | acc]
  end

  defp append_encoded_packet({:error, reason}, packet_name, acc) do
    Logger.warning("Failed to encode packet #{packet_name}: #{inspect(reason)}")
    acc
  end

  defp payload_size(items) do
    max_bit =
      items
      |> Enum.map(fn item -> item.bit_offset + item.bit_size end)
      |> Enum.max(fn -> 0 end)

    div(max_bit + 7, 8)
  end

  defp build_packet_id(apid) do
    version = 0
    type = 0
    sec_hdr_flag = 1
    version <<< 13 ||| type <<< 12 ||| sec_hdr_flag <<< 11 ||| apid
  end

  defp build_packing_layout(items, payload_size) do
    if Enum.all?(items, &byte_aligned?/1) do
      items
      |> Enum.sort_by(& &1.byte_offset)
      |> build_pack_items(0, [])
      |> finalize_packing_layout(payload_size)
    else
      fallback_packing_layout()
    end
  end

  defp build_pack_items([], cursor, acc), do: {:ok, Enum.reverse(acc), cursor}

  defp build_pack_items([item | rest], cursor, acc) do
    if item.byte_offset < cursor do
      :error
    else
      next_cursor = item.byte_offset + item.byte_size

      build_pack_items(
        rest,
        next_cursor,
        [{zero_binary(item.byte_offset - cursor), item, zero_binary(item.byte_size)} | acc]
      )
    end
  end

  defp finalize_packing_layout({:ok, pack_items, cursor}, payload_size) do
    %{
      strategy: :sequential,
      pack_items: pack_items,
      tail_gap: zero_binary(payload_size - cursor)
    }
  end

  defp finalize_packing_layout(:error, _payload_size), do: fallback_packing_layout()

  defp fallback_packing_layout do
    %{strategy: :spliced, pack_items: [], tail_gap: <<>>}
  end

  defp byte_aligned?(item) do
    rem(item.bit_offset, 8) == 0 and rem(item.bit_size, 8) == 0
  end

  defp zero_binary(0), do: <<>>
  defp zero_binary(size), do: :binary.copy(<<0>>, size)
end
