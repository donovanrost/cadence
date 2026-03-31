defmodule CadenceSimulator.PacketEncoder do
  @moduledoc """
  Encodes converted telemetry values into CCSDS space packets.

  This uses the legacy Cadence dev YAML shape, but emits packets compatible
  with the current Cadence runtime: primary header plus governed payload,
  without the old simulator-specific secondary header.
  """

  require Logger

  import Bitwise

  defstruct [
    :packets,
    :packet_order,
    :items_by_qualified_name,
    :conversions,
    :sequence_counts
  ]

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

  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, parsed} <- YamlElixir.read_from_string(content) do
      build_encoder(parsed)
    else
      {:error, reason} -> {:error, {:load_error, path, reason}}
    end
  end

  @spec load_string(String.t()) :: {:ok, t()} | {:error, term()}
  def load_string(yaml_content) do
    with {:ok, parsed} <- YamlElixir.read_from_string(yaml_content) do
      build_encoder(parsed)
    end
  end

  @spec encode(t(), String.t(), %{String.t() => any()}) ::
          {:ok, [{String.t(), binary()}], t()} | {:error, term()}
  def encode(encoder, _target_id, values) do
    active_packets = active_packets(encoder, values)

    {packets, encoder} =
      reduce_active_packets(encoder, active_packets, {[], encoder}, fn packet_name, {acc, enc} ->
        append_encoded_packet(encode_packet(enc, packet_name, values), packet_name, acc, enc)
      end)

    {:ok, Enum.reverse(packets), encoder}
  end

  @spec encode_with_sequence(t(), String.t(), %{String.t() => any()}, (non_neg_integer() ->
                                                                         non_neg_integer())) ::
          {:ok, [{String.t(), binary()}]} | {:error, term()}
  def encode_with_sequence(encoder, _target_id, values, sequence_fn)
      when is_function(sequence_fn, 1) do
    active_packets = active_packets(encoder, values)

    packets =
      reduce_active_packets(encoder, active_packets, [], fn packet_name, acc ->
        append_encoded_packet(
          encode_packet_with_sequence(encoder, packet_name, values, sequence_fn),
          packet_name,
          acc
        )
      end)

    {:ok, Enum.reverse(packets)}
  end

  @spec packet_names(t()) :: [String.t()]
  def packet_names(encoder), do: encoder.packet_order

  @spec item_names(t()) :: [String.t()]
  def item_names(encoder), do: Map.keys(encoder.items_by_qualified_name)

  @spec apids(t()) :: [non_neg_integer()]
  def apids(encoder) do
    encoder.packet_order
    |> Enum.map(&Map.fetch!(encoder.packets, &1).apid)
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

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
            data_length: max(payload_size - 1, 0),
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

    {:ok,
     %__MODULE__{
       packets: packet_map,
       packet_order: Enum.reverse(packet_order),
       items_by_qualified_name: items_map,
       conversions: conversions_map,
       sequence_counts: %{}
     }}
  end

  defp parse_conversion(nil), do: nil

  defp parse_conversion(%{"type" => "polynomial", "coefficients" => coefficients}) do
    %{type: "polynomial", coefficients: coefficients, reverse_states: nil}
  end

  defp parse_conversion(%{"type" => "state_table", "states" => states}) do
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

  defp encode_packet(encoder, packet_name, values) do
    case Map.get(encoder.packets, packet_name) do
      nil ->
        {:error, {:unknown_packet, packet_name}}

      packet_def ->
        binary = encode_packet_binary(encoder, packet_def, values)
        apid = packet_def.apid || 0
        seq = Map.get(encoder.sequence_counts, apid, 0)
        new_seq = rem(seq + 1, 16_384)
        encoder = %{encoder | sequence_counts: Map.put(encoder.sequence_counts, apid, new_seq)}
        {:ok, binary, encoder}
    end
  end

  defp encode_packet_with_sequence(encoder, packet_name, values, sequence_fn) do
    case Map.get(encoder.packets, packet_name) do
      nil ->
        {:error, {:unknown_packet, packet_name}}

      packet_def ->
        apid = packet_def.apid || 0
        {:ok, encode_packet_binary_with_seq(packet_def, values, sequence_fn.(apid))}
    end
  end

  defp encode_packet_binary(encoder, packet_def, values) do
    payload = build_payload(packet_def, values)
    apid = packet_def.apid || 0
    seq = Map.get(encoder.sequence_counts, apid, 0)
    build_ccsds_packet(packet_def, seq, payload)
  end

  defp encode_packet_binary_with_seq(packet_def, values, sequence) do
    payload = build_payload(packet_def, values)
    build_ccsds_packet(packet_def, sequence, payload)
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

  defp reverse_convert(value, nil), do: value

  defp reverse_convert(value, %{type: "polynomial", coefficients: coefficients}) do
    case coefficients do
      [c0, c1] when c1 != 0 -> (value - c0) / c1
      [c0] -> value - c0
      _ -> value
    end
  end

  defp reverse_convert(value, %{type: "state_table", reverse_states: reverse_states}) do
    case Map.fetch(reverse_states, value) do
      {:ok, raw_value} -> raw_value
      :error -> 0
    end
  end

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

  defp value_to_binary(value, "float", 32, _byte_size, "big"), do: <<value::float-big-32>>
  defp value_to_binary(value, "float", 32, _byte_size, "little"), do: <<value::float-little-32>>
  defp value_to_binary(value, "float", 32, _byte_size, _endianness), do: <<value::float-big-32>>
  defp value_to_binary(value, "float", 64, _byte_size, "big"), do: <<value::float-big-64>>
  defp value_to_binary(value, "float", 64, _byte_size, "little"), do: <<value::float-little-64>>
  defp value_to_binary(value, "float", 64, _byte_size, _endianness), do: <<value::float-big-64>>

  defp value_to_binary(value, "uint", _bit_size, byte_size, "little") do
    <<trunc(value)::unsigned-little-size(byte_size * 8)>>
  end

  defp value_to_binary(value, "uint", _bit_size, byte_size, _endianness) do
    <<trunc(value)::unsigned-big-size(byte_size * 8)>>
  end

  defp value_to_binary(value, "int", _bit_size, byte_size, "little") do
    <<trunc(value)::signed-little-size(byte_size * 8)>>
  end

  defp value_to_binary(value, "int", _bit_size, byte_size, _endianness) do
    <<trunc(value)::signed-big-size(byte_size * 8)>>
  end

  defp value_to_binary(value, "boolean", _bit_size, _byte_size, _endianness) do
    if value, do: <<1>>, else: <<0>>
  end

  defp value_to_binary(value, "string", _bit_size, byte_size, _endianness) do
    value
    |> to_string()
    |> String.pad_trailing(byte_size, <<0>>)
    |> String.slice(0, byte_size)
  end

  defp value_to_binary(value, "binary", _bit_size, byte_size, _endianness) when is_binary(value) do
    case byte_size(value) do
      ^byte_size -> value
      n when n < byte_size -> value <> :binary.copy(<<0>>, byte_size - n)
      _ -> binary_part(value, 0, byte_size)
    end
  end

  defp value_to_binary(_value, "binary", _bit_size, byte_size, _endianness) do
    :binary.copy(<<0>>, byte_size)
  end

  defp value_to_binary(value, _unknown_type, bit_size, byte_size, endianness) do
    value_to_binary(value, "uint", bit_size, byte_size, endianness)
  end

  defp insert_bits(payload, value_binary, byte_offset, byte_size) do
    prefix = binary_part(payload, 0, byte_offset)
    suffix_start = byte_offset + byte_size
    suffix_len = byte_size(payload) - suffix_start
    suffix = if suffix_len > 0, do: binary_part(payload, suffix_start, suffix_len), else: <<>>
    prefix <> binary_part(value_binary, 0, min(byte_size, byte_size(value_binary))) <> suffix
  end

  defp build_ccsds_packet(packet_def, sequence, payload) do
    <<
      0::3,
      0::1,
      0::1,
      (packet_def.apid || 0)::11,
      3::2,
      sequence::14,
      packet_def.data_length::16,
      payload::binary
    >>
  end

  defp active_packets(encoder, values) do
    Enum.reduce(values, %{}, fn {qualified_name, _value}, acc ->
      case Map.get(encoder.items_by_qualified_name, qualified_name) do
        %{packet_name: packet_name} -> Map.put(acc, packet_name, true)
        nil -> acc
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

  defp payload_size(item_defs) do
    case item_defs do
      [] ->
        0

      _ ->
        item_defs
        |> Enum.map(fn item_def -> item_def.byte_offset + item_def.byte_size end)
        |> Enum.max()
    end
  end

  defp build_packing_layout(item_defs, payload_size) do
    sorted_items = Enum.sort_by(item_defs, & &1.byte_offset)

    {pack_items, tail_offset, sequential?} =
      Enum.reduce(sorted_items, {[], 0, true}, fn item_def, {acc, offset, sequential?} ->
        gap_size = item_def.byte_offset - offset
        gap = if gap_size > 0, do: :binary.copy(<<0>>, gap_size), else: <<>>
        empty_value = :binary.copy(<<0>>, item_def.byte_size)
        next_offset = item_def.byte_offset + item_def.byte_size

        {
          [{gap, item_def, empty_value} | acc],
          next_offset,
          sequential? and item_def.bit_offset == item_def.byte_offset * 8
        }
      end)

    tail_gap_size = max(payload_size - tail_offset, 0)
    tail_gap = :binary.copy(<<0>>, tail_gap_size)

    %{
      strategy: if(sequential?, do: :sequential, else: :spliced),
      pack_items: Enum.reverse(pack_items),
      tail_gap: tail_gap
    }
  end

  defp build_packet_id(apid) do
    (0 <<< 13) ||| (0 <<< 12) ||| apid
  end

  defp zero_binary(0), do: <<>>
  defp zero_binary(size), do: :binary.copy(<<0>>, size)
end
