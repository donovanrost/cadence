defmodule CCSDS.SDLP.TM.FrameCodec do
  @moduledoc """
  CCSDS TM Transfer Frame wire codec.

  The codec supports Packet, Idle Data, and VCA_SDU data fields; optional
  Transfer Frame Secondary Headers, OCFs, and FECFs; and detailed evidence for
  every fixed-length frame dropped during stream decoding. Mission-managed
  invariants can be supplied through `TM.Configuration`.
  """

  @behaviour CCSDS.SDLP.FrameCodec

  alias CCSDS.Core.LinkFrame
  alias CCSDS.FrameErrorControl

  alias CCSDS.SDLP.TM.{Configuration, SecondaryHeader}

  @default_secondary_header_length 0
  @default_ocf_length 4
  @primary_header_size 6

  @impl true
  def profile, do: :tm

  @impl true
  def decode(bin, opts) when is_binary(bin) do
    with {:ok, decoded_frames, _dropped_frames, rest} <- decode_detailed(bin, opts) do
      {:ok, Enum.map(decoded_frames, & &1.frame), rest}
    end
  end

  @spec decode_detailed(binary(), keyword()) ::
          {:ok, [map()], [map()], rest :: binary()} | {:error, term()}
  def decode_detailed(bin, opts) when is_binary(bin) and is_list(opts) do
    with {:ok, options} <- normalize_options(opts),
         :ok <- validate_frame_size(options) do
      case split_frames(bin, options.frame_size) do
        {:incomplete, rest} ->
          {:ok, [], [], rest}

        {frames, rest} ->
          {decoded, dropped} = decode_frames(frames, options)
          {:ok, decoded, dropped, rest}
      end
    end
  end

  @impl true
  def encode(%LinkFrame{profile: :tm} = frame, opts) when is_list(opts) do
    with {:ok, options} <- normalize_options(opts),
         :ok <- validate_frame_size(options),
         :ok <- validate_frame_address(frame, options.configuration),
         {:ok, secondary_header} <- encode_secondary_header(frame, options),
         {:ok, ocf_flag, ocf} <- encode_ocf(frame, options),
         {:ok, status} <- encode_data_field_status(frame, options),
         :ok <- validate_data_field_length(frame.payload_octets, secondary_header, ocf, options),
         :ok <- validate_primary_fields(frame, status, ocf_flag) do
      encoded =
        <<
          0::2,
          frame.scid::10,
          frame.vcid::3,
          ocf_flag::1,
          status.mcfc::8,
          status.vcfc::8,
          status.secondary_header_flag::1,
          status.sync_flag::1,
          status.packet_order_flag::1,
          status.segment_length_id::2,
          status.fhp::11,
          secondary_header::binary,
          frame.payload_octets::binary,
          ocf::binary
        >>

      {:ok, maybe_append_fecf(encoded, options.fecf?)}
    end
  end

  def encode(%LinkFrame{profile: profile}, _opts), do: {:error, {:invalid_profile, profile}}
  def encode(_frame, _opts), do: {:error, :invalid_frame}

  defp normalize_options(opts) do
    case Keyword.get(opts, :configuration) do
      %Configuration{} = configuration ->
        with :ok <- Configuration.validate(configuration) do
          {:ok,
           %{
             frame_size: configuration.frame_size,
             secondary_header_length: configuration.secondary_header_length,
             ocf_length: if(Configuration.ocf?(configuration), do: @default_ocf_length, else: 0),
             fecf?: configuration.fecf?,
             timestamp: Keyword.get(opts, :timestamp),
             configuration: configuration
           }}
        end

      nil ->
        normalize_legacy_options(opts)

      value ->
        {:error, {:invalid_tm_configuration, value}}
    end
  end

  defp normalize_legacy_options(opts) do
    with {:ok, frame_size} <- Keyword.fetch(opts, :frame_size),
         secondary_header_length =
           Keyword.get(opts, :secondary_header_length, @default_secondary_header_length),
         ocf_length = Keyword.get(opts, :ocf_length, @default_ocf_length),
         fecf? = Keyword.get(opts, :fecf, false),
         :ok <- validate_non_negative(secondary_header_length, :secondary_header_length),
         :ok <- validate_non_negative(ocf_length, :ocf_length),
         :ok <- validate_fecf_presence(fecf?) do
      {:ok,
       %{
         frame_size: frame_size,
         secondary_header_length: secondary_header_length,
         ocf_length: ocf_length,
         fecf?: fecf?,
         timestamp: Keyword.get(opts, :timestamp),
         configuration: nil
       }}
    else
      :error -> {:error, {:missing_option, :frame_size}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_frame_size(%{frame_size: frame_size, fecf?: fecf?})
       when is_integer(frame_size) do
    minimum = @primary_header_size + fecf_length_bytes(fecf?) + 1

    if frame_size >= minimum,
      do: :ok,
      else: {:error, {:frame_size_too_small, frame_size, minimum}}
  end

  defp validate_frame_size(%{frame_size: frame_size}),
    do: {:error, {:invalid_frame_size, frame_size}}

  defp encode_secondary_header(frame, options) do
    value = Map.get(frame.meta, :secondary_header)
    data = Map.get(frame.meta, :secondary_header_data)

    with {:ok, header} <- normalize_secondary_header_value(value, data),
         {:ok, encoded} <- maybe_encode_secondary_header(header),
         :ok <- validate_secondary_header_presence(encoded, frame, options),
         :ok <- validate_secondary_header_length(encoded, options.secondary_header_length) do
      {:ok, encoded}
    end
  end

  defp normalize_secondary_header_value(nil, nil), do: {:ok, nil}
  defp normalize_secondary_header_value(%SecondaryHeader{} = header, nil), do: {:ok, header}

  defp normalize_secondary_header_value(nil, data) when is_binary(data),
    do: SecondaryHeader.new(data)

  defp normalize_secondary_header_value(value, nil) when is_binary(value),
    do: SecondaryHeader.new(value)

  defp normalize_secondary_header_value(value, data),
    do: {:error, {:invalid_secondary_header_values, value, data}}

  defp maybe_encode_secondary_header(nil), do: {:ok, <<>>}
  defp maybe_encode_secondary_header(header), do: SecondaryHeader.encode(header)

  defp validate_secondary_header_presence(encoded, frame, options) do
    present? = byte_size(encoded) > 0
    managed? = options.secondary_header_length > 0
    requested_flag = Map.get(frame.meta, :secondary_header_flag)

    with :ok <- validate_requested_secondary_header(requested_flag, present?) do
      validate_managed_secondary_header(present?, managed?)
    end
  end

  defp validate_requested_secondary_header(flag, _present?) when flag not in [nil, 0, 1],
    do: {:error, {:invalid_secondary_header_flag, flag}}

  defp validate_requested_secondary_header(1, false), do: {:error, :missing_secondary_header}

  defp validate_requested_secondary_header(0, true),
    do: {:error, :secondary_header_flag_mismatch}

  defp validate_requested_secondary_header(_flag, _present?), do: :ok

  defp validate_managed_secondary_header(false, true),
    do: {:error, :missing_managed_secondary_header}

  defp validate_managed_secondary_header(true, false), do: {:error, :unexpected_secondary_header}
  defp validate_managed_secondary_header(_present?, _managed?), do: :ok

  defp validate_secondary_header_length(<<>>, 0), do: :ok

  defp validate_secondary_header_length(encoded, expected) do
    actual = byte_size(encoded)

    if actual == expected,
      do: :ok,
      else: {:error, {:secondary_header_length_mismatch, actual, expected}}
  end

  defp encode_ocf(frame, %{configuration: %Configuration{} = configuration} = options) do
    if Configuration.ocf?(configuration) do
      normalize_present_ocf(frame.ocf, options.ocf_length)
    else
      normalize_absent_ocf(frame)
    end
  end

  defp encode_ocf(frame, options) do
    requested_flag = Map.get(frame.meta, :ocf_flag)

    cond do
      requested_flag not in [nil, 0, 1] ->
        {:error, {:invalid_ocf_flag, requested_flag}}

      requested_flag == 1 or (is_nil(requested_flag) and present_binary?(frame.ocf)) ->
        normalize_present_ocf(frame.ocf, options.ocf_length)

      true ->
        normalize_absent_ocf(frame)
    end
  end

  defp normalize_present_ocf(ocf, expected_length) when is_binary(ocf) do
    if byte_size(ocf) == expected_length and expected_length > 0 do
      {:ok, 1, ocf}
    else
      {:error, {:invalid_ocf_length, byte_size(ocf), expected_length}}
    end
  end

  defp normalize_present_ocf(_ocf, _expected_length), do: {:error, :missing_ocf}

  defp normalize_absent_ocf(%LinkFrame{ocf: ocf} = frame) do
    if present_binary?(ocf) or Map.get(frame.meta, :ocf_flag) == 1 do
      {:error, :unexpected_ocf}
    else
      {:ok, 0, <<>>}
    end
  end

  defp encode_data_field_status(frame, options) do
    sync_flag = managed_sync_flag(options.configuration, Map.get(frame.meta, :sync_flag, 0))
    status_fields = Map.get(frame.meta, :vca_status_fields)

    with :ok <- validate_bit(sync_flag, :sync_flag),
         {:ok, packet_order_flag, segment_length_id, fhp} <-
           normalize_status_fields(frame.meta, sync_flag, status_fields),
         :ok <- validate_status_fields(sync_flag, packet_order_flag, segment_length_id, fhp) do
      {:ok,
       %{
         mcfc: Map.get(frame.meta, :mcfc, 0),
         vcfc: Map.get(frame.meta, :vcfc, frame.frame_seq || 0),
         secondary_header_flag: if(options.secondary_header_length > 0, do: 1, else: 0),
         sync_flag: sync_flag,
         packet_order_flag: packet_order_flag,
         segment_length_id: segment_length_id,
         fhp: fhp
       }}
    end
  end

  defp managed_sync_flag(%Configuration{data_field_content: :packets}, _requested), do: 0
  defp managed_sync_flag(%Configuration{data_field_content: :vca_sdu}, _requested), do: 1
  defp managed_sync_flag(nil, requested), do: requested

  defp normalize_status_fields(_meta, 1, status_fields)
       when is_integer(status_fields) and status_fields in 0..0x3FFF do
    <<packet_order_flag::1, segment_length_id::2, fhp::11>> = <<status_fields::14>>
    {:ok, packet_order_flag, segment_length_id, fhp}
  end

  defp normalize_status_fields(meta, sync_flag, nil) do
    {:ok, Map.get(meta, :packet_order_flag, 0),
     Map.get(meta, :segment_length_id, default_segment_id(sync_flag)), Map.get(meta, :fhp, 0)}
  end

  defp normalize_status_fields(_meta, _sync_flag, value),
    do: {:error, {:invalid_vca_status_fields, value}}

  defp default_segment_id(0), do: 3
  defp default_segment_id(1), do: 0

  defp validate_status_fields(0, 0, 3, fhp) when fhp in 0..2047, do: :ok

  defp validate_status_fields(0, packet_order, _segment_id, _fhp) when packet_order != 0,
    do: {:error, :packet_order_flag_reserved}

  defp validate_status_fields(0, _packet_order, segment_id, _fhp),
    do: {:error, {:invalid_packet_segment_length_id, segment_id}}

  defp validate_status_fields(1, packet_order, segment_id, fhp)
       when packet_order in 0..1 and segment_id in 0..3 and fhp in 0..2047,
       do: :ok

  defp validate_status_fields(1, packet_order, segment_id, fhp),
    do: {:error, {:invalid_vca_status_fields, packet_order, segment_id, fhp}}

  defp validate_data_field_length(payload, secondary_header, ocf, options)
       when is_binary(payload) do
    expected =
      options.frame_size - @primary_header_size - byte_size(secondary_header) - byte_size(ocf) -
        fecf_length_bytes(options.fecf?)

    actual = byte_size(payload)
    if actual == expected, do: :ok, else: {:error, {:invalid_data_field_length, actual, expected}}
  end

  defp validate_data_field_length(payload, _secondary_header, _ocf, _options),
    do: {:error, {:invalid_data_field, payload}}

  defp validate_primary_fields(frame, status, ocf_flag) do
    with :ok <- validate_range(frame.scid, 0, 1023, :scid),
         :ok <- validate_range(frame.vcid, 0, 7, :vcid),
         :ok <- validate_bit(ocf_flag, :ocf_flag),
         :ok <- validate_range(status.mcfc, 0, 255, :mcfc) do
      validate_range(status.vcfc, 0, 255, :vcfc)
    end
  end

  defp split_frames(buffer, frame_size) do
    if byte_size(buffer) < frame_size do
      {:incomplete, buffer}
    else
      frame_count = div(byte_size(buffer), frame_size)
      total_size = frame_count * frame_size
      <<frames_bin::binary-size(^total_size), rest::binary>> = buffer
      frames = for <<frame::binary-size(^frame_size) <- frames_bin>>, do: frame
      {frames, rest}
    end
  end

  defp decode_frames(frames, options) do
    frames
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {frame, index}, {decoded, dropped} ->
      offset = index * options.frame_size

      case decode_frame(frame, options) do
        {:ok, decoded_frame} ->
          info = %{
            frame: decoded_frame,
            raw_frame_offset_bytes: offset,
            raw_frame_length_bytes: options.frame_size
          }

          {[info | decoded], dropped}

        {:drop, reason} ->
          anomaly = %{
            anomaly_kind: :frame_decode_dropped,
            raw_frame_offset_bytes: offset,
            raw_frame_length_bytes: options.frame_size,
            metadata: frame_decode_metadata(frame, reason)
          }

          {decoded, [anomaly | dropped]}
      end
    end)
    |> then(fn {decoded, dropped} -> {Enum.reverse(decoded), Enum.reverse(dropped)} end)
  end

  defp decode_frame(frame, options) do
    with {:ok, frame_without_fecf, fecf} <- validate_and_strip_fecf(frame, options.fecf?),
         {:ok, decoded} <- decode_frame_body(frame_without_fecf, options) do
      {:ok,
       %{
         decoded
         | meta: Map.merge(decoded.meta, %{fecf_present: options.fecf?, fecf: fecf})
       }}
    else
      {:error, reason} -> {:drop, reason}
      {:drop, reason} -> {:drop, reason}
    end
  end

  defp decode_frame_body(
         <<version::2, scid::10, vcid::3, ocf_flag::1, mcfc::8, vcfc::8, secondary_header_flag::1,
           sync_flag::1, packet_order_flag::1, segment_length_id::2, fhp::11, payload::binary>>,
         options
       ) do
    with :ok <- validate_version(version),
         :ok <- validate_decoded_address(scid, vcid, options.configuration),
         :ok <- validate_decoded_flags(ocf_flag, secondary_header_flag, sync_flag, options),
         :ok <- validate_status_fields(sync_flag, packet_order_flag, segment_length_id, fhp),
         {:ok, secondary_header, data_field, ocf} <-
           extract_fields(payload, secondary_header_flag, ocf_flag, options) do
      vca_status_fields =
        if sync_flag == 1,
          do: packet_order_flag * 8192 + segment_length_id * 2048 + fhp,
          else: nil

      meta =
        %{
          ocf_flag: ocf_flag,
          mcfc: mcfc,
          vcfc: vcfc,
          secondary_header_flag: secondary_header_flag,
          sync_flag: sync_flag,
          packet_order_flag: packet_order_flag,
          segment_length_id: segment_length_id,
          fhp: fhp,
          data_field_content: if(sync_flag == 0, do: :packets, else: :vca_sdu),
          vca_status_fields: vca_status_fields
        }
        |> maybe_put_secondary_header(secondary_header)

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
         timestamp: options.timestamp,
         meta: meta
       }}
    end
  end

  defp decode_frame_body(_frame, _options), do: {:drop, :invalid_frame}

  defp extract_fields(payload, secondary_header_flag, ocf_flag, options) do
    secondary_header_length =
      if(secondary_header_flag == 1, do: options.secondary_header_length, else: 0)

    ocf_length = if(ocf_flag == 1, do: options.ocf_length, else: 0)

    if byte_size(payload) < secondary_header_length + ocf_length + 1 do
      {:error, :frame_too_short}
    else
      <<secondary_header_bytes::binary-size(^secondary_header_length), rest::binary>> = payload
      data_length = byte_size(rest) - ocf_length
      <<data_field::binary-size(^data_length), ocf::binary-size(^ocf_length)>> = rest

      with {:ok, secondary_header} <- decode_secondary_header(secondary_header_bytes) do
        {:ok, secondary_header, data_field, empty_to_nil(ocf)}
      end
    end
  end

  defp decode_secondary_header(<<>>), do: {:ok, nil}
  defp decode_secondary_header(binary), do: SecondaryHeader.decode_exact(binary)

  defp maybe_put_secondary_header(meta, nil), do: meta

  defp maybe_put_secondary_header(meta, %SecondaryHeader{} = header) do
    meta
    |> Map.put(:secondary_header, header)
    |> Map.put(:secondary_header_data, header.data)
    |> Map.put(:secondary_header_length, SecondaryHeader.encoded_length(header))
  end

  defp validate_decoded_flags(ocf_flag, secondary_header_flag, sync_flag, options) do
    with :ok <- validate_bit(ocf_flag, :ocf_flag),
         :ok <- validate_bit(secondary_header_flag, :secondary_header_flag),
         :ok <- validate_bit(sync_flag, :sync_flag),
         :ok <- validate_managed_secondary_header_flag(secondary_header_flag, options),
         :ok <- validate_managed_ocf_flag(ocf_flag, options) do
      validate_managed_sync_flag(sync_flag, options.configuration)
    end
  end

  defp validate_managed_secondary_header_flag(flag, options) do
    expected = if(options.secondary_header_length > 0, do: 1, else: 0)

    if flag == expected,
      do: :ok,
      else: {:error, {:secondary_header_presence_mismatch, flag, expected}}
  end

  defp validate_managed_ocf_flag(_flag, %{configuration: nil}), do: :ok

  defp validate_managed_ocf_flag(flag, %{configuration: configuration}) do
    expected = if(Configuration.ocf?(configuration), do: 1, else: 0)
    if flag == expected, do: :ok, else: {:error, {:ocf_presence_mismatch, flag, expected}}
  end

  defp validate_managed_sync_flag(_flag, nil), do: :ok
  defp validate_managed_sync_flag(0, %Configuration{data_field_content: :packets}), do: :ok
  defp validate_managed_sync_flag(1, %Configuration{data_field_content: :vca_sdu}), do: :ok

  defp validate_managed_sync_flag(flag, configuration),
    do: {:error, {:data_field_content_mismatch, flag, configuration.data_field_content}}

  defp validate_frame_address(_frame, nil), do: :ok

  defp validate_frame_address(frame, configuration),
    do: validate_decoded_address(frame.scid, frame.vcid, configuration)

  defp validate_decoded_address(_scid, _vcid, nil), do: :ok

  defp validate_decoded_address(scid, vcid, %Configuration{} = configuration) do
    if Configuration.matches?(configuration, scid, vcid),
      do: :ok,
      else: {:error, {:managed_channel_mismatch, scid, vcid}}
  end

  defp frame_decode_metadata(
         <<version::2, scid::10, vcid::3, ocf_flag::1, mcfc::8, vcfc::8, secondary_header_flag::1,
           sync_flag::1, packet_order_flag::1, segment_length_id::2, fhp::11, _rest::binary>>,
         reason
       ) do
    %{
      reason: reason,
      version: version,
      scid: scid,
      vcid: vcid,
      ocf_flag: ocf_flag,
      mcfc: mcfc,
      vcfc: vcfc,
      secondary_header_flag: secondary_header_flag,
      sync_flag: sync_flag,
      packet_order_flag: packet_order_flag,
      segment_length_id: segment_length_id,
      first_header_pointer: fhp
    }
  end

  defp frame_decode_metadata(_frame, reason), do: %{reason: reason}

  defp validate_and_strip_fecf(frame, true), do: FrameErrorControl.validate_and_strip(frame)
  defp validate_and_strip_fecf(frame, false), do: {:ok, frame, nil}

  defp maybe_append_fecf(frame, true), do: FrameErrorControl.append(frame)
  defp maybe_append_fecf(frame, false), do: frame

  defp fecf_length_bytes(true), do: FrameErrorControl.size()
  defp fecf_length_bytes(false), do: 0

  defp validate_fecf_presence(value) when is_boolean(value), do: :ok
  defp validate_fecf_presence(value), do: {:error, {:invalid_fecf_presence, value}}

  defp validate_version(0), do: :ok
  defp validate_version(version), do: {:error, {:unsupported_version, version}}

  defp validate_bit(value, _field) when value in 0..1, do: :ok
  defp validate_bit(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_non_negative(value, _field) when is_integer(value) and value >= 0, do: :ok
  defp validate_non_negative(value, field), do: {:error, {:invalid_field, field, value}}

  defp present_binary?(value), do: is_binary(value) and byte_size(value) > 0
  defp empty_to_nil(<<>>), do: nil
  defp empty_to_nil(binary), do: binary
end
