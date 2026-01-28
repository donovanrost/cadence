defmodule Cadence.CCSDS.SDLP.TM.FrameCodec do
  @moduledoc """
  TM profile frame codec.
  """

  @behaviour Cadence.CCSDS.SDLP.FrameCodec

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.Metrics

  require Logger

  @default_secondary_header_length 0
  @default_ocf_length 4
  @primary_header_size 6

  @impl true
  def profile, do: :tm

  @impl true
  def decode(bin, opts) when is_binary(bin) do
    frame_size = Keyword.fetch!(opts, :frame_size)
    sec_hdr_len = Keyword.get(opts, :secondary_header_length, @default_secondary_header_length)
    ocf_len = Keyword.get(opts, :ocf_length, @default_ocf_length)
    timestamp = Keyword.get(opts, :timestamp)
    scope = Metrics.scope_from_opts(opts)

    Metrics.inc(scope, profile(), :bytes_in, byte_size(bin))

    case split_frames(bin, frame_size) do
      {:incomplete, rest} ->
        {:ok, [], rest}

      {frames, rest} ->
        {decoded, decode_stats} = decode_frames(frames, sec_hdr_len, ocf_len, timestamp)

        Metrics.inc(scope, profile(), :frame_decode_total, length(frames))
        Metrics.inc(scope, profile(), :frame_decode_ok, decode_stats.ok)
        Metrics.inc(scope, profile(), :frame_decode_drop, decode_stats.drop)

        {:ok, decoded, rest}
    end
  end

  @impl true
  def encode(%LinkFrame{profile: :tm} = frame, opts) do
    frame_size = Keyword.fetch!(opts, :frame_size)
    sec_hdr_len = Keyword.get(opts, :secondary_header_length, @default_secondary_header_length)
    ocf_len = Keyword.get(opts, :ocf_length, @default_ocf_length)
    scope = Metrics.scope_from_opts(opts)

    Metrics.inc(scope, profile(), :frame_encode_total)

    ocf_flag = Map.get(frame.meta, :ocf_flag, if(has_ocf?(frame), do: 1, else: 0))
    sec_hdr_flag = Map.get(frame.meta, :secondary_header_flag, 0)
    sync_flag = Map.get(frame.meta, :sync_flag, 0)
    packet_order_flag = Map.get(frame.meta, :packet_order_flag, 0)
    segment_len_id = Map.get(frame.meta, :segment_length_id, 3)
    fhp = Map.get(frame.meta, :fhp, 0)
    mcfc = Map.get(frame.meta, :mcfc, 0)
    vcfc = Map.get(frame.meta, :vcfc, frame.frame_seq || 0)

    if sec_hdr_flag != 0 do
      Metrics.inc(scope, profile(), :frame_encode_error)
      {:error, :secondary_header_not_supported}
    else
      expected_data_len =
        frame_size - @primary_header_size - ocf_length_bytes(ocf_flag, ocf_len) -
          secondary_header_bytes(sec_hdr_flag, sec_hdr_len)

      if byte_size(frame.payload_octets) != expected_data_len do
        Metrics.inc(scope, profile(), :frame_encode_error)
        {:error, {:invalid_data_field_length, byte_size(frame.payload_octets), expected_data_len}}
      else
        header_opts = %{
          ocf_flag: ocf_flag,
          sec_hdr_flag: sec_hdr_flag,
          sync_flag: sync_flag,
          packet_order_flag: packet_order_flag,
          segment_len_id: segment_len_id,
          fhp: fhp
        }

        with {:ok, ocf} <- maybe_extract_ocf(frame, ocf_flag, ocf_len),
             {:ok, header} <-
               build_primary_header(frame.scid, frame.vcid, mcfc, vcfc, header_opts) do
          encoded = header <> frame.payload_octets <> ocf
          Metrics.inc(scope, profile(), :frame_encode_ok)
          Metrics.inc(scope, profile(), :bytes_out, byte_size(encoded))
          {:ok, encoded}
        else
          {:error, reason} ->
            Metrics.inc(scope, profile(), :frame_encode_error)
            {:error, reason}
        end
      end
    end
  end

  def encode(_frame, opts) do
    scope = Metrics.scope_from_opts(opts)
    Metrics.inc(scope, profile(), :frame_encode_total)
    Metrics.inc(scope, profile(), :frame_encode_error)
    {:error, :invalid_profile}
  end

  defp has_ocf?(%LinkFrame{ocf: ocf}) when is_binary(ocf), do: byte_size(ocf) > 0
  defp has_ocf?(_), do: false

  defp ocf_length_bytes(1, ocf_len), do: ocf_len
  defp ocf_length_bytes(_, _), do: 0

  defp secondary_header_bytes(1, sec_hdr_len), do: sec_hdr_len
  defp secondary_header_bytes(_, _), do: 0

  defp maybe_extract_ocf(_frame, 0, _ocf_len), do: {:ok, <<>>}

  defp maybe_extract_ocf(%LinkFrame{ocf: ocf}, 1, ocf_len) when is_binary(ocf) do
    if byte_size(ocf) == ocf_len do
      {:ok, ocf}
    else
      {:error, {:invalid_ocf_length, byte_size(ocf), ocf_len}}
    end
  end

  defp maybe_extract_ocf(_frame, 1, _ocf_len), do: {:error, :missing_ocf}

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

  defp decode_frame(
         <<version::2, scid::10, vcid::3, ocf_flag::1, mcfc::8, vcfc::8, sec_hdr_flag::1,
           sync_flag::1, packet_order_flag::1, segment_len_id::2, fhp::11, payload::binary>>,
         sec_hdr_len,
         ocf_len,
         timestamp
       ) do
    frame_meta = %{
      ocf_flag: ocf_flag,
      mcfc: mcfc,
      vcfc: vcfc,
      secondary_header_flag: sec_hdr_flag,
      sync_flag: sync_flag,
      packet_order_flag: packet_order_flag,
      segment_length_id: segment_len_id,
      fhp: fhp
    }

    with :ok <- validate_version(version),
         :ok <- validate_sync_flag(sync_flag),
         :ok <- validate_segment_length_id(segment_len_id, sync_flag),
         {:ok, data_field, ocf} <-
           extract_data_field(payload, sec_hdr_flag, ocf_flag, sec_hdr_len, ocf_len) do
      {:ok,
       %LinkFrame{
         profile: :tm,
         scid: scid,
         vcid: vcid,
         map_id: nil,
         frame_seq: vcfc,
         payload_octets: data_field,
         quality: :good,
         ocf: ocf,
         timestamp: timestamp,
         meta: frame_meta
       }}
    else
      {:error, reason} ->
        Logger.warning("TM frame decode dropped frame: #{inspect(reason)}")
        {:drop, reason}
    end
  end

  defp decode_frame(_frame, _sec_hdr_len, _ocf_len, _timestamp) do
    Logger.warning("TM frame decode dropped frame: invalid frame")
    {:drop, :invalid_frame}
  end

  defp decode_frames(frames, sec_hdr_len, ocf_len, timestamp) do
    {decoded, decode_stats} =
      Enum.reduce(frames, {[], %{ok: 0, drop: 0}}, fn frame, {acc, stats} ->
        case decode_frame(frame, sec_hdr_len, ocf_len, timestamp) do
          {:ok, %LinkFrame{} = decoded_frame} ->
            {[decoded_frame | acc], %{stats | ok: stats.ok + 1}}

          {:drop, _reason} ->
            {acc, %{stats | drop: stats.drop + 1}}
        end
      end)

    {Enum.reverse(decoded), decode_stats}
  end

  defp validate_version(0), do: :ok
  defp validate_version(version), do: {:error, {:unsupported_version, version}}

  defp validate_sync_flag(0), do: :ok
  defp validate_sync_flag(1), do: {:error, :vca_sdu}
  defp validate_sync_flag(value), do: {:error, {:invalid_sync_flag, value}}

  defp validate_segment_length_id(3, 0), do: :ok
  defp validate_segment_length_id(_seg, 0), do: {:error, :unsupported_segment_length_id}
  defp validate_segment_length_id(_seg, 1), do: :ok

  defp extract_data_field(payload, sec_hdr_flag, ocf_flag, sec_hdr_len, ocf_len) do
    sec_hdr_len = if sec_hdr_flag == 1, do: sec_hdr_len, else: 0
    ocf_len = if ocf_flag == 1, do: ocf_len, else: 0

    if byte_size(payload) < sec_hdr_len + ocf_len do
      {:error, :frame_too_short}
    else
      <<_sec_hdr::binary-size(sec_hdr_len), rest::binary>> = payload
      data_len = byte_size(rest) - ocf_len
      <<data_field::binary-size(data_len), ocf::binary-size(ocf_len)>> = rest
      {:ok, data_field, ocf}
    end
  end

  defp build_primary_header(scid, vcid, mcfc, vcfc, header_opts) do
    version = 0
    ocf_flag = Map.get(header_opts, :ocf_flag, 0)
    sec_hdr_flag = Map.get(header_opts, :sec_hdr_flag, 0)
    sync_flag = Map.get(header_opts, :sync_flag, 0)
    packet_order_flag = Map.get(header_opts, :packet_order_flag, 0)
    segment_len_id = Map.get(header_opts, :segment_len_id, 3)
    fhp = Map.get(header_opts, :fhp, 0)

    {:ok,
     <<
       version::2,
       scid::10,
       vcid::3,
       ocf_flag::1,
       mcfc::8,
       vcfc::8,
       sec_hdr_flag::1,
       sync_flag::1,
       packet_order_flag::1,
       segment_len_id::2,
       fhp::11
     >>}
  end
end
