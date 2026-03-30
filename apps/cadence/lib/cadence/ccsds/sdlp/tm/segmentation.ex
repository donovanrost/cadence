defmodule Cadence.CCSDS.SDLP.TM.Segmentation do
  @moduledoc """
  CCSDS TM profile segmentation service for packet-carrying frames.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}

  @primary_header_size 6
  @min_idle_packet_size @primary_header_size + 1
  @idle_apid 0x7FF

  @impl true
  def init(opts) do
    {:ok,
     %{
       mcfc: Keyword.get(opts, :mcfc, 0),
       vcfc: Keyword.get(opts, :vcfc, 0),
       idle_padding_cache: %{}
     }}
  end

  @impl true
  def segment(%SDUOctets{profile: :tm} = sdu, ctx, state) do
    case build_frame_ctx(sdu, ctx) do
      {:ok, frame_ctx} ->
        {frames, _frame_count, next_state} = build_frames(sdu.octets, frame_ctx, state)
        {:ok, frames, next_state}

      {:error, reason} ->
        {:error, reason, state}

      _ ->
        {:error, :frame_size_too_small, state}
    end
  end

  def segment(_sdu, _ctx, state), do: {:error, :invalid_profile, state}

  @spec segment_encode(SDUOctets.t(), map(), term(), keyword()) ::
          {:ok, iodata(), term()} | {:error, term(), term()}
  def segment_encode(%SDUOctets{profile: :tm} = sdu, ctx, state, _opts) do
    case build_frame_ctx(sdu, ctx) do
      {:ok, frame_ctx} ->
        {frames, _frame_count, next_state} = encode_frames(sdu.octets, frame_ctx, state)
        {:ok, IO.iodata_to_binary(frames), next_state}

      {:error, reason} ->
        {:error, reason, state}

      _ ->
        {:error, :frame_size_too_small, state}
    end
  end

  def segment_encode(_sdu, _ctx, state, _opts), do: {:error, :invalid_profile, state}

  defp build_frames(packet, %{max_payload: max_payload} = frame_ctx, state) do
    if byte_size(packet) <= max_payload do
      {payload, next_state} = build_last_payload(packet, max_payload, state)
      frame = build_frame(payload, 0, frame_ctx, next_state)
      {[frame], 1, increment_state(next_state)}
    else
      build_segmented_frames(packet, max_payload, frame_ctx, state, [], true, 0)
    end
  end

  defp encode_frames(packet, %{max_payload: max_payload} = frame_ctx, state) do
    if byte_size(packet) <= max_payload do
      {payload, next_state} = build_last_payload(packet, max_payload, state)
      frame = encode_frame(payload, 0, frame_ctx, next_state)
      {[frame], 1, increment_state(next_state)}
    else
      encode_segmented_frames(packet, max_payload, frame_ctx, state, [], true, 0)
    end
  end

  defp build_segmented_frames(packet, max_payload, frame_ctx, state, acc, first?, count)
       when byte_size(packet) > max_payload do
    <<segment::binary-size(max_payload), rest::binary>> = packet
    fhp = if first?, do: 0, else: 2047
    frame = build_frame(segment, fhp, frame_ctx, state)

    build_segmented_frames(
      rest,
      max_payload,
      frame_ctx,
      increment_state(state),
      [frame | acc],
      false,
      count + 1
    )
  end

  defp build_segmented_frames(packet, max_payload, frame_ctx, state, acc, first?, count) do
    {payload, next_state} = build_last_payload(packet, max_payload, state)
    fhp = if first?, do: 0, else: 2047
    frame = build_frame(payload, fhp, frame_ctx, next_state)

    {Enum.reverse([frame | acc]), count + 1, increment_state(next_state)}
  end

  defp encode_segmented_frames(packet, max_payload, frame_ctx, state, acc, first?, count)
       when byte_size(packet) > max_payload do
    <<segment::binary-size(max_payload), rest::binary>> = packet
    fhp = if first?, do: 0, else: 2047
    frame = encode_frame(segment, fhp, frame_ctx, state)

    encode_segmented_frames(
      rest,
      max_payload,
      frame_ctx,
      increment_state(state),
      [frame | acc],
      false,
      count + 1
    )
  end

  defp encode_segmented_frames(packet, max_payload, frame_ctx, state, acc, first?, count) do
    {payload, next_state} = build_last_payload(packet, max_payload, state)
    fhp = if first?, do: 0, else: 2047
    frame = encode_frame(payload, fhp, frame_ctx, next_state)

    {Enum.reverse([frame | acc]), count + 1, increment_state(next_state)}
  end

  defp build_frame(
         payload,
         fhp,
         %{scid: scid, vcid: vcid, ocf: ocf, ocf_flag: ocf_flag, timestamp: timestamp},
         state
       ) do
    %LinkFrame{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      map_id: nil,
      frame_seq: state.vcfc,
      payload_octets: payload,
      quality: :good,
      ocf: ocf,
      timestamp: timestamp,
      meta: %{
        mcfc: state.mcfc,
        vcfc: state.vcfc,
        fhp: fhp,
        ocf_flag: ocf_flag,
        secondary_header_flag: 0,
        sync_flag: 0,
        packet_order_flag: 0,
        segment_length_id: 3
      }
    }
  end

  defp encode_frame(
         payload,
         fhp,
         %{scid: scid, vcid: vcid, ocf: ocf, ocf_flag: ocf_flag},
         state
       ) do
    ocf_bin = if ocf_flag == 1, do: ocf, else: <<>>

    <<
      0::2,
      scid::10,
      vcid::3,
      ocf_flag::1,
      state.mcfc::8,
      state.vcfc::8,
      0::1,
      0::1,
      0::1,
      3::2,
      fhp::11,
      payload::binary,
      ocf_bin::binary
    >>
  end

  defp build_last_payload(segment, max_payload, state) do
    padding_size = max_payload - byte_size(segment)

    case build_idle_padding(padding_size, state) do
      {<<>>, next_state} -> {segment, next_state}
      {padding, next_state} -> {segment <> padding, next_state}
    end
  end

  defp build_idle_padding(0, state), do: {<<>>, state}

  defp build_idle_padding(padding_size, _state) when padding_size < @min_idle_packet_size do
    raise ArgumentError,
          "TM frame padding #{padding_size} bytes is too small for an idle packet"
  end

  defp build_idle_padding(padding_size, %{idle_padding_cache: cache} = state) do
    case cache do
      %{^padding_size => padding} ->
        {padding, state}

      _ ->
        padding = build_idle_packet(padding_size)
        {padding, %{state | idle_padding_cache: Map.put(cache, padding_size, padding)}}
    end
  end

  defp build_idle_packet(size) do
    payload_size = size - @primary_header_size
    packet_length = payload_size - 1
    payload = :binary.copy(<<0>>, payload_size)

    <<
      0::3,
      0::1,
      0::1,
      @idle_apid::11,
      3::2,
      0::14,
      packet_length::16,
      payload::binary
    >>
  end

  defp increment_state(%{mcfc: mcfc, vcfc: vcfc} = state) do
    %{state | mcfc: increment_counter(mcfc), vcfc: increment_counter(vcfc)}
  end

  defp increment_counter(value), do: rem(value + 1, 256)

  defp build_frame_ctx(sdu, ctx) do
    frame_size = Map.fetch!(ctx, :frame_size)
    scid = sdu.scid || Map.get(ctx, :scid, 0)
    vcid = sdu.vcid || Map.get(ctx, :vcid, 0)

    with {:ok, ocf, ocf_len} <- normalize_ocf(ctx),
         max_payload when max_payload > 0 <- frame_size - @primary_header_size - ocf_len do
      {:ok,
       %{
         frame_size: frame_size,
         max_payload: max_payload,
         scid: scid,
         vcid: vcid,
         ocf: ocf,
         ocf_flag: if(ocf_len > 0, do: 1, else: 0),
         timestamp: sdu.timestamp
       }}
    end
  end

  defp normalize_ocf(ctx) do
    case Map.get(ctx, :ocf) do
      nil ->
        {:ok, nil, 0}

      ocf when is_binary(ocf) ->
        ocf_len = Map.get(ctx, :ocf_length, byte_size(ocf))

        if ocf_len == byte_size(ocf) do
          {:ok, ocf, ocf_len}
        else
          {:error, :invalid_ocf_length}
        end

      _ ->
        {:error, :invalid_ocf}
    end
  end
end
