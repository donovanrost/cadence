defmodule Cadence.CCSDS.SDLP.TM.Reassembly do
  @moduledoc """
  CCSDS TM profile reassembly service for packet-carrying frames.
  """

  @behaviour Cadence.CCSDS.SDLP.Reassembly

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Stream

  import Bitwise

  @default_oid_validation :none
  @default_oid_prefix_bytes 10
  @oid_seed 0xFFFFFFFF
  @impl true
  def init(opts) do
    oid_validation =
      normalize_oid_validation(Keyword.get(opts, :oid_validation, @default_oid_validation))

    oid_prefix_bytes = Keyword.get(opts, :oid_validation_prefix_bytes, @default_oid_prefix_bytes)
    validate_oid_prefix_bytes!(oid_prefix_bytes)

    default_sdu_type = normalize_sdu_kind_hint(Keyword.get(opts, :default_sdu_type))

    {:ok,
     %{
       scid_target_map: Keyword.get(opts, :scid_target_map, %{}),
       default_target_id: Keyword.get(opts, :default_target_id),
       vcid_target_map: Keyword.get(opts, :vcid_target_map, %{}),
       default_vcid_map: Keyword.get(opts, :default_vcid_map, %{}),
       oid_validation: oid_validation,
       oid_validation_prefix_bytes: oid_prefix_bytes,
       continuation_by_vcid: %{},
       oid_lfsr_by_vcid: %{},
       default_sdu_type: default_sdu_type,
       max_space_packet_size:
         Keyword.get(opts, :max_space_packet_size, SpacePacket.maximum_size()),
       packet_buffers_by_vcid: %{}
     }}
  end

  @impl true
  def ingest(%LinkFrame{profile: :tm} = frame, ctx, state) do
    vcid = frame.vcid
    fhp = Map.get(frame.meta, :fhp)

    case extract_segments(frame.payload_octets, vcid, fhp, state) do
      {:ok, segments, next_state} ->
        case reassemble_space_packets(segments, vcid, next_state) do
          {:ok, packets, final_state} ->
            sdu_octets = build_sdu_octets(packets, frame, ctx, final_state)
            {:ok, sdu_octets, final_state}

          {:error, reason, final_state} ->
            {:error, reason, final_state}
        end

      {:error, reason, next_state} ->
        {:error, reason, next_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def ingest(_frame, _ctx, state), do: {:error, :invalid_profile, state}

  defp reassemble_space_packets(segments, _vcid, %{default_sdu_type: sdu_type} = state)
       when sdu_type != :space_packet do
    {:ok, segments, state}
  end

  defp reassemble_space_packets(segments, vcid, state) do
    buffer = Map.get(state.packet_buffers_by_vcid, vcid, <<>>)
    packet_bytes = IO.iodata_to_binary([buffer | segments])

    case Stream.extract(packet_bytes, max_packet_size: state.max_space_packet_size) do
      {:ok, packets, remaining} ->
        {:ok, packets, update_packet_buffer(state, vcid, remaining)}

      {:error, reason} ->
        {:error, {:invalid_space_packet, reason}, clear_packet_buffer(state, vcid)}
    end
  end

  defp update_packet_buffer(state, vcid, <<>>) do
    %{state | packet_buffers_by_vcid: Map.delete(state.packet_buffers_by_vcid, vcid)}
  end

  defp update_packet_buffer(state, vcid, buffer) do
    %{state | packet_buffers_by_vcid: Map.put(state.packet_buffers_by_vcid, vcid, buffer)}
  end

  defp build_sdu_octets(segments, frame, ctx, state) do
    meta =
      frame.meta
      |> Map.put(:scid, frame.scid)
      |> Map.put(:vcid, frame.vcid)
      |> maybe_put_ocf(frame.ocf)
      |> maybe_put_target_id(target_id(state, frame.scid))
      |> merge_vcid_metadata(vcid_metadata(state, frame.scid, frame.vcid))

    direction = Map.get(ctx, :direction, :downlink)
    sdu_kind_hint = Map.get(ctx, :sdu_kind_hint)

    Enum.map(segments, fn segment ->
      %SDUOctets{
        profile: frame.profile,
        scid: frame.scid,
        vcid: frame.vcid,
        map_id: frame.map_id,
        direction: direction,
        sdu_kind_hint: sdu_kind_hint,
        octets: segment,
        quality: frame.quality || :good,
        source_frames: [frame.frame_seq],
        timestamp: frame.timestamp,
        meta: meta
      }
    end)
  end

  defp target_id(state, scid) do
    Map.get(state.scid_target_map, scid) || state.default_target_id
  end

  defp vcid_metadata(state, scid, vcid) do
    case Map.get(state.vcid_target_map, scid) do
      nil ->
        Map.get(state.default_vcid_map, vcid, %{})

      vcid_map ->
        Map.get(vcid_map, vcid) || Map.get(state.default_vcid_map, vcid, %{})
    end
  end

  defp merge_vcid_metadata(metadata, meta) when map_size(meta) == 0, do: metadata

  defp merge_vcid_metadata(metadata, meta) do
    metadata
    |> maybe_put_lane(meta)
    |> maybe_put_qos(meta)
  end

  defp maybe_put_lane(metadata, meta) do
    case Map.get(meta, :lane) || Map.get(meta, "lane") do
      nil -> metadata
      "" -> metadata
      lane -> Map.put(metadata, :lane, lane)
    end
  end

  defp maybe_put_qos(metadata, meta) do
    case Map.get(meta, :qos) || Map.get(meta, "qos") do
      nil -> metadata
      "" -> metadata
      qos -> Map.put(metadata, :qos, qos)
    end
  end

  defp maybe_put_target_id(metadata, nil), do: metadata
  defp maybe_put_target_id(metadata, target_id), do: Map.put(metadata, :target_id, target_id)

  defp maybe_put_ocf(metadata, nil), do: metadata
  defp maybe_put_ocf(metadata, <<>>), do: metadata
  defp maybe_put_ocf(metadata, ocf), do: Map.put(metadata, :ocf, ocf)

  defp extract_segments(data_field, vcid, fhp, state) do
    cond do
      fhp == 2046 ->
        case validate_oid_data_field(data_field, vcid, state) do
          {:ok, next_state} ->
            {:ok, [], clear_continuation(clear_packet_buffer(next_state, vcid), vcid)}

          {:error, reason, next_state} ->
            {:error, reason, clear_continuation(clear_packet_buffer(next_state, vcid), vcid)}
        end

      fhp == 2047 ->
        if continuation?(state, vcid) do
          {:ok, [data_field], state}
        else
          {:ok, [], state}
        end

      fhp >= 0 and fhp < byte_size(data_field) ->
        {prefix, suffix} = split_at(data_field, fhp)
        segments = build_segments(prefix, suffix, continuation?(state, vcid))
        {:ok, segments, set_continuation(state, vcid, true)}

      true ->
        {:error, {:invalid_fhp, fhp}}
    end
  end

  defp build_segments(prefix, suffix, true), do: [prefix <> suffix]
  defp build_segments(_prefix, suffix, false), do: [suffix]

  defp split_at(binary, offset) do
    <<prefix::binary-size(^offset), suffix::binary>> = binary
    {prefix, suffix}
  end

  defp clear_packet_buffer(%{default_sdu_type: sdu_type} = state, _vcid)
       when sdu_type != :space_packet do
    state
  end

  defp clear_packet_buffer(state, vcid) do
    %{state | packet_buffers_by_vcid: Map.delete(state.packet_buffers_by_vcid, vcid)}
  end

  defp validate_oid_data_field(_data_field, _vcid, %{oid_validation: :none} = state) do
    {:ok, state}
  end

  defp validate_oid_data_field(data_field, vcid, state) do
    {expected, next_lfsr} = oid_pn_bytes(byte_size(data_field), oid_lfsr_state(state, vcid))

    case state.oid_validation do
      :prefix ->
        prefix_size = min(state.oid_validation_prefix_bytes, byte_size(data_field))

        if binary_part(data_field, 0, prefix_size) ==
             binary_part(expected, 0, prefix_size) do
          {:ok, put_oid_lfsr_state(state, vcid, next_lfsr)}
        else
          {:error, :oid_pn_prefix_mismatch, state}
        end

      :strict ->
        if data_field == expected do
          {:ok, put_oid_lfsr_state(state, vcid, next_lfsr)}
        else
          {:error, :oid_pn_mismatch, state}
        end
    end
  end

  defp oid_lfsr_state(state, vcid) do
    Map.get(state.oid_lfsr_by_vcid, vcid, @oid_seed)
  end

  defp put_oid_lfsr_state(state, vcid, lfsr_state) do
    %{state | oid_lfsr_by_vcid: Map.put(state.oid_lfsr_by_vcid, vcid, lfsr_state)}
  end

  defp continuation?(state, vcid) do
    if state.default_sdu_type == :space_packet do
      case Map.get(state.packet_buffers_by_vcid, vcid) do
        nil -> false
        buffer -> byte_size(buffer) > 0
      end
    else
      Map.get(state.continuation_by_vcid, vcid, false)
    end
  end

  defp set_continuation(state, vcid, value) do
    %{state | continuation_by_vcid: Map.put(state.continuation_by_vcid, vcid, value)}
  end

  defp clear_continuation(state, vcid) do
    %{state | continuation_by_vcid: Map.delete(state.continuation_by_vcid, vcid)}
  end

  defp oid_pn_bytes(length, lfsr_state) do
    {bits, next_state} = generate_oid_bits(length * 8, lfsr_state)

    bytes =
      bits
      |> Enum.chunk_every(8)
      |> Enum.map(fn chunk ->
        Enum.reduce(chunk, 0, fn bit, acc -> acc <<< 1 ||| bit end)
      end)
      |> :binary.list_to_bin()

    {bytes, next_state}
  end

  defp generate_oid_bits(count, lfsr_state) do
    Enum.reduce(1..count, {[], lfsr_state}, fn _, {acc, state} ->
      {bit, next_state} = next_oid_bit(state)
      {[bit | acc], next_state}
    end)
    |> then(fn {bits, next_state} -> {Enum.reverse(bits), next_state} end)
  end

  defp next_oid_bit(state) do
    output = state >>> 31 &&& 1

    feedback =
      output
      |> bxor(state >>> 21 &&& 1)
      |> bxor(state >>> 1 &&& 1)
      |> bxor(state &&& 1)

    next_state = (state <<< 1 &&& 0xFFFFFFFF) ||| feedback
    {output, next_state}
  end

  defp normalize_oid_validation(value) when is_atom(value) do
    case value do
      :none -> :none
      :prefix -> :prefix
      :strict -> :strict
      _ -> raise ArgumentError, "invalid oid_validation: #{inspect(value)}"
    end
  end

  defp normalize_oid_validation(value) when is_binary(value) do
    case String.downcase(value) do
      "none" -> :none
      "prefix" -> :prefix
      "strict" -> :strict
      other -> raise ArgumentError, "invalid oid_validation: #{inspect(other)}"
    end
  end

  defp validate_oid_prefix_bytes!(value) when is_integer(value) and value > 0, do: :ok

  defp validate_oid_prefix_bytes!(value) do
    raise ArgumentError,
          "oid_validation_prefix_bytes must be a positive integer: #{inspect(value)}"
  end

  defp normalize_sdu_kind_hint(nil), do: nil
  defp normalize_sdu_kind_hint(:space_packet), do: :space_packet
  defp normalize_sdu_kind_hint(:encap), do: :encap

  defp normalize_sdu_kind_hint(value) when is_binary(value) do
    case String.downcase(value) do
      "space_packet" -> :space_packet
      "encap" -> :encap
      _ -> value
    end
  end

  defp normalize_sdu_kind_hint(value), do: value
end
