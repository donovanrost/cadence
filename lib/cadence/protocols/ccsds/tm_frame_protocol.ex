defmodule Cadence.Protocols.CCSDS.TMFrameProtocol do
  @moduledoc """
  TM transfer frame deframer.

  Extracts CCSDS space packets from fixed-length TM frames, supports segmented
  packets across frames, and discards idle packets. Metadata is annotated with
  SCID/VCID and frame header fields.
  """

  use Cadence.Telemetry.Protocol

  alias Cadence.Protocols.CCSDS.TMFrame

  import Bitwise
  require Logger

  @primary_header_size 6
  @idle_apid 0x7FF
  @default_oid_validation :none
  @default_oid_prefix_bytes 10
  @oid_seed 0xFFFFFFFF

  defstruct [
    :frame_size,
    :scid_target_map,
    :default_target_id,
    :secondary_header_length,
    :ocf_length,
    :scid,
    :vcid,
    :mcfc,
    :vcfc,
    :oid_validation,
    :oid_validation_prefix_bytes,
    buffer: <<>>,
    packet_meta_queue: :queue.new(),
    partial_by_vcid: %{},
    oid_lfsr_by_vcid: %{}
  ]

  @type t :: %__MODULE__{
          frame_size: pos_integer(),
          scid_target_map: map(),
          default_target_id: String.t() | nil,
          secondary_header_length: non_neg_integer(),
          ocf_length: non_neg_integer(),
          scid: non_neg_integer(),
          vcid: non_neg_integer(),
          mcfc: non_neg_integer(),
          vcfc: non_neg_integer(),
          oid_validation: :none | :prefix | :strict,
          oid_validation_prefix_bytes: pos_integer(),
          buffer: binary(),
          packet_meta_queue: :queue.queue(),
          partial_by_vcid: map(),
          oid_lfsr_by_vcid: map()
        }

  @doc """
  Initializes TM deframer state.

  Options:
  - `:frame_size` (required) - Total TM frame size in bytes
  - `:scid_target_map` - Map of scid => target_id
  - `:default_target_id` - Fallback target_id when scid is unknown
  - `:secondary_header_length` - Transfer Frame Secondary Header length (default: 0)
  - `:ocf_length` - Operational Control Field length (default: 4)
  - `:oid_validation` - OID idle-data validation: `:none`, `:prefix`, or `:strict` (default: :none)
  - `:oid_validation_prefix_bytes` - Bytes to check for `:prefix` validation (default: 10)
  """
  def new(opts) do
    oid_validation =
      normalize_oid_validation(Keyword.get(opts, :oid_validation, @default_oid_validation))

    oid_prefix_bytes = Keyword.get(opts, :oid_validation_prefix_bytes, @default_oid_prefix_bytes)
    validate_oid_prefix_bytes!(oid_prefix_bytes)

    %__MODULE__{
      frame_size: Keyword.fetch!(opts, :frame_size),
      scid_target_map: Keyword.get(opts, :scid_target_map, %{}),
      default_target_id: Keyword.get(opts, :default_target_id),
      secondary_header_length: Keyword.get(opts, :secondary_header_length, 0),
      ocf_length: Keyword.get(opts, :ocf_length, 4),
      scid: Keyword.get(opts, :scid, 0),
      vcid: Keyword.get(opts, :vcid, 0),
      mcfc: Keyword.get(opts, :mcfc, 0),
      vcfc: Keyword.get(opts, :vcfc, 0),
      oid_validation: oid_validation,
      oid_validation_prefix_bytes: oid_prefix_bytes,
      buffer: <<>>,
      packet_meta_queue: :queue.new(),
      partial_by_vcid: %{},
      oid_lfsr_by_vcid: %{}
    }
  end

  def write_data(packet, %__MODULE__{} = state) when is_binary(packet) do
    frame =
      TMFrame.encode(packet,
        frame_size: state.frame_size,
        scid: state.scid,
        vcid: state.vcid,
        mcfc: state.mcfc,
        vcfc: state.vcfc
      )

    {:ok, [frame], increment_counters(state)}
  end

  def encode_oid(%__MODULE__{} = state, pn_state) do
    {frame, next_pn_state} =
      TMFrame.encode_oid(
        frame_size: state.frame_size,
        scid: state.scid,
        vcid: state.vcid,
        mcfc: state.mcfc,
        vcfc: state.vcfc,
        pn_state: pn_state
      )

    {frame, increment_counters(state), next_pn_state}
  end

  def read_data(data, %__MODULE__{} = state) when is_binary(data) do
    buffer = state.buffer <> data
    frame_size = state.frame_size

    case split_frames(buffer, frame_size) do
      {:incomplete, buffered} ->
        {:stop, %{state | buffer: buffered}}

      {frames, rest} ->
        handle_frames(frames, rest, state)
    end
  end

  def read_packet(packet, metadata, %__MODULE__{} = state) do
    case :queue.out(state.packet_meta_queue) do
      {{:value, packet_meta}, queue} ->
        {packet, Map.merge(metadata, packet_meta), %{state | packet_meta_queue: queue}}

      {:empty, _} ->
        {packet, metadata, state}
    end
  end

  def packet_format, do: :ccsds

  defp maybe_put_target_id(metadata, nil), do: metadata
  defp maybe_put_target_id(metadata, target_id), do: Map.put(metadata, :target_id, target_id)

  defp split_frames(buffer, frame_size) do
    if byte_size(buffer) < frame_size do
      {:incomplete, buffer}
    else
      frame_count = div(byte_size(buffer), frame_size)
      total_size = frame_count * frame_size
      <<frames_bin::binary-size(total_size), rest::binary>> = buffer

      frames = for <<frame::binary-size(frame_size) <- frames_bin>>, do: frame

      {frames, rest}
    end
  end

  defp handle_frames(frames, rest, state) do
    {packets, updated_state} = Enum.reduce(frames, {[], state}, &process_frame/2)

    if packets == [] do
      {:stop, %{updated_state | buffer: rest}}
    else
      {:ok, packets, %{updated_state | buffer: rest}}
    end
  end

  defp process_frame(frame, {acc_packets, acc_state}) do
    case decode_frame(frame, acc_state) do
      {:ok, frame_packets, packet_meta, next_state} ->
        queue =
          Enum.reduce(frame_packets, acc_state.packet_meta_queue, fn _packet, q ->
            :queue.in(packet_meta, q)
          end)

        new_state = %{next_state | packet_meta_queue: queue}
        {acc_packets ++ frame_packets, new_state}

      {:drop, next_state} ->
        {acc_packets, next_state}
    end
  end

  defp decode_frame(
         <<version::2, scid::10, vcid::3, ocf_flag::1, mcfc::8, vcfc::8, sec_hdr_flag::1,
           sync_flag::1, packet_order_flag::1, segment_len_id::2, fhp::11, payload::binary>>,
         state
       ) do
    frame_meta = %{
      scid: scid,
      vcid: vcid,
      mcfc: mcfc,
      vcfc: vcfc,
      secondary_header_flag: sec_hdr_flag,
      sync_flag: sync_flag,
      packet_order_flag: packet_order_flag,
      segment_length_id: segment_len_id,
      fhp: fhp
    }

    case validate_version(version) do
      :ok ->
        decode_valid_frame(
          frame_meta,
          payload,
          sec_hdr_flag,
          ocf_flag,
          sync_flag,
          segment_len_id,
          vcid,
          fhp,
          state
        )

      {:error, reason} ->
        Logger.warning("TM deframer dropped frame: #{inspect(reason)}")
        {:drop, state}
    end
  end

  defp decode_frame(_frame, state) do
    Logger.warning("TM deframer dropped frame: invalid frame")
    {:drop, state}
  end

  defp decode_valid_frame(
         frame_meta,
         payload,
         sec_hdr_flag,
         ocf_flag,
         sync_flag,
         segment_len_id,
         vcid,
         fhp,
         state
       ) do
    with :ok <- validate_sync_flag(sync_flag),
         :ok <- validate_segment_length_id(segment_len_id, sync_flag),
         {:ok, data_field, ocf} <- extract_data_field(payload, sec_hdr_flag, ocf_flag, state) do
      case extract_packets(data_field, vcid, fhp, state) do
        {:ok, packets, next_state} ->
          packet_meta = build_packet_metadata(frame_meta, ocf, state)
          {:ok, packets, packet_meta, next_state}

        {:error, reason, next_state} ->
          Logger.warning("TM deframer dropped frame: #{inspect(reason)}")
          {:drop, next_state}

        {:error, reason} ->
          Logger.warning("TM deframer dropped frame: #{inspect(reason)}")
          {:drop, state}
      end
    else
      {:error, reason} ->
        Logger.warning("TM deframer dropped frame: #{inspect(reason)}")
        {:drop, state}
    end
  end

  defp validate_version(0), do: :ok
  defp validate_version(version), do: {:error, {:unsupported_version, version}}

  defp validate_sync_flag(0), do: :ok
  defp validate_sync_flag(1), do: {:error, :vca_sdu}
  defp validate_sync_flag(value), do: {:error, {:invalid_sync_flag, value}}

  defp validate_segment_length_id(3, 0), do: :ok
  defp validate_segment_length_id(_seg, 0), do: {:error, :unsupported_segment_length_id}
  defp validate_segment_length_id(_seg, 1), do: :ok

  defp extract_data_field(payload, sec_hdr_flag, ocf_flag, state) do
    sec_hdr_len = if sec_hdr_flag == 1, do: state.secondary_header_length, else: 0
    ocf_len = if ocf_flag == 1, do: state.ocf_length, else: 0

    if byte_size(payload) < sec_hdr_len + ocf_len do
      {:error, :frame_too_short}
    else
      <<_sec_hdr::binary-size(sec_hdr_len), rest::binary>> = payload
      data_len = byte_size(rest) - ocf_len
      <<data_field::binary-size(data_len), ocf::binary-size(ocf_len)>> = rest
      {:ok, data_field, ocf}
    end
  end

  defp extract_packets(data_field, vcid, fhp, state) do
    cond do
      fhp == 2046 ->
        case validate_oid_data_field(data_field, vcid, state) do
          {:ok, next_state} ->
            {:ok, [], clear_partial_buffer(next_state, vcid)}

          {:error, reason, next_state} ->
            {:error, reason, clear_partial_buffer(next_state, vcid)}
        end

      fhp == 2047 ->
        {packets, next_state} = continue_partial_if_present(state, vcid, data_field)
        {:ok, packets, next_state}

      fhp >= 0 and fhp < byte_size(data_field) ->
        {prefix, suffix} = split_at(data_field, fhp)
        {packets_a, state_after_prefix} = append_and_drain_partial(state, vcid, prefix)
        {packets_b, remaining} = extract_packets_from_buffer(suffix)
        updated_state = put_partial(state_after_prefix, vcid, remaining)
        {:ok, packets_a ++ packets_b, updated_state}

      true ->
        {:error, {:invalid_fhp, fhp}}
    end
  end

  defp build_packet_metadata(frame_meta, ocf, state) do
    target_id =
      Map.get(state.scid_target_map, frame_meta.scid) || state.default_target_id

    frame_meta
    |> maybe_put_ocf(ocf)
    |> maybe_put_target_id(target_id)
  end

  defp maybe_put_ocf(metadata, <<>>), do: metadata
  defp maybe_put_ocf(metadata, ocf), do: Map.put(metadata, :ocf, ocf)

  defp split_at(binary, offset) do
    <<prefix::binary-size(offset), suffix::binary>> = binary
    {prefix, suffix}
  end

  defp extract_packets_from_buffer(buffer) do
    do_extract_packets(buffer, [])
  end

  defp do_extract_packets(buffer, acc) do
    case buffer do
      <<_::binary-size(@primary_header_size), _::binary>> ->
        total_size = ccsds_packet_size(buffer)

        if byte_size(buffer) >= total_size do
          <<packet::binary-size(total_size), rest::binary>> = buffer

          if idle_packet?(packet) do
            do_extract_packets(rest, acc)
          else
            do_extract_packets(rest, [packet | acc])
          end
        else
          {Enum.reverse(acc), buffer}
        end

      _ ->
        {Enum.reverse(acc), buffer}
    end
  end

  defp ccsds_packet_size(
         <<_version::3, _type::1, _sec_hdr::1, _apid::11, _seq_flags::2, _seq_count::14,
           packet_length::16, _rest::binary>>
       ) do
    packet_length + 1 + @primary_header_size
  end

  defp idle_packet?(<<_version::3, _type::1, _sec_hdr::1, apid::11, _rest::binary>>) do
    apid == @idle_apid
  end

  defp idle_packet?(_packet), do: false

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

  defp oid_pn_bytes(length, lfsr_state) do
    {bits, next_state} = generate_oid_bits(length * 8, lfsr_state)

    bytes =
      bits
      |> Enum.chunk_every(8)
      |> Enum.map(fn chunk ->
        Enum.reduce(chunk, 0, fn bit, acc -> (acc <<< 1) ||| bit end)
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
    output = (state >>> 31) &&& 1

    feedback =
      output
      |> bxor((state >>> 21) &&& 1)
      |> bxor((state >>> 1) &&& 1)
      |> bxor(state &&& 1)

    next_state = ((state <<< 1) &&& 0xFFFFFFFF) ||| feedback
    {output, next_state}
  end

  defp normalize_oid_validation(value) when is_atom(value) do
    case value do
      :none -> :none
      :prefix -> :prefix
      :strict -> :strict
      _ -> raise ArgumentError, "Invalid oid_validation: #{inspect(value)}"
    end
  end

  defp normalize_oid_validation(value) when is_binary(value) do
    case String.downcase(value) do
      "none" -> :none
      "prefix" -> :prefix
      "strict" -> :strict
      other -> raise ArgumentError, "Invalid oid_validation: #{inspect(other)}"
    end
  end

  defp validate_oid_prefix_bytes!(value) when is_integer(value) and value > 0, do: :ok

  defp validate_oid_prefix_bytes!(value) do
    raise ArgumentError, "oid_validation_prefix_bytes must be a positive integer: #{inspect(value)}"
  end

  defp continue_partial_if_present(state, vcid, data) do
    case Map.get(state.partial_by_vcid, vcid) do
      nil ->
        {[], state}

      _partial ->
        append_and_drain_partial(state, vcid, data)
    end
  end

  defp append_and_drain_partial(state, vcid, data) do
    existing = Map.get(state.partial_by_vcid, vcid, <<>>)
    combined = existing <> data
    {packets, remaining} = extract_packets_from_buffer(combined)
    updated_state = put_partial(state, vcid, remaining)
    {packets, updated_state}
  end

  defp put_partial(state, vcid, <<>>),
    do: %{state | partial_by_vcid: Map.delete(state.partial_by_vcid, vcid)}

  defp put_partial(state, vcid, remaining) do
    %{state | partial_by_vcid: Map.put(state.partial_by_vcid, vcid, remaining)}
  end

  defp clear_partial_buffer(state, vcid) do
    %{state | partial_by_vcid: Map.delete(state.partial_by_vcid, vcid)}
  end

  defp increment_counters(state) do
    %{
      state
      | mcfc: rem(state.mcfc + 1, 256),
        vcfc: rem(state.vcfc + 1, 256)
    }
  end
end
